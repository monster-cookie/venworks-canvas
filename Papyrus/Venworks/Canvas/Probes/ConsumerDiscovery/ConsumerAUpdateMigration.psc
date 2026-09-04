ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerAUpdateMigration Extends Venworks:Canvas:Base:BaseQuest
Import Venworks:Canvas:Probes:ConsumerDiscovery:Registry

Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerARegistrar Property Registrar Auto Const Mandatory
String Property UpdatedDisplayName Auto Const Mandatory
String Property UpdatedNormalMoviePath Auto Const Mandatory
String Property UpdatedLargeMoviePath Auto Const Mandatory
Int Property UpdatedDescriptorVersion Auto Const Mandatory

String ModuleName = "Probes:ConsumerDiscovery:ConsumerAUpdateMigration"
; Saved acknowledgement only, never a lock. A failed/busy attempt cannot set it.
Bool MigrationApplied = False

; Reports this packaged script's runtime quest binding only; does not initialize storage or request work.
String Function ConsoleResolve() Global
  Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerAUpdateMigration target = ResolveConsoleMigration()
  If (target == None)
    Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ConsumerAUpdateMigration.ConsoleResolve | " + "CONSOLE_RESOLVE_FAILED")
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ConsumerAUpdateMigration.ConsoleResolve | " + "CONSOLE_RESOLVED")
  Return "CONSOLE_RESOLVED"
EndFunction

; Requests existing migration recovery; dispatch is not an acknowledgement that an update was applied.
String Function ConsoleRetryUpdate() Global
  Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerAUpdateMigration target = ResolveConsoleMigration()
  If (target == None)
    Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ConsumerAUpdateMigration.ConsoleRetryUpdate | " + "CONSOLE_RESOLVE_FAILED")
    Return "CONSOLE_RESOLVE_FAILED"
  EndIf
  target.RetryUpdate()
  LogConsoleMigration("ConsoleRetryUpdate", "CONSOLE_RETRY_REQUESTED | Await DESCRIPTOR_UPDATE_ACK; an already acknowledged update is not reset.")
  Venworks:Core:Utilities:Console.ConsoleEcho("VWCANVAS: ConsumerAUpdateMigration.ConsoleRetryUpdate | " + "CONSOLE_RETRY_REQUESTED")
  Return "CONSOLE_RETRY_REQUESTED"
EndFunction

; Resolve the permanent file-local identity on every explicit call; no Editor ID, cached target or external prefix.
Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerAUpdateMigration Function ResolveConsoleMigration() Global
  LogConsoleMigration("ResolveConsoleMigration", "CONSOLE_BEGIN | Plugin=Venworks-Canvas-ConsumerA.esm | LocalId=0x000801")
  Form targetForm = Game.GetFormFromFile(0x000801, "Venworks-Canvas-ConsumerA.esm")
  If (targetForm == None)
    LogConsoleMigration("ResolveConsoleMigration", "CONSOLE_TARGET_NOT_FOUND")
    Return None
  EndIf
  Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerAUpdateMigration target = targetForm as Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerAUpdateMigration
  If (target == None)
    LogConsoleMigration("ResolveConsoleMigration", "CONSOLE_SCRIPT_NOT_BOUND | Form=" + targetForm)
    Return None
  EndIf
  LogConsoleMigration("ResolveConsoleMigration", "CONSOLE_RESOLVED | Form=" + targetForm + " | RuntimeFormId=" + targetForm.GetFormID())
  Return target
EndFunction

; Global diagnostics cannot use instance logging or saved ModuleName; emit the same bounded build marker to both logs.
Function LogConsoleMigration(String functionName, String logMessage) Global
  Venworks:Core:Enumerations:LogSeverity severityTable = new Venworks:Core:Enumerations:LogSeverity
  Venworks:Core:Logging.LogUser(creationName="Venworks-Canvas", moduleName="Probes:ConsumerDiscovery:ConsumerAUpdateMigration", functionName=functionName, logMessage="VWCANVAS_CONSOLE/1 | " + logMessage, severity=severityTable.Info)
EndFunction

; Subscribe only. The new update quest must not enter a registrar guard indirectly during OnInit.
Event OnInit()
  EnsureMenuSubscriptions()
EndEvent

; Also callable by the explicit repair entry point for an old UpdatedA quest that already ran OnInit.
Function EnsureMenuSubscriptions()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
EndFunction

; Explicit console repair/retry for a saved migration quest; does not reset accepted descriptors or acknowledgements.
Function RetryUpdate()
  EnsureMenuSubscriptions()
  If (!MigrationApplied)
    StartTimer(0.3, 1)
  EndIf
EndFunction

; Retry the retained VMAD descriptor on a later HUD opening unless it has already been accepted.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening && !MigrationApplied)
    StartTimer(0.3, 1)
  EndIf
EndEvent

; Bounded asynchronous submission. A busy registrar has not accepted ownership of the request; keep it here.
Event OnTimer(Int aiTimerID)
  If (aiTimerID < 1 || aiTimerID > 20 || MigrationApplied)
    Return
  EndIf
  OperationResult result = NewResult("DEFERRED_REGISTRY_UNAVAILABLE")
  If (Registrar != None)
    result = Registrar.TryApplyDescriptorUpdate(UpdatedDisplayName, UpdatedNormalMoviePath, UpdatedLargeMoviePath, UpdatedDescriptorVersion)
    Registrar.ReportAttempt(result)
  EndIf
  If (IsRegistrationAccepted(result.Status))
    MigrationApplied = True
    LogUserInformational(ModuleName, "OnTimer", "DESCRIPTOR_UPDATE_ACK | Version=" + UpdatedDescriptorVersion)
  ElseIf (IsDeferred(result.Status))
    If (aiTimerID < 20)
      StartTimer(0.5, aiTimerID + 1)
    Else
      LogUserWarning(ModuleName, "OnTimer", "DESCRIPTOR_UPDATE_RETRY_EXHAUSTED | Request retained here for a later HUD opening.")
    EndIf
  Else
    LogUserError(ModuleName, "OnTimer", "DESCRIPTOR_UPDATE_REJECTED | " + result.Status + " | No automatic retry.")
  EndIf
EndEvent
