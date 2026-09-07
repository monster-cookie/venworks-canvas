<#
.SYNOPSIS
Verifies Canvas source contracts, selected build outputs, and installed packages.
#>
[CmdletBinding()]
param(
  [switch]$SourceOnly,
  [switch]$ArtifactsOnly,
  [string[]]$VariantKeys,
  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),
  [string]$ScaleformDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scaleform'),
  [string]$ScriptsDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scripts')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)

$retiredInvestigationTerm = 'pro' + 'be'
$retiredExplorationTerm = 'sp' + 'ike'
$retiredCanvasTerm = 'Canvas' + 'Discovery'
$retiredConsumerTerm = 'Consumer' + 'Discovery'
$retiredUpdatedTerm = 'Updated' + 'Example'
$retiredMigrationTerm = 'Example' + 'Update' + 'Migration'
$forbiddenPattern = '(?i)\b(?:' + [string]::Join('|', @($retiredInvestigationTerm, $retiredExplorationTerm, $retiredCanvasTerm, $retiredConsumerTerm, $retiredUpdatedTerm, $retiredMigrationTerm)) + ')\b'
$sourceRoots = @(
  (Join-Path $repositoryRoot 'Tools'),
  (Join-Path $repositoryRoot 'Papyrus'),
  (Join-Path $repositoryRoot 'Scaleform'),
  (Join-Path $repositoryRoot 'Spriggit'),
  (Join-Path $repositoryRoot 'Tests'),
  (Join-Path $repositoryRoot '.github')
)
$sourceFiles = @($sourceRoots | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object {
  Get-ChildItem -LiteralPath $_ -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psc', '.as', '.xml', '.psd1', '.json', '.yaml', '.yml') }
})
foreach ($topLevelFile in @('README.md', 'CHANGELOG.md')) {
  $path = Join-Path $repositoryRoot $topLevelFile
  if (Test-Path -LiteralPath $path -PathType Leaf) { $sourceFiles += Get-Item -LiteralPath $path }
}
$forbiddenHits = @($sourceFiles | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match $forbiddenPattern })
if ($forbiddenHits.Count -ne 0) { throw "Retired implementation terminology remains in: $([string]::Join(', ', @($forbiddenHits.FullName)))." }

foreach ($entryPoint in @('compileScripts.ps1', 'buildScaleform.ps1', 'createPackages.ps1', 'SpriggitDumpDatabaseToYaml.ps1', 'SpriggitAssembleDatabaseFromYaml.ps1')) {
  [void](Resolve-CanvasRequiredFile -Path (Join-Path $PSScriptRoot $entryPoint) -Description "Production entry point '$entryPoint'")
}
$allVariants = @(Get-ModuleVariants)
foreach ($variant in $allVariants) {
  foreach ($relativeSource in @($variant.PapyrusScripts)) {
    [void](Resolve-CanvasRequiredFile -Path (Join-Path $repositoryRoot "Papyrus\$relativeSource") -Description "Papyrus source '$relativeSource'")
  }
  $manifestPath = Resolve-CanvasRequiredFile -Path (Join-Path $repositoryRoot "Scaleform\canvas\$($variant.ScaleformManifest)") -Description "Scaleform manifest '$($variant.ScaleformManifest)'"
  $definition = Get-CanvasBuildDefinition -ManifestPath $manifestPath
  if ([string]$definition.OutputFile -cne [string]$variant.ScaleformOutput) { throw "Variant '$($variant.VariantKey)' manifest output differs from sharedConfig.ps1." }
}

foreach ($sourceContractTest in @(
  'testConsole.ps1',
  'testGuards.ps1',
  'testPackaging.ps1',
  'testBuildVariants.ps1',
  'testBuildEvidence.ps1',
  'testSpriggit.ps1',
  'testSetup.ps1',
  'testUiLoad.ps1',
  'testUiReceive.ps1',
  'testUuid.ps1'
)) {
  & (Resolve-CanvasRequiredFile -Path (Join-Path $PSScriptRoot $sourceContractTest) -Description "Source contract test '$sourceContractTest'")
}
if ($SourceOnly) {
  Write-Host -ForegroundColor Green 'Verified Canvas source identities, build entry points, and focused source contracts.'
  return
}

$scriptsDirectory = Resolve-CanvasRequiredDirectory -Path $ScriptsDirectory -Description 'Compiled Canvas Papyrus directory'
$scaleformDirectory = Resolve-CanvasRequiredDirectory -Path $ScaleformDirectory -Description 'Built Canvas Scaleform directory'
$moviesDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $scaleformDirectory 'movies') -Description 'Built Canvas movie directory'
$playerDirectory = $null
$shipDirectory = $null
if (@($variants | Where-Object { [string]$_.VariantKey -ceq 'CANVAS' }).Count -ne 0) {
  $playerDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $scaleformDirectory 'player-hud') -Description 'Built Player HUD directory'
  $shipDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $scaleformDirectory 'ship-hud') -Description 'Built Ship HUD directory'
}
$payloads = Get-CanvasPackagePayloads `
  -SelectedVariants $variants `
  -MoviesDirectory $moviesDirectory `
  -ScriptsDirectory $scriptsDirectory `
  -PlayerDirectory $playerDirectory `
  -ShipDirectory $shipDirectory
if ($ArtifactsOnly) {
  Write-Host -ForegroundColor Green "Verified current Canvas-owned build outputs for $($variants.VariantKey -join ', ')."
  return
}

Import-CanvasEnvironment -Path $EnvironmentPath
$operations = @(Get-CanvasPackageInstallOperations -SelectedVariants $variants -AllVariants $allVariants)
foreach ($operation in $operations) {
  $expectedEntries = @($payloads[[string]$operation.Key] | ForEach-Object {
    [ordered]@{ Path = ([string]$_.Target).Replace('\', '/').ToLowerInvariant(); Sha256 = [string]$_.ExpectedSha256 }
  })
  Assert-CanvasInstalledPackage -Variant $operation.Variant -InstallPath $operation.InstallPath -ExpectedEntries $expectedEntries
}
Write-Host -ForegroundColor Green "Verified current installed packages for $($variants.VariantKey -join ', ')."
