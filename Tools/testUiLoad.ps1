<#
.SYNOPSIS
Checks the load-only wire reference parser, source invariants and lifecycle sequence models; does not execute Papyrus or Scaleform.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1')
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

function New-TestUiPacket {
  param([string]$Id = 'beef70b2-024e-4e9b-a8d5-70a0c882c431', [string]$Version = '1',
    [string]$Normal = 'VenworksCanvas/Consumers/fixture.demo/normal.swf',
    [string]$Large = 'VenworksCanvas/Consumers/fixture.demo/large.swf', [string]$Protocol = '1',
    [string]$EventHeader = 'VWC_EVT/1|', [string]$PacketType = 'canvas.ui.load')
  $packet = $EventHeader + $PacketType + '|'
  foreach ($value in @($Protocol, $Id, $Version, $Normal, $Large)) { $packet += $value.Length.ToString() + ':' + $value }
  return $packet
}

function Get-TestPapyrusBody {
  param([string]$Source, [string]$Name)
  $match = [regex]::Match($Source, '(?ms)^(?:\w+\s+)?Function ' + [regex]::Escape($Name) + '\([^\r\n]*\)[^\r\n]*\r?\n(?<body>.*?)^EndFunction')
  if (!$match.Success) { throw "Missing function $Name." }
  return $match.Groups['body'].Value
}

function Assert-UiLoadSourceContract {
  param([string]$Enumerations, [string]$Registry, [string]$Movie)
  foreach ($token in @(
    'Struct EventHeader', 'Int V1 = 1', 'Struct PacketType', 'Int UiLoad = 1',
    'String Function ResolveEventHeader(Int eventHeader) Global',
    'String Function ResolvePacketType(Int packetType) Global',
    'Return "VWC_EVT/1|"', 'Return "canvas.ui.load"', 'Return ""'
  )) {
    if (!$Enumerations.Contains($token)) { throw "Missing Canvas protocol enumeration invariant: $token" }
  }
  if ([regex]::Matches($Enumerations, [regex]::Escape('VWC_EVT/1|')).Count -ne 1 -or
      [regex]::Matches($Enumerations, [regex]::Escape('canvas.ui.load')).Count -ne 1) {
    throw 'Protocol wire strings must each have exactly one Papyrus owner.'
  }
  $eventBuilder = Get-TestPapyrusBody $Registry 'BuildEventPacket'
  if ($eventBuilder -notmatch '(?s)ResolveEventHeader\(eventHeader\).*ResolvePacketType\(packetType\).*If \(eventHeaderText == "" \|\| packetTypeText == ""\).*Return "".*Return eventHeaderText \+ packetTypeText \+ "\|" \+ payload' -or
      $eventBuilder -match 'VWC_EVT/1|canvas\.ui\.load') {
    throw 'The event builder must resolve and reject enum selectors without accepting or owning raw wire text.'
  }
  $uiPacketBuilder = Get-TestPapyrusBody $Registry 'BuildUiLoadPacket'
  if ($uiPacketBuilder -notmatch '(?s)new Venworks:Canvas:Enumerations:EventHeader.*new Venworks:Canvas:Enumerations:PacketType.*BuildEventPacket\(headers\.V1, packetTypes\.UiLoad, payload\)' -or
      $Registry.Contains('"VWC_EVT/1|"') -or $Registry.Contains('"canvas.ui.load"') -or
      $Registry -match '(?im)^\s*(?:\w+\s+)?Function\s+\w+\([^\r\n]*String\s+(?:eventHeader|packetType)\b') {
    throw 'UI-load construction must use enum selectors and expose no raw-string header or packet-type argument.'
  }
  $request = Get-TestPapyrusBody $Registry 'TryRequestUiLoad'
  if ($request -notmatch '(?s)TryLockGuard RegistryGuard.*RequestUiLoadLocked.*QueueUiLoadLocked.*EndTryLockGuard\s+ScheduleUiPump\(result\)') {
    throw 'The second step must validate and enqueue under a guard, then schedule after release.'
  }
  $queue = Get-TestPapyrusBody $Registry 'QueueUiLoadLocked'
  if ($queue -notmatch '(?s)UiAppliedActivationRequest != UiActivationRequest.*?result\.Status = "DEFERRED_UI_INACTIVE".*?Return.*?Int registeredIndex') {
    throw 'A pending HUD activation must defer before old queue entries can satisfy deduplication.'
  }
  if ($queue -notmatch '(?s)If \(pending >= 32 && \(existing < 0 \|\| UiLoads\[existing\]\.Submitted\)\)\s+result\.Status = "DEFERRED_UI_QUEUE_FULL"\s+;[^\r\n]*\s+If \(UiPumpBase == 0\)\s+result\.TimerId = StartUiPumpLocked\(now\)\s+EndIf\s+Return') {
    throw 'A full pending queue must restart an inactive pump before returning its deferred result.'
  }
  $take = Get-TestPapyrusBody $Registry 'TryTakeUiLoad'
  if ($take -notmatch 'UiAppliedActivationRequest == UiActivationRequest && UiActive') {
    throw 'A pump must not reserve old-generation work while activation reset is pending.'
  }
  if ($take -notmatch '(?s)If \(entry == None\)\s+UiLoads\.Remove\(index\)\s+ElseIf \(!entry\.Submitted\).*?If \(registration\.Owner == entry\.Owner && BuildUiLoadPacket\(registration\) == entry\.Packet\).*?result\.Status = "UI_LOAD_RESERVED".*?entry\.Submitted = True\s+Else\s+UiLoads\.Remove\(index\)\s+EndIf\s+Else\s+UiLoads\.Remove\(index\)\s+EndIf\s+Else\s+index \+= 1') {
    throw 'The pump must remove stale unsent entries in place and mark only a matching reservation as submitted.'
  }
  if ((Get-TestPapyrusBody $Registry 'IsDeferred') -notmatch 'DEFERRED_UI_INACTIVE') {
    throw 'Pending activation admission must remain retryable through the registrar deferred contract.'
  }
  foreach ($name in @('TryRegisterConsumer', 'RegisterConsumerLocked', 'TryCheckUiLoadRequest', 'RequestUiLoadLocked')) {
    if ((Get-TestPapyrusBody $Registry $name) -match 'ShowCustomWatchAlert|QueueUiLoadLocked|ScheduleUiPump|TryRequestUiLoad') {
      throw "$name must not request, schedule or submit a UI load."
    }
  }
  foreach ($token in @(
    'pending >= 32', 'packet == ""', 'REJECTED_UI_PROTOCOL', 'IsPrintableAscii(packet, 1, 512)', 'UiLoads[existing].Packet == packet',
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
      $pump -notmatch '(?s)TryTakeUiLoad.*?If \(result.Status == "UI_LOAD_RESERVED"\).*?If \(UiAppliedActivationRequest == UiActivationRequest && PlayerHudRequested && result.Epoch == UiEpoch\).*?Game.ShowCustomWatchAlert\(result.Packet\).*?result.Status = "UI_LOAD_SUBMITTED"') {
    throw 'Only a reserved current-activation packet may reach the single native submission site.'
  }
  if ((Get-TestPapyrusBody $Registry 'RefreshUiActivation') -match '\bConsumers\s*=') { throw 'UI recreation must preserve registration storage.' }
  foreach ($token in @(
    'MAX_UI_LOAD_CHARACTERS:int = 512', 'packet.length > MAX_UI_LOAD_CHARACTERS',
    'this.matchAsciiPrefix(text,UI_LOAD_PREFIX)', 'this.matchAsciiPrefix(param1,UI_LOAD_PREFIX)',
    'this.matchAsciiPrefix(packet,UI_LOAD_PREFIX)', 'ASCII CASE-FOLDED',
    'actual >= 65 && actual <= 90', 'expected >= 65 && expected <= 90',
    'this.parseUiLoad(param1)', 'this.reconcile(desired,false)', 'this.resolveHostKind() == "PLAYER HUD"',
    'protocol.value != "1"', 'cursor != packet.length', 'this.validateDescriptor(descriptor)',
    'this.normalizeUuid(String(id.value))', 'this.removeLoaderListeners(loader)',
    'this.dataManager.Unsubscribe(PROVIDER,this.callback)', 'this.disposed || this.owner != null'
    'watch.getCanvasWatchDisabled()', 'watch.getCanvasWatchDataManager()', 'watch.getCanvasWatchSubscriptionsRestored()',
    'WATCH SUBSCRIPTIONS RESTORED', 'PROVIDER CALLBACK #', 'PROVIDER ALERT #'
  )) {
    if (!$Movie.Contains($token)) { throw "Missing host load invariant: $token" }
  }
  $prefixMatcher = [regex]::Match($Movie, '(?ms)      private function matchAsciiPrefix\([^\r\n]*\) : int\s*\{(?<body>.*?)^      \}')
  if (!$prefixMatcher.Success -or $prefixMatcher.Groups['body'].Value -match 'toLowerCase|toUpperCase') {
    throw 'The receiver must compare only the ASCII prefix without normalizing the complete packet.'
  }
  if ($Movie.Contains('this.receiveSnapshot(') -or $Movie.Contains('this.receiveDiagnostic(')) { throw 'Legacy ingress must stay unreachable.' }
}

function New-TestUiLifecycleModel {
  $loads = [System.Collections.ArrayList]::new()
  $reservations = [System.Collections.ArrayList]::new()
  return [pscustomobject]@{
    PlayerHudRequested = $true
    UiActive = $true
    UiEpoch = 0
    UiActivationRequest = 0
    UiAppliedActivationRequest = 0
    UiLoads = $loads
    Registrations = @{}
    PumpActive = $false
    PumpTicket = 0
    NextPumpTicket = 1000
    Reservations = $reservations
    NativeSubmissions = [System.Collections.ArrayList]::new()
  }
}

function Set-TestUiRegistration {
  param($Model, [string]$ConsumerId, [string]$Owner, [string]$Packet)
  $Model.Registrations[$ConsumerId] = [pscustomobject]@{ Owner = $Owner; Packet = $Packet }
}

function Add-TestUiLoad {
  param($Model, [string]$ConsumerId, [string]$Owner, [string]$Packet, [bool]$Submitted = $false)
  [void]$Model.UiLoads.Add([pscustomobject]@{ ConsumerId = $ConsumerId; Owner = $Owner; Packet = $Packet; Submitted = $Submitted })
}

function Request-TestUiLoad {
  param($Model, [string]$ConsumerId, [string]$Owner)
  if ($Model.UiAppliedActivationRequest -ne $Model.UiActivationRequest -or !$Model.UiActive -or !$Model.PlayerHudRequested) {
    return 'DEFERRED_UI_INACTIVE'
  }
  if (!$Model.Registrations.ContainsKey($ConsumerId)) { throw "Model request is not registered: $ConsumerId" }
  $packet = $Model.Registrations[$ConsumerId].Packet
  $existing = -1
  $index = 0
  while ($index -lt $Model.UiLoads.Count) {
    if ($Model.UiLoads[$index].ConsumerId -ceq $ConsumerId) { $existing = $index }
    $index += 1
  }
  if ($existing -ge 0 -and $Model.UiLoads[$existing].Owner -ceq $Owner -and $Model.UiLoads[$existing].Packet -ceq $packet) {
    if (!$Model.UiLoads[$existing].Submitted -and !$Model.PumpActive) {
      $Model.PumpActive = $true
      $Model.PumpTicket = $Model.NextPumpTicket
      $Model.NextPumpTicket += 100
    }
    return 'UI_LOAD_ALREADY_REQUESTED'
  }
  $entry = [pscustomobject]@{ ConsumerId = $ConsumerId; Owner = $Owner; Packet = $packet; Submitted = $false }
  if ($existing -ge 0) { $Model.UiLoads[$existing] = $entry } else { [void]$Model.UiLoads.Add($entry) }
  if (!$Model.PumpActive) {
    $Model.PumpActive = $true
    $Model.PumpTicket = $Model.NextPumpTicket
    $Model.NextPumpTicket += 100
  }
  return 'UI_LOAD_QUEUED'
}

function Request-TestHudActivation {
  param($Model, [bool]$Opening)
  $Model.PlayerHudRequested = $Opening
  $Model.UiActivationRequest += 1
}

function Invoke-TestUiActivationReset {
  param($Model, [switch]$Busy)
  if ($Busy) { return 'DEFERRED_REGISTRY_BUSY' }
  if ($Model.UiAppliedActivationRequest -ne $Model.UiActivationRequest -or $Model.UiActive -ne $Model.PlayerHudRequested) {
    $Model.UiEpoch += 1
    $Model.UiActive = $Model.PlayerHudRequested
    $Model.UiLoads.Clear()
    $Model.PumpActive = $false
    $Model.PumpTicket = 0
    $Model.UiAppliedActivationRequest = $Model.UiActivationRequest
    return 'UI_ACTIVATION_RESET'
  }
  return 'UI_ACTIVATION_UNCHANGED'
}

function Invoke-TestRegistrarAttempt {
  param($Model, [string]$ConsumerId, [string]$Owner, [int]$Attempt)
  $status = Request-TestUiLoad -Model $Model -ConsumerId $ConsumerId -Owner $Owner
  $deferred = $status -like 'DEFERRED_*'
  return [pscustomobject]@{
    Status = $status
    Retry = $deferred -and $Attempt -lt 20
    Exhausted = $deferred -and $Attempt -eq 20
  }
}

function Invoke-TestUiPump {
  param($Model, [int]$Ticket = 0)
  if ($Ticket -eq 0) { $Ticket = $Model.PumpTicket }
  if ($Model.UiAppliedActivationRequest -ne $Model.UiActivationRequest -or !$Model.UiActive -or !$Model.PlayerHudRequested -or
      $Ticket -eq 0 -or $Ticket -ne $Model.PumpTicket) {
    return [pscustomobject]@{ Status = 'UI_LOAD_IDLE'; Packet = $null; Inspected = 0; Epoch = -1 }
  }
  $Model.PumpActive = $false
  $Model.PumpTicket = 0
  $index = 0
  $inspected = 0
  $reserved = $null
  while ($index -lt $Model.UiLoads.Count -and $null -eq $reserved) {
    $inspected += 1
    $entry = $Model.UiLoads[$index]
    if ($null -eq $entry) {
      $Model.UiLoads.RemoveAt($index)
    }
    elseif (!$entry.Submitted) {
      $registration = if ($Model.Registrations.ContainsKey($entry.ConsumerId)) { $Model.Registrations[$entry.ConsumerId] } else { $null }
      if ($null -ne $registration -and $registration.Owner -ceq $entry.Owner -and $registration.Packet -ceq $entry.Packet) {
        $entry.Submitted = $true
        $reserved = $entry.Packet
        [void]$Model.Reservations.Add($reserved)
      }
      else {
        $Model.UiLoads.RemoveAt($index)
      }
    }
    else {
      $index += 1
    }
  }
  return [pscustomobject]@{ Status = if ($null -eq $reserved) { 'UI_LOAD_IDLE' } else { 'UI_LOAD_RESERVED' }; Packet = $reserved; Inspected = $inspected; Epoch = $Model.UiEpoch }
}

function Submit-TestUiReservation {
  param($Model, $Reservation)
  if ($Reservation.Status -ceq 'UI_LOAD_RESERVED' -and $Model.UiAppliedActivationRequest -eq $Model.UiActivationRequest -and
      $Model.PlayerHudRequested -and $Reservation.Epoch -eq $Model.UiEpoch) {
    [void]$Model.NativeSubmissions.Add($Reservation.Packet)
    return 'UI_LOAD_SUBMITTED'
  }
  return 'UI_LOAD_CANCELLED_ACTIVATION'
}

$valid = New-TestUiPacket
$canonical = 'beef70b2-024e-4e9b-a8d5-70a0c882c431'
foreach ($id in @($canonical, $canonical.ToUpperInvariant(), '{BeEf70B2-024e-4e9b-A8d5-70A0c882c431}', $canonical.Replace('-', ''))) {
  $record = ConvertFrom-CanvasUiLoadPacket -Packet (New-TestUiPacket -Id $id)
  if ($record.ConsumerId -cne $canonical -or $record.Version -ne 1) { throw 'UI load UUID normalization failed.' }
}
foreach ($caseVariant in @(
  @{ EventHeader = 'vwc_evt/1|'; PacketType = 'CANVAS.UI.LOAD' },
  @{ EventHeader = 'VwC_EvT/1|'; PacketType = 'CaNvAs.Ui.LoAd' }
)) {
  $record = ConvertFrom-CanvasUiLoadPacket -Packet (New-TestUiPacket -EventHeader $caseVariant.EventHeader -PacketType $caseVariant.PacketType)
  if ($record.ConsumerId -cne $canonical -or $record.NormalPath -cne 'VenworksCanvas/Consumers/fixture.demo/normal.swf') {
    throw 'Case-folded envelope acceptance changed framed payload data.'
  }
}
$mixed = ConvertFrom-CanvasUiLoadPacket -Packet (New-TestUiPacket -Normal 'VenworksCanvas/Consumers/FIXTURE.Demo/normal.swf' -Large 'VENWORKSCANVAS/CONSUMERS/fixture.demo/LARGE.SWF' -Version '9999')
if ($mixed.NormalPath -cne 'VenworksCanvas/Consumers/fixture.demo/normal.swf' -or $mixed.Version -ne 9999) { throw 'Path/version normalization failed.' }
$namespace = 'a' * 64
[void](ConvertFrom-CanvasUiLoadPacket -Packet (New-TestUiPacket -Normal "VenworksCanvas/Consumers/$namespace/normal.swf" -Large "VenworksCanvas/Consumers/$namespace/large.swf"))
$invalid = @('', ($valid + 'x'), $valid.Substring(0, $valid.Length - 1), ('x' * 513), ($valid + [char]10),
  $valid.Replace('canvas.ui.load', 'canvas.registry.snapshot'), $valid.Replace('1:1', '-1:1'),
  (New-TestUiPacket -Id 'not-a-uuid'), (New-TestUiPacket -Id (' ' + $canonical)),
  (New-TestUiPacket -Id '00000000-0000-0000-0000-000000000000'),
  (New-TestUiPacket -Version '0'), (New-TestUiPacket -Version '-1'), (New-TestUiPacket -Version '10000'),
  (New-TestUiPacket -Version '1.0'), (New-TestUiPacket -Protocol '2'),
  (New-TestUiPacket -Normal 'https://example.test/normal.swf'),
  (New-TestUiPacket -Normal 'VenworksCanvas/Consumers/../normal.swf'),
  (New-TestUiPacket -Normal 'VenworksCanvas/Consumers/fixture..demo/normal.swf'),
  (New-TestUiPacket -Normal 'VenworksCanvas/Consumers/other/normal.swf'),
  (New-TestUiPacket -Normal 'Interface/VenworksCanvas/Consumers/fixture.demo/normal.swf'),
  (New-TestUiPacket -Large 'VenworksCanvas/Consumers/fixture.demo/normal.swf'))
$rejected = 0
foreach ($packet in $invalid) {
  $caught = $false
  try { [void](ConvertFrom-CanvasUiLoadPacket -Packet $packet) } catch { $caught = $true }
  if (!$caught) { throw 'Invalid UI packet was accepted.' }
  $rejected += 1
}
$enumerations = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Papyrus/Venworks/Canvas/Enumerations.psc') -Raw
$registry = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Papyrus/Venworks/Canvas/Registry.psc') -Raw
$movie = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Scaleform/canvas/actionscript/CanvasHost.as') -Raw
Assert-UiLoadSourceContract -Enumerations $enumerations -Registry $registry -Movie $movie

# C-005: old submitted work cannot satisfy a request while a newer HUD activation awaits reset.
$activation = New-TestUiLifecycleModel
Set-TestUiRegistration $activation 'consumer-a' 'owner-a' 'packet-v1'
Add-TestUiLoad $activation 'consumer-a' 'owner-a' 'packet-v1' $true
Request-TestHudActivation $activation $true
$firstAttempt = Invoke-TestRegistrarAttempt $activation 'consumer-a' 'owner-a' 1
if ($firstAttempt.Status -cne 'DEFERRED_UI_INACTIVE' -or !$firstAttempt.Retry -or $activation.UiLoads.Count -ne 1) {
  throw 'C-005 model: an old submitted receipt was consumed before activation reset.'
}
Request-TestHudActivation $activation $true
$busyReset = Invoke-TestUiActivationReset $activation -Busy
$delayedAttempt = Invoke-TestRegistrarAttempt $activation 'consumer-a' 'owner-a' 2
if ($busyReset -cne 'DEFERRED_REGISTRY_BUSY' -or $delayedAttempt.Status -cne 'DEFERRED_UI_INACTIVE' -or !$delayedAttempt.Retry) {
  throw 'C-005 model: repeated opening or contended reset did not remain retryable.'
}
if ((Invoke-TestUiActivationReset $activation) -cne 'UI_ACTIVATION_RESET' -or $activation.UiLoads.Count -ne 0) {
  throw 'C-005 model: activation reset did not clear presentation bookkeeping.'
}
$afterReset = Invoke-TestRegistrarAttempt $activation 'consumer-a' 'owner-a' 3
$newReservation = Invoke-TestUiPump $activation
$newSubmission = Submit-TestUiReservation $activation $newReservation
if ($afterReset.Status -cne 'UI_LOAD_QUEUED' -or $newReservation.Status -cne 'UI_LOAD_RESERVED' -or
    $newReservation.Packet -cne 'packet-v1' -or $newSubmission -cne 'UI_LOAD_SUBMITTED' -or $activation.NativeSubmissions.Count -ne 1) {
  throw 'C-005 model: bounded registrar retry did not create a new reservation after reset.'
}
$reservedDuplicate = Request-TestUiLoad $activation 'consumer-a' 'owner-a'
if ($reservedDuplicate -cne 'UI_LOAD_ALREADY_REQUESTED' -or $activation.PumpActive -or
    $activation.Reservations.Count -ne 1 -or $activation.NativeSubmissions.Count -ne 1) {
  throw 'C-005 model: a real reservation lost terminal duplicate suppression.'
}

# A pending activation or the wrong timer ticket cannot inspect, reserve or dispatch queued work.
$pendingPump = New-TestUiLifecycleModel
Set-TestUiRegistration $pendingPump 'consumer-a' 'owner-a' 'packet-v1'
if ((Request-TestUiLoad $pendingPump 'consumer-a' 'owner-a') -cne 'UI_LOAD_QUEUED') { throw 'C-005 model setup failed to queue pump work.' }
$currentTicket = $pendingPump.PumpTicket
$wrongTicket = Invoke-TestUiPump $pendingPump ($currentTicket + 100)
if ($wrongTicket.Status -cne 'UI_LOAD_IDLE' -or $wrongTicket.Inspected -ne 0 -or !$pendingPump.PumpActive) {
  throw 'C-005 model: a mismatched pump ticket inspected or released queued work.'
}
Request-TestHudActivation $pendingPump $true
$oldGenerationPump = Invoke-TestUiPump $pendingPump $currentTicket
if ($oldGenerationPump.Status -cne 'UI_LOAD_IDLE' -or $oldGenerationPump.Inspected -ne 0 -or
    $pendingPump.UiLoads.Count -ne 1 -or $pendingPump.Reservations.Count -ne 0) {
  throw 'C-005 model: pending activation allowed an old-generation reservation.'
}

# If activation changes after reservation, the dispatch boundary still rejects the old generation.
$dispatchWindow = New-TestUiLifecycleModel
Set-TestUiRegistration $dispatchWindow 'consumer-a' 'owner-a' 'packet-v1'
[void](Request-TestUiLoad $dispatchWindow 'consumer-a' 'owner-a')
$reservedBeforeActivation = Invoke-TestUiPump $dispatchWindow
Request-TestHudActivation $dispatchWindow $true
$cancelledSubmission = Submit-TestUiReservation $dispatchWindow $reservedBeforeActivation
if ($cancelledSubmission -cne 'UI_LOAD_CANCELLED_ACTIVATION' -or $dispatchWindow.NativeSubmissions.Count -ne 0) {
  throw 'C-005 model: a reservation crossed an unapplied activation into native dispatch.'
}

# Exhaustion releases this attempt series; a later opening and successful reset starts again at attempt one.
$exhausted = New-TestUiLifecycleModel
Set-TestUiRegistration $exhausted 'consumer-a' 'owner-a' 'packet-v1'
Request-TestHudActivation $exhausted $true
$lastAttempt = $null
foreach ($attempt in 1..20) {
  $lastAttempt = Invoke-TestRegistrarAttempt $exhausted 'consumer-a' 'owner-a' $attempt
  if ($lastAttempt.Status -cne 'DEFERRED_UI_INACTIVE' -or ($attempt -lt 20 -and !$lastAttempt.Retry)) {
    throw "C-005 model: deferred registrar attempt $attempt did not preserve its bounded retry contract."
  }
}
if (!$lastAttempt.Exhausted -or $lastAttempt.Retry) { throw 'C-005 model: the twentieth deferred attempt did not exhaust.' }
Request-TestHudActivation $exhausted $true
if ((Invoke-TestUiActivationReset $exhausted) -cne 'UI_ACTIVATION_RESET') { throw 'C-005 model: later activation did not reset after exhaustion.' }
$restarted = Invoke-TestRegistrarAttempt $exhausted 'consumer-a' 'owner-a' 1
if ($restarted.Status -cne 'UI_LOAD_QUEUED') { throw 'C-005 model: a later activation did not restart registration/load reconciliation.' }

# C-008: descriptor drift discards an unsent entry, so restoring that descriptor can queue and reserve it.
$descriptorDrift = New-TestUiLifecycleModel
Set-TestUiRegistration $descriptorDrift 'consumer-a' 'owner-a' 'packet-v1'
if ((Request-TestUiLoad $descriptorDrift 'consumer-a' 'owner-a') -cne 'UI_LOAD_QUEUED') { throw 'C-008 model setup failed to queue v1.' }
Set-TestUiRegistration $descriptorDrift 'consumer-a' 'owner-a' 'packet-v2'
$discarded = Invoke-TestUiPump $descriptorDrift
if ($discarded.Status -cne 'UI_LOAD_IDLE' -or $descriptorDrift.UiLoads.Count -ne 0 -or $descriptorDrift.Reservations.Count -ne 0) {
  throw 'C-008 model: a stale unsent descriptor was retained or treated as reserved.'
}
Set-TestUiRegistration $descriptorDrift 'consumer-a' 'owner-a' 'packet-v1'
$restoredRequest = Request-TestUiLoad $descriptorDrift 'consumer-a' 'owner-a'
$restoredReservation = Invoke-TestUiPump $descriptorDrift
if ($restoredRequest -cne 'UI_LOAD_QUEUED' -or $restoredReservation.Status -cne 'UI_LOAD_RESERVED' -or $descriptorDrift.Reservations.Count -ne 1) {
  throw 'C-008 model: a restored descriptor remained suppressed after stale work was discarded.'
}

# Removing stale owner and descriptor entries must inspect the shifted next element and reserve valid work once.
$staleBeforeValid = New-TestUiLifecycleModel
Set-TestUiRegistration $staleBeforeValid 'stale-owner' 'current-owner' 'owner-packet'
Set-TestUiRegistration $staleBeforeValid 'stale-descriptor' 'owner-b' 'new-packet'
Set-TestUiRegistration $staleBeforeValid 'valid' 'owner-c' 'valid-packet'
Add-TestUiLoad $staleBeforeValid 'stale-owner' 'old-owner' 'owner-packet'
Add-TestUiLoad $staleBeforeValid 'stale-descriptor' 'owner-b' 'old-packet'
Add-TestUiLoad $staleBeforeValid 'valid' 'owner-c' 'valid-packet'
if ((Request-TestUiLoad $staleBeforeValid 'valid' 'owner-c') -cne 'UI_LOAD_ALREADY_REQUESTED') {
  throw 'C-008 model setup failed to restart the pump for valid queued work.'
}
$nextValid = Invoke-TestUiPump $staleBeforeValid
if ($nextValid.Status -cne 'UI_LOAD_RESERVED' -or $nextValid.Packet -cne 'valid-packet' -or $nextValid.Inspected -ne 3 -or
    $staleBeforeValid.UiLoads.Count -ne 1 -or $staleBeforeValid.Reservations.Count -ne 1) {
  throw 'C-008 model: stale removal skipped later valid work, duplicated a reservation, or failed to terminate.'
}

$mutations = @(
  @('Enumerations', 'Int V1 = 1', 'Int V1 = 2'),
  @('Enumerations', 'Int UiLoad = 1', 'Int UiLoad = 2'),
  @('Enumerations', 'Return "VWC_EVT/1|"', 'Return "CUSTOM|"'),
  @('Enumerations', 'Return "canvas.ui.load"', 'Return "custom.type"'),
  @('Registry', 'BuildEventPacket(headers.V1, packetTypes.UiLoad, payload)', 'BuildEventPacket(99, 99, payload)'),
  @('Registry', 'pending >= 32', 'pending >= 320'),
  @('Registry', 'packet == ""', 'False'),
  @('Registry', 'IsPrintableAscii(packet, 1, 512)', 'IsPrintableAscii(packet, 1, 4096)'),
  @('Registry', 'UiLoads[existing].Packet == packet', 'False'),
  @('Registry', 'UiLoads[existing].Owner == owner', 'True'),
  @('Registry', 'result.TimerId = StartUiPumpLocked(now)', 'result.TimerId = 0'),
  @('Registry', 'ticket == UiPumpBase', 'True'),
  @('Registry', 'now < UiNextSubmitTime', 'False'),
  @('Registry', 'UiNextSubmitTime = now + 1.0', 'UiNextSubmitTime = now'),
  @('Registry', 'registration.Owner == entry.Owner', 'True'),
  @('Registry', 'BuildUiLoadPacket(registration) == entry.Packet', 'True'),
  @('Registry', 'UiAppliedActivationRequest == UiActivationRequest && UiActive', 'UiActive'),
  @('Registry', 'UiAppliedActivationRequest == UiActivationRequest && PlayerHudRequested', 'PlayerHudRequested'),
  @('Registry', 'If (entry == None)', 'If (entry != None)'),
  @('Registry', 'ElseIf (!entry.Submitted)', 'ElseIf (entry.Submitted)'),
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
  @('Movie', 'this.parseUiLoad(param1)', 'this.receiveSnapshot(param1)'),
  @('Movie', 'this.matchAsciiPrefix(packet,UI_LOAD_PREFIX)', '1')
)
$mutated = 0
foreach ($mutation in $mutations) {
  $candidateEnumerations = $enumerations
  $candidateRegistry = $registry
  $candidateMovie = $movie
  $original = if ($mutation[0] -eq 'Enumerations') { $enumerations } elseif ($mutation[0] -eq 'Registry') { $registry } else { $movie }
  if (!$original.Contains($mutation[1])) { throw "Mutation did not match: $($mutation[1])" }
  if ($mutation[0] -eq 'Enumerations') { $candidateEnumerations = $enumerations.Replace($mutation[1], $mutation[2]) }
  elseif ($mutation[0] -eq 'Registry') { $candidateRegistry = $registry.Replace($mutation[1], $mutation[2]) }
  else { $candidateMovie = $movie.Replace($mutation[1], $mutation[2]) }
  $caught = $false
  try { Assert-UiLoadSourceContract $candidateEnumerations $candidateRegistry $candidateMovie } catch { $caught = $true }
  if (!$caught) { throw "Unsafe source mutation accepted: $($mutation[1])" }
  $mutated += 1
}
$matrix = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '../Scaleform/canvas/canvas-matrix.psd1')
if ($matrix.UiLoadTransport.EventHeader.Selector -ne 1 -or $matrix.UiLoadTransport.EventHeader.Wire -cne 'VWC_EVT/1|' -or
    $matrix.UiLoadTransport.PacketType.Selector -ne 1 -or $matrix.UiLoadTransport.PacketType.Wire -cne 'canvas.ui.load' -or
    $matrix.UiLoadTransport.Protocol -cne $matrix.UiLoadTransport.PacketType.Wire -or
    $matrix.UiLoadTransport.MaxCharacters -ne 512 -or $matrix.UiLoadTransport.MaxPending -ne 32 -or
    $matrix.UiLoadTransport.MinimumIntervalSeconds -ne 1 -or $matrix.UiLoadTransport.MaxBusyAttempts -ne 20 -or
    $matrix.UiLoadTransport.Target -cne 'PlayerHud') { throw 'Matrix load budgets differ from source.' }
Write-Output "UI load reference vectors and C-005/C-008 lifecycle models passed; $rejected malformed packets and $mutated unsafe source mutations rejected. No Papyrus/Scaleform VM or delivery acceptance is implied."
