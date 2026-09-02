ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:Registry Extends Quest

Quest[] ConsumerOwners
String[] ConsumerIds
String[] DisplayNames
String[] NormalMoviePaths
String[] LargeMoviePaths
Int[] DescriptorVersions
Int MessageId = 0

Int MaxConsumers = 8
Int MaxConsumerIdCharacters = 64
Int MaxDisplayNameCharacters = 80
Int MaxMoviePathCharacters = 180
Int MaxSnapshotCharacters = 4096

Event OnInit()
  EnsureStorage()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  PublishSnapshot("host-init")
EndEvent

Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening)
    PublishSnapshot("menu-" + menuName + "-0")
    Utility.WaitMenuPause(0.25)
    PublishSnapshot("menu-" + menuName + "-1")
    Utility.WaitMenuPause(0.50)
    PublishSnapshot("menu-" + menuName + "-2")
  EndIf
EndEvent

Bool Function RegisterConsumer(Quest owner, String consumerId, String displayName, String normalMoviePath, String largeMoviePath, Int descriptorVersion)
  EnsureStorage()
  If (!IsDescriptorValid(owner, consumerId, displayName, normalMoviePath, largeMoviePath, descriptorVersion))
    Debug.Trace("[Venworks Canvas][VWCANVAS-9] Rejected an invalid consumer descriptor.", 1)
    PublishDiagnostic("registration-rejected-invalid")
    Return False
  EndIf

  Int existingIndex = ConsumerIds.Find(consumerId)
  If (existingIndex >= 0)
    If (ConsumerOwners[existingIndex] != owner)
      Debug.Trace("[Venworks Canvas][VWCANVAS-9] Rejected duplicate consumer ID '" + consumerId + "' from a different owner.", 1)
      PublishDiagnostic("registration-rejected-owner:" + consumerId)
      Return False
    EndIf

    Bool changed = DisplayNames[existingIndex] != displayName || NormalMoviePaths[existingIndex] != normalMoviePath || LargeMoviePaths[existingIndex] != largeMoviePath || DescriptorVersions[existingIndex] != descriptorVersion
    If (!changed)
      PublishSnapshot("refresh")
      Return True
    EndIf

    DisplayNames[existingIndex] = displayName
    NormalMoviePaths[existingIndex] = normalMoviePath
    LargeMoviePaths[existingIndex] = largeMoviePath
    DescriptorVersions[existingIndex] = descriptorVersion
    Debug.Trace("[Venworks Canvas][VWCANVAS-9] Updated consumer '" + consumerId + "'.")
    PublishDiagnostic("registration-updated:" + consumerId)
    PublishSnapshot("update")
    Return True
  EndIf

  If (ConsumerIds.Length >= MaxConsumers)
    Debug.Trace("[Venworks Canvas][VWCANVAS-9] Rejected consumer '" + consumerId + "' because the bounded registry is full.", 1)
    PublishDiagnostic("registration-rejected-capacity:" + consumerId)
    Return False
  EndIf

  ConsumerOwners.Add(owner)
  ConsumerIds.Add(consumerId)
  DisplayNames.Add(displayName)
  NormalMoviePaths.Add(normalMoviePath)
  LargeMoviePaths.Add(largeMoviePath)
  DescriptorVersions.Add(descriptorVersion)
  Debug.Trace("[Venworks Canvas][VWCANVAS-9] Registered consumer '" + consumerId + "'.")
  PublishDiagnostic("registration-added:" + consumerId)
  PublishSnapshot("register")
  Return True
EndFunction

Bool Function UnregisterConsumer(Quest owner, String consumerId)
  EnsureStorage()
  Int existingIndex = ConsumerIds.Find(consumerId)
  If (existingIndex < 0)
    PublishSnapshot("unregister-absent")
    Return True
  EndIf
  If (ConsumerOwners[existingIndex] != owner)
    Debug.Trace("[Venworks Canvas][VWCANVAS-9] Rejected unregister for consumer '" + consumerId + "' from a different owner.", 1)
    PublishDiagnostic("unregister-rejected-owner:" + consumerId)
    Return False
  EndIf

  RemoveStorageAt(existingIndex)
  Debug.Trace("[Venworks Canvas][VWCANVAS-9] Unregistered consumer '" + consumerId + "'.")
  PublishDiagnostic("registration-removed:" + consumerId)
  PublishSnapshot("unregister")
  Return True
EndFunction

Bool Function PublishSnapshot(String reason = "manual")
  EnsureStorage()
  MessageId += 1
  String body = EncodeField(MessageId as String) + EncodeField(reason) + EncodeField(ConsumerIds.Length as String)
  Int index = 0
  While (index < ConsumerIds.Length)
    String record = EncodeField(ConsumerIds[index]) + EncodeField(DisplayNames[index]) + EncodeField(NormalMoviePaths[index]) + EncodeField(LargeMoviePaths[index]) + EncodeField(DescriptorVersions[index] as String)
    body += EncodeField(record)
    index += 1
  EndWhile

  If (GetCharacterCount(body) > MaxSnapshotCharacters)
    Debug.Trace("[Venworks Canvas][VWCANVAS-9] Rejected an oversized registry snapshot.", 2)
    PublishDiagnostic("snapshot-rejected-oversized")
    Return False
  EndIf

  Game.ShowCustomWatchAlert("VWC_EVT/1|canvas.registry.snapshot|" + body)
  Debug.Trace("[Venworks Canvas][VWCANVAS-9] Submitted registry snapshot " + MessageId + " with " + ConsumerIds.Length + " consumer(s).")
  Return True
EndFunction

Function PublishDiagnostic(String diagnostic)
  MessageId += 1
  String body = EncodeField(MessageId as String) + EncodeField(diagnostic)
  Game.ShowCustomWatchAlert("VWC_EVT/1|canvas.registry.diagnostic|" + body)
EndFunction

Bool Function IsDescriptorValid(Quest owner, String consumerId, String displayName, String normalMoviePath, String largeMoviePath, Int descriptorVersion)
  If (owner == None || descriptorVersion < 1 || descriptorVersion > 9999)
    Return False
  EndIf
  If (!IsConsumerIdValid(consumerId) || !IsPrintableAscii(displayName, 1, MaxDisplayNameCharacters))
    Return False
  EndIf
  If (!IsPrintableAscii(normalMoviePath, 1, MaxMoviePathCharacters) || !IsPrintableAscii(largeMoviePath, 1, MaxMoviePathCharacters))
    Return False
  EndIf
  If (normalMoviePath != "VenworksCanvas/Consumers/" + consumerId + "/normal.swf")
    Return False
  EndIf
  If (largeMoviePath != "VenworksCanvas/Consumers/" + consumerId + "/large.swf")
    Return False
  EndIf
  Return True
EndFunction

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

Bool Function IsAsciiLetterOrDigit(Int character)
  Return (character >= 97 && character <= 122) || (character >= 48 && character <= 57)
EndFunction

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

String Function EncodeField(String value)
  Return GetCharacterCount(value) + ":" + value
EndFunction

Int Function GetCharacterCount(String value)
  Int[] characters = Utility.SplitStringChars(value)
  If (characters == None)
    Return 0
  EndIf
  Return characters.Length
EndFunction

Function EnsureStorage()
  If (ConsumerOwners == None)
    ConsumerOwners = new Quest[0]
  EndIf
  If (ConsumerIds == None)
    ConsumerIds = new String[0]
  EndIf
  If (DisplayNames == None)
    DisplayNames = new String[0]
  EndIf
  If (NormalMoviePaths == None)
    NormalMoviePaths = new String[0]
  EndIf
  If (LargeMoviePaths == None)
    LargeMoviePaths = new String[0]
  EndIf
  If (DescriptorVersions == None)
    DescriptorVersions = new Int[0]
  EndIf

  NormalizeStorageLengths()
  Int index = ConsumerOwners.Length - 1
  While (index >= 0)
    If (ConsumerOwners[index] == None)
      String staleConsumerId = ConsumerIds[index]
      RemoveStorageAt(index)
      Debug.Trace("[Venworks Canvas][VWCANVAS-9] Pruned unavailable consumer owner '" + staleConsumerId + "'.", 1)
      PublishDiagnostic("registration-pruned:" + staleConsumerId)
    EndIf
    index -= 1
  EndWhile
EndFunction

Function NormalizeStorageLengths()
  Int minimumLength = ConsumerOwners.Length
  If (ConsumerIds.Length < minimumLength)
    minimumLength = ConsumerIds.Length
  EndIf
  If (DisplayNames.Length < minimumLength)
    minimumLength = DisplayNames.Length
  EndIf
  If (NormalMoviePaths.Length < minimumLength)
    minimumLength = NormalMoviePaths.Length
  EndIf
  If (LargeMoviePaths.Length < minimumLength)
    minimumLength = LargeMoviePaths.Length
  EndIf
  If (DescriptorVersions.Length < minimumLength)
    minimumLength = DescriptorVersions.Length
  EndIf

  Bool repaired = ConsumerOwners.Length != minimumLength || ConsumerIds.Length != minimumLength || DisplayNames.Length != minimumLength || NormalMoviePaths.Length != minimumLength || LargeMoviePaths.Length != minimumLength || DescriptorVersions.Length != minimumLength
  While (ConsumerOwners.Length > minimumLength)
    ConsumerOwners.Remove(ConsumerOwners.Length - 1)
  EndWhile
  While (ConsumerIds.Length > minimumLength)
    ConsumerIds.Remove(ConsumerIds.Length - 1)
  EndWhile
  While (DisplayNames.Length > minimumLength)
    DisplayNames.Remove(DisplayNames.Length - 1)
  EndWhile
  While (NormalMoviePaths.Length > minimumLength)
    NormalMoviePaths.Remove(NormalMoviePaths.Length - 1)
  EndWhile
  While (LargeMoviePaths.Length > minimumLength)
    LargeMoviePaths.Remove(LargeMoviePaths.Length - 1)
  EndWhile
  While (DescriptorVersions.Length > minimumLength)
    DescriptorVersions.Remove(DescriptorVersions.Length - 1)
  EndWhile
  If (repaired)
    Debug.Trace("[Venworks Canvas][VWCANVAS-9] Repaired mismatched persistent registry storage.", 1)
    PublishDiagnostic("registry-storage-repaired")
  EndIf
EndFunction

Function RemoveStorageAt(Int index)
  ConsumerOwners.Remove(index)
  ConsumerIds.Remove(index)
  DisplayNames.Remove(index)
  NormalMoviePaths.Remove(index)
  LargeMoviePaths.Remove(index)
  DescriptorVersions.Remove(index)
EndFunction
