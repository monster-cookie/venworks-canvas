@{
  Version = 2
  Protocol = 'VWCANVAS_REGISTRY_PROBE/1'
  VwHudFixture = @{
    Revision = '74aff1c0df83e2c642750f942872e07033ed4a3a'
    RequiredPipelineFiles = @(
      'Tools/compileScaleformAuxiliaryV2.ps1'
      'Tools/buildVariantV2.ps1'
      'Tools/createPackagesV2.ps1'
      'Tools/sharedScaleformMovies.ps1'
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
  RuntimeCases = @(
    @{ Id = 'pc-archive-host-only'; Packages = @('Host'); Expected = 'Player HUD visibly reports snapshot 0 consumers and remains responsive.' }
    @{ Id = 'pc-archive-consumer-a'; Packages = @('Host', 'ConsumerA'); Expected = 'Player HUD visibly reports Consumer A READY from its namespaced normal movie.' }
    @{ Id = 'pc-archive-two-consumers'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Player HUD visibly reports both independently registered consumers READY with no static slot.' }
    @{ Id = 'pc-archive-reversed-consumer-order'; Packages = @('Host', 'ConsumerB', 'ConsumerA'); Expected = 'Both consumers register regardless of consumer load order; Host remains their explicit master.' }
    @{ Id = 'pc-archive-save-reload'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Closing and reopening the HUD after save reload replays one current snapshot and restores both consumers.' }
    @{ Id = 'pc-archive-normal-large'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Normal and large player HUD movies load the corresponding namespaced consumer paths.' }
    @{ Id = 'pc-archive-ship-hud'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'Ship HUD visibly identifies itself and loads both consumers outside the pilot seat.' }
    @{ Id = 'pc-archive-pilot-seat'; Packages = @('Host', 'ConsumerA', 'ConsumerB'); Expected = 'While piloting, record whether the player HUD, ship HUD, both, or neither receives a new message ID.' }
  )
}
