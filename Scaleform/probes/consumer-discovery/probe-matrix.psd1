@{
  Version = 8
  Protocol = 'VWCANVAS_REGISTRY_PROBE/3'
  TestMode = 'ExplicitConsumerUiLoad'
  UiLoadResult = 'UI_LOAD_QUEUED'
  UiLoadTransport = @{ Protocol = 'canvas.ui.load'; Version = 1; MaxCharacters = 512; MaxPending = 32; MinimumIntervalSeconds = 1; MaxBusyAttempts = 20; Target = 'PlayerHud' }
  DefaultProfile = 'Baseline'
  Spriggit = @{
    PackageName = 'Spriggit.Yaml'
    MetadataPackageName = 'Spriggit.Yaml.Starfield'
    Version = '0.40.1'
    CliSha256 = '01E71FC882061F7387A5DC25022940A9A79892B81292C6B47F4DA2437649DCA5'
    TranslatorSha256 = 'E4358BFFA6E79723824764A5255A1ECA3A4FC14F10478FA42BA81ED58D7F1036'
    OutputRoot = 'Spriggit/ConsumerDiscovery'
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
  Movies = @(
    @{ Key = 'Host'; Manifest = 'build/host.build.xml'; Output = 'CanvasConsumerDiscoveryHost.swf' }
    @{ Key = 'ConsumerA'; Manifest = 'build/consumer-a.build.xml'; Output = 'CanvasDiscoveryConsumerA.swf' }
    @{ Key = 'ConsumerAUpdated'; Manifest = 'build/consumer-a-updated.build.xml'; Output = 'CanvasDiscoveryConsumerAUpdated.swf' }
    @{ Key = 'ConsumerB'; Manifest = 'build/consumer-b.build.xml'; Output = 'CanvasDiscoveryConsumerB.swf' }
  )
  Plugins = @(
    @{ Key = 'Host'; FileName = 'Venworks-Canvas-Host.esm'; Scripts = @('Venworks/Canvas/GlobalConfig.pex', 'Venworks/Canvas/Base/BaseQuest.pex', 'Venworks/Canvas/Probes/ConsumerDiscovery/Registry.pex') }
    @{ Key = 'ConsumerA'; FileName = 'Venworks-Canvas-ConsumerA.esm'; Scripts = @('Venworks/Canvas/Probes/ConsumerDiscovery/ConsumerARegistrar.pex', 'Venworks/Canvas/Probes/ConsumerDiscovery/ConsumerAUpdateMigration.pex') }
    @{ Key = 'ConsumerB'; FileName = 'Venworks-Canvas-ConsumerB.esm'; Scripts = @('Venworks/Canvas/Probes/ConsumerDiscovery/ConsumerBRegistrar.pex') }
  )
  Staging = @(
    @{ Key = 'Host'; Directory = 'Staging-Host'; Plugin = 'Venworks-Canvas-Host.esm'; Archive = 'Venworks-Canvas-Host - Main.ba2' }
    @{ Key = 'ConsumerA'; Directory = 'Staging-ConsumerA'; Plugin = 'Venworks-Canvas-ConsumerA.esm'; Archive = 'Venworks-Canvas-ConsumerA - Main.ba2' }
    @{ Key = 'ConsumerB'; Directory = 'Staging-ConsumerB'; Plugin = 'Venworks-Canvas-ConsumerB.esm'; Archive = 'Venworks-Canvas-ConsumerB - Main.ba2' }
  )
  Profiles = @(
    @{
      Key = 'Baseline'
      ConsumerAMovie = 'ConsumerA'
      ConsumerAVersion = 1
      ConsumerADisplayName = 'VWCANVAS-9 Consumer A'
      ConsumerBFaults = $false
      PluginSha256 = @{
        Host = '4265E0F9B3B63E6B8E1EEFAAC01781D5F2FB7D650050D30DFAEEC7BEC5E794EE'
        ConsumerA = '279AC14F54E0348C41A5E1AF5D8961EA34E41B3D50D6DB7E8B160059C8FAD34F'
        ConsumerB = '6E235B2DF75DA2FEEAE44B39E8F447AE79F6564525E0D0A1AFEE3C4B3BDEAD4C'
      }
    }
    @{
      Key = 'Faults'
      ConsumerAMovie = 'ConsumerA'
      ConsumerAVersion = 1
      ConsumerADisplayName = 'VWCANVAS-9 Consumer A'
      ConsumerBFaults = $true
      PluginSha256 = @{
        Host = '4265E0F9B3B63E6B8E1EEFAAC01781D5F2FB7D650050D30DFAEEC7BEC5E794EE'
        ConsumerA = '279AC14F54E0348C41A5E1AF5D8961EA34E41B3D50D6DB7E8B160059C8FAD34F'
        ConsumerB = '101A676F75EF47903B41CE3D264CB433F7CFA2E1CF9CD468D096FD96810B0423'
      }
    }
    @{
      Key = 'UpdatedA'
      ConsumerAMovie = 'ConsumerAUpdated'
      ConsumerAVersion = 2
      ConsumerADisplayName = 'VWCANVAS-9 Consumer A UPDATED'
      ConsumerBFaults = $false
      PluginSha256 = @{
        Host = '4265E0F9B3B63E6B8E1EEFAAC01781D5F2FB7D650050D30DFAEEC7BEC5E794EE'
        ConsumerA = '8E4C81957D728E07CC461380B26290FBC541061F2B63AC1444F167B6C95DF110'
        ConsumerB = '6E235B2DF75DA2FEEAE44B39E8F447AE79F6564525E0D0A1AFEE3C4B3BDEAD4C'
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
    @{ Id = 'pc-console-echo'; Packages = @('Host'); Expected = 'Core Utilities:Console.ConsoleEcho visibly echoes the supplied label with the RM> prefix under the PC debug-logging configuration; ConsoleOutputTests.Run exercises ordered block, blank, None/empty, and rejected LF entries. CR/CRLF VM coverage remains pending. These diagnostics are not needed for UI loading.' }
    @{ Id = 'pc-console-result-output'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Each Canvas ConsoleResolve/action CGF prints exactly one final VWCANVAS-labeled status matching its Papyrus return/log path, including resolution failure. Busy remains inconclusive and migration dispatch is not update acknowledgement. The console check itself never enables or uses transport.' }
    @{ Id = 'pc-console-resolution'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'ConsumerBRegistrar.ConsoleResolve invoked with cgf logs VWCANVAS_CONSOLE/1 CONSOLE_BEGIN and CONSOLE_RESOLVED with its runtime form; missing form or script binding stops without forwarding work. No external load-order prefix or quest title is used.' }
    @{ Id = 'pc-console-host-recovery'; Packages = @('Host'); Expected = 'Registry.ConsoleResolve changes no registry state; explicit ConsoleEnsureStorage restores callbacks on an affected host-only save and logs REGISTRY_READY or a distinct inconclusive busy result without resetting valid records.' }
    @{ Id = 'pc-console-update-recovery'; Profile = 'UpdatedA'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'ConsumerAUpdateMigration.ConsoleResolve resolves local record 000801 only in UpdatedA. ConsoleRetryUpdate reports dispatch, not acceptance; the existing migration later reports DESCRIPTOR_UPDATE_ACK without resetting an acknowledged update.' }
    @{ Id = 'pc-registration-host-only'; Packages = @('Host'); Expected = 'Host logs zero consumers and submits no load packets; vanilla watch stays responsive.' }
    @{ Id = 'pc-registration-consumer-a'; Packages = @('Host', 'ConsumerA'); Expected = 'A logs REGISTRATION_ACK then a separate UI_LOAD_QUEUED/UI_LOAD_SUBMITTED; readiness requires the visible panel.' }
    @{ Id = 'pc-registration-two-consumers'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'A and B each acknowledge registration and validate RequestUiLoad ownership; registry count is two.' }
    @{ Id = 'pc-registration-reload'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Reload/menu openings preserve valid records; separate consumer load requests recreate the UI with bounded bridge traffic.' }
    @{ Id = 'pc-registration-rejection'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Invalid descriptors report the exact field once per attempt, terminate without polling, and never request a UI load.' }
    @{ Id = 'pc-registration-ui-ownership'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Unknown IDs and wrong owners receive REJECTED_*; check-only calls return REGISTERED_UI_LOAD_ELIGIBLE and never queue or transmit.' }
    @{ Id = 'pc-registration-uuid-case'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'D, braced D and compact UUID inputs in mixed case identify the same record; nil, malformed and whitespace inputs are rejected.' }
    @{ Id = 'pc-registration-legacy-migration'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Known demo keys rekey to fixed UUIDs only for their existing owner, whether saved quest properties retain legacy text or now supply UUIDs; descriptors survive reload without duplicate rows.' }
    @{ Id = 'pc-registration-concurrent-owners'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Simultaneous different-owner claims for the same UUID leave exactly one owner; mixed-case collision and reconciliation cannot duplicate or remove that record.' }
    @{ Id = 'pc-registration-pending-update'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'UpdatedA arriving during registration defers without waiting for a guard and applies version 2 after acceptance; unavailable-registry updates remain pending and reconcile without reverting after save/reload.' }
  )
  # Player HUD cases are the current PC gate; ship/pilot and package-removal cases remain later controlled acceptance.
  RuntimeCases = @(
    @{ Id = 'pc-archive-host-only'; Profile = 'Baseline'; Packages = @('Host'); Expected = 'Player HUD identifies EXPLICIT UI LOAD TEST, submits no consumer load command and remains responsive.' }
    @{ Id = 'pc-archive-consumer-a'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA'); Expected = 'Player HUD visibly reports Consumer A READY from its namespaced normal movie.' }
    @{ Id = 'pc-archive-two-consumers'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Player HUD visibly reports both independently registered consumers READY with no static slot.' }
    @{ Id = 'pc-archive-reversed-consumer-order'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerB', 'ConsumerA'); Expected = 'Both consumers register regardless of consumer load order; Host remains their explicit master.' }
    @{ Id = 'pc-archive-collision-and-missing'; Profile = 'Faults'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'A and B remain READY while a different owner is rejected for A in Papyrus logs and an intentionally missing consumer movie fails independently.' }
    @{ Id = 'pc-archive-update-consumer-a'; Profile = 'UpdatedA'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'After replacing the Baseline Consumer A package and loading the same save, the HUD visibly reports Consumer A UPDATED at version 2 and retains version 2 after closing and reopening the HUD.' }
    @{ Id = 'pc-archive-remove-consumer-b'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA'); Expected = 'After saving with A and B, removing the Consumer B package, and loading the save, the registry prunes B and reports only A.' }
    @{ Id = 'pc-archive-id-reclamation'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'After the removal case, reinstalling Consumer B allows its released ID to register and become READY again.' }
    @{ Id = 'pc-archive-save-reload'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Closing/reopening the HUD after save reload preserves registration and the consumers explicitly request their UI again; both panels reappear.' }
    @{ Id = 'pc-archive-menu-replay'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Ten repeated Player HUD close/open cycles visibly retain both consumers; any miss is recorded as a concrete one-way transport blocker.' }
    @{ Id = 'pc-archive-normal-large'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Normal and large player HUD movies load the corresponding namespaced consumer paths.' }
    @{ Id = 'pc-archive-ship-hud'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'DEFERRED: Ship HUD visibly identifies itself and loads both consumers outside the pilot seat.' }
    @{ Id = 'pc-archive-pilot-seat'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'DEFERRED: While piloting, record whether the player HUD, ship HUD, both, or neither receives a new message ID without claiming guaranteed delivery.' }
  )
}
