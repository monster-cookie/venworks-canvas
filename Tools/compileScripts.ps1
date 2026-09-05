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

if (Test-Path -LiteralPath $resolvedOutputDirectory -PathType Container) {
  Assert-CanvasRemovalPath -Path $resolvedOutputDirectory -AllowedRoot $workRoot
  Remove-Item -LiteralPath $resolvedOutputDirectory -Recurse -Force
}
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

$compiled = [System.Collections.Generic.List[object]]::new()
foreach ($relativeSource in $sources) {
  $sourcePath = [string]$sourcePaths[$relativeSource]
  $sourceSha256Before = [string]$sourceHashes[$relativeSource]
  & $compilerPath $sourcePath -f -optimize "-flags=$resolvedFlagsPath" "-output=$resolvedOutputDirectory" "-import=$sourceRoot;$venworksCoreSourceRoot;$resolvedGameSourcePath" -ignorecwd
  if ($LASTEXITCODE -ne 0) {
    throw "Papyrus compilation failed for '$relativeSource' with exit code $LASTEXITCODE."
  }
  $outputName = [System.IO.Path]::ChangeExtension($relativeSource, '.pex')
  $outputPath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $resolvedOutputDirectory $outputName) `
    -Description "Compiled Papyrus script '$outputName'"
  if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $sourceSha256Before) {
    throw "Canvas Papyrus source changed during compilation: $relativeSource"
  }
  $compiled.Add([ordered]@{
    Source = $relativeSource.Replace('\', '/')
    SourceSha256 = $sourceSha256Before
    Output = $outputName.Replace('\', '/')
    Sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToUpperInvariant()
  })
}

[void](Assert-PinnedVenworksCoreFixture `
  -VenworksCoreRepositoryPath $resolvedVenworksCoreRoot `
  -Matrix $matrix)
foreach ($relativeSource in $sources) {
  $currentHash = (Get-FileHash -LiteralPath ([string]$sourcePaths[$relativeSource]) -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($currentHash -cne [string]$sourceHashes[$relativeSource]) {
    throw "Canvas Papyrus source changed during the complete compile: $relativeSource"
  }
}

$evidence = [ordered]@{
  Schema = 'VWCANVAS_SCRIPTS/1'
  CompilerVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($compilerPath).FileVersion
  Variants = @($variants.VariantKey)
  VenworksCoreRevision = [string]$matrix.VenworksCoreFixture.Revision
  VenworksCoreSources = @($matrix.VenworksCoreFixture.SourceFiles | ForEach-Object {
    [ordered]@{
      Path = [string]$_.Path
      Sha256 = [string]$_.Sha256
    }
  })
  Scripts = @($compiled)
}
Write-CanvasUtf8WithoutBom `
  -Path (Join-Path $resolvedOutputDirectory 'compile-evidence.json') `
  -Text (($evidence | ConvertTo-Json -Depth 5) + "`n")

Write-Host -ForegroundColor Green "Compiled and inventoried $($compiled.Count) Canvas Papyrus scripts at $resolvedOutputDirectory"
