[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VenworksCoreRepositoryPath,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),

  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\scripts')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workRoot = Join-Path $repositoryRoot '.work\consumer-discovery'
$sourceRoot = Join-Path $repositoryRoot 'Papyrus'
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot
$resolvedVenworksCoreRoot = Assert-PinnedVenworksCoreFixture `
  -VenworksCoreRepositoryPath $VenworksCoreRepositoryPath `
  -Matrix $matrix
$venworksCoreSourceRoot = Join-Path $resolvedVenworksCoreRoot 'Papyrus'
Import-ConsumerDiscoveryEnvironment -Path $EnvironmentPath

foreach ($requiredName in @('TOOL_PATH_PAPYRUS_COMPILER', 'PAPYRUS_COMPILER_FLAGS', 'PAPYRUS_SCRIPTS_SOURCE_PATH')) {
  $value = [Environment]::GetEnvironmentVariable($requiredName, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "$requiredName must be configured in $EnvironmentPath."
  }
}

$compilerPath = Resolve-ConsumerDiscoveryExecutable `
  -Path $env:TOOL_PATH_PAPYRUS_COMPILER `
  -FileName 'PapyrusCompiler.exe' `
  -Description 'Starfield Papyrus compiler'
$flagsPath = $env:PAPYRUS_COMPILER_FLAGS
if (Test-Path -LiteralPath $flagsPath -PathType Container) {
  $flagsPath = Join-Path $flagsPath 'Starfield_Papyrus_Flags.flg'
}
$resolvedFlagsPath = Resolve-ConsumerDiscoveryRequiredFile -Path $flagsPath -Description 'Starfield Papyrus flags file'
$resolvedGameSourcePath = Resolve-ConsumerDiscoveryRequiredDirectory `
  -Path $env:PAPYRUS_SCRIPTS_SOURCE_PATH `
  -Description 'Starfield Papyrus source directory'

if (Test-Path -LiteralPath $resolvedOutputDirectory -PathType Container) {
  Assert-ConsumerDiscoveryRemovalPath -Path $resolvedOutputDirectory -AllowedRoot $workRoot
  Remove-Item -LiteralPath $resolvedOutputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory | Out-Null

$sources = @(
  'Venworks\Canvas\GlobalConfig.psc'
  'Venworks\Canvas\Enumerations.psc'
  'Venworks\Canvas\Base\BaseQuest.psc'
  'Venworks\Canvas\Probes\ConsumerDiscovery\Registry.psc'
  'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerARegistrar.psc'
  'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerBRegistrar.psc'
  'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerAUpdateMigration.psc'
)
$sourcePaths = @{}
$sourceHashes = @{}
foreach ($relativeSource in $sources) {
  $sourcePath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $sourceRoot $relativeSource) `
    -Description "Consumer-discovery Papyrus source '$relativeSource'"
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
  $outputPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedOutputDirectory $outputName) `
    -Description "Compiled Papyrus script '$outputName'"
  if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $sourceSha256Before) {
    throw "Consumer-discovery Papyrus source changed during compilation: $relativeSource"
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
    throw "Consumer-discovery Papyrus source changed during the complete compile: $relativeSource"
  }
}

$evidence = [ordered]@{
  Schema = 'VWCANVAS9_CONSUMER_DISCOVERY_SCRIPTS/1'
  CompilerVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($compilerPath).FileVersion
  VenworksCoreRevision = [string]$matrix.VenworksCoreFixture.Revision
  VenworksCoreSources = @($matrix.VenworksCoreFixture.SourceFiles | ForEach-Object {
    [ordered]@{
      Path = [string]$_.Path
      Sha256 = [string]$_.Sha256
    }
  })
  Scripts = @($compiled)
}
Write-ConsumerDiscoveryUtf8WithoutBom `
  -Path (Join-Path $resolvedOutputDirectory 'compile-evidence.json') `
  -Text (($evidence | ConvertTo-Json -Depth 5) + "`n")

Write-Host -ForegroundColor Green "Compiled and inventoried $($compiled.Count) consumer-discovery Papyrus scripts at $resolvedOutputDirectory"
