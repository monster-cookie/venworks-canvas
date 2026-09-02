ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:Registry Extends Venworks:Canvas:Base:BaseQuest

Struct ConsumerRegistration
  Quest Owner
  String ConsumerId
  String DisplayName
  String NormalMovieUrl
  String LargeMovieUrl
  Int DescriptorVersion
EndStruct

ConsumerRegistration[] Consumers
Int MessageId = 0

String ModuleName = "Probes:ConsumerDiscovery:Registry"
Int MaxConsumerIdCharacters = 64
Int MaxDisplayNameCharacters = 80
Int MaxConsumerMovieUrlCharacters = 180
Int MaxSnapshotPageCharacters = 4096
Int MaxSnapshotPagePayloadCharacters = 3600

; Initializes persistent storage, registers both HUD menu callbacks, and publishes the initial registry generation.
Event OnInit()
  EnsureStorage()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  PublishSnapshot("host-init")
EndEvent

; Replays the complete current registry generation three times when either supported HUD menu opens.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening)
    PublishSnapshot("menu-" + menuName + "-0")
    Utility.WaitMenuPause(0.25)
    PublishSnapshot("menu-" + menuName + "-1")
    Utility.WaitMenuPause(0.50)
    PublishSnapshot("menu-" + menuName + "-2")
  EndIf
EndEvent

; Registers or updates one complete consumer record owned by the supplied quest and publishes the resulting registry generation.
; Returns false when the descriptor is invalid or an existing consumer ID belongs to a different owner.
Bool Function RegisterConsumer(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion)
  EnsureStorage()
  If (!IsDescriptorValid(owner, consumerId, displayName, normalMovieUrl, largeMovieUrl, descriptorVersion))
    LogUserWarning(ModuleName, "RegisterConsumer", "Rejected an invalid consumer descriptor.")
    PublishDiagnostic("registration-rejected-invalid")
    Return False
  EndIf

  Int existingIndex = FindConsumerIndex(consumerId)
  If (existingIndex >= 0)
    If (Consumers[existingIndex].Owner != owner)
      LogUserWarning(ModuleName, "RegisterConsumer", "Rejected duplicate consumer ID '" + consumerId + "' from a different owner.")
      PublishDiagnostic("registration-rejected-owner:" + consumerId)
      Return False
    EndIf

    Bool changed = Consumers[existingIndex].DisplayName != displayName || Consumers[existingIndex].NormalMovieUrl != normalMovieUrl || Consumers[existingIndex].LargeMovieUrl != largeMovieUrl || Consumers[existingIndex].DescriptorVersion != descriptorVersion
    If (!changed)
      PublishSnapshot("refresh")
      Return True
    EndIf

    Consumers[existingIndex].DisplayName = displayName
    Consumers[existingIndex].NormalMovieUrl = normalMovieUrl
    Consumers[existingIndex].LargeMovieUrl = largeMovieUrl
    Consumers[existingIndex].DescriptorVersion = descriptorVersion
    LogUserInformational(ModuleName, "RegisterConsumer", "Updated consumer '" + consumerId + "'.")
    PublishDiagnostic("registration-updated:" + consumerId)
    PublishSnapshot("update")
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
  LogUserInformational(ModuleName, "RegisterConsumer", "Registered consumer '" + consumerId + "'.")
  PublishDiagnostic("registration-added:" + consumerId)
  PublishSnapshot("register")
  Return True
EndFunction

; Removes one consumer when the supplied quest owns its ID and publishes the resulting registry generation.
; Returns true when the consumer is absent or removed, and false when another quest owns the ID.
Bool Function UnregisterConsumer(Quest owner, String consumerId)
  EnsureStorage()
  Int existingIndex = FindConsumerIndex(consumerId)
  If (existingIndex < 0)
    PublishSnapshot("unregister-absent")
    Return True
  EndIf
  If (Consumers[existingIndex].Owner != owner)
    LogUserWarning(ModuleName, "UnregisterConsumer", "Rejected unregister for consumer '" + consumerId + "' from a different owner.")
    PublishDiagnostic("unregister-rejected-owner:" + consumerId)
    Return False
  EndIf

  Consumers.Remove(existingIndex)
  LogUserInformational(ModuleName, "UnregisterConsumer", "Unregistered consumer '" + consumerId + "'.")
  PublishDiagnostic("registration-removed:" + consumerId)
  PublishSnapshot("unregister")
  Return True
EndFunction

; Publishes the complete registry as one atomic generation split across as many bounded Watch Alert pages as required.
; Returns false without publishing a partial generation when any record or assembled page exceeds its transport budget.
Bool Function PublishSnapshot(String reason = "manual")
  EnsureStorage()
  If (!IsPrintableAscii(reason, 1, 40))
    reason = "invalid-reason"
  EndIf

  String[] pagePayloads = new String[0]
  Int[] pageRecordCounts = new Int[0]
  String currentPayload = ""
  Int currentRecordCount = 0
  Int consumerIndex = 0
  While (consumerIndex < Consumers.Length)
    String record = EncodeField(Consumers[consumerIndex].ConsumerId) + EncodeField(Consumers[consumerIndex].DisplayName) + EncodeField(Consumers[consumerIndex].NormalMovieUrl) + EncodeField(Consumers[consumerIndex].LargeMovieUrl) + EncodeField(Consumers[consumerIndex].DescriptorVersion as String)
    String framedRecord = EncodeField(record)
    If (GetCharacterCount(framedRecord) > MaxSnapshotPagePayloadCharacters)
      LogUserError(ModuleName, "PublishSnapshot", "Rejected consumer '" + Consumers[consumerIndex].ConsumerId + "' because its framed record exceeds one snapshot page.")
      PublishDiagnostic("snapshot-rejected-record-oversized:" + Consumers[consumerIndex].ConsumerId)
      Return False
    EndIf
    If (currentRecordCount > 0 && GetCharacterCount(currentPayload + framedRecord) > MaxSnapshotPagePayloadCharacters)
      pagePayloads.Add(currentPayload)
      pageRecordCounts.Add(currentRecordCount)
      currentPayload = ""
      currentRecordCount = 0
    EndIf
    currentPayload += framedRecord
    currentRecordCount += 1
    consumerIndex += 1
  EndWhile

  If (currentRecordCount > 0 || pagePayloads.Length == 0)
    pagePayloads.Add(currentPayload)
    pageRecordCounts.Add(currentRecordCount)
  EndIf

  MessageId += 1
  String[] pageBodies = new String[0]
  Int pageIndex = 0
  While (pageIndex < pagePayloads.Length)
    String body = EncodeField(MessageId as String) + EncodeField(reason) + EncodeField(pageIndex as String) + EncodeField(pagePayloads.Length as String) + EncodeField(Consumers.Length as String) + EncodeField(pageRecordCounts[pageIndex] as String) + pagePayloads[pageIndex]
    If (GetCharacterCount(body) > MaxSnapshotPageCharacters)
      LogUserError(ModuleName, "PublishSnapshot", "Rejected registry generation " + MessageId + " because page " + pageIndex + " exceeds the Watch Alert transport budget.")
      PublishDiagnostic("snapshot-rejected-page-oversized")
      Return False
    EndIf
    pageBodies.Add(body)
    pageIndex += 1
  EndWhile

  pageIndex = 0
  While (pageIndex < pageBodies.Length)
    Game.ShowCustomWatchAlert("VWC_EVT/1|canvas.registry.snapshot|" + pageBodies[pageIndex])
    pageIndex += 1
  EndWhile
  LogUserInformational(ModuleName, "PublishSnapshot", "Submitted registry generation " + MessageId + " with " + Consumers.Length + " consumer(s) across " + pageBodies.Length + " page(s).")
  Return True
EndFunction

; Publishes a bounded registry diagnostic on the same one-way Watch Alert bridge using its own monotonic message ID.
Function PublishDiagnostic(String diagnostic)
  MessageId += 1
  String body = EncodeField(MessageId as String) + EncodeField(diagnostic)
  Game.ShowCustomWatchAlert("VWC_EVT/1|canvas.registry.diagnostic|" + body)
EndFunction

; Returns whether a proposed owner and descriptor satisfy the bounded, canonical consumer contract.
Bool Function IsDescriptorValid(Quest owner, String consumerId, String displayName, String normalMovieUrl, String largeMovieUrl, Int descriptorVersion)
  If (owner == None || descriptorVersion < 1 || descriptorVersion > 9999)
    Return False
  EndIf
  If (!IsConsumerIdValid(consumerId) || !IsPrintableAscii(displayName, 1, MaxDisplayNameCharacters))
    Return False
  EndIf
  If (!IsPrintableAscii(normalMovieUrl, 1, MaxConsumerMovieUrlCharacters) || !IsPrintableAscii(largeMovieUrl, 1, MaxConsumerMovieUrlCharacters))
    Return False
  EndIf
  If (normalMovieUrl != "VenworksCanvas/Consumers/" + consumerId + "/normal.swf")
    Return False
  EndIf
  If (largeMovieUrl != "VenworksCanvas/Consumers/" + consumerId + "/large.swf")
    Return False
  EndIf
  Return True
EndFunction

; Returns whether a consumer ID is bounded lowercase ASCII, namespaced, and safe for use in canonical loader URLs.
Bool Function IsConsumerIdValid(String consumerId)
  Int[] characters = Utility.SplitStringChars(consumerId)
  If (characters == None || characters.Length < 3 || characters.Length > MaxConsumerIdCharacters)
    Return False
  EndIf
  If (!IsAsciiLetterOrDigit(characters[0]) || !IsAsciiLetterOrDigit(characters[characters.Length - 1]))
    Return False
  EndIf

  Int index = 0
  Int previous = -1
  Bool foundNamespaceSeparator = False
  While (index < characters.Length)
    Int current = characters[index]
    Bool allowed = IsAsciiLetterOrDigit(current) || current == 45 || current == 46
    If (!allowed || (current == 46 && previous == 46))
      Return False
    EndIf
    If (current == 46)
      foundNamespaceSeparator = True
    EndIf
    previous = current
    index += 1
  EndWhile
  Return foundNamespaceSeparator
EndFunction

; Returns whether one character code is a lowercase ASCII letter or decimal digit.
Bool Function IsAsciiLetterOrDigit(Int character)
  Return (character >= 97 && character <= 122) || (character >= 48 && character <= 57)
EndFunction

; Returns whether a value has a character count inside the supplied bounds and contains only printable ASCII.
Bool Function IsPrintableAscii(String value, Int minimumLength, Int maximumLength)
  Int[] characters = Utility.SplitStringChars(value)
  If (characters == None || characters.Length < minimumLength || characters.Length > maximumLength)
    Return False
  EndIf
  Int index = 0
  While (index < characters.Length)
    If (characters[index] < 32 || characters[index] > 126)
      Return False
    EndIf
    index += 1
  EndWhile
  Return True
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

; Initializes the persistent registration array and prunes records whose owning quest is no longer available.
Function EnsureStorage()
  If (Consumers == None)
    Consumers = new ConsumerRegistration[0]
  EndIf

  Int index = Consumers.Length - 1
  While (index >= 0)
    If (Consumers[index].Owner == None)
      String staleConsumerId = Consumers[index].ConsumerId
      Consumers.Remove(index)
      LogUserWarning(ModuleName, "EnsureStorage", "Pruned unavailable consumer owner '" + staleConsumerId + "'.")
      PublishDiagnostic("registration-pruned:" + staleConsumerId)
    EndIf
    index -= 1
  EndWhile
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
