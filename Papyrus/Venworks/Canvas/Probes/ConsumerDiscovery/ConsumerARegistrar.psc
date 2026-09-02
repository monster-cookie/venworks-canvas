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

; Registers for both HUD menus and attempts the active descriptor, initially seeded from VMAD, after its configured delay.
Event OnInit()
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  If (InitialDelaySeconds > 0.0)
    Utility.Wait(InitialDelaySeconds)
  EndIf
  RegisterWithRetry()
EndEvent

; Re-publishes the persistent active descriptor when either supported HUD menu opens.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  If (opening)
    If (InitialDelaySeconds > 0.0)
      Utility.WaitMenuPause(InitialDelaySeconds)
    EndIf
    RegisterWithRetry()
  EndIf
EndEvent

; Attempts the persistent active descriptor with bounded retries and returns whether the expected result was observed.
Bool Function RegisterWithRetry()
  EnsureActiveDescriptor()
  Return RegisterDescriptorWithRetry(ActiveDisplayName, ActiveNormalMovieUrl, ActiveLargeMovieUrl, ActiveDescriptorVersion, ExpectedRegistration)
EndFunction

; Applies an explicit in-save descriptor update through this existing owner quest rather than persisted VMAD defaults.
; Returns whether the registry accepted and published the updated descriptor during the bounded retry window.
Bool Function ApplyDescriptorUpdate(String updatedDisplayName, String updatedNormalMovieUrl, String updatedLargeMovieUrl, Int updatedDescriptorVersion)
  EnsureActiveDescriptor()
  String previousDisplayName = ActiveDisplayName
  String previousNormalMovieUrl = ActiveNormalMovieUrl
  String previousLargeMovieUrl = ActiveLargeMovieUrl
  Int previousDescriptorVersion = ActiveDescriptorVersion

  ActiveDisplayName = updatedDisplayName
  ActiveNormalMovieUrl = updatedNormalMovieUrl
  ActiveLargeMovieUrl = updatedLargeMovieUrl
  ActiveDescriptorVersion = updatedDescriptorVersion
  Bool applied = RegisterDescriptorWithRetry(ActiveDisplayName, ActiveNormalMovieUrl, ActiveLargeMovieUrl, ActiveDescriptorVersion, True)
  If (!applied)
    ActiveDisplayName = previousDisplayName
    ActiveNormalMovieUrl = previousNormalMovieUrl
    ActiveLargeMovieUrl = previousLargeMovieUrl
    ActiveDescriptorVersion = previousDescriptorVersion
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

; Calls the registry as this stable owner until the expected outcome is observed or the bounded retry window is exhausted.
Bool Function RegisterDescriptorWithRetry(String requestedDisplayName, String requestedNormalMovieUrl, String requestedLargeMovieUrl, Int requestedDescriptorVersion, Bool expectedResult)
  Int attempt = 0
  While (attempt < 20)
    If (Registry != None)
      Bool actualRegistration = Registry.RegisterConsumer(Self, ConsumerId, requestedDisplayName, requestedNormalMovieUrl, requestedLargeMovieUrl, requestedDescriptorVersion)
      If (actualRegistration == expectedResult)
        LogUserInformational(ModuleName, "RegisterDescriptorWithRetry", "Observed the expected registration result for '" + ConsumerId + "'.")
        Return True
      EndIf
      If (actualRegistration && !expectedResult)
        Registry.UnregisterConsumer(Self, ConsumerId)
      EndIf
    EndIf
    attempt += 1
    Utility.WaitMenuPause(0.5)
  EndWhile

  LogUserWarning(ModuleName, "RegisterDescriptorWithRetry", "Exhausted the bounded registration retry for '" + ConsumerId + "'.")
  Return False
EndFunction
