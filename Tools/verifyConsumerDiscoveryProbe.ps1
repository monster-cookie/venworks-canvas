[CmdletBinding()]
param(
  [switch]$SourceOnly,

  [string]$VwHudRepositoryPath,

  [Alias('Profile')]
  [string]$ProbeProfile = 'Baseline',

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

function ConvertTo-ConsumerDiscoveryFrame {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Value
  )

  return "$($Value.Length):$Value"
}

function Read-ConsumerDiscoveryFrame {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Text,

    [Parameter(Mandatory = $true)]
    [int]$Offset,

    [Parameter(Mandatory = $true)]
    [int]$MaximumLength
  )

  if ($Offset -lt 0 -or $Offset -ge $Text.Length) {
    throw 'Missing length-prefixed frame.'
  }
  $delimiter = $Text.IndexOf(':', $Offset)
  if ($delimiter -lt 0 -or $delimiter -eq $Offset -or ($delimiter - $Offset) -gt 6) {
    throw 'Invalid length-prefixed frame header.'
  }
  $lengthText = $Text.Substring($Offset, $delimiter - $Offset)
  [int]$length = 0
  if (![int]::TryParse($lengthText, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$length) -or
      $length -lt 0 -or $length -gt $MaximumLength) {
    throw 'Length-prefixed frame is outside its permitted range.'
  }
  $valueStart = $delimiter + 1
  $valueEnd = $valueStart + $length
  if ($valueEnd -gt $Text.Length) {
    throw 'Length-prefixed frame is truncated.'
  }
  return [pscustomobject]@{
    Value = $Text.Substring($valueStart, $length)
    NextOffset = $valueEnd
  }
}

function New-ConsumerDiscoveryDescriptorRecord {
  param(
    [string]$ConsumerId = 'venworks.canvas.probe.consumer-a',
    [string]$DisplayName = 'VWCANVAS-9 Consumer A',
    [string]$NormalMoviePath = "VenworksCanvas/Consumers/$ConsumerId/normal.swf",
    [string]$LargeMoviePath = "VenworksCanvas/Consumers/$ConsumerId/large.swf",
    [int]$DescriptorVersion = 1
  )

  return (ConvertTo-ConsumerDiscoveryFrame -Value $ConsumerId) +
    (ConvertTo-ConsumerDiscoveryFrame -Value $DisplayName) +
    (ConvertTo-ConsumerDiscoveryFrame -Value $NormalMoviePath) +
    (ConvertTo-ConsumerDiscoveryFrame -Value $LargeMoviePath) +
    (ConvertTo-ConsumerDiscoveryFrame -Value ([string]$DescriptorVersion))
}

function New-ConsumerDiscoverySnapshotBody {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Records
  )

  $body = (ConvertTo-ConsumerDiscoveryFrame -Value '1') +
    (ConvertTo-ConsumerDiscoveryFrame -Value 'fixture') +
    (ConvertTo-ConsumerDiscoveryFrame -Value ([string]$Records.Count))
  foreach ($record in $Records) {
    $body += ConvertTo-ConsumerDiscoveryFrame -Value $record
  }
  return $body
}

function ConvertFrom-ConsumerDiscoveryDescriptorRecord {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Record
  )

  $limits = @(64, 80, 180, 180, 4)
  $values = [System.Collections.Generic.List[string]]::new()
  $offset = 0
  foreach ($limit in $limits) {
    $frame = Read-ConsumerDiscoveryFrame -Text $Record -Offset $offset -MaximumLength $limit
    $values.Add([string]$frame.Value)
    $offset = [int]$frame.NextOffset
  }
  if ($offset -ne $Record.Length) {
    throw 'Descriptor contains trailing data.'
  }

  [int]$descriptorVersion = 0
  $consumerId = $values[0]
  $displayName = $values[1]
  $expectedPrefix = "VenworksCanvas/Consumers/$consumerId/"
  $metadataValid = $consumerId -cmatch '^[a-z0-9][a-z0-9.-]{1,62}[a-z0-9]$' -and
    $consumerId.IndexOf('.', [StringComparison]::Ordinal) -gt 0 -and
    !$consumerId.Contains('..') -and
    $displayName -cmatch '^[\x20-\x7E]{1,80}$' -and
    [int]::TryParse($values[4], [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$descriptorVersion) -and
    $descriptorVersion -ge 1 -and $descriptorVersion -le 9999 -and
    $values[2] -ceq ($expectedPrefix + 'normal.swf') -and
    $values[3] -ceq ($expectedPrefix + 'large.swf')
  if (!$metadataValid) {
    throw 'Descriptor metadata is invalid.'
  }

  return [pscustomobject]@{
    ConsumerId = $consumerId
    DisplayName = $displayName
    DescriptorVersion = $descriptorVersion
  }
}

function ConvertFrom-ConsumerDiscoverySnapshotBody {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Body
  )

  if ($Body.Length -gt 4096) {
    throw 'Snapshot exceeds the bounded payload size.'
  }
  $offset = 0
  $messageFrame = Read-ConsumerDiscoveryFrame -Text $Body -Offset $offset -MaximumLength 12
  $offset = [int]$messageFrame.NextOffset
  $reasonFrame = Read-ConsumerDiscoveryFrame -Text $Body -Offset $offset -MaximumLength 40
  $offset = [int]$reasonFrame.NextOffset
  $countFrame = Read-ConsumerDiscoveryFrame -Text $Body -Offset $offset -MaximumLength 4
  $offset = [int]$countFrame.NextOffset
  [int]$recordCount = 0
  if (![int]::TryParse([string]$countFrame.Value, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$recordCount) -or
      $recordCount -lt 0 -or $recordCount -gt 8) {
    throw 'Snapshot record count is invalid.'
  }

  $descriptors = [ordered]@{}
  for ($index = 0; $index -lt $recordCount; $index += 1) {
    $recordFrame = Read-ConsumerDiscoveryFrame -Text $Body -Offset $offset -MaximumLength 512
    $offset = [int]$recordFrame.NextOffset
    try {
      $descriptor = ConvertFrom-ConsumerDiscoveryDescriptorRecord -Record ([string]$recordFrame.Value)
      if (!$descriptors.Contains([string]$descriptor.ConsumerId)) {
        $descriptors[[string]$descriptor.ConsumerId] = $descriptor
      }
    }
    catch {
      continue
    }
  }
  if ($offset -ne $Body.Length) {
    throw 'Snapshot contains trailing data.'
  }
  return $descriptors
}

function Assert-ConsumerDiscoveryParserFixtures {
  $delimiterRecord = New-ConsumerDiscoveryDescriptorRecord -DisplayName 'A | B ; C ~ D'
  $delimiterResult = ConvertFrom-ConsumerDiscoverySnapshotBody -Body (New-ConsumerDiscoverySnapshotBody -Records @($delimiterRecord))
  if ($delimiterResult.Count -ne 1 -or $delimiterResult['venworks.canvas.probe.consumer-a'].DisplayName -cne 'A | B ; C ~ D') {
    throw 'Length-prefixed parser fixture did not preserve delimiter-like display-name characters.'
  }

  $invalidId = New-ConsumerDiscoveryDescriptorRecord -ConsumerId 'Venworks.Canvas.Invalid'
  if ((ConvertFrom-ConsumerDiscoverySnapshotBody -Body (New-ConsumerDiscoverySnapshotBody -Records @($invalidId))).Count -ne 0) {
    throw 'Parser fixture accepted an invalid consumer ID.'
  }

  $traversal = New-ConsumerDiscoveryDescriptorRecord -NormalMoviePath '../outside.swf'
  if ((ConvertFrom-ConsumerDiscoverySnapshotBody -Body (New-ConsumerDiscoverySnapshotBody -Records @($traversal))).Count -ne 0) {
    throw 'Parser fixture accepted a path outside the consumer namespace.'
  }

  $first = New-ConsumerDiscoveryDescriptorRecord -DisplayName 'FIRST'
  $second = New-ConsumerDiscoveryDescriptorRecord -DisplayName 'SECOND'
  $duplicateResult = ConvertFrom-ConsumerDiscoverySnapshotBody -Body (New-ConsumerDiscoverySnapshotBody -Records @($first, $second))
  if ($duplicateResult.Count -ne 1 -or $duplicateResult['venworks.canvas.probe.consumer-a'].DisplayName -cne 'FIRST') {
    throw 'Parser fixture did not retain the first valid duplicate consumer descriptor.'
  }

  $invalidVersion = New-ConsumerDiscoveryDescriptorRecord -DescriptorVersion 0
  if ((ConvertFrom-ConsumerDiscoverySnapshotBody -Body (New-ConsumerDiscoverySnapshotBody -Records @($invalidVersion))).Count -ne 0) {
    throw 'Parser fixture accepted an invalid descriptor version.'
  }

  $truncatedRejected = $false
  try {
    $truncated = (New-ConsumerDiscoverySnapshotBody -Records @($first))
    [void](ConvertFrom-ConsumerDiscoverySnapshotBody -Body $truncated.Substring(0, $truncated.Length - 1))
  }
  catch {
    $truncatedRejected = $true
  }
  if (!$truncatedRejected) {
    throw 'Parser fixture accepted a truncated outer record frame.'
  }

  $oversizedRejected = $false
  try {
    [void](ConvertFrom-ConsumerDiscoverySnapshotBody -Body ('1:11:x1:0600:' + ('x' * 600)))
  }
  catch {
    $oversizedRejected = $true
  }
  if (!$oversizedRejected) {
    throw 'Parser fixture accepted an oversized record frame.'
  }

  $invalidThenValid = ConvertFrom-ConsumerDiscoverySnapshotBody -Body (New-ConsumerDiscoverySnapshotBody -Records @($invalidId, $first))
  if ($invalidThenValid.Count -ne 1 -or !$invalidThenValid.Contains('venworks.canvas.probe.consumer-a')) {
    throw 'Parser fixture allowed one invalid descriptor to poison a later valid descriptor.'
  }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$consumerRoot = Join-Path $repositoryRoot 'Scaleform\probes\consumer-discovery'
$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot

if ([int]$matrix.Version -ne 3 -or [string]$matrix.Protocol -cne 'VWCANVAS_REGISTRY_PROBE/2') {
  throw 'Consumer-discovery matrix must declare the v3 resilient dynamic registry probe contract.'
}

$expectedPackageKeys = [string[]]@('Host', 'ConsumerA', 'ConsumerB')
$expectedMovieKeys = [string[]]@('Host', 'ConsumerA', 'ConsumerAUpdated', 'ConsumerB')
foreach ($sectionName in @('Plugins', 'Staging')) {
  $keys = @($matrix[$sectionName].Key)
  if ($keys.Count -ne 3 -or [string]::Join("`n", @($keys | Sort-Object)) -cne [string]::Join("`n", @($expectedPackageKeys | Sort-Object))) {
    throw "Matrix section '$sectionName' must contain exactly Host, ConsumerA, and ConsumerB."
  }
}
if (@($matrix.Movies).Count -ne 4 -or
    [string]::Join("`n", @($matrix.Movies.Key | Sort-Object)) -cne [string]::Join("`n", @($expectedMovieKeys | Sort-Object))) {
  throw 'Matrix Movies must contain exactly Host, ConsumerA, ConsumerAUpdated, and ConsumerB.'
}

$requiredToolchainFiles = @($matrix.VwHudFixture.RequiredToolchainFiles)
if ($requiredToolchainFiles.Count -ne 2 -or
    [string]::Join("`n", @($requiredToolchainFiles | Sort-Object)) -cne [string]::Join("`n", @('Tools/compileScaleform.ps1', 'Tools/sharedScaleformMovies.ps1' | Sort-Object))) {
  throw 'Consumer discovery must pin exactly the VWHUD helper and compiler that its VWCANVAS-owned build invokes.'
}
if (@($matrix.VwHudFixture.PlayerHudMovies).Count -ne 4) {
  throw 'Consumer discovery must stage the exact four VWHUD player HUD movie variants.'
}

$profileKeys = @($matrix.Profiles.Key)
if ($profileKeys.Count -ne 3 -or
    [string]::Join("`n", @($profileKeys | Sort-Object)) -cne [string]::Join("`n", @('Baseline', 'Faults', 'UpdatedA' | Sort-Object))) {
  throw 'Consumer discovery must define exactly the Baseline, Faults, and UpdatedA profiles.'
}
$resolvedProfile = Resolve-ConsumerDiscoveryProfile -Matrix $matrix -ProbeProfile $ProbeProfile

$requiredParserCases = @(
  'delimiter-display-name'
  'invalid-consumer-id'
  'path-traversal'
  'duplicate-id'
  'invalid-version'
  'truncated-record'
  'oversized-field'
  'invalid-plus-valid'
)
$parserCases = @($matrix.ParserCases)
if ($parserCases.Count -ne $requiredParserCases.Count) {
  throw 'Parser matrix must contain exactly the eight approved framing and isolation cases.'
}
foreach ($caseId in $requiredParserCases) {
  if (@($parserCases | Where-Object { [string]$_.Id -ceq $caseId }).Count -ne 1) {
    throw "Parser matrix is missing exact case '$caseId'."
  }
}
Assert-ConsumerDiscoveryParserFixtures

$requiredRuntimeCases = @(
  'pc-archive-host-only'
  'pc-archive-consumer-a'
  'pc-archive-two-consumers'
  'pc-archive-reversed-consumer-order'
  'pc-archive-collision-and-missing'
  'pc-archive-update-consumer-a'
  'pc-archive-remove-consumer-b'
  'pc-archive-id-reclamation'
  'pc-archive-save-reload'
  'pc-archive-menu-replay'
  'pc-archive-normal-large'
  'pc-archive-ship-hud'
  'pc-archive-pilot-seat'
)
$runtimeCases = @($matrix.RuntimeCases)
if ($runtimeCases.Count -ne $requiredRuntimeCases.Count) {
  throw 'Runtime matrix must contain exactly the thirteen approved PC archive-only cases.'
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
    if ($packageKey -notin $expectedPackageKeys) {
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
  'Scaleform\probes\consumer-discovery\actionscript\CanvasDiscoveryConsumerAUpdated.as'
  'Scaleform\probes\consumer-discovery\actionscript\CanvasDiscoveryConsumerB.as'
  'Scaleform\probes\consumer-discovery\build\host.build.xml'
  'Scaleform\probes\consumer-discovery\build\consumer-a.build.xml'
  'Scaleform\probes\consumer-discovery\build\consumer-a-updated.build.xml'
  'Scaleform\probes\consumer-discovery\build\consumer-b.build.xml'
  'Scaleform\probes\consumer-discovery\patches\spaceship-hud-auxiliary-loader.xml'
  'Scaleform\probes\consumer-discovery\build\spaceshiphudmenu.build.xml'
  'Scaleform\probes\consumer-discovery\build\spaceshiphudmenu-lrg.build.xml'
  'Tools\ConsumerDiscoveryPluginGenerator\Venworks.Canvas.ConsumerDiscovery.PluginGenerator.csproj'
  'Tools\ConsumerDiscoveryPluginGenerator\packages.lock.json'
  'Tools\ConsumerDiscoveryPluginGenerator\Program.cs'
  'Tools\ConsumerDiscoveryPluginGenerator\PluginBuilder.cs'
  'Tools\ConsumerDiscoveryPluginGenerator\PluginSpecification.cs'
  'Tools\ConsumerDiscoveryPluginGenerator\QuestSpecification.cs'
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
  'ConsumerOwners[index] == None'
  'PublishDiagnostic("registration-pruned:"'
  'PublishDiagnostic("registry-storage-repaired")'
  'PublishSnapshot("refresh")'
  'RegisterForMenuOpenCloseEvent("HUDMenu")'
  'RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")'
  'Utility.WaitMenuPause(0.25)'
  'Utility.SplitStringChars'
  'EncodeField(record)'
  'Game.ShowCustomWatchAlert("VWC_EVT/1|canvas.registry.snapshot|"'
)) {
  if (!$registrySource.Contains($token)) {
    throw "Dynamic Papyrus registry is missing token '$token'."
  }
}

foreach ($consumerName in @('ConsumerARegistrar.psc', 'ConsumerBRegistrar.psc')) {
  $consumerSource = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot "Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\$consumerName"))
  foreach ($token in @(
    'Property Registry Auto Const Mandatory'
    'String Property ConsumerId Auto Const Mandatory'
    'String Property NormalMoviePath Auto Const Mandatory'
    'Int Property DescriptorVersion Auto Const Mandatory'
    'Bool Property ExpectedRegistration Auto Const Mandatory'
    'Float Property InitialDelaySeconds Auto Const Mandatory'
    'While (attempt < 20)'
    'Utility.WaitMenuPause(0.5)'
    'RegisterConsumer(Self, ConsumerId, DisplayName, NormalMoviePath, LargeMoviePath, DescriptorVersion)'
  )) {
    if (!$consumerSource.Contains($token)) {
      throw "Papyrus consumer '$consumerName' is missing token '$token'."
    }
  }
  if ($consumerSource.Contains('Interface/VenworksCanvas/')) {
    throw "Papyrus consumer '$consumerName' retained an Interface-prefixed loader path."
  }
}

$hostSource = [System.IO.File]::ReadAllText((Join-Path $consumerRoot 'actionscript\CanvasConsumerDiscoveryHost.as'))
foreach ($token in @(
  'CustomAlertsData'
  'SNAPSHOT_PREFIX'
  'DIAGNOSTIC_PREFIX'
  'readFrame('
  'parseUnsignedInt('
  'parseDescriptor('
  'new Loader()'
  'VenworksCanvas/Consumers/'
  'getCanvasDiscoveryRecord'
  'DESCRIPTOR REJECTED'
  'SNAPSHOT REJECTED'
  'this.getLoaderIds()'
  'this.dataManager.Unsubscribe(PROVIDER,this.callback)'
)) {
  if (!$hostSource.Contains($token)) {
    throw "Dynamic ActionScript host is missing token '$token'."
  }
}
if ($hostSource.Contains('Interface/VenworksCanvas/')) {
  throw 'Dynamic ActionScript host retained an Interface-prefixed loader path.'
}
$subscribeIndex = $hostSource.IndexOf('this.dataManager.Subscribe(PROVIDER,this.callback);', [StringComparison]::Ordinal)
$requestIndex = $hostSource.IndexOf('this.dataManager.GetDataFromClient(PROVIDER,true);', [StringComparison]::Ordinal)
if ($subscribeIndex -lt 0 -or $requestIndex -le $subscribeIndex) {
  throw 'Dynamic ActionScript host must subscribe before requesting current provider data.'
}

$sourceScope = [string]::Join("`n", @(
  $requiredFiles | ForEach-Object { [System.IO.File]::ReadAllText((Join-Path $repositoryRoot $_)) }
  [System.IO.File]::ReadAllText((Join-Path $consumerRoot 'probe-matrix.psd1'))
))
if ($sourceScope -match '(?i)slot-[0-9]+') {
  throw 'Consumer-discovery sources retain a forbidden static slot contract.'
}
if ($sourceScope.Contains('Interface/VenworksCanvas/Consumers/')) {
  throw 'Consumer-discovery sources retain a forbidden Interface-prefixed Loader path.'
}

$projectSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ConsumerDiscoveryPluginGenerator\Venworks.Canvas.ConsumerDiscovery.PluginGenerator.csproj'))
if (!$projectSource.Contains('<TargetFramework>net10.0</TargetFramework>') -or
    !$projectSource.Contains('<PackageReference Include="Mutagen.Bethesda" Version="0.54.4" />') -or
    !$projectSource.Contains('<TreatWarningsAsErrors>true</TreatWarningsAsErrors>')) {
  throw 'Mutagen generator does not retain its approved .NET 10, pinned dependency, and warnings-as-errors contract.'
}

$generatorSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ConsumerDiscoveryPluginGenerator\PluginBuilder.cs'))
foreach ($token in @(
  'profile is not ("Baseline" or "Faults" or "UpdatedA")'
  'VWCANVAS9_ConsumerBCollisionProbe'
  'VWCANVAS9_ConsumerBMissingProbe'
  'ScriptStringProperty'
  'ScriptIntProperty'
  'ScriptBoolProperty'
  'ScriptFloatProperty'
  'properties.Count == 8'
)) {
  if (!$generatorSource.Contains($token)) {
    throw "Mutagen generator is missing profile/readback token '$token'."
  }
}
$programSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ConsumerDiscoveryPluginGenerator\Program.cs'))
if (!$programSource.Contains('"--profile"')) {
  throw 'Mutagen generator command line does not require an explicit runtime profile.'
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
$allToolText = [string]::Join("`n", @($toolPaths | Where-Object { $_ -notlike '*verifyConsumerDiscoveryProbe.ps1' } | ForEach-Object {
  [System.IO.File]::ReadAllText((Join-Path $repositoryRoot $_))
}))
foreach ($forbiddenToken in @('Assert-VwHudV2Fixture', 'RequiredPipelineFiles', 'VwHudPipeline', 'compileScaleformAuxiliary.ps1')) {
  if ($allToolText.Contains($forbiddenToken)) {
    throw "Consumer-discovery tooling retains an inaccurate VWHUD pipeline claim or obsolete entry point '$forbiddenToken'."
  }
}
if (!$allToolText.Contains('VWCANVAS-owned, VWHUD-v2-derived') -or !$allToolText.Contains("'-compression=None'")) {
  throw 'Consumer-discovery tooling must describe the VWCANVAS-owned, VWHUD-v2-derived build and retain uncompressed General archives.'
}

Write-Host -ForegroundColor Green "Verified resilient dynamic source contracts, profile '$($resolvedProfile.Key)', parser fixtures, PC archive-only matrix, and PowerShell syntax."
if ($SourceOnly) {
  return
}

if ([string]::IsNullOrWhiteSpace($VwHudRepositoryPath)) {
  throw 'VwHudRepositoryPath is required for full consumer-discovery verification.'
}
$resolvedVwHudRoot = Assert-PinnedVwHudToolchainFixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
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
$buildEvidencePath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $resolvedMoviesDirectory 'build-evidence.json') `
  -Description 'Consumer-discovery build evidence'
$buildEvidence = Get-Content -LiteralPath $buildEvidencePath -Raw | ConvertFrom-Json
if ([string]$buildEvidence.Schema -cne 'VWCANVAS9_CONSUMER_DISCOVERY_BUILD/2' -or
    [string]$buildEvidence.CanvasPipeline -cne 'VWCANVAS_OWNED_VWHUD_V2_DERIVED/1' -or
    [string]$buildEvidence.VwHudRevision -cne [string]$matrix.VwHudFixture.Revision) {
  throw 'Auxiliary movie build evidence does not identify the exact VWCANVAS-owned, VWHUD-v2-derived build contract.'
}
$toolchainEvidence = @($buildEvidence.VwHudToolchain)
if ($toolchainEvidence.Count -ne $requiredToolchainFiles.Count) {
  throw 'Auxiliary movie build evidence does not contain the exact pinned VWHUD toolchain inventory.'
}
foreach ($relativePath in $requiredToolchainFiles) {
  $toolchainMatches = @($toolchainEvidence | Where-Object { [string]$_.Path -ceq [string]$relativePath })
  if ($toolchainMatches.Count -ne 1) {
    throw "Auxiliary movie build evidence is missing exact toolchain file '$relativePath'."
  }
  $toolPath = Join-Path $resolvedVwHudRoot ([string]$relativePath)
  if ([string]$toolchainMatches[0].Sha256 -cne (Get-FileSha256 -Path $toolPath)) {
    throw "Auxiliary movie build evidence hash drifted for '$relativePath'."
  }
}
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
    'interface/venworkscanvas/consumers/venworks.canvas.probe.consumer-a/normal.swf' = $movieHashByKey[[string]$resolvedProfile.ConsumerAMovie]
    'interface/venworkscanvas/consumers/venworks.canvas.probe.consumer-a/large.swf' = $movieHashByKey[[string]$resolvedProfile.ConsumerAMovie]
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
$stagingEvidencePath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $repositoryRoot '.work\consumer-discovery\staging-evidence.json') `
  -Description 'Consumer-discovery staging evidence'
$stagingEvidence = Get-Content -LiteralPath $stagingEvidencePath -Raw | ConvertFrom-Json
if ([string]$stagingEvidence.Schema -cne 'VWCANVAS9_CONSUMER_DISCOVERY_STAGING/2' -or
    [string]$stagingEvidence.Profile -cne [string]$resolvedProfile.Key -or
    [string]$stagingEvidence.VwHudRevision -cne [string]$matrix.VwHudFixture.Revision -or
    @($stagingEvidence.Staging).Count -ne 3) {
  throw "Staging evidence does not match selected profile '$($resolvedProfile.Key)' and the pinned VWHUD revision."
}
foreach ($staging in @($matrix.Staging)) {
  $key = [string]$staging.Key
  $stagingEvidenceMatches = @($stagingEvidence.Staging | Where-Object { [string]$_.Key -ceq $key })
  if ($stagingEvidenceMatches.Count -ne 1) {
    throw "Staging evidence does not contain exactly one '$key' package."
  }
  $packageEvidence = $stagingEvidenceMatches[0]
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
  if ([string]$packageEvidence.Plugin.Sha256 -cne (Get-FileSha256 -Path $stagedPluginPath)) {
    throw "$key staged plugin differs from its staging evidence."
  }

  $archivePath = Join-Path $stagingPath ([string]$staging.Archive)
  if ([string]$packageEvidence.Archive.Sha256 -cne (Get-FileSha256 -Path $archivePath)) {
    throw "$key staged archive differs from its staging evidence."
  }
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

Write-Host -ForegroundColor Green "Verified deterministic movies, profile '$($resolvedProfile.Key)' Mutagen plugins, compiled scripts, patched Ship HUD movies, and all three exact archive-only staging roots."
