<#
.SYNOPSIS
Checks the load-only wire reference parser and source invariants; does not execute Papyrus or Scaleform.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')

function New-TestUiPacket {
  param([string]$Id = 'beef70b2-024e-4e9b-a8d5-70a0c882c431', [string]$Version = '1',
    [string]$Normal = 'VenworksCanvas/Consumers/probe.demo/normal.swf',
    [string]$Large = 'VenworksCanvas/Consumers/probe.demo/large.swf', [string]$Protocol = '1')
  $packet = 'VWC_EVT/1|canvas.ui.load|'
  foreach ($value in @($Protocol, $Id, $Version, $Normal, $Large)) { $packet += $value.Length.ToString() + ':' + $value }
  return $packet
}

function Get-TestPapyrusBody {
  param([string]$Source, [string]$Name)
  $match = [regex]::Match($Source, '(?ms)^(?:\w+\s+)?Function ' + [regex]::Escape($Name) + '\([^\r\n]*\)\r?\n(?<body>.*?)^EndFunction')
  if (!$match.Success) { throw "Missing function $Name." }
  return $match.Groups['body'].Value
}

function Assert-UiLoadSourceContract {
  param([string]$Registry, [string]$Movie)
  $request = Get-TestPapyrusBody $Registry 'TryRequestUiLoad'
  if ($request -notmatch '(?s)TryLockGuard RegistryGuard.*RequestUiLoadLocked.*QueueUiLoadLocked.*EndTryLockGuard\s+ScheduleUiPump\(result\)') {
    throw 'The second step must validate and enqueue under a guard, then schedule after release.'
  }
  foreach ($name in @('TryRegisterConsumer', 'RegisterConsumerLocked', 'TryCheckUiLoadRequest', 'RequestUiLoadLocked')) {
    if ((Get-TestPapyrusBody $Registry $name) -match 'ShowCustomWatchAlert|QueueUiLoadLocked|ScheduleUiPump|TryRequestUiLoad') {
      throw "$name must not request, schedule or submit a UI load."
    }
  }
  foreach ($token in @(
    'pending >= 32', 'IsPrintableAscii(packet, 1, 512)', 'UiLoads[existing].Packet == packet',
    'UiLoads[existing].Owner == owner', 'UI_LOAD_ALREADY_REQUESTED', 'UI_LOAD_QUEUED',
    'ticket == UiPumpBase', 'now < UiNextSubmitTime', 'UiNextSubmitTime = now + 1.0',
    'registration.Owner == entry.Owner', 'BuildUiLoadPacket(registration) == entry.Packet',
    'entry.Submitted = True', 'attempt < 20', 'result.Epoch == UiEpoch', 'UiPumpBase = -ticket',
    'attempt >= 51 && attempt <= 70', 'attempt < 70', 'UiPumpBase == -ticket',
    'UiAppliedActivationRequest != UiActivationRequest', 'UiAppliedActivationRequest = UiActivationRequest',
    'now >= UiPumpExpiresAt', 'UiPumpExpiresAt - now > 30.0', 'UiLoads = new UiLoadEntry[0]'
  )) {
    if (![regex]::IsMatch($Registry, [regex]::Escape($token) + '(?![A-Za-z0-9_])')) { throw "Missing load-queue invariant: $token" }
  }
  $pump = Get-TestPapyrusBody $Registry 'PumpUiLoad'
  if ([regex]::Matches($Registry, 'Game\.ShowCustomWatchAlert\(').Count -ne 1 -or
      $pump -notmatch '(?s)TryTakeUiLoad.*?If \(result.Status == "UI_LOAD_RESERVED"\).*?If \(PlayerHudRequested && result.Epoch == UiEpoch\).*?Game.ShowCustomWatchAlert\(result.Packet\).*?result.Status = "UI_LOAD_SUBMITTED"') {
    throw 'Only a reserved current-activation packet may reach the single native submission site.'
  }
  if ((Get-TestPapyrusBody $Registry 'RefreshUiActivation') -match '\bConsumers\s*=') { throw 'UI recreation must preserve registration storage.' }
  foreach ($token in @(
    'MAX_UI_LOAD_CHARACTERS:int = 512', 'packet.length > MAX_UI_LOAD_CHARACTERS',
    'this.parseUiLoad(param1)', 'this.reconcile(desired,false)', 'this.resolveHostKind() == "PLAYER HUD"',
    'protocol.value != "1"', 'cursor != packet.length', 'this.validateDescriptor(descriptor)',
    'this.normalizeUuid(String(id.value))', 'this.removeLoaderListeners(loader)',
    'this.dataManager.Unsubscribe(PROVIDER,this.callback)', 'this.disposed || this.owner != null'
    'watch.getCanvasWatchDisabled()', 'watch.getCanvasWatchDataManager()', 'PROVIDER CALLBACK RECEIVED'
  )) {
    if (!$Movie.Contains($token)) { throw "Missing host load invariant: $token" }
  }
  if ($Movie.Contains('this.receiveSnapshot(') -or $Movie.Contains('this.receiveDiagnostic(')) { throw 'Legacy ingress must stay unreachable.' }
}

$valid = New-TestUiPacket
$canonical = 'beef70b2-024e-4e9b-a8d5-70a0c882c431'
foreach ($id in @($canonical, $canonical.ToUpperInvariant(), '{BeEf70B2-024e-4e9b-A8d5-70A0c882c431}', $canonical.Replace('-', ''))) {
  $record = ConvertFrom-ConsumerDiscoveryUiLoadPacket -Packet (New-TestUiPacket -Id $id)
  if ($record.ConsumerId -cne $canonical -or $record.Version -ne 1) { throw 'UI load UUID normalization failed.' }
}
$mixed = ConvertFrom-ConsumerDiscoveryUiLoadPacket -Packet (New-TestUiPacket -Normal 'VenworksCanvas/Consumers/PROBE.Demo/normal.swf' -Large 'VENWORKSCANVAS/CONSUMERS/probe.demo/LARGE.SWF' -Version '9999')
if ($mixed.NormalPath -cne 'VenworksCanvas/Consumers/probe.demo/normal.swf' -or $mixed.Version -ne 9999) { throw 'Path/version normalization failed.' }
$namespace = 'a' * 64
[void](ConvertFrom-ConsumerDiscoveryUiLoadPacket -Packet (New-TestUiPacket -Normal "VenworksCanvas/Consumers/$namespace/normal.swf" -Large "VenworksCanvas/Consumers/$namespace/large.swf"))
$invalid = @('', ($valid + 'x'), $valid.Substring(0, $valid.Length - 1), ('x' * 513), ($valid + [char]10),
  $valid.Replace('canvas.ui.load', 'canvas.registry.snapshot'), $valid.Replace('1:1', '-1:1'),
  (New-TestUiPacket -Id 'not-a-uuid'), (New-TestUiPacket -Id (' ' + $canonical)),
  (New-TestUiPacket -Id '00000000-0000-0000-0000-000000000000'),
  (New-TestUiPacket -Version '0'), (New-TestUiPacket -Version '-1'), (New-TestUiPacket -Version '10000'),
  (New-TestUiPacket -Version '1.0'), (New-TestUiPacket -Protocol '2'),
  (New-TestUiPacket -Normal 'https://example.test/normal.swf'),
  (New-TestUiPacket -Normal 'VenworksCanvas/Consumers/../normal.swf'),
  (New-TestUiPacket -Normal 'VenworksCanvas/Consumers/probe..demo/normal.swf'),
  (New-TestUiPacket -Normal 'VenworksCanvas/Consumers/other/normal.swf'),
  (New-TestUiPacket -Normal 'Interface/VenworksCanvas/Consumers/probe.demo/normal.swf'),
  (New-TestUiPacket -Large 'VenworksCanvas/Consumers/probe.demo/normal.swf'))
$rejected = 0
foreach ($packet in $invalid) {
  $caught = $false
  try { [void](ConvertFrom-ConsumerDiscoveryUiLoadPacket -Packet $packet) } catch { $caught = $true }
  if (!$caught) { throw 'Invalid UI packet was accepted.' }
  $rejected += 1
}
$registry = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Papyrus/Venworks/Canvas/Probes/ConsumerDiscovery/Registry.psc') -Raw
$movie = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Scaleform/probes/consumer-discovery/actionscript/CanvasConsumerDiscoveryHost.as') -Raw
Assert-UiLoadSourceContract -Registry $registry -Movie $movie
$mutations = @(
  @('Registry', 'pending >= 32', 'pending >= 320'),
  @('Registry', 'IsPrintableAscii(packet, 1, 512)', 'IsPrintableAscii(packet, 1, 4096)'),
  @('Registry', 'UiLoads[existing].Packet == packet', 'False'),
  @('Registry', 'UiLoads[existing].Owner == owner', 'True'),
  @('Registry', 'ticket == UiPumpBase', 'True'),
  @('Registry', 'now < UiNextSubmitTime', 'False'),
  @('Registry', 'UiNextSubmitTime = now + 1.0', 'UiNextSubmitTime = now'),
  @('Registry', 'registration.Owner == entry.Owner', 'True'),
  @('Registry', 'BuildUiLoadPacket(registration) == entry.Packet', 'True'),
  @('Registry', 'entry.Submitted = True', 'entry.Submitted = False'),
  @('Registry', 'attempt < 20', 'True'),
  @('Registry', 'UiPumpBase = -ticket', 'UiPumpBase = 0'),
  @('Registry', 'attempt < 70', 'True'),
  @('Registry', 'UiAppliedActivationRequest != UiActivationRequest', 'True'),
  @('Registry', 'result.Epoch == UiEpoch', 'True'),
  @('Registry', 'now >= UiPumpExpiresAt', 'False'),
  @('Registry', 'UiLoads = new UiLoadEntry[0]', 'Consumers = new ConsumerRegistration[0]'),
  @('Movie', 'this.reconcile(desired,false)', 'this.reconcile(desired,true)'),
  @('Movie', 'MAX_UI_LOAD_CHARACTERS:int = 512', 'MAX_UI_LOAD_CHARACTERS:int = 4096'),
  @('Movie', 'protocol.value != "1"', 'false'),
  @('Movie', 'cursor != packet.length', 'false'),
  @('Movie', 'this.normalizeUuid(String(id.value))', 'String(id.value)'),
  @('Movie', 'this.parseUiLoad(param1)', 'this.receiveSnapshot(param1)')
)
$mutated = 0
foreach ($mutation in $mutations) {
  $candidateRegistry = $registry
  $candidateMovie = $movie
  $original = if ($mutation[0] -eq 'Registry') { $registry } else { $movie }
  if (!$original.Contains($mutation[1])) { throw "Mutation did not match: $($mutation[1])" }
  if ($mutation[0] -eq 'Registry') { $candidateRegistry = $registry.Replace($mutation[1], $mutation[2]) }
  else { $candidateMovie = $movie.Replace($mutation[1], $mutation[2]) }
  $caught = $false
  try { Assert-UiLoadSourceContract $candidateRegistry $candidateMovie } catch { $caught = $true }
  if (!$caught) { throw "Unsafe source mutation accepted: $($mutation[1])" }
  $mutated += 1
}
$matrix = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '../Scaleform/probes/consumer-discovery/probe-matrix.psd1')
if ($matrix.UiLoadTransport.MaxCharacters -ne 512 -or $matrix.UiLoadTransport.MaxPending -ne 32 -or
    $matrix.UiLoadTransport.MinimumIntervalSeconds -ne 1 -or $matrix.UiLoadTransport.MaxBusyAttempts -ne 20 -or
    $matrix.UiLoadTransport.Target -cne 'PlayerHud') { throw 'Matrix load budgets differ from source.' }
Write-Output "UI load reference vectors passed; $rejected malformed packets and $mutated unsafe source mutations rejected. No Papyrus/Scaleform VM or delivery acceptance is implied."
