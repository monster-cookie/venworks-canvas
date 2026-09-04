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

; Reports this packaged script's runtime quest binding only; does not initialize storage or request work.
String Function ConsoleResolve() Global
  Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar target = ResolveConsoleConsumerB()
  If (target == None)
    Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ConsumerBRegistrar.ConsoleResolve | " + "CONSOLE_RESOLVE_FAILED")
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ConsumerBRegistrar.ConsoleResolve | " + "CONSOLE_RESOLVED")
  Return "CONSOLE_RESOLVED"
EndFunction

; One explicit B-owned request; pass the original UUID unchanged and never register or schedule a retry here.
String Function ConsoleCheckUiLoadRequest(String requestedConsumerId) Global
  Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar target = ResolveConsoleConsumerB()
  If (target == None)
    Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ConsumerBRegistrar.ConsoleCheckUiLoadRequest | " + "CONSOLE_RESOLVE_FAILED")
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  String result = target.CheckUiLoadRequest(requestedConsumerId)
  LogConsoleConsumerB("ConsoleCheckUiLoadRequest", "CONSOLE_RESULT | Status=" + result)
  Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ConsumerBRegistrar.ConsoleCheckUiLoadRequest | " + result)
  Return result
EndFunction

; Resolve the permanent file-local identity on every explicit call; no Editor ID, cached target or external prefix.
Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar Function ResolveConsoleConsumerB() Global
  LogConsoleConsumerB("ResolveConsoleConsumerB", "CONSOLE_BEGIN | Plugin=Venworks-Canvas-ConsumerB.esm | LocalId=0x000800")
  Form targetForm = Game.GetFormFromFile(0x000800, "Venworks-Canvas-ConsumerB.esm")
  If (targetForm == None)
    LogConsoleConsumerB("ResolveConsoleConsumerB", "CONSOLE_TARGET_NOT_FOUND")
    Return None
  EndIf
  Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar target = targetForm as Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar
  If (target == None)
    LogConsoleConsumerB("ResolveConsoleConsumerB", "CONSOLE_SCRIPT_NOT_BOUND | Form=" + targetForm)
    Return None
  EndIf
  LogConsoleConsumerB("ResolveConsoleConsumerB", "CONSOLE_RESOLVED | Form=" + targetForm + " | RuntimeFormId=" + targetForm.GetFormID())
  Return target
EndFunction

; Global diagnostics cannot use instance logging or saved ModuleName; emit the same bounded build marker to both logs.
Function LogConsoleConsumerB(String functionName, String logMessage) Global
  Venworks:Core:Enumerations:LogSeverity severityTable = new Venworks:Core:Enumerations:LogSeverity
  Venworks:Core:Logging.LogUser(creationName="Venworks-Canvas", moduleName="Probes:ConsumerDiscovery:ConsumerBRegistrar", functionName=functionName, logMessage="VWCANVAS_CONSOLE/1 | " + logMessage, severity=severityTable.Info)
EndFunction

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
  RequestRegisteredUi(result)
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
  Return Registry.CheckUiLoadRequest(Self, requestedConsumerId)
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
      result.UiLoad = "UI_LOAD_REQUEST_NEEDED"
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

; The consumer's explicit second step. Registration workers only mark intent; invoke outside all guards.
Function RequestRegisteredUi(OperationResult result)
  If (Registry != None && IsRegistrationAccepted(result.Status) && result.UiLoad == "UI_LOAD_REQUEST_NEEDED")
    OperationResult loadResult = Registry.TryRequestUiLoad(Self, result.ConsumerId)
    result.UiLoad = loadResult.Status
    Registry.LogOperation(loadResult)
  EndIf
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
