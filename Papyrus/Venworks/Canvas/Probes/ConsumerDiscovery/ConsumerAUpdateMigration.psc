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
