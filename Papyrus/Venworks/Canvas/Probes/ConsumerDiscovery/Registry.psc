ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:Registry Extends Venworks:Canvas:Base:BaseQuest

Struct ConsumerRegistration
  Quest Owner
  String ConsumerId
  String DisplayName
  String NormalMovieUrl
  String LargeMovieUrl
  Int DescriptorVersion
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

; Initializes persistent storage and menu callbacks without publishing any UI data.
Event OnInit()
  If (!EnsureStorage())
    Return
  EndIf
  LogUserInformational(ModuleName, "OnInit", "REGISTRATION LOG TEST | WATCH BRIDGE DISABLED | Consumers=" + GetConsumerCount())
EndEvent

; Reconciles saved storage and reports its current count once per supported HUD opening; never publishes UI data.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening && EnsureStorage())
    LogUserInformational(ModuleName, "OnMenuOpenCloseEvent", "WATCH BRIDGE DISABLED | Menu=" + menuName + " | Consumers=" + GetConsumerCount())
  EndIf
EndEvent

; Validates and stores one complete descriptor owned by the supplied quest; identical registration is a successful no-op.
; True acknowledges Papyrus registry state only, not UI submission or loading. False is a terminal descriptor/ownership rejection.
Bool Function RegisterConsumerLocked(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion)
  If (!EnsureStorageLocked())
    Return False
  EndIf
  String rejection = GetDescriptorRejectionReason(owner, consumerId, displayName, normalMovieUrl, largeMovieUrl, descriptorVersion)
  If (rejection != "")
    LogUserWarning(ModuleName, "RegisterConsumer", "REGISTRATION_REJECTED | " + rejection + " | Owner=" + owner)
    Return False
  EndIf

  consumerId = Venworks:Core:Utilities:UUID.Normalize(consumerId)
  Int existingIndex = FindConsumerIndexLocked(consumerId)
  If (existingIndex >= 0)
    If (Consumers[existingIndex].Owner != owner)
      LogUserWarning(ModuleName, "RegisterConsumer", "Rejected duplicate consumer ID '" + consumerId + "' from a different owner.")
      Return False
    EndIf

    Bool changed = Consumers[existingIndex].DisplayName != displayName || Consumers[existingIndex].NormalMovieUrl != normalMovieUrl || Consumers[existingIndex].LargeMovieUrl != largeMovieUrl || Consumers[existingIndex].DescriptorVersion != descriptorVersion
    If (!changed)
      LogUserInformational(ModuleName, "RegisterConsumer", "REGISTRATION_UNCHANGED | Consumer=" + consumerId + " | Version=" + descriptorVersion + " | Consumers=" + Consumers.Length)
      Return True
    EndIf

    Consumers[existingIndex].DisplayName = displayName
    Consumers[existingIndex].NormalMovieUrl = normalMovieUrl
    Consumers[existingIndex].LargeMovieUrl = largeMovieUrl
    Consumers[existingIndex].DescriptorVersion = descriptorVersion
    LogUserInformational(ModuleName, "RegisterConsumer", "REGISTRATION_UPDATED | Consumer=" + consumerId + " | Version=" + descriptorVersion + " | Consumers=" + Consumers.Length)
    Return True
  EndIf

  ConsumerRegistration registration = new ConsumerRegistration
  registration.Owner = owner
  registration.ConsumerId = consumerId
  registration.DisplayName = displayName
  registration.NormalMovieUrl = normalMovieUrl
  registration.LargeMovieUrl = largeMovieUrl
  registration.DescriptorVersion = descriptorVersion
  Consumers.Add(registration)
  LogUserInformational(ModuleName, "RegisterConsumer", "REGISTRATION_ACCEPTED | Consumer=" + consumerId + " | Version=" + descriptorVersion + " | Consumers=" + Consumers.Length)
  Return True
EndFunction

; Removes one consumer when the supplied quest owns its ID, without publishing UI data.
; Returns true when the consumer is absent or removed, and false when another quest owns the ID.
Bool Function UnregisterConsumerLocked(Quest owner, String consumerId)
  If (!EnsureStorageLocked())
    Return False
  EndIf
  If (owner == None || !IsConsumerIdValid(consumerId))
    Return False
  EndIf
  Int existingIndex = FindConsumerIndexLocked(consumerId)
  If (existingIndex < 0)
    Return True
  EndIf
  If (Consumers[existingIndex].Owner != owner)
    LogUserWarning(ModuleName, "UnregisterConsumer", "Rejected unregister for consumer '" + consumerId + "' from a different owner.")
    Return False
  EndIf

  Consumers.Remove(existingIndex)
  LogUserInformational(ModuleName, "UnregisterConsumer", "Unregistered consumer '" + consumerId + "'.")
  Return True
EndFunction

; Checks the registered owner/ID pair without accepting replacement paths. No request is queued or submitted and no movie is loaded.
; Returns REGISTERED_TRANSPORT_DISABLED for a valid request, or a REJECTED_* reason for an unavailable owner, invalid ID, or ownership mismatch.
String Function RequestUiLoadLocked(Quest owner, String consumerId)
  If (!EnsureStorageLocked() || owner == None)
    LogUserWarning(ModuleName, "RequestUiLoad", "REJECTED_OWNER_UNAVAILABLE")
    Return "REJECTED_OWNER_UNAVAILABLE"
  EndIf
  If (!IsConsumerIdValid(consumerId))
    LogUserWarning(ModuleName, "RequestUiLoad", "REJECTED_CONSUMER_ID")
    Return "REJECTED_CONSUMER_ID"
  EndIf
  Int index = FindConsumerIndexLocked(consumerId)
  If (index < 0)
    LogUserWarning(ModuleName, "RequestUiLoad", "REJECTED_NOT_REGISTERED | Consumer=" + consumerId)
    Return "REJECTED_NOT_REGISTERED"
  EndIf
  If (Consumers[index].Owner != owner)
    LogUserWarning(ModuleName, "RequestUiLoad", "REJECTED_OWNER_MISMATCH | Consumer=" + consumerId)
    Return "REJECTED_OWNER_MISMATCH"
  EndIf
  LogUserInformational(ModuleName, "RequestUiLoad", "REGISTERED_TRANSPORT_DISABLED | Consumer=" + Consumers[index].ConsumerId + " | Version=" + Consumers[index].DescriptorVersion + " | Not queued, submitted, or loaded.")
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

; Initializes missing persistent storage without replacing a valid saved array, then prunes records whose owning quest is unavailable.
; Returns true after storage is available for registry operations.
Bool Function EnsureStorageLocked()
  EnsureMenuSubscriptionsLocked()
  If (Consumers == None)
    Consumers = new ConsumerRegistration[0]
    LogUserWarning(ModuleName, "EnsureStorage", "Initialized missing consumer registry storage; consumer quests may register again when a supported HUD menu opens.")
  EndIf

  Int index = Consumers.Length - 1
  While (index >= 0)
    If (Consumers[index] == None)
      Consumers.Remove(index)
      LogUserWarning(ModuleName, "EnsureStorage", "Pruned a None consumer record.")
    ElseIf (Consumers[index].Owner == None)
      String staleConsumerId = Consumers[index].ConsumerId
      Consumers.Remove(index)
      If (staleConsumerId == "")
        LogUserInformational(ModuleName, "EnsureStorage", "Pruned the typed consumer registry storage seed.")
      Else
        LogUserWarning(ModuleName, "EnsureStorage", "Pruned unavailable consumer owner '" + staleConsumerId + "'.")
      EndIf
    EndIf
    index -= 1
  EndWhile
  Return True
EndFunction

; Restores both host callbacks on first use of this revision, including saved quests whose old OnInit exited early.
; The saved flag is set only after both native registrations complete. No UI transport is involved.
Function EnsureMenuSubscriptionsLocked()
  If (!MenuSubscriptionsInitialized)
    RegisterForMenuOpenCloseEvent("HUDMenu")
    RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
    MenuSubscriptionsInitialized = True
    LogUserInformational(ModuleName, "EnsureMenuSubscriptions", "Registered HUDMenu and SpaceshipHudMenu callbacks; transport remains disabled.")
  EndIf
EndFunction

; Returns the index of a registered consumer ID or negative one when no complete record has that ID.
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

; Guarded public entry point. Serializes RegisterConsumer with all registry state operations; no waits or consumer callbacks occur under the guard.
Bool Function RegisterConsumer(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion)
  Bool result
  LockGuard RegistryGuard
    result = RegisterConsumerLocked(owner, consumerId, displayName, normalMovieUrl, largeMovieUrl, descriptorVersion)
  EndLockGuard
  Return result
EndFunction

; Guarded public entry point. Serializes UnregisterConsumer with all registry state operations; no waits or consumer callbacks occur under the guard.
Bool Function UnregisterConsumer(Quest owner, String consumerId)
  Bool result
  LockGuard RegistryGuard
    result = UnregisterConsumerLocked(owner, consumerId)
  EndLockGuard
  Return result
EndFunction

; Guarded public entry point. Serializes RequestUiLoad with all registry state operations; no waits or consumer callbacks occur under the guard.
String Function RequestUiLoad(Quest owner, String consumerId)
  String result
  LockGuard RegistryGuard
    result = RequestUiLoadLocked(owner, consumerId)
  EndLockGuard
  Return result
EndFunction

; Guarded public entry point. Serializes EnsureStorage with all registry state operations; no waits or consumer callbacks occur under the guard.
Bool Function EnsureStorage()
  Bool result
  LockGuard RegistryGuard
    result = EnsureStorageLocked()
  EndLockGuard
  Return result
EndFunction

; Guarded public entry point. Serializes FindConsumerIndex with all registry state operations; no waits or consumer callbacks occur under the guard.
Int Function FindConsumerIndex(String consumerId)
  Int result
  LockGuard RegistryGuard
    EnsureStorageLocked()
    result = FindConsumerIndexLocked(consumerId)
  EndLockGuard
  Return result
EndFunction

; Guarded public entry point. Serializes EnsureMenuSubscriptions with all registry state operations; no waits or consumer callbacks occur under the guard.
Function EnsureMenuSubscriptions()
  LockGuard RegistryGuard
    EnsureMenuSubscriptionsLocked()
  EndLockGuard
EndFunction

; Returns the current repaired registry count while holding the registry guard.
Int Function GetConsumerCount()
  Int count = 0
  LockGuard RegistryGuard
    EnsureStorageLocked()
    count = Consumers.Length
  EndLockGuard
  Return count
EndFunction

; Explicit owner-checked legacy rekey. Absent legacy records are a successful no-op; conflicting ownership fails without mutation.
; Consumers, FormIDs and descriptors are preserved. This method does not infer or generate the new UUID.
Bool Function MigrateConsumerIdentity(Quest owner, String legacyId, String newId)
  Bool migrated = False
  LockGuard RegistryGuard
    migrated = MigrateConsumerIdentityLocked(owner, legacyId, newId)
  EndLockGuard
  Return migrated
EndFunction

; Internal rekey transaction; caller holds RegistryGuard. Only non-UUID legacy text can be rekeyed.
Bool Function MigrateConsumerIdentityLocked(Quest owner, String legacyId, String newId)
  EnsureStorageLocked()
  If (owner == None || !IsConsumerIdValid(newId) || legacyId == "" || Venworks:Core:Utilities:UUID.IsValid(legacyId))
    Return False
  EndIf
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
        Consumers[index].ConsumerId = Venworks:Core:Utilities:UUID.Normalize(newId)
        current = index
      EndIf
      LogUserInformational(ModuleName, "MigrateConsumerIdentity", "LEGACY_ID_MIGRATED | Consumer=" + newId)
    EndIf
    index -= 1
  EndWhile
  Return True
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
