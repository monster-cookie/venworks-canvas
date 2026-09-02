@{
  Version = 1
  Protocol = 'VWCANVAS_DISCOVERY_PROBE/1'
  VwHudFixture = @{
    Revision = '74aff1c0df83e2c642750f942872e07033ed4a3a'
    RequiredPipelineFiles = @(
      'Tools/compileScaleformAuxiliaryV2.ps1'
      'Tools/buildVariantV2.ps1'
      'Tools/createPackagesV2.ps1'
      'Tools/sharedScaleformMovies.ps1'
    )
    HostMovies = @(
      @{
        Source = 'Staging-PS5DBG/Interface/hudmenu.gfx'
        Manifest = 'Scaleform/variants/PS5DBG/movies/hudmenu.build.xml'
        Target = 'Interface/hudmenu.gfx'
      }
      @{
        Source = 'Staging-PS5DBG/Interface/hudmenu.swf'
        Manifest = 'Scaleform/variants/PS5DBG/movies/hudmenu-swf.build.xml'
        Target = 'Interface/hudmenu.swf'
      }
      @{
        Source = 'Staging-PS5DBG/Interface/hudmenu_lrg.gfx'
        Manifest = 'Scaleform/variants/PS5DBG/movies/hudmenu-lrg.build.xml'
        Target = 'Interface/hudmenu_lrg.gfx'
      }
      @{
        Source = 'Staging-PS5DBG/Interface/hudmenu_lrg.swf'
        Manifest = 'Scaleform/variants/PS5DBG/movies/hudmenu-lrg-swf.build.xml'
        Target = 'Interface/hudmenu_lrg.swf'
      }
    )
  }
  Movies = @(
    @{ Key = 'Host'; Manifest = 'build/host.build.xml'; Output = 'CanvasConsumerDiscoveryHost.swf' }
    @{ Key = 'A1'; Manifest = 'build/consumer-a.build.xml'; Output = 'CanvasDiscoveryConsumerA.swf' }
    @{ Key = 'A2'; Manifest = 'build/consumer-a-update.build.xml'; Output = 'CanvasDiscoveryConsumerAUpdate.swf' }
    @{ Key = 'B1'; Manifest = 'build/consumer-b.build.xml'; Output = 'CanvasDiscoveryConsumerB.swf' }
    @{ Key = 'Invalid'; Manifest = 'build/consumer-invalid.build.xml'; Output = 'CanvasDiscoveryConsumerInvalid.swf' }
  )
  Slots = @(
    @{ Index = 0; Name = 'slot-00'; NormalPath = 'Interface/VenworksCanvas/Consumers/normal/slot-00.swf'; LargePath = 'Interface/VenworksCanvas/Consumers/large/slot-00.swf' }
    @{ Index = 1; Name = 'slot-01'; NormalPath = 'Interface/VenworksCanvas/Consumers/normal/slot-01.swf'; LargePath = 'Interface/VenworksCanvas/Consumers/large/slot-01.swf' }
    @{ Index = 2; Name = 'slot-02'; NormalPath = 'Interface/VenworksCanvas/Consumers/normal/slot-02.swf'; LargePath = 'Interface/VenworksCanvas/Consumers/large/slot-02.swf' }
    @{ Index = 3; Name = 'slot-03'; NormalPath = 'Interface/VenworksCanvas/Consumers/normal/slot-03.swf'; LargePath = 'Interface/VenworksCanvas/Consumers/large/slot-03.swf' }
  )
  Packages = @(
    @{ Key = 'Host'; BaseName = 'VWCANVAS9-Discovery-Host'; MovieKey = 'Host'; Role = 'Host' }
    @{ Key = 'A1'; BaseName = 'VWCANVAS9-Discovery-A1'; MovieKey = 'A1'; Role = 'Consumer'; Slot = 0 }
    @{ Key = 'A2'; BaseName = 'VWCANVAS9-Discovery-A2'; MovieKey = 'A2'; Role = 'Consumer'; Slot = 0 }
    @{ Key = 'B1'; BaseName = 'VWCANVAS9-Discovery-B1'; MovieKey = 'B1'; Role = 'Consumer'; Slot = 1 }
    @{ Key = 'Invalid'; BaseName = 'VWCANVAS9-Discovery-Invalid'; MovieKey = 'Invalid'; Role = 'Consumer'; Slot = 0 }
  )
  RuntimeCases = @(
    @{ Id = 'pc-loose-host-only'; Platform = 'PC'; Shape = 'Loose'; Packages = @('Host'); Expected = 'slot-00 through slot-03 report MISSING; host remains responsive' }
    @{ Id = 'pc-loose-a1'; Platform = 'PC'; Shape = 'Loose'; Packages = @('Host', 'A1'); Expected = 'slot-00 reports READY A1; later slots report MISSING' }
    @{ Id = 'pc-loose-a1-b1'; Platform = 'PC'; Shape = 'Loose'; Packages = @('Host', 'A1', 'B1'); Expected = 'slot-00 reports READY A1 and slot-01 reports READY B1' }
    @{ Id = 'pc-archive-host-only'; Platform = 'PC'; Shape = 'Archive'; Packages = @('Host'); Expected = 'archive-only missing-slot handling completes without disabling the HUD' }
    @{ Id = 'pc-archive-b1-after-missing'; Platform = 'PC'; Shape = 'Archive'; Packages = @('Host', 'B1'); Expected = 'slot-00 reports MISSING and slot-01 still reports READY B1' }
    @{ Id = 'pc-archive-a1-b1'; Platform = 'PC'; Shape = 'Archive'; Packages = @('Host', 'A1', 'B1'); Expected = 'two distinct fixed slots report READY' }
    @{ Id = 'pc-archive-collision-a1-wins'; Platform = 'PC'; Shape = 'Archive'; Packages = @('Host', 'A2', 'A1'); Expected = 'slot-00 reports A1 when A1 is the observed winning archive' }
    @{ Id = 'pc-archive-collision-a2-wins'; Platform = 'PC'; Shape = 'Archive'; Packages = @('Host', 'A1', 'A2'); Expected = 'slot-00 reports A2 when A2 is the observed winning archive' }
    @{ Id = 'pc-archive-update-a1-to-a2'; Platform = 'PC'; Shape = 'Archive'; Packages = @('Host', 'A1', 'A2'); Expected = 'cold start reports A1 before replacement and A2 after replacement' }
    @{ Id = 'pc-archive-remove-a'; Platform = 'PC'; Shape = 'Archive'; Packages = @('Host', 'A1'); Expected = 'cold start reports A1 before removal and MISSING after removal' }
    @{ Id = 'pc-archive-invalid-then-b1'; Platform = 'PC'; Shape = 'Archive'; Packages = @('Host', 'Invalid', 'B1'); Expected = 'slot-00 reports INVALID and slot-01 still reports READY B1' }
    @{ Id = 'pc-archive-normal-large'; Platform = 'PC'; Shape = 'Archive'; Packages = @('Host', 'A1', 'B1'); Expected = 'normal and large HUD hosts request their corresponding explicit path roots' }
    @{ Id = 'pc-archive-teardown'; Platform = 'PC'; Shape = 'Archive'; Packages = @('Host', 'A1', 'B1'); Expected = 'HUD close and reopen produces one fresh bounded inventory with no late callbacks' }
    @{ Id = 'ps5-vwhud-baseline'; Platform = 'PS5'; Shape = 'Archive'; Packages = @(); Expected = 'unchanged pinned VWHUD PS5DBG host remains the last accepted no-Canvas baseline' }
    @{ Id = 'ps5-host-missing'; Platform = 'PS5'; Shape = 'Archive'; Packages = @('Host'); Expected = 'one missing-slot request completes before expanding the matrix' }
    @{ Id = 'ps5-a1'; Platform = 'PS5'; Shape = 'Archive'; Packages = @('Host', 'A1'); Expected = 'slot-00 reports READY A1' }
    @{ Id = 'ps5-a1-b1'; Platform = 'PS5'; Shape = 'Archive'; Packages = @('Host', 'A1', 'B1'); Expected = 'two distinct fixed slots report READY' }
    @{ Id = 'ps5-collision'; Platform = 'PS5'; Shape = 'Archive'; Packages = @('Host', 'A1', 'A2'); Expected = 'both load orders select the observed archive winner deterministically across cold starts' }
    @{ Id = 'ps5-update'; Platform = 'PS5'; Shape = 'Archive'; Packages = @('Host', 'A1', 'A2'); Expected = 'A1 to A2 replacement is visible after a cold start' }
    @{ Id = 'ps5-remove'; Platform = 'PS5'; Shape = 'Archive'; Packages = @('Host', 'A1'); Expected = 'removal returns slot-00 to MISSING after a cold start' }
    @{ Id = 'ps5-normal-large'; Platform = 'PS5'; Shape = 'Archive'; Packages = @('Host', 'A1', 'B1'); Expected = 'normal and large hosts request their corresponding explicit path roots' }
    @{ Id = 'ps5-teardown'; Platform = 'PS5'; Shape = 'Archive'; Packages = @('Host', 'A1', 'B1'); Expected = 'HUD close and reopen produces one fresh bounded inventory with no late callbacks' }
  )
}
