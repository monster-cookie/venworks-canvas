<#
.SYNOPSIS
Verifies Canvas production sources and, when requested, their generated artifacts and packages.
#>
[CmdletBinding()]
param(
  [switch]$SourceOnly,

  [switch]$ArtifactsOnly,

  [Alias('Profile')]
  [string]$BuildProfile = 'Production',

  [string[]]$VariantKeys,

  [string]$VwHudRepositoryPath,

  [string]$VenworksCoreRepositoryPath,

  [string]$ScaleformDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scaleform'),

  [string]$PluginsDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\plugins'),

  [string]$ScriptsDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scripts')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

function Assert-ExactFileInventory {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string[]]$Expected,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $actual = @(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {
    [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/')
  } | Sort-Object)
  $wanted = @($Expected | ForEach-Object { $_.Replace('\', '/') } | Sort-Object)
  if ($actual.Count -ne $wanted.Count -or [string]::Join("`n", $actual) -cne [string]::Join("`n", $wanted)) {
    throw "$Description inventory differs. Expected $([string]::Join(', ', $wanted)); found $([string]::Join(', ', $actual))."
  }
}

function Assert-EvidenceHash {
  param(
    [Parameter(Mandatory = $true)][object[]]$Rows,
    [Parameter(Mandatory = $true)][string]$NameProperty,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $matchingRows = @($Rows | Where-Object { [string]$_.$NameProperty -ceq $Name })
  $actualHash = Get-CanvasFileSha256 -Path $Path
  if ($matchingRows.Count -ne 1 -or [string]$matchingRows[0].Sha256 -cne $actualHash) {
    throw "$Description evidence does not match '$Name'."
  }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$matrix = Get-CanvasMatrix -RepositoryRoot $repositoryRoot
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$allVariants = @(Get-ModuleVariants)
$resolvedProfile = Resolve-CanvasProfile -Matrix $matrix -BuildProfile $BuildProfile

$retiredInvestigationTerm = 'pro' + 'be'
$retiredExplorationTerm = 'sp' + 'ike'
$retiredCanvasTerm = 'Canvas' + 'Discovery'
$retiredConsumerTerm = 'Consumer' + 'Discovery'
$retiredUpdatedTerm = 'Updated' + 'Example'
$retiredMigrationTerm = 'Example' + 'Update' + 'Migration'
$forbiddenPattern = '(?i)\b(?:' + [string]::Join('|', @(
  $retiredInvestigationTerm,
  $retiredExplorationTerm,
  $retiredCanvasTerm,
  $retiredConsumerTerm,
  $retiredUpdatedTerm,
  $retiredMigrationTerm
)) + ')\b'
$sourceRoots = @(
  (Join-Path $repositoryRoot 'Tools'),
  (Join-Path $repositoryRoot 'Papyrus'),
  (Join-Path $repositoryRoot 'Scaleform'),
  (Join-Path $repositoryRoot 'Spriggit'),
  (Join-Path $repositoryRoot '.github')
)
$sourceFiles = @($sourceRoots | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object {
  Get-ChildItem -LiteralPath $_ -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psc', '.as', '.xml', '.psd1', '.json', '.yaml', '.yml') }
})
foreach ($topLevelFile in @('README.md', 'CHANGELOG.md')) {
  $path = Join-Path $repositoryRoot $topLevelFile
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    $sourceFiles += Get-Item -LiteralPath $path
  }
}
$forbiddenHits = @($sourceFiles | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match $forbiddenPattern })
if ($forbiddenHits.Count -ne 0) {
  throw "Retired implementation terminology remains in: $([string]::Join(', ', @($forbiddenHits.FullName)))."
}

foreach ($retiredPath in @(
  "Tools\compile${retiredConsumerTerm}Scripts.ps1",
  "Tools\build${retiredConsumerTerm}WatchMovies.ps1",
  "Tools\build${retiredConsumerTerm}ShipMovies.ps1",
  "Tools\stage${retiredConsumerTerm}$($retiredInvestigationTerm.Substring(0, 1).ToUpperInvariant())$($retiredInvestigationTerm.Substring(1)).ps1",
  "Tools\dump${retiredConsumerTerm}PluginsToYaml.ps1",
  "Papyrus\Venworks\Canvas\$($retiredInvestigationTerm.Substring(0, 1).ToUpperInvariant())$($retiredInvestigationTerm.Substring(1))s",
  "Scaleform\$($retiredInvestigationTerm)s",
  "Spriggit\$retiredConsumerTerm"
)) {
  if (Test-Path -LiteralPath (Join-Path $repositoryRoot $retiredPath)) {
    throw "Retired path still exists: $retiredPath"
  }
}
foreach ($entryPoint in @('compileScripts.ps1', 'buildScaleform.ps1', 'createPackages.ps1')) {
  [void](Resolve-CanvasRequiredFile -Path (Join-Path $PSScriptRoot $entryPoint) -Description "Production build entry point '$entryPoint'")
}

$profileKeys = @($matrix.Profiles.Key | Sort-Object)
if ([string]::Join("`n", $profileKeys) -cne [string]::Join("`n", @('Faults', 'Production'))) {
  throw 'Canvas must define exactly the Production and Faults profiles.'
}
foreach ($profileDefinition in @($matrix.Profiles)) {
  foreach ($variant in $allVariants) {
    $hash = [string]$profileDefinition.PluginSha256[$variant.VariantKey]
    if ($hash -cnotmatch '^[0-9A-F]{64}$') {
      throw "Profile '$($profileDefinition.Key)' lacks a pinned hash for '$($variant.VariantKey)'."
    }
  }
  if (@($profileDefinition.PluginSha256.Keys).Count -ne $allVariants.Count) {
    throw "Profile '$($profileDefinition.Key)' contains an unexpected plugin hash key."
  }
}
foreach ($variant in $allVariants) {
  foreach ($relativeSource in @($variant.PapyrusScripts)) {
    [void](Resolve-CanvasRequiredFile -Path (Join-Path $repositoryRoot "Papyrus\$relativeSource") -Description "Papyrus source '$relativeSource'")
  }
  $manifestPath = Resolve-CanvasRequiredFile -Path (Join-Path $repositoryRoot "Scaleform\canvas\$($variant.ScaleformManifest)") -Description "Scaleform manifest '$($variant.ScaleformManifest)'"
  $definition = Get-CanvasBuildDefinition -ManifestPath $manifestPath
  if ([string]$definition.OutputFile -cne [string]$variant.ScaleformOutput) {
    throw "Variant '$($variant.VariantKey)' manifest output differs from sharedConfig.ps1."
  }
}

foreach ($sourceContractTest in @(
  'testConsole.ps1',
  'testGuards.ps1',
  'testPackaging.ps1',
  'testUiLoad.ps1',
  'testUiReceive.ps1',
  'testUuid.ps1'
)) {
  & (Resolve-CanvasRequiredFile -Path (Join-Path $PSScriptRoot $sourceContractTest) -Description "Source contract test '$sourceContractTest'")
}

if ($SourceOnly) {
  Write-Host -ForegroundColor Green 'Verified Canvas production source identities, variant definitions, profiles, and build entry points.'
  return
}

if ([string]::IsNullOrWhiteSpace($VwHudRepositoryPath) -or [string]::IsNullOrWhiteSpace($VenworksCoreRepositoryPath)) {
  throw 'Artifact verification requires VwHudRepositoryPath and VenworksCoreRepositoryPath.'
}
[void](Assert-PinnedVwHudToolchainFixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix)
[void](Assert-PinnedVenworksCoreFixture -VenworksCoreRepositoryPath $VenworksCoreRepositoryPath -Matrix $matrix)
$resolvedPluginsDirectory = Resolve-CanvasRequiredDirectory -Path $PluginsDirectory -Description 'Generated plugin directory'
$resolvedScriptsDirectory = Resolve-CanvasRequiredDirectory -Path $ScriptsDirectory -Description 'Compiled Papyrus directory'
$resolvedScaleformDirectory = Resolve-CanvasRequiredDirectory -Path $ScaleformDirectory -Description 'Built Scaleform directory'

$pluginEvidencePath = Resolve-CanvasRequiredFile -Path (Join-Path $resolvedPluginsDirectory 'generation-evidence.json') -Description 'Plugin generation evidence'
$pluginEvidence = Get-Content -LiteralPath $pluginEvidencePath -Raw | ConvertFrom-Json
if ([string]$pluginEvidence.Schema -cne 'VWCANVAS_PLUGIN_SET/1' -or
    [string]$pluginEvidence.Profile -cne [string]$resolvedProfile.Key -or
    $pluginEvidence.BinaryReadback -ne $true -or
    @($pluginEvidence.Plugins).Count -ne $allVariants.Count) {
  throw 'Plugin generation evidence does not match the selected profile and variant inventory.'
}
Assert-ExactFileInventory -Root $resolvedPluginsDirectory -Expected (@('generation-evidence.json') + @($allVariants | ForEach-Object { "$($_.PackageBaseName).esm" })) -Description 'Generated plugin output'
foreach ($variant in $allVariants) {
  $fileName = "$($variant.PackageBaseName).esm"
  $pluginPath = Resolve-CanvasRequiredFile -Path (Join-Path $resolvedPluginsDirectory $fileName) -Description "Generated plugin '$fileName'"
  Assert-CanvasArtifactHeader -Path $pluginPath
  Assert-EvidenceHash -Rows @($pluginEvidence.Plugins) -NameProperty 'FileName' -Name $fileName -Path $pluginPath -Description 'Plugin generation'
  if ((Get-CanvasFileSha256 -Path $pluginPath) -cne [string]$resolvedProfile.PluginSha256[$variant.VariantKey]) {
    throw "Generated plugin '$fileName' differs from the '$($resolvedProfile.Key)' profile pin."
  }
}

$compileEvidencePath = Resolve-CanvasRequiredFile -Path (Join-Path $resolvedScriptsDirectory 'compile-evidence.json') -Description 'Papyrus compile evidence'
$compileEvidence = Get-Content -LiteralPath $compileEvidencePath -Raw | ConvertFrom-Json
if ([string]$compileEvidence.Schema -cne 'VWCANVAS_SCRIPTS/1' -or
    [string]$compileEvidence.VenworksCoreRevision -cne [string]$matrix.VenworksCoreFixture.Revision) {
  throw 'Papyrus compile evidence does not match the production schema or pinned Core revision.'
}
$expectedSources = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($variant in $variants) {
  foreach ($source in @($variant.PapyrusScripts)) {
    [void]$expectedSources.Add($source.Replace('\', '/'))
  }
}
if (@($compileEvidence.Scripts).Count -ne $expectedSources.Count) {
  throw 'Papyrus compile evidence does not contain the selected variants exact source inventory.'
}
foreach ($row in @($compileEvidence.Scripts)) {
  if (!$expectedSources.Contains([string]$row.Source)) {
    throw "Papyrus compile evidence contains an unexpected source '$($row.Source)'."
  }
  $sourcePath = Join-Path $repositoryRoot ('Papyrus\' + ([string]$row.Source).Replace('/', '\'))
  $outputPath = Join-Path $resolvedScriptsDirectory ([string]$row.Output)
  if ((Get-CanvasFileSha256 -Path $sourcePath) -cne [string]$row.SourceSha256 -or
      (Get-CanvasFileSha256 -Path $outputPath) -cne [string]$row.Sha256) {
    throw "Papyrus source or output drifted for '$($row.Source)'."
  }
}

$scaleformEvidence = Get-Content -LiteralPath (Resolve-CanvasRequiredFile -Path (Join-Path $resolvedScaleformDirectory 'build-evidence.json') -Description 'Scaleform build evidence') -Raw | ConvertFrom-Json
if ([string]$scaleformEvidence.Schema -cne 'VWCANVAS_SCALEFORM_BUILD/1' -or
    [string]$scaleformEvidence.VwHudRevision -cne [string]$matrix.VwHudFixture.Revision) {
  throw 'Scaleform build evidence does not match the production schema or pinned VWHUD revision.'
}
$movieDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'movies') -Description 'Canvas movie output'
$movieEvidence = Get-Content -LiteralPath (Join-Path $movieDirectory 'build-evidence.json') -Raw | ConvertFrom-Json
if ([string]$movieEvidence.Schema -cne 'VWCANVAS_SCALEFORM_MOVIES/1') {
  throw 'Canvas movie evidence uses an unexpected schema.'
}
foreach ($variant in $variants) {
  $moviePath = Join-Path $movieDirectory $variant.ScaleformOutput
  Assert-EvidenceHash -Rows @($movieEvidence.Movies) -NameProperty 'OutputFile' -Name $variant.ScaleformOutput -Path $moviePath -Description 'Canvas movie build'
}
if (@($variants | Where-Object { $_.IncludesPlayerHud }).Count -gt 0) {
  $playerDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'player-hud') -Description 'Player HUD output'
  $playerEvidence = Get-Content -LiteralPath (Join-Path $playerDirectory 'build-evidence.json') -Raw | ConvertFrom-Json
  if ([string]$playerEvidence.Schema -cne 'VWCANVAS_PLAYER_HUD_BUILD/1' -or $playerEvidence.PinnedOutputs -ne $true -or @($playerEvidence.Movies).Count -ne 8) {
    throw 'Player HUD evidence does not contain the exact pinned eight-movie set.'
  }
  foreach ($movie in @($playerEvidence.Movies)) {
    Assert-EvidenceHash -Rows @($playerEvidence.Movies) -NameProperty 'File' -Name ([string]$movie.File) -Path (Join-Path $playerDirectory ([string]$movie.File)) -Description 'Player HUD build'
  }
}
if (@($variants | Where-Object { $_.IncludesShipHud }).Count -gt 0) {
  $shipDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'ship-hud') -Description 'Ship HUD output'
  $shipEvidence = Get-Content -LiteralPath (Join-Path $shipDirectory 'build-evidence.json') -Raw | ConvertFrom-Json
  if ([string]$shipEvidence.Schema -cne 'VWCANVAS_SHIP_HUD_BUILD/1' -or @($shipEvidence.Movies).Count -ne 2) {
    throw 'Ship HUD evidence does not contain the exact two-movie set.'
  }
  foreach ($movie in @($shipEvidence.Movies)) {
    Assert-EvidenceHash -Rows @($shipEvidence.Movies) -NameProperty 'File' -Name ([string]$movie.File) -Path (Join-Path $shipDirectory ([string]$movie.File)) -Description 'Ship HUD build'
  }
}

$spriggitProfilePath = Resolve-CanvasRequiredDirectory -Path (Join-Path $repositoryRoot "Spriggit\$($resolvedProfile.Key)") -Description "Spriggit profile '$($resolvedProfile.Key)'"
$spriggitEvidence = Get-Content -LiteralPath (Resolve-CanvasRequiredFile -Path (Join-Path $spriggitProfilePath 'dump-evidence.json') -Description 'Spriggit dump evidence') -Raw | ConvertFrom-Json
if ([string]$spriggitEvidence.Schema -cne 'VWCANVAS_SPRIGGIT_DUMP/1' -or
    [string]$spriggitEvidence.Profile -cne [string]$resolvedProfile.Key -or
    @($spriggitEvidence.Plugins).Count -ne $allVariants.Count) {
  throw 'Spriggit dump evidence does not match the selected profile and variant inventory.'
}
foreach ($variant in $allVariants) {
  $fileName = "$($variant.PackageBaseName).esm"
  $row = @($spriggitEvidence.Plugins | Where-Object { [string]$_.Key -ceq [string]$variant.VariantKey })
  $yamlPath = Resolve-CanvasRequiredDirectory -Path (Join-Path $spriggitProfilePath $fileName) -Description "Spriggit YAML '$fileName'"
  if ($row.Count -ne 1 -or [string]$row[0].EsmSha256 -cne [string]$resolvedProfile.PluginSha256[$variant.VariantKey] -or [string]$row[0].YamlSha256 -cne (Get-CanvasDirectoryDigest -Path $yamlPath)) {
    throw "Spriggit YAML '$fileName' differs from its evidence."
  }
}

if ($ArtifactsOnly) {
  Write-Host -ForegroundColor Green "Verified source-bound Canvas artifacts for profile '$($resolvedProfile.Key)'."
  return
}

$packageEvidencePath = Resolve-CanvasRequiredFile -Path (Join-Path $repositoryRoot '.work\canvas\staging-evidence.json') -Description 'Package evidence'
$packageEvidence = Get-Content -LiteralPath $packageEvidencePath -Raw | ConvertFrom-Json
if ([string]$packageEvidence.Schema -cne 'VWCANVAS_PACKAGES/1' -or
    [string]$packageEvidence.Profile -cne [string]$resolvedProfile.Key -or
    @($packageEvidence.Staging).Count -ne $allVariants.Count) {
  throw 'Package evidence does not match the selected profile and complete variant inventory.'
}
foreach ($variant in $allVariants) {
  $stagingPath = Resolve-CanvasRequiredDirectory -Path $variant.StagingFolderPath -Description "Staging root '$($variant.VariantKey)'"
  $pluginName = "$($variant.PackageBaseName).esm"
  $archiveName = "$($variant.PackageBaseName) - Main.ba2"
  Assert-ExactFileInventory -Root $stagingPath -Expected @($pluginName, $archiveName) -Description "Staging root '$($variant.VariantKey)'"
  Assert-CanvasArtifactHeader -Path (Join-Path $stagingPath $pluginName)
  Assert-CanvasArtifactHeader -Path (Join-Path $stagingPath $archiveName)
}

Write-Host -ForegroundColor Green "Verified Canvas production sources, artifacts, Spriggit review data, and packages for profile '$($resolvedProfile.Key)'."
