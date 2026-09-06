@{
  Version = 1
  WatchPresentation = 'DisabledAfterSubscriptionsRestored'
  WatchBuild = 'build/player-hud-watch.build.psd1'
  Protocol = 'VWCANVAS_REGISTRY/1'
  TestMode = 'ExplicitConsumerUiLoad'
  UiLoadResult = 'UI_LOAD_QUEUED'
  UiLoadTransport = @{ EventHeader = @{ Selector = 1; Wire = 'VWC_EVT/1|' }; PacketType = @{ Selector = 1; Wire = 'canvas.ui.load' }; Protocol = 'canvas.ui.load'; Version = 1; MaxCharacters = 512; MaxPending = 32; MinimumIntervalSeconds = 1; MaxBusyAttempts = 20; Target = 'PlayerHud' }
  DefaultProfile = 'Production'
  Spriggit = @{
    PackageName = 'Spriggit.Yaml'
    MetadataPackageName = 'Spriggit.Yaml.Starfield'
    Version = '0.40.1'
    CliSha256 = '01E71FC882061F7387A5DC25022940A9A79892B81292C6B47F4DA2437649DCA5'
    TranslatorSha256 = 'E4358BFFA6E79723824764A5255A1ECA3A4FC14F10478FA42BA81ED58D7F1036'
    OutputRoot = 'Spriggit'
  }
  VenworksCoreFixture = @{
    Revision = 'fce6fadcb110f8a462c41680a1147d3c36e8421f'
    SourceFiles = @(
      @{ Path = 'Papyrus/Venworks/Core/Utilities/Console.psc'; Sha256 = '2BF41AF1CDD4E85B7BB57C7643C56AB293B346DB305975650CE7870DF68FC835' }
      @{ Path = 'Papyrus/Venworks/Core/Tests/ConsoleOutputTests.psc'; Sha256 = 'CBC699724A55E58BB70B339D7AF5BB3748353C2404ADFF18DCAF645F15DD774A' }
      @{ Path = 'Papyrus/Venworks/Core/Utilities/UUID.psc'; Sha256 = '5BEC2410485E13E3925CA3E58E3EACC218F25FBF0FC49E8AAFC24D98FDF5EB24' }
      @{ Path = 'Papyrus/Venworks/Core/Tests/UUIDTests.psc'; Sha256 = '076639D852BE419BC791C262C692B100161AC5E2FC4D65F0A554BE5933C8F931' }
      @{ Path = 'Papyrus/Venworks/Core/Base/BaseQuest.psc'; Sha256 = 'F6949CA9871039FA68B697676C3095A320A06983459C9472DFC73C5D5B02626A' }
      @{ Path = 'Papyrus/Venworks/Core/Logging.psc'; Sha256 = '2DB449958CFF801155B7B8044818EA5E9514AC85F5BF50E7AC27AC469924E6E5' }
      @{ Path = 'Papyrus/Venworks/Core/Enumerations.psc'; Sha256 = '48D37F52FB226F5E90E4DA4A49EFE62E1B03EE8B571BBDF36BEDBCE91A1A67C9' }
      @{ Path = 'Papyrus/Venworks/Core/GlobalConfig.psc'; Sha256 = 'D1BA0153344316AD0CE9A989BC235C3218BBCD9F3EE5D4F8BF11AC4F250A9E80' }
    )
    RuntimeScripts = @(
      @{ Source = 'Staging/Scripts/Venworks/Core/Utilities/Console.pex'; Target = 'Scripts/Venworks/Core/Utilities/Console.pex'; Sha256 = '5BEDE7090FD580B70776D1E64B8EC98B084AD8BD3C787CA3342633551E42EA7D' }
      @{ Source = 'Staging/Scripts/Venworks/Core/Tests/ConsoleOutputTests.pex'; Target = 'Scripts/Venworks/Core/Tests/ConsoleOutputTests.pex'; Sha256 = '51BC4040102A3A60F200882629B264E0826DACF2C2758CC77E3C5BB7FD526B06' }
      @{ Source = 'Staging/Scripts/Venworks/Core/Utilities/UUID.pex'; Target = 'Scripts/Venworks/Core/Utilities/UUID.pex'; Sha256 = '611C0777CA4BCBCAA5CB5748FB70759E884DECBA89DD8174A781814798FCF03E' }
      @{ Source = 'Staging/Scripts/Venworks/Core/Tests/UUIDTests.pex'; Target = 'Scripts/Venworks/Core/Tests/UUIDTests.pex'; Sha256 = '12AE2847A0C7E398C56F594F10C2497B7F8EC828508F71C9D1D34A1CCAD88AC2' }
      @{ Source = 'Staging/Scripts/Venworks/Core/Base/BaseQuest.pex'; Target = 'Scripts/Venworks/Core/Base/BaseQuest.pex'; Sha256 = 'BF118F1918605CD1DF374C54C0D741B3FB98F8D1CBBA9FECA707CE105011F917' }
      @{ Source = 'Staging/Scripts/Venworks/Core/Logging.pex'; Target = 'Scripts/Venworks/Core/Logging.pex'; Sha256 = '16F393D15F10EEAC273D6B40C951AA3F2EC3DB8CDAF2C9E086BDFDEA31B154D5' }
      @{ Source = 'Staging/Scripts/Venworks/Core/Enumerations.pex'; Target = 'Scripts/Venworks/Core/Enumerations.pex'; Sha256 = 'AE84C6618ACC629B827C64DF7C597CB8F0A1B2492338632D4D3A78F53ADF17E4' }
      @{ Source = 'Staging/Scripts/Venworks/Core/GlobalConfig.pex'; Target = 'Scripts/Venworks/Core/GlobalConfig.pex'; Sha256 = '0EFF6E5B453DAA22CB0A3C93161ECBB00078C6734032A4250C2971FA8221692A' }
    )
  }
  VwHudFixture = @{
    Revision = '74aff1c0df83e2c642750f942872e07033ed4a3a'
    RequiredToolchainFiles = @(
      'Tools/sharedScaleformMovies.ps1'
      'Tools/compileScaleform.ps1'
    )
    AuxiliaryDerivedFiles = @(
      'Tools/sharedScaleformMovies.ps1'
    )
    ShipCompilerFile = 'Tools/compileScaleform.ps1'
    PlayerHudMovies = @(
      @{ Source = 'Staging-PS5DBG/Interface/hudmenu.gfx'; Target = 'Interface/hudmenu.gfx' }
      @{ Source = 'Staging-PS5DBG/Interface/hudmenu.swf'; Target = 'Interface/hudmenu.swf' }
      @{ Source = 'Staging-PS5DBG/Interface/hudmenu_lrg.gfx'; Target = 'Interface/hudmenu_lrg.gfx' }
      @{ Source = 'Staging-PS5DBG/Interface/hudmenu_lrg.swf'; Target = 'Interface/hudmenu_lrg.swf' }
    )
  }
  Profiles = @(
    @{
      Key = 'Production'
      ExampleMovie = 'Example'
      ExampleVersion = 1
      ExampleDisplayName = 'Venworks Canvas Example'
      ComponentGalleryFaults = $false
      PluginSha256 = @{
        CANVAS = 'DE3B4E4203FA3C1E8B499E5B801DDA15B6C9E73CB1566838BB139540333E221E'
        EXAMPLE = '8F402192BEFF0C1E3982587F6F25C6134C32A71F98B05E75CC1C8642821E59EF'
        COMPONENTGALLERY = '87821A7A806D984AD86E1FB1D417A6552D84D6C34C181B5B25A5C6E6A5280A6A'
      }
    }
    @{
      Key = 'Faults'
      ExampleMovie = 'Example'
      ExampleVersion = 1
      ExampleDisplayName = 'Venworks Canvas Example'
      ComponentGalleryFaults = $true
      PluginSha256 = @{
        CANVAS = 'DE3B4E4203FA3C1E8B499E5B801DDA15B6C9E73CB1566838BB139540333E221E'
        EXAMPLE = '8F402192BEFF0C1E3982587F6F25C6134C32A71F98B05E75CC1C8642821E59EF'
        COMPONENTGALLERY = '0E8CCDCECBDE51E0BAFBFF799406E4617A19E16F7D443E65F67664DD8AB26F97'
      }
    }
  )
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
    @{ Id = 'pc-archive-host-only'; Profile = 'Production'; Packages = @('Canvas'); Expected = 'Player HUD identifies EXPLICIT UI LOAD TEST, WATCH SUBSCRIPTIONS RESTORED and WATCH PRESENTATION DISABLED, submits no consumer load command and remains responsive. Provider subscription is not callback or delivery proof.' }
    @{ Id = 'pc-archive-example'; Profile = 'Production'; Packages = @('Canvas', 'Example'); Expected = 'Player HUD visibly reports Example READY from its namespaced normal movie.' }
    @{ Id = 'pc-archive-two-consumers'; Profile = 'Production'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Player HUD visibly reports both independently registered consumers READY with no static slot.' }
    @{ Id = 'pc-archive-reversed-consumer-order'; Profile = 'Production'; Packages = @('Canvas', 'ComponentGallery', 'Example'); Expected = 'Both consumers register regardless of consumer load order; Host remains their explicit master.' }
    @{ Id = 'pc-archive-collision-and-missing'; Profile = 'Faults'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Example and Component Gallery remain READY while a different owner is rejected for the Example UUID in Papyrus logs and an intentionally missing consumer movie fails independently.' }
    @{ Id = 'pc-archive-remove-component-gallery'; Profile = 'Production'; Packages = @('Canvas', 'Example'); Expected = 'After saving with both consumers, removing the Component Gallery package, and loading the save, the registry prunes Component Gallery and reports only Example.' }
    @{ Id = 'pc-archive-id-reclamation'; Profile = 'Production'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'After the removal case, reinstalling Component Gallery allows its released ID to register and become READY again.' }
    @{ Id = 'pc-archive-save-reload'; Profile = 'Production'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Closing/reopening the HUD after save reload preserves registration and the consumers explicitly request their UI again; both panels reappear.' }
    @{ Id = 'pc-archive-menu-replay'; Profile = 'Production'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Ten repeated Player HUD close/open cycles visibly retain both consumers; any miss is recorded as a concrete one-way transport blocker.' }
    @{ Id = 'pc-archive-normal-large'; Profile = 'Production'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'Normal and large player HUD movies load the corresponding namespaced consumer paths.' }
    @{ Id = 'pc-archive-ship-hud'; Profile = 'Production'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'DEFERRED: Ship HUD visibly identifies itself and loads both consumers outside the pilot seat.' }
    @{ Id = 'pc-archive-pilot-seat'; Profile = 'Production'; Packages = @('Canvas', 'Example', 'ComponentGallery'); Expected = 'DEFERRED: While piloting, record whether the player HUD, ship HUD, both, or neither receives a new message ID without claiming guaranteed delivery.' }
  )
}
