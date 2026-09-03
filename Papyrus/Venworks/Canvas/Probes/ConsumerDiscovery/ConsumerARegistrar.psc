ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerARegistrar Extends Venworks:Canvas:Base:BaseQuest

Venworks:Canvas:Probes:ConsumerDiscovery:Registry Property Registry Auto Const Mandatory
String Property ConsumerId Auto Const Mandatory
String Property DisplayName Auto Const Mandatory
String Property NormalMoviePath Auto Const Mandatory
String Property LargeMoviePath Auto Const Mandatory
Int Property DescriptorVersion Auto Const Mandatory
Bool Property ExpectedRegistration Auto Const Mandatory
Float Property InitialDelaySeconds Auto Const Mandatory

String ModuleName = "Probes:ConsumerDiscovery:ConsumerARegistrar"
String ActiveDisplayName
String ActiveNormalMovieUrl
String ActiveLargeMovieUrl
Int ActiveDescriptorVersion = 0
Bool RegistrationAttemptActive = False
Guard AttemptGuard ProtectsFunctionLogic
Bool PendingUpdate = False
String PendingDisplayName
String PendingNormalMovieUrl
String PendingLargeMovieUrl
Int PendingDescriptorVersion = 0

; Registers for both HUD menus and attempts the active descriptor, initially seeded from VMAD, after its configured delay.
Event OnInit()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  If (InitialDelaySeconds > 0.0)
    Utility.Wait(InitialDelaySeconds)
  EndIf
  RegisterWithRetry()
EndEvent

; Reconciles the persistent descriptor when either HUD opens. Overlapping attempts serialize and no bridge publication occurs.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening)
    If (InitialDelaySeconds > 0.0)
      Utility.WaitMenuPause(InitialDelaySeconds)
    EndIf
    RegisterWithRetry()
  EndIf
EndEvent

; Attempts the persistent descriptor once the registry is available. True means the expected Papyrus result, never UI readiness.
Bool Function RegisterWithRetry()
  Bool result = False
  LockGuard AttemptGuard
    RegistrationAttemptActive = True
    EnsureActiveDescriptor()
    If (PendingUpdate)
      result = ApplyPendingUpdate()
    Else
      result = AttemptDescriptorRegistration(ActiveDisplayName, ActiveNormalMovieUrl, ActiveLargeMovieUrl, ActiveDescriptorVersion, ExpectedRegistration)
    EndIf
    RegistrationAttemptActive = False
  EndLockGuard
  Return result
EndFunction

; Persists one pending update before attempting it. Concurrent callers serialize behind the active attempt rather than dropping the update.
; True means accepted by the registry; False leaves unavailable-registry work pending, or records terminal invalid input.
Bool Function ApplyDescriptorUpdate(String updatedDisplayName, String updatedNormalMovieUrl, String updatedLargeMovieUrl, Int updatedDescriptorVersion)
  LockGuard AttemptGuard
    PendingDisplayName = updatedDisplayName
    PendingNormalMovieUrl = updatedNormalMovieUrl
    PendingLargeMovieUrl = updatedLargeMovieUrl
    PendingDescriptorVersion = updatedDescriptorVersion
    PendingUpdate = True
  EndLockGuard
  Return RegisterWithRetry()
EndFunction

; Internal worker under AttemptGuard. Commits active fields only after registry success; missing registry leaves pending data for reconciliation.
Bool Function ApplyPendingUpdate()
  Bool applied = AttemptDescriptorRegistration(PendingDisplayName, PendingNormalMovieUrl, PendingLargeMovieUrl, PendingDescriptorVersion, True)
  If (applied)
    ActiveDisplayName = PendingDisplayName
    ActiveNormalMovieUrl = PendingNormalMovieUrl
    ActiveLargeMovieUrl = PendingLargeMovieUrl
    ActiveDescriptorVersion = PendingDescriptorVersion
    PendingUpdate = False
    LogUserInformational(ModuleName, "ApplyPendingUpdate", "DESCRIPTOR_UPDATE_APPLIED | Version=" + ActiveDescriptorVersion)
  ElseIf (Registry != None)
    PendingUpdate = False
    LogUserWarning(ModuleName, "ApplyPendingUpdate", "DESCRIPTOR_UPDATE_REJECTED | Terminal host rejection.")
  Else
    LogUserWarning(ModuleName, "ApplyPendingUpdate", "DESCRIPTOR_UPDATE_PENDING | Registry unavailable; retained for next reconciliation.")
  EndIf
  Return applied
EndFunction

; Initializes the persistent active descriptor from VMAD defaults when this quest has not accepted an explicit update.
Function EnsureActiveDescriptor()
  If (ActiveDescriptorVersion < 1)
    ActiveDisplayName = DisplayName
    ActiveNormalMovieUrl = NormalMoviePath
    ActiveLargeMovieUrl = LargeMoviePath
    ActiveDescriptorVersion = DescriptorVersion
  EndIf
EndFunction

; Compatibility entry point that serializes an explicit descriptor attempt. True acknowledges the expected registration result only.
Bool Function RegisterDescriptorWithRetry(String requestedDisplayName, String requestedNormalMovieUrl, String requestedLargeMovieUrl, Int requestedDescriptorVersion, Bool expectedResult)
  Bool result = False
  LockGuard AttemptGuard
    RegistrationAttemptActive = True
    result = AttemptDescriptorRegistration(requestedDisplayName, requestedNormalMovieUrl, requestedLargeMovieUrl, requestedDescriptorVersion, expectedResult)
    RegistrationAttemptActive = False
  EndLockGuard
  Return result
EndFunction

; Waits only for a missing registry reference, then treats its first answer as terminal. Caller owns RegistrationAttemptActive.
; A successful positive case checks RequestUiLoad; an expected rejection never requests a UI load. Disabled transport is not failure.
Bool Function AttemptDescriptorRegistration(String requestedDisplayName, String requestedNormalMovieUrl, String requestedLargeMovieUrl, Int requestedDescriptorVersion, Bool expectedResult)
  Int attempt = 0
  While (attempt < 20)
    If (Registry != None)
      String registrationId = ResolveRegistrationId()
      Bool actualRegistration = Registry.RegisterConsumer(Self, registrationId, requestedDisplayName, requestedNormalMovieUrl, requestedLargeMovieUrl, requestedDescriptorVersion)
      If (actualRegistration == expectedResult)
        If (actualRegistration)
          String loadResult = Registry.RequestUiLoad(Self, registrationId)
          LogUserInformational(ModuleName, "AttemptDescriptorRegistration", "REGISTRATION_ACK | Consumer=" + registrationId + " | LoadUI=" + loadResult)
        Else
          LogUserInformational(ModuleName, "AttemptDescriptorRegistration", "EXPECTED_REGISTRATION_REJECTION | No UI load requested.")
        EndIf
        Return True
      EndIf
      If (actualRegistration && !expectedResult)
        Registry.UnregisterConsumer(Self, registrationId)
      EndIf
      LogUserWarning(ModuleName, "AttemptDescriptorRegistration", "Unexpected terminal registration result; see the Registry diagnostic. No retry or UI load requested.")
      Return False
    EndIf
    attempt += 1
    If (attempt < 20)
      Utility.WaitMenuPause(0.5)
    EndIf
  EndWhile

  LogUserWarning(ModuleName, "AttemptDescriptorRegistration", "Registry reference remained unavailable during the bounded retry window.")
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
