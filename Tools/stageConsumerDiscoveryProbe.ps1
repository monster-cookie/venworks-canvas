[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VwHudRepositoryPath,

  [Parameter(Mandatory = $true)]
  [string]$VenworksCoreRepositoryPath,

  [Alias('Profile')]
  [string]$ProbeProfile = 'Baseline',

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),

  [string]$PluginsDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\plugins'),

  [string]$ScriptsDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\scripts'),

  [string]$MoviesDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\movies'),

  [string]$ShipMoviesDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\ship-movies'),

  [string]$WatchMoviesDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\watch-movies'),

  [switch]$HostOnly,

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
    throw "Refusing to replace unexpected package directory: $fullPath"
  }
}

function Test-ConsumerDiscoverySamePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Left,

    [Parameter(Mandatory = $true)]
    [string]$Right
  )

  return [string]::Equals(
    [System.IO.Path]::GetFullPath($Left).TrimEnd('\', '/'),
    [System.IO.Path]::GetFullPath($Right).TrimEnd('\', '/'),
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

function Test-ConsumerDiscoveryOverlappingPaths {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Left,

    [Parameter(Mandatory = $true)]
    [string]$Right
  )

  $leftPath = [System.IO.Path]::GetFullPath($Left).TrimEnd('\', '/')
  $rightPath = [System.IO.Path]::GetFullPath($Right).TrimEnd('\', '/')
  $separator = [System.IO.Path]::DirectorySeparatorChar
  return [string]::Equals($leftPath, $rightPath, [StringComparison]::OrdinalIgnoreCase) -or
    $leftPath.StartsWith($rightPath + $separator, [StringComparison]::OrdinalIgnoreCase) -or
    $rightPath.StartsWith($leftPath + $separator, [StringComparison]::OrdinalIgnoreCase)
}

function Get-ConsumerDiscoveryJunctionTarget {
  param(
    [Parameter(Mandatory = $true)]
    [System.IO.DirectoryInfo]$Item
  )

  $targets = @($Item.Target)
  if ($targets.Count -ne 1) {
    return $null
  }
  return [System.IO.Path]::GetFullPath([string]$targets[0]).TrimEnd('\', '/')
}

function Assert-ConsumerDiscoveryJunctionTarget {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StagingPath,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedTargetPath
  )

  $stagingItem = Get-Item -LiteralPath $StagingPath -Force
  if ($stagingItem.LinkType -cne 'Junction') {
    throw "Staging path is not a Junction: $StagingPath"
  }
  $actualTargetPath = Get-ConsumerDiscoveryJunctionTarget -Item $stagingItem
  if ($null -eq $actualTargetPath -or
      !(Test-ConsumerDiscoverySamePath -Left $actualTargetPath -Right $ExpectedTargetPath)) {
    throw "Staging Junction does not target its configured physical module folder: $StagingPath"
  }
}

function Resolve-ConsumerDiscoveryArchiveTarget {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [Parameter(Mandatory = $true)]
    [string]$Target
  )

  if ([string]::IsNullOrWhiteSpace($Target) -or
      [System.IO.Path]::IsPathRooted($Target) -or
      $Target.Contains(':')) {
    throw "Archive payload target must be a non-rooted relative path: '$Target'."
  }
  $segments = $Target.Split([char[]]@('\', '/'), [System.StringSplitOptions]::None)
  if (@($segments | Where-Object { [string]::IsNullOrEmpty($_) -or $_ -ceq '.' -or $_ -ceq '..' }).Count -ne 0) {
    throw "Archive payload target contains an empty or traversal segment: '$Target'."
  }

  $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
  $fullTarget = [System.IO.Path]::GetFullPath((Join-Path $fullRoot $Target))
  $rootPrefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
  if (!$fullTarget.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Archive payload target escapes its package root: '$Target'."
  }
  return $fullTarget
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workRoot = Join-Path $repositoryRoot '.work\consumer-discovery'
$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot
$selectedStaging = @(Get-ConsumerDiscoveryStagingSelection -Matrix $matrix -HostOnly:$HostOnly)
$resolvedProfile = Resolve-ConsumerDiscoveryProfile -Matrix $matrix -ProbeProfile $ProbeProfile
$resolvedVwHudRoot = Assert-PinnedVwHudToolchainFixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
$resolvedVenworksCoreRoot = Assert-PinnedVenworksCoreFixture `
  -VenworksCoreRepositoryPath $VenworksCoreRepositoryPath `
  -Matrix $matrix
Import-ConsumerDiscoveryEnvironment -Path $EnvironmentPath
if ([string]::IsNullOrWhiteSpace($env:TOOL_PATH_ARCHIVER)) {
  throw "TOOL_PATH_ARCHIVER must be configured in $EnvironmentPath."
}
$archive2Path = Resolve-ConsumerDiscoveryExecutable `
  -Path $env:TOOL_PATH_ARCHIVER `
  -FileName 'Archive2.exe' `
  -Description 'Archive2 executable'
$resolvedPluginsDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $PluginsDirectory -Description 'Generated plugin directory'
$pluginGenerationEvidencePath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $resolvedPluginsDirectory 'generation-evidence.json') `
  -Description 'Profile-bound plugin generation evidence'
$pluginGenerationEvidence = Get-Content -LiteralPath $pluginGenerationEvidencePath -Raw | ConvertFrom-Json
if ([string]$pluginGenerationEvidence.Schema -cne 'VWCANVAS9_CONSUMER_DISCOVERY_PLUGINS/1' -or
    [string]$pluginGenerationEvidence.Profile -cne [string]$resolvedProfile.Key -or
    $pluginGenerationEvidence.BinaryReadback -ne $true -or
    @($pluginGenerationEvidence.Plugins).Count -ne @($matrix.Plugins).Count) {
  throw "Plugin generation evidence does not match selected profile '$($resolvedProfile.Key)'."
}
$pluginPathsByKey = @{}
foreach ($plugin in @($matrix.Plugins)) {
  $fileName = [string]$plugin.FileName
  $evidenceMatches = @($pluginGenerationEvidence.Plugins | Where-Object { [string]$_.FileName -ceq $fileName })
  if ($evidenceMatches.Count -ne 1) {
    throw "Plugin generation evidence does not contain exactly one '$fileName' entry."
  }
  $pluginPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedPluginsDirectory $fileName) `
    -Description "Generated plugin '$fileName'"
  $actualHash = (Get-FileHash -LiteralPath $pluginPath -Algorithm SHA256).Hash.ToUpperInvariant()
  $expectedHash = [string]$resolvedProfile.PluginSha256[[string]$plugin.Key]
  if ($expectedHash -notmatch '^[0-9A-F]{64}$' -or
      [string]$evidenceMatches[0].Sha256 -cne $expectedHash -or
      $actualHash -cne $expectedHash) {
    throw "Generated plugin '$fileName' does not match its profile-bound generation evidence."
  }
  $pluginPathsByKey[[string]$plugin.Key] = $pluginPath
}
$spriggitDumpPath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $PSScriptRoot 'dumpConsumerDiscoveryPluginsToYaml.ps1') `
  -Description 'Consumer-discovery Spriggit dump tool'
& $spriggitDumpPath `
  -ProbeProfile ([string]$resolvedProfile.Key) `
  -EnvironmentPath $EnvironmentPath `
  -PluginsDirectory $resolvedPluginsDirectory
$resolvedScriptsDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $ScriptsDirectory -Description 'Compiled Papyrus script directory'
$resolvedMoviesDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $MoviesDirectory -Description 'Built auxiliary movie directory'
$resolvedShipMoviesDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $ShipMoviesDirectory -Description 'Built Ship HUD movie directory'
$resolvedArchiveRootsDirectory = [System.IO.Path]::GetFullPath($ArchiveRootsDirectory)
$resolvedCandidateStagingDirectory = Join-Path $workRoot 'staging-candidates'
$resolvedStagingBackupDirectory = Join-Path $workRoot 'staging-backups'

$expectedStagingByKey = @{
  Host = @{ Directory = 'Staging-Host'; Plugin = 'Venworks-Canvas-Host.esm'; Archive = 'Venworks-Canvas-Host - Main.ba2' }
  ConsumerA = @{ Directory = 'Staging-ConsumerA'; Plugin = 'Venworks-Canvas-ConsumerA.esm'; Archive = 'Venworks-Canvas-ConsumerA - Main.ba2' }
  ConsumerB = @{ Directory = 'Staging-ConsumerB'; Plugin = 'Venworks-Canvas-ConsumerB.esm'; Archive = 'Venworks-Canvas-ConsumerB - Main.ba2' }
}
$expectedPhysicalTargetByKey = @{
  Host = [string]$env:MODULE_VARIANT_HOST_PATH
  ConsumerA = [string]$env:MODULE_VARIANT_CONSUMER_A_PATH
  ConsumerB = [string]$env:MODULE_VARIANT_CONSUMER_B_PATH
}
if (@($matrix.Staging).Count -ne $expectedStagingByKey.Count) {
  throw 'Staging matrix must contain exactly the three canonical package contracts.'
}
foreach ($key in @($expectedStagingByKey.Keys)) {
  $expected = $expectedStagingByKey[$key]
  $stagingMatches = @($matrix.Staging | Where-Object { [string]$_.Key -ceq $key })
  if ($stagingMatches.Count -ne 1 -or
      [string]$stagingMatches[0].Directory -cne [string]$expected.Directory -or
      [string]$stagingMatches[0].Plugin -cne [string]$expected.Plugin -or
      [string]$stagingMatches[0].Archive -cne [string]$expected.Archive) {
    throw "Staging matrix entry '$key' must match its canonical directory, plugin, and archive contract."
  }
}
$allowedStagingPaths = @($expectedStagingByKey.Values | ForEach-Object { Join-Path $repositoryRoot ([string]$_.Directory) })
foreach ($expected in @($expectedStagingByKey.Values)) {
  $stagingPath = Join-Path $repositoryRoot ([string]$expected.Directory)
  Assert-ConsumerDiscoveryStagingTarget -Path $stagingPath -AllowedPaths $allowedStagingPaths
}
$allowedPhysicalTargetPaths = [System.Collections.Generic.List[string]]::new()

# Validate disjoint targets for every package, including packages excluded by HostOnly.
$allInstallPaths = @{}
foreach ($staging in @($matrix.Staging)) {
  $path = Join-Path $repositoryRoot $staging.Directory
  $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  if ($null -ne $item -and $item.LinkType -ceq 'Junction') {
    $expectedTarget = [string]$expectedPhysicalTargetByKey[$staging.Key]
    if ([string]::IsNullOrWhiteSpace($expectedTarget)) { throw "Missing physical target for $($staging.Key)." }
    Assert-ConsumerDiscoveryJunctionTarget -StagingPath $path -ExpectedTargetPath $expectedTarget
    $path = [IO.Path]::GetFullPath($expectedTarget)
  }
  foreach ($otherPath in $allInstallPaths.Values) {
    if (Test-ConsumerDiscoveryOverlappingPaths -Left $path -Right $otherPath) { throw 'Selected and unselected package targets must be disjoint.' }
  }
  $allInstallPaths[$staging.Key] = $path
}

$consumerAMovieDefinitions = @($matrix.Movies | Where-Object {
  [string]$_.Key -ceq [string]$resolvedProfile.ConsumerAMovie
})
if ($consumerAMovieDefinitions.Count -ne 1) {
  throw "Profile '$($resolvedProfile.Key)' must select exactly one Consumer A movie definition."
}
$consumerAMoviePath = Join-Path $resolvedMoviesDirectory ([string]$consumerAMovieDefinitions[0].Output)

$payloads = @{
  Host = @(
    @{ Source = (Join-Path $resolvedMoviesDirectory 'CanvasConsumerDiscoveryHost.swf'); Target = 'Interface\venworkscui.swf' }
    @{ Source = (Join-Path $resolvedShipMoviesDirectory 'spaceshiphudmenu.swf'); Target = 'Interface\spaceshiphudmenu.swf' }
    @{ Source = (Join-Path $resolvedShipMoviesDirectory 'spaceshiphudmenu_lrg.swf'); Target = 'Interface\spaceshiphudmenu_lrg.swf' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\GlobalConfig.pex'); Target = 'Scripts\Venworks\Canvas\GlobalConfig.pex' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Enumerations.pex'); Target = 'Scripts\Venworks\Canvas\Enumerations.pex' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Base\BaseQuest.pex'); Target = 'Scripts\Venworks\Canvas\Base\BaseQuest.pex' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\Registry.pex'); Target = 'Scripts\Venworks\Canvas\Probes\ConsumerDiscovery\Registry.pex' }
  )
  ConsumerA = @(
    @{ Source = $consumerAMoviePath; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.probe.consumer-a\normal.swf' }
    @{ Source = $consumerAMoviePath; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.probe.consumer-a\large.swf' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerARegistrar.pex'); Target = 'Scripts\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerARegistrar.pex' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerAUpdateMigration.pex'); Target = 'Scripts\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerAUpdateMigration.pex' }
  )
  ConsumerB = @(
    @{ Source = (Join-Path $resolvedMoviesDirectory 'CanvasDiscoveryConsumerB.swf'); Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.probe.consumer-b\normal.swf' }
    @{ Source = (Join-Path $resolvedMoviesDirectory 'CanvasDiscoveryConsumerB.swf'); Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.probe.consumer-b\large.swf' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerBRegistrar.pex'); Target = 'Scripts\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerBRegistrar.pex' }
  )
}

foreach ($coreScript in @($matrix.VenworksCoreFixture.RuntimeScripts)) {
  $payloads.Host += @{
    Source = (Join-Path $resolvedVenworksCoreRoot ([string]$coreScript.Source))
    Target = ([string]$coreScript.Target).Replace('/', '\')
  }
}

foreach ($playerHudMovie in @($matrix.VwHudFixture.PlayerHudMovies)) {
  $payloads.Host += @{
    Source = (Join-Path $resolvedVwHudRoot ([string]$playerHudMovie.Source))
    Target = ([string]$playerHudMovie.Target).Replace('/', '\')
  }
}

$resolvedPayloads = @{}
$watchEvidence = @(Get-ConsumerDiscoveryWatchMovieEvidence -RepositoryRoot $repositoryRoot `
  -VwHudRepositoryPath $resolvedVwHudRoot -MoviesDirectory ([IO.Path]::GetFullPath($WatchMoviesDirectory)) -Matrix $matrix)
foreach ($watchMovie in $watchEvidence) {
  $payloads.Host += @{ Source = $watchMovie.Source; Target = $watchMovie.Target }
}
foreach ($staging in @($matrix.Staging)) {
  $key = [string]$staging.Key
  $keyPayloads = [System.Collections.Generic.List[object]]::new()
  foreach ($payload in @($payloads[$key])) {
    $sourcePath = Resolve-ConsumerDiscoveryRequiredFile `
      -Path ([string]$payload.Source) `
      -Description "$key payload '$($payload.Target)'"
    $keyPayloads.Add([pscustomobject]@{
      Source = $sourcePath
      Target = [string]$payload.Target
    })
  }
  $resolvedPayloads[$key] = @($keyPayloads)
}

$artifactVerifierPath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $PSScriptRoot 'verifyConsumerDiscoveryProbe.ps1') `
  -Description 'Consumer-discovery artifact verifier'
$artifactVerificationArguments = @{
  ArtifactsOnly = $true
  ProbeProfile = [string]$resolvedProfile.Key
  VwHudRepositoryPath = $resolvedVwHudRoot
  VenworksCoreRepositoryPath = $resolvedVenworksCoreRoot
  MoviesDirectory = $resolvedMoviesDirectory
  ShipMoviesDirectory = $resolvedShipMoviesDirectory
  WatchMoviesDirectory = $WatchMoviesDirectory
  PluginsDirectory = $resolvedPluginsDirectory
  ScriptsDirectory = $resolvedScriptsDirectory
}
& $artifactVerifierPath @artifactVerificationArguments

foreach ($generatedDirectory in @($resolvedArchiveRootsDirectory, $resolvedCandidateStagingDirectory)) {
  if (Test-Path -LiteralPath $generatedDirectory -PathType Container) {
    Assert-ConsumerDiscoveryRemovalPath -Path $generatedDirectory -AllowedRoot $workRoot
    Remove-Item -LiteralPath $generatedDirectory -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
}
if (Test-Path -LiteralPath $resolvedStagingBackupDirectory) {
  throw "A prior staging swap backup requires inspection before another stage: $resolvedStagingBackupDirectory"
}

$stageEvidence = [System.Collections.Generic.List[object]]::new()
$candidateInputs = [System.Collections.Generic.List[object]]::new()
foreach ($staging in @($matrix.Staging)) {
  $key = [string]$staging.Key
  $selected = @($selectedStaging | Where-Object { $_.Key -ceq $key }).Count -eq 1
  $archiveRoot = Join-Path $resolvedArchiveRootsDirectory $key
  $candidateStagingPath = if ($selected) { Join-Path $resolvedCandidateStagingDirectory ([string]$staging.Directory) } else { Join-Path $repositoryRoot ([string]$staging.Directory) }
  if ($selected) {
    New-Item -ItemType Directory -Force -Path $archiveRoot, $candidateStagingPath | Out-Null
  }
  else {
    $existingNames = @(Get-ChildItem -LiteralPath $candidateStagingPath -Force | Select-Object -ExpandProperty Name | Sort-Object)
    $expectedNames = @([string]$staging.Plugin, [string]$staging.Archive | Sort-Object)
    if (($existingNames -join '|') -cne ($expectedNames -join '|')) {
      throw "$key unselected package must already contain exactly its ESM and BA2."
    }
  }
  $entries = [System.Collections.Generic.List[object]]::new()
  foreach ($payload in @($resolvedPayloads[$key])) {
    $sourcePath = [string]$payload.Source
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
    $targetPath = Resolve-ConsumerDiscoveryArchiveTarget -Root $archiveRoot -Target ([string]$payload.Target)
    $targetHash = $sourceHash
    if ($selected) {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null
      Copy-Item -LiteralPath $sourcePath -Destination $targetPath
      $targetHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToUpperInvariant()
    }
    if ($targetHash -cne $sourceHash) {
      throw "$key payload '$($payload.Target)' changed while it was copied into the archive root."
    }
    if ($selected) {
      $candidateInputs.Add([pscustomobject]@{ Path = $sourcePath; Sha256 = $sourceHash })
    }
    $entries.Add([ordered]@{
      Path = ([string]$payload.Target).Replace('\', '/')
      Sha256 = if ($selected) { $targetHash } else { $null }
    })
  }

  $pluginSource = [string]$pluginPathsByKey[$key]
  $pluginSourceHash = (Get-FileHash -LiteralPath $pluginSource -Algorithm SHA256).Hash.ToUpperInvariant()
  $pluginTarget = Join-Path $candidateStagingPath ([string]$staging.Plugin)
  if ($selected) { Copy-Item -LiteralPath $pluginSource -Destination $pluginTarget }
  $pluginTargetHash = (Get-FileHash -LiteralPath $pluginTarget -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($pluginTargetHash -cne $pluginSourceHash) {
    throw "$key plugin changed while it was copied into the candidate staging root."
  }
  $candidateInputs.Add([pscustomobject]@{ Path = $pluginSource; Sha256 = $pluginSourceHash })

  $archiveTarget = Join-Path $candidateStagingPath ([string]$staging.Archive)
  $archiveArguments = @(
    "$archiveRoot\"
    "-root=$archiveRoot\"
    "-create=$archiveTarget"
    '-format=General'
    '-compression=None'
    '-maxSizeMB=2048'
    '-excludeFilters=.*\\meta\.ini|.*\\.*\.dds|.*\\.*\.btc|.*\\.*\.esp|.*\\.*\.esm|.*\\.*\.ba2'
  )
  if ($selected) {
    & $archive2Path @archiveArguments
    if ($LASTEXITCODE -ne 0) {
      throw "Archive2 failed to build the $key archive with exit code $LASTEXITCODE."
    }
  }
  [void](Resolve-ConsumerDiscoveryRequiredFile -Path $archiveTarget -Description "$key staged archive")
  $archiveEntries = @(Get-ConsumerDiscoveryGeneralBa2Entries -Path $archiveTarget)
  if (@($archiveEntries | Where-Object { [uint32]$_.PackedSize -ne 0 }).Count -ne 0) {
    throw "$key staged archive contains compressed entries."
  }
  $actualArchivePaths = @($archiveEntries.Name | ForEach-Object { ([string]$_).Replace('\', '/').ToLowerInvariant() } | Sort-Object)
  $expectedArchivePaths = @($entries.Path | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object)
  if ($actualArchivePaths.Count -ne $expectedArchivePaths.Count -or
      [string]::Join("`n", $actualArchivePaths) -cne [string]::Join("`n", $expectedArchivePaths)) {
    throw "$key candidate archive inventory differs from its exact payload."
  }
  $entryRecordsByPath = @{}
  foreach ($entry in @($entries)) {
    $entryRecordsByPath[([string]$entry.Path).ToLowerInvariant()] = $entry
  }
  foreach ($archiveEntry in $archiveEntries) {
    $entryPath = ([string]$archiveEntry.Name).Replace('\', '/').ToLowerInvariant()
    $entryBytes = Read-ConsumerDiscoveryGeneralBa2EntryBytes -Entry $archiveEntry
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
      $entryHash = [Convert]::ToHexString($algorithm.ComputeHash($entryBytes))
    }
    finally {
      $algorithm.Dispose()
    }
    if ($selected -and $entryHash -cne [string]$entryRecordsByPath[$entryPath].Sha256) {
      throw "$key candidate archive entry '$entryPath' differs from its copied payload."
    }
    if (!$selected) {
      $entryRecordsByPath[$entryPath].Sha256 = $entryHash
    }
  }

  $stageEvidence.Add([ordered]@{
    Key = $key
    Selected = $selected
    Directory = [string]$staging.Directory
    Plugin = [ordered]@{
      File = [string]$staging.Plugin
      Sha256 = $pluginTargetHash
    }
    Archive = [ordered]@{
      File = [string]$staging.Archive
      Sha256 = (Get-FileHash -LiteralPath $archiveTarget -Algorithm SHA256).Hash.ToUpperInvariant()
      Entries = @($entries)
    }
  })
}

& $artifactVerifierPath @artifactVerificationArguments
foreach ($candidateInput in @($candidateInputs)) {
  $currentHash = (Get-FileHash -LiteralPath ([string]$candidateInput.Path) -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($currentHash -cne [string]$candidateInput.Sha256) {
    throw "A candidate package input changed before the staging swap: $($candidateInput.Path)"
  }
}

$allowedInstallPaths = @($allowedStagingPaths)
$swapOperations = [System.Collections.Generic.List[object]]::new()
foreach ($staging in $selectedStaging) {
  $key = [string]$staging.Key
  $directoryName = [string]$staging.Directory
  $stagingPath = Join-Path $repositoryRoot $directoryName
  $candidateStagingPath = Join-Path $resolvedCandidateStagingDirectory $directoryName
  $backupStagingPath = Join-Path $resolvedStagingBackupDirectory $directoryName
  Assert-ConsumerDiscoveryStagingTarget -Path $stagingPath -AllowedPaths $allowedStagingPaths
  Assert-ConsumerDiscoveryRemovalPath -Path $candidateStagingPath -AllowedRoot $workRoot
  Assert-ConsumerDiscoveryRemovalPath -Path $backupStagingPath -AllowedRoot $workRoot
  [void](Resolve-ConsumerDiscoveryRequiredDirectory -Path $candidateStagingPath -Description "$key candidate staging directory")

  $mode = 'Directory'
  $installPath = $stagingPath
  $stagingItem = Get-Item -LiteralPath $stagingPath -Force -ErrorAction SilentlyContinue
  if ($null -ne $stagingItem) {
    if (!$stagingItem.PSIsContainer) {
      throw "$key staging path is not a directory: $stagingPath"
    }
    if ($stagingItem.LinkType -eq 'Junction') {
      $mode = 'Junction'
      $physicalTargetPath = [string]$expectedPhysicalTargetByKey[$key]
      if ([string]::IsNullOrWhiteSpace($physicalTargetPath)) {
        throw "The physical module folder for '$key' is not configured in $EnvironmentPath."
      }
      $installPath = [System.IO.Path]::GetFullPath($physicalTargetPath).TrimEnd('\', '/')
      if (@($allowedPhysicalTargetPaths | Where-Object {
        Test-ConsumerDiscoveryOverlappingPaths -Left $_ -Right $installPath
      }).Count -ne 0) {
        throw "Physical module folders must be disjoint, not identical or nested: $installPath"
      }
      if (@($allowedStagingPaths | Where-Object {
        Test-ConsumerDiscoveryOverlappingPaths -Left $_ -Right $installPath
      }).Count -ne 0) {
        throw "A physical module folder cannot overlap a repository staging path: $installPath"
      }
      $expectedPhysicalTargetByKey[$key] = $installPath
      $allowedPhysicalTargetPaths.Add($installPath)
      $allowedInstallPaths += $installPath
      Assert-ConsumerDiscoveryJunctionTarget -StagingPath $stagingPath -ExpectedTargetPath $installPath
      if (!(Test-Path -LiteralPath $installPath -PathType Container)) {
        throw "$key physical module target is not a directory: $installPath"
      }
      $installItem = Get-Item -LiteralPath $installPath -Force
      if ($null -ne $installItem.LinkType) {
        throw "$key physical module target must be a real directory: $installPath"
      }
    }
    elseif ($null -ne $stagingItem.LinkType) {
      throw "$key staging path uses an unsupported link type '$($stagingItem.LinkType)': $stagingPath"
    }
  }

  Assert-ConsumerDiscoveryStagingTarget -Path $installPath -AllowedPaths $allowedInstallPaths
  if (@($swapOperations | Where-Object {
    Test-ConsumerDiscoveryOverlappingPaths -Left ([string]$_.InstallPath) -Right $installPath
  }).Count -ne 0) {
    throw "Package installation paths must be disjoint, not identical or nested: $installPath"
  }
  $swapOperations.Add([pscustomobject]@{
    Key = $key
    Mode = $mode
    StagingPath = $stagingPath
    InstallPath = $installPath
    CandidatePath = $candidateStagingPath
    BackupPath = $backupStagingPath
  })
}

New-Item -ItemType Directory -Path $resolvedStagingBackupDirectory | Out-Null
$backedUpOperations = [System.Collections.Generic.List[object]]::new()
try {
  foreach ($operation in @($swapOperations)) {
    $installItems = @(Get-ChildItem -LiteralPath $operation.InstallPath -Force)
    $candidateItems = @(Get-ChildItem -LiteralPath $operation.CandidatePath -Force)
    if (@($installItems | Where-Object { $_.PSIsContainer }).Count -ne 0 -or
        @($candidateItems | Where-Object { $_.PSIsContainer }).Count -ne 0) {
      throw "$($operation.Key) package swap accepts only the canonical root ESM and BA2 files."
    }
    $installNames = @($installItems.Name | Sort-Object)
    $candidateNames = @($candidateItems.Name | Sort-Object)
    if ($installNames.Count -ne $candidateNames.Count -or
        [string]::Join("`n", $installNames) -cne [string]::Join("`n", $candidateNames)) {
      throw "$($operation.Key) candidate and installed package file sets differ."
    }

    New-Item -ItemType Directory -Path $operation.BackupPath | Out-Null
    foreach ($installItem in $installItems) {
      Copy-Item -LiteralPath $installItem.FullName -Destination (Join-Path $operation.BackupPath $installItem.Name)
    }
    $backedUpOperations.Add($operation)

    foreach ($candidateItem in $candidateItems) {
      $destinationPath = Join-Path $operation.InstallPath $candidateItem.Name
      $temporaryPath = Join-Path $operation.InstallPath ".$($candidateItem.Name).$PID-$([guid]::NewGuid().ToString('N')).new"
      try {
        Copy-Item -LiteralPath $candidateItem.FullName -Destination $temporaryPath
        if ((Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash -cne
            (Get-FileHash -LiteralPath $candidateItem.FullName -Algorithm SHA256).Hash) {
          throw "$($operation.Key) candidate changed while copying '$($candidateItem.Name)' into its package folder."
        }
        [System.IO.File]::Move($temporaryPath, $destinationPath, $true)
      }
      finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
          Remove-Item -LiteralPath $temporaryPath -Force
        }
      }
    }

    if ($operation.Mode -ceq 'Junction') {
      Assert-ConsumerDiscoveryJunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.InstallPath
    }
  }
}
catch {
  $swapError = $_
  $rollbackErrors = [System.Collections.Generic.List[string]]::new()
  for ($index = $backedUpOperations.Count - 1; $index -ge 0; $index--) {
    $operation = $backedUpOperations[$index]
    try {
      if ($operation.Mode -ceq 'Junction') {
        Assert-ConsumerDiscoveryJunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.InstallPath
      }
      Assert-ConsumerDiscoveryStagingTarget -Path $operation.InstallPath -AllowedPaths $allowedInstallPaths
      foreach ($backupFile in @(Get-ChildItem -LiteralPath $operation.BackupPath -File)) {
        $destinationPath = Join-Path $operation.InstallPath $backupFile.Name
        $temporaryPath = Join-Path $operation.InstallPath ".$($backupFile.Name).$PID-$([guid]::NewGuid().ToString('N')).restore"
        try {
          Copy-Item -LiteralPath $backupFile.FullName -Destination $temporaryPath
          [System.IO.File]::Move($temporaryPath, $destinationPath, $true)
        }
        finally {
          if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
          }
        }
      }
    }
    catch {
      $rollbackErrors.Add("Unable to restore files in '$($operation.InstallPath)': $($_.Exception.Message)")
    }
  }
  if ($rollbackErrors.Count -ne 0) {
    throw "Unable to install selected package files, and automatic restoration was incomplete. $($swapError.Exception.Message) Rollback errors: $([string]::Join(' | ', $rollbackErrors))"
  }
  throw "Unable to install selected package files; prior ESM/BA2 files were restored without replacing their directory or Junction. $($swapError.Exception.Message)"
}

foreach ($generatedDirectory in @($resolvedCandidateStagingDirectory, $resolvedStagingBackupDirectory)) {
  if (Test-Path -LiteralPath $generatedDirectory -PathType Container) {
    Assert-ConsumerDiscoveryRemovalPath -Path $generatedDirectory -AllowedRoot $workRoot
    Remove-Item -LiteralPath $generatedDirectory -Recurse -Force
  }
}

$evidence = [ordered]@{
  Schema = 'VWCANVAS9_CONSUMER_DISCOVERY_STAGING/4'
  Profile = [string]$resolvedProfile.Key
  VwHudRevision = [string]$matrix.VwHudFixture.Revision
  VenworksCoreRevision = [string]$matrix.VenworksCoreFixture.Revision
  PluginGenerationEvidenceSha256 = (Get-FileHash -LiteralPath $pluginGenerationEvidencePath -Algorithm SHA256).Hash.ToUpperInvariant()
  Staging = @($stageEvidence)
}
Write-ConsumerDiscoveryUtf8WithoutBom `
  -Path (Join-Path $workRoot 'staging-evidence.json') `
  -Text (($evidence | ConvertTo-Json -Depth 10) + "`n")

Write-Host -ForegroundColor Green "Staged $($selectedStaging.Key -join ', ') and verified all three archive-only packages for profile '$($resolvedProfile.Key)'."
