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
  LogUserInformational(ModuleName, "OnInit", "REGISTRATION LOG TEST | WATCH BRIDGE DISABLED | Consumers=" + Consumers.Length)
EndEvent

; Reconciles saved storage and reports its current count once per supported HUD opening; never publishes UI data.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening && EnsureStorage())
    LogUserInformational(ModuleName, "OnMenuOpenCloseEvent", "WATCH BRIDGE DISABLED | Menu=" + menuName + " | Consumers=" + Consumers.Length)
  EndIf
EndEvent

; Validates and stores one complete descriptor owned by the supplied quest; identical registration is a successful no-op.
; True acknowledges Papyrus registry state only, not UI submission or loading. False is a terminal descriptor/ownership rejection.
Bool Function RegisterConsumer(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion)
  If (!EnsureStorage())
    Return False
  EndIf
  String rejection = GetDescriptorRejectionReason(owner, consumerId, displayName, normalMovieUrl, largeMovieUrl, descriptorVersion)
  If (rejection != "")
    LogUserWarning(ModuleName, "RegisterConsumer", "REGISTRATION_REJECTED | " + rejection + " | Owner=" + owner)
    Return False
  EndIf

  Int existingIndex = FindConsumerIndex(consumerId)
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
Bool Function UnregisterConsumer(Quest owner, String consumerId)
  If (!EnsureStorage())
    Return False
  EndIf
  Int existingIndex = FindConsumerIndex(consumerId)
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
String Function RequestUiLoad(Quest owner, String consumerId)
  If (!EnsureStorage() || owner == None)
    LogUserWarning(ModuleName, "RequestUiLoad", "REJECTED_OWNER_UNAVAILABLE")
    Return "REJECTED_OWNER_UNAVAILABLE"
  EndIf
  If (!IsConsumerIdValid(consumerId))
    LogUserWarning(ModuleName, "RequestUiLoad", "REJECTED_CONSUMER_ID")
    Return "REJECTED_CONSUMER_ID"
  EndIf
  Int index = FindConsumerIndex(consumerId)
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
  If (normalMovieUrl != "VenworksCanvas/Consumers/" + consumerId + "/normal.swf")
    If (GetCharacterCount(normalMovieUrl) > 180 || GetCharacterCount(consumerId) > 64)
      Return "normalMovieUrl noncanonical | length=" + GetCharacterCount(normalMovieUrl) + " | consumerIdLength=" + GetCharacterCount(consumerId)
    EndIf
    Return "normalMovieUrl='" + normalMovieUrl + "' | expected='VenworksCanvas/Consumers/" + consumerId + "/normal.swf'"
  EndIf
  If (largeMovieUrl != "VenworksCanvas/Consumers/" + consumerId + "/large.swf")
    If (GetCharacterCount(largeMovieUrl) > 180 || GetCharacterCount(consumerId) > 64)
      Return "largeMovieUrl noncanonical | length=" + GetCharacterCount(largeMovieUrl) + " | consumerIdLength=" + GetCharacterCount(consumerId)
    EndIf
    Return "largeMovieUrl='" + largeMovieUrl + "' | expected='VenworksCanvas/Consumers/" + consumerId + "/large.swf'"
  EndIf
  Return ""
EndFunction

; Returns whether a proposed owner and descriptor satisfy the canonical contract; validation has no publication side effects.
Bool Function IsDescriptorValid(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion)
  Return GetDescriptorRejectionReason(owner, consumerId, displayName, normalMovieUrl, largeMovieUrl, descriptorVersion) == ""
EndFunction

; Returns whether a consumer ID is bounded lowercase ASCII, namespaced, and safe for use in canonical loader URLs.
Bool Function IsConsumerIdValid(String consumerId)
  Return GetConsumerIdRejectionReason(consumerId) == ""
EndFunction

; Returns an empty string for a canonical ID or its first length, character, or namespace rejection; never echoes an unbounded ID.
String Function GetConsumerIdRejectionReason(String consumerId)
  Int[] characters = Utility.SplitStringChars(consumerId)
  If (characters == None)
    Return "consumerId split=None | maximum=" + MaxConsumerIdCharacters
  EndIf
  If (characters.Length < 3 || characters.Length > MaxConsumerIdCharacters)
    Return "consumerId length=" + characters.Length + " | range=3.." + MaxConsumerIdCharacters
  EndIf
  If (!IsAsciiLetterOrDigit(characters[0]) || !IsAsciiLetterOrDigit(characters[characters.Length - 1]))
    Return "consumerId boundary | firstCode=" + characters[0] + " | lastCode=" + characters[characters.Length - 1]
  EndIf

  Int index = 0
  Int previous = -1
  Bool foundNamespaceSeparator = False
  While (index < characters.Length)
    Int current = characters[index]
    Bool allowed = IsAsciiLetterOrDigit(current) || current == 45 || current == 46
    If (!allowed || (current == 46 && previous == 46))
      Return "consumerId character | index=" + index + " | code=" + current + " | previousCode=" + previous
    EndIf
    If (current == 46)
      foundNamespaceSeparator = True
    EndIf
    previous = current
    index += 1
  EndWhile
  If (!foundNamespaceSeparator)
    Return "consumerId missing namespace separator"
  EndIf
  Return ""
EndFunction

; Returns whether one character code is a lowercase ASCII letter or decimal digit.
Bool Function IsAsciiLetterOrDigit(Int character)
  Return (character >= 97 && character <= 122) || (character >= 48 && character <= 57)
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
Bool Function EnsureStorage()
  EnsureMenuSubscriptions()
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
Function EnsureMenuSubscriptions()
  If (!MenuSubscriptionsInitialized)
    RegisterForMenuOpenCloseEvent("HUDMenu")
    RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
    MenuSubscriptionsInitialized = True
    LogUserInformational(ModuleName, "EnsureMenuSubscriptions", "Registered HUDMenu and SpaceshipHudMenu callbacks; transport remains disabled.")
  EndIf
EndFunction

; Returns the index of a registered consumer ID or negative one when no complete record has that ID.
Int Function FindConsumerIndex(String consumerId)
  Int index = 0
  While (index < Consumers.Length)
    If (Consumers[index].ConsumerId == consumerId)
      Return index
    EndIf
    index += 1
  EndWhile
  Return -1
EndFunction
