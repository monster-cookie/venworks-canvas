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
  $archiveRoot = Join-Path $resolvedArchiveRootsDirectory $key
  New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
  $candidateStagingPath = Join-Path $resolvedCandidateStagingDirectory ([string]$staging.Directory)
  New-Item -ItemType Directory -Force -Path $candidateStagingPath | Out-Null
  $entries = [System.Collections.Generic.List[object]]::new()
  foreach ($payload in @($resolvedPayloads[$key])) {
    $sourcePath = [string]$payload.Source
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
    $targetPath = Resolve-ConsumerDiscoveryArchiveTarget -Root $archiveRoot -Target ([string]$payload.Target)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $targetPath
    $targetHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($targetHash -cne $sourceHash) {
      throw "$key payload '$($payload.Target)' changed while it was copied into the archive root."
    }
    $candidateInputs.Add([pscustomobject]@{ Path = $sourcePath; Sha256 = $sourceHash })
    $entries.Add([ordered]@{
      Path = ([string]$payload.Target).Replace('\', '/')
      Sha256 = $targetHash
    })
  }

  $pluginSource = [string]$pluginPathsByKey[$key]
  $pluginSourceHash = (Get-FileHash -LiteralPath $pluginSource -Algorithm SHA256).Hash.ToUpperInvariant()
  $pluginTarget = Join-Path $candidateStagingPath ([string]$staging.Plugin)
  Copy-Item -LiteralPath $pluginSource -Destination $pluginTarget
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
  & $archive2Path @archiveArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Archive2 failed to build the $key archive with exit code $LASTEXITCODE."
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
  $entryHashesByPath = @{}
  foreach ($entry in @($entries)) {
    $entryHashesByPath[([string]$entry.Path).ToLowerInvariant()] = [string]$entry.Sha256
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
    if ($entryHash -cne [string]$entryHashesByPath[$entryPath]) {
      throw "$key candidate archive entry '$entryPath' differs from its copied payload."
    }
  }

  $stageEvidence.Add([ordered]@{
    Key = $key
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

New-Item -ItemType Directory -Path $resolvedStagingBackupDirectory | Out-Null
$backedUpDirectories = [System.Collections.Generic.List[string]]::new()
$installedDirectories = [System.Collections.Generic.List[string]]::new()
try {
  foreach ($staging in @($matrix.Staging)) {
    $directoryName = [string]$staging.Directory
    $stagingPath = Join-Path $repositoryRoot $directoryName
    $candidateStagingPath = Join-Path $resolvedCandidateStagingDirectory $directoryName
    $backupStagingPath = Join-Path $resolvedStagingBackupDirectory $directoryName
    if (Test-Path -LiteralPath $stagingPath -PathType Container) {
      Move-Item -LiteralPath $stagingPath -Destination $backupStagingPath
      $backedUpDirectories.Add($directoryName)
    }
    Move-Item -LiteralPath $candidateStagingPath -Destination $stagingPath
    $installedDirectories.Add($directoryName)
  }
}
catch {
  $swapError = $_
  foreach ($directoryName in @($installedDirectories)) {
    $stagingPath = Join-Path $repositoryRoot $directoryName
    if (Test-Path -LiteralPath $stagingPath -PathType Container) {
      Assert-ConsumerDiscoveryStagingTarget -Path $stagingPath -AllowedPaths $allowedStagingPaths
      Remove-Item -LiteralPath $stagingPath -Recurse -Force
    }
  }
  foreach ($directoryName in @($backedUpDirectories)) {
    $stagingPath = Join-Path $repositoryRoot $directoryName
    $backupStagingPath = Join-Path $resolvedStagingBackupDirectory $directoryName
    if (Test-Path -LiteralPath $backupStagingPath -PathType Container) {
      Move-Item -LiteralPath $backupStagingPath -Destination $stagingPath
    }
  }
  throw "Unable to install all three staged packages; prior staging roots were restored. $($swapError.Exception.Message)"
}

foreach ($generatedDirectory in @($resolvedCandidateStagingDirectory, $resolvedStagingBackupDirectory)) {
  if (Test-Path -LiteralPath $generatedDirectory -PathType Container) {
    Assert-ConsumerDiscoveryRemovalPath -Path $generatedDirectory -AllowedRoot $workRoot
    Remove-Item -LiteralPath $generatedDirectory -Recurse -Force
  }
}

$evidence = [ordered]@{
  Schema = 'VWCANVAS9_CONSUMER_DISCOVERY_STAGING/3'
  Profile = [string]$resolvedProfile.Key
  VwHudRevision = [string]$matrix.VwHudFixture.Revision
  VenworksCoreRevision = [string]$matrix.VenworksCoreFixture.Revision
  PluginGenerationEvidenceSha256 = (Get-FileHash -LiteralPath $pluginGenerationEvidencePath -Algorithm SHA256).Hash.ToUpperInvariant()
  Staging = @($stageEvidence)
}
Write-ConsumerDiscoveryUtf8WithoutBom `
  -Path (Join-Path $workRoot 'staging-evidence.json') `
  -Text (($evidence | ConvertTo-Json -Depth 10) + "`n")

Write-Host -ForegroundColor Green "Created the exact Host, ConsumerA, and ConsumerB archive-only staging roots for profile '$($resolvedProfile.Key)'."
