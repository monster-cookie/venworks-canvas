@{
  Version = 1
  WatchPresentation = 'DisabledAfterSubscriptionsRestored'
  WatchBuild = 'build/player-hud-watch.build.psd1'
  Protocol = 'VWCANVAS_REGISTRY/1'
  TestMode = 'ExplicitConsumerUiLoad'
  UiLoadResult = 'UI_LOAD_QUEUED'
  UiLoadTransport = @{ EventHeader = @{ Selector = 1; Wire = 'VWC_EVT/1|' }; PacketType = @{ Selector = 1; Wire = 'canvas.ui.load' }; Protocol = 'canvas.ui.load'; Version = 1; MaxCharacters = 512; MaxPending = 32; MinimumIntervalSeconds = 1; MaxBusyAttempts = 20; Target = 'PlayerHud' }
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
    @{ Id = 'pc-console-result-output'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Each Canvas ConsoleResolve/action CGF prints exactly one final VWCANVAS-labeled status matching its Papyrus return/log path, including resolution failure. Busy remains inconclusive. The console check itself never enables or uses transport.' }
    @{ Id = 'pc-console-resolution'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'ComponentGalleryRegistrar.ConsoleResolve invoked with cgf logs VWCANVAS_CONSOLE/1 CONSOLE_BEGIN and CONSOLE_RESOLVED with its runtime form; missing form or script binding stops without forwarding work. No external load-order prefix or quest title is used.' }
    @{ Id = 'pc-console-host-recovery'; Packages = @('Canvas'); Expected = 'Registry.ConsoleResolve changes no registry state; explicit ConsoleEnsureStorage restores callbacks on an affected host-only save and logs REGISTRY_READY or a distinct inconclusive busy result without resetting valid records.' }
    @{ Id = 'pc-registration-host-only'; Packages = @('Canvas'); Expected = 'Host logs zero consumers and submits no load packets; all vanilla Watch subscriptions are restored before its presentation is detached and gameplay remains responsive.' }
    @{ Id = 'pc-registration-example'; Packages = @('Canvas', 'Example'); Expected = 'Example logs REGISTRATION_ACK then a separate UI_LOAD_QUEUED/UI_LOAD_SUBMITTED; readiness requires the visible panel.' }
    @{ Id = 'pc-registration-two-consumers'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Example and Component Gallery each acknowledge registration and validate RequestUiLoad ownership; registry count is two.' }
    @{ Id = 'pc-registration-reload'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Reload/menu openings preserve valid records; separate consumer load requests recreate the UI with bounded bridge traffic.' }
    @{ Id = 'pc-registration-rejection'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Invalid descriptors report the exact field once per attempt, terminate without polling, and never request a UI load.' }
    @{ Id = 'pc-registration-ui-ownership'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Unknown IDs and wrong owners receive REJECTED_*; check-only calls return REGISTERED_UI_LOAD_ELIGIBLE and never queue or transmit.' }
    @{ Id = 'pc-registration-uuid-case'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'D, braced D and compact UUID inputs in mixed case identify the same record; nil, malformed and whitespace inputs are rejected.' }
    @{ Id = 'pc-registration-concurrent-owners'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Simultaneous different-owner claims for the same UUID leave exactly one owner; mixed-case collision and reconciliation cannot duplicate or remove that record.' }
  )
  # Player HUD cases are the current PC gate; ship/pilot and package-removal cases remain later controlled acceptance.
  RuntimeCases = @(
    @{ Id = 'pc-archive-host-only'; Packages = @('Canvas'); Expected = 'Player HUD identifies EXPLICIT UI LOAD TEST, WATCH SUBSCRIPTIONS RESTORED and WATCH PRESENTATION DISABLED, submits no consumer load command and remains responsive. Provider subscription is not callback or delivery proof.' }
    @{ Id = 'pc-archive-example'; Packages = @('Canvas', 'Example'); Expected = 'Player HUD visibly reports Example READY from its namespaced normal movie.' }
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
