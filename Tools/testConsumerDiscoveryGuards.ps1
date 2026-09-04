<#
.SYNOPSIS
Checks Canvas guard/lifecycle source contracts and deliberate unsafe mutations, not Papyrus VM behavior.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-GuardPattern {
  param([string]$Text, [string]$Pattern, [string]$Contract)
  if (![regex]::IsMatch($Text, $Pattern)) { throw "Guard contract: $Contract" }
}

function Get-GuardFunctions {
  param([hashtable]$Sources)
  $functions = @{}
  foreach ($scriptName in $Sources.Keys) {
    foreach ($match in [regex]::Matches($Sources[$scriptName], '(?m)^(?:[\w:]+(?:\[\])?\s+)?(?:Function|Event)\s+(\w+)\([^\r\n]*\)[^\r\n]*\r?\n(?<body>[\s\S]*?)^End(?:Function|Event)')) {
      $functions["$scriptName.$($match.Groups[1].Value)"] = $match.Groups['body'].Value
    }
  }
  return $functions
}

function Assert-GuardCallTree {
  param([hashtable]$Functions, [string]$ScriptName, [string]$Body, [hashtable]$Visited, [switch]$Initialization)
  # Ignore comments and string contents when traversing calls; prose is not executable behavior.
  $code = [regex]::Replace($Body, '(?m);[^\r\n]*', '')
  $code = [regex]::Replace($code, '"[^"]*"', '""')
  if ($Initialization) {
    if ($code -match '(?im)^\s*(?:Try)?LockGuard\b') { throw 'OnInit reaches a guard.' }
  }
  elseif ($code -match '\b(?:Log\w*|ReportAttempt|StartTimer|CancelTimer|RegisterFor\w+|UnregisterFor\w+|Wait\w*)\s*\(') {
    throw 'A guard reaches logging, scheduling, subscriptions or a wait.'
  }
  foreach ($call in [regex]::Matches($code, '(?<![\w:])(?:(\w+)\.)?(\w+)\s*\(')) {
    $receiver = $call.Groups[1].Value
    $name = $call.Groups[2].Value
    $targetScript = $ScriptName
    if ($receiver -eq 'Registry') { $targetScript = 'Registry' }
    elseif ($receiver -eq 'Registrar') { $targetScript = 'ConsumerARegistrar' }
    elseif ($receiver -ne '' -and $receiver -ne 'Self') { continue }
    $target = "$targetScript.$name"
    if (!$Functions.ContainsKey($target) -and $receiver -eq '') { $target = "Registry.$name" }
    if ($Functions.ContainsKey($target) -and !$Visited.ContainsKey($target)) {
      $Visited[$target] = $true
      Assert-GuardCallTree -Functions $Functions -ScriptName $target.Split('.')[0] -Body $Functions[$target] -Visited $Visited -Initialization:$Initialization
    }
  }
}

function Assert-CanvasGuardContract {
  param([hashtable]$Sources)
  $functions = Get-GuardFunctions -Sources $Sources
  foreach ($scriptName in $Sources.Keys) {
    $source = $Sources[$scriptName]
    if ($source -match '(?im)^\s*LockGuard\b' -or $source -match '\bUtility\.Wait\w*\s*\(') {
      throw "$scriptName contains a blocking acquisition or wait."
    }
    if ($source -match '(?m)^\s*(?:If|ElseIf|While)\s*\([^\r\n]*RegistrationAttemptActive') {
      throw 'Saved in-flight state is being used as a permanent gate.'
    }
    Assert-GuardCallTree -Functions $functions -ScriptName $scriptName -Body $functions["$scriptName.OnInit"] -Visited @{} -Initialization
    Assert-GuardPattern $source '(?s)Event OnTimer\(Int aiTimerID\).*?aiTimerID.*?20' "$scriptName has a bounded timer entry point"
    foreach ($block in [regex]::Matches($source, '(?m)^\s*TryLockGuard\s+\w+\s*\r?\n(?<body>[\s\S]*?)^\s*EndTryLockGuard')) {
      if ($block.Groups['body'].Value -match '(?im)^\s*Return\b') { throw 'Return exits a guard body.' }
      Assert-GuardCallTree -Functions $functions -ScriptName $scriptName -Body $block.Groups['body'].Value -Visited @{}
    }
    $startCount = [regex]::Matches($source, '(?m)^\s*TryLockGuard\b').Count
    if ($startCount -ne [regex]::Matches($source, '(?m)^\s*EndTryLockGuard\b').Count) { throw 'Unbalanced try guard blocks.' }
  }
  $registry = $Sources.Registry
  foreach ($operation in @('TryRegisterConsumer', 'TryUnregisterConsumer', 'TryRequestUiLoad', 'TryEnsureStorage', 'TryMigrateConsumerIdentity')) {
    Assert-GuardPattern $functions["Registry.$operation"] '(?s)NewResult\("DEFERRED_REGISTRY_BUSY"\).*?TryLockGuard RegistryGuard.*?EndTryLockGuard\s+Return result' "$operation keeps busy distinct and returns after release"
  }
  Assert-GuardPattern $functions['Registry.TryRegisterConsumer'] '(?s)GetDescriptorRejectionReason.*?TryLockGuard RegistryGuard.*?MigrateConsumerIdentityLocked.*?RegisterConsumerLocked.*?EndTryLockGuard' 'rekey and registration share one transaction after validation'
  Assert-GuardPattern $registry '(?s)If \(Consumers == None\)\s+Consumers = new ConsumerRegistration\[0\]' 'only missing storage is initialized'
  if ([regex]::Matches($registry, 'Consumers = new ConsumerRegistration\[0\]').Count -ne 1) { throw 'Valid saved storage may be replaced.' }
  Assert-GuardPattern $registry 'Int Count = -1' 'busy count is not zero'
  Assert-GuardPattern $functions['Registry.FindConsumerIndex'] 'Int index = -2' 'busy lookup is not absent'
  Assert-GuardPattern $functions['Registry.IsDeferred'] 'DEFERRED_REGISTRY_BUSY.*DEFERRED_ATTEMPT_BUSY.*DEFERRED_REGISTRY_UNAVAILABLE' 'all transient outcomes are recognized'
  foreach ($scriptName in @('ConsumerARegistrar', 'ConsumerBRegistrar')) {
    $attempt = $functions["$scriptName.AttemptDescriptorRegistration"]
    Assert-GuardPattern $attempt '(?s)If \(IsDeferred\(result.Status\)\)\s+Return result\s+EndIf\s+If \(IsRegistrationAccepted\(result.Status\)\)\s+If \(expectedResult\)\s+OperationResult loadResult = Registry.TryRequestUiLoad' "$scriptName handles busy before negative tests and requests UI only after acceptance"
    Assert-GuardPattern $functions["$scriptName.TryReconcile"] '(?s)Registry.EnsureMenuSubscriptions\(\).*?NewResult\("DEFERRED_ATTEMPT_BUSY"\).*?TryLockGuard AttemptGuard.*?EndTryLockGuard\s+Return result' "$scriptName subscribes before acquiring and preserves a skipped result"
    Assert-GuardPattern $functions["$scriptName.ProcessAttempt"] '(?s)TryReconcile\(\).*?ReportAttempt\(result\).*?If \(IsDeferred\(result.Status\) \|\| IsDeferred\(result.UiLoad\)\).*?If \(attempt < 20\).*?StartTimer\(0.5, attempt \+ 1\)' "$scriptName retries only deferred outcomes, after its attempt"
    if ($functions["$scriptName.ResolveRegistrationId"] -match 'Registry\.(?:Try)?Migrate') { throw 'Identity resolution conflates host outcome with UUID validity.' }
    Assert-GuardPattern $functions["$scriptName.ReportAttempt"] '(?s)If \(IsRegistrationAccepted\(result.Status\)\)\s+LogUserInformational[^\r\n]*REGISTRATION_ACK' "$scriptName ACK requires acceptance"
  }
  Assert-GuardPattern $functions['ConsumerARegistrar.TryApplyDescriptorUpdate'] '(?s)TryLockGuard AttemptGuard.*?PendingDisplayName = updatedDisplayName.*?PendingLargeMovieUrl = updatedLargeMovieUrl.*?PendingDescriptorVersion = updatedDescriptorVersion.*?PendingUpdate = True\s+result = ApplyPendingUpdateLocked\(\).*?EndTryLockGuard' 'pending data is stored as one guarded request before attempting it'
  Assert-GuardPattern $functions['ConsumerARegistrar.ApplyPendingUpdateLocked'] '(?s)If \(IsRegistrationAccepted\(result.Status\)\).*?ActiveDisplayName = PendingDisplayName.*?PendingUpdate = False.*?ElseIf \(!IsDeferred\(result.Status\)\)\s+PendingUpdate = False' 'busy preserves pending work; acceptance alone commits active data'
  $migration = $functions['ConsumerAUpdateMigration.OnTimer']
  Assert-GuardPattern $migration '(?s)Registrar.TryApplyDescriptorUpdate\(UpdatedDisplayName, UpdatedNormalMoviePath, UpdatedLargeMoviePath, UpdatedDescriptorVersion\).*?If \(IsRegistrationAccepted\(result.Status\)\)\s+MigrationApplied = True.*?ElseIf \(IsDeferred\(result.Status\)\).*?If \(aiTimerID < 20\).*?StartTimer\(0.5, aiTimerID \+ 1\)' 'migration retains and resubmits VMAD input until accepted'
}

$sourceRoot = Join-Path $PSScriptRoot '../Papyrus/Venworks/Canvas/Probes/ConsumerDiscovery'
$sources = @{}
foreach ($name in @('Registry', 'ConsumerARegistrar', 'ConsumerBRegistrar', 'ConsumerAUpdateMigration')) {
  $sources[$name] = Get-Content -LiteralPath (Join-Path $sourceRoot "$name.psc") -Raw
}
Assert-CanvasGuardContract -Sources $sources
$lineBreak = [Environment]::NewLine
$mutations = @(
  @{ File = 'Registry'; From = 'TryLockGuard RegistryGuard'; To = 'LockGuard RegistryGuard' }
  @{ File = 'Registry'; From = '    EnsureStorageLocked(result)'; To = ('    Return result' + $lineBreak + '    EnsureStorageLocked(result)') }
  @{ File = 'Registry'; From = '  Int index = Consumers.Length - 1'; To = ('  Utility.WaitMenuPause(0.5)' + $lineBreak + '  Int index = Consumers.Length - 1') }
  @{ File = 'Registry'; From = '  Int index = Consumers.Length - 1'; To = ('  LogUserWarning(ModuleName, "Unsafe", "Inside worker")' + $lineBreak + '  Int index = Consumers.Length - 1') }
  @{ File = 'Registry'; From = '  Int index = Consumers.Length - 1'; To = ('  StartTimer(0.5, 1)' + $lineBreak + '  Int index = Consumers.Length - 1') }
  @{ File = 'Registry'; From = '  Int index = Consumers.Length - 1'; To = ('  EnsureMenuSubscriptions()' + $lineBreak + '  Int index = Consumers.Length - 1') }
  @{ File = 'Registry'; From = '  EnsureMenuSubscriptions()'; To = ('  EnsureStorage()' + $lineBreak + '  EnsureMenuSubscriptions()') }
  @{ File = 'Registry'; From = 'Int Count = -1'; To = 'Int Count = 0' }
  @{ File = 'Registry'; From = 'Int index = -2'; To = 'Int index = -1' }
  @{ File = 'Registry'; From = 'NewResult("DEFERRED_REGISTRY_BUSY")'; To = 'NewResult("REGISTRATION_REJECTED")' }
  @{ File = 'Registry'; From = 'If (Consumers == None)'; To = 'If (True)' }
  @{ File = 'ConsumerARegistrar'; From = 'ElseIf (!IsDeferred(result.Status))'; To = 'Else' }
  @{ File = 'ConsumerARegistrar'; From = 'If (IsRegistrationAccepted(result.Status))'; To = 'If (True)' }
  @{ File = 'ConsumerARegistrar'; From = 'If (IsDeferred(result.Status))'; To = 'If (False)' }
  @{ File = 'ConsumerBRegistrar'; From = 'If (expectedResult)'; To = 'If (True)' }
  @{ File = 'ConsumerBRegistrar'; From = 'If (IsDeferred(result.Status))'; To = 'If (False)' }
  @{ File = 'ConsumerBRegistrar'; From = 'NewResult("DEFERRED_ATTEMPT_BUSY")'; To = 'NewResult("EXPECTED_REGISTRATION_REJECTION")' }
  @{ File = 'ConsumerBRegistrar'; From = 'If (opening)'; To = 'If (opening && !RegistrationAttemptActive)' }
  @{ File = 'ConsumerARegistrar'; From = 'If (attempt < 20)'; To = 'If (True)' }
  @{ File = 'ConsumerAUpdateMigration'; From = 'If (aiTimerID < 20)'; To = 'If (True)' }
  @{ File = 'ConsumerAUpdateMigration'; From = 'If (IsRegistrationAccepted(result.Status))'; To = 'If (True)' }
  @{ File = 'ConsumerAUpdateMigration'; From = '  RegisterForMenuOpenCloseEvent("HUDMenu")'; To = ('  Registrar.RegisterWithRetry()' + $lineBreak + '  RegisterForMenuOpenCloseEvent("HUDMenu")') }
)
$rejected = 0
foreach ($mutation in $mutations) {
  $candidate = @{} + $sources
  if (!$candidate[$mutation.File].Contains($mutation.From)) { throw "Mutation did not match: $($mutation.From)" }
  $candidate[$mutation.File] = $candidate[$mutation.File].Replace($mutation.From, $mutation.To)
  $caught = $false
  try { Assert-CanvasGuardContract -Sources $candidate } catch { $caught = $true }
  if (!$caught) { throw "Unsafe mutation was accepted: $($mutation.From)" }
  $rejected += 1
}
Write-Output "Guard source/call-tree contracts passed; $rejected unsafe mutations rejected. No Papyrus VM/runtime acceptance is implied."
