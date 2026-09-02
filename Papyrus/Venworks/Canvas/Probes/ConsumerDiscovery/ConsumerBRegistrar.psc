ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar Extends Venworks:Canvas:Base:BaseQuest

Venworks:Canvas:Probes:ConsumerDiscovery:Registry Property Registry Auto Const Mandatory
String Property ConsumerId Auto Const Mandatory
String Property DisplayName Auto Const Mandatory
String Property NormalMoviePath Auto Const Mandatory
String Property LargeMoviePath Auto Const Mandatory
Int Property DescriptorVersion Auto Const Mandatory
Bool Property ExpectedRegistration Auto Const Mandatory
Float Property InitialDelaySeconds Auto Const Mandatory

String ModuleName = "Probes:ConsumerDiscovery:ConsumerBRegistrar"

; Registers for both HUD menus and attempts the VMAD-configured descriptor after its configured delay.
Event OnInit()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  If (InitialDelaySeconds > 0.0)
    Utility.Wait(InitialDelaySeconds)
  EndIf
  RegisterWithRetry()
EndEvent

; Re-publishes the VMAD-configured descriptor when either supported HUD menu opens.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening)
    If (InitialDelaySeconds > 0.0)
      Utility.WaitMenuPause(InitialDelaySeconds)
    EndIf
    RegisterWithRetry()
  EndIf
EndEvent

; Attempts the VMAD-configured descriptor with bounded retries and returns whether the expected result was observed.
Bool Function RegisterWithRetry()
  Int attempt = 0
  While (attempt < 20)
    If (Registry != None)
      Bool actualRegistration = Registry.RegisterConsumer(Self, ConsumerId, DisplayName, NormalMoviePath, LargeMoviePath, DescriptorVersion)
      If (actualRegistration == ExpectedRegistration)
        LogUserInformational(ModuleName, "RegisterWithRetry", "Observed the expected registration result for '" + ConsumerId + "'.")
        Return True
      EndIf
      If (actualRegistration && !ExpectedRegistration)
        Registry.UnregisterConsumer(Self, ConsumerId)
      EndIf
    EndIf
    attempt += 1
    Utility.WaitMenuPause(0.5)
  EndWhile

  LogUserWarning(ModuleName, "RegisterWithRetry", "Exhausted the bounded registration retry for '" + ConsumerId + "'.")
  Return False
EndFunction
