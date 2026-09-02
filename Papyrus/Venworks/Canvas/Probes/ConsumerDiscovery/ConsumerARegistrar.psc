ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerARegistrar Extends Quest

Venworks:Canvas:Probes:ConsumerDiscovery:Registry Property Registry Auto Const Mandatory

Event OnInit()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  RegisterWithRetry()
EndEvent

Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening)
    RegisterWithRetry()
  EndIf
EndEvent

Bool Function RegisterWithRetry()
  Int attempt = 0
  While (attempt < 20)
    If (Registry != None && Registry.RegisterConsumer(Self, "venworks.canvas.probe.consumer-a", "VWCANVAS-9 Consumer A", "Interface/VenworksCanvas/Consumers/venworks.canvas.probe.consumer-a/normal.swf", "Interface/VenworksCanvas/Consumers/venworks.canvas.probe.consumer-a/large.swf", 1))
      Debug.Trace("[Venworks Canvas][VWCANVAS-9] Consumer A registration is active.")
      Return True
    EndIf
    attempt += 1
    Utility.Wait(0.5)
  EndWhile

  Debug.Trace("[Venworks Canvas][VWCANVAS-9] Consumer A exhausted its bounded registration retry.", 1)
  Return False
EndFunction
