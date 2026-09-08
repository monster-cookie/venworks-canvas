<#
.SYNOPSIS
Loads the Canvas build environment and declares its reusable build configuration.

.PARAMETER EnvironmentPath
Environment file selected by the first successful configuration initialization in the current PowerShell session. Start a fresh process to initialize from a different file.
#>
[CmdletBinding()]
param(
  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedVariants.ps1')
. (Join-Path $PSScriptRoot 'sharedBuild.ps1')

Import-BuildEnvironment -Path $EnvironmentPath

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Global:BuildSettings = @{
  WorkRoot = Join-Path $repositoryRoot '.work/canvas'
  PapyrusSourceRoot = Join-Path $repositoryRoot 'Papyrus'
  ScriptsDirectory = Join-Path $repositoryRoot '.work/canvas/scripts'
  ScaleformSourceRoot = Join-Path $repositoryRoot 'Scaleform/canvas'
  ScaleformDirectory = Join-Path $repositoryRoot '.work/canvas/scaleform'
}

$Global:ModuleVariants = @(
  [ModuleVariant]::new(
    'CANVAS',
    'Venworks Canvas',
    'Venworks-Canvas.esm',
    'Venworks-Canvas',
    'Venworks:Canvas',
    (Join-Path $repositoryRoot 'Staging-Canvas'),
    'MODULE_VARIANT_CANVAS_PATH',
    @(
      @{
        Name = 'canvas-host'
        Kind = 'Flex'
        OutputSet = 'movies'
        ManifestPath = 'Scaleform/canvas/build/canvas.build.xml'
        Outputs = @(
          @{ OutputFile = 'CanvasHost.swf' }
        )
      }
      @{
        Name = 'player-watch'
        Kind = 'Patch'
        OutputSet = 'player-hud'
        PatchPath = 'Scaleform/canvas/patches/player-hud-watch-disabled.xml'
        Outputs = @(
          @{ InputFile = 'playerhudcomponents.swf'; OutputFile = 'playerhudcomponents.swf' }
          @{ InputFile = 'playerhudcomponents.gfx'; OutputFile = 'playerhudcomponents.gfx' }
          @{ InputFile = 'playerhudcomponents_lrg.swf'; OutputFile = 'playerhudcomponents_lrg.swf' }
          @{ InputFile = 'playerhudcomponents_lrg.gfx'; OutputFile = 'playerhudcomponents_lrg.gfx' }
        )
      }
      @{
        Name = 'ship-loader'
        Kind = 'Patch'
        OutputSet = 'ship-hud'
        PatchPath = 'Scaleform/canvas/patches/spaceship-hud-auxiliary-loader.xml'
        Outputs = @(
          @{ InputFile = 'spaceshiphudmenu.swf'; OutputFile = 'spaceshiphudmenu.swf' }
          @{ InputFile = 'spaceshiphudmenu_lrg.swf'; OutputFile = 'spaceshiphudmenu_lrg.swf' }
        )
      }
    ),
    @(
      @{
        FileName = 'Venworks-Canvas - Main.ba2'
        Format = 'General'
        Compression = 'None'
        MaxSizeMB = 2048
        IncludePapyrus = $true
        Assets = @(
          @{ Root = 'Scaleform'; Source = 'movies/CanvasHost.swf'; Target = 'Interface/venworkscui.swf' }
          @{ Root = 'Scaleform'; Source = 'player-hud/playerhudcomponents.swf'; Target = 'Interface/playerhudcomponents.swf' }
          @{ Root = 'Scaleform'; Source = 'player-hud/playerhudcomponents.gfx'; Target = 'Interface/playerhudcomponents.gfx' }
          @{ Root = 'Scaleform'; Source = 'player-hud/playerhudcomponents_lrg.swf'; Target = 'Interface/playerhudcomponents_lrg.swf' }
          @{ Root = 'Scaleform'; Source = 'player-hud/playerhudcomponents_lrg.gfx'; Target = 'Interface/playerhudcomponents_lrg.gfx' }
          @{ Root = 'Scaleform'; Source = 'ship-hud/spaceshiphudmenu.swf'; Target = 'Interface/spaceshiphudmenu.swf' }
          @{ Root = 'Scaleform'; Source = 'ship-hud/spaceshiphudmenu_lrg.swf'; Target = 'Interface/spaceshiphudmenu_lrg.swf' }
        )
      }
    )
  )
  [ModuleVariant]::new(
    'EXAMPLE',
    'Venworks Canvas Example',
    'Venworks-Canvas-Example.esm',
    'Venworks-Canvas-Example',
    'Venworks:CanvasExamples',
    (Join-Path $repositoryRoot 'Staging-Example'),
    'MODULE_VARIANT_EXAMPLE_PATH',
    @(
      @{
        Name = 'canvas-example'
        Kind = 'Flex'
        OutputSet = 'movies'
        ManifestPath = 'Scaleform/canvas/build/example.build.xml'
        Outputs = @(
          @{ OutputFile = 'CanvasExample.swf' }
        )
      }
    ),
    @(
      @{
        FileName = 'Venworks-Canvas-Example - Main.ba2'
        Format = 'General'
        Compression = 'None'
        MaxSizeMB = 2048
        IncludePapyrus = $true
        Assets = @(
          @{ Root = 'Scaleform'; Source = 'movies/CanvasExample.swf'; Target = 'Interface/VenworksCanvas/Consumers/venworks.canvas.example/normal.swf' }
          @{ Root = 'Scaleform'; Source = 'movies/CanvasExample.swf'; Target = 'Interface/VenworksCanvas/Consumers/venworks.canvas.example/large.swf' }
        )
      }
    )
  )
  [ModuleVariant]::new(
    'COMPONENTGALLERY',
    'Venworks Canvas Component Gallery',
    'Venworks-Canvas-ComponentGallery.esm',
    'Venworks-Canvas-ComponentGallery',
    'Venworks:CanvasComponentGallery',
    (Join-Path $repositoryRoot 'Staging-ComponentGallery'),
    'MODULE_VARIANT_COMPONENT_GALLERY_PATH',
    @(
      @{
        Name = 'canvas-component-gallery'
        Kind = 'Flex'
        OutputSet = 'movies'
        ManifestPath = 'Scaleform/canvas/build/component-gallery.build.xml'
        Outputs = @(
          @{ OutputFile = 'CanvasComponentGallery.swf' }
        )
      }
    ),
    @(
      @{
        FileName = 'Venworks-Canvas-ComponentGallery - Main.ba2'
        Format = 'General'
        Compression = 'None'
        MaxSizeMB = 2048
        IncludePapyrus = $true
        Assets = @(
          @{ Root = 'Scaleform'; Source = 'movies/CanvasComponentGallery.swf'; Target = 'Interface/VenworksCanvas/Consumers/venworks.canvas.component-gallery/normal.swf' }
          @{ Root = 'Scaleform'; Source = 'movies/CanvasComponentGallery.swf'; Target = 'Interface/VenworksCanvas/Consumers/venworks.canvas.component-gallery/large.swf' }
        )
      }
    )
  )
)

$Global:SharedConfigurationLoaded = $true
