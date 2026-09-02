[CmdletBinding()]
param(
  [switch]$SourceOnly,

  [string]$VwHudRepositoryPath,

  [string]$MoviesDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\movies'),

  [string]$ShipMoviesDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\ship-movies'),

  [string]$PluginsDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\plugins'),

  [string]$ScriptsDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\scripts')
)

$PSNativeCommandUseErrorActionPreference = $true
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

  $actual = @(Get-ChildItem -LiteralPath $Root -File -Recurse | ForEach-Object {
    $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
  } | Sort-Object)
  $sortedExpected = @($Expected | ForEach-Object { $_.Replace('\', '/') } | Sort-Object)
  if ($actual.Count -ne $sortedExpected.Count -or
      [string]::Join("`n", $actual) -cne [string]::Join("`n", $sortedExpected)) {
    throw "$Description inventory differs. Expected [$([string]::Join(', ', $sortedExpected))]; found [$([string]::Join(', ', $actual))]."
  }
}

function Get-Sha256FileValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $line = [System.IO.File]::ReadAllText($Path).Trim()
  $match = [regex]::Match($line, '^(?<hash>[0-9A-Fa-f]{64})(?:\s{2,}.+)?$')
  if (!$match.Success) {
    throw "Invalid SHA-256 sidecar: $Path"
  }
  return $match.Groups['hash'].Value.ToUpperInvariant()
}

function Get-FileSha256 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-BytesSha256 {
  param(
    [Parameter(Mandatory = $true)]
    [byte[]]$Bytes
  )

  $algorithm = [Security.Cryptography.SHA256]::Create()
  try {
    return [Convert]::ToHexString($algorithm.ComputeHash($Bytes))
  }
  finally {
    $algorithm.Dispose()
  }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$consumerRoot = Join-Path $repositoryRoot 'Scaleform\probes\consumer-discovery'
$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot

if ([int]$matrix.Version -ne 2 -or [string]$matrix.Protocol -cne 'VWCANVAS_REGISTRY_PROBE/1') {
  throw 'Consumer-discovery matrix must declare the v2 dynamic registry probe contract.'
}

$expectedKeys = [string[]]@('Host', 'ConsumerA', 'ConsumerB')
foreach ($sectionName in @('Movies', 'Plugins', 'Staging')) {
  $keys = @($matrix[$sectionName].Key)
  if ($keys.Count -ne 3 -or [string]::Join("`n", @($keys | Sort-Object)) -cne [string]::Join("`n", @($expectedKeys | Sort-Object))) {
    throw "Matrix section '$sectionName' must contain exactly Host, ConsumerA, and ConsumerB."
  }
}

if (@($matrix.VwHudFixture.RequiredPipelineFiles).Count -ne 4 -or
    @($matrix.VwHudFixture.RequiredPipelineFiles | Where-Object { $_ -notmatch 'V2|sharedScaleformMovies' }).Count -ne 0) {
  throw 'Consumer discovery must pin only the declared VWHUD v2 pipeline files.'
}
if (@($matrix.VwHudFixture.PlayerHudMovies).Count -ne 4) {
  throw 'Consumer discovery must stage the exact four VWHUD player HUD movie variants.'
}

$requiredRuntimeCases = @(
  'pc-archive-host-only'
  'pc-archive-consumer-a'
  'pc-archive-two-consumers'
  'pc-archive-reversed-consumer-order'
  'pc-archive-save-reload'
  'pc-archive-normal-large'
  'pc-archive-ship-hud'
  'pc-archive-pilot-seat'
)
$runtimeCases = @($matrix.RuntimeCases)
if ($runtimeCases.Count -ne $requiredRuntimeCases.Count) {
  throw 'Runtime matrix must contain exactly the eight approved PC archive-only cases.'
}
foreach ($caseId in $requiredRuntimeCases) {
  if (@($runtimeCases | Where-Object { [string]$_.Id -ceq $caseId }).Count -ne 1) {
    throw "Runtime matrix is missing exact case '$caseId'."
  }
}
foreach ($runtimeCase in $runtimeCases) {
  if ([string]$runtimeCase.Id -match 'ps5|loose' -or [string]::IsNullOrWhiteSpace([string]$runtimeCase.Expected)) {
    throw "Runtime case '$($runtimeCase.Id)' violates the PC archive-only scope."
  }
  foreach ($packageKey in @($runtimeCase.Packages)) {
    if ($packageKey -notin $expectedKeys) {
      throw "Runtime case '$($runtimeCase.Id)' references unknown package '$packageKey'."
    }
  }
}

$requiredFiles = @(
  'Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\Registry.psc'
  'Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerARegistrar.psc'
  'Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerBRegistrar.psc'
  'Scaleform\probes\consumer-discovery\actionscript\CanvasConsumerDiscoveryHost.as'
  'Scaleform\probes\consumer-discovery\actionscript\CanvasDiscoveryConsumerA.as'
  'Scaleform\probes\consumer-discovery\actionscript\CanvasDiscoveryConsumerB.as'
  'Scaleform\probes\consumer-discovery\patches\spaceship-hud-auxiliary-loader.xml'
  'Scaleform\probes\consumer-discovery\build\spaceshiphudmenu.build.xml'
  'Scaleform\probes\consumer-discovery\build\spaceshiphudmenu-lrg.build.xml'
  'Tools\ConsumerDiscoveryPluginGenerator\Venworks.Canvas.ConsumerDiscovery.PluginGenerator.csproj'
  'Tools\ConsumerDiscoveryPluginGenerator\packages.lock.json'
  'Tools\ConsumerDiscoveryPluginGenerator\Program.cs'
  'Tools\ConsumerDiscoveryPluginGenerator\PluginBuilder.cs'
  'Tools\ConsumerDiscoveryPluginGenerator\PluginSpecification.cs'
)
foreach ($relativePath in $requiredFiles) {
  [void](Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $repositoryRoot $relativePath) `
    -Description "Consumer-discovery source '$relativePath'")
}

$obsoleteFiles = @(
  'Scaleform\probes\consumer-discovery\actionscript\CanvasDiscoveryConsumerAUpdate.as'
  'Scaleform\probes\consumer-discovery\actionscript\CanvasDiscoveryConsumerInvalid.as'
  'Scaleform\probes\consumer-discovery\build\consumer-a-update.build.xml'
  'Scaleform\probes\consumer-discovery\build\consumer-invalid.build.xml'
  'Tools\createConsumerDiscoveryProbePackages.ps1'
)
foreach ($relativePath in $obsoleteFiles) {
  if (Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath)) {
    throw "Obsolete static-slot probe source still exists: $relativePath"
  }
}

$registrySource = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot $requiredFiles[0]))
foreach ($token in @(
  'ConsumerOwners.Add(owner)'
  'ConsumerIds.Find(consumerId)'
  'ConsumerOwners[existingIndex] != owner'
  'RegisterForMenuOpenCloseEvent("HUDMenu")'
  'RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")'
  'Game.ShowCustomWatchAlert("VWC_EVT/1|canvas.registry.snapshot|"'
)) {
  if (!$registrySource.Contains($token)) {
    throw "Dynamic Papyrus registry is missing token '$token'."
  }
}

foreach ($consumerName in @('ConsumerARegistrar.psc', 'ConsumerBRegistrar.psc')) {
  $consumerSource = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot "Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\$consumerName"))
  foreach ($token in @('Property Registry Auto Const Mandatory', 'While (attempt < 20)', 'Utility.Wait(0.5)', 'RegisterConsumer(Self,')) {
    if (!$consumerSource.Contains($token)) {
      throw "Papyrus consumer '$consumerName' is missing token '$token'."
    }
  }
}

$hostSource = [System.IO.File]::ReadAllText((Join-Path $consumerRoot 'actionscript\CanvasConsumerDiscoveryHost.as'))
foreach ($token in @(
  'CustomAlertsData'
  'canvas.registry.snapshot'
  'new Loader()'
  'Interface/VenworksCanvas/Consumers/'
  'getCanvasDiscoveryRecord'
  'DESCRIPTOR REJECTED'
  'this.getLoaderIds()'
  'this.dataManager.Unsubscribe(PROVIDER,this.callback)'
)) {
  if (!$hostSource.Contains($token)) {
    throw "Dynamic ActionScript host is missing token '$token'."
  }
}

$sourceScope = [string]::Join("`n", @(
  $requiredFiles | ForEach-Object { [System.IO.File]::ReadAllText((Join-Path $repositoryRoot $_)) }
  [System.IO.File]::ReadAllText((Join-Path $consumerRoot 'probe-matrix.psd1'))
))
if ($sourceScope -match '(?i)slot-[0-9]+') {
  throw 'Consumer-discovery sources retain a forbidden static slot contract.'
}

$projectSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ConsumerDiscoveryPluginGenerator\Venworks.Canvas.ConsumerDiscovery.PluginGenerator.csproj'))
if (!$projectSource.Contains('<TargetFramework>net10.0</TargetFramework>') -or
    !$projectSource.Contains('<PackageReference Include="Mutagen.Bethesda" Version="0.54.4" />') -or
    !$projectSource.Contains('<TreatWarningsAsErrors>true</TreatWarningsAsErrors>')) {
  throw 'Mutagen generator does not retain its approved .NET 10, pinned dependency, and warnings-as-errors contract.'
}

$toolPaths = @(
  'Tools\sharedConsumerDiscoveryProbe.ps1'
  'Tools\buildConsumerDiscoveryProbe.ps1'
  'Tools\buildConsumerDiscoveryShipMovies.ps1'
  'Tools\compileConsumerDiscoveryScripts.ps1'
  'Tools\generateConsumerDiscoveryPlugins.ps1'
  'Tools\stageConsumerDiscoveryProbe.ps1'
  'Tools\verifyConsumerDiscoveryProbe.ps1'
)
foreach ($relativePath in $toolPaths) {
  $toolPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $repositoryRoot $relativePath) `
    -Description "Consumer-discovery tool '$relativePath'"
  $tokens = $null
  $parseErrors = $null
  [void][Management.Automation.Language.Parser]::ParseFile($toolPath, [ref]$tokens, [ref]$parseErrors)
  if (@($parseErrors).Count -ne 0) {
    throw "Consumer-discovery tool '$relativePath' has parse errors: $([string]::Join('; ', @($parseErrors.Message)))"
  }
}
$allToolText = [string]::Join("`n", @($toolPaths | ForEach-Object {
  [System.IO.File]::ReadAllText((Join-Path $repositoryRoot $_))
}))
if ($allToolText -match '(?<!V2)compileScaleformAuxiliary\.ps1' -or !$allToolText.Contains("'-compression=None'")) {
  throw 'Consumer-discovery tooling violates the VWHUD v2 or uncompressed General archive contract.'
}

Write-Host -ForegroundColor Green 'Verified dynamic source contracts, three-package matrix, PC archive-only scope, and PowerShell syntax.'
if ($SourceOnly) {
  return
}

if ([string]::IsNullOrWhiteSpace($VwHudRepositoryPath)) {
  throw 'VwHudRepositoryPath is required for full consumer-discovery verification.'
}
$resolvedVwHudRoot = Assert-VwHudV2Fixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
$resolvedMoviesDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $MoviesDirectory -Description 'Built auxiliary movie directory'
$resolvedShipMoviesDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $ShipMoviesDirectory -Description 'Built Ship HUD movie directory'
$resolvedPluginsDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $PluginsDirectory -Description 'Generated plugin directory'
$resolvedScriptsDirectory = Resolve-ConsumerDiscoveryRequiredDirectory -Path $ScriptsDirectory -Description 'Compiled script directory'

$expectedMovieInventory = @('build-evidence.json')
foreach ($movie in @($matrix.Movies)) {
  $expectedMovieInventory += [string]$movie.Output
  $expectedMovieInventory += "$($movie.Output).sha256"
  $expectedMovieInventory += "$($movie.Output).classes.txt"
}
Assert-ExactRelativeFileInventory -Root $resolvedMoviesDirectory -Expected $expectedMovieInventory -Description 'Auxiliary movie output'
$movieHashByKey = @{}
foreach ($movie in @($matrix.Movies)) {
  $moviePath = Join-Path $resolvedMoviesDirectory ([string]$movie.Output)
  $actualHash = Get-FileSha256 -Path $moviePath
  $sidecarHash = [System.IO.File]::ReadAllText("$moviePath.sha256").Trim().ToUpperInvariant()
  if ($actualHash -cne $sidecarHash) {
    throw "Auxiliary movie '$($movie.Key)' does not match its deterministic hash sidecar."
  }
  $movieHashByKey[[string]$movie.Key] = $actualHash
}

Assert-ExactRelativeFileInventory `
  -Root $resolvedShipMoviesDirectory `
  -Expected @('spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf') `
  -Description 'Ship HUD movie output'
$shipMovieHashes = @{}
foreach ($definition in @(
  @{ Output = 'spaceshiphudmenu.swf'; HashFile = 'spaceshiphudmenu.expected.sha256' }
  @{ Output = 'spaceshiphudmenu_lrg.swf'; HashFile = 'spaceshiphudmenu-lrg.expected.sha256' }
)) {
  $outputPath = Join-Path $resolvedShipMoviesDirectory ([string]$definition.Output)
  $expectedHash = Get-Sha256FileValue -Path (Join-Path $consumerRoot "build\$($definition.HashFile)")
  $actualHash = Get-FileSha256 -Path $outputPath
  if ($actualHash -cne $expectedHash) {
    throw "Patched Ship HUD movie '$($definition.Output)' does not match its pinned expected hash."
  }
  $shipMovieHashes[[string]$definition.Output] = $actualHash
}

Assert-ExactRelativeFileInventory `
  -Root $resolvedPluginsDirectory `
  -Expected @($matrix.Plugins.FileName) `
  -Description 'Generated plugin output'
foreach ($plugin in @($matrix.Plugins)) {
  Assert-ConsumerDiscoveryNotGitLfsPointer `
    -Path (Join-Path $resolvedPluginsDirectory ([string]$plugin.FileName)) `
    -Description "Generated plugin '$($plugin.Key)'"
}

$expectedScriptInventory = @(
  'compile-evidence.json'
  'Venworks/Canvas/Probes/ConsumerDiscovery/Registry.pex'
  'Venworks/Canvas/Probes/ConsumerDiscovery/ConsumerARegistrar.pex'
  'Venworks/Canvas/Probes/ConsumerDiscovery/ConsumerBRegistrar.pex'
)
Assert-ExactRelativeFileInventory -Root $resolvedScriptsDirectory -Expected $expectedScriptInventory -Description 'Compiled Papyrus output'

$payloadHashes = @{
  Host = @{
    'interface/venworkscui.swf' = $movieHashByKey.Host
    'interface/spaceshiphudmenu.swf' = $shipMovieHashes['spaceshiphudmenu.swf']
    'interface/spaceshiphudmenu_lrg.swf' = $shipMovieHashes['spaceshiphudmenu_lrg.swf']
    'scripts/venworks/canvas/probes/consumerdiscovery/registry.pex' = (Get-FileSha256 -Path (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\Registry.pex'))
  }
  ConsumerA = @{
    'interface/venworkscanvas/consumers/venworks.canvas.probe.consumer-a/normal.swf' = $movieHashByKey.ConsumerA
    'interface/venworkscanvas/consumers/venworks.canvas.probe.consumer-a/large.swf' = $movieHashByKey.ConsumerA
    'scripts/venworks/canvas/probes/consumerdiscovery/consumeraregistrar.pex' = (Get-FileSha256 -Path (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerARegistrar.pex'))
  }
  ConsumerB = @{
    'interface/venworkscanvas/consumers/venworks.canvas.probe.consumer-b/normal.swf' = $movieHashByKey.ConsumerB
    'interface/venworkscanvas/consumers/venworks.canvas.probe.consumer-b/large.swf' = $movieHashByKey.ConsumerB
    'scripts/venworks/canvas/probes/consumerdiscovery/consumerbregistrar.pex' = (Get-FileSha256 -Path (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerBRegistrar.pex'))
  }
}
foreach ($playerHudMovie in @($matrix.VwHudFixture.PlayerHudMovies)) {
  $sourcePath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedVwHudRoot ([string]$playerHudMovie.Source)) `
    -Description "Pinned VWHUD player HUD movie '$($playerHudMovie.Source)'"
  $payloadHashes.Host[([string]$playerHudMovie.Target).ToLowerInvariant()] = Get-FileSha256 -Path $sourcePath
}

if (Test-Path -LiteralPath (Join-Path $repositoryRoot 'Staging')) {
  throw 'Legacy shared Staging directory must not coexist with the three package-owned staging roots.'
}
foreach ($staging in @($matrix.Staging)) {
  $key = [string]$staging.Key
  $stagingPath = Resolve-ConsumerDiscoveryRequiredDirectory `
    -Path (Join-Path $repositoryRoot ([string]$staging.Directory)) `
    -Description "$key staging root"
  Assert-ExactRelativeFileInventory `
    -Root $stagingPath `
    -Expected @([string]$staging.Plugin, [string]$staging.Archive) `
    -Description "$key staging root"

  $generatedPluginPath = Join-Path $resolvedPluginsDirectory ([string]$staging.Plugin)
  $stagedPluginPath = Join-Path $stagingPath ([string]$staging.Plugin)
  if ((Get-FileSha256 -Path $generatedPluginPath) -cne (Get-FileSha256 -Path $stagedPluginPath)) {
    throw "$key staged plugin differs from the Mutagen-generated plugin."
  }

  $archivePath = Join-Path $stagingPath ([string]$staging.Archive)
  $entries = @(Get-ConsumerDiscoveryGeneralBa2Entries -Path $archivePath)
  if (@($entries | Where-Object { [uint32]$_.PackedSize -ne 0 }).Count -ne 0) {
    throw "$key staged archive contains compressed entries."
  }
  $actualEntryNames = @($entries.Name | ForEach-Object { $_.Replace('\', '/').ToLowerInvariant() } | Sort-Object)
  $expectedEntryNames = @($payloadHashes[$key].Keys | Sort-Object)
  if ($actualEntryNames.Count -ne $expectedEntryNames.Count -or
      [string]::Join("`n", $actualEntryNames) -cne [string]::Join("`n", $expectedEntryNames)) {
    throw "$key staged archive inventory does not match its exact owner payload."
  }
  foreach ($entry in $entries) {
    $entryName = ([string]$entry.Name).Replace('\', '/').ToLowerInvariant()
    $entryHash = Get-BytesSha256 -Bytes (Read-ConsumerDiscoveryGeneralBa2EntryBytes -Entry $entry)
    if ($entryHash -cne [string]$payloadHashes[$key][$entryName]) {
      throw "$key staged archive entry '$entryName' differs from its verified source artifact."
    }
  }
}

Write-Host -ForegroundColor Green 'Verified deterministic movies, Mutagen plugins, compiled scripts, patched Ship HUD movies, and all three exact archive-only staging roots.'
