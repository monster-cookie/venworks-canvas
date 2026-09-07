<#
.SYNOPSIS
Verifies Canvas source contracts, selected build artifacts, and installed package receipts.
#>
[CmdletBinding()]
param(
  [switch]$SourceOnly,
  [switch]$ArtifactsOnly,
  [string[]]$VariantKeys,
  [string]$VwHudRepositoryPath,
  [string]$VenworksCoreRepositoryPath,
  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),
  [string]$ScaleformDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scaleform'),
  [string]$ScriptsDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scripts'),
  [string]$PackageReceiptsDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\package-receipts')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$matrix = Get-CanvasMatrix -RepositoryRoot $repositoryRoot
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
  'testBuildEvidence.ps1',
  'testBuildVariants.ps1',
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

if ([string]::IsNullOrWhiteSpace($VwHudRepositoryPath) -or [string]::IsNullOrWhiteSpace($VenworksCoreRepositoryPath)) {
  throw 'Artifact verification requires VwHudRepositoryPath and VenworksCoreRepositoryPath.'
}
Import-CanvasEnvironment -Path $EnvironmentPath
$resolvedVwHudRoot = Assert-PinnedVwHudToolchainFixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
$resolvedCoreRoot = Assert-PinnedVenworksCoreFixture -VenworksCoreRepositoryPath $VenworksCoreRepositoryPath -Matrix $matrix
$scriptsDirectory = Resolve-CanvasRequiredDirectory -Path $ScriptsDirectory -Description 'Compiled Papyrus directory'
$scaleformDirectory = Resolve-CanvasRequiredDirectory -Path $ScaleformDirectory -Description 'Built Scaleform directory'
$moviesDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $scaleformDirectory 'movies') -Description 'Built Canvas movie directory'

foreach ($name in @('TOOL_PATH_PAPYRUS_COMPILER', 'PAPYRUS_COMPILER_FLAGS')) {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) { throw "$name must be configured in $EnvironmentPath." }
}
$compilerPath = Resolve-CanvasExecutable -Path $env:TOOL_PATH_PAPYRUS_COMPILER -FileName 'PapyrusCompiler.exe' -Description 'Papyrus compiler'
$flagsPath = $env:PAPYRUS_COMPILER_FLAGS
if (Test-Path -LiteralPath $flagsPath -PathType Container) { $flagsPath = Join-Path $flagsPath 'Starfield_Papyrus_Flags.flg' }
$compileToolchain = Get-CanvasCompileToolchainEvidence -RepositoryRoot $repositoryRoot -CompilerPath $compilerPath -FlagsPath $flagsPath -VenworksCoreRepositoryPath $resolvedCoreRoot -Matrix $matrix
$compileEvidencePath = Resolve-CanvasRequiredFile -Path (Join-Path $scriptsDirectory 'compile-evidence.json') -Description 'Papyrus compile evidence'
$compileEvidenceSnapshot = Get-CanvasJsonEvidenceSnapshot -Path $compileEvidencePath -Description 'Papyrus compile evidence' -TransactionFileName 'compile-evidence.json'
$compileEvidence = $compileEvidenceSnapshot.Value
Assert-CanvasCompileEvidence -Evidence $compileEvidence -RepositoryRoot $repositoryRoot -OutputDirectory $scriptsDirectory -Variants $variants -Toolchain $compileToolchain

$scaleformToolchain = Get-CanvasScaleformToolchainEvidence `
  -RepositoryRoot $repositoryRoot `
  -VwHudRepositoryPath $resolvedVwHudRoot `
  -JavaPath (Join-Path $resolvedVwHudRoot '.work\tools\java\bin\java.exe') `
  -JpexsJarPath (Join-Path $resolvedVwHudRoot '.work\tools\jpexs\ffdec.jar') `
  -FlexSdkPath (Join-Path $resolvedVwHudRoot '.work\tools\flex') `
  -Matrix $matrix
$movieEvidencePath = Resolve-CanvasRequiredFile -Path (Join-Path $moviesDirectory 'build-evidence.json') -Description 'Canvas movie evidence'
$movieEvidenceSnapshot = Get-CanvasJsonEvidenceSnapshot -Path $movieEvidencePath -Description 'Canvas movie evidence' -TransactionFileName 'canvas-movies-evidence.json'
$movieEvidence = $movieEvidenceSnapshot.Value
Assert-CanvasMovieEvidence -Evidence $movieEvidence -RepositoryRoot $repositoryRoot -MoviesDirectory $moviesDirectory -Variants $variants -Toolchain $scaleformToolchain
$scaleformEvidencePath = Resolve-CanvasRequiredFile -Path (Join-Path $scaleformDirectory 'build-evidence.json') -Description 'Scaleform aggregate evidence'
$scaleformEvidenceSnapshot = Get-CanvasJsonEvidenceSnapshot -Path $scaleformEvidencePath -Description 'Scaleform aggregate evidence' -TransactionFileName 'scaleform-evidence.json'
$scaleformEvidence = $scaleformEvidenceSnapshot.Value
$requiresPlayerHud = @($variants | Where-Object { $_.IncludesPlayerHud }).Count -gt 0
$requiresShipHud = @($variants | Where-Object { $_.IncludesShipHud }).Count -gt 0
$playerDirectory = $null
$playerEvidence = $null
$playerEvidenceSnapshot = $null
$shipDirectory = $null
$shipEvidence = $null
$shipEvidenceSnapshot = $null
if ($requiresPlayerHud) {
  $playerDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $scaleformDirectory 'player-hud') -Description 'Player HUD output'
  $playerEvidenceSnapshot = Get-CanvasJsonEvidenceSnapshot -Path (Join-Path $playerDirectory 'build-evidence.json') -Description 'Player HUD evidence' -TransactionFileName 'player-hud-evidence.json'
  $playerEvidence = $playerEvidenceSnapshot.Value
  Assert-CanvasPlayerHudEvidence -Evidence $playerEvidence -RepositoryRoot $repositoryRoot -VwHudRepositoryPath $resolvedVwHudRoot -PlayerDirectory $playerDirectory -Matrix $matrix
}
if ($requiresShipHud) {
  $shipDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $scaleformDirectory 'ship-hud') -Description 'Ship HUD output'
  $shipEvidenceSnapshot = Get-CanvasJsonEvidenceSnapshot -Path (Join-Path $shipDirectory 'build-evidence.json') -Description 'Ship HUD evidence' -TransactionFileName 'ship-hud-evidence.json'
  $shipEvidence = $shipEvidenceSnapshot.Value
  Assert-CanvasShipHudEvidence -Evidence $shipEvidence -RepositoryRoot $repositoryRoot -VwHudRepositoryPath $resolvedVwHudRoot -ShipDirectory $shipDirectory -Matrix $matrix
}
Assert-CanvasScaleformAggregateEvidence -Evidence $scaleformEvidence -ScaleformDirectory $scaleformDirectory -RequiredVariantKeys @($variants.VariantKey) -RequirePlayerHud $requiresPlayerHud -RequireShipHud $requiresShipHud
if ([string]$scaleformEvidence.CanvasMoviesEvidenceSha256 -cne [string]$movieEvidenceSnapshot.Sha256 -or
    ($requiresPlayerHud -and [string]$scaleformEvidence.PlayerHudEvidenceSha256 -cne [string]$playerEvidenceSnapshot.Sha256) -or
    ($requiresShipHud -and [string]$scaleformEvidence.ShipHudEvidenceSha256 -cne [string]$shipEvidenceSnapshot.Sha256)) {
  throw 'Scaleform aggregate evidence does not bind the evidence documents admitted for verification.'
}
if ($ArtifactsOnly) {
  Write-Host -ForegroundColor Green "Verified current source-bound build artifacts for $($variants.VariantKey -join ', ')."
  return
}

$operations = @(Get-CanvasPackageInstallOperations -SelectedVariants $variants -AllVariants $allVariants)
$payloads = Get-CanvasPackagePayloads `
  -SelectedVariants $variants `
  -CompileEvidence $compileEvidence `
  -MovieEvidence $movieEvidence `
  -MoviesDirectory $moviesDirectory `
  -ScriptsDirectory $scriptsDirectory `
  -VenworksCoreRepositoryPath $resolvedCoreRoot `
  -Matrix $matrix `
  -PlayerDirectory $playerDirectory `
  -PlayerEvidence $playerEvidence `
  -ShipDirectory $shipDirectory `
  -ShipEvidence $shipEvidence
$receipts = @(Get-CanvasPackageReceipts -ReceiptDirectory $PackageReceiptsDirectory -RequiredVariantKeys @($variants.VariantKey))
foreach ($operation in $operations) {
  $receipt = @($receipts | Where-Object { [string]$_.VariantKey -ceq [string]$operation.Key })
  if ($receipt.Count -ne 1) { throw "Package evidence does not resolve exactly one '$($operation.Key)' receipt." }
  $expectedEntries = @($payloads[[string]$operation.Key] | ForEach-Object {
    [ordered]@{ Path = ([string]$_.Target).Replace('\', '/').ToLowerInvariant(); Sha256 = [string]$_.ExpectedSha256 }
  })
  Assert-CanvasPackageReceipt `
    -Receipt $receipt[0] `
    -Variant $operation.Variant `
    -InstallPath $operation.InstallPath `
    -ExpectedEntries $expectedEntries `
    -CompileEvidenceSha256 ([string]$compileEvidenceSnapshot.Sha256) `
    -ScaleformEvidenceSha256 ([string]$scaleformEvidenceSnapshot.Sha256)
}
Write-Host -ForegroundColor Green "Verified current build provenance and installed package receipts for $($variants.VariantKey -join ', ')."
