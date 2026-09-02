ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerAUpdateMigration Extends Venworks:Canvas:Base:BaseQuest

Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerARegistrar Property Registrar Auto Const Mandatory
String Property UpdatedDisplayName Auto Const Mandatory
String Property UpdatedNormalMoviePath Auto Const Mandatory
String Property UpdatedLargeMoviePath Auto Const Mandatory
Int Property UpdatedDescriptorVersion Auto Const Mandatory

String ModuleName = "Probes:ConsumerDiscovery:ConsumerAUpdateMigration"

; Runs once on the new UpdatedA quest form and asks the existing registrar owner to publish the replacement descriptor.
Event OnInit()
  If (Registrar == None)
    LogUserError(ModuleName, "OnInit", "Cannot apply the Consumer A update because its existing registrar is unavailable.")
    Return
  EndIf

  If (Registrar.ApplyDescriptorUpdate(UpdatedDisplayName, UpdatedNormalMoviePath, UpdatedLargeMoviePath, UpdatedDescriptorVersion))
    LogUserInformational(ModuleName, "OnInit", "Applied the explicit Consumer A descriptor update.")
  Else
    LogUserError(ModuleName, "OnInit", "The existing Consumer A registrar did not accept the explicit descriptor update.")
  EndIf
EndEvent
