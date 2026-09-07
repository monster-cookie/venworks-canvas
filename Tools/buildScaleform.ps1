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
$workDirectoryRoot = [System.IO.Path]::GetFullPath($WorkDirectory)
Assert-CanvasRemovalPath -Path $resolvedOutputDirectory -AllowedRoot $canvasWorkRoot
Assert-CanvasRemovalPath -Path $workDirectoryRoot -AllowedRoot $canvasWorkRoot
New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory, $workDirectoryRoot | Out-Null
$resolvedWorkDirectory = Join-Path $workDirectoryRoot ('build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $resolvedWorkDirectory | Out-Null
$env:APPDATA = Join-Path $repositoryRoot '.work\appdata'

$sharedMovieScript = Resolve-CanvasRequiredFile `
  -Path (Join-Path $resolvedVwHudRoot 'Tools\sharedScaleformMovies.ps1') `
  -Description 'Pinned VWHUD shared Scaleform movie helper used by the Canvas build'
. $sharedMovieScript
$toolchain = Get-CanvasScaleformToolchainEvidence `
  -RepositoryRoot $repositoryRoot `
  -VwHudRepositoryPath $resolvedVwHudRoot `
  -JavaPath $resolvedJavaPath `
  -JpexsJarPath $resolvedJpexsPath `
  -FlexSdkPath $resolvedFlexSdkPath `
  -Matrix $matrix

$movieOutputDirectory = Join-Path $resolvedOutputDirectory 'movies'
$movieWorkDirectory = Join-Path $resolvedWorkDirectory 'movies'
New-Item -ItemType Directory -Force -Path $movieOutputDirectory, $movieWorkDirectory | Out-Null
$existingMovieEvidence = $null
$movieEvidencePath = Join-Path $movieOutputDirectory 'build-evidence.json'
if (Test-Path -LiteralPath $movieEvidencePath -PathType Leaf) {
  try { $existingMovieEvidence = Get-Content -LiteralPath $movieEvidencePath -Raw | ConvertFrom-Json }
  catch { Write-Warning "Existing Canvas movie evidence could not be read and will not be retained: $($_.Exception.Message)" }
}
$retainedMovieRows = @(Get-CanvasValidRetainedMovieRows `
  -Evidence $existingMovieEvidence `
  -RepositoryRoot $repositoryRoot `
  -MoviesDirectory $movieOutputDirectory `
  -SelectedVariantKeys @($variants.VariantKey) `
  -Toolchain $toolchain)
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
  $movieResults.Add([pscustomobject]@{ VariantKey = [string]$variant.VariantKey; Result = $result })
}

$movieEvidence = [ordered]@{
  Schema = 'VWCANVAS_SCALEFORM_MOVIES/2'
  GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
  CanvasPipeline = 'VWCANVAS_OWNED_VWHUD_V2_DERIVED/1'
  Toolchain = $toolchain
  Movies = @($retainedMovieRows + @($movieResults | ForEach-Object {
    $result = $_.Result
    [ordered]@{
      VariantKey = [string]$_.VariantKey
      Name = $result.Name
      Role = $result.Role
      OutputFile = $result.OutputFile
      Sha256 = $result.Sha256
      Manifest = ([System.IO.Path]::GetRelativePath($canvasRoot, [string]$result.ManifestPath)).Replace('\', '/')
      ManifestSha256 = $result.ManifestSha256
      Source = ([System.IO.Path]::GetRelativePath($canvasRoot, [string]$result.SourcePath)).Replace('\', '/')
      SourceSha256 = $result.SourceSha256
      ClassInventory = @($result.ClassInventory)
      BuildPasses = $result.BuildPasses
    }
  }) | Sort-Object VariantKey)
}
Write-CanvasUtf8WithoutBom `
  -Path $movieEvidencePath `
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
  $playerInputs = @(
    (Get-CanvasEvidenceFileRow -Key 'Definition' -Path $definitionPath -DisplayPath 'Scaleform/canvas/build/player-hud-watch.build.psd1'),
    (Get-CanvasEvidenceFileRow -Key 'Patch' -Path $patchPath -DisplayPath ([System.IO.Path]::GetRelativePath($repositoryRoot, $patchPath))),
    (Get-CanvasEvidenceFileRow -Key 'Compiler' -Path $compileScript -DisplayPath 'Tools/compileScaleform.ps1')
  )
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
    $playerOutputs.Add([ordered]@{
      File = [string]$movie.File
      Role = 'WatchPresentationDisabled'
      VanillaSha256 = [string]$movie.VanillaSha256
      ExpectedSha256 = [string]$movie.OutputSha256
      Sha256 = $hash
    })
  }
  foreach ($hostMovie in @(Get-VwHudHostMovieEvidence -VwHudRepositoryPath $resolvedVwHudRoot -Matrix $matrix)) {
    $targetName = Split-Path -Leaf ([string]$hostMovie.Target)
    Copy-Item -LiteralPath (Join-Path $resolvedVwHudRoot ([string]$hostMovie.Source)) -Destination (Join-Path $playerOutputDirectory $targetName)
    $playerOutputs.Add([ordered]@{
      File = $targetName
      Role = 'PlayerHudHost'
      Source = [string]$hostMovie.Source
      SourceSha256 = [string]$hostMovie.Sha256
      Sha256 = [string]$hostMovie.Sha256
    })
  }
  $playerHudEvidence = [ordered]@{
    Schema = 'VWCANVAS_PLAYER_HUD_BUILD/2'
    PinnedOutputs = !$EstablishExpectedHashes
    VwHudRevision = [string]$matrix.VwHudFixture.Revision
    Inputs = @($playerInputs)
    Movies = @($playerOutputs | Sort-Object File)
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
  $shipInputs = [System.Collections.Generic.List[object]]::new()
  foreach ($manifestPath in $manifestPaths) {
    $manifestName = Split-Path -Leaf $manifestPath
    $shipInputs.Add((Get-CanvasEvidenceFileRow -Key "Manifest/$manifestName" -Path $manifestPath -DisplayPath "Scaleform/canvas/build/$manifestName"))
    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
    foreach ($attribute in @('vanillaHashFile', 'expectedHashFile')) {
      $hashName = [string]$manifest.scaleformBuild.$attribute
      $shipInputs.Add((Get-CanvasEvidenceFileRow -Key "Hash/$hashName" -Path (Join-Path (Split-Path $manifestPath -Parent) $hashName) -DisplayPath "Scaleform/canvas/build/$hashName"))
    }
  }
  $shipInputs.Add((Get-CanvasEvidenceFileRow -Key 'Patch' -Path (Join-Path $canvasRoot 'patches\spaceship-hud-auxiliary-loader.xml') -DisplayPath 'Scaleform/canvas/patches/spaceship-hud-auxiliary-loader.xml'))
  $shipInputs.Add((Get-CanvasEvidenceFileRow -Key 'Compiler' -Path $compileScript -DisplayPath ([string]$matrix.VwHudFixture.ShipCompilerFile)))
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
  $shipOutputs = @($manifestPaths | ForEach-Object {
    [xml]$manifest = Get-Content -LiteralPath $_ -Raw
    $outputName = [string]$manifest.scaleformBuild.outputFile
    $outputPath = Resolve-CanvasRequiredFile -Path (Join-Path $shipOutputDirectory $outputName) -Description "Patched Ship HUD movie '$outputName'"
    [ordered]@{
      File = $outputName
      Manifest = "Scaleform/canvas/build/$(Split-Path -Leaf $_)"
      VanillaSha256 = Get-CanvasPinnedHashFromFile -Path (Join-Path (Split-Path $_ -Parent) ([string]$manifest.scaleformBuild.vanillaHashFile))
      ExpectedSha256 = Get-CanvasPinnedHashFromFile -Path (Join-Path (Split-Path $_ -Parent) ([string]$manifest.scaleformBuild.expectedHashFile))
      Sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToUpperInvariant()
    }
  })
  $shipHudEvidence = [ordered]@{
    Schema = 'VWCANVAS_SHIP_HUD_BUILD/2'
    PinnedOutputs = !$EstablishExpectedHashes
    VwHudRevision = [string]$matrix.VwHudFixture.Revision
    Inputs = @($shipInputs)
    Movies = @($shipOutputs | Sort-Object File)
  }
  Write-CanvasUtf8WithoutBom -Path (Join-Path $shipOutputDirectory 'build-evidence.json') -Text (($shipHudEvidence | ConvertTo-Json -Depth 6) + "`n")
}

Assert-CanvasScaleformToolchainEvidence `
  -Actual $toolchain `
  -Expected (Get-CanvasScaleformToolchainEvidence -RepositoryRoot $repositoryRoot -VwHudRepositoryPath $resolvedVwHudRoot -JavaPath $resolvedJavaPath -JpexsJarPath $resolvedJpexsPath -FlexSdkPath $resolvedFlexSdkPath -Matrix $matrix)
Assert-CanvasMovieEvidence `
  -Evidence (Get-Content -LiteralPath $movieEvidencePath -Raw | ConvertFrom-Json) `
  -RepositoryRoot $repositoryRoot `
  -MoviesDirectory $movieOutputDirectory `
  -Variants $variants `
  -Toolchain $toolchain `
  -ValidateAllRows

if ($null -eq $playerHudEvidence) {
  $existingPlayerEvidencePath = Join-Path $resolvedOutputDirectory 'player-hud\build-evidence.json'
  if (Test-Path -LiteralPath $existingPlayerEvidencePath -PathType Leaf) {
    try {
      $existingPlayerEvidence = Get-Content -LiteralPath $existingPlayerEvidencePath -Raw | ConvertFrom-Json
      Assert-CanvasPlayerHudEvidence -Evidence $existingPlayerEvidence -RepositoryRoot $repositoryRoot -VwHudRepositoryPath $resolvedVwHudRoot -PlayerDirectory (Split-Path -Parent $existingPlayerEvidencePath) -Matrix $matrix
      $playerHudEvidence = $existingPlayerEvidence
    }
    catch { Write-Warning "Retained Player HUD evidence was omitted as stale: $($_.Exception.Message)" }
  }
}
if ($null -eq $shipHudEvidence) {
  $existingShipEvidencePath = Join-Path $resolvedOutputDirectory 'ship-hud\build-evidence.json'
  if (Test-Path -LiteralPath $existingShipEvidencePath -PathType Leaf) {
    try {
      $existingShipEvidence = Get-Content -LiteralPath $existingShipEvidencePath -Raw | ConvertFrom-Json
      Assert-CanvasShipHudEvidence -Evidence $existingShipEvidence -RepositoryRoot $repositoryRoot -VwHudRepositoryPath $resolvedVwHudRoot -ShipDirectory (Split-Path -Parent $existingShipEvidencePath) -Matrix $matrix
      $shipHudEvidence = $existingShipEvidence
    }
    catch { Write-Warning "Retained Ship HUD evidence was omitted as stale: $($_.Exception.Message)" }
  }
}

$buildEvidence = [ordered]@{
  Schema = 'VWCANVAS_SCALEFORM_BUILD/2'
  Variants = @($movieEvidence.Movies | ForEach-Object { [string]$_.VariantKey } | Sort-Object)
  VwHudRevision = [string]$matrix.VwHudFixture.Revision
  CanvasMoviesEvidenceSha256 = Get-CanvasFileSha256 -Path $movieEvidencePath
  PlayerHudEvidenceSha256 = if ($null -eq $playerHudEvidence) { $null } else { Get-CanvasFileSha256 -Path (Join-Path $resolvedOutputDirectory 'player-hud\build-evidence.json') }
  ShipHudEvidenceSha256 = if ($null -eq $shipHudEvidence) { $null } else { Get-CanvasFileSha256 -Path (Join-Path $resolvedOutputDirectory 'ship-hud\build-evidence.json') }
}
Write-CanvasUtf8WithoutBom -Path (Join-Path $resolvedOutputDirectory 'build-evidence.json') -Text (($buildEvidence | ConvertTo-Json -Depth 8) + "`n")

Assert-CanvasScaleformAggregateEvidence `
  -Evidence (Get-Content -LiteralPath (Join-Path $resolvedOutputDirectory 'build-evidence.json') -Raw | ConvertFrom-Json) `
  -ScaleformDirectory $resolvedOutputDirectory `
  -RequiredVariantKeys @($variants.VariantKey) `
  -RequirePlayerHud (@($variants | Where-Object { $_.IncludesPlayerHud }).Count -gt 0) `
  -RequireShipHud (@($variants | Where-Object { $_.IncludesShipHud }).Count -gt 0)

if (!$KeepWork -and (Test-Path -LiteralPath $resolvedWorkDirectory -PathType Container)) {
  Assert-CanvasRemovalPath -Path $resolvedWorkDirectory -AllowedRoot $canvasWorkRoot
  Remove-Item -LiteralPath $resolvedWorkDirectory -Recurse -Force
}

Write-Host -ForegroundColor Green "Built selected Scaleform artifacts for $([string]::Join(', ', @($variants.VariantKey))) and retained only current unselected evidence at $resolvedOutputDirectory"
