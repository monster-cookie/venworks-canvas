<#
.SYNOPSIS
Checks UUID reference vectors and source-level guard contracts; does not execute the Papyrus or Scaleform VM.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedVariants.ps1')
. (Join-Path $PSScriptRoot 'sharedBuild.ps1')
$configurationLoaded = Get-Variable -Name SharedConfigurationLoaded -Scope Global -ErrorAction SilentlyContinue
if ($null -eq $configurationLoaded -or !$configurationLoaded.Value) {
  . (Join-Path $PSScriptRoot 'sharedConfig.ps1')
}
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')
$canonical = 'a8098c1a-f86e-4b1e-9d7c-5a102bf38460'
foreach ($inputValue in @($canonical, $canonical.ToUpperInvariant(), '{A8098c1A-f86E-4b1e-9D7c-5A102bF38460}', $canonical.Replace('-', ''))) {
  if ((ConvertTo-CanvasUuid -Value $inputValue) -cne $canonical) { throw 'UUID canonical key mismatch.' }
}
foreach ($inputValue in @('', 'invalid', '00000000-0000-0000-0000-000000000000', 'a8098c1a_f86e-4b1e-9d7c-5a102bf38460', 'a8098c1a-f86e-4b1e-9d7c-5a102bf3846g', " $canonical", "$canonical ", "$canonical`n", ('{' + $canonical.Replace('-', '') + '}'))) {
  $rejected = $false
  try { [void](ConvertTo-CanvasUuid -Value $inputValue) } catch { $rejected = $true }
  if (!$rejected) { throw 'UUID reference accepted a malformed/nil value.' }
}
$sourceRoot = Join-Path $PSScriptRoot '../Papyrus'
$registry = Get-Content -LiteralPath (Join-Path $sourceRoot 'Venworks/Canvas/Registry.psc') -Raw
& (Join-Path $PSScriptRoot 'testGuards.ps1')
$registrar = Get-Content -LiteralPath (Join-Path $sourceRoot 'Venworks/CanvasExamples/ExampleRegistrar.psc') -Raw
if ($registry.Contains('GenerateV4(') -or $registrar.Contains('GenerateV4(')) { throw 'Registration must not generate IDs.' }
$canvasHostSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Scaleform/canvas/actionscript/CanvasHost.as') -Raw
foreach ($token in @('this.normalizeUuid(String(consumerIdFrame.value))','this.normalizeUuid(String(param1.consumerId))','this.normalizeUuid(param1.consumerId)','value.length != 36','value.length == 32','value = value.toLowerCase();')) {
  if (!$canvasHostSource.Contains($token)) { throw "ActionScript intake normalization missing: $token" }
}
$expectedIds = @{
  VWCANVAS_ExampleRegistrar = $canonical
  VWCANVAS_ComponentGalleryRegistrar = 'beef70b2-024e-4e9b-a8d5-70a0c882c431'
}
$expectedScripts = @{
  VWCANVAS_ExampleRegistrar = 'Venworks:CanvasExamples:ExampleRegistrar'
  VWCANVAS_ComponentGalleryRegistrar = 'Venworks:CanvasComponentGallery:ComponentGalleryRegistrar'
}
$yamlBindings = 0
$spriggitRoot = Join-Path $PSScriptRoot '../Spriggit'
if (!(Test-Path -LiteralPath $spriggitRoot -PathType Container)) {
  throw "UUID binding root does not exist: $spriggitRoot"
}
foreach ($file in Get-ChildItem -LiteralPath $spriggitRoot -Recurse -File -Filter RecordData.yaml) {
  $yaml = Get-Content -LiteralPath $file.FullName -Raw
  $editorId = [regex]::Match($yaml, '(?m)^EditorID: (\S+)').Groups[1].Value
  if (!$expectedIds.ContainsKey($editorId)) { continue }
  $scriptBinding = [regex]::Match($yaml, '(?m)^  - Name: (\S+)').Groups[1].Value
  if ($scriptBinding -cne $expectedScripts[$editorId]) { throw "Unexpected registrar script binding in $($file.FullName)." }
  $binding = [regex]::Match($yaml, '(?m)^      Name: ConsumerId\r?\n      Data: ([^\r\n]+)').Groups[1].Value
  if ($binding -cne $expectedIds[$editorId]) { throw "Unexpected persistent UUID binding in $($file.FullName)." }
  [void](ConvertTo-CanvasUuid -Value $binding)
  $yamlBindings += 1
}
if ($yamlBindings -ne 2) { throw "Expected two UUID VMAD bindings, found $yamlBindings." }
Write-Output 'UUID reference vectors, two namespaced VMAD bindings and guard-source contracts passed; Papyrus/Scaleform runtime remains a PC test.'
