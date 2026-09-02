[CmdletBinding()]
param(
  [switch]$SourceOnly,

  [string]$VwHudRepositoryPath,

  [string]$MoviesDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\movies'),

  [string]$LooseDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\loose'),

  [string]$PackagesDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\packages')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')

function Assert-ExactRelativeFileInventory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [Parameter(Mandatory = $true)]
    [string[]]$Expected,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  $resolvedRoot = Resolve-ConsumerDiscoveryRequiredDirectory -Path $Root -Description $Description
  $actual = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File | ForEach-Object {
    $_.FullName.Substring($resolvedRoot.Length + 1).Replace('\', '/')
  } | Sort-Object)
  $sortedExpected = @($Expected | Sort-Object)
  if ($actual.Count -ne $sortedExpected.Count -or
      [string]::Join("`n", $actual) -cne [string]::Join("`n", $sortedExpected)) {
    throw "$Description has an unexpected file inventory. Expected '$([string]::Join(', ', $sortedExpected))'; found '$([string]::Join(', ', $actual))'."
  }
}

function Get-BytesSha256 {
  param(
    [Parameter(Mandatory = $true)]
    [byte[]]$Bytes
  )

  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '')
  }
  finally {
    $algorithm.Dispose()
  }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$probeRoot = Join-Path $repositoryRoot 'Scaleform\probes\consumer-discovery'
$actionScriptRoot = Join-Path $probeRoot 'actionscript'
$buildRoot = Join-Path $probeRoot 'build'
$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot

$expectedActionScriptFiles = @(
  'CanvasConsumerDiscoveryHost.as'
  'CanvasDiscoveryConsumerA.as'
  'CanvasDiscoveryConsumerAUpdate.as'
  'CanvasDiscoveryConsumerB.as'
  'CanvasDiscoveryConsumerInvalid.as'
)
$expectedBuildFiles = @(
  'consumer-a-update.build.xml'
  'consumer-a.build.xml'
  'consumer-b.build.xml'
  'consumer-invalid.build.xml'
  'host.build.xml'
)
Assert-ExactRelativeFileInventory `
  -Root $actionScriptRoot `
  -Expected $expectedActionScriptFiles `
  -Description 'Consumer-discovery ActionScript source directory'
Assert-ExactRelativeFileInventory `
  -Root $buildRoot `
  -Expected $expectedBuildFiles `
  -Description 'Consumer-discovery build manifest directory'

if ([int]$matrix.Version -ne 1 -or [string]$matrix.Protocol -cne 'VWCANVAS_DISCOVERY_PROBE/1') {
  throw 'Consumer-discovery matrix has an unsupported version or protocol.'
}
if ([string]$matrix.VwHudFixture.Revision -notmatch '^[0-9a-f]{40}$') {
  throw 'Consumer-discovery matrix must pin one complete lowercase VWHUD revision.'
}
$requiredV2Files = @(
  'Tools/buildVariantV2.ps1'
  'Tools/compileScaleformAuxiliaryV2.ps1'
  'Tools/createPackagesV2.ps1'
  'Tools/sharedScaleformMovies.ps1'
) | Sort-Object
$matrixV2Files = @($matrix.VwHudFixture.RequiredPipelineFiles | Sort-Object)
if ([string]::Join("`n", $requiredV2Files) -cne [string]::Join("`n", $matrixV2Files)) {
  throw 'Consumer-discovery matrix does not pin the exact required VWHUD v2 pipeline files.'
}
if (@($matrix.VwHudFixture.HostMovies).Count -ne 4) {
  throw 'Consumer-discovery matrix must pin exactly four normal/large VWHUD PS5DBG host movies.'
}

$movieKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$movieOutputs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($movie in @($matrix.Movies)) {
  if (!$movieKeys.Add([string]$movie.Key)) {
    throw "Consumer-discovery matrix contains duplicate movie key '$($movie.Key)'."
  }
  if (!$movieOutputs.Add([string]$movie.Output)) {
    throw "Consumer-discovery matrix contains duplicate movie output '$($movie.Output)'."
  }
  $definition = Get-ConsumerDiscoveryBuildDefinition `
    -ManifestPath (Join-Path $probeRoot ([string]$movie.Manifest))
  if ($definition.OutputFile -cne [string]$movie.Output) {
    throw "Movie '$($movie.Key)' output does not match its manifest."
  }
  $sourceText = [System.IO.File]::ReadAllText($definition.SourcePath)
  $classMatches = @([regex]::Matches(
    $sourceText,
    '(?m)^\s*public\s+final\s+class\s+([A-Za-z_][A-Za-z0-9_]*)\b'
  ))
  if ($classMatches.Count -ne 1 -or [string]$classMatches[0].Groups[1].Value -cne $definition.ClassName) {
    throw "Movie '$($movie.Key)' source does not declare exactly its manifest class '$($definition.ClassName)'."
  }
  foreach ($requiredToken in @($definition.RequiredTokens)) {
    if (!$sourceText.Contains([string]$requiredToken)) {
      throw "Movie '$($movie.Key)' source is missing required token '$requiredToken'."
    }
  }
  foreach ($forbiddenToken in @($definition.ForbiddenTokens)) {
    if ($sourceText.Contains([string]$forbiddenToken)) {
      throw "Movie '$($movie.Key)' source contains forbidden token '$forbiddenToken'."
    }
  }
}
if ($movieKeys.Count -ne 5) {
  throw 'Consumer-discovery matrix must define exactly five single-class probe movies.'
}

$hostSource = [System.IO.File]::ReadAllText((Join-Path $actionScriptRoot 'CanvasConsumerDiscoveryHost.as'))
foreach ($token in @(
  'private static const SLOT_COUNT:int = 4;',
  'this.currentSlot++',
  'this.discoverNextSlot();',
  'removeEventListener(Event.REMOVED_FROM_STAGE',
  'contentLoaderInfo.removeEventListener(Event.INIT',
  'contentLoaderInfo.removeEventListener(Event.COMPLETE',
  'contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR',
  'contentLoaderInfo.removeEventListener(SecurityErrorEvent.SECURITY_ERROR',
  'loader.unload()',
  'bridge["dispose"]()'
)) {
  if (!$hostSource.Contains($token)) {
    throw "Consumer-discovery host is missing bounded discovery or teardown token '$token'."
  }
}
foreach ($forbiddenHostToken in @('URLLoader', 'XML(', 'XMLList', 'getDirectoryListing', 'FileReference', 'Game.ShowCustomWatchAlert', 'CustomAlertsData')) {
  if ($hostSource.Contains($forbiddenHostToken)) {
    throw "Consumer-discovery host contains forbidden transport, parser, or enumeration token '$forbiddenHostToken'."
  }
}

$slots = @($matrix.Slots | Sort-Object { [int]$_.Index })
if ($slots.Count -ne 4) {
  throw 'Consumer-discovery matrix must define exactly four bounded slots.'
}
for ($index = 0; $index -lt $slots.Count; $index++) {
  $expectedName = 'slot-{0:D2}' -f $index
  if ([int]$slots[$index].Index -ne $index -or [string]$slots[$index].Name -cne $expectedName) {
    throw "Consumer-discovery slot $index is not the expected fixed slot '$expectedName'."
  }
  foreach ($path in @([string]$slots[$index].NormalPath, [string]$slots[$index].LargePath)) {
    if ($path -notmatch '^Interface/VenworksCanvas/Consumers/(?:normal|large)/slot-[0-9]{2}\.swf$') {
      throw "Consumer-discovery slot path is outside the fixed Canvas namespace: $path"
    }
  }
}

$packageKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$packageNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($package in @($matrix.Packages)) {
  if (!$packageKeys.Add([string]$package.Key) -or !$packageNames.Add([string]$package.BaseName)) {
    throw 'Consumer-discovery package keys and base names must be unique.'
  }
  if (!$movieKeys.Contains([string]$package.MovieKey)) {
    throw "Package '$($package.Key)' references unknown movie '$($package.MovieKey)'."
  }
}
$expectedPackageKeys = [string[]]@('Host', 'A1', 'A2', 'B1', 'Invalid')
if ($packageKeys.Count -ne 5 -or !$packageKeys.SetEquals($expectedPackageKeys)) {
  throw 'Consumer-discovery matrix must define the exact Host, A1, A2, B1, and Invalid package set.'
}

$runtimeCases = @($matrix.RuntimeCases)
foreach ($requiredCase in @(
  'pc-loose-host-only',
  'pc-archive-collision-a1-wins',
  'pc-archive-collision-a2-wins',
  'pc-archive-invalid-then-b1',
  'pc-archive-normal-large',
  'pc-archive-teardown',
  'ps5-vwhud-baseline',
  'ps5-host-missing',
  'ps5-collision',
  'ps5-normal-large',
  'ps5-teardown'
)) {
  if (@($runtimeCases | Where-Object { [string]$_.Id -ceq $requiredCase }).Count -ne 1) {
    throw "Consumer-discovery runtime matrix is missing exact case '$requiredCase'."
  }
}
foreach ($runtimeCase in $runtimeCases) {
  if ([string]$runtimeCase.Platform -notin @('PC', 'PS5') -or
      [string]$runtimeCase.Shape -notin @('Loose', 'Archive') -or
      [string]::IsNullOrWhiteSpace([string]$runtimeCase.Expected)) {
    throw "Runtime case '$($runtimeCase.Id)' has an invalid platform, shape, or expectation."
  }
  foreach ($packageKey in @($runtimeCase.Packages)) {
    if (!$packageKeys.Contains([string]$packageKey)) {
      throw "Runtime case '$($runtimeCase.Id)' references unknown package '$packageKey'."
    }
  }
}

$toolPaths = @(
  'Tools\sharedConsumerDiscoveryProbe.ps1'
  'Tools\buildConsumerDiscoveryProbe.ps1'
  'Tools\createConsumerDiscoveryProbePackages.ps1'
  'Tools\verifyConsumerDiscoveryProbe.ps1'
)
foreach ($toolRelativePath in $toolPaths) {
  $toolPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $repositoryRoot $toolRelativePath) `
    -Description "Consumer-discovery tool '$toolRelativePath'"
  $tokens = $null
  $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile(
    $toolPath,
    [ref]$tokens,
    [ref]$parseErrors
  )
  if (@($parseErrors).Count -ne 0) {
    throw "Consumer-discovery tool '$toolRelativePath' has PowerShell parse errors: $([string]::Join('; ', @($parseErrors.Message)))"
  }
}
$allToolText = [string]::Join("`n", @($toolPaths | ForEach-Object {
  [System.IO.File]::ReadAllText((Join-Path $repositoryRoot $_))
}))
if ($allToolText -match '(?<!V2)compileScaleformAuxiliary\.ps1') {
  throw 'Consumer-discovery tooling references the legacy VWHUD auxiliary compiler.'
}
if (!$allToolText.Contains('sharedScaleformMovies.ps1') -or
    !$allToolText.Contains("'-compression=None'")) {
  throw 'Consumer-discovery tooling does not retain the required VWHUD v2 movie helper and uncompressed General archive contract.'
}

Write-Host -ForegroundColor Green 'Verified consumer-discovery source contracts, bounded fixed slots, runtime matrix, and PowerShell syntax.'
if ($SourceOnly) {
  return
}

if ([string]::IsNullOrWhiteSpace($VwHudRepositoryPath)) {
  throw 'VwHudRepositoryPath is required for full consumer-discovery verification.'
}
$resolvedVwHudRoot = Assert-VwHudV2Fixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
$hostMovieEvidence = @(Get-VwHudHostMovieEvidence -VwHudRepositoryPath $resolvedVwHudRoot -Matrix $matrix)
$sharedMovieScript = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $resolvedVwHudRoot 'Tools\sharedScaleformMovies.ps1') `
  -Description 'VWHUD v2 shared Scaleform movie helper'
. $sharedMovieScript

$resolvedMoviesDirectory = Resolve-ConsumerDiscoveryRequiredDirectory `
  -Path $MoviesDirectory `
  -Description 'Built consumer-discovery movie directory'
$expectedMovieInventory = @('build-evidence.json')
foreach ($movie in @($matrix.Movies)) {
  $expectedMovieInventory += [string]$movie.Output
  $expectedMovieInventory += "$($movie.Output).sha256"
  $expectedMovieInventory += "$($movie.Output).classes.txt"
}
Assert-ExactRelativeFileInventory `
  -Root $resolvedMoviesDirectory `
  -Expected $expectedMovieInventory `
  -Description 'Built consumer-discovery movie directory'

$buildEvidencePath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $resolvedMoviesDirectory 'build-evidence.json') `
  -Description 'Consumer-discovery build evidence'
$buildEvidence = Get-Content -LiteralPath $buildEvidencePath -Raw | ConvertFrom-Json
if ([string]$buildEvidence.Schema -cne 'VWCANVAS9_CONSUMER_DISCOVERY_BUILD/1' -or
    [string]$buildEvidence.VwHudRevision -cne [string]$matrix.VwHudFixture.Revision) {
  throw 'Consumer-discovery build evidence has an unexpected schema or VWHUD revision.'
}

$movieHashByKey = @{}
foreach ($movie in @($matrix.Movies)) {
  $moviePath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedMoviesDirectory ([string]$movie.Output)) `
    -Description "Built movie '$($movie.Key)'"
  Assert-ScaleformMovieEncoding `
    -Path $moviePath `
    -Context "Built movie '$($movie.Key)'" `
    -ExpectedSignature CWS
  $actualHash = (Get-FileHash -LiteralPath $moviePath -Algorithm SHA256).Hash.ToUpperInvariant()
  $sidecarHash = [System.IO.File]::ReadAllText("$moviePath.sha256").Trim().ToUpperInvariant()
  $evidenceRecord = @($buildEvidence.Movies | Where-Object { [string]$_.OutputFile -ceq [string]$movie.Output })
  if ($actualHash -cne $sidecarHash -or
      $evidenceRecord.Count -ne 1 -or
      [string]$evidenceRecord[0].Sha256 -cne $actualHash -or
      [int]$evidenceRecord[0].BuildPasses -ne 2) {
    throw "Built movie '$($movie.Key)' hash or deterministic-pass evidence does not match."
  }
  $movieHashByKey[[string]$movie.Key] = $actualHash
}

$resolvedPackagesDirectory = Resolve-ConsumerDiscoveryRequiredDirectory `
  -Path $PackagesDirectory `
  -Description 'Consumer-discovery package directory'
$resolvedLooseDirectory = Resolve-ConsumerDiscoveryRequiredDirectory `
  -Path $LooseDirectory `
  -Description 'Consumer-discovery loose package directory'
$packageEvidencePath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $resolvedPackagesDirectory 'package-evidence.json') `
  -Description 'Consumer-discovery package evidence'
$packageEvidence = Get-Content -LiteralPath $packageEvidencePath -Raw | ConvertFrom-Json
if ([string]$packageEvidence.Schema -cne 'VWCANVAS9_CONSUMER_DISCOVERY_PACKAGES/1' -or
    [string]$packageEvidence.VwHudRevision -cne [string]$matrix.VwHudFixture.Revision) {
  throw 'Consumer-discovery package evidence has an unexpected schema or VWHUD revision.'
}

$actualPackageDirectories = @(Get-ChildItem -LiteralPath $resolvedPackagesDirectory -Directory | Select-Object -ExpandProperty Name | Sort-Object)
$actualLooseDirectories = @(Get-ChildItem -LiteralPath $resolvedLooseDirectory -Directory | Select-Object -ExpandProperty Name | Sort-Object)
$expectedPackageDirectories = @($matrix.Packages.Key | Sort-Object)
if ([string]::Join("`n", $actualPackageDirectories) -cne [string]::Join("`n", $expectedPackageDirectories)) {
  throw 'Consumer-discovery package directory contains an unexpected package set.'
}
if ([string]::Join("`n", $actualLooseDirectories) -cne [string]::Join("`n", $expectedPackageDirectories)) {
  throw 'Consumer-discovery loose directory contains an unexpected package set.'
}
if (@(Get-ChildItem -LiteralPath $resolvedPackagesDirectory -Directory -Recurse | Where-Object { $_.Name -ceq 'Interface' }).Count -ne 0) {
  throw 'Consumer-discovery package output contains a loose Interface shadow.'
}

$pluginSourcePath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $repositoryRoot 'Staging\Venworks-Canvas.esm') `
  -Description 'Canvas probe plugin source'
$pluginSourceHash = (Get-FileHash -LiteralPath $pluginSourcePath -Algorithm SHA256).Hash.ToUpperInvariant()

foreach ($package in @($matrix.Packages)) {
  $packageKey = [string]$package.Key
  $packagePath = Join-Path $resolvedPackagesDirectory $packageKey
  $baseName = [string]$package.BaseName
  Assert-ExactRelativeFileInventory `
    -Root $packagePath `
    -Expected @(
      "$baseName - Main.ba2"
      "$baseName - Main_PS.ba2"
      "$baseName.esm"
    ) `
    -Description "Consumer-discovery package '$packageKey'"
  $pluginPath = Join-Path $packagePath "$baseName.esm"
  if ((Get-FileHash -LiteralPath $pluginPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $pluginSourceHash) {
    throw "Consumer-discovery package '$packageKey' plugin copy does not match the Canvas source plugin."
  }

  $expectedEntryHashes = @{}
  $expectedLooseHashes = @{}
  if ([string]$package.Role -ceq 'Host') {
    foreach ($hostMovie in $hostMovieEvidence) {
      $target = [string]$hostMovie.Target
      $expectedEntryHashes[$target.ToLowerInvariant()] = [string]$hostMovie.Sha256
      $expectedLooseHashes[$target] = [string]$hostMovie.Sha256
    }
    $expectedEntryHashes['interface/venworkscui.swf'] = $movieHashByKey['Host']
    $expectedLooseHashes['Interface/venworkscui.swf'] = $movieHashByKey['Host']
  }
  else {
    $slot = @($matrix.Slots | Where-Object { [int]$_.Index -eq [int]$package.Slot })
    if ($slot.Count -ne 1) {
      throw "Consumer-discovery package '$packageKey' does not resolve exactly one slot."
    }
    $expectedEntryHashes[([string]$slot[0].NormalPath).ToLowerInvariant()] = $movieHashByKey[[string]$package.MovieKey]
    $expectedEntryHashes[([string]$slot[0].LargePath).ToLowerInvariant()] = $movieHashByKey[[string]$package.MovieKey]
    $expectedLooseHashes[[string]$slot[0].NormalPath] = $movieHashByKey[[string]$package.MovieKey]
    $expectedLooseHashes[[string]$slot[0].LargePath] = $movieHashByKey[[string]$package.MovieKey]
  }

  $expectedLooseHashes["$baseName.esm"] = $pluginSourceHash
  $loosePackagePath = Join-Path $resolvedLooseDirectory $packageKey
  Assert-ExactRelativeFileInventory `
    -Root $loosePackagePath `
    -Expected @($expectedLooseHashes.Keys) `
    -Description "Consumer-discovery loose package '$packageKey'"
  foreach ($looseRelativePath in $expectedLooseHashes.Keys) {
    $looseFilePath = Join-Path $loosePackagePath $looseRelativePath
    $looseHash = (Get-FileHash -LiteralPath $looseFilePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($looseHash -cne [string]$expectedLooseHashes[$looseRelativePath]) {
      throw "Consumer-discovery loose package '$packageKey' file '$looseRelativePath' does not match its pinned source bytes."
    }
  }

  foreach ($archiveTarget in @('Main', 'Main_PS')) {
    $archivePath = Join-Path $packagePath "$baseName - $archiveTarget.ba2"
    $entries = @(Get-ConsumerDiscoveryGeneralBa2Entries -Path $archivePath)
    $actualEntryNames = @($entries.Name | ForEach-Object { $_.Replace('\', '/').ToLowerInvariant() } | Sort-Object)
    $expectedEntryNames = @($expectedEntryHashes.Keys | Sort-Object)
    if ($actualEntryNames.Count -ne $expectedEntryNames.Count -or
        [string]::Join("`n", $actualEntryNames) -cne [string]::Join("`n", $expectedEntryNames)) {
      throw "Consumer-discovery package '$packageKey' $archiveTarget inventory does not match its exact contract."
    }
    foreach ($entry in $entries) {
      $entryName = ([string]$entry.Name).Replace('\', '/').ToLowerInvariant()
      $entryBytes = Read-ConsumerDiscoveryGeneralBa2EntryBytes -Entry $entry
      $entryHash = Get-BytesSha256 -Bytes $entryBytes
      if ($entryHash -cne [string]$expectedEntryHashes[$entryName]) {
        throw "Consumer-discovery package '$packageKey' $archiveTarget entry '$entryName' does not match its pinned source bytes."
      }
    }
  }
}

Write-Host -ForegroundColor Green 'Verified deterministic movies, pinned VWHUD host inputs, loose payloads, archive-only packages, exact BA2 inventories, uncompressed entries, and embedded hashes.'
