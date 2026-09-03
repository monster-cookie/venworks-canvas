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

; Registers for both HUD menus and attempts the active descriptor, initially seeded from VMAD, after its configured delay.
Event OnInit()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  If (InitialDelaySeconds > 0.0)
    Utility.Wait(InitialDelaySeconds)
  EndIf
  RegisterWithRetry()
EndEvent

; Reconciles the persistent descriptor when either HUD opens. Overlapping attempts are skipped and no bridge publication occurs.
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
  If (RegistrationAttemptActive)
    Return False
  EndIf
  RegistrationAttemptActive = True
  EnsureActiveDescriptor()
  Bool result = AttemptDescriptorRegistration(ActiveDisplayName, ActiveNormalMovieUrl, ActiveLargeMovieUrl, ActiveDescriptorVersion, ExpectedRegistration)
  RegistrationAttemptActive = False
  Return result
EndFunction

; Applies an explicit in-save descriptor update through this existing owner quest rather than persisted VMAD defaults.
; Returns whether the registry accepted the update; disabled UI transport does not roll back a successful registration.
Bool Function ApplyDescriptorUpdate(String updatedDisplayName, String updatedNormalMovieUrl, String updatedLargeMovieUrl, Int updatedDescriptorVersion)
  If (RegistrationAttemptActive)
    Return False
  EndIf
  RegistrationAttemptActive = True
  EnsureActiveDescriptor()
  String previousDisplayName = ActiveDisplayName
  String previousNormalMovieUrl = ActiveNormalMovieUrl
  String previousLargeMovieUrl = ActiveLargeMovieUrl
  Int previousDescriptorVersion = ActiveDescriptorVersion

  ActiveDisplayName = updatedDisplayName
  ActiveNormalMovieUrl = updatedNormalMovieUrl
  ActiveLargeMovieUrl = updatedLargeMovieUrl
  ActiveDescriptorVersion = updatedDescriptorVersion
  Bool applied = AttemptDescriptorRegistration(ActiveDisplayName, ActiveNormalMovieUrl, ActiveLargeMovieUrl, ActiveDescriptorVersion, True)
  If (!applied)
    ActiveDisplayName = previousDisplayName
    ActiveNormalMovieUrl = previousNormalMovieUrl
    ActiveLargeMovieUrl = previousLargeMovieUrl
    ActiveDescriptorVersion = previousDescriptorVersion
  EndIf
  RegistrationAttemptActive = False
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
  If (RegistrationAttemptActive)
    Return False
  EndIf
  RegistrationAttemptActive = True
  Bool result = AttemptDescriptorRegistration(requestedDisplayName, requestedNormalMovieUrl, requestedLargeMovieUrl, requestedDescriptorVersion, expectedResult)
  RegistrationAttemptActive = False
  Return result
EndFunction

; Waits only for a missing registry reference, then treats its first answer as terminal. Caller owns RegistrationAttemptActive.
; A successful positive case checks RequestUiLoad; an expected rejection never requests a UI load. Disabled transport is not failure.
Bool Function AttemptDescriptorRegistration(String requestedDisplayName, String requestedNormalMovieUrl, String requestedLargeMovieUrl, Int requestedDescriptorVersion, Bool expectedResult)
  Int attempt = 0
  While (attempt < 20)
    If (Registry != None)
      Bool actualRegistration = Registry.RegisterConsumer(Self, ConsumerId, requestedDisplayName, requestedNormalMovieUrl, requestedLargeMovieUrl, requestedDescriptorVersion)
      If (actualRegistration == expectedResult)
        If (actualRegistration)
          String loadResult = Registry.RequestUiLoad(Self, ConsumerId)
          LogUserInformational(ModuleName, "AttemptDescriptorRegistration", "REGISTRATION_ACK | Consumer=" + ConsumerId + " | LoadUI=" + loadResult)
        Else
          LogUserInformational(ModuleName, "AttemptDescriptorRegistration", "EXPECTED_REGISTRATION_REJECTION | No UI load requested.")
        EndIf
        Return True
      EndIf
      If (actualRegistration && !expectedResult)
        Registry.UnregisterConsumer(Self, ConsumerId)
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
