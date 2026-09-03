ScriptName Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerAUpdateMigration Extends Venworks:Canvas:Base:BaseQuest

Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerARegistrar Property Registrar Auto Const Mandatory
String Property UpdatedDisplayName Auto Const Mandatory
String Property UpdatedNormalMoviePath Auto Const Mandatory
String Property UpdatedLargeMoviePath Auto Const Mandatory
Int Property UpdatedDescriptorVersion Auto Const Mandatory

String ModuleName = "Probes:ConsumerDiscovery:ConsumerAUpdateMigration"

; On initialization of the new UpdatedA quest form, asks the existing owner to register the replacement descriptor without UI publication.
Event OnInit()
  If (Registrar == None)
    LogUserError(ModuleName, "OnInit", "Cannot apply the Consumer A update because its existing registrar is unavailable.")
    Return
  EndIf

  If (Registrar.ApplyDescriptorUpdate(UpdatedDisplayName, UpdatedNormalMoviePath, UpdatedLargeMoviePath, UpdatedDescriptorVersion))
    LogUserInformational(ModuleName, "OnInit", "Applied the explicit Consumer A descriptor update.")
  Else
    LogUserWarning(ModuleName, "OnInit", "Update not applied yet; registrar logs distinguish retained pending work from terminal rejection.")
  EndIf
EndEvent
