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
Guard AttemptGuard ProtectsFunctionLogic

; Registers for both HUD menus and attempts the VMAD-configured descriptor after its configured delay.
Event OnInit()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  If (InitialDelaySeconds > 0.0)
    Utility.Wait(InitialDelaySeconds)
  EndIf
  RegisterWithRetry()
EndEvent

; Reconciles the VMAD descriptor when either HUD opens. Overlapping attempts serialize and no bridge publication occurs.
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
  Bool result = False
  LockGuard AttemptGuard
    RegistrationAttemptActive = True
    result = AttemptRegistration()
    RegistrationAttemptActive = False
  EndLockGuard
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
      String registrationId = ResolveRegistrationId()
      Bool actualRegistration = Registry.RegisterConsumer(Self, registrationId, DisplayName, NormalMoviePath, LargeMoviePath, DescriptorVersion)
      If (actualRegistration == ExpectedRegistration)
        If (actualRegistration)
          String loadResult = Registry.RequestUiLoad(Self, registrationId)
          LogUserInformational(ModuleName, "AttemptRegistration", "REGISTRATION_ACK | Consumer=" + registrationId + " | LoadUI=" + loadResult)
        Else
          LogUserInformational(ModuleName, "AttemptRegistration", "EXPECTED_REGISTRATION_REJECTION | No UI load requested.")
        EndIf
        Return True
      EndIf
      If (actualRegistration && !ExpectedRegistration)
        Registry.UnregisterConsumer(Self, registrationId)
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

; Returns the supplied UUID or performs only the explicit legacy demonstration mapping. Never generates an ID.
; The owner-checked rekey preserves a saved descriptor. Unknown legacy IDs fail closed at the registry.
String Function ResolveRegistrationId()
  If (Venworks:Core:Utilities:UUID.IsValid(ConsumerId))
    ; Updated VMAD may supply a UUID while the saved registry still contains its old demo key.
    ; Rekey only this owner's known demo row. A conflict remains a terminal RegisterConsumer rejection.
    If (Venworks:Core:Utilities:UUID.AreEqual(ConsumerId, "a8098c1a-f86e-4b1e-9d7c-5a102bf38460"))
      Registry.MigrateConsumerIdentity(Self, "venworks.canvas.probe.consumer-a", ConsumerId)
    ElseIf (Venworks:Core:Utilities:UUID.AreEqual(ConsumerId, "beef70b2-024e-4e9b-a8d5-70a0c882c431"))
      Registry.MigrateConsumerIdentity(Self, "venworks.canvas.probe.consumer-b", ConsumerId)
    ElseIf (Venworks:Core:Utilities:UUID.AreEqual(ConsumerId, "cad7cd56-217a-4e62-a98d-42c3adad07b5"))
      Registry.MigrateConsumerIdentity(Self, "venworks.canvas.probe.missing", ConsumerId)
    EndIf
    Return Venworks:Core:Utilities:UUID.Normalize(ConsumerId)
  EndIf
  String migratedId = ""
  If (Registry.SameAsciiText(ConsumerId, "venworks.canvas.probe.consumer-a"))
    migratedId = "a8098c1a-f86e-4b1e-9d7c-5a102bf38460"
  ElseIf (Registry.SameAsciiText(ConsumerId, "venworks.canvas.probe.consumer-b"))
    migratedId = "beef70b2-024e-4e9b-a8d5-70a0c882c431"
  ElseIf (Registry.SameAsciiText(ConsumerId, "venworks.canvas.probe.missing"))
    migratedId = "cad7cd56-217a-4e62-a98d-42c3adad07b5"
  EndIf
  If (migratedId != "" && Registry.MigrateConsumerIdentity(Self, ConsumerId, migratedId))
    Return migratedId
  EndIf
  Return ""
EndFunction
