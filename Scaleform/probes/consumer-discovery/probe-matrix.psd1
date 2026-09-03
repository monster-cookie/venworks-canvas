@{
  Version = 5
  Protocol = 'VWCANVAS_REGISTRY_PROBE/3'
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
    Revision = '23de60ba837c62ba4c07396059e242a0d54cc629'
    SourceFiles = @(
      @{ Path = 'Papyrus/Venworks/Core/Base/BaseQuest.psc'; Sha256 = 'F6949CA9871039FA68B697676C3095A320A06983459C9472DFC73C5D5B02626A' }
      @{ Path = 'Papyrus/Venworks/Core/Logging.psc'; Sha256 = '2DB449958CFF801155B7B8044818EA5E9514AC85F5BF50E7AC27AC469924E6E5' }
      @{ Path = 'Papyrus/Venworks/Core/Enumerations.psc'; Sha256 = '48D37F52FB226F5E90E4DA4A49EFE62E1B03EE8B571BBDF36BEDBCE91A1A67C9' }
      @{ Path = 'Papyrus/Venworks/Core/GlobalConfig.psc'; Sha256 = 'D1BA0153344316AD0CE9A989BC235C3218BBCD9F3EE5D4F8BF11AC4F250A9E80' }
    )
    RuntimeScripts = @(
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
    @{ Key = 'Host'; FileName = 'VWCANVAS9-Host.esm'; Scripts = @('Venworks/Canvas/GlobalConfig.pex', 'Venworks/Canvas/Base/BaseQuest.pex', 'Venworks/Canvas/Probes/ConsumerDiscovery/Registry.pex') }
    @{ Key = 'ConsumerA'; FileName = 'VWCANVAS9-ConsumerA.esm'; Scripts = @('Venworks/Canvas/Probes/ConsumerDiscovery/ConsumerARegistrar.pex', 'Venworks/Canvas/Probes/ConsumerDiscovery/ConsumerAUpdateMigration.pex') }
    @{ Key = 'ConsumerB'; FileName = 'VWCANVAS9-ConsumerB.esm'; Scripts = @('Venworks/Canvas/Probes/ConsumerDiscovery/ConsumerBRegistrar.pex') }
  )
  Staging = @(
    @{ Key = 'Host'; Directory = 'Staging-Host'; Plugin = 'VWCANVAS9-Host.esm'; Archive = 'VWCANVAS9-Host - Main.ba2' }
    @{ Key = 'ConsumerA'; Directory = 'Staging-ConsumerA'; Plugin = 'VWCANVAS9-ConsumerA.esm'; Archive = 'VWCANVAS9-ConsumerA - Main.ba2' }
    @{ Key = 'ConsumerB'; Directory = 'Staging-ConsumerB'; Plugin = 'VWCANVAS9-ConsumerB.esm'; Archive = 'VWCANVAS9-ConsumerB - Main.ba2' }
  )
  Profiles = @(
    @{
      Key = 'Baseline'
      ConsumerAMovie = 'ConsumerA'
      ConsumerAVersion = 1
      ConsumerADisplayName = 'VWCANVAS-9 Consumer A'
      ConsumerBFaults = $false
      PluginSha256 = @{
        Host = '3116B07CCBCA0E9783D4181B00FD89BAB899F9386DA253AAEC33FB9D4BB760DE'
        ConsumerA = 'B4764B2CC82BFC3101200C3BCE15EB0F36B4E26F5F27CCB2B40B4F5B4CD56699'
        ConsumerB = '7150876C736C83A61141EFC2B336E9C141631546431F5FA5D6B97CF1A7A7151E'
      }
    }
    @{
      Key = 'Faults'
      ConsumerAMovie = 'ConsumerA'
      ConsumerAVersion = 1
      ConsumerADisplayName = 'VWCANVAS-9 Consumer A'
      ConsumerBFaults = $true
      PluginSha256 = @{
        Host = '3116B07CCBCA0E9783D4181B00FD89BAB899F9386DA253AAEC33FB9D4BB760DE'
        ConsumerA = 'B4764B2CC82BFC3101200C3BCE15EB0F36B4E26F5F27CCB2B40B4F5B4CD56699'
        ConsumerB = 'AFFB5621DF4DBADF76F3F64F475221116460BAD1419B196761042C00A00AD8D5'
      }
    }
    @{
      Key = 'UpdatedA'
      ConsumerAMovie = 'ConsumerAUpdated'
      ConsumerAVersion = 2
      ConsumerADisplayName = 'VWCANVAS-9 Consumer A UPDATED'
      ConsumerBFaults = $false
      PluginSha256 = @{
        Host = '3116B07CCBCA0E9783D4181B00FD89BAB899F9386DA253AAEC33FB9D4BB760DE'
        ConsumerA = 'B445D7654901A0EA75AB68AB04A5F22905F74064F5E3779328FEBA5E944E8713'
        ConsumerB = '7150876C736C83A61141EFC2B336E9C141631546431F5FA5D6B97CF1A7A7151E'
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
  RuntimeCases = @(
    @{ Id = 'pc-archive-host-only'; Profile = 'Baseline'; Packages = @('Host'); Expected = 'Player HUD visibly reports a current snapshot with zero consumers and remains responsive.' }
    @{ Id = 'pc-archive-consumer-a'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA'); Expected = 'Player HUD visibly reports Consumer A READY from its namespaced normal movie.' }
    @{ Id = 'pc-archive-two-consumers'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Player HUD visibly reports both independently registered consumers READY with no static slot.' }
    @{ Id = 'pc-archive-reversed-consumer-order'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerB', 'ConsumerA'); Expected = 'Both consumers register regardless of consumer load order; Host remains their explicit master.' }
    @{ Id = 'pc-archive-collision-and-missing'; Profile = 'Faults'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'A and B remain READY while a different owner is visibly rejected for A and an intentionally missing consumer movie fails independently.' }
    @{ Id = 'pc-archive-update-consumer-a'; Profile = 'UpdatedA'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'After replacing the Baseline Consumer A package and loading the same save, the HUD visibly reports Consumer A UPDATED at version 2 and retains version 2 after closing and reopening the HUD.' }
    @{ Id = 'pc-archive-remove-consumer-b'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA'); Expected = 'After saving with A and B, removing the Consumer B package, and loading the save, the registry prunes B and reports only A.' }
    @{ Id = 'pc-archive-id-reclamation'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'After the removal case, reinstalling Consumer B allows its released ID to register and become READY again.' }
    @{ Id = 'pc-archive-save-reload'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Closing and reopening the HUD after save reload replays bounded current-state snapshots and restores both consumers.' }
    @{ Id = 'pc-archive-menu-replay'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Ten repeated Player HUD close/open cycles visibly retain both consumers; any miss is recorded as a concrete one-way transport blocker.' }
    @{ Id = 'pc-archive-normal-large'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Normal and large player HUD movies load the corresponding namespaced consumer paths.' }
    @{ Id = 'pc-archive-ship-hud'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Ship HUD visibly identifies itself and loads both consumers outside the pilot seat.' }
    @{ Id = 'pc-archive-pilot-seat'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'While piloting, record whether the player HUD, ship HUD, both, or neither receives a new message ID without claiming guaranteed delivery.' }
  )
}
