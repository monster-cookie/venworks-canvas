<#
.SYNOPSIS
Builds every Scaleform artifact owned by the selected Canvas package variants.
.DESCRIPTION
Canvas movies use the configured Java, JPEXS, and Apache Flex tools. When CANVAS is selected, this command also applies the repository-owned Watch and Ship patches to current installed vanilla interface movies.
#>
[CmdletBinding()]
param(
  [string[]]$VariantKeys,

  [string]$JavaPath = (Join-Path $PSScriptRoot '..\.work\tools\java\bin\java.exe'),

  [string]$JpexsJarPath = (Join-Path $PSScriptRoot '..\.work\tools\jpexs\ffdec.jar'),

  [string]$FlexSdkPath = (Join-Path $PSScriptRoot '..\.work\tools\flex'),

  [string]$VanillaInterfacePath,

  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scaleform'),

  [string]$WorkDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scaleform-build'),

  [switch]$KeepWork
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')
. (Join-Path $PSScriptRoot 'sharedCanvasScaleform.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$canvasRoot = Join-Path $repositoryRoot 'Scaleform\canvas'
$canvasWorkRoot = Join-Path $repositoryRoot '.work\canvas'
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$buildPlayerHud = @($variants | Where-Object { $_.IncludesPlayerHud }).Count -gt 0
$buildShipHud = @($variants | Where-Object { $_.IncludesShipHud }).Count -gt 0
$buildHud = $buildPlayerHud -or $buildShipHud
if ($buildHud -and [string]::IsNullOrWhiteSpace($VanillaInterfacePath)) {
  throw 'VanillaInterfacePath is required when a selected variant builds Canvas-owned HUD patches.'
}

$resolvedJavaPath = Resolve-CanvasRequiredFile -Path $JavaPath -Description 'Java executable'
$resolvedJpexsPath = Resolve-CanvasRequiredFile -Path $JpexsJarPath -Description 'JPEXS JAR'
$resolvedFlexSdkPath = Resolve-CanvasRequiredDirectory -Path $FlexSdkPath -Description 'Apache Flex SDK'

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$resolvedWorkRoot = [System.IO.Path]::GetFullPath($WorkDirectory)
Assert-CanvasRemovalPath -Path $resolvedOutputDirectory -AllowedRoot $canvasWorkRoot
Assert-CanvasRemovalPath -Path $resolvedWorkRoot -AllowedRoot $canvasWorkRoot
if (Test-CanvasOverlappingPaths -Left $resolvedOutputDirectory -Right $resolvedWorkRoot) {
  throw 'Scaleform output and work directories cannot overlap.'
}
New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory, $resolvedWorkRoot | Out-Null
$resolvedWorkDirectory = Join-Path $resolvedWorkRoot ('build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $resolvedWorkDirectory | Out-Null

$movieCandidateDirectory = Join-Path $resolvedWorkDirectory 'movies-candidate'
$movieWorkDirectory = Join-Path $resolvedWorkDirectory 'movies-work'
New-Item -ItemType Directory -Path $movieCandidateDirectory, $movieWorkDirectory | Out-Null
$movieResults = [System.Collections.Generic.List[object]]::new()
foreach ($variant in $variants) {
  if ([string]::IsNullOrWhiteSpace($variant.ScaleformManifest)) {
    continue
  }
  $manifestPath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $canvasRoot $variant.ScaleformManifest) `
    -Description "Canvas manifest '$($variant.ScaleformManifest)'"
  Write-Host -ForegroundColor Green "Building $($variant.VariantKey) Canvas movie"
  $result = Invoke-CanvasMovieBuild `
    -ManifestPath $manifestPath `
    -OutputDirectory $movieCandidateDirectory `
    -WorkDirectory $movieWorkDirectory `
    -JavaPath $resolvedJavaPath `
    -JpexsJarPath $resolvedJpexsPath `
    -FlexSdkPath $resolvedFlexSdkPath `
    -KeepWork:$KeepWork
  if ($result.OutputFile -cne $variant.ScaleformOutput) {
    throw "Variant '$($variant.VariantKey)' emitted '$($result.OutputFile)' instead of '$($variant.ScaleformOutput)'."
  }
  $movieResults.Add($result)
}

$expectedMovieNames = @($movieResults | ForEach-Object { [string]$_.OutputFile })
Assert-CanvasExactNames `
  -Actual @(Get-ChildItem -LiteralPath $movieCandidateDirectory -File | ForEach-Object { $_.Name }) `
  -Expected $expectedMovieNames `
  -Description 'Selected Canvas movie candidate inventory'
$movieOutputDirectory = Join-Path $resolvedOutputDirectory 'movies'
New-Item -ItemType Directory -Force -Path $movieOutputDirectory | Out-Null
foreach ($movieName in $expectedMovieNames) {
  Publish-CanvasScaleformFile `
    -CandidatePath (Join-Path $movieCandidateDirectory $movieName) `
    -DestinationPath (Join-Path $movieOutputDirectory $movieName) `
    -AllowedRoot $canvasWorkRoot
}
foreach ($movieName in $expectedMovieNames) {
  [void](Assert-CanvasScaleformFile -Path (Join-Path $movieOutputDirectory $movieName) -Description "Published Canvas movie '$movieName'")
}

$vanillaMoviesPath = $null
if ($buildHud) {
  $resolvedVanillaPath = Resolve-CanvasRequiredDirectory -Path $VanillaInterfacePath -Description 'Installed vanilla interface path'
  $requiredVanillaMovies = @()
  if ($buildPlayerHud) {
    $requiredVanillaMovies += @('playerhudcomponents.swf', 'playerhudcomponents.gfx', 'playerhudcomponents_lrg.swf', 'playerhudcomponents_lrg.gfx')
  }
  if ($buildShipHud) {
    $requiredVanillaMovies += @('spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf')
  }
  $directMoviesPresent = @($requiredVanillaMovies | Where-Object { !(Test-Path -LiteralPath (Join-Path $resolvedVanillaPath $_) -PathType Leaf) }).Count -eq 0
  $nestedInterfacePath = Join-Path $resolvedVanillaPath 'Interface'
  $nestedMoviesPresent = (Test-Path -LiteralPath $nestedInterfacePath -PathType Container) -and
    @($requiredVanillaMovies | Where-Object { !(Test-Path -LiteralPath (Join-Path $nestedInterfacePath $_) -PathType Leaf) }).Count -eq 0
  if ($directMoviesPresent) {
    $vanillaMoviesPath = $resolvedVanillaPath
  }
  elseif ($nestedMoviesPresent) {
    $vanillaMoviesPath = $nestedInterfacePath
  }
  else {
    throw "Installed vanilla interface path does not contain the selected Canvas HUD inputs: $([string]::Join(', ', $requiredVanillaMovies))"
  }
}

if ($buildPlayerHud) {
  $expectedPlayerNames = @('playerhudcomponents.swf', 'playerhudcomponents.gfx', 'playerhudcomponents_lrg.swf', 'playerhudcomponents_lrg.gfx')
  $definition = Get-CanvasPlayerHudBuildDefinition -DefinitionPath (Join-Path $canvasRoot 'build\player-hud-watch.build.psd1')
  Assert-CanvasExactNames -Actual @($definition.Movies) -Expected $expectedPlayerNames -Description 'Player HUD Watch build definition'
  $playerCandidateDirectory = Join-Path $resolvedWorkDirectory 'player-hud-candidate'
  $playerWorkDirectory = Join-Path $resolvedWorkDirectory 'player-hud-work'
  New-Item -ItemType Directory -Path $playerCandidateDirectory, $playerWorkDirectory | Out-Null
  foreach ($movieName in $expectedPlayerNames) {
    [void](Invoke-CanvasPatchedMovieBuild `
      -InputPath (Join-Path $vanillaMoviesPath $movieName) `
      -OutputPath (Join-Path $playerCandidateDirectory $movieName) `
      -PatchPath $definition.PatchPath `
      -JavaPath $resolvedJavaPath `
      -JpexsJarPath $resolvedJpexsPath `
      -FlexSdkPath $resolvedFlexSdkPath `
      -WorkDirectory $playerWorkDirectory `
      -KeepWork:$KeepWork)
  }
  $playerOutputDirectory = Join-Path $resolvedOutputDirectory 'player-hud'
  Publish-CanvasValidatedHudOutputSet `
    -CandidateDirectory $playerCandidateDirectory `
    -DestinationDirectory $playerOutputDirectory `
    -WorkDirectory $resolvedWorkDirectory `
    -AllowedRoot $canvasWorkRoot `
    -ExpectedFiles $expectedPlayerNames `
    -Description 'Player HUD'
}

if ($buildShipHud) {
  $expectedShipNames = @('spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf')
  $manifestPaths = @(
    (Join-Path $canvasRoot 'build\spaceshiphudmenu.build.xml'),
    (Join-Path $canvasRoot 'build\spaceshiphudmenu-lrg.build.xml')
  )
  $shipDefinitions = @($manifestPaths | ForEach-Object { Get-CanvasPatchedMovieBuildDefinition -ManifestPath $_ })
  Assert-CanvasExactNames -Actual @($shipDefinitions.InputFile) -Expected $expectedShipNames -Description 'Ship HUD build input inventory'
  Assert-CanvasExactNames -Actual @($shipDefinitions.OutputFile) -Expected $expectedShipNames -Description 'Ship HUD build output inventory'
  $shipCandidateDirectory = Join-Path $resolvedWorkDirectory 'ship-hud-candidate'
  $shipWorkDirectory = Join-Path $resolvedWorkDirectory 'ship-hud-work'
  New-Item -ItemType Directory -Path $shipCandidateDirectory, $shipWorkDirectory | Out-Null
  foreach ($definition in $shipDefinitions) {
    [void](Invoke-CanvasPatchedMovieBuild `
      -InputPath (Join-Path $vanillaMoviesPath $definition.InputFile) `
      -OutputPath (Join-Path $shipCandidateDirectory $definition.OutputFile) `
      -PatchPath $definition.PatchPath `
      -JavaPath $resolvedJavaPath `
      -JpexsJarPath $resolvedJpexsPath `
      -FlexSdkPath $resolvedFlexSdkPath `
      -WorkDirectory $shipWorkDirectory `
      -KeepWork:$KeepWork)
  }
  $shipOutputDirectory = Join-Path $resolvedOutputDirectory 'ship-hud'
  Publish-CanvasValidatedHudOutputSet `
    -CandidateDirectory $shipCandidateDirectory `
    -DestinationDirectory $shipOutputDirectory `
    -WorkDirectory $resolvedWorkDirectory `
    -AllowedRoot $canvasWorkRoot `
    -ExpectedFiles $expectedShipNames `
    -Description 'Ship HUD'
}

if ($KeepWork) {
  Write-Host -ForegroundColor Yellow "Canvas Scaleform build files retained at $resolvedWorkDirectory"
}
elseif (Test-Path -LiteralPath $resolvedWorkDirectory -PathType Container) {
  Assert-CanvasRemovalPath -Path $resolvedWorkDirectory -AllowedRoot $canvasWorkRoot
  Remove-Item -LiteralPath $resolvedWorkDirectory -Recurse -Force
}

Write-Host -ForegroundColor Green "Built selected Scaleform artifacts for $([string]::Join(', ', @($variants.VariantKey))) at $resolvedOutputDirectory"
