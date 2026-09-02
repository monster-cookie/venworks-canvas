ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar Extends Quest

Venworks:Canvas:Probes:ConsumerDiscovery:Registry Property Registry Auto Const Mandatory
String Property ConsumerId Auto Const Mandatory
String Property DisplayName Auto Const Mandatory
String Property NormalMoviePath Auto Const Mandatory
String Property LargeMoviePath Auto Const Mandatory
Int Property DescriptorVersion Auto Const Mandatory
Bool Property ExpectedRegistration Auto Const Mandatory
Float Property InitialDelaySeconds Auto Const Mandatory

Event OnInit()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  If (InitialDelaySeconds > 0.0)
    Utility.Wait(InitialDelaySeconds)
  EndIf
  RegisterWithRetry()
EndEvent

Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening)
    If (InitialDelaySeconds > 0.0)
      Utility.WaitMenuPause(InitialDelaySeconds)
    EndIf
    RegisterWithRetry()
  EndIf
EndEvent

Bool Function RegisterWithRetry()
  Int attempt = 0
  While (attempt < 20)
    If (Registry != None)
      Bool actualRegistration = Registry.RegisterConsumer(Self, ConsumerId, DisplayName, NormalMoviePath, LargeMoviePath, DescriptorVersion)
      If (actualRegistration == ExpectedRegistration)
        Debug.Trace("[Venworks Canvas][VWCANVAS-9] Consumer B probe observed its expected registration result for '" + ConsumerId + "'.")
        Return True
      EndIf
      If (actualRegistration && !ExpectedRegistration)
        Registry.UnregisterConsumer(Self, ConsumerId)
      EndIf
    EndIf
    attempt += 1
    Utility.WaitMenuPause(0.5)
  EndWhile

  Debug.Trace("[Venworks Canvas][VWCANVAS-9] Consumer B exhausted its bounded registration retry.", 1)
  Return False
EndFunction
