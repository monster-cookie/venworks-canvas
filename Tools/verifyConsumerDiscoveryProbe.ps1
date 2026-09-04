[CmdletBinding()]
param(
  [switch]$SourceOnly,

  [switch]$ArtifactsOnly,

  [string]$VwHudRepositoryPath,

  [string]$VenworksCoreRepositoryPath,

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
    [string]$ConsumerId = 'a8098c1a-f86e-4b1e-9d7c-5a102bf38460',
    [string]$DisplayName = 'VWCANVAS-9 Consumer A',
    [string]$NormalMoviePath = "VenworksCanvas/Consumers/venworks.canvas.probe.consumer-a/normal.swf",
    [string]$LargeMoviePath = "VenworksCanvas/Consumers/venworks.canvas.probe.consumer-a/large.swf",
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
    [string[]]$Records,

    [int]$GenerationId = 1,

    [string]$Reason = 'fixture',

    [int]$PageIndex = 0,

    [int]$PageCount = 1,

    [int]$TotalRecordCount = -1
  )

  if ($TotalRecordCount -lt 0) {
    $TotalRecordCount = $Records.Count
  }
  $body = (ConvertTo-ConsumerDiscoveryFrame -Value ([string]$GenerationId)) +
    (ConvertTo-ConsumerDiscoveryFrame -Value $Reason) +
    (ConvertTo-ConsumerDiscoveryFrame -Value ([string]$PageIndex)) +
    (ConvertTo-ConsumerDiscoveryFrame -Value ([string]$PageCount)) +
    (ConvertTo-ConsumerDiscoveryFrame -Value ([string]$TotalRecordCount)) +
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
  $consumerId = ConvertTo-ConsumerDiscoveryUuid -Value $values[0]
  $displayName = $values[1]
  $normalMatch = [regex]::Match($values[2], '\AVenworksCanvas/Consumers/([a-z0-9][a-z0-9.-]{1,62}[a-z0-9])/normal\.swf\z', 'IgnoreCase')
  $largeMatch = [regex]::Match($values[3], '\AVenworksCanvas/Consumers/([a-z0-9][a-z0-9.-]{1,62}[a-z0-9])/large\.swf\z', 'IgnoreCase')
  $metadataValid = $displayName -cmatch '^[\x20-\x7E]{1,80}$' -and
    [int]::TryParse($values[4], [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$descriptorVersion) -and
    $descriptorVersion -ge 1 -and $descriptorVersion -le 9999 -and
    $normalMatch.Success -and $largeMatch.Success -and
    !$normalMatch.Groups[1].Value.Contains('..') -and
    $normalMatch.Groups[1].Value -ieq $largeMatch.Groups[1].Value
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

  $page = ConvertFrom-ConsumerDiscoverySnapshotPageBody -Body $Body
  if ($page.PageIndex -ne 0 -or $page.PageCount -ne 1 -or $page.TotalRecordCount -ne $page.PageRecordCount) {
    throw 'Single-page snapshot metadata is inconsistent.'
  }
  return $page.Descriptors
}

function ConvertFrom-ConsumerDiscoverySnapshotPageBody {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Body
  )

  if ($Body.Length -gt 4096) {
    throw 'Snapshot page exceeds the bounded payload size.'
  }
  $offset = 0
  $generationFrame = Read-ConsumerDiscoveryFrame -Text $Body -Offset $offset -MaximumLength 12
  $offset = [int]$generationFrame.NextOffset
  $reasonFrame = Read-ConsumerDiscoveryFrame -Text $Body -Offset $offset -MaximumLength 40
  $offset = [int]$reasonFrame.NextOffset
  $pageIndexFrame = Read-ConsumerDiscoveryFrame -Text $Body -Offset $offset -MaximumLength 12
  $offset = [int]$pageIndexFrame.NextOffset
  $pageCountFrame = Read-ConsumerDiscoveryFrame -Text $Body -Offset $offset -MaximumLength 12
  $offset = [int]$pageCountFrame.NextOffset
  $totalRecordCountFrame = Read-ConsumerDiscoveryFrame -Text $Body -Offset $offset -MaximumLength 12
  $offset = [int]$totalRecordCountFrame.NextOffset
  $pageRecordCountFrame = Read-ConsumerDiscoveryFrame -Text $Body -Offset $offset -MaximumLength 12
  $offset = [int]$pageRecordCountFrame.NextOffset

  $integers = [System.Collections.Generic.List[int]]::new()
  foreach ($value in @(
    [string]$generationFrame.Value,
    [string]$pageIndexFrame.Value,
    [string]$pageCountFrame.Value,
    [string]$totalRecordCountFrame.Value,
    [string]$pageRecordCountFrame.Value
  )) {
    [int]$parsed = 0
    if (![int]::TryParse($value, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed) -or $parsed -lt 0) {
      throw 'Snapshot page integer metadata is invalid.'
    }
    $integers.Add($parsed)
  }
  $generationId = $integers[0]
  $pageIndex = $integers[1]
  $pageCount = $integers[2]
  $totalRecordCount = $integers[3]
  $pageRecordCount = $integers[4]
  if ($pageCount -lt 1 -or $pageIndex -ge $pageCount -or $pageRecordCount -gt $totalRecordCount) {
    throw 'Snapshot page metadata is inconsistent.'
  }

  $descriptors = [ordered]@{}
  for ($index = 0; $index -lt $pageRecordCount; $index += 1) {
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
    throw 'Snapshot page contains trailing data.'
  }

  return [pscustomobject]@{
    GenerationId = $generationId
    Reason = [string]$reasonFrame.Value
    PageIndex = $pageIndex
    PageCount = $pageCount
    TotalRecordCount = $totalRecordCount
    PageRecordCount = $pageRecordCount
    Descriptors = $descriptors
  }
}

function ConvertFrom-ConsumerDiscoverySnapshotGeneration {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Bodies
  )

  if ($Bodies.Count -lt 1) {
    throw 'Snapshot generation has no pages.'
  }
  $pages = @{}
  $pageBodies = @{}
  $generationId = -1
  $reason = $null
  $pageCount = -1
  $totalRecordCount = -1
  $receivedRecordCount = 0
  foreach ($body in $Bodies) {
    $page = ConvertFrom-ConsumerDiscoverySnapshotPageBody -Body $body
    if ($generationId -lt 0) {
      $generationId = $page.GenerationId
      $reason = $page.Reason
      $pageCount = $page.PageCount
      $totalRecordCount = $page.TotalRecordCount
    }
    if ($page.GenerationId -ne $generationId -or $page.Reason -cne $reason -or $page.PageCount -ne $pageCount -or $page.TotalRecordCount -ne $totalRecordCount) {
      throw 'Snapshot generation metadata differs between pages.'
    }
    if ($pages.ContainsKey($page.PageIndex)) {
      if ([string]$pageBodies[$page.PageIndex] -ceq $body) {
        continue
      }
      throw 'Snapshot generation contains a conflicting duplicate page.'
    }
    $pages[$page.PageIndex] = $page
    $pageBodies[$page.PageIndex] = $body
    $receivedRecordCount += $page.PageRecordCount
  }
  if ($pages.Count -ne $pageCount -or $receivedRecordCount -ne $totalRecordCount) {
    throw 'Snapshot generation is incomplete.'
  }

  $descriptors = [ordered]@{}
  for ($pageIndex = 0; $pageIndex -lt $pageCount; $pageIndex += 1) {
    if (!$pages.ContainsKey($pageIndex)) {
      throw "Snapshot generation is missing page $pageIndex."
    }
    foreach ($descriptor in $pages[$pageIndex].Descriptors.Values) {
      if (!$descriptors.Contains([string]$descriptor.ConsumerId)) {
        $descriptors[[string]$descriptor.ConsumerId] = $descriptor
      }
    }
  }
  return $descriptors
}

function Assert-ConsumerDiscoveryParserFixtures {
  $delimiterRecord = New-ConsumerDiscoveryDescriptorRecord -DisplayName 'A | B ; C ~ D'
  $delimiterResult = ConvertFrom-ConsumerDiscoverySnapshotBody -Body (New-ConsumerDiscoverySnapshotBody -Records @($delimiterRecord))
  if ($delimiterResult.Count -ne 1 -or $delimiterResult['a8098c1a-f86e-4b1e-9d7c-5a102bf38460'].DisplayName -cne 'A | B ; C ~ D') {
    throw 'Length-prefixed parser fixture did not preserve delimiter-like display-name characters.'
  }

  $maximumConsumerId = '{A8098C1A-F86E-4B1E-9D7C-5A102BF38460}'
  $maximumAssetNamespace = 'a.' + ('b' * 62)
  $maximumNormalMoviePath = "VenworksCanvas/Consumers/$maximumAssetNamespace/normal.swf"
  $maximumLargeMoviePath = "VenworksCanvas/Consumers/$maximumAssetNamespace/large.swf"
  $maximumRecord = New-ConsumerDiscoveryDescriptorRecord `
    -ConsumerId $maximumConsumerId `
    -DisplayName ('D' * 80) `
    -NormalMoviePath $maximumNormalMoviePath `
    -LargeMoviePath $maximumLargeMoviePath `
    -DescriptorVersion 9999
  $maximumResult = ConvertFrom-ConsumerDiscoverySnapshotBody -Body (New-ConsumerDiscoverySnapshotBody -Records @($maximumRecord))
  if ($maximumRecord.Length -ne 336 -or $maximumResult.Count -ne 1 -or !$maximumResult.Contains((ConvertTo-ConsumerDiscoveryUuid -Value $maximumConsumerId))) {
    throw 'Parser fixture rejected the maximum valid canonical descriptor.'
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
  if ($duplicateResult.Count -ne 1 -or $duplicateResult['a8098c1a-f86e-4b1e-9d7c-5a102bf38460'].DisplayName -cne 'FIRST') {
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
  if ($invalidThenValid.Count -ne 1 -or !$invalidThenValid.Contains('a8098c1a-f86e-4b1e-9d7c-5a102bf38460')) {
    throw 'Parser fixture allowed one invalid descriptor to poison a later valid descriptor.'
  }

  $consumerB = New-ConsumerDiscoveryDescriptorRecord `
    -ConsumerId 'beef70b2-024e-4e9b-a8d5-70a0c882c431' `
    -DisplayName 'VWCANVAS-9 Consumer B'
  $page0 = New-ConsumerDiscoverySnapshotBody -Records @($first) -GenerationId 10 -PageIndex 0 -PageCount 2 -TotalRecordCount 2
  $page1 = New-ConsumerDiscoverySnapshotBody -Records @($consumerB) -GenerationId 10 -PageIndex 1 -PageCount 2 -TotalRecordCount 2
  $multiPageResult = ConvertFrom-ConsumerDiscoverySnapshotGeneration -Bodies @($page1, $page0)
  if ($multiPageResult.Count -ne 2 -or !$multiPageResult.Contains('a8098c1a-f86e-4b1e-9d7c-5a102bf38460') -or !$multiPageResult.Contains('beef70b2-024e-4e9b-a8d5-70a0c882c431')) {
    throw 'Parser fixture did not atomically assemble a complete out-of-order multipage generation.'
  }

  $lastComplete = ConvertFrom-ConsumerDiscoverySnapshotBody -Body (New-ConsumerDiscoverySnapshotBody -Records @($first) -GenerationId 9)
  $missingPageRejected = $false
  try {
    [void](ConvertFrom-ConsumerDiscoverySnapshotGeneration -Bodies @($page0))
  }
  catch {
    $missingPageRejected = $true
  }
  if (!$missingPageRejected) {
    throw 'Parser fixture accepted a generation with a missing page.'
  }
  if ($lastComplete.Count -ne 1 -or !$lastComplete.Contains('a8098c1a-f86e-4b1e-9d7c-5a102bf38460')) {
    throw 'A missing page mutated the previously complete generation fixture.'
  }

  $duplicatePageResult = ConvertFrom-ConsumerDiscoverySnapshotGeneration -Bodies @($page0, $page0, $page1)
  if ($duplicatePageResult.Count -ne 2 -or !$duplicatePageResult.Contains('a8098c1a-f86e-4b1e-9d7c-5a102bf38460') -or !$duplicatePageResult.Contains('beef70b2-024e-4e9b-a8d5-70a0c882c431')) {
    throw 'Parser fixture did not treat identical duplicate-page delivery idempotently.'
  }

  $conflictingPage0 = New-ConsumerDiscoverySnapshotBody -Records @($consumerB) -GenerationId 10 -PageIndex 0 -PageCount 2 -TotalRecordCount 2
  $conflictingDuplicateRejected = $false
  try {
    [void](ConvertFrom-ConsumerDiscoverySnapshotGeneration -Bodies @($page0, $conflictingPage0, $page1))
  }
  catch {
    $conflictingDuplicateRejected = $true
  }
  if (!$conflictingDuplicateRejected) {
    throw 'Parser fixture accepted a conflicting duplicate snapshot page.'
  }

  $inconsistentPage = New-ConsumerDiscoverySnapshotBody -Records @($consumerB) -GenerationId 10 -Reason 'different' -PageIndex 1 -PageCount 2 -TotalRecordCount 2
  $inconsistentRejected = $false
  try {
    [void](ConvertFrom-ConsumerDiscoverySnapshotGeneration -Bodies @($page0, $inconsistentPage))
  }
  catch {
    $inconsistentRejected = $true
  }
  if (!$inconsistentRejected) {
    throw 'Parser fixture accepted inconsistent snapshot-page metadata.'
  }

  $incompleteSuperseded = $false
  try {
    [void](ConvertFrom-ConsumerDiscoverySnapshotGeneration -Bodies @($page0))
  }
  catch {
    $incompleteSuperseded = $true
  }
  if (!$incompleteSuperseded) {
    throw 'Superseding-generation fixture unexpectedly accepted the incomplete older generation.'
  }
  $supersedingResult = ConvertFrom-ConsumerDiscoverySnapshotGeneration -Bodies @(
    (New-ConsumerDiscoverySnapshotBody -Records @($consumerB) -GenerationId 11)
  )
  if ($supersedingResult.Count -ne 1 -or !$supersedingResult.Contains('beef70b2-024e-4e9b-a8d5-70a0c882c431')) {
    throw 'A newer complete generation did not supersede an incomplete generation fixture.'
  }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$consumerRoot = Join-Path $repositoryRoot 'Scaleform\probes\consumer-discovery'
$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot

if ($SourceOnly -and $ArtifactsOnly) {
  throw 'SourceOnly and ArtifactsOnly cannot be combined.'
}

if ([int]$matrix.Version -ne 7 -or [string]$matrix.Protocol -cne 'VWCANVAS_REGISTRY_PROBE/3' -or
    [string]$matrix.TestMode -cne 'RegistrationOnlyBridgeDisabled' -or
    [string]$matrix.UiLoadResult -cne 'REGISTERED_TRANSPORT_DISABLED') {
  throw 'Consumer-discovery matrix must declare the v6 bridge-disabled registration test contract.'
}

function Assert-ExactOrdinalList {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Actual,

    [Parameter(Mandatory = $true)]
    [string[]]$Expected,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  if ($Actual.Count -ne $Expected.Count -or
      [string]::Join("`n", $Actual) -cne [string]::Join("`n", $Expected)) {
    throw "$Description differs. Expected [$([string]::Join(', ', $Expected))]; found [$([string]::Join(', ', $Actual))]."
  }
}

function Get-SpriggitYamlListValues {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Lines,

    [Parameter(Mandatory = $true)]
    [int]$HeaderIndex,

    [Parameter(Mandatory = $true)]
    [string]$Prefix
  )

  $values = [Collections.Generic.List[string]]::new()
  for ($index = $HeaderIndex + 1; $index -lt $Lines.Count; $index++) {
    $line = $Lines[$index]
    if (!$line.StartsWith($Prefix, [StringComparison]::Ordinal)) {
      break
    }
    $values.Add($line.Substring($Prefix.Length))
  }
  return @($values)
}

function Assert-SpriggitPluginHeader {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$FileName,

    [Parameter(Mandatory = $true)]
    [string[]]$ExpectedMasters
  )

  [string[]]$lines = Get-Content -LiteralPath $Path
  $flagsHeaderIndex = [Array]::IndexOf($lines, '  Flags:')
  if ($flagsHeaderIndex -lt 0) {
    throw "Tracked Spriggit header for '$FileName' is missing its Flags list."
  }
  $flags = @(Get-SpriggitYamlListValues -Lines $lines -HeaderIndex $flagsHeaderIndex -Prefix '  - ')
  Assert-ExactOrdinalList -Actual $flags -Expected @('Master', 'Light') -Description "Tracked Spriggit header flags for '$FileName'"

  $formVersionLines = @($lines | Where-Object { $_ -ceq '  FormVersion: 582' })
  if ($formVersionLines.Count -ne 1) {
    throw "Tracked Spriggit header for '$FileName' must contain exactly one FormVersion 582 declaration."
  }

  $masterHeaderIndex = [Array]::IndexOf($lines, '  MasterReferences:')
  if ($masterHeaderIndex -lt 0) {
    throw "Tracked Spriggit header for '$FileName' is missing its MasterReferences list."
  }
  $masters = @(Get-SpriggitYamlListValues -Lines $lines -HeaderIndex $masterHeaderIndex -Prefix '  - Master: ')
  Assert-ExactOrdinalList -Actual $masters -Expected $ExpectedMasters -Description "Tracked Spriggit master list for '$FileName'"
}

function Assert-SpriggitQuestContract {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PluginYamlPath,

    [Parameter(Mandatory = $true)]
    [string]$FileName,

    [Parameter(Mandatory = $true)]
    [string[]]$ExpectedEditorIds
  )

  $questRoot = Resolve-ConsumerDiscoveryRequiredDirectory `
    -Path (Join-Path $PluginYamlPath 'Quests') `
    -Description "Tracked Spriggit quest root for '$FileName'"
  $questFiles = @(Get-ChildItem -LiteralPath $questRoot -File -Recurse -Filter 'RecordData.yaml')
  $actualEditorIds = [Collections.Generic.List[string]]::new()
  foreach ($questFile in $questFiles) {
    [string[]]$lines = Get-Content -LiteralPath $questFile.FullName
    $editorIdLines = @($lines | Where-Object { $_.StartsWith('EditorID: ', [StringComparison]::Ordinal) })
    if ($editorIdLines.Count -ne 1) {
      throw "Tracked Spriggit quest '$($questFile.FullName)' must contain exactly one EditorID."
    }
    $editorId = $editorIdLines[0].Substring('EditorID: '.Length)
    $actualEditorIds.Add($editorId)

    if ($FileName -ceq 'Venworks-Canvas-Host.esm' -and $editorId -ceq 'VWCANVAS9_ConsumerDiscoveryRegistry') {
      $vmAdapterIndex = [Array]::IndexOf($lines, 'VirtualMachineAdapter:')
      $versioningIndex = [Array]::IndexOf($lines, '  Versioning:')
      if ($vmAdapterIndex -lt 0 -or $versioningIndex -le $vmAdapterIndex) {
        throw "Tracked Spriggit Host quest '$($questFile.FullName)' is missing its VM adapter boundaries."
      }
      $actualVmAdapter = [string[]]$lines[$vmAdapterIndex..$versioningIndex]
      $expectedVmAdapter = [string[]]@(
        'VirtualMachineAdapter:'
        '  Scripts:'
        '  - Name: Venworks:Canvas:Probes:ConsumerDiscovery:Registry'
        '    Properties:'
        '    - MutagenObjectType: ScriptStructListProperty'
        '      Name: Consumers'
        '      Structs:'
        '      - Members:'
        '        - MutagenObjectType: ScriptObjectProperty'
        '          Name: Owner'
        '        - MutagenObjectType: ScriptStringProperty'
        '          Name: ConsumerId'
        "          Data: ''"
        '        - MutagenObjectType: ScriptStringProperty'
        '          Name: DisplayName'
        "          Data: ''"
        '        - MutagenObjectType: ScriptStringProperty'
        '          Name: NormalMovieUrl'
        "          Data: ''"
        '        - MutagenObjectType: ScriptStringProperty'
        '          Name: LargeMovieUrl'
        "          Data: ''"
        '        - MutagenObjectType: ScriptIntProperty'
        '          Name: DescriptorVersion'
        '  Versioning:'
      )
      Assert-ExactOrdinalList `
        -Actual $actualVmAdapter `
        -Expected $expectedVmAdapter `
        -Description "Tracked Spriggit Host Consumers typed default seed for '$($questFile.FullName)'"
    }

    $formVersionLines = @($lines | Where-Object { $_ -ceq 'FormVersion: 582' })
    if ($formVersionLines.Count -ne 1) {
      throw "Tracked Spriggit quest '$($questFile.FullName)' must contain exactly one FormVersion 582 declaration."
    }

    $dataIndex = [Array]::IndexOf($lines, 'Data:')
    if ($dataIndex -lt 0 -or $dataIndex + 1 -ge $lines.Count -or $lines[$dataIndex + 1] -cne '  Flags:') {
      throw "Tracked Spriggit quest '$($questFile.FullName)' is missing its Data Flags list."
    }
    $flags = @(Get-SpriggitYamlListValues -Lines $lines -HeaderIndex ($dataIndex + 1) -Prefix '  - ')
    Assert-ExactOrdinalList `
      -Actual $flags `
      -Expected @('StartGameEnabled', 'StartsEnabled') `
      -Description "Tracked Spriggit quest flags for '$($questFile.FullName)'"
    if ($lines -ccontains '  - RunOnce') {
      throw "Tracked Spriggit quest '$($questFile.FullName)' must not retain RunOnce."
    }
  }

  Assert-ExactOrdinalList `
    -Actual @($actualEditorIds | Sort-Object) `
    -Expected @($ExpectedEditorIds | Sort-Object) `
    -Description "Tracked Spriggit quest inventory for '$FileName'"
}
function Assert-TrackedSpriggitPluginContract {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PluginYamlPath,
    [Parameter(Mandatory = $true)]
    [string]$FileName,
    [Parameter(Mandatory = $true)]
    [string]$PluginKey,
    [Parameter(Mandatory = $true)]
    [string]$ProfileKey
  )

  $expectedMasters = @('Starfield.esm', 'Venworks-Core.esm')
  if ($PluginKey -cne 'Host') {
    $expectedMasters += 'Venworks-Canvas-Host.esm'
  }
  Assert-SpriggitPluginHeader -Path (Join-Path $PluginYamlPath 'RecordData.yaml') -FileName $FileName -ExpectedMasters $expectedMasters
  $expectedQuestEditorIds = switch ($PluginKey) {
    'Host' { @('VWCANVAS9_ConsumerDiscoveryRegistry') }
    'ConsumerA' {
      'VWCANVAS9_ConsumerARegistrar'
      if ($ProfileKey -ceq 'UpdatedA') { 'VWCANVAS9_ConsumerAUpdateMigration' }
    }
    'ConsumerB' {
      'VWCANVAS9_ConsumerBRegistrar'
      if ($ProfileKey -ceq 'Faults') {
        'VWCANVAS9_ConsumerBCollisionProbe'
        'VWCANVAS9_ConsumerBMissingProbe'
      }
    }
    default { throw "Unknown plugin key '$PluginKey' in the consumer-discovery matrix." }
  }
  Assert-SpriggitQuestContract -PluginYamlPath $PluginYamlPath -FileName $FileName -ExpectedEditorIds @($expectedQuestEditorIds)
}

if ([string]$matrix.Spriggit.PackageName -cne 'Spriggit.Yaml' -or
    [string]$matrix.Spriggit.MetadataPackageName -cne 'Spriggit.Yaml.Starfield' -or
    [string]$matrix.Spriggit.Version -cne '0.40.1' -or
    [string]$matrix.Spriggit.CliSha256 -cne '01E71FC882061F7387A5DC25022940A9A79892B81292C6B47F4DA2437649DCA5' -or
    [string]$matrix.Spriggit.TranslatorSha256 -cne 'E4358BFFA6E79723824764A5255A1ECA3A4FC14F10478FA42BA81ED58D7F1036' -or
    [string]$matrix.Spriggit.OutputRoot -cne 'Spriggit/ConsumerDiscovery') {
  throw 'Consumer discovery must pin the approved Spriggit YAML-only review contract.'
}

$expectedPackageKeys = [string[]]@('Host', 'ConsumerA', 'ConsumerB')
$expectedMovieKeys = [string[]]@('Host', 'ConsumerA', 'ConsumerAUpdated', 'ConsumerB')
foreach ($sectionName in @('Plugins', 'Staging')) {
  $keys = @($matrix[$sectionName].Key)
  if ($keys.Count -ne 3 -or [string]::Join("`n", @($keys | Sort-Object)) -cne [string]::Join("`n", @($expectedPackageKeys | Sort-Object))) {
    throw "Matrix section '$sectionName' must contain exactly Host, ConsumerA, and ConsumerB."
  }
}
$expectedStagingByKey = @{
  Host = @{ Directory = 'Staging-Host'; Plugin = 'Venworks-Canvas-Host.esm'; Archive = 'Venworks-Canvas-Host - Main.ba2' }
  ConsumerA = @{ Directory = 'Staging-ConsumerA'; Plugin = 'Venworks-Canvas-ConsumerA.esm'; Archive = 'Venworks-Canvas-ConsumerA - Main.ba2' }
  ConsumerB = @{ Directory = 'Staging-ConsumerB'; Plugin = 'Venworks-Canvas-ConsumerB.esm'; Archive = 'Venworks-Canvas-ConsumerB - Main.ba2' }
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
if (@($matrix.Movies).Count -ne 4 -or
    [string]::Join("`n", @($matrix.Movies.Key | Sort-Object)) -cne [string]::Join("`n", @($expectedMovieKeys | Sort-Object))) {
  throw 'Matrix Movies must contain exactly Host, ConsumerA, ConsumerAUpdated, and ConsumerB.'
}

$requiredToolchainFiles = @($matrix.VwHudFixture.RequiredToolchainFiles)
if ($requiredToolchainFiles.Count -ne 2 -or
    [string]::Join("`n", @($requiredToolchainFiles | Sort-Object)) -cne [string]::Join("`n", @('Tools/compileScaleform.ps1', 'Tools/sharedScaleformMovies.ps1' | Sort-Object))) {
  throw 'Consumer discovery must pin exactly the VWHUD helper and compiler that its VWCANVAS-owned build invokes.'
}
$auxiliaryDerivedFiles = @($matrix.VwHudFixture.AuxiliaryDerivedFiles)
if ($auxiliaryDerivedFiles.Count -ne 1 -or [string]$auxiliaryDerivedFiles[0] -cne 'Tools/sharedScaleformMovies.ps1' -or
    [string]$matrix.VwHudFixture.ShipCompilerFile -cne 'Tools/compileScaleform.ps1') {
  throw 'Consumer discovery must distinguish its copied auxiliary helper from the VWHUD Ship HUD compiler it directly invokes.'
}
if (@($matrix.VwHudFixture.PlayerHudMovies).Count -ne 4) {
  throw 'Consumer discovery must stage the exact four VWHUD player HUD movie variants.'
}
$coreSources = @($matrix.VenworksCoreFixture.SourceFiles)
$coreRuntimeScripts = @($matrix.VenworksCoreFixture.RuntimeScripts)
if ($coreSources.Count -ne 6 -or $coreRuntimeScripts.Count -ne 6 -or
    [string]::IsNullOrWhiteSpace([string]$matrix.VenworksCoreFixture.Revision)) {
  throw 'Consumer discovery must pin six required Venworks Core sources and matching runtime scripts, including UUID utilities/tests.'
}

$profileKeys = @($matrix.Profiles.Key)
if ($profileKeys.Count -ne 3 -or
    [string]::Join("`n", @($profileKeys | Sort-Object)) -cne [string]::Join("`n", @('Baseline', 'Faults', 'UpdatedA' | Sort-Object))) {
  throw 'Consumer discovery must define exactly the Baseline, Faults, and UpdatedA profiles.'
}
$resolvedProfile = Resolve-ConsumerDiscoveryProfile -Matrix $matrix -ProbeProfile $ProbeProfile
foreach ($profileDefinition in @($matrix.Profiles)) {
  $profilePluginKeys = @($profileDefinition.PluginSha256.Keys | Sort-Object)
  if ([string]::Join("`n", $profilePluginKeys) -cne [string]::Join("`n", @($expectedPackageKeys | Sort-Object))) {
    throw "Profile '$($profileDefinition.Key)' does not pin exactly the Host, ConsumerA, and ConsumerB plugin hashes."
  }
  foreach ($packageKey in $expectedPackageKeys) {
    if ([string]$profileDefinition.PluginSha256[$packageKey] -notmatch '^[0-9A-F]{64}$') {
      throw "Profile '$($profileDefinition.Key)' contains an invalid pinned plugin hash for '$packageKey'."
    }
  }
}

# Committed YAML contracts require no game toolchain and run for every profile even in SourceOnly CI.
foreach ($profileDefinition in @($matrix.Profiles)) {
  foreach ($plugin in @($matrix.Plugins)) {
    $pluginYamlPath = Join-Path $repositoryRoot ([string]$matrix.Spriggit.OutputRoot) ([string]$profileDefinition.Key) ([string]$plugin.FileName)
    Assert-TrackedSpriggitPluginContract `
      -PluginYamlPath $pluginYamlPath `
      -FileName ([string]$plugin.FileName) `
      -PluginKey ([string]$plugin.Key) `
      -ProfileKey ([string]$profileDefinition.Key)
  }
}

$requiredParserCases = @(
  'delimiter-display-name'
  'maximum-valid-descriptor'
  'invalid-consumer-id'
  'path-traversal'
  'duplicate-id'
  'invalid-version'
  'truncated-record'
  'oversized-field'
  'invalid-plus-valid'
  'complete-multipage'
  'missing-page'
  'duplicate-page'
  'conflicting-duplicate-page'
  'inconsistent-page-metadata'
  'superseded-generation'
)
$parserCases = @($matrix.ParserCases)
if ($parserCases.Count -ne $requiredParserCases.Count) {
  throw 'Parser matrix must contain exactly the fifteen approved framing, paging, and isolation cases.'
}
foreach ($caseId in $requiredParserCases) {
  if (@($parserCases | Where-Object { [string]$_.Id -ceq $caseId }).Count -ne 1) {
    throw "Parser matrix is missing exact case '$caseId'."
  }
}
Assert-ConsumerDiscoveryParserFixtures

$requiredRegistrationCases = @('pc-console-resolution', 'pc-console-host-recovery', 'pc-console-update-recovery', 'pc-registration-host-only', 'pc-registration-consumer-a', 'pc-registration-two-consumers', 'pc-registration-reload', 'pc-registration-rejection', 'pc-registration-ui-ownership', 'pc-registration-uuid-case', 'pc-registration-legacy-migration', 'pc-registration-concurrent-owners', 'pc-registration-pending-update')
Assert-ExactOrdinalList `
  -Actual @($matrix.RegistrationRuntimeCases.Id) `
  -Expected $requiredRegistrationCases `
  -Description 'Bridge-disabled PC registration cases'

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
  'Papyrus\Venworks\Canvas\Base\BaseQuest.psc'
  'Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\Registry.psc'
  'Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerARegistrar.psc'
  'Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerBRegistrar.psc'
  'Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerAUpdateMigration.psc'
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

$baseQuestPath = Join-Path $repositoryRoot 'Papyrus\Venworks\Canvas\Base\BaseQuest.psc'
$baseQuestSource = [System.IO.File]::ReadAllText($baseQuestPath)
foreach ($token in @(
  'Extends Venworks:Core:Base:BaseQuest'
  'Import Venworks:Core:Enumerations'
  'Import Venworks:Core:Logging'
  'Import Venworks:Canvas:GlobalConfig'
  'Function LogUserInformational('
  'Function LogUserWarning('
  'Function LogUserError('
  'Function LogUserCritical('
)) {
  if (!$baseQuestSource.Contains($token)) {
    throw "Canvas BaseQuest is missing Core integration token '$token'."
  }
}

$registrySource = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\Registry.psc'))
foreach ($token in @(
  'Extends Venworks:Canvas:Base:BaseQuest'
  'Struct ConsumerRegistration'
  'Guard RegistryGuard ProtectsFunctionLogic'
  'TryLockGuard RegistryGuard'
  'Venworks:Core:Utilities:UUID.AreEqual'
  'Venworks:Core:Utilities:UUID.Normalize'
  'MigrateConsumerIdentityLocked'
  'IsMoviePairValid'
  'ConsumerRegistration[] Property Consumers Auto Mandatory'
  'Quest Owner'
  'Consumers.Add(registration)'
  'Consumers[existingIndex].Owner != owner'
  'Consumers[index].Owner == None'
  'EnsureStorageLocked(result)'
  'Consumers = new ConsumerRegistration[0]'
  'String Function RequestUiLoad(Quest owner, String consumerId)'
  'Return "REGISTERED_TRANSPORT_DISABLED"'
  'Return "REJECTED_NOT_REGISTERED"'
  'Return "REJECTED_OWNER_MISMATCH"'
  'Consumers[index].Owner != owner'
  'GetDescriptorRejectionReason('
  'GetConsumerIdRejectionReason('
  'GetPrintableAsciiRejectionReason('
  'REGISTRATION_REJECTED'
  'REGISTRATION_UNCHANGED'
  'Function EnsureMenuSubscriptions()'
  'MenuSubscriptionsInitialized = True'
  'Consumers[index] == None'
  'WATCH BRIDGE DISABLED'
  'RegisterForMenuOpenCloseEvent("HUDMenu")'
  'RegisterForMenuOpenCloseEvent("SpaceshipHudMenu")'
  'Utility.SplitStringChars'
  'MaxConsumerMovieUrlCharacters'
  'LogUserInformational('
  'LogUserWarning('
)) {
  if (!$registrySource.Contains($token)) {
    throw "Dynamic Papyrus registry is missing token '$token'."
  }
}
if ([regex]::Matches($registrySource, [regex]::Escape('Consumers = new ConsumerRegistration[0]')).Count -ne 1 -or
    ![regex]::IsMatch(
      $registrySource,
      'If\s+\(Consumers == None\)\s+Consumers = new ConsumerRegistration\[0\].*?EndIf',
      [Text.RegularExpressions.RegexOptions]::Singleline)) {
  throw 'Dynamic Papyrus registry must initialize missing Consumers storage exactly once inside its None guard.'
}
foreach ($forbiddenToken in @('ConsumerRegistration[] Consumers', 'ConsumerRegistration[] Property Consumers Auto Const', 'registry-storage-missing', 'MaxConsumers', 'ConsumerOwners', 'ConsumerIds', 'DisplayNames', 'NormalMoviePaths', 'LargeMoviePaths', 'DescriptorVersions', 'Debug.Trace', 'Utility.Wait')) {
  if ($registrySource.Contains($forbiddenToken)) {
    throw "Dynamic Papyrus registry retained forbidden parallel-storage, fixed-capacity, or direct-log token '$forbiddenToken'."
  }
}

if (![regex]::IsMatch($registrySource, '(?s)Bool Function PublishSnapshot\([^\r\n]*\)\s+LogDisabledPublication\(\)\s+Return False\s+EndFunction') -or
    ![regex]::IsMatch($registrySource, '(?s)Function PublishDiagnostic\([^\r\n]*\)\s+LogDisabledPublication\(\)\s+EndFunction') -or
    [regex]::IsMatch($registrySource, '(?im)^\s*(?:PublishSnapshot|PublishDiagnostic)\(')) {
  throw 'Legacy publishers must remain inert with no internal callers.'
}
foreach ($functionContract in @(
  @{ Type = 'String'; Name = 'GetDescriptorRejectionReason'; Return = '""' },
  @{ Type = 'String'; Name = 'GetConsumerIdRejectionReason'; Return = '""' },
  @{ Type = 'String'; Name = 'GetPrintableAsciiRejectionReason'; Return = '""' }
)) {
  $functionPattern = '(?ims)^' + $functionContract.Type + ' Function ' + $functionContract.Name + '\([^\r\n]*\)\s*(?<body>.*?)^EndFunction'
  $functionMatch = [regex]::Match($registrySource, $functionPattern)
  if (!$functionMatch.Success -or
      $functionMatch.Groups['body'].Value.TrimEnd() -cnotmatch ('Return ' + [regex]::Escape($functionContract.Return) + '$')) {
    throw "Registry '$($functionContract.Name)' must return $($functionContract.Return) after its successful path; implicit Papyrus casts are not acceptable."
  }
}

# Keep lifecycle and transitive guard checks in the focused verifier, separate from artifact inspection.
& (Join-Path $PSScriptRoot 'testConsumerDiscoveryGuards.ps1')
& (Join-Path $PSScriptRoot 'testConsumerDiscoveryConsole.ps1')
foreach ($consumerName in @('ConsumerARegistrar.psc', 'ConsumerBRegistrar.psc')) {
  $consumerSource = Get-Content -LiteralPath (Join-Path $repositoryRoot "Papyrus/Venworks/Canvas/Probes/ConsumerDiscovery/$consumerName") -Raw
  foreach ($token in @('Extends Venworks:Canvas:Base:BaseQuest', 'Property Registry Auto Const Mandatory', 'String Property ConsumerId Auto Const Mandatory', 'String Property NormalMoviePath Auto Const Mandatory', 'Int Property DescriptorVersion Auto Const Mandatory', 'Bool Property ExpectedRegistration Auto Const Mandatory', 'Float Property InitialDelaySeconds Auto Const Mandatory')) {
    if (!$consumerSource.Contains($token)) { throw "Papyrus consumer '$consumerName' is missing token '$token'." }
  }
  if ($consumerSource.Contains('Interface/VenworksCanvas/') -or $consumerSource.Contains('Debug.Trace')) {
    throw "Papyrus consumer '$consumerName' retained an Interface-prefixed path or direct logging."
  }
}

foreach ($papyrusPath in @(
  $baseQuestPath
  (Join-Path $repositoryRoot 'Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\Registry.psc')
  (Join-Path $repositoryRoot 'Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerARegistrar.psc')
  (Join-Path $repositoryRoot 'Papyrus\Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerBRegistrar.psc')
)) {
  $lines = [System.IO.File]::ReadAllLines($papyrusPath)
  for ($lineIndex = 0; $lineIndex -lt $lines.Length; $lineIndex += 1) {
    if ($lines[$lineIndex] -match '^\s*(?:(?:Bool|Int|String|Float|Var)\s+)?Function\s+') {
      $commentIndex = $lineIndex - 1
      while ($commentIndex -ge 0 -and [string]::IsNullOrWhiteSpace($lines[$commentIndex])) {
        $commentIndex -= 1
      }
      if ($commentIndex -lt 0 -or !$lines[$commentIndex].TrimStart().StartsWith(';')) {
        throw "Public Papyrus function at '${papyrusPath}:$($lineIndex + 1)' lacks an immediately preceding description comment."
      }
    }
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
  'pendingGenerationId'
  'pendingPages'
  'pendingPageBodies'
  'pendingHasRejectedDescriptor'
  'commitPendingGeneration()'
  'resetPendingGeneration()'
  'conflicting duplicate snapshot page'
  'this.reconcile(desired,!this.pendingHasRejectedDescriptor)'
  'inconsistent snapshot generation metadata'
  'this.getLoaderIds()'
  'this.dataManager.Unsubscribe(PROVIDER,this.callback)'
  'REGISTRATION LOG TEST'
  'WATCH BRIDGE DISABLED'
  'CONSUMER MOVIES NOT LOADED'
)) {
  if (!$hostSource.Contains($token)) {
    throw "Dynamic ActionScript host is missing token '$token'."
  }
}
if ($hostSource.Contains('Interface/VenworksCanvas/')) {
  throw 'Dynamic ActionScript host retained an Interface-prefixed loader path.'
}
if ($hostSource.Contains('MAX_CONSUMERS')) {
  throw 'Dynamic ActionScript host retained a fixed total consumer limit.'
}
$shipPatchSource = [System.IO.File]::ReadAllText((Join-Path $consumerRoot 'patches\spaceship-hud-auxiliary-loader.xml'))
foreach ($token in @(
  'addChild(this.VenworksCanvasRegistryLoader)'
  'removeChild(this.VenworksCanvasRegistryLoader)'
  'this.VenworksCanvasRegistryLoader.parent !== this'
  'this.VenworksCanvasRegistryLoader.parent === this'
)) {
  if (!$shipPatchSource.Contains($token)) {
    throw "Ship HUD auxiliary patch is missing Loader ownership token '$token'."
  }
}
foreach ($forbiddenToken in @('addChild(loadedContent)', 'removeChild(loadedContent)')) {
  if ($shipPatchSource.Contains($forbiddenToken)) {
    throw "Ship HUD auxiliary patch retained forbidden Loader-content reparenting token '$forbiddenToken'."
  }
}
$loaderIdentityGuard = 'if(loader == null || this.loaders[loader.name] !== loader)'
if ([regex]::Matches($hostSource, [regex]::Escape($loaderIdentityGuard)).Count -ne 3) {
  throw 'Dynamic ActionScript host must reject stale init, completion, and error events from replaced loaders.'
}
if ($hostSource.Contains('.Subscribe(') -or $hostSource.Contains('.GetDataFromClient(') -or $hostSource.Contains('BRIDGE SUBSCRIBED')) {
  throw 'Bridge-disabled ActionScript must not subscribe, request provider data, or report an active bridge.'
}
foreach ($papyrusFile in @(Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'Papyrus\Venworks\Canvas') -Recurse -File -Filter '*.psc')) {
  if ([IO.File]::ReadAllText($papyrusFile.FullName) -match '(?i)ShowCustomWatchAlert') {
    throw "Bridge-disabled Canvas source contains a Watch Alert reference: $($papyrusFile.FullName)"
  }
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

foreach ($removedGeneratorPath in @('Tools\ConsumerDiscoveryPluginGenerator', 'Tools\generateConsumerDiscoveryPlugins.ps1')) {
  if (Test-Path -LiteralPath (Join-Path $repositoryRoot $removedGeneratorPath)) {
    throw "One-off plugin generator remains committed outside ignored .work: $removedGeneratorPath"
  }
}

$toolPaths = @(
  'Tools\sharedConsumerDiscoveryProbe.ps1'
  'Tools\buildConsumerDiscoveryProbe.ps1'
  'Tools\buildConsumerDiscoveryShipMovies.ps1'
  'Tools\compileConsumerDiscoveryScripts.ps1'
  'Tools\dumpConsumerDiscoveryPluginsToYaml.ps1'
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
if (!$allToolText.Contains('Spriggit.CLI.exe') -or
    !$allToolText.Contains('$spriggitTranslatorPath serialize') -or
    !$allToolText.Contains('Temp\Spriggit\Translations') -or
    !$allToolText.Contains('Spriggit.CliSha256') -or
    !$allToolText.Contains('Spriggit.TranslatorSha256') -or
    !$allToolText.Contains('changed during Spriggit serialization') -or
    !$allToolText.Contains('dumpConsumerDiscoveryPluginsToYaml.ps1') -or
    $allToolText.Contains('--Check') -or
    $allToolText.Contains(' deserialize ')) {
  throw 'Consumer-discovery tooling must use the pinned Spriggit translator to serialize review-only YAML and must never assemble plugins from it.'
}

$spriggitConfigPath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $repositoryRoot '.spriggit') `
  -Description 'Spriggit known-master configuration'
$spriggitConfig = Get-Content -LiteralPath $spriggitConfigPath -Raw | ConvertFrom-Json
foreach ($expectedKnownMaster in @(
  @{ ModKey = 'Starfield.esm'; Style = 'Full' }
  @{ ModKey = 'Venworks-Core.esm'; Style = 'Small' }
  @{ ModKey = 'Venworks-Canvas-Host.esm'; Style = 'Small' }
)) {
  $knownMasterMatches = @($spriggitConfig.KnownMasters | Where-Object {
    [string]$_.ModKey -ceq [string]$expectedKnownMaster.ModKey -and
    [string]$_.Style -ceq [string]$expectedKnownMaster.Style
  })
  if ($knownMasterMatches.Count -ne 1) {
    throw "Spriggit must contain exactly one $($expectedKnownMaster.Style) known-master entry for '$($expectedKnownMaster.ModKey)'."
  }
}

Write-Host -ForegroundColor Green "Verified bridge-disabled registration sources, all three tracked YAML contracts, profile '$($resolvedProfile.Key)', deferred parser fixtures, PC matrices, and PowerShell syntax."
& (Join-Path $PSScriptRoot 'testConsumerDiscoveryUuid.ps1')
& (Join-Path $PSScriptRoot 'testConsumerDiscoveryPackaging.ps1')

if ($SourceOnly) {
  return
}

if ([string]::IsNullOrWhiteSpace($VwHudRepositoryPath)) {
  throw 'VwHudRepositoryPath is required for full consumer-discovery verification.'
}
if ([string]::IsNullOrWhiteSpace($VenworksCoreRepositoryPath)) {
  throw 'VenworksCoreRepositoryPath is required for full consumer-discovery verification.'
}
$resolvedVwHudRoot = Assert-PinnedVwHudToolchainFixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
$resolvedVenworksCoreRoot = Assert-PinnedVenworksCoreFixture `
  -VenworksCoreRepositoryPath $VenworksCoreRepositoryPath `
  -Matrix $matrix
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
if ([string]$buildEvidence.Schema -cne 'VWCANVAS9_CONSUMER_DISCOVERY_BUILD/3' -or
    [string]$buildEvidence.CanvasPipeline -cne 'VWCANVAS_OWNED_VWHUD_V2_DERIVED/1' -or
    [string]$buildEvidence.VwHudRevision -cne [string]$matrix.VwHudFixture.Revision) {
  throw 'Auxiliary movie build evidence does not identify the exact VWCANVAS-owned, VWHUD-v2-derived build contract.'
}
$toolchainEvidence = @($buildEvidence.VwHudDerivedHelpers)
if ($toolchainEvidence.Count -ne $auxiliaryDerivedFiles.Count) {
  throw 'Auxiliary movie build evidence does not contain the exact copied VWHUD helper inventory.'
}
foreach ($relativePath in $auxiliaryDerivedFiles) {
  $toolchainMatches = @($toolchainEvidence | Where-Object { [string]$_.Path -ceq [string]$relativePath })
  if ($toolchainMatches.Count -ne 1) {
    throw "Auxiliary movie build evidence is missing exact derived helper '$relativePath'."
  }
  $toolPath = Join-Path $resolvedVwHudRoot ([string]$relativePath)
  if ([string]$toolchainMatches[0].Sha256 -cne (Get-FileSha256 -Path $toolPath)) {
    throw "Auxiliary movie derived-helper evidence hash drifted for '$relativePath'."
  }
}
$movieHashByKey = @{}
foreach ($movie in @($matrix.Movies)) {
  $moviePath = Join-Path $resolvedMoviesDirectory ([string]$movie.Output)
  $actualHash = Get-FileSha256 -Path $moviePath
  $sidecarHash = [System.IO.File]::ReadAllText("$moviePath.sha256").Trim().ToUpperInvariant()
  $evidenceMatches = @($buildEvidence.Movies | Where-Object { [string]$_.OutputFile -ceq [string]$movie.Output })
  if ($evidenceMatches.Count -ne 1) {
    throw "Auxiliary movie '$($movie.Key)' does not have exactly one build-evidence entry."
  }
  $manifestPath = Join-Path $consumerRoot ([string]$movie.Manifest)
  $buildDefinition = Get-ConsumerDiscoveryBuildDefinition -ManifestPath $manifestPath
  $expectedManifest = ([System.IO.Path]::GetRelativePath($consumerRoot, $buildDefinition.ManifestPath)).Replace('\', '/')
  $expectedSource = ([System.IO.Path]::GetRelativePath($consumerRoot, $buildDefinition.SourcePath)).Replace('\', '/')
  if ([string]$evidenceMatches[0].Manifest -cne $expectedManifest -or
      [string]$evidenceMatches[0].ManifestSha256 -cne (Get-FileSha256 -Path $buildDefinition.ManifestPath) -or
      [string]$evidenceMatches[0].Source -cne $expectedSource -or
      [string]$evidenceMatches[0].SourceSha256 -cne (Get-FileSha256 -Path $buildDefinition.SourcePath) -or
      [int]$evidenceMatches[0].BuildPasses -ne 2 -or
      @($evidenceMatches[0].ClassInventory).Count -ne 1 -or
      [string]$evidenceMatches[0].ClassInventory[0] -cne [string]$buildDefinition.ClassName) {
    throw "Auxiliary movie '$($movie.Key)' build evidence is not bound to its current manifest, source, and validated class."
  }
  if ($actualHash -cne $sidecarHash) {
    throw "Auxiliary movie '$($movie.Key)' does not match its deterministic hash sidecar."
  }
  if ($actualHash -cne [string]$evidenceMatches[0].Sha256) {
    throw "Auxiliary movie '$($movie.Key)' does not match its class/token-validated build evidence."
  }
  $movieHashByKey[[string]$movie.Key] = $actualHash
}
if (@($buildEvidence.Movies).Count -ne @($matrix.Movies).Count) {
  throw 'Auxiliary movie build evidence contains a missing, duplicate, or unexpected movie entry.'
}

Assert-ExactRelativeFileInventory `
  -Root $resolvedShipMoviesDirectory `
  -Expected @('build-evidence.json', 'spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf') `
  -Description 'Ship HUD movie output'
$shipBuildEvidencePath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $resolvedShipMoviesDirectory 'build-evidence.json') `
  -Description 'Ship HUD build evidence'
$shipBuildEvidence = Get-Content -LiteralPath $shipBuildEvidencePath -Raw | ConvertFrom-Json
$shipCompilerPath = Join-Path $resolvedVwHudRoot ([string]$matrix.VwHudFixture.ShipCompilerFile)
if ([string]$shipBuildEvidence.Schema -cne 'VWCANVAS9_CONSUMER_DISCOVERY_SHIP_BUILD/1' -or
    [string]$shipBuildEvidence.VwHudRevision -cne [string]$matrix.VwHudFixture.Revision -or
    [string]$shipBuildEvidence.VwHudCompiler.Path -cne [string]$matrix.VwHudFixture.ShipCompilerFile -or
    [string]$shipBuildEvidence.VwHudCompiler.Sha256 -cne (Get-FileSha256 -Path $shipCompilerPath)) {
  throw 'Ship HUD build evidence does not identify the exact invoked VWHUD compiler.'
}
$expectedShipInputs = @(
  'Scaleform/probes/consumer-discovery/build/spaceshiphudmenu.build.xml'
  'Scaleform/probes/consumer-discovery/build/spaceshiphudmenu-lrg.build.xml'
  'Scaleform/probes/consumer-discovery/patches/spaceship-hud-auxiliary-loader.xml'
)
if (@($shipBuildEvidence.Inputs).Count -ne $expectedShipInputs.Count) {
  throw 'Ship HUD build evidence does not contain the exact source-input inventory.'
}
foreach ($relativePath in $expectedShipInputs) {
  $shipInputMatches = @($shipBuildEvidence.Inputs | Where-Object { [string]$_.Path -ceq $relativePath })
  if ($shipInputMatches.Count -ne 1 -or [string]$shipInputMatches[0].Sha256 -cne (Get-FileSha256 -Path (Join-Path $repositoryRoot $relativePath))) {
    throw "Ship HUD build evidence drifted for '$relativePath'."
  }
}
$shipMovieHashes = @{}
foreach ($definition in @(
  @{ Output = 'spaceshiphudmenu.swf'; HashFile = 'spaceshiphudmenu.expected.sha256' }
  @{ Output = 'spaceshiphudmenu_lrg.swf'; HashFile = 'spaceshiphudmenu-lrg.expected.sha256' }
)) {
  $outputPath = Join-Path $resolvedShipMoviesDirectory ([string]$definition.Output)
  $expectedHash = Get-Sha256FileValue -Path (Join-Path $consumerRoot "build\$($definition.HashFile)")
  $actualHash = Get-FileSha256 -Path $outputPath
  $evidenceMatches = @($shipBuildEvidence.Movies | Where-Object { [string]$_.File -ceq [string]$definition.Output })
  if ($actualHash -cne $expectedHash) {
    throw "Patched Ship HUD movie '$($definition.Output)' does not match its pinned expected hash."
  }
  if ($evidenceMatches.Count -ne 1 -or [string]$evidenceMatches[0].Sha256 -cne $actualHash) {
    throw "Patched Ship HUD movie '$($definition.Output)' does not match its source-bound build evidence."
  }
  $shipMovieHashes[[string]$definition.Output] = $actualHash
}
if (@($shipBuildEvidence.Movies).Count -ne 2) {
  throw 'Ship HUD build evidence contains a missing, duplicate, or unexpected movie entry.'
}

Assert-ExactRelativeFileInventory `
  -Root $resolvedPluginsDirectory `
  -Expected @(@($matrix.Plugins.FileName) + 'generation-evidence.json') `
  -Description 'Generated plugin output'
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
foreach ($plugin in @($matrix.Plugins)) {
  $fileName = [string]$plugin.FileName
  $evidenceMatches = @($pluginGenerationEvidence.Plugins | Where-Object { [string]$_.FileName -ceq $fileName })
  if ($evidenceMatches.Count -ne 1) {
    throw "Plugin generation evidence does not contain exactly one '$fileName' entry."
  }
  $pluginPath = Join-Path $resolvedPluginsDirectory $fileName
  Assert-ConsumerDiscoveryNotGitLfsPointer `
    -Path $pluginPath `
    -Description "Generated plugin '$($plugin.Key)'"
  $expectedHash = [string]$resolvedProfile.PluginSha256[[string]$plugin.Key]
  if ([string]$evidenceMatches[0].Sha256 -cne $expectedHash -or
      (Get-FileSha256 -Path $pluginPath) -cne $expectedHash) {
    throw "Generated plugin '$fileName' does not match its profile-bound binary-readback evidence."
  }
}

$spriggitOutputRoot = Resolve-ConsumerDiscoveryRequiredDirectory `
  -Path (Join-Path $repositoryRoot ([string]$matrix.Spriggit.OutputRoot)) `
  -Description 'Tracked consumer-discovery Spriggit output root'
$spriggitProfilePath = Resolve-ConsumerDiscoveryRequiredDirectory `
  -Path (Join-Path $spriggitOutputRoot ([string]$resolvedProfile.Key)) `
  -Description "Tracked Spriggit output for profile '$($resolvedProfile.Key)'"
$expectedSpriggitProfileEntries = @('dump-evidence.json') + @($matrix.Plugins.FileName)
$actualSpriggitProfileEntries = @(Get-ChildItem -LiteralPath $spriggitProfilePath -Force | ForEach-Object { $_.Name } | Sort-Object)
if ($actualSpriggitProfileEntries.Count -ne $expectedSpriggitProfileEntries.Count -or
    [string]::Join("`n", $actualSpriggitProfileEntries) -cne [string]::Join("`n", @($expectedSpriggitProfileEntries | Sort-Object))) {
  throw "Tracked Spriggit profile '$($resolvedProfile.Key)' does not contain exactly its evidence and three plugin directories."
}
$spriggitEvidencePath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $spriggitProfilePath 'dump-evidence.json') `
  -Description "Tracked Spriggit evidence for profile '$($resolvedProfile.Key)'"
$spriggitEvidence = Get-Content -LiteralPath $spriggitEvidencePath -Raw | ConvertFrom-Json
if ([string]$spriggitEvidence.Schema -cne 'VWCANVAS9_CONSUMER_DISCOVERY_SPRIGGIT/2' -or
    [string]$spriggitEvidence.Profile -cne [string]$resolvedProfile.Key -or
    [string]$spriggitEvidence.PackageName -cne [string]$matrix.Spriggit.MetadataPackageName -or
    [string]$spriggitEvidence.SpriggitVersion -cne [string]$matrix.Spriggit.Version -or
    [string]$spriggitEvidence.SpriggitCliSha256 -cne [string]$matrix.Spriggit.CliSha256 -or
    [string]$spriggitEvidence.SpriggitTranslatorSha256 -cne [string]$matrix.Spriggit.TranslatorSha256 -or
    [string]$spriggitEvidence.PluginGenerationEvidenceSha256 -cne (Get-FileSha256 -Path $pluginGenerationEvidencePath) -or
    @($spriggitEvidence.Plugins).Count -ne @($matrix.Plugins).Count) {
  throw "Tracked Spriggit evidence does not match selected profile '$($resolvedProfile.Key)'."
}
foreach ($plugin in @($matrix.Plugins)) {
  $fileName = [string]$plugin.FileName
  $evidenceMatches = @($spriggitEvidence.Plugins | Where-Object {
    [string]$_.Key -ceq [string]$plugin.Key -and [string]$_.FileName -ceq $fileName
  })
  $pluginYamlPath = Resolve-ConsumerDiscoveryRequiredDirectory `
    -Path (Join-Path $spriggitProfilePath $fileName) `
    -Description "Tracked Spriggit YAML for '$fileName'"
  if ($evidenceMatches.Count -ne 1 -or
      [string]$evidenceMatches[0].Directory -cne $fileName -or
      [string]$evidenceMatches[0].EsmSha256 -cne [string]$resolvedProfile.PluginSha256[[string]$plugin.Key] -or
      [string]$evidenceMatches[0].YamlSha256 -cne (Get-ConsumerDiscoveryDirectoryDigest -Path $pluginYamlPath)) {
    throw "Tracked Spriggit YAML for '$fileName' does not match its profile-bound evidence."
  }

  $recordDataPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $pluginYamlPath 'RecordData.yaml') `
    -Description "Tracked Spriggit record data for '$fileName'"
  $recordData = [System.IO.File]::ReadAllText($recordDataPath)
  foreach ($token in @(
    "PackageName: $($matrix.Spriggit.MetadataPackageName)"
    "Version: $($matrix.Spriggit.Version)"
    "ModKey: $fileName"
    'GameRelease: Starfield'
  )) {
    if (!$recordData.Contains($token)) {
      throw "Tracked Spriggit record data for '$fileName' is missing token '$token'."
    }
  }

  Assert-TrackedSpriggitPluginContract `
    -PluginYamlPath $pluginYamlPath `
    -FileName $fileName `
    -PluginKey ([string]$plugin.Key) `
    -ProfileKey ([string]$resolvedProfile.Key)
}

$expectedScriptOutputs = @($matrix.Plugins | ForEach-Object { @($_.Scripts) })
$expectedScriptInventory = @('compile-evidence.json') + $expectedScriptOutputs
Assert-ExactRelativeFileInventory -Root $resolvedScriptsDirectory -Expected $expectedScriptInventory -Description 'Compiled Papyrus output'
$compileEvidencePath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $resolvedScriptsDirectory 'compile-evidence.json') `
  -Description 'Papyrus compile evidence'
$compileEvidence = Get-Content -LiteralPath $compileEvidencePath -Raw | ConvertFrom-Json
if ([string]$compileEvidence.Schema -cne 'VWCANVAS9_CONSUMER_DISCOVERY_SCRIPTS/1' -or
    [string]$compileEvidence.VenworksCoreRevision -cne [string]$matrix.VenworksCoreFixture.Revision -or
    @($compileEvidence.Scripts).Count -ne ($expectedScriptInventory.Count - 1) -or
    @($compileEvidence.VenworksCoreSources).Count -ne @($matrix.VenworksCoreFixture.SourceFiles).Count) {
  throw 'Papyrus compile evidence does not match the Canvas script inventory and pinned Venworks Core source contract.'
}
foreach ($output in $expectedScriptOutputs) {
  $source = [System.IO.Path]::ChangeExtension([string]$output, '.psc')
  # PEX function names are serialized strings; fail closed even when a native call is hidden in an inactive branch.
  $compiledText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Join-Path $resolvedScriptsDirectory ([string]$output))))
  if ($compiledText -match '(?i)ShowCustomWatchAlert') {
    throw "Bridge-disabled Canvas PEX contains a Watch Alert reference: $output"
  }
  $scriptEvidenceMatches = @($compileEvidence.Scripts | Where-Object {
    [string]$_.Source -ceq $source -and [string]$_.Output -ceq [string]$output
  })
  if ($scriptEvidenceMatches.Count -ne 1 -or
      [string]$scriptEvidenceMatches[0].SourceSha256 -cne (Get-FileSha256 -Path (Join-Path $repositoryRoot "Papyrus\$source")) -or
      [string]$scriptEvidenceMatches[0].Sha256 -cne (Get-FileSha256 -Path (Join-Path $resolvedScriptsDirectory ([string]$output)))) {
    throw "Papyrus compile evidence does not contain exactly one source-bound row for '$output'."
  }
}
foreach ($coreSource in @($matrix.VenworksCoreFixture.SourceFiles)) {
  $coreSourceMatches = @($compileEvidence.VenworksCoreSources | Where-Object { [string]$_.Path -ceq [string]$coreSource.Path })
  if ($coreSourceMatches.Count -ne 1 -or [string]$coreSourceMatches[0].Sha256 -cne [string]$coreSource.Sha256) {
    throw "Papyrus compile evidence does not contain the exact pinned Core source '$($coreSource.Path)'."
  }
}

$payloadHashes = @{
  Host = @{
    'interface/venworkscui.swf' = $movieHashByKey.Host
    'interface/spaceshiphudmenu.swf' = $shipMovieHashes['spaceshiphudmenu.swf']
    'interface/spaceshiphudmenu_lrg.swf' = $shipMovieHashes['spaceshiphudmenu_lrg.swf']
    'scripts/venworks/canvas/globalconfig.pex' = (Get-FileSha256 -Path (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\GlobalConfig.pex'))
    'scripts/venworks/canvas/base/basequest.pex' = (Get-FileSha256 -Path (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Base\BaseQuest.pex'))
    'scripts/venworks/canvas/probes/consumerdiscovery/registry.pex' = (Get-FileSha256 -Path (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\Registry.pex'))
  }
  ConsumerA = @{
    'interface/venworkscanvas/consumers/venworks.canvas.probe.consumer-a/normal.swf' = $movieHashByKey[[string]$resolvedProfile.ConsumerAMovie]
    'interface/venworkscanvas/consumers/venworks.canvas.probe.consumer-a/large.swf' = $movieHashByKey[[string]$resolvedProfile.ConsumerAMovie]
    'scripts/venworks/canvas/probes/consumerdiscovery/consumeraregistrar.pex' = (Get-FileSha256 -Path (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerARegistrar.pex'))
    'scripts/venworks/canvas/probes/consumerdiscovery/consumeraupdatemigration.pex' = (Get-FileSha256 -Path (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerAUpdateMigration.pex'))
  }
  ConsumerB = @{
    'interface/venworkscanvas/consumers/venworks.canvas.probe.consumer-b/normal.swf' = $movieHashByKey.ConsumerB
    'interface/venworkscanvas/consumers/venworks.canvas.probe.consumer-b/large.swf' = $movieHashByKey.ConsumerB
    'scripts/venworks/canvas/probes/consumerdiscovery/consumerbregistrar.pex' = (Get-FileSha256 -Path (Join-Path $resolvedScriptsDirectory 'Venworks\Canvas\Probes\ConsumerDiscovery\ConsumerBRegistrar.pex'))
  }
}
foreach ($coreScript in @($matrix.VenworksCoreFixture.RuntimeScripts)) {
  $sourcePath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedVenworksCoreRoot ([string]$coreScript.Source)) `
    -Description "Pinned Venworks Core runtime script '$($coreScript.Source)'"
  $actualHash = Get-FileSha256 -Path $sourcePath
  if ($actualHash -cne [string]$coreScript.Sha256) {
    throw "Pinned Venworks Core runtime script '$($coreScript.Source)' drifted."
  }
  $payloadHashes.Host[([string]$coreScript.Target).Replace('\', '/').ToLowerInvariant()] = $actualHash
}
foreach ($playerHudMovie in @($matrix.VwHudFixture.PlayerHudMovies)) {
  $sourcePath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedVwHudRoot ([string]$playerHudMovie.Source)) `
    -Description "Pinned VWHUD player HUD movie '$($playerHudMovie.Source)'"
  $payloadHashes.Host[([string]$playerHudMovie.Target).ToLowerInvariant()] = Get-FileSha256 -Path $sourcePath
}

if ($ArtifactsOnly) {
  Write-Host -ForegroundColor Green "Verified all source-bound artifacts for profile '$($resolvedProfile.Key)' before staging."
  return
}

$repositoryStagingPath = Join-Path $repositoryRoot 'Staging'
if (Test-Path -LiteralPath $repositoryStagingPath) {
  $repositoryStagingItem = Get-Item -LiteralPath $repositoryStagingPath -Force
  if ($repositoryStagingItem.LinkType -ne 'Junction') {
    throw 'A real legacy Staging directory must not coexist with the three package-owned staging roots.'
  }
}
$stagingEvidencePath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $repositoryRoot '.work\consumer-discovery\staging-evidence.json') `
  -Description 'Consumer-discovery staging evidence'
$stagingEvidence = Get-Content -LiteralPath $stagingEvidencePath -Raw | ConvertFrom-Json
if ([string]$stagingEvidence.Schema -cne 'VWCANVAS9_CONSUMER_DISCOVERY_STAGING/3' -or
    [string]$stagingEvidence.Profile -cne [string]$resolvedProfile.Key -or
    [string]$stagingEvidence.VwHudRevision -cne [string]$matrix.VwHudFixture.Revision -or
    [string]$stagingEvidence.VenworksCoreRevision -cne [string]$matrix.VenworksCoreFixture.Revision -or
    [string]$stagingEvidence.PluginGenerationEvidenceSha256 -cne (Get-FileSha256 -Path $pluginGenerationEvidencePath) -or
    @($stagingEvidence.Staging).Count -ne 3) {
  throw "Staging evidence does not match selected profile '$($resolvedProfile.Key)' and the pinned VWHUD/Core revisions."
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
