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
Bool RegistrationAttemptActive = False

; Registers for both HUD menus and attempts the VMAD-configured descriptor after its configured delay.
Event OnInit()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  If (InitialDelaySeconds > 0.0)
    Utility.Wait(InitialDelaySeconds)
  EndIf
  RegisterWithRetry()
EndEvent

; Reconciles the VMAD descriptor when either HUD opens. Overlapping attempts are skipped and no bridge publication occurs.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening)
    If (InitialDelaySeconds > 0.0)
      Utility.WaitMenuPause(InitialDelaySeconds)
    EndIf
    RegisterWithRetry()
  EndIf
EndEvent

; Serializes registration attempts; true means the expected Papyrus result, not UI submission or readiness.
Bool Function RegisterWithRetry()
  If (RegistrationAttemptActive)
    Return False
  EndIf
  RegistrationAttemptActive = True
  Bool result = AttemptRegistration()
  RegistrationAttemptActive = False
  Return result
EndFunction

; Explicit console-test helper: checks a requested ID using this quest as owner, without registration or bridge traffic.
; Returns the host's REJECTED_* or REGISTERED_TRANSPORT_DISABLED result, or REJECTED_REGISTRY_UNAVAILABLE when unbound.
String Function CheckUiLoadRequest(String requestedConsumerId)
  If (Registry == None)
    LogUserWarning(ModuleName, "CheckUiLoadRequest", "REJECTED_REGISTRY_UNAVAILABLE")
    Return "REJECTED_REGISTRY_UNAVAILABLE"
  EndIf
  Return Registry.RequestUiLoad(Self, requestedConsumerId)
EndFunction

; Waits only for a missing registry reference, then treats its first answer as terminal. Caller owns RegistrationAttemptActive.
; A positive case checks RequestUiLoad; an expected rejection never requests a UI load. Disabled transport is not failure.
Bool Function AttemptRegistration()
  Int attempt = 0
  While (attempt < 20)
    If (Registry != None)
      Bool actualRegistration = Registry.RegisterConsumer(Self, ConsumerId, DisplayName, NormalMoviePath, LargeMoviePath, DescriptorVersion)
      If (actualRegistration == ExpectedRegistration)
        If (actualRegistration)
          String loadResult = Registry.RequestUiLoad(Self, ConsumerId)
          LogUserInformational(ModuleName, "AttemptRegistration", "REGISTRATION_ACK | Consumer=" + ConsumerId + " | LoadUI=" + loadResult)
        Else
          LogUserInformational(ModuleName, "AttemptRegistration", "EXPECTED_REGISTRATION_REJECTION | No UI load requested.")
        EndIf
        Return True
      EndIf
      If (actualRegistration && !ExpectedRegistration)
        Registry.UnregisterConsumer(Self, ConsumerId)
      EndIf
      LogUserWarning(ModuleName, "AttemptRegistration", "Unexpected terminal registration result; see the Registry diagnostic. No retry or UI load requested.")
      Return False
    EndIf
    attempt += 1
    If (attempt < 20)
      Utility.WaitMenuPause(0.5)
    EndIf
  EndWhile

  LogUserWarning(ModuleName, "AttemptRegistration", "Registry reference remained unavailable during the bounded retry window.")
  Return False
EndFunction
