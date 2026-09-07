<#
.SYNOPSIS
Compiles the Papyrus scripts owned by one or more Canvas package variants.
.DESCRIPTION
Variant membership comes exclusively from sharedConfig.ps1. Output is written only beneath
.work and is accompanied by source-bound compile evidence.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VenworksCoreRepositoryPath,

  [string[]]$VariantKeys,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),

  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scripts')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workRoot = Join-Path $repositoryRoot '.work\canvas'
$sourceRoot = Join-Path $repositoryRoot 'Papyrus'
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$matrix = Get-CanvasMatrix -RepositoryRoot $repositoryRoot
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$resolvedVenworksCoreRoot = Assert-PinnedVenworksCoreFixture `
  -VenworksCoreRepositoryPath $VenworksCoreRepositoryPath `
  -Matrix $matrix
$venworksCoreSourceRoot = Join-Path $resolvedVenworksCoreRoot 'Papyrus'
Import-CanvasEnvironment -Path $EnvironmentPath

foreach ($requiredName in @('TOOL_PATH_PAPYRUS_COMPILER', 'PAPYRUS_COMPILER_FLAGS', 'PAPYRUS_SCRIPTS_SOURCE_PATH')) {
  $value = [Environment]::GetEnvironmentVariable($requiredName, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "$requiredName must be configured in $EnvironmentPath."
  }
}

$compilerPath = Resolve-CanvasExecutable `
  -Path $env:TOOL_PATH_PAPYRUS_COMPILER `
  -FileName 'PapyrusCompiler.exe' `
  -Description 'Starfield Papyrus compiler'
$flagsPath = $env:PAPYRUS_COMPILER_FLAGS
if (Test-Path -LiteralPath $flagsPath -PathType Container) {
  $flagsPath = Join-Path $flagsPath 'Starfield_Papyrus_Flags.flg'
}
$resolvedFlagsPath = Resolve-CanvasRequiredFile -Path $flagsPath -Description 'Starfield Papyrus flags file'
$resolvedGameSourcePath = Resolve-CanvasRequiredDirectory `
  -Path $env:PAPYRUS_SCRIPTS_SOURCE_PATH `
  -Description 'Starfield Papyrus source directory'

Assert-CanvasRemovalPath -Path $resolvedOutputDirectory -AllowedRoot $workRoot
New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory | Out-Null

$sourceSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$sources = [System.Collections.Generic.List[string]]::new()
foreach ($variant in $variants) {
  foreach ($relativeSource in @($variant.PapyrusScripts)) {
    if ($sourceSet.Add([string]$relativeSource)) {
      $sources.Add([string]$relativeSource)
    }
  }
}
if ($sources.Count -eq 0) {
  throw 'The selected variants do not declare any Papyrus scripts.'
}

$sourcePaths = @{}
$sourceHashes = @{}
foreach ($relativeSource in $sources) {
  $sourcePath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $sourceRoot $relativeSource) `
    -Description "Canvas Papyrus source '$relativeSource'"
  $sourcePaths[$relativeSource] = $sourcePath
  $sourceHashes[$relativeSource] = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
}

$toolchain = Get-CanvasCompileToolchainEvidence `
  -RepositoryRoot $repositoryRoot `
  -CompilerPath $compilerPath `
  -FlagsPath $resolvedFlagsPath `
  -VenworksCoreRepositoryPath $resolvedVenworksCoreRoot `
  -Matrix $matrix
$selectedSourceMap = Get-CanvasExpectedCompileSources -Variants $variants
$selectedCanonicalSources = @($selectedSourceMap.Keys)
$existingEvidence = $null
$existingEvidencePath = Join-Path $resolvedOutputDirectory 'compile-evidence.json'
if (Test-Path -LiteralPath $existingEvidencePath -PathType Leaf) {
  try { $existingEvidence = Get-Content -LiteralPath $existingEvidencePath -Raw | ConvertFrom-Json }
  catch { Write-Warning "Existing Papyrus compile evidence could not be read and will not be retained: $($_.Exception.Message)" }
}
$retainedRows = @(Get-CanvasValidRetainedCompileRows `
  -Evidence $existingEvidence `
  -RepositoryRoot $repositoryRoot `
  -OutputDirectory $resolvedOutputDirectory `
  -SelectedSources $selectedCanonicalSources `
  -Toolchain $toolchain)

$transactionRoot = Join-Path $workRoot ('script-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $transactionRoot | Out-Null
$compiled = [System.Collections.Generic.List[object]]::new()
try {
  foreach ($relativeSource in $sources) {
    $sourcePath = [string]$sourcePaths[$relativeSource]
    $sourceSha256Before = [string]$sourceHashes[$relativeSource]
    & $compilerPath $sourcePath -f -optimize "-flags=$resolvedFlagsPath" "-output=$transactionRoot" "-import=$sourceRoot;$venworksCoreSourceRoot;$resolvedGameSourcePath" -ignorecwd
    if ($LASTEXITCODE -ne 0) {
      throw "Papyrus compilation failed for '$relativeSource' with exit code $LASTEXITCODE."
    }
    $outputName = [System.IO.Path]::ChangeExtension($relativeSource, '.pex')
    $candidatePath = Resolve-CanvasRequiredFile `
      -Path (Join-Path $transactionRoot $outputName) `
      -Description "Compiled Papyrus script '$outputName'"
    if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $sourceSha256Before) {
      throw "Canvas Papyrus source changed during compilation: $relativeSource"
    }
    $compiled.Add([ordered]@{
      VariantKeys = @($selectedSourceMap[$relativeSource.Replace('\', '/')])
      Source = $relativeSource.Replace('\', '/')
      SourceSha256 = $sourceSha256Before
      Output = $outputName.Replace('\', '/')
      Sha256 = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToUpperInvariant()
    })
  }

  [void](Assert-PinnedVenworksCoreFixture `
    -VenworksCoreRepositoryPath $resolvedVenworksCoreRoot `
    -Matrix $matrix)
  Assert-CanvasCompileToolchainEvidence `
    -Actual $toolchain `
    -Expected (Get-CanvasCompileToolchainEvidence -RepositoryRoot $repositoryRoot -CompilerPath $compilerPath -FlagsPath $resolvedFlagsPath -VenworksCoreRepositoryPath $resolvedVenworksCoreRoot -Matrix $matrix)
  foreach ($relativeSource in $sources) {
    $currentHash = (Get-FileHash -LiteralPath ([string]$sourcePaths[$relativeSource]) -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($currentHash -cne [string]$sourceHashes[$relativeSource]) {
      throw "Canvas Papyrus source changed during the complete compile: $relativeSource"
    }
  }

  foreach ($row in @($compiled)) {
    $candidatePath = Join-Path $transactionRoot ([string]$row.Output).Replace('/', '\')
    $destinationPath = Join-Path $resolvedOutputDirectory ([string]$row.Output).Replace('/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationPath) | Out-Null
    $temporaryPath = "$destinationPath.$PID-$([guid]::NewGuid().ToString('N')).new"
    try {
      Copy-Item -LiteralPath $candidatePath -Destination $temporaryPath
      if ((Get-CanvasFileSha256 -Path $temporaryPath) -cne [string]$row.Sha256) {
        throw "Compiled Papyrus promotion copy differs for '$($row.Output)'."
      }
      [System.IO.File]::Move($temporaryPath, $destinationPath, $true)
      if ((Get-CanvasFileSha256 -Path $destinationPath) -cne [string]$row.Sha256) {
        throw "Compiled Papyrus output differs after promotion for '$($row.Output)'."
      }
    }
    finally {
      if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
  }

  $evidence = [ordered]@{
    Schema = 'VWCANVAS_SCRIPTS/2'
    Toolchain = $toolchain
    Scripts = @($retainedRows + @($compiled) | Sort-Object Source)
  }
  $evidenceTemporaryPath = "$existingEvidencePath.$PID-$([guid]::NewGuid().ToString('N')).new"
  Write-CanvasUtf8WithoutBom -Path $evidenceTemporaryPath -Text (($evidence | ConvertTo-Json -Depth 8) + "`n")
  [System.IO.File]::Move($evidenceTemporaryPath, $existingEvidencePath, $true)
  Assert-CanvasCompileEvidence `
    -Evidence (Get-Content -LiteralPath $existingEvidencePath -Raw | ConvertFrom-Json) `
    -RepositoryRoot $repositoryRoot `
    -OutputDirectory $resolvedOutputDirectory `
    -Variants $variants `
    -Toolchain $toolchain `
    -ValidateAllRows
}
finally {
  if (Test-Path -LiteralPath $transactionRoot -PathType Container) {
    Assert-CanvasRemovalPath -Path $transactionRoot -AllowedRoot $workRoot
    Remove-Item -LiteralPath $transactionRoot -Recurse -Force
  }
}

Write-Host -ForegroundColor Green "Compiled $($compiled.Count) selected Canvas Papyrus scripts and preserved $($retainedRows.Count) validated evidence rows at $resolvedOutputDirectory"
