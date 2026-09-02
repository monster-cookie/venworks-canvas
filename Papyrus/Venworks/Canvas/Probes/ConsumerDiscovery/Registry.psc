ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:Registry Extends Quest

Quest[] ConsumerOwners
String[] ConsumerIds
String[] DisplayNames
String[] NormalMoviePaths
String[] LargeMoviePaths
Int[] DescriptorVersions
Int MessageId = 0

Event OnInit()
  EnsureStorage()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  PublishSnapshot("host-init")
EndEvent

Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening)
    PublishSnapshot("menu-" + menuName)
  EndIf
EndEvent

Bool Function RegisterConsumer(Quest owner, String consumerId, String displayName, String normalMoviePath, String largeMoviePath, Int descriptorVersion)
  EnsureStorage()
  If (owner == None || consumerId == "" || displayName == "" || normalMoviePath == "" || largeMoviePath == "" || descriptorVersion < 1)
    Debug.Trace("[Venworks Canvas][VWCANVAS-9] Rejected an incomplete consumer descriptor.", 1)
    PublishDiagnostic("registration-rejected-incomplete")
    Return False
  EndIf

  Int existingIndex = ConsumerIds.Find(consumerId)
  If (existingIndex >= 0)
    If (ConsumerOwners[existingIndex] != owner)
      Debug.Trace("[Venworks Canvas][VWCANVAS-9] Rejected duplicate consumer ID '" + consumerId + "' from a different owner.", 1)
      PublishDiagnostic("registration-rejected-owner|" + consumerId)
      Return False
    EndIf

    Bool changed = DisplayNames[existingIndex] != displayName || NormalMoviePaths[existingIndex] != normalMoviePath || LargeMoviePaths[existingIndex] != largeMoviePath || DescriptorVersions[existingIndex] != descriptorVersion
    If (!changed)
      Return True
    EndIf

    DisplayNames[existingIndex] = displayName
    NormalMoviePaths[existingIndex] = normalMoviePath
    LargeMoviePaths[existingIndex] = largeMoviePath
    DescriptorVersions[existingIndex] = descriptorVersion
    Debug.Trace("[Venworks Canvas][VWCANVAS-9] Updated consumer '" + consumerId + "'.")
    PublishSnapshot("update")
    Return True
  EndIf

  ConsumerOwners.Add(owner)
  ConsumerIds.Add(consumerId)
  DisplayNames.Add(displayName)
  NormalMoviePaths.Add(normalMoviePath)
  LargeMoviePaths.Add(largeMoviePath)
  DescriptorVersions.Add(descriptorVersion)
  Debug.Trace("[Venworks Canvas][VWCANVAS-9] Registered consumer '" + consumerId + "'.")
  PublishSnapshot("register")
  Return True
EndFunction

Bool Function UnregisterConsumer(Quest owner, String consumerId)
  EnsureStorage()
  Int existingIndex = ConsumerIds.Find(consumerId)
  If (existingIndex < 0)
    Return True
  EndIf
  If (ConsumerOwners[existingIndex] != owner)
    Debug.Trace("[Venworks Canvas][VWCANVAS-9] Rejected unregister for consumer '" + consumerId + "' from a different owner.", 1)
    PublishDiagnostic("unregister-rejected-owner|" + consumerId)
    Return False
  EndIf

  ConsumerOwners.Remove(existingIndex)
  ConsumerIds.Remove(existingIndex)
  DisplayNames.Remove(existingIndex)
  NormalMoviePaths.Remove(existingIndex)
  LargeMoviePaths.Remove(existingIndex)
  DescriptorVersions.Remove(existingIndex)
  Debug.Trace("[Venworks Canvas][VWCANVAS-9] Unregistered consumer '" + consumerId + "'.")
  PublishSnapshot("unregister")
  Return True
EndFunction

Bool Function PublishSnapshot(String reason = "manual")
  EnsureStorage()
  MessageId += 1
  String body = MessageId + "|" + reason + "|" + ConsumerIds.Length + "|"
  Int index = 0
  While (index < ConsumerIds.Length)
    If (index > 0)
      body += ";"
    EndIf
    body += ConsumerIds[index] + "~" + DisplayNames[index] + "~" + NormalMoviePaths[index] + "~" + LargeMoviePaths[index] + "~" + DescriptorVersions[index]
    index += 1
  EndWhile

  Game.ShowCustomWatchAlert("VWC_EVT/1|canvas.registry.snapshot|" + body)
  Debug.Trace("[Venworks Canvas][VWCANVAS-9] Submitted registry snapshot " + MessageId + " with " + ConsumerIds.Length + " consumer(s).")
  Return True
EndFunction

Function PublishDiagnostic(String diagnostic)
  MessageId += 1
  Game.ShowCustomWatchAlert("VWC_EVT/1|canvas.registry.diagnostic|" + MessageId + "|" + diagnostic)
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
EndFunction
