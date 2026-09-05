[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VwHudRepositoryPath,

  [Parameter(Mandatory = $true)]
  [string]$VenworksCoreRepositoryPath,

  [Alias('Profile')]
  [string]$BuildProfile = 'Production',

  [string[]]$VariantKeys,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),

  [string]$PluginsDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\plugins'),

  [string]$ScriptsDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scripts'),

  [string]$ScaleformDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scaleform'),

  [string]$ArchiveRootsDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\archive-roots')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

function Assert-CanvasStagingTarget {
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

function Test-CanvasSamePath {
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

function Test-CanvasOverlappingPaths {
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

function Get-CanvasJunctionTarget {
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

function Assert-CanvasJunctionTarget {
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
  $actualTargetPath = Get-CanvasJunctionTarget -Item $stagingItem
  if ($null -eq $actualTargetPath -or
      !(Test-CanvasSamePath -Left $actualTargetPath -Right $ExpectedTargetPath)) {
    throw "Staging Junction does not target its configured physical module folder: $StagingPath"
  }
}

function Resolve-CanvasArchiveTarget {
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
$workRoot = Join-Path $repositoryRoot '.work\canvas'
$matrix = Get-CanvasMatrix -RepositoryRoot $repositoryRoot
$allVariants = @(Get-ModuleVariants)
$selectedVariants = @(Get-CanvasStagingSelection -VariantKeys $VariantKeys)
$resolvedProfile = Resolve-CanvasProfile -Matrix $matrix -BuildProfile $BuildProfile
$resolvedVwHudRoot = Assert-PinnedVwHudToolchainFixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
$resolvedVenworksCoreRoot = Assert-PinnedVenworksCoreFixture `
  -VenworksCoreRepositoryPath $VenworksCoreRepositoryPath `
  -Matrix $matrix
Import-CanvasEnvironment -Path $EnvironmentPath
if ([string]::IsNullOrWhiteSpace($env:TOOL_PATH_ARCHIVER)) {
  throw "TOOL_PATH_ARCHIVER must be configured in $EnvironmentPath."
}
$archive2Path = Resolve-CanvasExecutable `
  -Path $env:TOOL_PATH_ARCHIVER `
  -FileName 'Archive2.exe' `
  -Description 'Archive2 executable'
$resolvedPluginsDirectory = Resolve-CanvasRequiredDirectory -Path $PluginsDirectory -Description 'Generated plugin directory'
$pluginGenerationEvidencePath = Resolve-CanvasRequiredFile `
  -Path (Join-Path $resolvedPluginsDirectory 'generation-evidence.json') `
  -Description 'Profile-bound plugin generation evidence'
$pluginGenerationEvidence = Get-Content -LiteralPath $pluginGenerationEvidencePath -Raw | ConvertFrom-Json
if ([string]$pluginGenerationEvidence.Schema -cne 'VWCANVAS_PLUGIN_SET/1' -or
    [string]$pluginGenerationEvidence.Profile -cne [string]$resolvedProfile.Key -or
    $pluginGenerationEvidence.BinaryReadback -ne $true -or
    @($pluginGenerationEvidence.Plugins).Count -ne $allVariants.Count) {
  throw "Plugin generation evidence does not match selected profile '$($resolvedProfile.Key)'."
}
$pluginPathsByKey = @{}
foreach ($variant in $allVariants) {
  $fileName = "$($variant.PackageBaseName).esm"
  $evidenceMatches = @($pluginGenerationEvidence.Plugins | Where-Object { [string]$_.FileName -ceq $fileName })
  if ($evidenceMatches.Count -ne 1) {
    throw "Plugin generation evidence does not contain exactly one '$fileName' entry."
  }
  $pluginPath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $resolvedPluginsDirectory $fileName) `
    -Description "Generated plugin '$fileName'"
  $actualHash = (Get-FileHash -LiteralPath $pluginPath -Algorithm SHA256).Hash.ToUpperInvariant()
  $expectedHash = [string]$resolvedProfile.PluginSha256[[string]$variant.VariantKey]
  if ($expectedHash -notmatch '^[0-9A-F]{64}$' -or
      [string]$evidenceMatches[0].Sha256 -cne $expectedHash -or
      $actualHash -cne $expectedHash) {
    throw "Generated plugin '$fileName' does not match its profile-bound generation evidence."
  }
  $pluginPathsByKey[[string]$variant.VariantKey] = $pluginPath
}
$spriggitDumpPath = Resolve-CanvasRequiredFile `
  -Path (Join-Path $PSScriptRoot 'SpriggitDumpDatabaseToYaml.ps1') `
  -Description 'Canvas Spriggit dump tool'
& $spriggitDumpPath `
  -Profile ([string]$resolvedProfile.Key) `
  -VariantKeys @($allVariants.VariantKey) `
  -EnvironmentPath $EnvironmentPath `
  -PluginsDirectory $resolvedPluginsDirectory
$resolvedScriptsDirectory = Resolve-CanvasRequiredDirectory -Path $ScriptsDirectory -Description 'Compiled Papyrus script directory'
$resolvedScaleformDirectory = Resolve-CanvasRequiredDirectory -Path $ScaleformDirectory -Description 'Built Scaleform output directory'
$resolvedMoviesDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'movies') -Description 'Built Canvas movie directory'
$resolvedPlayerHudDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'player-hud') -Description 'Built Player HUD movie directory'
$resolvedShipMoviesDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'ship-hud') -Description 'Built Ship HUD movie directory'
$resolvedArchiveRootsDirectory = [System.IO.Path]::GetFullPath($ArchiveRootsDirectory)
$resolvedCandidateStagingDirectory = Join-Path $workRoot 'staging-candidates'
$resolvedStagingBackupDirectory = Join-Path $workRoot 'staging-backups'

$packages = @($allVariants | ForEach-Object {
  [pscustomobject]@{
    Key = [string]$_.VariantKey
    Directory = Split-Path -Leaf ([string]$_.StagingFolderPath)
    StagingPath = [System.IO.Path]::GetFullPath([string]$_.StagingFolderPath)
    Plugin = "$($_.PackageBaseName).esm"
    Archive = "$($_.PackageBaseName) - Main.ba2"
    EnvironmentVariableName = [string]$_.EnvironmentVariableName
  }
})
$packageByKey = @{}
$expectedPhysicalTargetByKey = @{}
foreach ($package in $packages) {
  $packageByKey[$package.Key] = $package
  $expectedPhysicalTargetByKey[$package.Key] = [Environment]::GetEnvironmentVariable($package.EnvironmentVariableName, 'Process')
}
$allowedStagingPaths = @($packages.StagingPath)
foreach ($package in $packages) {
  $stagingPath = [string]$package.StagingPath
  Assert-CanvasStagingTarget -Path $stagingPath -AllowedPaths $allowedStagingPaths
}
$allowedPhysicalTargetPaths = [System.Collections.Generic.List[string]]::new()

# Validate disjoint targets for every package, including unselected variants.
$allInstallPaths = @{}
foreach ($package in $packages) {
  $path = [string]$package.StagingPath
  $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  if ($null -ne $item -and $item.LinkType -ceq 'Junction') {
    $expectedTarget = [string]$expectedPhysicalTargetByKey[$package.Key]
    if ([string]::IsNullOrWhiteSpace($expectedTarget)) { throw "Missing physical target for $($package.Key)." }
    Assert-CanvasJunctionTarget -StagingPath $path -ExpectedTargetPath $expectedTarget
    $path = [IO.Path]::GetFullPath($expectedTarget)
  }
  foreach ($otherPath in $allInstallPaths.Values) {
    if (Test-CanvasOverlappingPaths -Left $path -Right $otherPath) { throw 'Selected and unselected package targets must be disjoint.' }
  }
  $allInstallPaths[$package.Key] = $path
}

$exampleVariant = @(Get-ModuleVariants -VariantKeys 'EXAMPLE')[0]
$exampleMoviePath = Join-Path $resolvedMoviesDirectory $exampleVariant.ScaleformOutput

$payloads = @{
  CANVAS = @(
    @{ Source = (Join-Path $resolvedMoviesDirectory 'CanvasHost.swf'); Target = 'Interface\venworkscui.swf' }
    @{ Source = (Join-Path $resolvedShipMoviesDirectory 'spaceshiphudmenu.swf'); Target = 'Interface\spaceshiphudmenu.swf' }
    @{ Source = (Join-Path $resolvedShipMoviesDirectory 'spaceshiphudmenu_lrg.swf'); Target = 'Interface\spaceshiphudmenu_lrg.swf' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\GlobalConfig.pex'); Target = 'Scripts\Venworks\Canvas\GlobalConfig.pex' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Enumerations.pex'); Target = 'Scripts\Venworks\Canvas\Enumerations.pex' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Base\BaseQuest.pex'); Target = 'Scripts\Venworks\Canvas\Base\BaseQuest.pex' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Registry.pex'); Target = 'Scripts\Venworks\Canvas\Registry.pex' }
  )
  EXAMPLE = @(
    @{ Source = $exampleMoviePath; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.example\normal.swf' }
    @{ Source = $exampleMoviePath; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.example\large.swf' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\ExampleRegistrar.pex'); Target = 'Scripts\Venworks\Canvas\ExampleRegistrar.pex' }
  )
  COMPONENTGALLERY = @(
    @{ Source = (Join-Path $resolvedMoviesDirectory 'CanvasComponentGallery.swf'); Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.component-gallery\normal.swf' }
    @{ Source = (Join-Path $resolvedMoviesDirectory 'CanvasComponentGallery.swf'); Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.component-gallery\large.swf' }
    @{ Source = (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\ComponentGalleryRegistrar.pex'); Target = 'Scripts\Venworks\Canvas\ComponentGalleryRegistrar.pex' }
  )
}

foreach ($coreScript in @($matrix.VenworksCoreFixture.RuntimeScripts)) {
  $payloads.CANVAS += @{
    Source = (Join-Path $resolvedVenworksCoreRoot ([string]$coreScript.Source))
    Target = ([string]$coreScript.Target).Replace('/', '\')
  }
}

$resolvedPayloads = @{}
$playerHudEvidence = Get-Content -LiteralPath (Join-Path $resolvedPlayerHudDirectory 'build-evidence.json') -Raw | ConvertFrom-Json
if ([string]$playerHudEvidence.Schema -cne 'VWCANVAS_PLAYER_HUD_BUILD/1' -or
    [string]$playerHudEvidence.VwHudRevision -cne [string]$matrix.VwHudFixture.Revision -or
    $playerHudEvidence.PinnedOutputs -ne $true) {
  throw 'Player HUD build evidence is not pinned to the expected VWHUD revision.'
}
foreach ($movie in @($playerHudEvidence.Movies)) {
  $payloads.CANVAS += @{
    Source = (Join-Path $resolvedPlayerHudDirectory ([string]$movie.File))
    Target = "Interface\$($movie.File)"
  }
}
foreach ($package in $packages) {
  $key = [string]$package.Key
  $keyPayloads = [System.Collections.Generic.List[object]]::new()
  foreach ($payload in @($payloads[$key])) {
    $sourcePath = Resolve-CanvasRequiredFile `
      -Path ([string]$payload.Source) `
      -Description "$key payload '$($payload.Target)'"
    $keyPayloads.Add([pscustomobject]@{
      Source = $sourcePath
      Target = [string]$payload.Target
    })
  }
  $resolvedPayloads[$key] = @($keyPayloads)
}

$artifactVerifierPath = Resolve-CanvasRequiredFile `
  -Path (Join-Path $PSScriptRoot 'verifyCanvas.ps1') `
  -Description 'Canvas artifact verifier'
$artifactVerificationArguments = @{
  ArtifactsOnly = $true
  Profile = [string]$resolvedProfile.Key
  VwHudRepositoryPath = $resolvedVwHudRoot
  VenworksCoreRepositoryPath = $resolvedVenworksCoreRoot
  ScaleformDirectory = $resolvedScaleformDirectory
  PluginsDirectory = $resolvedPluginsDirectory
  ScriptsDirectory = $resolvedScriptsDirectory
}
& $artifactVerifierPath @artifactVerificationArguments

foreach ($generatedDirectory in @($resolvedArchiveRootsDirectory, $resolvedCandidateStagingDirectory)) {
  if (Test-Path -LiteralPath $generatedDirectory -PathType Container) {
    Assert-CanvasRemovalPath -Path $generatedDirectory -AllowedRoot $workRoot
    Remove-Item -LiteralPath $generatedDirectory -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
}
if (Test-Path -LiteralPath $resolvedStagingBackupDirectory) {
  throw "A prior staging swap backup requires inspection before another stage: $resolvedStagingBackupDirectory"
}

$stageEvidence = [System.Collections.Generic.List[object]]::new()
$candidateInputs = [System.Collections.Generic.List[object]]::new()
foreach ($package in $packages) {
  $key = [string]$package.Key
  $selected = @($selectedVariants | Where-Object { $_.VariantKey -ceq $key }).Count -eq 1
  $archiveRoot = Join-Path $resolvedArchiveRootsDirectory $key
  $candidateStagingPath = if ($selected) { Join-Path $resolvedCandidateStagingDirectory ([string]$package.Directory) } else { [string]$package.StagingPath }
  if ($selected) {
    New-Item -ItemType Directory -Force -Path $archiveRoot, $candidateStagingPath | Out-Null
  }
  else {
    $existingNames = @(Get-ChildItem -LiteralPath $candidateStagingPath -Force | Select-Object -ExpandProperty Name | Sort-Object)
    $expectedNames = @([string]$package.Plugin, [string]$package.Archive | Sort-Object)
    if (($existingNames -join '|') -cne ($expectedNames -join '|')) {
      throw "$key unselected package must already contain exactly its ESM and BA2."
    }
  }
  $entries = [System.Collections.Generic.List[object]]::new()
  foreach ($payload in @($resolvedPayloads[$key])) {
    $sourcePath = [string]$payload.Source
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
    $targetPath = Resolve-CanvasArchiveTarget -Root $archiveRoot -Target ([string]$payload.Target)
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
  $pluginTarget = Join-Path $candidateStagingPath ([string]$package.Plugin)
  if ($selected) { Copy-Item -LiteralPath $pluginSource -Destination $pluginTarget }
  $pluginTargetHash = (Get-FileHash -LiteralPath $pluginTarget -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($pluginTargetHash -cne $pluginSourceHash) {
    throw "$key plugin changed while it was copied into the candidate staging root."
  }
  $candidateInputs.Add([pscustomobject]@{ Path = $pluginSource; Sha256 = $pluginSourceHash })

  $archiveTarget = Join-Path $candidateStagingPath ([string]$package.Archive)
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
  [void](Resolve-CanvasRequiredFile -Path $archiveTarget -Description "$key staged archive")
  $archiveEntries = @(Get-CanvasGeneralBa2Entries -Path $archiveTarget)
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
    $entryBytes = Read-CanvasGeneralBa2EntryBytes -Entry $archiveEntry
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
    Directory = [string]$package.Directory
    Plugin = [ordered]@{
      File = [string]$package.Plugin
      Sha256 = $pluginTargetHash
    }
    Archive = [ordered]@{
      File = [string]$package.Archive
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
foreach ($variant in $selectedVariants) {
  $key = [string]$variant.VariantKey
  $package = $packageByKey[$key]
  $directoryName = [string]$package.Directory
  $stagingPath = [string]$package.StagingPath
  $candidateStagingPath = Join-Path $resolvedCandidateStagingDirectory $directoryName
  $backupStagingPath = Join-Path $resolvedStagingBackupDirectory $directoryName
  Assert-CanvasStagingTarget -Path $stagingPath -AllowedPaths $allowedStagingPaths
  Assert-CanvasRemovalPath -Path $candidateStagingPath -AllowedRoot $workRoot
  Assert-CanvasRemovalPath -Path $backupStagingPath -AllowedRoot $workRoot
  [void](Resolve-CanvasRequiredDirectory -Path $candidateStagingPath -Description "$key candidate staging directory")

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
        Test-CanvasOverlappingPaths -Left $_ -Right $installPath
      }).Count -ne 0) {
        throw "Physical module folders must be disjoint, not identical or nested: $installPath"
      }
      if (@($allowedStagingPaths | Where-Object {
        Test-CanvasOverlappingPaths -Left $_ -Right $installPath
      }).Count -ne 0) {
        throw "A physical module folder cannot overlap a repository staging path: $installPath"
      }
      $expectedPhysicalTargetByKey[$key] = $installPath
      $allowedPhysicalTargetPaths.Add($installPath)
      $allowedInstallPaths += $installPath
      Assert-CanvasJunctionTarget -StagingPath $stagingPath -ExpectedTargetPath $installPath
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

  Assert-CanvasStagingTarget -Path $installPath -AllowedPaths $allowedInstallPaths
  if (@($swapOperations | Where-Object {
    Test-CanvasOverlappingPaths -Left ([string]$_.InstallPath) -Right $installPath
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
    $installNames = @($installItems | ForEach-Object { $_.Name } | Sort-Object)
    $candidateNames = @($candidateItems | ForEach-Object { $_.Name } | Sort-Object)
    $matchingFileSet = $installNames.Count -eq $candidateNames.Count -and
      [string]::Join("`n", $installNames) -ceq [string]::Join("`n", $candidateNames)
    if ($installNames.Count -ne 0 -and !$matchingFileSet) {
      throw "$($operation.Key) installed package must be empty or contain exactly the candidate ESM and BA2 file set."
    }
    $operation | Add-Member -NotePropertyName OriginalNames -NotePropertyValue @($installNames) -Force
    $operation | Add-Member -NotePropertyName CandidateNames -NotePropertyValue @($candidateNames) -Force

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
      Assert-CanvasJunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.InstallPath
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
        Assert-CanvasJunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.InstallPath
      }
      Assert-CanvasStagingTarget -Path $operation.InstallPath -AllowedPaths $allowedInstallPaths
      foreach ($candidateName in @($operation.CandidateNames)) {
        if ($candidateName -cnotin @($operation.OriginalNames)) {
          $candidateInstallPath = Join-Path $operation.InstallPath $candidateName
          if (Test-Path -LiteralPath $candidateInstallPath -PathType Leaf) {
            Remove-Item -LiteralPath $candidateInstallPath -Force
          }
        }
      }
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
    Assert-CanvasRemovalPath -Path $generatedDirectory -AllowedRoot $workRoot
    Remove-Item -LiteralPath $generatedDirectory -Recurse -Force
  }
}

$evidence = [ordered]@{
  Schema = 'VWCANVAS_PACKAGES/1'
  Profile = [string]$resolvedProfile.Key
  VwHudRevision = [string]$matrix.VwHudFixture.Revision
  VenworksCoreRevision = [string]$matrix.VenworksCoreFixture.Revision
  PluginGenerationEvidenceSha256 = (Get-FileHash -LiteralPath $pluginGenerationEvidencePath -Algorithm SHA256).Hash.ToUpperInvariant()
  Staging = @($stageEvidence)
}
Write-CanvasUtf8WithoutBom `
  -Path (Join-Path $workRoot 'staging-evidence.json') `
  -Text (($evidence | ConvertTo-Json -Depth 10) + "`n")

Write-Host -ForegroundColor Green "Packaged $($selectedVariants.VariantKey -join ', ') without replacing any staging directory or Junction for profile '$($resolvedProfile.Key)'."
