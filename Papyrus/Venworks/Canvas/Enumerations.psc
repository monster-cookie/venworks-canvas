ScriptName Venworks:Canvas:Enumerations Extends ScriptObject Hidden

; Public selectors for supported Canvas event envelope versions. Wire strings remain Canvas-owned.
Struct EventHeader
  Int V1 = 1
EndStruct

; Public selectors for supported Canvas packet types. Wire strings remain Canvas-owned.
Struct PacketType
  Int UiLoad = 1
EndStruct

; Resolves a validated event-header selector to its canonical wire text; unsupported values return empty.
String Function ResolveEventHeader(Int eventHeader) Global
  EventHeader headers = new EventHeader
  If (eventHeader == headers.V1)
    Return "VWC_EVT/1|"
  EndIf
  Return ""
EndFunction

; Resolves a validated packet-type selector to its canonical wire text; unsupported values return empty.
String Function ResolvePacketType(Int packetType) Global
  PacketType packetTypes = new PacketType
  If (packetType == packetTypes.UiLoad)
    Return "canvas.ui.load"
  EndIf
  Return ""
EndFunction
