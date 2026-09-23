ScriptName Venworks:CanvasExamples:ExampleRegistrar Extends Venworks:Canvas:Base:BaseQuest
Import Venworks:Canvas:Registry

Venworks:Canvas:Registry Property Registry Auto Const Mandatory
String Property ConsumerId Auto Const Mandatory
String Property DisplayName Auto Const Mandatory
String Property NormalMoviePath Auto Const Mandatory
String Property LargeMoviePath Auto Const Mandatory
Int Property DescriptorVersion Auto Const Mandatory
Bool Property ExpectedRegistration Auto Const Mandatory
; Retained for ESM and saved-script compatibility; startup no longer waits on this value.
Float Property InitialDelaySeconds Auto Const Mandatory
FormList Property BuffEffects Auto Const Mandatory
FormList Property DebuffEffects Auto Const Mandatory
String[] Property BuffLabels Auto Const Mandatory
String[] Property DebuffLabels Auto Const Mandatory

String ModuleName = "CanvasExamples:ExampleRegistrar"
; Retained for saved-script compatibility only; this flag is never consulted as a lock or scheduling gate.
Bool RegistrationAttemptActive = False
Guard AttemptGuard ProtectsFunctionLogic
Guard EffectSnapshotGuard ProtectsFunctionLogic
String ActiveDisplayName
String ActiveNormalMovieUrl
String ActiveLargeMovieUrl
Int ActiveDescriptorVersion = 0
Bool PendingUpdate = False
String PendingDisplayName
String PendingNormalMovieUrl
String PendingLargeMovieUrl
Int PendingDescriptorVersion = 0
Bool LocationEventRegistered = False
Bool PlayerLoadEventRegistered = False
Bool MagicEffectEventRegistered = False
Bool EffectRefreshPending = False
Bool EffectForceRefresh = False
Bool EffectChangedDuringPublication = False
Bool EffectSnapshotBuilding = False
Int EffectSourceRevision = 0
; Retained as inert saved-script fields from the multipart effect protocol.
Int EffectSnapshotSequence = 0
Int EffectPacketIndex = 0
Int EffectRetryCount = 0
Int LastActiveEffectCount = 0
Float LastEffectSnapshotAt = 0.0
Float LastHudOpenAt = 0.0
String LastEffectSignature = ""
String PendingEffectSignature = ""
String[] EffectPackets
String PendingEffectPayload = ""
String[] ObservedEffectEntries
MagicEffect[] ActiveSourceEffects
String[] ActiveSourceEffectEntries
ENV_AfflictionScript[] ActiveSourceAfflictions
String[] ActiveSourceAfflictionEntries
Spell[] ActiveSourceSpells
String[] ActiveSourceSpellEntries
String[] PendingEffectRemovals

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
  String result = SubmitConsoleDescriptorUpdate("VWCANVAS Subscriptions Probe", "VenworksCanvas/Consumers/venworks.canvas.example.subscriptions-probe/normal.swf", "VenworksCanvas/Consumers/venworks.canvas.example.subscriptions-probe/large.swf", 2)
  LogUserInformational(ModuleName, "SelectConsoleSubscriptionsProbe", "EFFECT_PROBE_REFRESH_REQUESTED")
  RequestEffectRefresh(True)
  Return result
EndFunction

; Restores the authored Example descriptor after a diagnostic run.
String Function RestoreConsoleExample()
  String result = SubmitConsoleDescriptorUpdate(DisplayName, NormalMoviePath, LargeMoviePath, DescriptorVersion)
  LogUserInformational(ModuleName, "RestoreConsoleExample", "EFFECT_RESTORE_REFRESH_REQUESTED")
  RequestEffectRefresh(True)
  Return result
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

; Bootstrap menu and player notifications and schedule the first bounded effect scan.
Event OnInit()
  LogUserInformational(ModuleName, "OnInit", "EVENT_TRIGGERED | Registering HUD menus and effect events.")
  RegisterForMenuOpenCloseEvent("HUDMenu")
  RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")
  EnsurePlayerEventRegistrations()
  EnsureMagicEffectRegistrations(True)
  StartTimer(0.1, 1)
  RequestEffectRefresh(True)
EndEvent

; HUD opening schedules a bounded sequence; there is no saved active latch or wait in this event.
Event OnMenuOpenCloseEvent(String menuName, Bool opening)
  LogUserInformational(ModuleName, "OnMenuOpenCloseEvent", "EVENT_TRIGGERED | Menu=" + menuName + " | Opening=" + opening)
  If (opening)
    LastHudOpenAt = Utility.GetCurrentRealTime()
    EnsurePlayerEventRegistrations()
    EnsureMagicEffectRegistrations(True)
    StartTimer(0.1, 1)
    RequestEffectRefresh(True)
    ScheduleActiveEffectCheck()
  EndIf
EndEvent

; Saved registrations from pre-effect Example versions can still dispatch this event; location is no longer published.
Event Actor.OnLocationChange(Actor akSender, Location akOldLoc, Location akNewLoc)
EndEvent

; A saved game can load with effects already active; HUD opening provides a second path when this event is skipped.
Event Actor.OnPlayerLoadGame(Actor akSender)
  LogUserInformational(ModuleName, "Actor.OnPlayerLoadGame", "EVENT_TRIGGERED | Sender=" + akSender)
  EffectSourceRevision += 1
  EffectPackets = None
  EffectPacketIndex = 0
  PendingEffectPayload = ""
  EffectSnapshotBuilding = False
  EffectChangedDuringPublication = False
  ObservedEffectEntries = None
  ActiveSourceEffects = None
  ActiveSourceEffectEntries = None
  ActiveSourceAfflictions = None
  ActiveSourceAfflictionEntries = None
  ActiveSourceSpells = None
  ActiveSourceSpellEntries = None
  PendingEffectRemovals = None
  CancelTimer(31)
  EffectRefreshPending = False
  MagicEffectEventRegistered = False
  EnsureMagicEffectRegistrations(True)
  RequestEffectRefresh(True)
  ScheduleActiveEffectCheck()
EndEvent

; Saved quests enter this path through their existing menu registration after a script update.
Function EnsurePlayerEventRegistrations()
  Actor player = Game.GetPlayer()
  If (player == None)
    LogUserWarning(ModuleName, "EnsurePlayerEventRegistrations", "PLAYER_EVENT_REGISTRATION_DEFERRED | Player=None | Event=OnPlayerLoadGame")
    Return
  EndIf
  If (LocationEventRegistered)
    UnregisterForRemoteEvent(player, "OnLocationChange")
    LocationEventRegistered = False
    LogUserInformational(ModuleName, "EnsurePlayerEventRegistrations", "REMOTE_EVENT_UNREGISTERED | Event=OnLocationChange | Player=" + player)
  EndIf
  If (!PlayerLoadEventRegistered)
    Bool playerLoadRegistrationAccepted = RegisterForRemoteEvent(player, "OnPlayerLoadGame")
    PlayerLoadEventRegistered = playerLoadRegistrationAccepted
    If (playerLoadRegistrationAccepted)
      LogUserInformational(ModuleName, "EnsurePlayerEventRegistrations", "REMOTE_EVENT_REGISTRATION_RESULT | Event=OnPlayerLoadGame | Accepted=true | Player=" + player)
    Else
      LogUserWarning(ModuleName, "EnsurePlayerEventRegistrations", "REMOTE_EVENT_REGISTRATION_RESULT | Event=OnPlayerLoadGame | Accepted=false | Player=" + player)
    EndIf
  Else
    LogUserInformational(ModuleName, "EnsurePlayerEventRegistrations", "REMOTE_EVENT_ALREADY_FLAGGED | Event=OnPlayerLoadGame | Player=" + player)
  EndIf
EndFunction

; Registration, effect refresh, reconciliation, and packet publication use disjoint timer IDs.
Event OnTimer(Int aiTimerID)
  If (aiTimerID >= 1 && aiTimerID <= 20)
    ProcessAttempt(aiTimerID)
  ElseIf (aiTimerID == 31 && EffectRefreshPending)
    EffectRefreshPending = False
    PrepareEffectSnapshot()
  ElseIf (aiTimerID == 32)
    CheckActiveEffectSources()
    ScheduleActiveEffectCheck()
  ElseIf (aiTimerID == 33)
    PublishNextEffectPacket()
  ElseIf (aiTimerID == 34)
    RequestEffectRefresh(True)
  EndIf
EndEvent

; Re-register after each one-shot apply notification, then scan after the effect can become active.
Event OnMagicEffectApply(ObjectReference akTarget, ObjectReference akCaster, MagicEffect akEffect)
  Bool reportApply = akTarget == Game.GetPlayer() && !EffectRefreshPending
  If (reportApply)
    LogUserInformational(ModuleName, "OnMagicEffectApply", "EVENT_TRIGGERED | Target=" + akTarget + " | Effect=" + akEffect)
  EndIf
  MagicEffectEventRegistered = False
  EnsureMagicEffectRegistrations(reportApply)
  If (akTarget == Game.GetPlayer())
    RequestEffectRefresh(False)
  EndIf
EndEvent

; This one-shot registration is unfiltered so newly applied, cataloged effects cannot be missed.
Function EnsureMagicEffectRegistrations(Bool reportRegistration)
  If (MagicEffectEventRegistered)
    Return
  EndIf
  Actor player = Game.GetPlayer()
  If (player == None)
    LogUserWarning(ModuleName, "EnsureMagicEffectRegistrations", "EFFECT_EVENT_REGISTRATION_DEFERRED | Player unavailable.")
    Return
  EndIf
  UnregisterForAllMagicEffectApplyEvents(player)
  RegisterForMagicEffectApplyEvent(player)
  MagicEffectEventRegistered = True
  If (reportRegistration)
    LogUserInformational(ModuleName, "EnsureMagicEffectRegistrations", "EFFECT_EVENT_REGISTRATION | Target=Player | Filter=None")
  EndIf
EndFunction

; Coalesces load, HUD-ready, and apply requests while preserving a requested full resend.
Function RequestEffectRefresh(Bool forceSnapshot)
  If (forceSnapshot)
    EffectForceRefresh = True
  EndIf
  If (EffectRefreshPending)
    Return
  EndIf
  EffectRefreshPending = True
  StartTimer(0.5, 31)
EndFunction

; No removal deadline is available from the quest's base-effect event. Check only known-active sources.
Function ScheduleActiveEffectCheck()
  CancelTimer(32)
  If (ObservedEffectEntries != None && ObservedEffectEntries.Length > 0)
    StartTimer(1.0, 32)
  EndIf
EndFunction

; An expiry or cure has no quest-level finish event. Never send a removal from a guessed timer alone.
Function CheckActiveEffectSources()
  Int sourceRevision = EffectSourceRevision
  String[] observedEntries = ObservedEffectEntries
  If (observedEntries == None || observedEntries.Length == 0 || EffectSnapshotBuilding)
    Return
  EndIf
  Actor player = Game.GetPlayer()
  If (player == None)
    Return
  EndIf
  String[] stillActive = new String[0]
  Int index = 0
  While (ActiveSourceEffects != None && index < ActiveSourceEffects.Length)
    If (ActiveSourceEffects[index] != None && player.HasMagicEffect(ActiveSourceEffects[index]) && !ContainsEffectEntry(stillActive, ActiveSourceEffectEntries[index]))
      stillActive.Add(ActiveSourceEffectEntries[index])
    EndIf
    index += 1
  EndWhile
  index = 0
  While (ActiveSourceAfflictions != None && index < ActiveSourceAfflictions.Length)
    If (HasAfflictionSpell(player, ActiveSourceAfflictions[index]) && !ContainsEffectEntry(stillActive, ActiveSourceAfflictionEntries[index]))
      stillActive.Add(ActiveSourceAfflictionEntries[index])
    EndIf
    index += 1
  EndWhile
  index = 0
  While (ActiveSourceSpells != None && index < ActiveSourceSpells.Length)
    Bool namedStatusActive = ActiveSourceSpells[index] != None && player.HasSpell(ActiveSourceSpells[index])
    If (namedStatusActive && ActiveSourceSpells[index] == Game.GetFormFromFile(0x08CB51, "Starfield.esm"))
      MagicEffect corrosiveSoak = Game.GetFormFromFile(0x08CB47, "Starfield.esm") as MagicEffect
      namedStatusActive = corrosiveSoak != None && player.HasMagicEffect(corrosiveSoak)
    EndIf
    If (namedStatusActive && !ContainsEffectEntry(stillActive, ActiveSourceSpellEntries[index]))
      stillActive.Add(ActiveSourceSpellEntries[index])
    EndIf
    index += 1
  EndWhile
  String[] remaining = new String[0]
  String[] removedEntries = new String[0]
  index = 0
  While (index < observedEntries.Length)
    String entry = observedEntries[index]
    If (ContainsEffectEntry(stillActive, entry))
      remaining.Add(entry)
    Else
      removedEntries.Add(entry)
    EndIf
    index += 1
  EndWhile
  Bool removed = False
  TryLockGuard EffectSnapshotGuard
    If (!EffectSnapshotBuilding && EffectSourceRevision == sourceRevision && removedEntries.Length > 0)
      ObservedEffectEntries = remaining
      EffectSourceRevision += 1
      removed = True
    EndIf
  EndTryLockGuard
  If (removed)
    RequestEffectRefresh(False)
    LogUserInformational(ModuleName, "CheckActiveEffectSources", "EFFECT_REMOVAL_DETECTED | Remaining=" + remaining.Length)
  EndIf
EndFunction

; Builds one complete state payload; every submitted datagram is independently valid.
Function PrepareEffectSnapshot()
  If (Registry == None || BuffEffects == None || DebuffEffects == None)
    LogUserWarning(ModuleName, "PrepareEffectSnapshot", "EFFECT_SNAPSHOT_DEFERRED | Registry or catalog unavailable.")
    Return
  EndIf
  Actor player = Game.GetPlayer()
  If (player == None)
    LogUserWarning(ModuleName, "PrepareEffectSnapshot", "EFFECT_SNAPSHOT_DEFERRED | Player unavailable.")
    Return
  EndIf
  Bool snapshotClaimed = False
  Bool snapshotGuardAcquired = False
  TryLockGuard EffectSnapshotGuard
    snapshotGuardAcquired = True
    If (EffectSnapshotBuilding || PendingEffectPayload != "")
      EffectChangedDuringPublication = True
    Else
      EffectSnapshotBuilding = True
      EffectSourceRevision += 1
      snapshotClaimed = True
    EndIf
  EndTryLockGuard
  If (!snapshotClaimed)
    If (!snapshotGuardAcquired)
      RequestEffectRefresh(False)
    EndIf
    Return
  EndIf
  String[] previousEntries = ObservedEffectEntries
  ActiveSourceEffects = new MagicEffect[0]
  ActiveSourceEffectEntries = new String[0]
  ActiveSourceAfflictions = new ENV_AfflictionScript[0]
  ActiveSourceAfflictionEntries = new String[0]
  ActiveSourceSpells = new Spell[0]
  ActiveSourceSpellEntries = new String[0]
  String[] entries = new String[0]
  entries = AppendActiveEffects(entries, player, BuffEffects, BuffLabels, "B")
  Int buffCount = entries.Length
  entries = AppendActiveEffects(entries, player, DebuffEffects, DebuffLabels, "D")
  entries = AppendActiveAfflictions(entries, player)
  entries = AppendActiveEnvironmentalStatuses(entries, player)
  Int debuffCount = entries.Length - buffCount
  LastActiveEffectCount = entries.Length
  If (previousEntries != None)
    Int previousIndex = 0
    While (previousIndex < previousEntries.Length)
      If (!ContainsEffectEntry(entries, previousEntries[previousIndex]))
        EffectForceRefresh = True
      EndIf
      previousIndex += 1
    EndWhile
  EndIf
  ObservedEffectEntries = entries
  ScheduleActiveEffectCheck()
  String signature = ""
  Int index = 0
  While (index < entries.Length)
    signature += entries[index] + ";"
    index += 1
  EndWhile
  Bool entriesChanged = signature != LastEffectSignature
  Float now = Utility.GetCurrentRealTime()
  If (!EffectForceRefresh && !entriesChanged && now >= LastEffectSnapshotAt && now - LastEffectSnapshotAt < 60.0)
    EffectSnapshotBuilding = False
    If (EffectChangedDuringPublication)
      EffectChangedDuringPublication = False
      RequestEffectRefresh(False)
    EndIf
    Return
  EndIf
  EffectForceRefresh = False
  String payload = buffCount + "|" + debuffCount + "|" + signature
  String datagram = Registry.BuildCanvasDatagramBody("effects.state", 1, "ci-ascii", payload)
  String framedPacket = Registry.BuildCanvasEventPacket("venworks.canvas.example.status", datagram)
  Int framedLength = Registry.GetCharacterCount(framedPacket)
  If (datagram == "" || framedLength > 4096)
    EffectSnapshotBuilding = False
    EffectForceRefresh = True
    LogUserWarning(ModuleName, "PrepareEffectSnapshot", "EFFECT_DATAGRAM_REJECTED | Buffs=" + buffCount + " | Debuffs=" + debuffCount + " | Length=" + framedLength + " | Limit=4096")
    Return
  EndIf
  If (PendingEffectPayload != "")
    EffectChangedDuringPublication = True
    EffectSnapshotBuilding = False
    Return
  EndIf
  ; Publish the payload last, after every field used by the send timer is ready.
  PendingEffectSignature = signature
  EffectRetryCount = 0
  PendingEffectPayload = payload
  EffectSnapshotBuilding = False
  LogUserInformational(ModuleName, "PrepareEffectSnapshot", "EFFECT_DATAGRAM_QUEUED | Type=effects.state | Schema=1 | Buffs=" + buffCount + " | Debuffs=" + debuffCount + " | Length=" + framedLength)
  StartTimer(0.1, 33)
EndFunction

; SQ_ENV owns injuries and infections separately from the magic-effect catalog. Its spells
; are the status-menu source of truth even when a console-applied spell did not set Active.
String[] Function AppendActiveAfflictions(String[] entries, Actor player)
  SQ_ENV_AfflictionsScript afflictionQuest = Game.GetFormFromFile(0x00248D20, "Starfield.esm") as SQ_ENV_AfflictionsScript
  If (afflictionQuest == None || afflictionQuest.AfflictionData == None)
    Return entries
  EndIf
  ENV_AfflictionScript[] afflictions = afflictionQuest.AfflictionData
  Int index = 0
  While (index < afflictions.Length)
    ENV_AfflictionScript affliction = afflictions[index]
    If (HasAfflictionSpell(player, affliction))
      String label = ResolveAfflictionLabel(affliction.ID)
      String entry = "D:#" + affliction.GetFormID() + ":" + label
      entries.Add(entry)
      ActiveSourceAfflictions.Add(affliction)
      ActiveSourceAfflictionEntries.Add(entry)
    EndIf
    index += 1
  EndWhile
  Return entries
EndFunction

Bool Function HasAfflictionSpell(Actor player, ENV_AfflictionScript affliction)
  If (player == None || affliction == None || affliction.AfflictionSpellList == None)
    Return False
  EndIf
  FormList spellList = affliction.AfflictionSpellList
  Int index = 0
  While (index < spellList.GetSize())
    Spell rankSpell = spellList.GetAt(index) as Spell
    If (rankSpell != None && player.HasSpell(rankSpell))
      Return True
    EndIf
    index += 1
  EndWhile
  Return False
EndFunction

; Only named source spells are used; shared airborne-hazard effects cannot identify toxic gas.
String[] Function AppendActiveEnvironmentalStatuses(String[] entries, Actor player)
  Spell corrosiveEnvironment = Game.GetFormFromFile(0x08CB51, "Starfield.esm") as Spell
  MagicEffect corrosiveSoak = Game.GetFormFromFile(0x08CB47, "Starfield.esm") as MagicEffect
  Spell corrosiveRain = Game.GetFormFromFile(0x281ECB, "Starfield.esm") as Spell
  Spell toxicGas = Game.GetFormFromFile(0x245B6B, "Starfield.esm") as Spell
  If (corrosiveEnvironment != None && corrosiveSoak != None && player.HasSpell(corrosiveEnvironment) && player.HasMagicEffect(corrosiveSoak))
    String entry = "D:#" + corrosiveEnvironment.GetFormID() + ":Corrosive Environment"
    entries.Add(entry)
    ActiveSourceSpells.Add(corrosiveEnvironment)
    ActiveSourceSpellEntries.Add(entry)
  EndIf
  If (corrosiveRain != None && player.HasSpell(corrosiveRain))
    String entry = "D:#" + corrosiveRain.GetFormID() + ":Corrosive Rain"
    entries.Add(entry)
    ActiveSourceSpells.Add(corrosiveRain)
    ActiveSourceSpellEntries.Add(entry)
  EndIf
  If (toxicGas != None && player.HasSpell(toxicGas))
    String entry = "D:#" + toxicGas.GetFormID() + ":Toxic Gas Hazard"
    entries.Add(entry)
    ActiveSourceSpells.Add(toxicGas)
    ActiveSourceSpellEntries.Add(entry)
  EndIf
  Return entries
EndFunction

; The activator has no Papyrus display-name getter, so keep vanilla IDs and labels paired here.
String Function ResolveAfflictionLabel(String afflictionId)
  If (afflictionId == "BoneInfection")
    Return "Bone Infection"
  ElseIf (afflictionId == "BrainInfection")
    Return "Brain Infection"
  ElseIf (afflictionId == "IntestinalInfection")
    Return "Intestinal Infection"
  ElseIf (afflictionId == "LungInfection")
    Return "Lung Infection"
  ElseIf (afflictionId == "TissueInfection")
    Return "Tissue Infection"
  ElseIf (afflictionId == "BrainInjury")
    Return "Brain Injury"
  ElseIf (afflictionId == "Burns")
    Return "Burns"
  ElseIf (afflictionId == "Concussion")
    Return "Concussion"
  ElseIf (afflictionId == "Contusions")
    Return "Contusions"
  ElseIf (afflictionId == "DislocatedLimb")
    Return "Dislocated Limb"
  ElseIf (afflictionId == "FracturedLimb")
    Return "Fractured Limb"
  ElseIf (afflictionId == "FracturedSkull")
    Return "Fractured Skull"
  ElseIf (afflictionId == "Frostbite")
    Return "Frostbite"
  ElseIf (afflictionId == "Heatstroke")
    Return "Heatstroke"
  ElseIf (afflictionId == "Hernia")
    Return "Hernia"
  ElseIf (afflictionId == "Hypothermia")
    Return "Hypothermia"
  ElseIf (afflictionId == "Lacerations")
    Return "Lacerations"
  ElseIf (afflictionId == "LungDamage")
    Return "Lung Damage"
  ElseIf (afflictionId == "Poisoning")
    Return "Poisoning"
  ElseIf (afflictionId == "PunctureWounds")
    Return "Puncture Wounds"
  ElseIf (afflictionId == "RadiationPoisoning")
    Return "Radiation Poisoning"
  ElseIf (afflictionId == "Sprain")
    Return "Sprain"
  ElseIf (afflictionId == "TornMuscle")
    Return "Torn Muscle"
  EndIf
  Return afflictionId
EndFunction

; Only cataloged statuses are published. Multiple active sustenance modifiers describe one player-facing condition.
String[] Function AppendActiveEffects(String[] entries, Actor player, FormList catalog, String[] labels, String category)
  Int index = 0
  Int catalogSize = catalog.GetSize()
  While (index < catalogSize)
    MagicEffect effect = catalog.GetAt(index) as MagicEffect
    If (effect != None && player.HasMagicEffect(effect))
      String label = ""
      Bool grouped = False
      If (IsSustenanceFoodEffect(effect))
        label = "Malnourished"
        grouped = True
      ElseIf (IsSustenanceDrinkEffect(effect))
        label = "Dehydrated"
        grouped = True
      ElseIf (IsSustenanceHydratedEffect(effect))
        label = "Hydrated"
        grouped = True
      ElseIf (IsSustenanceFedEffect(effect))
        label = "Fed"
        grouped = True
      ElseIf (labels != None && labels.Length == catalogSize && index < labels.Length && labels[index] != "")
        label = labels[index]
      Else
        ; Existing saves can retain the old broad VMAD label arrays after the FormLists are updated.
        label = ResolveKnownBuffLabel(effect)
      EndIf
      If (label == "")
        label = "EFFECT " + effect.GetFormID()
      EndIf
      String entry = category + ":#" + effect.GetFormID() + ":" + label
      If (grouped)
        entry = category + ":" + label
      EndIf
      ; Starfield can retain a negative sustenance modifier while its positive
      ; player-facing state is active. Buffs are assembled first, so keep one
      ; visible state per food or drink family.
      Bool suppressed = IsSuppressedSustenanceEntry(entries, entry)
      If ((!grouped || !ContainsEffectEntry(entries, entry)) && !suppressed)
        entries.Add(entry)
      EndIf
      ActiveSourceEffects.Add(effect)
      ActiveSourceEffectEntries.Add(entry)
    EndIf
    index += 1
  EndWhile
  Return entries
EndFunction

String Function ResolveKnownBuffLabel(MagicEffect effect)
  If (effect == Game.GetFormFromFile(0x05C527, "Starfield.esm"))
    Return "Well Rested"
  ElseIf (effect == Game.GetFormFromFile(0x0738B0, "Starfield.esm"))
    Return "Companion Affinity Increases Faster"
  ElseIf (effect == Game.GetFormFromFile(0x0738B1, "Starfield.esm"))
    Return "Improved Research Crit Chance"
  ElseIf (effect == Game.GetFormFromFile(0x0738B3, "Starfield.esm"))
    Return "Reduced Research Cost"
  ElseIf (effect == Game.GetFormFromFile(0x2D88C4, "Starfield.esm"))
    Return "Fortify Persuasion"
  ElseIf (effect == Game.GetFormFromFile(0x0B92EB, "Starfield.esm"))
    Return "Heart+"
  EndIf
  Return ""
EndFunction

Bool Function ContainsEffectEntry(String[] entries, String candidate)
  Int index = 0
  While (index < entries.Length)
    If (entries[index] == candidate)
      Return True
    EndIf
    index += 1
  EndWhile
  Return False
EndFunction

Bool Function IsSuppressedSustenanceEntry(String[] entries, String candidate)
  If (candidate == "D:Dehydrated")
    Return ContainsEffectEntry(entries, "B:Hydrated")
  ElseIf (candidate == "D:Malnourished")
    Return ContainsEffectEntry(entries, "B:Fed")
  EndIf
  Return False
EndFunction

Bool Function IsSustenanceFoodEffect(MagicEffect effect)
  Return effect == Game.GetFormFromFile(0x31326D, "Starfield.esm") || effect == Game.GetFormFromFile(0x31326E, "Starfield.esm") || effect == Game.GetFormFromFile(0x31326F, "Starfield.esm")
EndFunction

Bool Function IsSustenanceDrinkEffect(MagicEffect effect)
  Return effect == Game.GetFormFromFile(0x31327B, "Starfield.esm") || effect == Game.GetFormFromFile(0x31329B, "Starfield.esm") || effect == Game.GetFormFromFile(0x2EDFDA, "Starfield.esm")
EndFunction

Bool Function IsSustenanceHydratedEffect(MagicEffect effect)
  Return effect == Game.GetFormFromFile(0x313260, "Starfield.esm") || effect == Game.GetFormFromFile(0x2EDFDC, "Starfield.esm") || effect == Game.GetFormFromFile(0x2EFD74, "Starfield.esm")
EndFunction

Bool Function IsSustenanceFedEffect(MagicEffect effect)
  Return effect == Game.GetFormFromFile(0x2EDFE1, "Starfield.esm") || effect == Game.GetFormFromFile(0x2EDFD5, "Starfield.esm") || effect == Game.GetFormFromFile(0x313251, "Starfield.esm")
EndFunction

; Publishes one complete state datagram. EVENT_SUBMITTED acknowledges native submission only.
Function PublishNextEffectPacket()
  If (Registry == None)
    Return
  EndIf
  If (PendingEffectPayload == "")
    Return
  EndIf
  String payload = PendingEffectPayload
  String signature = PendingEffectSignature
  OperationResult result = Registry.TryPublishCanvasDatagram("venworks.canvas.example.status", "effects.state", 1, "ci-ascii", payload)
  Float elapsed = -1.0
  Float now = Utility.GetCurrentRealTime()
  If (LastHudOpenAt > 0.0 && now >= LastHudOpenAt)
    elapsed = now - LastHudOpenAt
  EndIf
  LogUserInformational(ModuleName, "PublishNextEffectPacket", "EFFECT_DATAGRAM_ATTEMPT | Type=effects.state | Schema=1 | Length=" + Registry.GetCharacterCount(result.Packet) + " | Status=" + result.Status + " | SinceHudOpen=" + elapsed)
  If (PendingEffectPayload != payload || PendingEffectSignature != signature)
    Return
  EndIf
  If (result.Status == "EVENT_SUBMITTED")
    EffectRetryCount = 0
    LastEffectSignature = signature
    LastEffectSnapshotAt = Utility.GetCurrentRealTime()
    PendingEffectPayload = ""
    If (EffectChangedDuringPublication)
      EffectChangedDuringPublication = False
      RequestEffectRefresh(False)
    EndIf
  ElseIf (result.Status == "REJECTED_EVENT_INACTIVE")
    LogUserInformational(ModuleName, "PublishNextEffectPacket", "EFFECT_DATAGRAM_WAITING_FOR_HUD")
    EffectRetryCount += 1
    If (EffectRetryCount <= 20)
      StartTimer(0.5, 33)
    Else
      LogUserWarning(ModuleName, "PublishNextEffectPacket", "EFFECT_DATAGRAM_RETRY_EXHAUSTED | Status=" + result.Status)
      PendingEffectPayload = ""
      EffectForceRefresh = True
    EndIf
  ElseIf (IsDeferred(result.Status) || result.Status == "EVENT_CANCELLED_ACTIVATION")
    EffectRetryCount += 1
    If (EffectRetryCount <= 20)
      StartTimer(0.5, 33)
    Else
      LogUserWarning(ModuleName, "PublishNextEffectPacket", "EFFECT_DATAGRAM_RETRY_EXHAUSTED | Status=" + result.Status)
      PendingEffectPayload = ""
      EffectForceRefresh = True
    EndIf
  Else
    LogUserWarning(ModuleName, "PublishNextEffectPacket", "EFFECT_DATAGRAM_REJECTED | Status=" + result.Status + " | Detail=" + result.Detail)
    PendingEffectPayload = ""
    EffectForceRefresh = True
  EndIf
EndFunction

; Compatibility entry point. A positive result acknowledges only the expected Papyrus result, never UI readiness.
Bool Function RegisterWithRetry()
  Return ProcessAttempt(1)
EndFunction

; One attempt followed by diagnostics and optional scheduling, all outside the acquired guards.
Bool Function ProcessAttempt(Int attempt)
  OperationResult result = TryReconcile()
  If (result.Status == "REGISTRATION_UNCHANGED" && !result.UpdateApplied)
    result.UiLoad = "UI_LOAD_ACTIVATION_REPLAY"
  EndIf
  RequestRegisteredUi(result)
  ReportAttempt(result)
  Bool retryUi = IsDeferred(result.UiLoad) && result.UiLoad != "DEFERRED_UI_INACTIVE"
  If (IsDeferred(result.Status) || retryUi)
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
