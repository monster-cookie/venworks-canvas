[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VwHudRepositoryPath,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),

  [string]$PluginsDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\plugins'),

  [string]$ScriptsDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\scripts'),

  [string]$MoviesDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\movies'),

  [string]$ShipMoviesDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\ship-movies'),

  [string]$ArchiveRootsDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\archive-roots')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')

function Assert-ConsumerDiscoveryStagingTarget {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string[]]$AllowedPaths
  )

  $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
  $allowed = @($AllowedPaths | ForEach-Object { [System.IO.Path]::GetFullPath($_).TrimEnd('\', '/') })
  if ($fullPath -notin $allowed) {
    throw "Refusing to replace unexpected staging directory: $fullPath"
  }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workRoot = Join-Path $repositoryRoot '.work\consumer-discovery'
$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot
$resolvedVwHudRoot = Assert-VwHudV2Fixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
Import-ConsumerDiscoveryEnvironment -Path $EnvironmentPath
if ([string]::IsNullOrWhiteSpace($env:TOOL_PATH_ARCHIVER)) {
  throw "TOOL_PATH_ARCHIVER must be configured in $EnvironmentPath."
}
$archive2Path = Resolve-ConsumerDiscoveryExecutable `
  -Path $env:TOOL_PATH_ARCHIVER `
  -FileName 'Archive2.exe' `
  -Description 'Archive2 executable'
$resolvedPluginsDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $PluginsDirectory -Description 'Generated plugin directory'
$resolvedScriptsDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $ScriptsDirectory -Description 'Compiled Papyrus script directory'
$resolvedMoviesDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $MoviesDirectory -Description 'Built auxiliary movie directory'
$resolvedShipMoviesDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $ShipMoviesDirectory -Description 'Built Ship HUD movie directory'
$resolvedArchiveRootsDirectory = [System.IO.Path]::GetFullPath($ArchiveRootsDirectory)

if (Test-Path -LiteralPath $resolvedArchiveRootsDirectory -PathType Container) {
  Assert-ConsumerDiscoveryRemovalPath -Path $resolvedArchiveRootsDirectory -AllowedRoot $workRoot
  Remove-Item -LiteralPath $resolvedArchiveRootsDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $resolvedArchiveRootsDirectory | Out-Null

$allowedStagingPaths = @($matrix.Staging | ForEach-Object { Join-Path $repositoryRoot ([string]$_.Directory) })
foreach ($staging in @($matrix.Staging)) {
  $stagingPath = Join-Path $repositoryRoot ([string]$staging.Directory)
  Assert-ConsumerDiscoveryStagingTarget -Path $stagingPath -AllowedPaths $allowedStagingPaths
  if (Test-Path -LiteralPath $stagingPath -PathType Container) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $stagingPath | Out-Null
}

$payloads = @{
  Host = @(
    @{ Source = (Join-Path $resolvedMoviesDirectory 'CanvasConsumerDiscoveryHost.swf'); Target = 'Interface\venworkscui.swf' }
    @{ Source = (Join-Path $resolvedShipMoviesDirectory 'spaceshiphudmenu.swf'); Target = 'Interface\spaceshiphudmenu.swf' }
    @{ Source = (Join-Path $resolvedShipMoviesDirectory 'spaceshiphudmenu_lrg.swf'); Target = 'Interface\spaceshiphudmenu_lrg.swf' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\Registry.pex'); Target = 'Scripts\Venworks\Canvas\Probes\ConsumerDiscovery\Registry.pex' }
  )
  ConsumerA = @(
    @{ Source = (Join-Path $resolvedMoviesDirectory 'CanvasDiscoveryConsumerA.swf'); Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.probe.consumer-a\normal.swf' }
    @{ Source = (Join-Path $resolvedMoviesDirectory 'CanvasDiscoveryConsumerA.swf'); Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.probe.consumer-a\large.swf' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerARegistrar.pex'); Target = 'Scripts\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerARegistrar.pex' }
  )
  ConsumerB = @(
    @{ Source = (Join-Path $resolvedMoviesDirectory 'CanvasDiscoveryConsumerB.swf'); Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.probe.consumer-b\normal.swf' }
    @{ Source = (Join-Path $resolvedMoviesDirectory 'CanvasDiscoveryConsumerB.swf'); Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.probe.consumer-b\large.swf' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerBRegistrar.pex'); Target = 'Scripts\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerBRegistrar.pex' }
  )
}

foreach ($playerHudMovie in @($matrix.VwHudFixture.PlayerHudMovies)) {
  $payloads.Host += @{
    Source = (Join-Path $resolvedVwHudRoot ([string]$playerHudMovie.Source))
    Target = ([string]$playerHudMovie.Target).Replace('/', '\')
  }
}

$stageEvidence = [System.Collections.Generic.List[object]]::new()
foreach ($staging in @($matrix.Staging)) {
  $key = [string]$staging.Key
  $archiveRoot = Join-Path $resolvedArchiveRootsDirectory $key
  New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
  $entries = [System.Collections.Generic.List[object]]::new()
  foreach ($payload in @($payloads[$key])) {
    $sourcePath = Resolve-ConsumerDiscoveryRequiredFile `
      -Path ([string]$payload.Source) `
      -Description "$key payload '$($payload.Target)'"
    $targetPath = Join-Path $archiveRoot ([string]$payload.Target)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $targetPath
    $entries.Add([ordered]@{
      Path = ([string]$payload.Target).Replace('\', '/')
      Sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
    })
  }

  $stagingPath = Join-Path $repositoryRoot ([string]$staging.Directory)
  $pluginSource = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedPluginsDirectory ([string]$staging.Plugin)) `
    -Description "$key generated plugin"
  $pluginTarget = Join-Path $stagingPath ([string]$staging.Plugin)
  Copy-Item -LiteralPath $pluginSource -Destination $pluginTarget

  $archiveTarget = Join-Path $stagingPath ([string]$staging.Archive)
  $archiveArguments = @(
    "$archiveRoot\"
    "-root=$archiveRoot\"
    "-create=$archiveTarget"
    '-format=General'
    '-compression=None'
    '-maxSizeMB=2048'
    '-excludeFilters=.*\\meta\.ini|.*\\.*\.dds|.*\\.*\.btc|.*\\.*\.esp|.*\\.*\.esm|.*\\.*\.ba2'
  )
  & $archive2Path @archiveArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Archive2 failed to build the $key archive with exit code $LASTEXITCODE."
  }
  [void](Resolve-ConsumerDiscoveryRequiredFile -Path $archiveTarget -Description "$key staged archive")
  $archiveEntries = @(Get-ConsumerDiscoveryGeneralBa2Entries -Path $archiveTarget)
  if (@($archiveEntries | Where-Object { [uint32]$_.PackedSize -ne 0 }).Count -ne 0) {
    throw "$key staged archive contains compressed entries."
  }

  $stageEvidence.Add([ordered]@{
    Key = $key
    Directory = [string]$staging.Directory
    Plugin = [ordered]@{
      File = [string]$staging.Plugin
      Sha256 = (Get-FileHash -LiteralPath $pluginTarget -Algorithm SHA256).Hash.ToUpperInvariant()
    }
    Archive = [ordered]@{
      File = [string]$staging.Archive
      Sha256 = (Get-FileHash -LiteralPath $archiveTarget -Algorithm SHA256).Hash.ToUpperInvariant()
      Entries = @($entries)
    }
  })
}

$evidence = [ordered]@{
  Schema = 'VWCANVAS9_CONSUMER_DISCOVERY_STAGING/1'
  VwHudRevision = [string]$matrix.VwHudFixture.Revision
  Staging = @($stageEvidence)
}
Write-ConsumerDiscoveryUtf8WithoutBom `
  -Path (Join-Path $workRoot 'staging-evidence.json') `
  -Text (($evidence | ConvertTo-Json -Depth 10) + "`n")

Write-Host -ForegroundColor Green 'Created the exact Host, ConsumerA, and ConsumerB archive-only staging roots.'
