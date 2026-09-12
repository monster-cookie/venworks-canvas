ScriptName Venworks:CanvasExamples:ExampleRegistrar Extends Venworks:Canvas:Base:BaseQuest
Import Venworks:Canvas:Registry

Venworks:Canvas:Registry Property Registry Auto Const Mandatory
String Property ConsumerId Auto Const Mandatory
String Property DisplayName Auto Const Mandatory
String Property NormalMoviePath Auto Const Mandatory
String Property LargeMoviePath Auto Const Mandatory
Int Property DescriptorVersion Auto Const Mandatory
Bool Property ExpectedRegistration Auto Const Mandatory
Float Property InitialDelaySeconds Auto Const Mandatory

String ModuleName = "CanvasExamples:ExampleRegistrar"
; Retained for saved-script compatibility only; this flag is never consulted as a lock or scheduling gate.
Bool RegistrationAttemptActive = False
Guard AttemptGuard ProtectsFunctionLogic
String ActiveDisplayName
String ActiveNormalMovieUrl
String ActiveLargeMovieUrl
Int ActiveDescriptorVersion = 0
Bool PendingUpdate = False
String PendingDisplayName
String PendingNormalMovieUrl
String PendingLargeMovieUrl
Int PendingDescriptorVersion = 0

; Reports this packaged script's runtime quest binding only; does not register or request UI work.
String Function ConsoleResolve() Global
  Venworks:CanvasExamples:ExampleRegistrar target = ResolveConsoleExample()
  If (target == None)
    Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ExampleRegistrar.ConsoleResolve | " + "CONSOLE_RESOLVE_FAILED")
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ExampleRegistrar.ConsoleResolve | " + "CONSOLE_RESOLVED")
  Return "CONSOLE_RESOLVED"
EndFunction

; Makes one Example-owned publication attempt. The actual transport status is logged, echoed and returned unchanged.
String Function ConsolePing() Global
  Venworks:CanvasExamples:ExampleRegistrar target = ResolveConsoleExample()
  If (target == None)
    Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ExampleRegistrar.ConsolePing | " + "CONSOLE_RESOLVE_FAILED")
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  String result = target.PublishConsolePing()
  LogConsoleExample("ConsolePing", "CONSOLE_RESULT | Status=" + result)
  Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ExampleRegistrar.ConsolePing | " + result)
  Return result
EndFunction

; Switches the packaged Example registration to the subscriptions diagnostic and requests one UI load.
String Function ConsoleSubscriptionsProbe() Global
  Venworks:CanvasExamples:ExampleRegistrar target = ResolveConsoleExample()
  If (target == None)
    Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ExampleRegistrar.ConsoleSubscriptionsProbe | " + "CONSOLE_RESOLVE_FAILED")
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  String result = target.SelectConsoleSubscriptionsProbe()
  LogConsoleExample("ConsoleSubscriptionsProbe", "CONSOLE_RESULT | Status=" + result)
  Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ExampleRegistrar.ConsoleSubscriptionsProbe | " + result)
  Return result
EndFunction

; Restores the packaged Example registration after a subscriptions diagnostic run and requests one UI load.
String Function ConsoleRestoreExample() Global
  Venworks:CanvasExamples:ExampleRegistrar target = ResolveConsoleExample()
  If (target == None)
    Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ExampleRegistrar.ConsoleRestoreExample | " + "CONSOLE_RESOLVE_FAILED")
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  String result = target.RestoreConsoleExample()
  LogConsoleExample("ConsoleRestoreExample", "CONSOLE_RESULT | Status=" + result)
  Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ExampleRegistrar.ConsoleRestoreExample | " + result)
  Return result
EndFunction

; The command has no caller-selected topic or body and never registers, requests UI work or schedules a retry.
String Function PublishConsolePing()
  If (Registry == None)
    LogUserWarning(ModuleName, "PublishConsolePing", "DEFERRED_REGISTRY_UNAVAILABLE")
    Return "DEFERRED_REGISTRY_UNAVAILABLE"
  EndIf
  OperationResult result = Registry.TryPublishCanvasEvent("venworks.canvas.example.ping", "ping")
  Registry.LogOperation(result)
  Return result.Status
EndFunction

; Selects the packaged subscriptions diagnostic using a distinct descriptor version so the host replaces the Example movie.
String Function SelectConsoleSubscriptionsProbe()
  Return SubmitConsoleDescriptorUpdate("VWCANVAS Subscriptions Probe", "VenworksCanvas/Consumers/venworks.canvas.example.subscriptions-probe/normal.swf", "VenworksCanvas/Consumers/venworks.canvas.example.subscriptions-probe/large.swf", 2)
EndFunction

; Restores the authored Example descriptor after a diagnostic run.
String Function RestoreConsoleExample()
  Return SubmitConsoleDescriptorUpdate(DisplayName, NormalMoviePath, LargeMoviePath, DescriptorVersion)
EndFunction

; Makes one explicit descriptor update and UI-load request; retained deferred input uses the registrar's existing timer reconciliation.
String Function SubmitConsoleDescriptorUpdate(String requestedDisplayName, String requestedNormalMovieUrl, String requestedLargeMovieUrl, Int requestedDescriptorVersion)
  OperationResult result = TryApplyDescriptorUpdate(requestedDisplayName, requestedNormalMovieUrl, requestedLargeMovieUrl, requestedDescriptorVersion)
  RequestRegisteredUi(result)
  ReportAttempt(result)
  If (result.Status != "DEFERRED_ATTEMPT_BUSY" && (IsDeferred(result.Status) || IsDeferred(result.UiLoad)))
    StartTimer(0.5, 1)
  EndIf
  If (result.UiLoad != "")
    Return result.Status + " | " + result.UiLoad
  EndIf
  Return result.Status
EndFunction

; Resolve the permanent file-local identity on every explicit call; no Editor ID, cached target or external prefix.
Venworks:CanvasExamples:ExampleRegistrar Function ResolveConsoleExample() Global
  LogConsoleExample("ResolveConsoleExample", "CONSOLE_BEGIN | Plugin=Venworks-Canvas-Example.esm | LocalId=0x000800")
  Form targetForm = Game.GetFormFromFile(0x000800, "Venworks-Canvas-Example.esm")
  If (targetForm == None)
    LogConsoleExample("ResolveConsoleExample", "CONSOLE_TARGET_NOT_FOUND")
    Return None
  EndIf
  Venworks:CanvasExamples:ExampleRegistrar target = targetForm as Venworks:CanvasExamples:ExampleRegistrar
  If (target == None)
    LogConsoleExample("ResolveConsoleExample", "CONSOLE_SCRIPT_NOT_BOUND | Form=" + targetForm)
    Return None
  EndIf
  LogConsoleExample("ResolveConsoleExample", "CONSOLE_RESOLVED | Form=" + targetForm + " | RuntimeFormId=" + targetForm.GetFormID())
  Return target
EndFunction

; Global diagnostics cannot use instance logging or saved ModuleName; emit the same bounded build marker to both logs.
Function LogConsoleExample(String functionName, String logMessage) Global
  Venworks:Core:Enumerations:LogSeverity severityTable = new Venworks:Core:Enumerations:LogSeverity
  Venworks:Core:Logging.LogUser(creationName="Venworks-Canvas", moduleName="CanvasExamples:ExampleRegistrar", functionName=functionName, logMessage="VWCANVAS_CONSOLE/1 | " + logMessage, severity=severityTable.Info)
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
    EnsureActiveDescriptor()
    If (PendingUpdate)
      result = ApplyPendingUpdateLocked()
    Else
      result = AttemptDescriptorRegistration(ActiveDisplayName, ActiveNormalMovieUrl, ActiveLargeMovieUrl, ActiveDescriptorVersion, ExpectedRegistration)
    EndIf
  EndTryLockGuard
  Return result
EndFunction

; Compatibility Boolean: true means accepted; false may mean deferred. Explicit callers must retain input until accepted.
Bool Function ApplyDescriptorUpdate(String updatedDisplayName, String updatedNormalMovieUrl, String updatedLargeMovieUrl, Int updatedDescriptorVersion)
  OperationResult result = TryApplyDescriptorUpdate(updatedDisplayName, updatedNormalMovieUrl, updatedLargeMovieUrl, updatedDescriptorVersion)
  RequestRegisteredUi(result)
  ReportAttempt(result)
  If (IsDeferred(result.Status) || IsDeferred(result.UiLoad))
    StartTimer(0.5, 1)
  EndIf
  Return IsRegistrationAccepted(result.Status)
EndFunction

; Busy AttemptGuard means input was NOT retained: the caller must resubmit the same request.
; Once acquired, retain the entire pending descriptor before contacting the registry. No waiting/logging inside the guard.
OperationResult Function TryApplyDescriptorUpdate(String updatedDisplayName, String updatedNormalMovieUrl, String updatedLargeMovieUrl, Int updatedDescriptorVersion)
  If (Registry != None)
    Registry.EnsureMenuSubscriptions()
  EndIf
  OperationResult result = NewResult("DEFERRED_ATTEMPT_BUSY")
  TryLockGuard AttemptGuard
    EnsureActiveDescriptor()
    PendingDisplayName = updatedDisplayName
    PendingNormalMovieUrl = updatedNormalMovieUrl
    PendingLargeMovieUrl = updatedLargeMovieUrl
    PendingDescriptorVersion = updatedDescriptorVersion
    PendingUpdate = True
    result = ApplyPendingUpdateLocked()
  EndTryLockGuard
  Return result
EndFunction

; Caller holds AttemptGuard. Commit active state on registration acceptance, regardless of disabled/deferred UI transport.
OperationResult Function ApplyPendingUpdateLocked()
  OperationResult result = AttemptDescriptorRegistration(PendingDisplayName, PendingNormalMovieUrl, PendingLargeMovieUrl, PendingDescriptorVersion, True)
  If (IsRegistrationAccepted(result.Status))
    ActiveDisplayName = PendingDisplayName
    ActiveNormalMovieUrl = PendingNormalMovieUrl
    ActiveLargeMovieUrl = PendingLargeMovieUrl
    ActiveDescriptorVersion = PendingDescriptorVersion
    PendingUpdate = False
    result.UpdateApplied = True
  ElseIf (!IsDeferred(result.Status))
    PendingUpdate = False
  EndIf
  Return result
EndFunction

; Initializes saved active fields only until an explicit accepted update has replaced the VMAD defaults.
Function EnsureActiveDescriptor()
  If (ActiveDescriptorVersion < 1)
    ActiveDisplayName = DisplayName
    ActiveNormalMovieUrl = NormalMoviePath
    ActiveLargeMovieUrl = LargeMoviePath
    ActiveDescriptorVersion = DescriptorVersion
  EndIf
EndFunction

; Compatibility explicit-descriptor entry point: one nonblocking attempt. On false, the caller retains/retries its supplied input.
Bool Function RegisterDescriptorWithRetry(String requestedDisplayName, String requestedNormalMovieUrl, String requestedLargeMovieUrl, Int requestedDescriptorVersion, Bool expectedResult)
  If (Registry != None)
    Registry.EnsureMenuSubscriptions()
  EndIf
  OperationResult result = NewResult("DEFERRED_ATTEMPT_BUSY")
  TryLockGuard AttemptGuard
    result = AttemptDescriptorRegistration(requestedDisplayName, requestedNormalMovieUrl, requestedLargeMovieUrl, requestedDescriptorVersion, expectedResult)
  EndTryLockGuard
  RequestRegisteredUi(result)
  ReportAttempt(result)
  Return IsRegistrationAccepted(result.Status) || result.Status == "EXPECTED_REGISTRATION_REJECTION"
EndFunction

; Caller holds AttemptGuard. All host calls are nonblocking receipts without logging or callbacks.
OperationResult Function AttemptDescriptorRegistration(String requestedDisplayName, String requestedNormalMovieUrl, String requestedLargeMovieUrl, Int requestedDescriptorVersion, Bool expectedResult)
  If (Registry == None)
    Return NewResult("DEFERRED_REGISTRY_UNAVAILABLE")
  EndIf
  String registrationId = ResolveRegistrationId()
  OperationResult result = Registry.TryRegisterConsumer(Self, registrationId, requestedDisplayName, requestedNormalMovieUrl, requestedLargeMovieUrl, requestedDescriptorVersion)
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

; An accepted descriptor may defer UI independently; schedule this consumer's own bounded reconciliation.
Function RetryRegisteredUi()
  StartTimer(0.5, 1)
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
    If (result.UpdateApplied)
      LogUserInformational(ModuleName, "ReportAttempt", "DESCRIPTOR_UPDATE_APPLIED | Version=" + result.DescriptorVersion + " | Retained independently of UI transport.")
    EndIf
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
  Return ""
EndFunction
