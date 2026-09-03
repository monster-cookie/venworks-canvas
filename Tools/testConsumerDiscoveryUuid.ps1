<#
.SYNOPSIS
Checks UUID reference vectors and source-level guard contracts; does not execute the Papyrus or Scaleform VM.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')
$canonical = 'a8098c1a-f86e-4b1e-9d7c-5a102bf38460'
foreach ($inputValue in @($canonical, $canonical.ToUpperInvariant(), '{A8098c1A-f86E-4b1e-9D7c-5A102bF38460}', $canonical.Replace('-', ''))) {
  if ((ConvertTo-ConsumerDiscoveryUuid -Value $inputValue) -cne $canonical) { throw 'UUID canonical key mismatch.' }
}
foreach ($inputValue in @('', 'invalid', '00000000-0000-0000-0000-000000000000', 'a8098c1a_f86e-4b1e-9d7c-5a102bf38460', 'a8098c1a-f86e-4b1e-9d7c-5a102bf3846g', " $canonical", "$canonical ", "$canonical`n", ('{' + $canonical.Replace('-', '') + '}'))) {
  $rejected = $false
  try { [void](ConvertTo-ConsumerDiscoveryUuid -Value $inputValue) } catch { $rejected = $true }
  if (!$rejected) { throw 'UUID reference accepted a malformed/nil value.' }
}
$sourceRoot = Join-Path $PSScriptRoot '../Papyrus/Venworks/Canvas/Probes/ConsumerDiscovery'
$registry = Get-Content -LiteralPath (Join-Path $sourceRoot 'Registry.psc') -Raw
foreach ($name in @('RegisterConsumer','UnregisterConsumer','RequestUiLoad','EnsureStorage','FindConsumerIndex','MigrateConsumerIdentity')) {
  $pattern = '(?ms)^(?:Bool|Int|String) Function ' + $name + '\([^\r\n]*\).*?^EndFunction'
  $body = [regex]::Match($registry, $pattern).Value
  if (!$body.Contains('LockGuard RegistryGuard') -or !$body.Contains($name + 'Locked(')) {
    throw "Registry API is not guarded: $name"
  }
}
$registrar = Get-Content -LiteralPath (Join-Path $sourceRoot 'ConsumerARegistrar.psc') -Raw
foreach ($token in @('Guard AttemptGuard ProtectsFunctionLogic','LockGuard AttemptGuard','PendingUpdate = True','If (PendingUpdate)','ApplyPendingUpdate()','DESCRIPTOR_UPDATE_PENDING')) {
  if (!$registrar.Contains($token)) { throw "Pending migration contract missing: $token" }
}
if ($registry.Contains('GenerateV4(') -or $registrar.Contains('GenerateV4(')) { throw 'Registration must not generate IDs.' }
$canvasHostSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Scaleform/probes/consumer-discovery/actionscript/CanvasConsumerDiscoveryHost.as') -Raw
foreach ($token in @('this.normalizeUuid(String(consumerIdFrame.value))','this.normalizeUuid(String(record.consumerId))','value.length != 36','value.length == 32','value = value.toLowerCase();')) {
  if (!$canvasHostSource.Contains($token)) { throw "ActionScript intake normalization missing: $token" }
}
$expectedIds = @{
  VWCANVAS9_ConsumerARegistrar = $canonical
  VWCANVAS9_ConsumerBRegistrar = 'beef70b2-024e-4e9b-a8d5-70a0c882c431'
  VWCANVAS9_ConsumerBCollisionProbe = $canonical.ToUpperInvariant()
  VWCANVAS9_ConsumerBMissingProbe = 'cad7cd56-217a-4e62-a98d-42c3adad07b5'
}
$yamlBindings = 0
foreach ($uuidProfile in @('Baseline','Faults','UpdatedA')) {
  $root = Join-Path $PSScriptRoot "../Spriggit/ConsumerDiscovery/$uuidProfile"
  foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter RecordData.yaml) {
    $yaml = Get-Content -LiteralPath $file.FullName -Raw
    $editorId = [regex]::Match($yaml, '(?m)^EditorID: (\S+)').Groups[1].Value
    if (!$expectedIds.ContainsKey($editorId)) { continue }
    $binding = [regex]::Match($yaml, '(?m)^      Name: ConsumerId\r?\n      Data: ([^\r\n]+)').Groups[1].Value
    if ($binding -cne $expectedIds[$editorId]) { throw "Unexpected persistent UUID binding in $($file.FullName)." }
    [void](ConvertTo-ConsumerDiscoveryUuid -Value $binding)
    $yamlBindings += 1
  }
}
if ($yamlBindings -ne 8) { throw "Expected eight UUID VMAD bindings, found $yamlBindings." }
Write-Output 'UUID reference vectors, eight VMAD bindings and guard-source contracts passed; Papyrus/Scaleform runtime remains a PC test.'
