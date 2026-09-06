<#
.SYNOPSIS
Builds every Scaleform artifact owned by the selected Canvas package variants.
.DESCRIPTION
Canvas movies, the Watch-disabled Player HUD support movies, and the Ship HUD loader movies
share one variant-aware build entry point. All generated files remain beneath .work.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VwHudRepositoryPath,

  [string[]]$VariantKeys,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),

  [string]$JavaPath,

  [string]$JpexsJarPath,

  [string]$FlexSdkPath,

  [string]$VanillaInterfacePath = (Join-Path $PSScriptRoot '..\.work\canvas\vanilla-interface'),

  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scaleform'),

  [string]$WorkDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scaleform-build'),

  [switch]$KeepWork,

  [switch]$EstablishExpectedHashes
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$canvasRoot = Join-Path $repositoryRoot 'Scaleform\canvas'
$canvasWorkRoot = Join-Path $repositoryRoot '.work\canvas'
$matrix = Get-CanvasMatrix -RepositoryRoot $repositoryRoot
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$buildHostMovies = @($variants | Where-Object { $_.IncludesPlayerHud -or $_.IncludesShipHud }).Count -gt 0
$resolvedVwHudRoot = Assert-PinnedVwHudToolchainFixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix

if ([string]::IsNullOrWhiteSpace($JavaPath)) {
  $JavaPath = Join-Path $resolvedVwHudRoot '.work\tools\java\bin\java.exe'
}
if ([string]::IsNullOrWhiteSpace($JpexsJarPath)) {
  $JpexsJarPath = Join-Path $resolvedVwHudRoot '.work\tools\jpexs\ffdec.jar'
}
if ([string]::IsNullOrWhiteSpace($FlexSdkPath)) {
  $FlexSdkPath = Join-Path $resolvedVwHudRoot '.work\tools\flex'
}
$resolvedJavaPath = Resolve-CanvasRequiredFile -Path $JavaPath -Description 'Pinned Java runtime'
$resolvedJpexsPath = Resolve-CanvasRequiredFile -Path $JpexsJarPath -Description 'Pinned JPEXS jar'
$resolvedFlexSdkPath = Resolve-CanvasRequiredDirectory -Path $FlexSdkPath -Description 'Pinned Flex SDK'

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$resolvedWorkDirectory = [System.IO.Path]::GetFullPath($WorkDirectory)
foreach ($generatedDirectory in @($resolvedOutputDirectory, $resolvedWorkDirectory)) {
  if (Test-Path -LiteralPath $generatedDirectory -PathType Container) {
    Assert-CanvasRemovalPath -Path $generatedDirectory -AllowedRoot $canvasWorkRoot
    Remove-Item -LiteralPath $generatedDirectory -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
}
$env:APPDATA = Join-Path $repositoryRoot '.work\appdata'

$pipelineEvidence = [System.Collections.Generic.List[object]]::new()
foreach ($relativePath in @($matrix.VwHudFixture.AuxiliaryDerivedFiles)) {
  $pipelinePath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $resolvedVwHudRoot ([string]$relativePath)) `
    -Description "Pinned VWHUD toolchain file '$relativePath'"
  $pipelineEvidence.Add([ordered]@{
    Path = [string]$relativePath
    Sha256 = (Get-FileHash -LiteralPath $pipelinePath -Algorithm SHA256).Hash.ToUpperInvariant()
  })
}
$sharedMovieScript = Resolve-CanvasRequiredFile `
  -Path (Join-Path $resolvedVwHudRoot 'Tools\sharedScaleformMovies.ps1') `
  -Description 'Pinned VWHUD shared Scaleform movie helper used by the Canvas build'
. $sharedMovieScript

$movieOutputDirectory = Join-Path $resolvedOutputDirectory 'movies'
$movieWorkDirectory = Join-Path $resolvedWorkDirectory 'movies'
New-Item -ItemType Directory -Force -Path $movieOutputDirectory, $movieWorkDirectory | Out-Null
$movieResults = [System.Collections.Generic.List[object]]::new()
foreach ($variant in $variants) {
  if ([string]::IsNullOrWhiteSpace($variant.ScaleformManifest)) {
    continue
  }
  $manifestPath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $canvasRoot $variant.ScaleformManifest) `
    -Description "Canvas manifest '$($variant.ScaleformManifest)'"
  Write-Host -ForegroundColor Green "Building $($variant.VariantKey) through the VWHUD-v2-derived movie pipeline"
  $result = Invoke-CanvasMovieBuild `
    -ManifestPath $manifestPath `
    -OutputDirectory $movieOutputDirectory `
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

$movieEvidence = [ordered]@{
  Schema = 'VWCANVAS_SCALEFORM_MOVIES/1'
  GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
  Variants = @($variants.VariantKey)
  CanvasPipeline = 'VWCANVAS_OWNED_VWHUD_V2_DERIVED/1'
  VwHudRevision = [string]$matrix.VwHudFixture.Revision
  VwHudDerivedHelpers = @($pipelineEvidence)
  Movies = @($movieResults | ForEach-Object {
    [ordered]@{
      Name = $_.Name
      Role = $_.Role
      OutputFile = $_.OutputFile
      Sha256 = $_.Sha256
      Manifest = ([System.IO.Path]::GetRelativePath($canvasRoot, [string]$_.ManifestPath)).Replace('\', '/')
      ManifestSha256 = $_.ManifestSha256
      Source = ([System.IO.Path]::GetRelativePath($canvasRoot, [string]$_.SourcePath)).Replace('\', '/')
      SourceSha256 = $_.SourceSha256
      ClassInventory = @($_.ClassInventory)
      BuildPasses = $_.BuildPasses
    }
  })
}
Write-CanvasUtf8WithoutBom `
  -Path (Join-Path $movieOutputDirectory 'build-evidence.json') `
  -Text (($movieEvidence | ConvertTo-Json -Depth 8) + "`n")

if ($buildHostMovies) {
  Import-CanvasEnvironment -Path $EnvironmentPath
  $resolvedVanillaPath = [System.IO.Path]::GetFullPath($VanillaInterfacePath)
  $vanillaMoviesPath = Join-Path $resolvedVanillaPath 'Interface'
  $requiredVanillaMovies = @(
    'playerhudcomponents.swf',
    'playerhudcomponents.gfx',
    'playerhudcomponents_lrg.swf',
    'playerhudcomponents_lrg.gfx',
    'spaceshiphudmenu.swf',
    'spaceshiphudmenu_lrg.swf'
  )
  $missingVanillaMovie = @($requiredVanillaMovies | Where-Object {
    !(Test-Path -LiteralPath (Join-Path $vanillaMoviesPath $_) -PathType Leaf)
  }).Count -gt 0
  if ($missingVanillaMovie) {
    foreach ($requiredName in @('TOOL_PATH_ARCHIVER', 'STEAM_DATA_FOLDER')) {
      $value = [Environment]::GetEnvironmentVariable($requiredName, 'Process')
      if ([string]::IsNullOrWhiteSpace($value)) {
        throw "$requiredName must be configured in $EnvironmentPath to extract vanilla interface movies."
      }
    }
    $archive2Path = Resolve-CanvasExecutable `
      -Path $env:TOOL_PATH_ARCHIVER `
      -FileName 'Archive2.exe' `
      -Description 'Archive2 executable'
    $interfaceArchive = Resolve-CanvasRequiredFile `
      -Path (Join-Path $env:STEAM_DATA_FOLDER 'Starfield - Interface.ba2') `
      -Description 'Starfield vanilla interface archive'
    if (Test-Path -LiteralPath $resolvedVanillaPath -PathType Container) {
      Assert-CanvasRemovalPath -Path $resolvedVanillaPath -AllowedRoot $canvasWorkRoot
      Remove-Item -LiteralPath $resolvedVanillaPath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $resolvedVanillaPath | Out-Null
    & $archive2Path $interfaceArchive "-extract=$resolvedVanillaPath" -quiet
    if ($LASTEXITCODE -ne 0) {
      throw "Archive2 failed to extract the vanilla interface archive with exit code $LASTEXITCODE."
    }
  }
  foreach ($movieName in $requiredVanillaMovies) {
    [void](Resolve-CanvasRequiredFile -Path (Join-Path $vanillaMoviesPath $movieName) -Description "Vanilla interface movie '$movieName'")
  }
}

$playerHudEvidence = $null
if (@($variants | Where-Object { $_.IncludesPlayerHud }).Count -gt 0) {
  $playerOutputDirectory = Join-Path $resolvedOutputDirectory 'player-hud'
  New-Item -ItemType Directory -Force -Path $playerOutputDirectory | Out-Null
  $definitionPath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $canvasRoot 'build\player-hud-watch.build.psd1') `
    -Description 'Player HUD Watch build definition'
  $definition = Import-PowerShellDataFile -LiteralPath $definitionPath
  $patchPath = Resolve-CanvasRequiredFile `
    -Path ([System.IO.Path]::GetFullPath((Join-Path (Split-Path $definitionPath -Parent) $definition.Patch))) `
    -Description 'Player HUD Watch patch'
  $compileScript = Resolve-CanvasRequiredFile `
    -Path (Join-Path $resolvedVwHudRoot 'Tools\compileScaleform.ps1') `
    -Description 'Pinned VWHUD Scaleform compiler'
  $expectedNames = @('playerhudcomponents.swf', 'playerhudcomponents.gfx', 'playerhudcomponents_lrg.swf', 'playerhudcomponents_lrg.gfx')
  if (@($definition.Movies).Count -ne 4 -or
      @($definition.Movies.File | Sort-Object -Unique).Count -ne 4 -or
      @($definition.Movies | Where-Object { $_.File -cnotin $expectedNames }).Count -ne 0) {
    throw 'Player HUD Watch build definition must contain exactly the four normal/large SWF/GFX variants.'
  }
  $playerInputs = @(@($definitionPath, $patchPath, $compileScript) | ForEach-Object {
    [ordered]@{ Path = $_; Sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToUpperInvariant() }
  })
  foreach ($movie in $definition.Movies) {
    $inputPath = Join-Path $vanillaMoviesPath $movie.File
    if ((Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $movie.VanillaSha256) {
      throw "Vanilla Player HUD input hash mismatch: $($movie.File)"
    }
    if (!$EstablishExpectedHashes -and $movie.OutputSha256 -cnotmatch '^[0-9A-F]{64}$') {
      throw "A reviewed output hash must be pinned before building $($movie.File)."
    }
  }
  $playerScratch = Join-Path $resolvedWorkDirectory 'player-hud'
  New-Item -ItemType Directory -Force -Path $playerScratch | Out-Null
  $manifests = [System.Collections.Generic.List[string]]::new()
  foreach ($movie in $definition.Movies) {
    $name = [string]$movie.File
    $manifest = Join-Path $playerScratch ($name + '.xml')
    $hash = if ($EstablishExpectedHashes) { '0' * 64 } else { $movie.OutputSha256 }
    Write-CanvasUtf8WithoutBom -Path (Join-Path $playerScratch ($name + '.vanilla.sha256')) -Text ($movie.VanillaSha256 + "  $name`n")
    Write-CanvasUtf8WithoutBom -Path (Join-Path $playerScratch ($name + '.expected.sha256')) -Text ($hash + "  $name`n")
    $escapedPatch = [System.Security.SecurityElement]::Escape([System.IO.Path]::GetRelativePath($playerScratch, $patchPath))
    $xml = "<scaleformBuild name=`"watch-$name`" mode=`"auxiliary-bootstrap`" inputFile=`"$name`" outputFile=`"$name`" vanillaHashFile=`"$name.vanilla.sha256`" expectedHashFile=`"$name.expected.sha256`"><actionScriptPatches><patch path=`"$escapedPatch`" /></actionScriptPatches></scaleformBuild>"
    Write-CanvasUtf8WithoutBom -Path $manifest -Text $xml
    $manifests.Add($manifest)
  }
  foreach ($pass in @(1, 2)) {
    & $compileScript `
      -JavaPath $resolvedJavaPath `
      -JpexsJarPath $resolvedJpexsPath `
      -VanillaInterfacePath $vanillaMoviesPath `
      -OutputDirectory (Join-Path $playerScratch "pass-$pass") `
      -WorkDirectory (Join-Path $playerScratch "work-$pass") `
      -ManifestPath @($manifests.ToArray()) `
      -SkipOverrides `
      -KeepWork `
      -UpdateExpectedHashes:($EstablishExpectedHashes -and $pass -eq 1)
    if ($LASTEXITCODE -ne 0) {
      throw "Player HUD Watch build pass $pass failed with exit code $LASTEXITCODE."
    }
  }
  $playerOutputs = [System.Collections.Generic.List[object]]::new()
  foreach ($movie in $definition.Movies) {
    $first = Join-Path $playerScratch ('pass-1\' + $movie.File)
    $second = Join-Path $playerScratch ('pass-2\' + $movie.File)
    $hash = (Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($hash -cne (Get-FileHash -LiteralPath $second -Algorithm SHA256).Hash.ToUpperInvariant()) {
      throw "Non-deterministic Player HUD Watch output: $($movie.File)"
    }
    Copy-Item -LiteralPath $second -Destination (Join-Path $playerOutputDirectory $movie.File)
    $playerOutputs.Add([ordered]@{ File = [string]$movie.File; Role = 'WatchPresentationDisabled'; Sha256 = $hash })
  }
  foreach ($hostMovie in @(Get-VwHudHostMovieEvidence -VwHudRepositoryPath $resolvedVwHudRoot -Matrix $matrix)) {
    $targetName = Split-Path -Leaf ([string]$hostMovie.Target)
    Copy-Item -LiteralPath (Join-Path $resolvedVwHudRoot ([string]$hostMovie.Source)) -Destination (Join-Path $playerOutputDirectory $targetName)
    $playerOutputs.Add([ordered]@{ File = $targetName; Role = 'PlayerHudHost'; Sha256 = [string]$hostMovie.Sha256 })
  }
  $playerHudEvidence = [ordered]@{
    Schema = 'VWCANVAS_PLAYER_HUD_BUILD/1'
    PinnedOutputs = !$EstablishExpectedHashes
    VwHudRevision = [string]$matrix.VwHudFixture.Revision
    DefinitionSha256 = $playerInputs[0].Sha256
    PatchSha256 = $playerInputs[1].Sha256
    CompilerSha256 = $playerInputs[2].Sha256
    Movies = @($playerOutputs)
  }
  Write-CanvasUtf8WithoutBom -Path (Join-Path $playerOutputDirectory 'build-evidence.json') -Text (($playerHudEvidence | ConvertTo-Json -Depth 5) + "`n")
}

$shipHudEvidence = $null
if (@($variants | Where-Object { $_.IncludesShipHud }).Count -gt 0) {
  $shipOutputDirectory = Join-Path $resolvedOutputDirectory 'ship-hud'
  $shipWorkDirectory = Join-Path $resolvedWorkDirectory 'ship-hud'
  New-Item -ItemType Directory -Force -Path $shipOutputDirectory, $shipWorkDirectory | Out-Null
  $compileScript = Resolve-CanvasRequiredFile `
    -Path (Join-Path $resolvedVwHudRoot 'Tools\compileScaleform.ps1') `
    -Description 'Pinned VWHUD Scaleform compiler invoked by the Canvas Ship HUD build'
  $manifestPaths = @(
    (Join-Path $canvasRoot 'build\spaceshiphudmenu.build.xml'),
    (Join-Path $canvasRoot 'build\spaceshiphudmenu-lrg.build.xml')
  )
  $shipInputPaths = @($manifestPaths) + @((Join-Path $canvasRoot 'patches\spaceship-hud-auxiliary-loader.xml'))
  $shipInputs = @($shipInputPaths | ForEach-Object {
    $inputPath = Resolve-CanvasRequiredFile -Path $_ -Description 'Ship HUD build input'
    [ordered]@{
      Path = ([System.IO.Path]::GetRelativePath($repositoryRoot, $inputPath)).Replace('\', '/')
      Sha256 = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToUpperInvariant()
    }
  })
  $compilerSha256 = (Get-FileHash -LiteralPath $compileScript -Algorithm SHA256).Hash.ToUpperInvariant()
  & $compileScript `
    -JavaPath $resolvedJavaPath `
    -JpexsJarPath $resolvedJpexsPath `
    -VanillaInterfacePath $vanillaMoviesPath `
    -OutputDirectory $shipOutputDirectory `
    -WorkDirectory $shipWorkDirectory `
    -ManifestPath $manifestPaths `
    -SkipOverrides `
    -UpdateExpectedHashes:$EstablishExpectedHashes `
    -KeepWork:$KeepWork
  if ($LASTEXITCODE -ne 0) {
    throw "VWHUD Ship HUD build failed with exit code $LASTEXITCODE."
  }
  $shipOutputs = @(@('spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf') | ForEach-Object {
    $outputPath = Resolve-CanvasRequiredFile -Path (Join-Path $shipOutputDirectory $_) -Description "Patched Ship HUD movie '$_'"
    [ordered]@{ File = $_; Sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToUpperInvariant() }
  })
  $shipHudEvidence = [ordered]@{
    Schema = 'VWCANVAS_SHIP_HUD_BUILD/1'
    VwHudRevision = [string]$matrix.VwHudFixture.Revision
    VwHudCompiler = [ordered]@{ Path = [string]$matrix.VwHudFixture.ShipCompilerFile; Sha256 = $compilerSha256 }
    Inputs = $shipInputs
    Movies = $shipOutputs
  }
  Write-CanvasUtf8WithoutBom -Path (Join-Path $shipOutputDirectory 'build-evidence.json') -Text (($shipHudEvidence | ConvertTo-Json -Depth 6) + "`n")
}

foreach ($pipelineFile in @($pipelineEvidence)) {
  $pipelinePath = Resolve-CanvasRequiredFile -Path (Join-Path $resolvedVwHudRoot ([string]$pipelineFile.Path)) -Description "Pinned VWHUD toolchain file '$($pipelineFile.Path)'"
  if ((Get-FileHash -LiteralPath $pipelinePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$pipelineFile.Sha256) {
    throw "Pinned VWHUD toolchain file '$($pipelineFile.Path)' changed during the complete Scaleform build."
  }
}

$buildEvidence = [ordered]@{
  Schema = 'VWCANVAS_SCALEFORM_BUILD/1'
  Variants = @($variants.VariantKey)
  VwHudRevision = [string]$matrix.VwHudFixture.Revision
  CanvasMovies = @($movieEvidence.Movies)
  PlayerHudBuilt = $null -ne $playerHudEvidence
  ShipHudBuilt = $null -ne $shipHudEvidence
}
Write-CanvasUtf8WithoutBom -Path (Join-Path $resolvedOutputDirectory 'build-evidence.json') -Text (($buildEvidence | ConvertTo-Json -Depth 8) + "`n")

Write-Host -ForegroundColor Green "Built Scaleform artifacts for $([string]::Join(', ', @($variants.VariantKey))) at $resolvedOutputDirectory"
