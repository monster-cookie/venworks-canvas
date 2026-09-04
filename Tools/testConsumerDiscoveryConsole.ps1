<#
.SYNOPSIS
Checks global console entry points, local record mappings and documentation; does not execute the Papyrus VM.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-ConsolePattern {
  param([string]$Text, [string]$Pattern, [string]$Contract)
  if (![regex]::IsMatch($Text, $Pattern)) { throw "Console contract: $Contract" }
}

function Get-ConsoleFunctions {
  param([string]$Source)
  $functions = @{}
  foreach ($match in [regex]::Matches($Source, '(?m)^(?:[\w:]+\s+)?Function\s+(?<name>\w+)\((?<parameters>[^\r\n]*)\)(?<flags>[^\r\n]*)\r?\n(?<body>[\s\S]*?)^EndFunction')) {
    $functions[$match.Groups['name'].Value] = @{
      Parameters = $match.Groups['parameters'].Value
      Flags = $match.Groups['flags'].Value
      Body = $match.Groups['body'].Value
    }
  }
  return $functions
}

function Assert-CanvasConsoleContract {
  param([hashtable]$Sources, [string]$Readme, [object[]]$Definitions)
  $prefix = 'Venworks:Canvas:Probes:ConsumerDiscovery:'
  foreach ($definition in $Definitions) {
    $name = [string]$definition.Script
    $functions = Get-ConsoleFunctions -Source $Sources[$name]
    $resolver = 'ResolveConsole' + $definition.Suffix
    $logger = 'LogConsole' + $definition.Suffix
    $action = [string]$definition.Action
    foreach ($functionName in @('ConsoleResolve', $action, $resolver, $logger)) {
      if (!$functions.ContainsKey($functionName)) { throw "Missing $name.$functionName" }
      Assert-ConsolePattern $functions[$functionName].Flags '^\s+Global\s*$' "$name.$functionName is a callable global, not an instance/protected/beta-only method"
    }
    if ($functions.ConsoleResolve.Parameters -ne '' -or $functions[$resolver].Parameters -ne '' -or
        $functions[$action].Parameters -cne [string]$definition.Parameters) { throw "$name console signature changed." }

    $body = $functions[$resolver].Body
    $type = [regex]::Escape($prefix + $name)
    $lookup = 'Form targetForm = Game.GetFormFromFile(0x' + $definition.LocalId + ', "' + $definition.Plugin + '")'
    Assert-ConsolePattern $body ([regex]::Escape($lookup)) "$name uses its permanent plugin and file-local ID"
    Assert-ConsolePattern $body '(?s)If \(targetForm == None\).*?CONSOLE_TARGET_NOT_FOUND.*?Return None\s+EndIf' "$name rejects a missing form before casting"
    Assert-ConsolePattern $body ('(?s)' + $type + ' target = targetForm as ' + $type + '\s+If \(target == None\).*?CONSOLE_SCRIPT_NOT_BOUND.*?Return None\s+EndIf') "$name validates the attached script before returning it"
    Assert-ConsolePattern $body ('(?s)' + $logger + '\("' + $resolver + '", "CONSOLE_BEGIN.*?GetFormFromFile.*?CONSOLE_RESOLVED.*?targetForm.GetFormID\(\).*?Return target') "$name exposes invocation and runtime binding separately"
    if ([regex]::Matches($body, 'Game.GetFormFromFile\(').Count -ne 1) { throw "$name has an unexpected fallback lookup." }
    foreach ($functionName in @('ConsoleResolve', $action)) {
      Assert-ConsolePattern $functions[$functionName].Body ('(?s)target = ' + $resolver + '\(\)\s+If \(target == None\)\s+Venworks:Core:Utilities:Console\.ConsoleEcho\([^\r\n]*\)\s+Return "CONSOLE_RESOLVE_FAILED"\s+EndIf') "$name.$functionName prints and stops on resolution failure"
      $entryBody = $functions[$functionName].Body
      $returns = @([regex]::Matches($entryBody, '(?m)^\s*Return ([^\r\n]+)'))
      if ($returns.Count -ne 2 -or [regex]::Matches($entryBody, 'Venworks:Core:Utilities:Console\.ConsoleEcho\(').Count -ne 2) {
        throw "$name.$functionName must echo exactly once on each of its two return paths."
      }
      foreach ($returnLine in $returns) {
        $value = $returnLine.Groups[1].Value
        $echo = 'Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ' + $name + '.' + $functionName + ' | " + ' + $value + ')'
        Assert-ConsolePattern $entryBody ([regex]::Escape($echo) + '\s+Return ' + [regex]::Escape($value)) "$name.$functionName echoes the same result it returns with the caller-owned label"
      }
    }
    Assert-ConsolePattern $functions.ConsoleResolve.Body '(?s)EndIf\s+Venworks:Core:Utilities:Console\.ConsoleEcho\([^\r\n]*\)\s+Return "CONSOLE_RESOLVED"\s*$' "$name resolution only echoes its result after lookup"
    Assert-ConsolePattern $functions[$logger].Body 'Venworks:Core:Logging.LogUser\(' "$name uses existing shared logging"
    Assert-ConsolePattern $functions[$logger].Body 'VWCANVAS_CONSOLE/1 \| ' "$name emits the packaged diagnostic marker"

    foreach ($functionName in @('ConsoleResolve', $resolver, $logger, $action)) {
      $code = [regex]::Replace($functions[$functionName].Body, '"[^"\r\n]*"|(?m);[^\r\n]*', '')
      if ($code -match '\b(?:TryLockGuard|LockGuard|While|StartTimer|CancelTimer|Wait\w*)\b' -or
          $code -match '\b(?:RegisterConsumer|TryRegisterConsumer|RegisterWithRetry|AttemptRegistration|GenerateV4)\s*\(') {
        throw "$name.$functionName introduced a guard, registration, generation or retry loop."
      }
      if ($functionName -ne $action -and $code -match '\b(?:EnsureStorage|TryEnsureStorage|EnsureMenuSubscriptions|RetryUpdate|RequestUiLoad|CheckUiLoadRequest)\s*\(') {
        throw "$name.$functionName does work during a resolution-only call."
      }
    }
    if ($name -eq 'ConsumerBRegistrar') {
      Assert-ConsolePattern $functions[$action].Body '(?s)String result = target.CheckUiLoadRequest\(requestedConsumerId\).*?CONSOLE_RESULT.*?Return result' 'B passes unchanged input through its instance method and returns the actual result'
      Assert-ConsolePattern $functions.CheckUiLoadRequest.Body 'Registry.CheckUiLoadRequest\(Self, requestedConsumerId\)' 'B remains the owner of the check-only UI request'
      if ($functions[$action].Body -match '\b(?:Normalize|Trim|ToLower|TryRequestUiLoad|RequestUiLoad)\(') { throw 'The B wrapper bypasses the instance path or changes test input.' }
    }
    elseif ($name -eq 'Registry') {
      Assert-ConsolePattern $functions[$action].Body '(?s)target.EnsureMenuSubscriptions\(\)\s+OperationResult result = target.TryEnsureStorage\(\)\s+target.LogOperation\(result\).*?Return result.Status' 'host recovery preserves its detailed busy result and logs outside the guard'
    }
    else {
      Assert-ConsolePattern $functions[$action].Body '(?s)target.RetryUpdate\(\).*?Return "CONSOLE_RETRY_REQUESTED"' 'migration only dispatches the existing recovery method'
      if ($functions[$action].Body -match 'MigrationApplied\s*=|DESCRIPTOR_UPDATE_ACK \| Version=') { throw 'Migration console dispatch pretends an update was applied.' }
    }
    foreach ($functionName in @('ConsoleResolve', $action)) {
      $command = 'cgf "' + $prefix + $name + '.' + $functionName + '"'
      if (!$Readme.Contains($command)) { throw "README is missing $command" }
    }
  }
  if ($Readme -match '\bcqf\b') { throw 'README still directs users to a quest-function console path.' }
  foreach ($command in [regex]::Matches($Readme, 'cgf "Venworks:Canvas:Probes:ConsumerDiscovery:(\w+)\.(\w+)"')) {
    $scriptName = $command.Groups[1].Value
    $functionName = $command.Groups[2].Value
    if (!$Sources.ContainsKey($scriptName)) { throw "Unknown documented console script: $scriptName" }
    $functions = Get-ConsoleFunctions -Source $Sources[$scriptName]
    if (!$functions.ContainsKey($functionName)) { throw "Unknown documented console function: $functionName" }
    Assert-ConsolePattern $functions[$functionName].Flags '^\s+Global\s*$' 'each documented Canvas console command targets a real global'
  }
  Assert-ConsolePattern $Readme 'help "VWCANVAS9_ConsumerBRegistrar" 4 QUST' 'optional quest help searches the Editor ID, not the display title'
}

$definitions = @(
  @{ Script = 'Registry'; Suffix = 'Registry'; Plugin = 'Venworks-Canvas-Host.esm'; LocalId = '000800'; Action = 'ConsoleEnsureStorage'; Parameters = '' }
  @{ Script = 'ConsumerBRegistrar'; Suffix = 'ConsumerB'; Plugin = 'Venworks-Canvas-ConsumerB.esm'; LocalId = '000800'; Action = 'ConsoleCheckUiLoadRequest'; Parameters = 'String requestedConsumerId' }
  @{ Script = 'ConsumerAUpdateMigration'; Suffix = 'Migration'; Plugin = 'Venworks-Canvas-ConsumerA.esm'; LocalId = '000801'; Action = 'ConsoleRetryUpdate'; Parameters = '' }
)
$sourceRoot = Join-Path $PSScriptRoot '../Papyrus/Venworks/Canvas/Probes/ConsumerDiscovery'
$sources = @{}
foreach ($definition in $definitions) {
  $sources[$definition.Script] = Get-Content -LiteralPath (Join-Path $sourceRoot ($definition.Script + '.psc')) -Raw
}
$readme = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../README.md') -Raw
Assert-CanvasConsoleContract -Sources $sources -Readme $readme -Definitions $definitions
$mutations = @(
  @{ Script = 'ConsumerBRegistrar'; From = 'Venworks:Core:Utilities:Console.ConsoleEcho('; To = 'Venworks:Core:Logging.ConsoleEcho(' }
  @{ Script = 'Registry'; From = '"VWCANVAS: Registry.ConsoleEnsureStorage | "'; To = '"VWCORE: Registry.ConsoleEnsureStorage | "' }
  @{ Script = 'ConsumerAUpdateMigration'; From = '"VWCANVAS: ConsumerAUpdateMigration.ConsoleRetryUpdate | " + "CONSOLE_RETRY_REQUESTED"'; To = '"VWCANVAS: ConsumerAUpdateMigration.ConsoleRetryUpdate | " + "DESCRIPTOR_UPDATE_ACK"' }
  @{ Script = 'ConsumerBRegistrar'; From = 'ConsoleCheckUiLoadRequest(String requestedConsumerId) Global'; To = 'ConsoleCheckUiLoadRequest(String requestedConsumerId)' }
  @{ Script = 'Registry'; From = 'ConsoleResolve() Global'; To = 'ConsoleResolve() Global Protected' }
  @{ Script = 'Registry'; From = 'Game.GetFormFromFile(0x000800,'; To = 'Game.GetFormFromFile(0xFE004800,' }
  @{ Script = 'ConsumerBRegistrar'; From = '"Venworks-Canvas-ConsumerB.esm"'; To = '"Venworks-Canvas-ConsumerA.esm"' }
  @{ Script = 'ConsumerAUpdateMigration'; From = 'Game.GetFormFromFile(0x000801,'; To = 'Game.GetFormFromFile(0x000800,' }
  @{ Script = 'Registry'; From = 'If (targetForm == None)'; To = 'If (False)' }
  @{ Script = 'ConsumerBRegistrar'; From = 'If (target == None)'; To = 'If (False)' }
  @{ Script = 'ConsumerBRegistrar'; From = 'target.CheckUiLoadRequest(requestedConsumerId)'; To = 'target.CheckUiLoadRequest("beef70b2-024e-4e9b-a8d5-70a0c882c431")' }
  @{ Script = 'ConsumerBRegistrar'; From = 'Registry.CheckUiLoadRequest(Self, requestedConsumerId)'; To = 'Registry.CheckUiLoadRequest(Registry, requestedConsumerId)' }
  @{ Script = 'ConsumerBRegistrar'; From = 'Registry.CheckUiLoadRequest(Self, requestedConsumerId)'; To = 'Registry.RequestUiLoad(Self, requestedConsumerId)' }
  @{ Script = 'ConsumerBRegistrar'; From = 'Return result'; To = 'Return "REGISTERED_TRANSPORT_DISABLED"' }
  @{ Script = 'Registry'; From = 'target.LogOperation(result)'; To = '; omitted' }
  @{ Script = 'ConsumerAUpdateMigration'; From = 'target.RetryUpdate()'; To = 'target.OnInit()' }
  @{ Script = 'ConsumerAUpdateMigration'; From = 'Return "CONSOLE_RETRY_REQUESTED"'; To = 'Return "DESCRIPTOR_UPDATE_ACK"' }
  @{ Script = 'ConsumerBRegistrar'; From = 'Return "CONSOLE_RESOLVED"'; To = ('target.RegisterWithRetry()' + [Environment]::NewLine + '  Return "CONSOLE_RESOLVED"') }
  @{ Script = 'Registry'; From = 'VWCANVAS_CONSOLE/1'; To = 'old-build' }
  @{ Script = 'README'; From = '.ConsoleCheckUiLoadRequest"'; To = '.CheckUiLoadRequest"' }
  @{ Script = 'README'; From = 'help "VWCANVAS9_ConsumerBRegistrar"'; To = 'help "VWCANVAS-9 Consumer B Registrar"' }
)
$rejected = 0
foreach ($mutation in $mutations) {
  $candidate = @{} + $sources
  $candidateReadme = $readme
  $original = if ($mutation.Script -eq 'README') { $readme } else { $candidate[$mutation.Script] }
  if (!$original.Contains($mutation.From)) { throw "Mutation did not match: $($mutation.From)" }
  $changed = $original.Replace($mutation.From, $mutation.To)
  if ($mutation.Script -eq 'README') { $candidateReadme = $changed } else { $candidate[$mutation.Script] = $changed }
  $caught = $false
  try { Assert-CanvasConsoleContract -Sources $candidate -Readme $candidateReadme -Definitions $definitions } catch { $caught = $true }
  if (!$caught) { throw "Invalid console contract was accepted: $($mutation.From)" }
  $rejected += 1
}
Write-Output "Console source/documentation contracts passed; $rejected invalid mutations rejected. No console invocation or runtime lookup acceptance is implied."
