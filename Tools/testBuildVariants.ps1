<#
.SYNOPSIS
Exercises selected-build evidence retention and selected-only package payload resolution with isolated files.
.DESCRIPTION
This is a filesystem/evidence simulation. It does not invoke the Papyrus, Flex, JPEXS, VWHUD, or Archive2 toolchains.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

function Assert-TestRejected {
  param([Parameter(Mandatory = $true)][scriptblock]$Action, [Parameter(Mandatory = $true)][string]$Description)
  $caught = $false
  try { & $Action } catch { $caught = $true }
  if (!$caught) { throw "$Description was accepted." }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testBase = Join-Path $repositoryRoot '.work\canvas\build-remediation-tests'
$fixtureRoot = Join-Path $testBase ('variants-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
try {
  $environmentProbeRoot = Join-Path $fixtureRoot 'environment-path'
  $probeRepositoryRoot = Join-Path $environmentProbeRoot 'repository'
  $probeToolsDirectory = Join-Path $probeRepositoryRoot 'Tools'
  New-Item -ItemType Directory -Force -Path $probeToolsDirectory | Out-Null
  foreach ($fileName in @('sharedConfig.ps1', 'sharedCanvas.ps1', 'sharedCanvasBuildEvidence.ps1', 'sharedCanvasPackaging.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination $probeToolsDirectory
  }
  $alternateEnvironmentPath = Join-Path $environmentProbeRoot 'alternate.env'
  Write-CanvasUtf8WithoutBom -Path $alternateEnvironmentPath -Text "VWCANVAS_ENVIRONMENT_PATH_PROBE=alternate`n"
  if (Test-Path -LiteralPath (Join-Path $probeRepositoryRoot '.env')) {
    throw 'Explicit EnvironmentPath fixture unexpectedly contains a default .env file.'
  }
  $probePath = Join-Path $probeToolsDirectory 'environmentPathProbe.ps1'
  $probeSource = @'
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$EnvironmentPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')
Import-CanvasEnvironment -Path $EnvironmentPath
if ($env:VWCANVAS_ENVIRONMENT_PATH_PROBE -cne 'alternate') { throw 'Explicit alternate environment content was not imported.' }
Write-Output "VWCANVAS_ENVIRONMENT_PATH_OK=$([System.IO.Path]::GetFullPath($EnvironmentPath))"
'@
  Write-CanvasUtf8WithoutBom -Path $probePath -Text ($probeSource + "`n")
  $probeOutput = @(& (Get-Process -Id $PID).Path -NoProfile -File $probePath -EnvironmentPath $alternateEnvironmentPath 2>&1)
  $expectedProbeOutput = "VWCANVAS_ENVIRONMENT_PATH_OK=$([System.IO.Path]::GetFullPath($alternateEnvironmentPath))"
  if ($LASTEXITCODE -ne 0 -or $probeOutput.Count -ne 1 -or [string]$probeOutput[0] -cne $expectedProbeOutput) {
    throw "An explicit alternate EnvironmentPath was not preserved across sharedConfig loading: $([string]::Join(' | ', @($probeOutput)))"
  }
  foreach ($wrapperName in @(
    'compileScripts.ps1',
    'buildScaleform.ps1',
    'createPackages.ps1',
    'verifyCanvas.ps1',
    'SpriggitDumpDatabaseToYaml.ps1',
    'SpriggitAssembleDatabaseFromYaml.ps1'
  )) {
    $wrapperSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot $wrapperName))
    if ($wrapperSource -cnotmatch '(?m)^\s*\[string\]\$EnvironmentPath(?:\s*=|,)' -or
        $wrapperSource -cnotmatch '(?m)^\. \(Join-Path \$PSScriptRoot ''sharedConfig\.ps1''\) -SkipEnvironment\s*$' -or
        $wrapperSource -cnotmatch '(?m)Import-CanvasEnvironment\s+-Path\s+\$EnvironmentPath') {
      throw "$wrapperName no longer exposes and consumes the shared alternate EnvironmentPath contract."
    }
  }

  $allVariants = @(Get-ModuleVariants)
  $example = @(Get-ModuleVariants -VariantKeys 'EXAMPLE')[0]
  $componentGallery = @(Get-ModuleVariants -VariantKeys 'COMPONENTGALLERY')[0]
  $canvas = @(Get-ModuleVariants -VariantKeys 'CANVAS')[0]

  $scriptsDirectory = Join-Path $fixtureRoot 'scripts'
  $sourceOwnership = Get-CanvasExpectedCompileSources -Variants $allVariants
  $compileRows = [System.Collections.Generic.List[object]]::new()
  foreach ($source in @($sourceOwnership.Keys)) {
    $sourcePath = Join-Path $fixtureRoot ('Papyrus\' + $source.Replace('/', '\'))
    $output = [System.IO.Path]::ChangeExtension($source, '.pex')
    $outputPath = Join-Path $scriptsDirectory $output.Replace('/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sourcePath), (Split-Path -Parent $outputPath) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repositoryRoot ('Papyrus\' + $source.Replace('/', '\'))) -Destination $sourcePath
    [System.IO.File]::WriteAllBytes($outputPath, [Text.Encoding]::UTF8.GetBytes("compiled-$source"))
    $compileRows.Add([pscustomobject]@{
      VariantKeys = @($sourceOwnership[$source]); Source = $source; SourceSha256 = Get-CanvasFileSha256 -Path $sourcePath
      Output = $output; Sha256 = Get-CanvasFileSha256 -Path $outputPath
    })
  }
  $compileToolchain = [pscustomobject]@{
    Compiler = [pscustomobject]@{ Key = 'PapyrusCompiler'; Path = 'compiler'; Sha256 = '1' * 64 }; CompilerVersion = 'fixture'
    Flags = [pscustomobject]@{ Key = 'PapyrusFlags'; Path = 'flags'; Sha256 = '2' * 64 }; VenworksCoreRevision = 'fixture'
    VenworksCoreSources = @([pscustomobject]@{ Key = 'core'; Path = 'core'; Sha256 = '3' * 64 })
    ImplementationFiles = @([pscustomobject]@{ Key = 'implementation'; Path = 'implementation'; Sha256 = '4' * 64 })
  }
  $compileEvidence = [pscustomobject]@{ Schema = 'VWCANVAS_SCRIPTS/2'; Toolchain = $compileToolchain; Scripts = @($compileRows) }
  $selectedSources = @((Get-CanvasExpectedCompileSources -Variants @($example)).Keys)
  $retainedCompile = @(Get-CanvasValidRetainedCompileRows -Evidence $compileEvidence -RepositoryRoot $fixtureRoot -OutputDirectory $scriptsDirectory -SelectedSources $selectedSources -Toolchain $compileToolchain)
  if ($retainedCompile.Count -ne $compileRows.Count - 1) { throw 'EXAMPLE-only compile retention did not preserve every valid unselected row.' }
  $staleCompileRow = @($retainedCompile | Where-Object { 'CANVAS' -in @($_.VariantKeys) })[0]
  $staleCompilePath = Join-Path $scriptsDirectory ([string]$staleCompileRow.Output).Replace('/', '\')
  [System.IO.File]::AppendAllText($staleCompilePath, 'stale')
  $staleCompileHash = Get-CanvasFileSha256 -Path $staleCompilePath
  $filteredCompile = @(Get-CanvasValidRetainedCompileRows -Evidence $compileEvidence -RepositoryRoot $fixtureRoot -OutputDirectory $scriptsDirectory -SelectedSources $selectedSources -Toolchain $compileToolchain -WarningAction SilentlyContinue)
  if ($filteredCompile.Count -ne $retainedCompile.Count - 1 -or (Get-CanvasFileSha256 -Path $staleCompilePath) -cne $staleCompileHash) {
    throw 'Stale unselected compile evidence was not omitted while preserving its output bytes.'
  }

  $canvasRoot = Join-Path $fixtureRoot 'Scaleform\canvas'
  $moviesDirectory = Join-Path $fixtureRoot 'scaleform\movies'
  New-Item -ItemType Directory -Force -Path $moviesDirectory | Out-Null
  $movieRows = [System.Collections.Generic.List[object]]::new()
  foreach ($variant in $allVariants) {
    $manifestSource = Join-Path $repositoryRoot "Scaleform\canvas\$($variant.ScaleformManifest)"
    $manifestPath = Join-Path $canvasRoot ([string]$variant.ScaleformManifest)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifestPath) | Out-Null
    Copy-Item -LiteralPath $manifestSource -Destination $manifestPath
    $definition = Get-CanvasBuildDefinition -ManifestPath $manifestSource
    $sourceRelative = [System.IO.Path]::GetRelativePath((Join-Path $repositoryRoot 'Scaleform\canvas'), $definition.SourcePath)
    $sourcePath = Join-Path $canvasRoot $sourceRelative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sourcePath) | Out-Null
    Copy-Item -LiteralPath $definition.SourcePath -Destination $sourcePath -Force
    $outputPath = Join-Path $moviesDirectory ([string]$variant.ScaleformOutput)
    [System.IO.File]::WriteAllBytes($outputPath, [Text.Encoding]::UTF8.GetBytes("movie-$($variant.VariantKey)"))
    $movieRows.Add([pscustomobject]@{
      VariantKey = [string]$variant.VariantKey; Name = ([string]$variant.VariantKey).ToLowerInvariant(); Role = 'fixture'
      OutputFile = [string]$variant.ScaleformOutput; Sha256 = Get-CanvasFileSha256 -Path $outputPath
      Manifest = ([string]$variant.ScaleformManifest).Replace('\', '/'); ManifestSha256 = Get-CanvasFileSha256 -Path $manifestPath
      Source = $sourceRelative.Replace('\', '/'); SourceSha256 = Get-CanvasFileSha256 -Path $sourcePath
      ClassInventory = @('Fixture'); BuildPasses = 2
    })
  }
  $scaleformToolchain = [pscustomobject]@{
    VwHudRevision = 'fixture'
    Files = @([pscustomobject]@{ Key = 'tool'; Path = 'tool'; Sha256 = '5' * 64 })
    ImplementationFiles = @([pscustomobject]@{ Key = 'implementation'; Path = 'implementation'; Sha256 = '6' * 64 })
  }
  $movieEvidence = [pscustomobject]@{ Schema = 'VWCANVAS_SCALEFORM_MOVIES/2'; Toolchain = $scaleformToolchain; Movies = @($movieRows) }
  $retainedMovies = @(Get-CanvasValidRetainedMovieRows -Evidence $movieEvidence -RepositoryRoot $fixtureRoot -MoviesDirectory $moviesDirectory -SelectedVariantKeys @('EXAMPLE') -Toolchain $scaleformToolchain)
  if ($retainedMovies.Count -ne 2) { throw 'EXAMPLE-only movie retention did not preserve both valid unselected rows.' }
  $canvasMoviePath = Join-Path $moviesDirectory $canvas.ScaleformOutput
  [System.IO.File]::AppendAllText($canvasMoviePath, 'stale')
  $staleMovieHash = Get-CanvasFileSha256 -Path $canvasMoviePath
  $filteredMovies = @(Get-CanvasValidRetainedMovieRows -Evidence $movieEvidence -RepositoryRoot $fixtureRoot -MoviesDirectory $moviesDirectory -SelectedVariantKeys @('EXAMPLE') -Toolchain $scaleformToolchain -WarningAction SilentlyContinue)
  if ($filteredMovies.Count -ne 1 -or (Get-CanvasFileSha256 -Path $canvasMoviePath) -cne $staleMovieHash) {
    throw 'Stale unselected movie evidence was not omitted while preserving its output bytes.'
  }

  $movieEvidencePath = Join-Path $moviesDirectory 'build-evidence.json'
  Write-CanvasUtf8WithoutBom -Path $movieEvidencePath -Text (($movieEvidence | ConvertTo-Json -Depth 8) + "`n")
  $aggregate = [pscustomobject]@{
    Schema = 'VWCANVAS_SCALEFORM_BUILD/2'; Variants = @('CANVAS', 'EXAMPLE', 'COMPONENTGALLERY')
    CanvasMoviesEvidenceSha256 = Get-CanvasFileSha256 -Path $movieEvidencePath; PlayerHudEvidenceSha256 = $null; ShipHudEvidenceSha256 = $null
  }
  Assert-CanvasScaleformAggregateEvidence -Evidence $aggregate -ScaleformDirectory (Join-Path $fixtureRoot 'scaleform') -RequiredVariantKeys @('EXAMPLE') -RequirePlayerHud $false -RequireShipHud $false

  foreach ($variant in @($example, $componentGallery)) {
    $payloads = Get-CanvasPackagePayloads -SelectedVariants @($variant) -CompileEvidence $compileEvidence -MovieEvidence $movieEvidence -MoviesDirectory $moviesDirectory -ScriptsDirectory $scriptsDirectory -VenworksCoreRepositoryPath $fixtureRoot -Matrix @{ VenworksCoreFixture = @{ RuntimeScripts = @() } }
    if (@($payloads[[string]$variant.VariantKey]).Count -ne 3) { throw "$($variant.VariantKey)-only payload unexpectedly requires unrelated Player/Ship directories." }
    $variantMovieHash = [string]@($movieEvidence.Movies | Where-Object VariantKey -CEQ $variant.VariantKey)[0].Sha256
    foreach ($payload in @($payloads[[string]$variant.VariantKey] | Where-Object { [string]$_.Target -like 'Interface\*' })) {
      if ([string]$payload.ExpectedSha256 -cne $variantMovieHash) { throw "$($variant.VariantKey) payload did not retain its admitted movie hash." }
    }
    foreach ($payload in @($payloads[[string]$variant.VariantKey] | Where-Object { [string]$_.Target -like 'Scripts\*' })) {
      $source = ([string]$variant.PapyrusScripts[0]).Replace('\', '/')
      $expectedCompileHash = [string]@($compileEvidence.Scripts | Where-Object Source -CEQ $source)[0].Sha256
      if ([string]$payload.ExpectedSha256 -cne $expectedCompileHash) { throw "$($variant.VariantKey) payload did not retain its admitted compile hash." }
    }
  }
  $missingCompileEvidence = [pscustomobject]@{ Scripts = @() }
  Assert-TestRejected -Description 'Payload with missing admitted compile row' -Action {
    [void](Get-CanvasPackagePayloads -SelectedVariants @($example) -CompileEvidence $missingCompileEvidence -MovieEvidence $movieEvidence -MoviesDirectory $moviesDirectory -ScriptsDirectory $scriptsDirectory -VenworksCoreRepositoryPath $fixtureRoot -Matrix @{ VenworksCoreFixture = @{ RuntimeScripts = @() } })
  }
  $exampleCompileRow = @($compileEvidence.Scripts | Where-Object { 'EXAMPLE' -in @($_.VariantKeys) })[0]
  $duplicateCompileEvidence = [pscustomobject]@{ Scripts = @($compileEvidence.Scripts) + @($exampleCompileRow) }
  Assert-TestRejected -Description 'Payload with duplicate admitted compile row' -Action {
    [void](Get-CanvasPackagePayloads -SelectedVariants @($example) -CompileEvidence $duplicateCompileEvidence -MovieEvidence $movieEvidence -MoviesDirectory $moviesDirectory -ScriptsDirectory $scriptsDirectory -VenworksCoreRepositoryPath $fixtureRoot -Matrix @{ VenworksCoreFixture = @{ RuntimeScripts = @() } })
  }
  Assert-TestRejected -Description 'CANVAS payload without Player/Ship evidence' -Action {
    [void](Get-CanvasPackagePayloads -SelectedVariants @($canvas) -CompileEvidence $compileEvidence -MovieEvidence $movieEvidence -MoviesDirectory $moviesDirectory -ScriptsDirectory $scriptsDirectory -VenworksCoreRepositoryPath $fixtureRoot -Matrix @{ VenworksCoreFixture = @{ RuntimeScripts = @() } })
  }
}
finally {
  if (Test-Path -LiteralPath $fixtureRoot) {
    Assert-CanvasRemovalPath -Path $fixtureRoot -AllowedRoot $testBase
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}

Write-Output 'Selected-build simulation passed: explicit alternate environment paths survive shared configuration loading for all six affected wrappers, payloads retain admitted compile/movie hashes, valid unselected evidence is retained, stale rows are omitted without deleting outputs, and consumer-only payloads require no Player/Ship directories.'
