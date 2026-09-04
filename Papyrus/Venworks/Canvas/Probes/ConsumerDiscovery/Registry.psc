ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:Registry Extends Venworks:Canvas:Base:BaseQuest

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
  Bool Migrated = False
  Bool UpdateApplied = False
EndStruct

ConsumerRegistration[] Property Consumers Auto Mandatory
Int MessageId = 0
Bool MenuSubscriptionsInitialized = False
Bool DisabledPublicationLogged = False
Guard RegistryGuard ProtectsFunctionLogic

String ModuleName = "Probes:ConsumerDiscovery:Registry"
Int MaxConsumerIdCharacters = 64
Int MaxDisplayNameCharacters = 80
Int MaxConsumerMovieUrlCharacters = 180
Int MaxSnapshotPageCharacters = 4096
Int MaxSnapshotPagePayloadCharacters = 3600

; Reports this packaged script's runtime quest binding only; does not initialize storage or request work.
String Function ConsoleResolve() Global
  Venworks:Canvas:Probes:ConsumerDiscovery:Registry target = ResolveConsoleRegistry()
  If (target == None)
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  Return "CONSOLE_RESOLVED"
EndFunction

; Explicit host bootstrap; callbacks and logging stay outside the existing nonblocking storage guard.
String Function ConsoleEnsureStorage() Global
  Venworks:Canvas:Probes:ConsumerDiscovery:Registry target = ResolveConsoleRegistry()
  If (target == None)
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  target.EnsureMenuSubscriptions()
  OperationResult result = target.TryEnsureStorage()
  target.LogOperation(result)
  LogConsoleRegistry("ConsoleEnsureStorage", "CONSOLE_RESULT | Status=" + result.Status)
  Return result.Status
EndFunction

; Resolve the permanent file-local identity on every explicit call; no Editor ID, cached target or external prefix.
Venworks:Canvas:Probes:ConsumerDiscovery:Registry Function ResolveConsoleRegistry() Global
  LogConsoleRegistry("ResolveConsoleRegistry", "CONSOLE_BEGIN | Plugin=Venworks-Canvas-Host.esm | LocalId=0x000800")
  Form targetForm = Game.GetFormFromFile(0x000800, "Venworks-Canvas-Host.esm")
  If (targetForm == None)
    LogConsoleRegistry("ResolveConsoleRegistry", "CONSOLE_TARGET_NOT_FOUND")
    Return None
  EndIf
  Venworks:Canvas:Probes:ConsumerDiscovery:Registry target = targetForm as Venworks:Canvas:Probes:ConsumerDiscovery:Registry
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
  Venworks:Core:Logging.LogUser(creationName="Venworks-Canvas", moduleName="Probes:ConsumerDiscovery:Registry", functionName=functionName, logMessage="VWCANVAS_CONSOLE/1 | " + logMessage, severity=severityTable.Info)
EndFunction

; OnInit may execute around the initial save-load/revert. Install callbacks only; do not enter a guard here.
Event OnInit()
  EnsureMenuSubscriptions()
EndEvent

; A supported HUD opening starts deferred reconciliation, never a guarded OnInit continuation.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening)
    StartTimer(0.2, 1)
  EndIf
EndEvent

; Timer IDs carry the bounded attempt number; no saved "active" flag can permanently suppress work.
Event OnTimer(Int aiTimerID)
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
  Return status == "DEFERRED_REGISTRY_BUSY" || status == "DEFERRED_ATTEMPT_BUSY" || status == "DEFERRED_REGISTRY_UNAVAILABLE"
EndFunction

; Validation is outside RegistryGuard. Optional legacy rekey and registration share one acquired transaction.
; Does not log, subscribe, wait, call consumers, or publish. Callers must log the receipt outside their own guards.
OperationResult Function TryRegisterConsumer(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion, String legacyId = "")
  OperationResult result = NewResult("DEFERRED_REGISTRY_BUSY")
  result.Detail = GetDescriptorRejectionReason(owner, consumerId, displayName, normalMovieUrl, largeMovieUrl, descriptorVersion)
  If (result.Detail != "")
    result.Status = "REGISTRATION_REJECTED"
    Return result
  EndIf
  If (legacyId != "" && Venworks:Core:Utilities:UUID.IsValid(legacyId))
    result.Status = "REGISTRATION_REJECTED"
    result.Detail = "Legacy rekey accepts non-UUID keys only."
    Return result
  EndIf
  result.ConsumerId = Venworks:Core:Utilities:UUID.Normalize(consumerId)
  result.DescriptorVersion = descriptorVersion
  TryLockGuard RegistryGuard
    EnsureStorageLocked(result)
    Bool identityReady = True
    If (legacyId != "")
      identityReady = MigrateConsumerIdentityLocked(owner, legacyId, result.ConsumerId, result)
    EndIf
    If (identityReady)
      result.Status = RegisterConsumerLocked(owner, result.ConsumerId, displayName, normalMovieUrl, largeMovieUrl, descriptorVersion)
    Else
      result.Status = "REGISTRATION_REJECTED"
      result.Detail = "Legacy identity ownership conflict."
    EndIf
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

; Reads only the stored owner/ID pair. The accepted result deliberately queues, submits and loads nothing.
OperationResult Function TryRequestUiLoad(Quest owner, String consumerId)
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
  Return "REGISTERED_TRANSPORT_DISABLED"
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

; Records suppressed legacy publication once without creating bridge traffic or repeating caller-controlled diagnostics.
Function LogDisabledPublication()
  If (!DisabledPublicationLogged)
    DisabledPublicationLogged = True
    LogUserWarning(ModuleName, "LogDisabledPublication", "WATCH BRIDGE DISABLED | Legacy publication suppressed; nothing queued or submitted.")
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
    LogUserInformational(ModuleName, "EnsureMenuSubscriptions", "Registered HUD callbacks; WATCH BRIDGE DISABLED.")
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

; Explicit UI request, returning DEFERRED_REGISTRY_BUSY separately from REJECTED_* and disabled transport.
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

; Compatibility Boolean; false includes busy. Never infer a malformed UUID from this result.
Bool Function MigrateConsumerIdentity(Quest owner, String legacyId, String newId)
  OperationResult result = TryMigrateConsumerIdentity(owner, legacyId, newId)
  LogOperation(result)
  Return result.Status == "IDENTITY_READY"
EndFunction

; Explicit legacy rekey with a distinct busy result. New registrars combine rekey with registration instead.
OperationResult Function TryMigrateConsumerIdentity(Quest owner, String legacyId, String newId)
  OperationResult result = NewResult("DEFERRED_REGISTRY_BUSY")
  If (owner == None || !IsConsumerIdValid(newId) || legacyId == "" || Venworks:Core:Utilities:UUID.IsValid(legacyId))
    result.Status = "REJECTED_IDENTITY"
    Return result
  EndIf
  result.ConsumerId = Venworks:Core:Utilities:UUID.Normalize(newId)
  TryLockGuard RegistryGuard
    EnsureStorageLocked(result)
    If (MigrateConsumerIdentityLocked(owner, legacyId, result.ConsumerId, result))
      result.Status = "IDENTITY_READY"
    Else
      result.Status = "REJECTED_OWNER_MISMATCH"
    EndIf
    result.Count = Consumers.Length
  EndTryLockGuard
  Return result
EndFunction

; Owner-checked rekey under RegistryGuard. Absent legacy rows succeed without mutation; descriptors remain intact.
Bool Function MigrateConsumerIdentityLocked(Quest owner, String legacyId, String newId, OperationResult result)
  Int current = FindConsumerIndexLocked(newId)
  If (current >= 0)
    If (Consumers[current].Owner != owner)
      Return False
    EndIf
  EndIf
  Int index = Consumers.Length - 1
  While (index >= 0)
    If (SameAsciiText(Consumers[index].ConsumerId, legacyId) && Consumers[index].Owner == owner)
      If (current >= 0)
        Consumers.Remove(index)
        If (index < current)
          current -= 1
        EndIf
      Else
        Consumers[index].ConsumerId = newId
        current = index
      EndIf
      result.Migrated = True
    EndIf
    index -= 1
  EndWhile
  Return True
EndFunction

; Logs a caller-owned snapshot only after every guard has ended. Count is from that transaction, not a fresh read.
Function LogOperation(OperationResult result)
  If (result.Initialized)
    LogUserWarning(ModuleName, "LogOperation", "Initialized missing consumer registry storage.")
  EndIf
  If (result.Pruned > 0)
    LogUserInformational(ModuleName, "LogOperation", "REGISTRY_PRUNED | Records=" + result.Pruned)
  EndIf
  If (result.Migrated)
    LogUserInformational(ModuleName, "LogOperation", "LEGACY_ID_MIGRATED | Consumer=" + result.ConsumerId)
  EndIf
  String diagnosticText = result.Status + " | Consumer=" + result.ConsumerId + " | Version=" + result.DescriptorVersion + " | Consumers=" + result.Count + " | " + result.Detail
  If (IsRegistrationAccepted(result.Status) || result.Status == "REGISTRY_READY" || result.Status == "IDENTITY_READY" || result.Status == "UNREGISTERED" || result.Status == "REGISTERED_TRANSPORT_DISABLED")
    LogUserInformational(ModuleName, "LogOperation", diagnosticText)
  Else
    LogUserWarning(ModuleName, "LogOperation", diagnosticText)
  EndIf
EndFunction

; Compares ASCII text numerically, ignoring only A-Z case. Used for legacy fixture names and archive URLs, never display labels.
Bool Function SameAsciiText(String first, String second)
  Int[] left = Utility.SplitStringChars(first)
  Int[] right = Utility.SplitStringChars(second)
  If (left == None || right == None)
    Return False
  EndIf
  If (left.Length != right.Length)
    Return False
  EndIf
  Int index = 0
  While (index < left.Length)
    If (FoldAscii(left[index]) != FoldAscii(right[index]))
      Return False
    EndIf
    index += 1
  EndWhile
  Return True
EndFunction

; Folds one ASCII capital to lowercase without relying on Papyrus string identity.
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
