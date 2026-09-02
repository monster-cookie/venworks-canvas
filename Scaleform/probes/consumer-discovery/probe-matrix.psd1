@{
  Version = 3
  Protocol = 'VWCANVAS_REGISTRY_PROBE/2'
  DefaultProfile = 'Baseline'
  VwHudFixture = @{
    Revision = '74aff1c0df83e2c642750f942872e07033ed4a3a'
    RequiredToolchainFiles = @(
      'Tools/sharedScaleformMovies.ps1'
      'Tools/compileScaleform.ps1'
    )
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
    @{ Key = 'Host'; FileName = 'VWCANVAS9-Host.esm'; Script = 'Venworks/Canvas/Probes/ConsumerDiscovery/Registry.pex' }
    @{ Key = 'ConsumerA'; FileName = 'VWCANVAS9-ConsumerA.esm'; Script = 'Venworks/Canvas/Probes/ConsumerDiscovery/ConsumerARegistrar.pex' }
    @{ Key = 'ConsumerB'; FileName = 'VWCANVAS9-ConsumerB.esm'; Script = 'Venworks/Canvas/Probes/ConsumerDiscovery/ConsumerBRegistrar.pex' }
  )
  Staging = @(
    @{ Key = 'Host'; Directory = 'Staging-Host'; Plugin = 'VWCANVAS9-Host.esm'; Archive = 'VWCANVAS9-Host - Main.ba2' }
    @{ Key = 'ConsumerA'; Directory = 'Staging-ConsumerA'; Plugin = 'VWCANVAS9-ConsumerA.esm'; Archive = 'VWCANVAS9-ConsumerA - Main.ba2' }
    @{ Key = 'ConsumerB'; Directory = 'Staging-ConsumerB'; Plugin = 'VWCANVAS9-ConsumerB.esm'; Archive = 'VWCANVAS9-ConsumerB - Main.ba2' }
  )
  Profiles = @(
    @{ Key = 'Baseline'; ConsumerAMovie = 'ConsumerA'; ConsumerAVersion = 1; ConsumerADisplayName = 'VWCANVAS-9 Consumer A'; ConsumerBFaults = $false }
    @{ Key = 'Faults'; ConsumerAMovie = 'ConsumerA'; ConsumerAVersion = 1; ConsumerADisplayName = 'VWCANVAS-9 Consumer A'; ConsumerBFaults = $true }
    @{ Key = 'UpdatedA'; ConsumerAMovie = 'ConsumerAUpdated'; ConsumerAVersion = 2; ConsumerADisplayName = 'VWCANVAS-9 Consumer A UPDATED'; ConsumerBFaults = $false }
  )
  ParserCases = @(
    @{ Id = 'delimiter-display-name'; Expected = 'accepted' }
    @{ Id = 'invalid-consumer-id'; Expected = 'descriptor-rejected' }
    @{ Id = 'path-traversal'; Expected = 'descriptor-rejected' }
    @{ Id = 'duplicate-id'; Expected = 'first-valid-wins' }
    @{ Id = 'invalid-version'; Expected = 'descriptor-rejected' }
    @{ Id = 'truncated-record'; Expected = 'snapshot-rejected' }
    @{ Id = 'oversized-field'; Expected = 'snapshot-rejected' }
    @{ Id = 'invalid-plus-valid'; Expected = 'valid-consumer-retained' }
  )
  RuntimeCases = @(
    @{ Id = 'pc-archive-host-only'; Profile = 'Baseline'; Packages = @('Host'); Expected = 'Player HUD visibly reports a current snapshot with zero consumers and remains responsive.' }
    @{ Id = 'pc-archive-consumer-a'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA'); Expected = 'Player HUD visibly reports Consumer A READY from its namespaced normal movie.' }
    @{ Id = 'pc-archive-two-consumers'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Player HUD visibly reports both independently registered consumers READY with no static slot.' }
    @{ Id = 'pc-archive-reversed-consumer-order'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerB', 'ConsumerA'); Expected = 'Both consumers register regardless of consumer load order; Host remains their explicit master.' }
    @{ Id = 'pc-archive-collision-and-missing'; Profile = 'Faults'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'A and B remain READY while a different owner is visibly rejected for A and an intentionally missing consumer movie fails independently.' }
    @{ Id = 'pc-archive-update-consumer-a'; Profile = 'UpdatedA'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'After replacing the Baseline Consumer A package and loading the same save, the HUD visibly reports Consumer A UPDATED at version 2.' }
    @{ Id = 'pc-archive-remove-consumer-b'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA'); Expected = 'After saving with A and B, removing the Consumer B package, and loading the save, the registry prunes B and reports only A.' }
    @{ Id = 'pc-archive-id-reclamation'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'After the removal case, reinstalling Consumer B allows its released ID to register and become READY again.' }
    @{ Id = 'pc-archive-save-reload'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Closing and reopening the HUD after save reload replays bounded current-state snapshots and restores both consumers.' }
    @{ Id = 'pc-archive-menu-replay'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Ten repeated Player HUD close/open cycles visibly retain both consumers; any miss is recorded as a concrete one-way transport blocker.' }
    @{ Id = 'pc-archive-normal-large'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Normal and large player HUD movies load the corresponding namespaced consumer paths.' }
    @{ Id = 'pc-archive-ship-hud'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Ship HUD visibly identifies itself and loads both consumers outside the pilot seat.' }
    @{ Id = 'pc-archive-pilot-seat'; Profile = 'Baseline'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'While piloting, record whether the player HUD, ship HUD, both, or neither receives a new message ID without claiming guaranteed delivery.' }
  )
}
