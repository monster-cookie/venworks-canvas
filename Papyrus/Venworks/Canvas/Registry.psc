ScriptName Venworks:Canvas:Registry Extends Venworks:Canvas:Base:BaseQuest

Struct ConsumerRegistration
  Quest Owner
  String ConsumerId
  String DisplayName
  String NormalMovieUrl
  String LargeMovieUrl
  Int DescriptorVersion
EndStruct

; Per-call receipt, never shared as registry state. Diagnostics are emitted only after all guards are released.
Struct OperationResult
  String Status
  String ConsumerId
  String Detail
  String UiLoad
  Int DescriptorVersion = 0
  Int Count = -1
  Int Pruned = 0
  Bool Initialized = False
  Bool UpdateApplied = False
  Int TimerId = 0
  Int Epoch = 0
  String Packet
EndStruct

; Presentation bookkeeping only. Reset on HUD activation; never replaces the persistent registration array.
Struct UiLoadEntry
  Quest Owner
  String ConsumerId
  String Packet
  Bool Submitted = False
EndStruct

ConsumerRegistration[] Property Consumers Auto Mandatory
UiLoadEntry[] UiLoads
Bool PlayerHudRequested = False
Bool UiActive = False
Int UiEpoch = 0
Int UiActivationRequest = 0
Int UiAppliedActivationRequest = -1
Int UiTimerSerial = 1000
Int UiPumpBase = 0
Float UiNextSubmitTime = 0.0
Float UiPumpExpiresAt = 0.0
Int MessageId = 0
Bool MenuSubscriptionsInitialized = False
Bool DisabledPublicationLogged = False
Guard RegistryGuard ProtectsFunctionLogic

String ModuleName = "Canvas:Registry"
Int MaxConsumerIdCharacters = 64
Int MaxDisplayNameCharacters = 80
Int MaxConsumerMovieUrlCharacters = 180
Int MaxSnapshotPageCharacters = 4096
Int MaxSnapshotPagePayloadCharacters = 3600

; Reports this packaged script's runtime quest binding only; does not initialize storage or request work.
String Function ConsoleResolve() Global
  Venworks:Canvas:Registry target = ResolveConsoleRegistry()
  If (target == None)
    Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: Registry.ConsoleResolve | " + "CONSOLE_RESOLVE_FAILED")
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: Registry.ConsoleResolve | " + "CONSOLE_RESOLVED")
  Return "CONSOLE_RESOLVED"
EndFunction

; Explicit host bootstrap; callbacks and logging stay outside the existing nonblocking storage guard.
String Function ConsoleEnsureStorage() Global
  Venworks:Canvas:Registry target = ResolveConsoleRegistry()
  If (target == None)
    Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: Registry.ConsoleEnsureStorage | " + "CONSOLE_RESOLVE_FAILED")
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  target.EnsureMenuSubscriptions()
  OperationResult result = target.TryEnsureStorage()
  target.LogOperation(result)
  LogConsoleRegistry("ConsoleEnsureStorage", "CONSOLE_RESULT | Status=" + result.Status)
  Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: Registry.ConsoleEnsureStorage | " + result.Status)
  Return result.Status
EndFunction

; Resolve the permanent file-local identity on every explicit call; no Editor ID, cached target or external prefix.
Venworks:Canvas:Registry Function ResolveConsoleRegistry() Global
  LogConsoleRegistry("ResolveConsoleRegistry", "CONSOLE_BEGIN | Plugin=Venworks-Canvas.esm | LocalId=0x000800")
  Form targetForm = Game.GetFormFromFile(0x000800, "Venworks-Canvas.esm")
  If (targetForm == None)
    LogConsoleRegistry("ResolveConsoleRegistry", "CONSOLE_TARGET_NOT_FOUND")
    Return None
  EndIf
  Venworks:Canvas:Registry target = targetForm as Venworks:Canvas:Registry
  If (target == None)
    LogConsoleRegistry("ResolveConsoleRegistry", "CONSOLE_SCRIPT_NOT_BOUND | Form=" + targetForm)
    Return None
  EndIf
  LogConsoleRegistry("ResolveConsoleRegistry", "CONSOLE_RESOLVED | Form=" + targetForm + " | RuntimeFormId=" + targetForm.GetFormID())
  Return target
EndFunction

; Global diagnostics cannot use instance logging or saved ModuleName; emit the same bounded build marker to both logs.
Function LogConsoleRegistry(String functionName, String logMessage) Global
  Venworks:Core:Enumerations:LogSeverity severityTable = new Venworks:Core:Enumerations:LogSeverity
  Venworks:Core:Logging.LogUser(creationName="Venworks-Canvas", moduleName="Canvas:Registry", functionName=functionName, logMessage="VWCANVAS_CONSOLE/1 | " + logMessage, severity=severityTable.Info)
EndFunction

; OnInit may execute around the initial save-load/revert. Install callbacks only; do not enter a guard here.
Event OnInit()
  EnsureMenuSubscriptions()
EndEvent

; A supported HUD opening starts deferred reconciliation, never a guarded OnInit continuation.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (menuName == "HUDMenu")
    PlayerHudRequested = opening
    UiActivationRequest += 1
    StartTimer(0.2, 100)
  EndIf
  If (opening)
    StartTimer(0.2, 1)
  EndIf
EndEvent

; Timer IDs carry the bounded attempt number; no saved "active" flag can permanently suppress work.
Event OnTimer(Int aiTimerID)
  If (aiTimerID >= 100 && aiTimerID < 120)
    RefreshUiActivation(aiTimerID)
    Return
  ElseIf (aiTimerID >= 1001)
    PumpUiLoad(aiTimerID)
    Return
  EndIf
  If (aiTimerID < 1 || aiTimerID > 20)
    Return
  EndIf
  OperationResult result = TryEnsureStorage()
  LogOperation(result)
  If (IsDeferred(result.Status))
    If (aiTimerID < 20)
      StartTimer(0.5, aiTimerID + 1)
    Else
      LogUserWarning(ModuleName, "OnTimer", "REGISTRY_RETRY_EXHAUSTED | Deferred until a later HUD opening or explicit caller.")
    EndIf
  EndIf
EndEvent

; Allocates a caller-owned result. A skipped TryLockGuard keeps its explicit deferred default.
OperationResult Function NewResult(String status) Global
  OperationResult result = new OperationResult
  result.Status = status
  Return result
EndFunction

; Only these statuses acknowledge a stored descriptor; busy and negative tests are not acknowledgements.
Bool Function IsRegistrationAccepted(String status) Global
  Return status == "REGISTRATION_ACCEPTED" || status == "REGISTRATION_UPDATED" || status == "REGISTRATION_UNCHANGED"
EndFunction

; Busy/unavailable outcomes are distinct from terminal descriptor or ownership rejection.
Bool Function IsDeferred(String status) Global
  Return status == "DEFERRED_REGISTRY_BUSY" || status == "DEFERRED_ATTEMPT_BUSY" || status == "DEFERRED_REGISTRY_UNAVAILABLE" || status == "DEFERRED_UI_INACTIVE" || status == "DEFERRED_UI_QUEUE_FULL"
EndFunction

; Validation is outside RegistryGuard; registration completes in one acquired transaction.
; Does not log, subscribe, wait, call consumers, or publish. Callers must log the receipt outside their own guards.
OperationResult Function TryRegisterConsumer(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion)
  OperationResult result = NewResult("DEFERRED_REGISTRY_BUSY")
  result.Detail = GetDescriptorRejectionReason(owner, consumerId, displayName, normalMovieUrl, largeMovieUrl, descriptorVersion)
  If (result.Detail != "")
    result.Status = "REGISTRATION_REJECTED"
    Return result
  EndIf
  result.ConsumerId = Venworks:Core:Utilities:UUID.Normalize(consumerId)
  result.DescriptorVersion = descriptorVersion
  TryLockGuard RegistryGuard
    EnsureStorageLocked(result)
    result.Status = RegisterConsumerLocked(owner, result.ConsumerId, displayName, normalMovieUrl, largeMovieUrl, descriptorVersion)
    result.Count = Consumers.Length
  EndTryLockGuard
  Return result
EndFunction

; Internal worker: the supplied descriptor is validated and RegistryGuard is held.
String Function RegisterConsumerLocked(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion)
  Int existingIndex = FindConsumerIndexLocked(consumerId)
  If (existingIndex >= 0)
    If (Consumers[existingIndex].Owner != owner)
      Return "REJECTED_OWNER_MISMATCH"
    EndIf
    Bool changed = Consumers[existingIndex].DisplayName != displayName || Consumers[existingIndex].NormalMovieUrl != normalMovieUrl || Consumers[existingIndex].LargeMovieUrl != largeMovieUrl || Consumers[existingIndex].DescriptorVersion != descriptorVersion
    If (!changed)
      Return "REGISTRATION_UNCHANGED"
    EndIf
    Consumers[existingIndex].DisplayName = displayName
    Consumers[existingIndex].NormalMovieUrl = normalMovieUrl
    Consumers[existingIndex].LargeMovieUrl = largeMovieUrl
    Consumers[existingIndex].DescriptorVersion = descriptorVersion
    Return "REGISTRATION_UPDATED"
  EndIf
  ConsumerRegistration registration = new ConsumerRegistration
  registration.Owner = owner
  registration.ConsumerId = consumerId
  registration.DisplayName = displayName
  registration.NormalMovieUrl = normalMovieUrl
  registration.LargeMovieUrl = largeMovieUrl
  registration.DescriptorVersion = descriptorVersion
  Consumers.Add(registration)
  Return "REGISTRATION_ACCEPTED"
EndFunction

; Nonblocking removal; ownership is checked in the same transaction as removal. No diagnostic calls occur inside it.
OperationResult Function TryUnregisterConsumer(Quest owner, String consumerId)
  OperationResult result = NewResult("DEFERRED_REGISTRY_BUSY")
  If (owner == None || !IsConsumerIdValid(consumerId))
    result.Status = "REJECTED_CONSUMER_ID"
    Return result
  EndIf
  result.ConsumerId = Venworks:Core:Utilities:UUID.Normalize(consumerId)
  TryLockGuard RegistryGuard
    EnsureStorageLocked(result)
    result.Status = UnregisterConsumerLocked(owner, result.ConsumerId)
    result.Count = Consumers.Length
  EndTryLockGuard
  Return result
EndFunction

; Internal owner-checked removal under RegistryGuard; absent IDs are successful no-ops.
String Function UnregisterConsumerLocked(Quest owner, String consumerId)
  Int index = FindConsumerIndexLocked(consumerId)
  If (index < 0)
    Return "UNREGISTERED"
  EndIf
  If (Consumers[index].Owner != owner)
    Return "REJECTED_OWNER_MISMATCH"
  EndIf
  Consumers.Remove(index)
  Return "UNREGISTERED"
EndFunction

; Reads only the stored owner/ID pair. Never queues, schedules, or transmits a UI request.
OperationResult Function TryCheckUiLoadRequest(Quest owner, String consumerId)
  OperationResult result = NewResult("DEFERRED_REGISTRY_BUSY")
  If (owner == None)
    result.Status = "REJECTED_OWNER_UNAVAILABLE"
    Return result
  EndIf
  If (!IsConsumerIdValid(consumerId))
    result.Status = "REJECTED_CONSUMER_ID"
    Return result
  EndIf
  result.ConsumerId = Venworks:Core:Utilities:UUID.Normalize(consumerId)
  TryLockGuard RegistryGuard
    EnsureStorageLocked(result)
    result.Status = RequestUiLoadLocked(owner, result.ConsumerId)
    result.Count = Consumers.Length
  EndTryLockGuard
  Return result
EndFunction

; Internal read under RegistryGuard; no replacement paths and no UI transport.
String Function RequestUiLoadLocked(Quest owner, String consumerId)
  Int index = FindConsumerIndexLocked(consumerId)
  If (index < 0)
    Return "REJECTED_NOT_REGISTERED"
  EndIf
  If (Consumers[index].Owner != owner)
    Return "REJECTED_OWNER_MISMATCH"
  EndIf
  Return "REGISTERED_UI_LOAD_ELIGIBLE"
EndFunction

; Explicit second step after registration. Call outside every caller guard; scheduling occurs after RegistryGuard.
OperationResult Function TryRequestUiLoad(Quest owner, String consumerId)
  Float now = Utility.GetCurrentRealTime()
  OperationResult result = NewResult("DEFERRED_REGISTRY_BUSY")
  If (owner == None)
    result.Status = "REJECTED_OWNER_UNAVAILABLE"
    Return result
  EndIf
  If (!IsConsumerIdValid(consumerId))
    result.Status = "REJECTED_CONSUMER_ID"
    Return result
  EndIf
  result.ConsumerId = Venworks:Core:Utilities:UUID.Normalize(consumerId)
  TryLockGuard RegistryGuard
    EnsureStorageLocked(result)
    result.Status = RequestUiLoadLocked(owner, result.ConsumerId)
    If (result.Status == "REGISTERED_UI_LOAD_ELIGIBLE")
      QueueUiLoadLocked(owner, result, now)
    EndIf
    result.Count = Consumers.Length
  EndTryLockGuard
  ScheduleUiPump(result)
  Return result
EndFunction

; A supported menu event defers presentation reset to a bounded timer, not OnInit or a waiting guard.
Function RefreshUiActivation(Int timerId)
  OperationResult result = NewResult("DEFERRED_REGISTRY_BUSY")
  TryLockGuard RegistryGuard
    result.Status = "UI_ACTIVATION_UNCHANGED"
    If (UiAppliedActivationRequest != UiActivationRequest || UiActive != PlayerHudRequested)
      UiEpoch += 1
      UiActive = PlayerHudRequested
      UiLoads = new UiLoadEntry[0]
      UiPumpBase = 0
      UiAppliedActivationRequest = UiActivationRequest
      result.Status = "UI_ACTIVATION_RESET"
    EndIf
    result.Epoch = UiEpoch
  EndTryLockGuard
  LogOperation(result)
  If (result.Status == "DEFERRED_REGISTRY_BUSY" && timerId < 119)
    StartTimer(0.5, timerId + 1)
  EndIf
EndFunction

; Maps validated enum selectors to Canvas-owned wire text; callers cannot supply a raw header or packet type.
String Function BuildEventPacket(Int eventHeader, Int packetType, String payload)
  String eventHeaderText = Venworks:Canvas:Enumerations.ResolveEventHeader(eventHeader)
  String packetTypeText = Venworks:Canvas:Enumerations.ResolvePacketType(packetType)
  If (eventHeaderText == "" || packetTypeText == "")
    Return ""
  EndIf
  Return eventHeaderText + packetTypeText + "|" + payload
EndFunction

; Copies only the current validated descriptor into a bounded packet; display names are not bridge data.
String Function BuildUiLoadPacket(ConsumerRegistration registration)
  Venworks:Canvas:Enumerations:EventHeader headers = new Venworks:Canvas:Enumerations:EventHeader
  Venworks:Canvas:Enumerations:PacketType packetTypes = new Venworks:Canvas:Enumerations:PacketType
  String payload = EncodeField("1") + EncodeField(registration.ConsumerId) + EncodeField(registration.DescriptorVersion as String) + EncodeField(registration.NormalMovieUrl) + EncodeField(registration.LargeMovieUrl)
  Return BuildEventPacket(headers.V1, packetTypes.UiLoad, payload)
EndFunction

; Caller holds RegistryGuard. Coalesce one entry per UUID, cap pending work rather than registrations.
Function QueueUiLoadLocked(Quest owner, OperationResult result, Float now)
  If (!UiActive || !PlayerHudRequested || UiLoads == None)
    result.Status = "DEFERRED_UI_INACTIVE"
    Return
  EndIf
  Int registeredIndex = FindConsumerIndexLocked(result.ConsumerId)
  ; A saved or exhausted timer ticket is not a permanent gate, including after a process-clock reset.
  If (UiPumpBase != 0 && (now >= UiPumpExpiresAt || UiPumpExpiresAt - now > 30.0))
    UiPumpBase = 0
  EndIf
  ConsumerRegistration registration = Consumers[registeredIndex]
  If (!IsDescriptorValid(owner, registration.ConsumerId, registration.DisplayName, registration.NormalMovieUrl, registration.LargeMovieUrl, registration.DescriptorVersion))
    result.Status = "REJECTED_UI_DESCRIPTOR"
    Return
  EndIf
  String packet = BuildUiLoadPacket(registration)
  If (packet == "")
    result.Status = "REJECTED_UI_PROTOCOL"
    Return
  EndIf
  If (!IsPrintableAscii(packet, 1, 512))
    result.Status = "REJECTED_UI_PACKET"
    Return
  EndIf
  Int existing = -1
  Int pending = 0
  Int index = UiLoads.Length - 1
  While (index >= 0)
    If (UiLoads[index] == None)
      UiLoads.Remove(index)
    ElseIf (UiLoads[index].Owner == None || FindConsumerIndexLocked(UiLoads[index].ConsumerId) < 0)
      UiLoads.Remove(index)
    EndIf
    index -= 1
  EndWhile
  index = 0
  While (index < UiLoads.Length)
    If (UiLoads[index].ConsumerId == result.ConsumerId)
      existing = index
    EndIf
    If (!UiLoads[index].Submitted)
      pending += 1
    EndIf
    index += 1
  EndWhile
  If (existing >= 0)
    If (UiLoads[existing].Owner == owner && UiLoads[existing].Packet == packet)
      result.Status = "UI_LOAD_ALREADY_REQUESTED"
      ; Restart an exhausted local pump, but never resubmit an already reserved packet.
      If (!UiLoads[existing].Submitted && UiPumpBase == 0)
        result.TimerId = StartUiPumpLocked(now)
      EndIf
      Return
    EndIf
  EndIf
  If (pending >= 32 && (existing < 0 || UiLoads[existing].Submitted))
    result.Status = "DEFERRED_UI_QUEUE_FULL"
    Return
  EndIf
  UiLoadEntry entry = new UiLoadEntry
  entry.Owner = owner
  entry.ConsumerId = result.ConsumerId
  entry.Packet = packet
  If (existing >= 0)
    UiLoads[existing] = entry
  Else
    UiLoads.Add(entry)
  EndIf
  result.Status = "UI_LOAD_QUEUED"
  result.DescriptorVersion = registration.DescriptorVersion
  If (UiPumpBase == 0)
    result.TimerId = StartUiPumpLocked(now)
  EndIf
EndFunction

; Monotonic timer tickets make duplicate or superseded timer callbacks inert. Caller holds RegistryGuard.
Int Function StartUiPumpLocked(Float now)
  UiTimerSerial += 100
  If (UiTimerSerial > 2000000000)
    UiTimerSerial = 1000
  EndIf
  UiPumpBase = UiTimerSerial
  UiPumpExpiresAt = now + 30.0
  Return UiPumpBase + 1
EndFunction

; Timer work is never scheduled while holding a registry or registrar guard.
Function ScheduleUiPump(OperationResult result)
  If (result.TimerId > 0)
    StartTimer(1.0, result.TimerId)
  EndIf
EndFunction

; One owner-checked, rate-limited reservation; a missed UI event is never retried for lack of an ACK.
Function PumpUiLoad(Int timerId)
  Int attempt = timerId % 100
  If (attempt >= 51 && attempt <= 70)
    FinishUiLoad(timerId)
    Return
  EndIf
  If (attempt < 1 || attempt > 20)
    Return
  EndIf
  Float now = Utility.GetCurrentRealTime()
  OperationResult result = TryTakeUiLoad(timerId - attempt, now)
  If (result.Status == "UI_LOAD_RESERVED")
    If (PlayerHudRequested && result.Epoch == UiEpoch)
      Game.ShowCustomWatchAlert(result.Packet)
      result.Status = "UI_LOAD_SUBMITTED"
    Else
      result.Status = "UI_LOAD_CANCELLED_ACTIVATION"
    EndIf
    FinishUiLoad(timerId - attempt + 51)
  EndIf
  LogOperation(result)
  ScheduleUiPump(result)
  If (result.Status == "DEFERRED_REGISTRY_BUSY" || result.Status == "DEFERRED_UI_RATE_LIMIT")
    If (attempt < 20)
      StartTimer(0.5, timerId + 1)
    Else
      ReleaseUiPump(timerId - attempt)
      LogUserWarning(ModuleName, "PumpUiLoad", "UI_LOAD_RETRY_EXHAUSTED | Later explicit request or HUD activation may retry; no delivery ACK.")
    EndIf
  EndIf
EndFunction

; Drops stale owners/descriptors and atomically takes only one packet. No native transport is called here.
OperationResult Function TryTakeUiLoad(Int ticket, Float now)
  OperationResult result = NewResult("DEFERRED_REGISTRY_BUSY")
  TryLockGuard RegistryGuard
    result.Status = "UI_LOAD_IDLE"
    If (UiActive && PlayerHudRequested && UiLoads != None && ticket == UiPumpBase)
      EnsureStorageLocked(result)
      If (now < UiNextSubmitTime && UiNextSubmitTime - now <= 1.0)
        result.Status = "DEFERRED_UI_RATE_LIMIT"
      Else
        UiPumpBase = 0
        Int index = 0
        While (index < UiLoads.Length && result.Packet == "")
          UiLoadEntry entry = UiLoads[index]
          If (entry != None && !entry.Submitted)
            Int registeredIndex = FindConsumerIndexLocked(entry.ConsumerId)
            If (entry.Owner != None && registeredIndex >= 0)
              ConsumerRegistration registration = Consumers[registeredIndex]
              If (registration.Owner == entry.Owner && BuildUiLoadPacket(registration) == entry.Packet)
                result.Packet = entry.Packet
                result.ConsumerId = entry.ConsumerId
                result.DescriptorVersion = registration.DescriptorVersion
                result.Epoch = UiEpoch
                result.Status = "UI_LOAD_RESERVED"
                UiNextSubmitTime = now + 1.0
                ; Keep an expiring ticket across submission so another caller cannot start a concurrent pump.
                UiPumpBase = -ticket
              EndIf
            EndIf
            entry.Submitted = True
          EndIf
          index += 1
        EndWhile
      EndIf
    EndIf
  EndTryLockGuard
  Return result
EndFunction

; Complete a reservation after native submission, spacing the next timer from completion rather than reservation.
Function FinishUiLoad(Int timerId)
  Int attempt = timerId % 100
  Int ticket = timerId - attempt
  Float now = Utility.GetCurrentRealTime()
  OperationResult result = NewResult("DEFERRED_REGISTRY_BUSY")
  TryLockGuard RegistryGuard
    result.Status = "UI_LOAD_IDLE"
    If (UiPumpBase == -ticket)
      UiPumpBase = 0
      UiNextSubmitTime = now + 1.0
      If (UiActive && PlayerHudRequested && UiLoads != None)
        Int index = 0
        While (index < UiLoads.Length && result.TimerId == 0)
          If (UiLoads[index] != None && !UiLoads[index].Submitted)
            result.TimerId = StartUiPumpLocked(now)
          EndIf
          index += 1
        EndWhile
      EndIf
    EndIf
  EndTryLockGuard
  ScheduleUiPump(result)
  If (result.Status == "DEFERRED_REGISTRY_BUSY")
    If (attempt < 70)
      StartTimer(0.5, timerId + 1)
    Else
      ReleaseUiPump(ticket)
      LogUserWarning(ModuleName, "FinishUiLoad", "UI_LOAD_RETRY_EXHAUSTED | Submission is not retried; remaining queued requests await recovery.")
    EndIf
  EndIf
EndFunction

; Bounded exhaustion must not leave a permanent active latch; failure here is recovered by HUD activation.
Function ReleaseUiPump(Int ticket)
  TryLockGuard RegistryGuard
    If (UiPumpBase == ticket || UiPumpBase == -ticket)
      UiPumpBase = 0
    EndIf
  EndTryLockGuard
EndFunction

; Read-only diagnostic wrapper retained separately from the transmitting RequestUiLoad API.
String Function CheckUiLoadRequest(Quest owner, String consumerId)
  OperationResult result = TryCheckUiLoadRequest(owner, consumerId)
  LogOperation(result)
  Return result.Status
EndFunction

; Disabled compatibility entry point for saved callers. Always returns false; no snapshot is built, queued, or submitted.
Bool Function PublishSnapshot(String reason = "manual")
  LogDisabledPublication()
  Return False
EndFunction

; Disabled compatibility entry point for saved callers. Ignores caller text and logs suppression at most once per saved host.
Function PublishDiagnostic(String diagnostic)
  LogDisabledPublication()
EndFunction

; Records suppressed snapshot publication once without creating bridge traffic or repeating caller-controlled diagnostics.
Function LogDisabledPublication()
  If (!DisabledPublicationLogged)
    DisabledPublicationLogged = True
    LogUserWarning(ModuleName, "LogDisabledPublication", "SNAPSHOT WATCH BRIDGE DISABLED | Snapshot/diagnostic publication suppressed.")
  EndIf
EndFunction

; Returns an empty string for a valid descriptor, otherwise a field-specific reason including actual runtime limits.
String Function GetDescriptorRejectionReason(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion)
  If (owner == None)
    Return "owner=None"
  EndIf
  If (descriptorVersion < 1 || descriptorVersion > 9999)
    Return "descriptorVersion=" + descriptorVersion + " | range=1..9999"
  EndIf
  String rejection = GetConsumerIdRejectionReason(consumerId)
  If (rejection != "")
    Return rejection
  EndIf
  rejection = GetPrintableAsciiRejectionReason(displayName, 1, MaxDisplayNameCharacters, "displayName")
  If (rejection != "")
    Return rejection
  EndIf
  rejection = GetPrintableAsciiRejectionReason(normalMovieUrl, 1, MaxConsumerMovieUrlCharacters, "normalMovieUrl")
  If (rejection != "")
    Return rejection
  EndIf
  rejection = GetPrintableAsciiRejectionReason(largeMovieUrl, 1, MaxConsumerMovieUrlCharacters, "largeMovieUrl")
  If (rejection != "")
    Return rejection
  EndIf
  If (!IsMoviePairValid(normalMovieUrl, largeMovieUrl))
    Return "movie paths must share one safe local asset namespace"
  EndIf
  Return ""
EndFunction

; Returns whether a proposed owner and descriptor satisfy the canonical contract; validation has no publication side effects.
Bool Function IsDescriptorValid(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion)
  Return GetDescriptorRejectionReason(owner, consumerId, displayName, normalMovieUrl, largeMovieUrl, descriptorVersion) == ""
EndFunction

; Returns whether the supplied UUID is structurally valid and non-nil, regardless of accepted text shape or case.
Bool Function IsConsumerIdValid(String consumerId)
  Return GetConsumerIdRejectionReason(consumerId) == ""
EndFunction

; Returns an empty string for a non-nil UUID, or a bounded reason. Never generates an identity.
String Function GetConsumerIdRejectionReason(String consumerId)
  If (!Venworks:Core:Utilities:UUID.IsValid(consumerId))
    Return "consumerId invalid UUID"
  EndIf
  If (Venworks:Core:Utilities:UUID.IsNil(consumerId))
    Return "consumerId nil UUID"
  EndIf
  Return ""
EndFunction

; Returns whether one character code is an ASCII letter in either case or a decimal digit.
Bool Function IsAsciiLetterOrDigit(Int character)
  Return (character >= 97 && character <= 122) || (character >= 65 && character <= 90) || (character >= 48 && character <= 57)
EndFunction

; Returns whether a value has a character count inside the supplied bounds and contains only printable ASCII.
Bool Function IsPrintableAscii(String value, Int minimumLength, Int maximumLength)
  Return GetPrintableAsciiRejectionReason(value, minimumLength, maximumLength, "value") == ""
EndFunction

; Returns an empty string for printable ASCII, otherwise its actual length/limits or first invalid character; does not echo the value.
String Function GetPrintableAsciiRejectionReason(String value, Int minimumLength, Int maximumLength, String fieldName)
  Int[] characters = Utility.SplitStringChars(value)
  If (characters == None)
    Return fieldName + " split=None | range=" + minimumLength + ".." + maximumLength
  EndIf
  If (characters.Length < minimumLength || characters.Length > maximumLength)
    Return fieldName + " length=" + characters.Length + " | range=" + minimumLength + ".." + maximumLength
  EndIf
  Int index = 0
  While (index < characters.Length)
    If (characters[index] < 32 || characters[index] > 126)
      Return fieldName + " character | index=" + index + " | code=" + characters[index]
    EndIf
    index += 1
  EndWhile
  Return ""
EndFunction

; Encodes one value as a decimal character length followed by a colon and its unescaped contents.
String Function EncodeField(String value)
  Return GetCharacterCount(value) + ":" + value
EndFunction

; Returns the Papyrus character count for a string, treating an unavailable split result as zero.
Int Function GetCharacterCount(String value)
  Int[] characters = Utility.SplitStringChars(value)
  If (characters == None)
    Return 0
  EndIf
  Return characters.Length
EndFunction

; Repairs only missing storage and prunes invalid rows while RegistryGuard is held. The receipt carries diagnostics out.
Function EnsureStorageLocked(OperationResult result)
  If (Consumers == None)
    Consumers = new ConsumerRegistration[0]
    result.Initialized = True
  EndIf
  Int index = Consumers.Length - 1
  While (index >= 0)
    If (Consumers[index] == None)
      Consumers.Remove(index)
      result.Pruned += 1
    ElseIf (Consumers[index].Owner == None)
      Consumers.Remove(index)
      result.Pruned += 1
    EndIf
    index -= 1
  EndWhile
EndFunction

; Idempotent native subscriptions deliberately occur outside all guards, including the registrar guard.
Function EnsureMenuSubscriptions()
  If (!MenuSubscriptionsInitialized)
    RegisterForMenuOpenCloseEvent("HUDMenu")
    RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
    MenuSubscriptionsInitialized = True
    LogUserInformational(ModuleName, "EnsureMenuSubscriptions", "Registered HUD callbacks; explicit load-only transport.")
  EndIf
EndFunction

; Internal lookup of a complete record; caller holds RegistryGuard and has repaired storage.
Int Function FindConsumerIndexLocked(String consumerId)
  Int index = 0
  While (index < Consumers.Length)
    If (Venworks:Core:Utilities:UUID.AreEqual(Consumers[index].ConsumerId, consumerId))
      Return index
    EndIf
    index += 1
  EndWhile
  Return -1
EndFunction

; Compatibility Boolean: true means stored; false includes busy. New consumers use the explicit TryRegisterConsumer receipt.
Bool Function RegisterConsumer(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion)
  EnsureMenuSubscriptions()
  OperationResult result = TryRegisterConsumer(owner, consumerId, displayName, normalMovieUrl, largeMovieUrl, descriptorVersion)
  LogOperation(result)
  Return IsRegistrationAccepted(result.Status)
EndFunction

; Compatibility Boolean: false includes busy, not solely ownership rejection. Use TryUnregisterConsumer for distinct outcomes.
Bool Function UnregisterConsumer(Quest owner, String consumerId)
  OperationResult result = TryUnregisterConsumer(owner, consumerId)
  LogOperation(result)
  Return result.Status == "UNREGISTERED"
EndFunction

; Explicit second step: queues a validated load request, never promises delivery or rendering.
String Function RequestUiLoad(Quest owner, String consumerId)
  OperationResult result = TryRequestUiLoad(owner, consumerId)
  LogOperation(result)
  Return result.Status
EndFunction

; A single nonblocking repair/count operation. Busy is not an empty registry.
OperationResult Function TryEnsureStorage()
  OperationResult result = NewResult("DEFERRED_REGISTRY_BUSY")
  TryLockGuard RegistryGuard
    EnsureStorageLocked(result)
    result.Status = "REGISTRY_READY"
    result.Count = Consumers.Length
  EndTryLockGuard
  Return result
EndFunction

; Explicit bootstrap for an old host-only save with missing callbacks. Never replaces valid storage.
Bool Function EnsureStorage()
  EnsureMenuSubscriptions()
  OperationResult result = TryEnsureStorage()
  LogOperation(result)
  Return result.Status == "REGISTRY_READY"
EndFunction

; Returns -2 for busy, -1 for absent, or the matching index. The returned index is not a transaction lease.
Int Function FindConsumerIndex(String consumerId)
  OperationResult result = NewResult("DEFERRED_REGISTRY_BUSY")
  Int index = -2
  TryLockGuard RegistryGuard
    EnsureStorageLocked(result)
    index = FindConsumerIndexLocked(consumerId)
  EndTryLockGuard
  Return index
EndFunction

; Returns -1 when busy rather than inventing a zero count.
Int Function GetConsumerCount()
  OperationResult result = TryEnsureStorage()
  Return result.Count
EndFunction

; Logs a caller-owned snapshot only after every guard has ended. Count is from that transaction, not a fresh read.
Function LogOperation(OperationResult result)
  If (result.Initialized)
    LogUserWarning(ModuleName, "LogOperation", "Initialized missing consumer registry storage.")
  EndIf
  If (result.Pruned > 0)
    LogUserInformational(ModuleName, "LogOperation", "REGISTRY_PRUNED | Records=" + result.Pruned)
  EndIf
  String diagnosticText = result.Status + " | Consumer=" + result.ConsumerId + " | Version=" + result.DescriptorVersion + " | Consumers=" + result.Count + " | Epoch=" + result.Epoch + " | " + result.Detail
  If (IsRegistrationAccepted(result.Status) || result.Status == "REGISTRY_READY" || result.Status == "UNREGISTERED" || result.Status == "REGISTERED_UI_LOAD_ELIGIBLE" || result.Status == "UI_LOAD_QUEUED" || result.Status == "UI_LOAD_ALREADY_REQUESTED" || result.Status == "UI_LOAD_SUBMITTED" || result.Status == "UI_ACTIVATION_RESET" || result.Status == "UI_LOAD_IDLE")
    LogUserInformational(ModuleName, "LogOperation", diagnosticText)
  Else
    LogUserWarning(ModuleName, "LogOperation", diagnosticText)
  EndIf
EndFunction

; Folds one ASCII capital to lowercase for case-insensitive archive URL validation.
Int Function FoldAscii(Int character)
  If (character >= 65 && character <= 90)
    Return character + 32
  EndIf
  Return character
EndFunction

; Validates both local loader paths independently of the UUID, and requires one identical asset namespace.
Bool Function IsMoviePairValid(String normalPath, String largePath)
  If (!IsMoviePathValid(normalPath, "/normal.swf") || !IsMoviePathValid(largePath, "/large.swf"))
    Return False
  EndIf
  Int[] normal = Utility.SplitStringChars(normalPath)
  Int[] large = Utility.SplitStringChars(largePath)
  ; /normal.swf has 11 characters; /large.swf has 10.
  If (normal.Length - 11 != large.Length - 10)
    Return False
  EndIf
  Int index = 0
  While (index < normal.Length - 11)
    If (FoldAscii(normal[index]) != FoldAscii(large[index]))
      Return False
    EndIf
    index += 1
  EndWhile
  Return True
EndFunction

; Allows only VenworksCanvas/Consumers/<ASCII-namespace>/<selected-movie>. No protocol, traversal, drives or extra segments.
Bool Function IsMoviePathValid(String path, String suffix)
  Int[] chars = Utility.SplitStringChars(path)
  Int[] prefix = Utility.SplitStringChars("VenworksCanvas/Consumers/")
  Int[] ending = Utility.SplitStringChars(suffix)
  If (chars == None || prefix == None || ending == None)
    Return False
  EndIf
  Int namespaceEnd = chars.Length - ending.Length
  Int namespaceLength = namespaceEnd - prefix.Length
  If (namespaceLength < 3 || namespaceLength > 64 || chars.Length > MaxConsumerMovieUrlCharacters)
    Return False
  EndIf
  Int index = 0
  While (index < prefix.Length)
    If (FoldAscii(chars[index]) != FoldAscii(prefix[index]))
      Return False
    EndIf
    index += 1
  EndWhile
  If (!IsAsciiLetterOrDigit(chars[index]) || !IsAsciiLetterOrDigit(chars[namespaceEnd - 1]))
    Return False
  EndIf
  Int previous = -1
  While (index < namespaceEnd)
    Int current = chars[index]
    If ((!IsAsciiLetterOrDigit(current) && current != 45 && current != 46) || (current == 46 && previous == 46))
      Return False
    EndIf
    previous = current
    index += 1
  EndWhile
  index = 0
  While (index < ending.Length)
    If (FoldAscii(chars[namespaceEnd + index]) != FoldAscii(ending[index]))
      Return False
    EndIf
    index += 1
  EndWhile
  Return True
EndFunction
