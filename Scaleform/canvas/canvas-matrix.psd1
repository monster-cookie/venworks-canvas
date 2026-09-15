@{
  Version = 1
  WatchPresentation = 'CanvasOwnedChronomarkWithNativeWatchStructurallyAbsent'
  Chronomark = @{
    Ownership = 'CanvasProceduralVectorAndText'
    Providers = @('LocalEnvironmentData', 'LocalEnvData_Frequent', 'PlayerData', 'PlayerFrequentData', 'HudCompassData', 'PersonalEffectsData', 'PersonalAlertsData', 'EnvironmentEffectsData', 'EnvironmentAlertsData', 'HUDOpacityData')
    VisibilitySource = 'HUDMenu.HudModeData.BottomLeftGroup'
    CustomAlerts = 'DataLayerOnlyNotRendered'
    Capacities = @{ GeneralAndHazardMarkers = 48; MissionMarkers = 16; EnemyMarkers = 16; PersonalEffects = 5; EnvironmentEffects = 4; AlertTransactions = 16 }
  }
  Protocol = 'VWCANVAS_REGISTRY/1'
  TestMode = 'ExplicitConsumerUiLoad'
  UiLoadResult = 'UI_LOAD_QUEUED'
  UiLoadTransport = @{ EventHeader = @{ Selector = 1; Wire = 'VWC_EVT/1|' }; PacketType = @{ Selector = 1; Wire = 'canvas.ui.load' }; Protocol = 'canvas.ui.load'; Version = 1; MaxCharacters = 512; MaxPending = 32; MinimumIntervalSeconds = 1; MaxBusyAttempts = 20; Target = 'PlayerHud' }
  ConsumerContract = @{
    LegacyProtocol = 'VWCANVAS_CONSUMER/1'
    Protocol = 'VWCANVAS_CONSUMER/2'
    HostContractVersion = 2
    MaxConsumers = 32
    MaxUiChannelsPerConsumer = 18
    MaxEventTopicsPerConsumer = 16
    UiChannels = @(
      'LocalEnvironmentData', 'LocalEnvData_Frequent', 'PlayerData', 'PlayerFrequentData', 'PlayerInventoryData', 'WeaponData',
      'HudJetpackData', 'HUDStarbornPowersData', 'FavoritesData', 'ControlMapData', 'EnvironmentEffectsData', 'PersonalEffectsData',
      'StarmapSystemBodyInfoProvider', 'HudCompassData', 'HudCrosshairData', 'HUDStealthData', 'HUDVehicleData', 'HUDOpacityData'
    )
  }
  CanvasEventTransport = @{ EventHeader = @{ Selector = 1; Wire = 'VWC_EVT/1|' }; PacketType = @{ Selector = 2; Wire = 'canvas.event' }; Version = 1; MaxTopicCharacters = 96; MaxBodyCharacters = 400; MaxCharacters = 512; MinimumIntervalSeconds = 1; Target = 'PlayerHud' }
  ParserCases = @(
    @{ Id = 'delimiter-display-name'; Expected = 'accepted' }
    @{ Id = 'maximum-valid-descriptor'; Expected = 'accepted' }
    @{ Id = 'invalid-consumer-id'; Expected = 'descriptor-rejected' }
    @{ Id = 'path-traversal'; Expected = 'descriptor-rejected' }
    @{ Id = 'duplicate-id'; Expected = 'first-valid-wins' }
    @{ Id = 'invalid-version'; Expected = 'descriptor-rejected' }
    @{ Id = 'truncated-record'; Expected = 'snapshot-rejected' }
    @{ Id = 'oversized-field'; Expected = 'snapshot-rejected' }
    @{ Id = 'invalid-plus-valid'; Expected = 'valid-consumer-retained' }
    @{ Id = 'complete-multipage'; Expected = 'generation-accepted' }
    @{ Id = 'missing-page'; Expected = 'last-complete-retained' }
    @{ Id = 'duplicate-page'; Expected = 'identical-redelivery-accepted' }
    @{ Id = 'conflicting-duplicate-page'; Expected = 'generation-rejected' }
    @{ Id = 'inconsistent-page-metadata'; Expected = 'generation-rejected' }
    @{ Id = 'superseded-generation'; Expected = 'new-complete-generation-accepted' }
  )
  RegistrationRuntimeCases = @(
    @{ Id = 'pc-console-echo'; Packages = @('Canvas'); Expected = 'Core Utilities:Console.ConsoleEcho visibly echoes the supplied label with the RM> prefix under the PC debug-logging configuration; ConsoleOutputTests.Run exercises ordered block, blank, None/empty, and rejected LF entries. CR/CRLF VM coverage remains pending. These diagnostics are not needed for UI loading.' }
    @{ Id = 'pc-console-result-output'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Each Canvas ConsoleResolve/action CGF prints exactly one final VWCANVAS-labeled status matching its Papyrus return/log path, including resolution failure. Busy remains inconclusive. Resolution and check-only commands do not use transport; Example ConsolePing explicitly makes one named-event publication attempt.' }
    @{ Id = 'pc-example-location-clock'; Packages = @('Canvas', 'Example'); Expected = 'The upper-left Example clock renders universal time, local planetary time, and the time remaining until the next sunrise or sunset from LocalEnvironmentData and LocalEnvData_Frequent. A player OnLocationChange publishes the location identity, including encoded surface latitude and longitude when present, through venworks.canvas.example.location.changed as a bounded refresh notification without using CustomAlertsData.' }
    @{ Id = 'pc-example-location-clock-reload'; Packages = @('Canvas', 'Example'); Expected = 'After HUD unload/reopen and save reload, the Example clock recreates exactly once with current provider values. The registrar registers player OnLocationChange and OnPlayerLoadGame notifications, publishes Game.GetPlayer().GetCurrentLocation() on load, and refreshes the current location after HUD opening so an early lossy event need not reach an unloaded consumer.' }
    @{ Id = 'pc-console-resolution'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'ComponentGalleryRegistrar.ConsoleResolve invoked with cgf logs VWCANVAS_CONSOLE/1 CONSOLE_BEGIN and CONSOLE_RESOLVED with its runtime form; missing form or script binding stops without forwarding work. No external load-order prefix or quest title is used.' }
    @{ Id = 'pc-console-host-recovery'; Packages = @('Canvas'); Expected = 'Registry.ConsoleResolve changes no registry state; explicit ConsoleEnsureStorage restores callbacks on an affected host-only save and logs REGISTRY_READY or a distinct inconclusive busy result without resetting valid records.' }
    @{ Id = 'pc-registration-host-only'; Packages = @('Canvas'); Expected = 'Host logs zero consumers and submits no load packets; the native Watch symbol is absent while the Canvas-owned Chronomark receives ordinary HUD providers, and gameplay remains responsive.' }
    @{ Id = 'pc-registration-example'; Packages = @('Canvas', 'Example'); Expected = 'Example logs REGISTRATION_ACK then a separate UI_LOAD_QUEUED/UI_LOAD_SUBMITTED; readiness requires the visible panel.' }
    @{ Id = 'pc-registration-two-consumers'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Example and Component Gallery each acknowledge registration and validate RequestUiLoad ownership; registry count is two.' }
    @{ Id = 'pc-component-gallery-cheatsheet-rendering'; Packages = @('Canvas', 'ComponentGallery'); Expected = 'Selecting CANVAS COMPONENT GALLERY in the Pause Menu loads index.html without linking Canvas HTML, CSS, or rendering classes into the Gallery. CanvasHost reports HTML PARSED with exactly six resources, then HTML RENDERED and READY. The visible Gallery shows grouped rows with Tag, Syntax, and Rendered Result columns; each syntax cell shows literal markup while each result cell is a separate Canvas-rendered display tree. Local PNG, local SVG, and inline SVG path examples render distinctly.' }
    @{ Id = 'pc-component-gallery-css-layout'; Packages = @('Canvas', 'ComponentGallery'); Expected = 'Canvas loads gallery.css and its local @import of gallery-theme.css, then visibly applies the supported selector cascade, imported theme color, typography, spacing, width, flex rows and columns, gaps, alignment, and clipping. The relative and absolute position example honors left/top placement and z-index so the front layer overlaps above the back layer. Rows remain aligned without overlap or cumulative position drift in both normal and large Pause Menu modes.' }
    @{ Id = 'pc-component-gallery-data-composition'; Packages = @('Canvas', 'ComponentGallery'); Expected = 'Canvas renders the Gallery include, template/use, state, repeat, meter, text binding, visibility, and data-vw-format examples from declared HTML and Gallery-owned menu-local sample data. Score: {value} resolves visibly to Score: 42, the setData row reports Menu-local sample data, repeat produces three Repeated item rows, and the meter fills to 72 percent without stale generated nodes. The Gallery dispatches the dotted venworks.canvas.example.ping sample through the Canvas bridge, activating the named pingstate and revealing its state content.' }
    @{ Id = 'pc-component-gallery-navigation'; Packages = @('Canvas', 'ComponentGallery'); Expected = 'While the Pause Menu Gallery is active, engine-routed Up/Down input, right-stick input, mouse-wheel input, scrollbar-track clicks, and scrollbar-thumb dragging scroll the Canvas-rendered document and clamp at both ends. Cancel closes the Gallery and restores the normal Pause Menu. Input does not create duplicate rows or callbacks.' }
    @{ Id = 'pc-component-gallery-reload-disposal'; Packages = @('Canvas', 'ComponentGallery'); Expected = 'Ten Gallery open/close cycles and ten Pause Menu close/open cycles each recreate exactly one complete Gallery with current menu-local sample data. Unload removes Pause Menu listeners, the locally loaded Canvas host and Gallery consumer, and the Canvas-generated display tree; late callbacks from an earlier generation do not repaint or affect the replacement session.' }
    @{ Id = 'pc-component-gallery-bounded-failure'; Packages = @('Canvas', 'ComponentGallery'); Expected = 'With one controlled invalid text resource at a time, malformed HTML or CSS, a missing local resource, rejected traversal, excessive expansion, and invalid or oversized binding data each produce one bounded sanitized diagnostic, leave no partial successful Gallery tree, do not loop or grow the display list, and recover after restoring the valid resource and reopening the Pause Menu Gallery.' }
    @{ Id = 'pc-component-gallery-package-boundary'; Packages = @('Canvas', 'ComponentGallery'); Expected = 'With Canvas installed alone, the vanilla Pause Menu has no CANVAS COMPONENT GALLERY entry. Installing ComponentGallery adds the entry through its own normal and large Pause Menu patches. Removing ComponentGallery restores the vanilla Pause Menu surface without removing or changing the Canvas framework package.' }
    @{ Id = 'pc-registration-reload'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Reload/menu openings preserve valid records; separate consumer load requests recreate the UI with bounded bridge traffic.' }
    @{ Id = 'pc-registration-rejection'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Invalid descriptors report the exact field once per attempt, terminate without polling, and never request a UI load.' }
    @{ Id = 'pc-registration-ui-ownership'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Unknown IDs and wrong owners receive REJECTED_*; check-only calls return REGISTERED_UI_LOAD_ELIGIBLE and never queue or transmit.' }
    @{ Id = 'pc-registration-uuid-case'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'D, braced D and compact UUID inputs in mixed case identify the same record; nil, malformed and whitespace inputs are rejected.' }
    @{ Id = 'pc-registration-concurrent-owners'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Simultaneous different-owner claims for the same UUID leave exactly one owner; mixed-case collision and reconciliation cannot duplicate or remove that record.' }
  )
  # Player HUD cases are the current PC gate; ship/pilot and package-removal cases remain later controlled acceptance.
  RuntimeCases = @(
    @{ Id = 'pc-archive-host-only'; Packages = @('Canvas'); Expected = 'Player HUD identifies EXPLICIT UI LOAD TEST and CANVAS CHRONOMARK READY, submits no consumer load command, contains no native Watch instance, and remains responsive. Provider subscription is not callback or delivery proof.' }
    @{ Id = 'pc-archive-example'; Packages = @('Canvas', 'Example'); Expected = 'Player HUD visibly renders the namespaced Example clock in the upper-left with universal, local, and next solar-transition rows using readable Bethesda-font glyphs; a coordinate-bearing current-location refresh after load or HUD opening can clear the pending solar row without travel.' }
    @{ Id = 'pc-archive-two-consumers'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Player HUD visibly reports both independently registered consumers READY with no static slot.' }
    @{ Id = 'pc-archive-reversed-consumer-order'; Packages = @('Canvas', 'ComponentGallery', 'Example'); Expected = 'Both consumers register regardless of consumer load order; Host remains their explicit master.' }
    @{ Id = 'pc-archive-remove-component-gallery'; Packages = @('Canvas', 'Example'); Expected = 'After saving with both consumers, removing the Component Gallery package, and loading the save, the registry prunes Component Gallery and reports only Example.' }
    @{ Id = 'pc-archive-id-reclamation'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'After the removal case, reinstalling Component Gallery allows its released ID to register and become READY again.' }
    @{ Id = 'pc-archive-save-reload'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Closing/reopening the HUD after save reload preserves registration and the consumers explicitly request their UI again; both panels reappear.' }
    @{ Id = 'pc-archive-menu-replay'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Ten repeated Player HUD close/open cycles visibly retain both consumers; any miss is recorded as a concrete one-way transport blocker.' }
    @{ Id = 'pc-archive-normal-large'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Normal and large player HUD movies load the corresponding namespaced consumer paths.' }
    @{ Id = 'pc-archive-ship-hud'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'DEFERRED: Ship HUD visibly identifies itself and loads both consumers outside the pilot seat.' }
    @{ Id = 'pc-archive-pilot-seat'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'DEFERRED: While piloting, record whether the player HUD, ship HUD, both, or neither receives a new message ID without claiming guaranteed delivery.' }
  )
}
