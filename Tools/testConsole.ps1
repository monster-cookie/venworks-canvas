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

function Get-ActionScriptFunctionBody {
  param([string]$Source, [string]$Name)
  $pattern = '(?ms)^      public function ' + [regex]::Escape($Name) + '\([^\r\n]*\) : void\s*\r?\n      \{\r?\n(?<body>.*?)^      \}'
  $match = [regex]::Match($Source, $pattern)
  if (!$match.Success) { throw "Missing CanvasExample.$Name" }
  return $match.Groups['body'].Value
}

function Assert-ExamplePingUiContract {
  param([string]$Source)
  Assert-ConsolePattern $Source '(?m)^      private var pingReceived:Boolean;\s*$' 'Example owns one movie-lifetime ping receipt state'
  $uiData = Get-ActionScriptFunctionBody -Source $Source -Name 'handleUIData'
  $canvasEvent = Get-ActionScriptFunctionBody -Source $Source -Name 'handleCanvasEvent'
  $lifecycle = Get-ActionScriptFunctionBody -Source $Source -Name 'handleLifecycle'
  Assert-ConsolePattern $canvasEvent '(?s)if\(this\.marker != null && param1 == "venworks\.canvas\.example\.ping"\).*?this\.pingReceived = true;\s+this\.marker\.text = "pong";' 'only the exact ping topic records and displays lowercase pong'
  Assert-ConsolePattern $uiData 'if\(this\.marker != null && !this\.pingReceived && param1 == "PlayerData"\)' 'later PlayerData callbacks preserve pong'
  Assert-ConsolePattern $lifecycle 'if\(this\.marker != null && !this\.pingReceived && param1 == "ready"\)' 'later lifecycle callbacks preserve pong'
  if ([regex]::Matches($Source, 'this\.pingReceived\s*=\s*true;').Count -ne 1 -or
      [regex]::Matches($Source, 'this\.marker\.text\s*=\s*"pong";').Count -ne 1) {
    throw 'CanvasExample must set ping receipt state and lowercase pong only in its exact event callback.'
  }
}

function Assert-CanvasConsoleContract {
  param([hashtable]$Sources, [string]$Readme, [object[]]$Definitions)
  foreach ($definition in $Definitions) {
    $name = [string]$definition.Script
    $qualifiedScriptName = [string]$definition.ScriptName
    $functions = Get-ConsoleFunctions -Source $Sources[$name]
    Assert-ConsolePattern $Sources[$name] ('(?m)^ScriptName ' + [regex]::Escape($qualifiedScriptName) + '\s') "$name declares its package-owned namespace"
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
    $type = [regex]::Escape($qualifiedScriptName)
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
    if ($name -eq 'ComponentGalleryRegistrar') {
      Assert-ConsolePattern $functions[$action].Body '(?s)String result = target.CheckUiLoadRequest\(requestedConsumerId\).*?CONSOLE_RESULT.*?Return result' 'B passes unchanged input through its instance method and returns the actual result'
      Assert-ConsolePattern $functions.CheckUiLoadRequest.Body 'Registry.CheckUiLoadRequest\(Self, requestedConsumerId\)' 'B remains the owner of the check-only UI request'
      if ($functions[$action].Body -match '\b(?:Normalize|Trim|ToLower|TryRequestUiLoad|RequestUiLoad)\(') { throw 'The B wrapper bypasses the instance path or changes test input.' }
    }
    elseif ($name -eq 'Registry') {
      Assert-ConsolePattern $functions[$action].Body '(?s)target.EnsureMenuSubscriptions\(\)\s+OperationResult result = target.TryEnsureStorage\(\)\s+target.LogOperation\(result\).*?Return result.Status' 'host recovery preserves its detailed busy result and logs outside the guard'
    }
    elseif ($name -eq 'ExampleRegistrar') {
      if (!$functions.ContainsKey('PublishConsolePing')) { throw 'Missing ExampleRegistrar.PublishConsolePing' }
      Assert-ConsolePattern $functions[$action].Body '(?s)String result = target.PublishConsolePing\(\).*?CONSOLE_RESULT \| Status=.*?Return result' 'Example console action returns the actual publish result'
      Assert-ConsolePattern $functions.PublishConsolePing.Body '(?s)If \(Registry == None\).*?Return "DEFERRED_REGISTRY_UNAVAILABLE"\s+EndIf\s+OperationResult result = Registry.TryPublishCanvasEvent\("venworks\.canvas\.example\.ping", "ping"\)\s+Registry.LogOperation\(result\)\s+Return result.Status' 'Example publishes one fixed ping and preserves the registry receipt'
      $publishCode = [regex]::Replace($functions.PublishConsolePing.Body, '"[^"\r\n]*"|(?m);[^\r\n]*', '')
      if ($publishCode -match '\b(?:TryLockGuard|LockGuard|While|StartTimer|CancelTimer|Wait\w*|RegisterConsumer|TryRegisterConsumer|RegisterWithRetry|AttemptRegistration|RequestUiLoad|TryRequestUiLoad)\b') {
        throw 'ExampleRegistrar.PublishConsolePing introduced registration, UI work, a guard or retry behavior.'
      }
    }
    foreach ($functionName in @('ConsoleResolve', $action)) {
      $command = 'cgf "' + $qualifiedScriptName + '.' + $functionName + '"'
      if (!$Readme.Contains($command)) { throw "README is missing $command" }
    }
  }
  if ($Readme -match '\bcqf\b') { throw 'README still directs users to a quest-function console path.' }
  foreach ($command in [regex]::Matches($Readme, 'cgf "(?<script>Venworks:[\w:]+)\.(?<function>\w+)"')) {
    $qualifiedScriptName = $command.Groups['script'].Value
    $definition = @($Definitions | Where-Object { $_.ScriptName -ceq $qualifiedScriptName })
    if ($definition.Count -ne 1) { throw "Unknown documented console script: $qualifiedScriptName" }
    $scriptName = [string]$definition[0].Script
    $functionName = $command.Groups['function'].Value
    $functions = Get-ConsoleFunctions -Source $Sources[$scriptName]
    if (!$functions.ContainsKey($functionName)) { throw "Unknown documented console function: $functionName" }
    Assert-ConsolePattern $functions[$functionName].Flags '^\s+Global\s*$' 'each documented Canvas console command targets a real global'
  }
  Assert-ConsolePattern $Readme 'help "VWCANVAS_ComponentGalleryRegistrar" 4 QUST' 'optional quest help searches the Editor ID, not the display title'
}

$definitions = @(
  @{ Script = 'Registry'; ScriptName = 'Venworks:Canvas:Registry'; Source = 'Venworks/Canvas/Registry.psc'; Suffix = 'Registry'; Plugin = 'Venworks-Canvas.esm'; LocalId = '000800'; Action = 'ConsoleEnsureStorage'; Parameters = '' }
  @{ Script = 'ComponentGalleryRegistrar'; ScriptName = 'Venworks:CanvasComponentGallery:ComponentGalleryRegistrar'; Source = 'Venworks/CanvasComponentGallery/ComponentGalleryRegistrar.psc'; Suffix = 'ComponentGallery'; Plugin = 'Venworks-Canvas-ComponentGallery.esm'; LocalId = '000800'; Action = 'ConsoleCheckUiLoadRequest'; Parameters = 'String requestedConsumerId' }
  @{ Script = 'ExampleRegistrar'; ScriptName = 'Venworks:CanvasExamples:ExampleRegistrar'; Source = 'Venworks/CanvasExamples/ExampleRegistrar.psc'; Suffix = 'Example'; Plugin = 'Venworks-Canvas-Example.esm'; LocalId = '000800'; Action = 'ConsolePing'; Parameters = '' }
)
$sourceRoot = Join-Path $PSScriptRoot '../Papyrus'
$sources = @{}
foreach ($definition in $definitions) {
  $sources[$definition.Script] = Get-Content -LiteralPath (Join-Path $sourceRoot $definition.Source) -Raw
}
$readme = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../README.md') -Raw
$exampleMovie = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Scaleform/canvas/actionscript/CanvasExample.as') -Raw
Assert-CanvasConsoleContract -Sources $sources -Readme $readme -Definitions $definitions
Assert-ExamplePingUiContract -Source $exampleMovie
$mutations = @(
  @{ Script = 'ComponentGalleryRegistrar'; From = 'Venworks:Core:Utilities:Console.ConsoleEcho('; To = 'Venworks:Core:Logging.ConsoleEcho(' }
  @{ Script = 'Registry'; From = '"VWCANVAS: Registry.ConsoleEnsureStorage | "'; To = '"VWCORE: Registry.ConsoleEnsureStorage | "' }
  @{ Script = 'ComponentGalleryRegistrar'; From = 'ConsoleCheckUiLoadRequest(String requestedConsumerId) Global'; To = 'ConsoleCheckUiLoadRequest(String requestedConsumerId)' }
  @{ Script = 'ComponentGalleryRegistrar'; From = 'ScriptName Venworks:CanvasComponentGallery:ComponentGalleryRegistrar'; To = 'ScriptName Venworks:Canvas:ComponentGalleryRegistrar' }
  @{ Script = 'Registry'; From = 'ConsoleResolve() Global'; To = 'ConsoleResolve() Global Protected' }
  @{ Script = 'Registry'; From = 'Game.GetFormFromFile(0x000800,'; To = 'Game.GetFormFromFile(0xFE004800,' }
  @{ Script = 'ComponentGalleryRegistrar'; From = '"Venworks-Canvas-ComponentGallery.esm"'; To = '"Venworks-Canvas-Example.esm"' }
  @{ Script = 'Registry'; From = 'If (targetForm == None)'; To = 'If (False)' }
  @{ Script = 'ComponentGalleryRegistrar'; From = 'If (target == None)'; To = 'If (False)' }
  @{ Script = 'ComponentGalleryRegistrar'; From = 'target.CheckUiLoadRequest(requestedConsumerId)'; To = 'target.CheckUiLoadRequest("beef70b2-024e-4e9b-a8d5-70a0c882c431")' }
  @{ Script = 'ComponentGalleryRegistrar'; From = 'Registry.CheckUiLoadRequest(Self, requestedConsumerId)'; To = 'Registry.CheckUiLoadRequest(Registry, requestedConsumerId)' }
  @{ Script = 'ComponentGalleryRegistrar'; From = 'Registry.CheckUiLoadRequest(Self, requestedConsumerId)'; To = 'Registry.RequestUiLoad(Self, requestedConsumerId)' }
  @{ Script = 'ComponentGalleryRegistrar'; From = 'Return result'; To = 'Return "REGISTERED_TRANSPORT_DISABLED"' }
  @{ Script = 'Registry'; From = 'target.LogOperation(result)'; To = '; omitted' }
  @{ Script = 'ComponentGalleryRegistrar'; From = 'Return "CONSOLE_RESOLVED"'; To = ('target.RegisterWithRetry()' + [Environment]::NewLine + '  Return "CONSOLE_RESOLVED"') }
  @{ Script = 'Registry'; From = 'VWCANVAS_CONSOLE/1'; To = 'old-build' }
  @{ Script = 'ExampleRegistrar'; From = 'ConsolePing() Global'; To = 'ConsolePing()' }
  @{ Script = 'ExampleRegistrar'; From = 'Game.GetFormFromFile(0x000800,'; To = 'Game.GetFormFromFile(0xFE004800,' }
  @{ Script = 'ExampleRegistrar'; From = '"Venworks-Canvas-Example.esm"'; To = '"Venworks-Canvas-ComponentGallery.esm"' }
  @{ Script = 'ExampleRegistrar'; From = 'target.PublishConsolePing()'; To = '"EVENT_SUBMITTED"' }
  @{ Script = 'ExampleRegistrar'; From = '"venworks.canvas.example.ping", "ping"'; To = '"venworks.canvas.example.other", "ping"' }
  @{ Script = 'ExampleRegistrar'; From = 'Registry.LogOperation(result)'; To = '; omitted' }
  @{ Script = 'ExampleRegistrar'; From = 'Return result.Status'; To = 'Return "EVENT_SUBMITTED"' }
  @{ Script = 'CanvasExample'; From = 'this.pingReceived = true;'; To = 'this.pingReceived = false;' }
  @{ Script = 'CanvasExample'; From = 'this.marker.text = "pong";'; To = 'this.marker.text = "PONG";' }
  @{ Script = 'CanvasExample'; From = '!this.pingReceived && param1 == "PlayerData"'; To = 'param1 == "PlayerData"' }
  @{ Script = 'CanvasExample'; From = 'param1 == "venworks.canvas.example.ping"'; To = 'param1 == "venworks.canvas.example.other"' }
  @{ Script = 'README'; From = '.ConsoleCheckUiLoadRequest"'; To = '.CheckUiLoadRequest"' }
  @{ Script = 'README'; From = 'help "VWCANVAS_ComponentGalleryRegistrar"'; To = 'help "VWCANVAS Component Gallery Registrar"' }
)
$rejected = 0
foreach ($mutation in $mutations) {
  $candidate = @{} + $sources
  $candidateReadme = $readme
  $candidateExampleMovie = $exampleMovie
  $original = if ($mutation.Script -eq 'README') { $readme } elseif ($mutation.Script -eq 'CanvasExample') { $exampleMovie } else { $candidate[$mutation.Script] }
  if (!$original.Contains($mutation.From)) { throw "Mutation did not match: $($mutation.From)" }
  $changed = $original.Replace($mutation.From, $mutation.To)
  if ($mutation.Script -eq 'README') { $candidateReadme = $changed } elseif ($mutation.Script -eq 'CanvasExample') { $candidateExampleMovie = $changed } else { $candidate[$mutation.Script] = $changed }
  $caught = $false
  try {
    Assert-CanvasConsoleContract -Sources $candidate -Readme $candidateReadme -Definitions $definitions
    Assert-ExamplePingUiContract -Source $candidateExampleMovie
  } catch { $caught = $true }
  if (!$caught) { throw "Invalid console contract was accepted: $($mutation.From)" }
  $rejected += 1
}
Write-Output "Console source/documentation contracts passed; $rejected invalid mutations rejected. No console invocation or runtime lookup acceptance is implied."
