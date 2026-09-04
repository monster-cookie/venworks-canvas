ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar Extends Venworks:Canvas:Base:BaseQuest
Import Venworks:Canvas:Probes:ConsumerDiscovery:Registry

Venworks:Canvas:Probes:ConsumerDiscovery:Registry Property Registry Auto Const Mandatory
String Property ConsumerId Auto Const Mandatory
String Property DisplayName Auto Const Mandatory
String Property NormalMoviePath Auto Const Mandatory
String Property LargeMoviePath Auto Const Mandatory
Int Property DescriptorVersion Auto Const Mandatory
Bool Property ExpectedRegistration Auto Const Mandatory
Float Property InitialDelaySeconds Auto Const Mandatory

String ModuleName = "Probes:ConsumerDiscovery:ConsumerBRegistrar"
; Retained for saved-script compatibility only; this flag is never consulted as a lock or scheduling gate.
Bool RegistrationAttemptActive = False
Guard AttemptGuard ProtectsFunctionLogic

; Bootstrap only: no wait, registration, storage access or guard acquisition in OnInit.
Event OnInit()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
EndEvent

; HUD opening schedules a bounded sequence; there is no saved active latch or wait in this event.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening)
    Float delay = InitialDelaySeconds
    If (delay < 0.1)
      delay = 0.1
    EndIf
    StartTimer(delay, 1)
  EndIf
EndEvent

; Each timer ID is an attempt number, so retry exhaustion needs no cross-stack mutable counter.
Event OnTimer(Int aiTimerID)
  If (aiTimerID >= 1 && aiTimerID <= 20)
    ProcessAttempt(aiTimerID)
  EndIf
EndEvent

; Compatibility entry point. A positive result acknowledges only the expected Papyrus result, never UI readiness.
Bool Function RegisterWithRetry()
  Return ProcessAttempt(1)
EndFunction

; One attempt followed by diagnostics and optional scheduling, all outside the acquired guards.
Bool Function ProcessAttempt(Int attempt)
  OperationResult result = TryReconcile()
  ReportAttempt(result)
  If (IsDeferred(result.Status) || IsDeferred(result.UiLoad))
    If (attempt < 20)
      StartTimer(0.5, attempt + 1)
    Else
      LogUserWarning(ModuleName, "ProcessAttempt", "REGISTRATION_RETRY_EXHAUSTED | Pending data retained; later HUD opening or explicit request may retry.")
    EndIf
  EndIf
  Return IsRegistrationAccepted(result.Status) || result.Status == "EXPECTED_REGISTRATION_REJECTION"
EndFunction

; Holds AttemptGuard for one non-waiting host transaction. Registry never calls back into a registrar.
OperationResult Function TryReconcile()
  If (Registry != None)
    Registry.EnsureMenuSubscriptions()
  EndIf
  OperationResult result = NewResult("DEFERRED_ATTEMPT_BUSY")
  TryLockGuard AttemptGuard
    result = AttemptDescriptorRegistration(DisplayName, NormalMoviePath, LargeMoviePath, DescriptorVersion, ExpectedRegistration)
  EndTryLockGuard
  Return result
EndFunction

; Explicit console probe: never registers or transmits data; busy is returned separately from rejected input.
String Function CheckUiLoadRequest(String requestedConsumerId)
  If (Registry == None)
    LogUserWarning(ModuleName, "CheckUiLoadRequest", "DEFERRED_REGISTRY_UNAVAILABLE")
    Return "DEFERRED_REGISTRY_UNAVAILABLE"
  EndIf
  Return Registry.RequestUiLoad(Self, requestedConsumerId)
EndFunction

; Compatibility entry point now uses one attempt and bounded deferred retry, never a guarded wait.
Bool Function AttemptRegistration()
  Return RegisterWithRetry()
EndFunction

; Caller holds AttemptGuard. All host calls are nonblocking receipts without logging or callbacks.
OperationResult Function AttemptDescriptorRegistration(String requestedDisplayName, String requestedNormalMovieUrl, String requestedLargeMovieUrl, Int requestedDescriptorVersion, Bool expectedResult)
  If (Registry == None)
    Return NewResult("DEFERRED_REGISTRY_UNAVAILABLE")
  EndIf
  String registrationId = ResolveRegistrationId()
  OperationResult result = Registry.TryRegisterConsumer(Self, registrationId, requestedDisplayName, requestedNormalMovieUrl, requestedLargeMovieUrl, requestedDescriptorVersion, ResolveLegacyId(registrationId))
  If (IsDeferred(result.Status))
    Return result
  EndIf
  If (IsRegistrationAccepted(result.Status))
    If (expectedResult)
      OperationResult loadResult = Registry.TryRequestUiLoad(Self, registrationId)
      result.UiLoad = loadResult.Status
    Else
      OperationResult removal = Registry.TryUnregisterConsumer(Self, registrationId)
      If (IsDeferred(removal.Status))
        Return removal
      EndIf
      result.Status = "UNEXPECTED_REGISTRATION_ACCEPTANCE"
      result.Detail = "Negative fixture accepted; cleanup=" + removal.Status
    EndIf
  ElseIf (!expectedResult && (result.Status == "REGISTRATION_REJECTED" || result.Status == "REJECTED_OWNER_MISMATCH"))
    result.Detail = result.Status + " | " + result.Detail
    result.Status = "EXPECTED_REGISTRATION_REJECTION"
  EndIf
  Return result
EndFunction

; Diagnostics consume the per-call receipt only after AttemptGuard and RegistryGuard have both ended.
Function ReportAttempt(OperationResult result)
  If (Registry != None)
    Registry.LogOperation(result)
  EndIf
  If (IsRegistrationAccepted(result.Status))
    LogUserInformational(ModuleName, "ReportAttempt", "REGISTRATION_ACK | Consumer=" + result.ConsumerId + " | LoadUI=" + result.UiLoad)
  ElseIf (result.Status == "EXPECTED_REGISTRATION_REJECTION")
    LogUserInformational(ModuleName, "ReportAttempt", "EXPECTED_REGISTRATION_REJECTION | No UI load requested.")
  ElseIf (IsDeferred(result.Status))
    LogUserWarning(ModuleName, "ReportAttempt", "DESCRIPTOR_UPDATE_PENDING / REGISTRATION_DEFERRED | " + result.Status + " | Busy caller must retain unsubmitted input.")
  Else
    LogUserWarning(ModuleName, "ReportAttempt", "Unexpected terminal registration result | " + result.Status + " | No automatic retry.")
  EndIf
EndFunction

; Pure identity resolution; a busy host can never become an empty/invalid UUID.
String Function ResolveRegistrationId()
  If (Venworks:Core:Utilities:UUID.IsValid(ConsumerId))
    Return Venworks:Core:Utilities:UUID.Normalize(ConsumerId)
  EndIf
  If (Registry.SameAsciiText(ConsumerId, "venworks.canvas.probe.consumer-a"))
    Return "a8098c1a-f86e-4b1e-9d7c-5a102bf38460"
  ElseIf (Registry.SameAsciiText(ConsumerId, "venworks.canvas.probe.consumer-b"))
    Return "beef70b2-024e-4e9b-a8d5-70a0c882c431"
  ElseIf (Registry.SameAsciiText(ConsumerId, "venworks.canvas.probe.missing"))
    Return "cad7cd56-217a-4e62-a98d-42c3adad07b5"
  EndIf
  Return ""
EndFunction

; Only known demo UUIDs supply a legacy key; host rekey and registration are one guarded transaction.
String Function ResolveLegacyId(String registrationId)
  If (Venworks:Core:Utilities:UUID.AreEqual(registrationId, "a8098c1a-f86e-4b1e-9d7c-5a102bf38460"))
    Return "venworks.canvas.probe.consumer-a"
  ElseIf (Venworks:Core:Utilities:UUID.AreEqual(registrationId, "beef70b2-024e-4e9b-a8d5-70a0c882c431"))
    Return "venworks.canvas.probe.consumer-b"
  ElseIf (Venworks:Core:Utilities:UUID.AreEqual(registrationId, "cad7cd56-217a-4e62-a98d-42c3adad07b5"))
    Return "venworks.canvas.probe.missing"
  EndIf
  Return ""
EndFunction
