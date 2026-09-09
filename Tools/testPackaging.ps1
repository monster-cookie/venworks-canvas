$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedVariants.ps1')
. (Join-Path $PSScriptRoot 'sharedBuild.ps1')
if (!(Test-Path -LiteralPath 'Variable:Global:SharedConfigurationLoaded') -or !$Global:SharedConfigurationLoaded) {
  . (Join-Path $PSScriptRoot 'sharedConfig.ps1')
}
. (Join-Path $PSScriptRoot 'sharedPackaging.ps1')

function Assert-TestRejected {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$Action,
    [Parameter(Mandatory = $true)][string]$Description,
    [string]$MessagePattern
  )

  $failure = $null
  try { & $Action } catch { $failure = $_ }
  if ($null -eq $failure) { throw "$Description was accepted." }
  if (![string]::IsNullOrWhiteSpace($MessagePattern) -and $failure.Exception.Message -notmatch $MessagePattern) {
    throw "$Description failed for the wrong reason: $($failure.Exception.Message)"
  }
}

function Assert-TestNames {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Actual,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Expected,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $actualNames = @($Actual | ForEach-Object { ([string]$_).Replace('\', '/').ToLowerInvariant() } | Sort-Object)
  $expectedNames = @($Expected | ForEach-Object { ([string]$_).Replace('\', '/').ToLowerInvariant() } | Sort-Object)
  if ($actualNames.Count -ne $expectedNames.Count -or [string]::Join("`n", $actualNames) -cne [string]::Join("`n", $expectedNames)) {
    throw "$Description differs. Expected $([string]::Join(', ', $expectedNames)); found $([string]::Join(', ', $actualNames))."
  }
}

function Write-TestPsc {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$ScriptName)

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  [IO.File]::WriteAllText($Path, "ScriptName $ScriptName`n")
}

function Write-TestPex {
  param([Parameter(Mandatory = $true)][string]$Path)

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $bytes = [byte[]]::new(16)
  $bytes[0] = 0xDE
  $bytes[1] = 0xC0
  $bytes[2] = 0x57
  $bytes[3] = 0xFA
  [IO.File]::WriteAllBytes($Path, $bytes)
}

function Write-TestScaleform {
  param([Parameter(Mandatory = $true)][string]$Path, [string]$Signature = 'CWS')

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $bytes = [byte[]]::new(8)
  [Text.Encoding]::ASCII.GetBytes($Signature).CopyTo($bytes, 0)
  [IO.File]::WriteAllBytes($Path, $bytes)
}

function Write-TestEsm {
  param([Parameter(Mandatory = $true)][string]$Path, [byte]$Marker = 0)

  $bytes = [byte[]]::new(42)
  [Text.Encoding]::ASCII.GetBytes('TES4').CopyTo($bytes, 0)
  [BitConverter]::GetBytes([uint32]18).CopyTo($bytes, 4)
  $bytes[24] = $Marker
  [IO.File]::WriteAllBytes($Path, $bytes)
}

function Write-TestBa2 {
  param([Parameter(Mandatory = $true)][string]$Path, [byte]$Marker = 0)

  $data = [byte[]]@(0x41, $Marker)
  $name = [Text.Encoding]::UTF8.GetBytes('docs/test.txt')
  $recordEnd = 68
  $nameOffset = $recordEnd + $data.Length
  $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
  $writer = [IO.BinaryWriter]::new($stream, [Text.Encoding]::UTF8, $true)
  try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes('BTDX'))
    $writer.Write([uint32]2)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('GNRL'))
    $writer.Write([uint32]1)
    $writer.Write([uint64]$nameOffset)
    $writer.Write([uint64]0)
    $writer.Write([byte[]]::new(16))
    $writer.Write([uint64]$recordEnd)
    $writer.Write([uint32]0)
    $writer.Write([uint32]$data.Length)
    $writer.Write([uint32]0)
    $writer.Write($data)
    $writer.Write([uint16]$name.Length)
    $writer.Write($name)
  }
  finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

$configured = @(Get-ModuleVariants)
if ($configured.Count -ne 3) { throw 'Canvas packaging config must contain three variants.' }
$configuredCanvas = @(Get-ModuleVariants -VariantKeys 'CANVAS')[0]
$configuredExample = @(Get-ModuleVariants -VariantKeys 'EXAMPLE')[0]
$configuredGallery = @(Get-ModuleVariants -VariantKeys 'COMPONENTGALLERY')[0]
if ([string]$configuredCanvas.EsmFileName -cne 'Venworks-Canvas.esm' -or [string]$configuredCanvas.Archives[0].FileName -cne 'Venworks-Canvas - Main.ba2') {
  throw 'Canvas ESM/archive output identities changed.'
}
if (@($configuredCanvas.Archives[0].Assets).Count -ne 11 -or @($configuredExample.Archives[0].Assets).Count -ne 2 -or @($configuredGallery.Archives[0].Assets).Count -ne 2) {
  throw 'Canvas Scaleform archive mapping counts changed.'
}
if (@($configured | Where-Object { @($_.Archives).Count -ne 1 -or ![bool]$_.Archives[0].IncludePapyrus }).Count -ne 0) {
  throw 'Each Canvas variant must own one Papyrus-bearing archive.'
}

$wrapperTokens = $null
$wrapperParseErrors = $null
$wrapperAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'createPackages.ps1'), [ref]$wrapperTokens, [ref]$wrapperParseErrors)
if ($wrapperParseErrors.Count -ne 0) { throw "createPackages.ps1 has $($wrapperParseErrors.Count) parse error(s)." }
$packageTransactionTry = $null
foreach ($candidateTry in @($wrapperAst.FindAll({ param($node) $node -is [Management.Automation.Language.TryStatementAst] }, $true))) {
  $commands = @($candidateTry.Body.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
  if ($commands -contains 'Enter-BuildPackageLock') {
    if ($null -ne $packageTransactionTry) { throw 'createPackages.ps1 contains multiple package-lock transaction scopes.' }
    $packageTransactionTry = $candidateTry
  }
}
if ($null -eq $packageTransactionTry -or $null -eq $packageTransactionTry.Finally) { throw 'createPackages.ps1 does not protect the package-lock transaction with finally.' }
$cleanupTries = @($packageTransactionTry.Finally.Statements | Where-Object { $_ -is [Management.Automation.Language.IfStatementAst] } | ForEach-Object {
  $_.Clauses.Item2.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] }
})
if ($cleanupTries.Count -ne 1 -or $null -eq $cleanupTries[0].Finally) { throw 'createPackages.ps1 does not keep successful cleanup inside the lock-owned release scope.' }
$cleanupCommands = @($cleanupTries[0].Body.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
if ($cleanupCommands -cnotcontains 'Remove-Item') { throw 'createPackages.ps1 does not clean a successful transaction while the package lock is held.' }
$wrapperSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'createPackages.ps1'))
if ($wrapperSource -match 'NotePropertyName\s+CandidateNames') { throw 'createPackages.ps1 must use the flat CandidateNames returned by its install operation.' }

$testBase = Join-Path ([string]$Global:BuildSettings.WorkRoot) 'pipeline-tests/package'
$fixtureRoot = Join-Path $testBase ('packaging-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
$originalTarget = [Environment]::GetEnvironmentVariable('TEST_PACKAGE_TARGET', 'Process')
$originalOtherTarget = [Environment]::GetEnvironmentVariable('TEST_OTHER_PACKAGE_TARGET', 'Process')
try {
  $papyrusRoot = Join-Path $fixtureRoot 'Papyrus'
  $scriptsDirectory = Join-Path $fixtureRoot 'outputs/scripts'
  $scaleformDirectory = Join-Path $fixtureRoot 'outputs/scaleform'
  $stagingTarget = Join-Path $fixtureRoot 'installed'
  $stagingPath = Join-Path $fixtureRoot 'staging'
  $otherTarget = Join-Path $fixtureRoot 'other-installed'
  $otherStaging = Join-Path $fixtureRoot 'other-staging'
  $repositoryAssets = Join-Path $fixtureRoot 'assets'
  New-Item -ItemType Directory -Force -Path $papyrusRoot, $scriptsDirectory, $scaleformDirectory, $stagingTarget, $otherTarget, $repositoryAssets | Out-Null

  $sourceRows = @(
    @{ Relative = 'Venworks/Canvas/GlobalConfig.psc'; Name = 'Venworks:Canvas:GlobalConfig' }
    @{ Relative = 'Venworks/Canvas/Base/BaseQuest.psc'; Name = 'Venworks:Canvas:Base:BaseQuest' }
    @{ Relative = 'Venworks/CanvasExamples/Example.psc'; Name = 'Venworks:CanvasExamples:Example' }
    @{ Relative = 'Venworks/CanvasExtra/Extra.psc'; Name = 'Venworks:CanvasExtra:Extra' }
  )
  foreach ($row in $sourceRows) {
    Write-TestPsc -Path (Join-Path $papyrusRoot $row.Relative) -ScriptName $row.Name
    Write-TestPex -Path (Join-Path $scriptsDirectory ([IO.Path]::ChangeExtension($row.Relative, '.pex')))
  }
  Write-TestPex -Path (Join-Path $scriptsDirectory 'Venworks/Canvas/Deleted.pex')
  Write-TestScaleform -Path (Join-Path $scaleformDirectory 'movies/Consumer.swf')
  [IO.File]::WriteAllText((Join-Path $repositoryAssets 'readme.txt'), 'repository asset')
  Write-TestEsm -Path (Join-Path $stagingTarget 'ExplicitAnchor.esm')
  New-Item -ItemType Directory -Force -Path (Join-Path $stagingTarget 'Scripts'), (Join-Path $stagingTarget 'Textures') | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $stagingTarget 'Scripts/Foreign.pex'), [byte[]]::new(0))
  [IO.File]::WriteAllText((Join-Path $stagingTarget 'Textures/surface.dds'), 'dds payload')
  [IO.File]::WriteAllText((Join-Path $stagingTarget 'meta.ini'), 'metadata')
  [IO.File]::WriteAllText((Join-Path $stagingTarget 'loose.txt'), 'loose payload')
  [IO.File]::WriteAllText((Join-Path $stagingTarget 'DifferentArchiveBase - Main.ba2'), 'old invalid archive')

  $mainArchive = @{
    FileName = 'DifferentArchiveBase - Main.ba2'; Format = 'General'; Compression = 'None'; MaxSizeMB = 2048; IncludePapyrus = $true
    ExcludeFilters = '.*\\meta\.ini|.*\\.*\.dds|.*\\.*\.esm|.*\\.*\.ba2'
    Assets = @(
      @{ Root = 'Staging'; Source = '.'; Target = '' }
      @{ Root = 'Scaleform'; Source = 'movies/Consumer.swf'; Target = 'Interface/Consumers/normal.swf' }
      @{ Root = 'Scaleform'; Source = 'movies/Consumer.swf'; Target = 'Interface/Consumers/large.swf' }
      @{ Root = 'Repository'; Source = ([IO.Path]::GetRelativePath($fixtureRoot, (Join-Path $repositoryAssets 'readme.txt'))); Target = 'Docs/readme.txt' }
    )
  }
  $textureArchive = @{
    FileName = 'DifferentArchiveBase - Textures.ba2'; Format = 'DDS'; Compression = 'Default'; MaxSizeMB = 2048; IncludePapyrus = $false
    IncludeFilters = '.*\\.*\.dds'
    Assets = @(@{ Root = 'Staging'; Source = '.'; Target = '' })
  }
  $variant = [pscustomobject]@{
    VariantKey = 'FIXTURE'; VariantName = 'Fixture'; EsmFileName = 'ExplicitAnchor.esm'; PackageBaseName = 'DifferentArchiveBase'
    PapyrusNamespace = 'Venworks:Canvas'; StagingFolderPath = $stagingTarget; EnvironmentVariableName = 'TEST_PACKAGE_TARGET'
    ScaleformBuilds = @(); Archives = @($mainArchive, $textureArchive)
  }

  $plans = @(Get-BuildPackageArchivePlans -Variants @($variant) -RepositoryRoot $fixtureRoot -PapyrusSourceRoot $papyrusRoot -ScriptsDirectory $scriptsDirectory -ScaleformDirectory $scaleformDirectory)
  if ($plans.Count -ne 2) { throw 'Fixture variant did not produce one plan per archive.' }
  $mainPlan = @($plans | Where-Object FileName -CEQ 'DifferentArchiveBase - Main.ba2')[0]
  $texturePlan = @($plans | Where-Object FileName -CEQ 'DifferentArchiveBase - Textures.ba2')[0]
  Assert-TestNames -Actual @($mainPlan.Payloads.Target) -Expected @(
    'loose.txt'
    'Interface/Consumers/normal.swf'
    'Interface/Consumers/large.swf'
    'Docs/readme.txt'
    'Scripts/Venworks/Canvas/GlobalConfig.pex'
    'Scripts/Venworks/Canvas/Base/BaseQuest.pex'
  ) -Description 'Exact namespace-owned Main payload inventory'
  Assert-TestNames -Actual @($texturePlan.Payloads.Target) -Expected @('Textures/surface.dds') -Description 'Filtered texture payload inventory'
  if (@($plans.Payloads | ForEach-Object { $_ } | Where-Object { $_.Target -match 'CanvasExamples|CanvasExtra|Deleted|Foreign' }).Count -ne 0) {
    throw 'Sibling, stale, or foreign PEX entered a package plan.'
  }

  foreach ($ownedSource in @($sourceRows | Where-Object { $_.Name -like 'Venworks:Canvas:*' -or $_.Name -ceq 'Venworks:Canvas:GlobalConfig' })) {
    Write-TestPex -Path (Join-Path (Join-Path $stagingTarget 'Scripts') ([IO.Path]::ChangeExtension($ownedSource.Relative, '.pex')))
  }
  Write-TestScaleform -Path (Join-Path $stagingTarget 'Interface/Consumers/normal.swf')
  Write-TestScaleform -Path (Join-Path $stagingTarget 'Interface/Consumers/large.swf')
  $stagedArchive = @{
    FileName = 'Staged.ba2'; Format = 'General'; Compression = 'None'; MaxSizeMB = 2048; IncludePapyrus = $true
    Assets = @(
      @{ Root = 'Scaleform'; Source = 'movies/Consumer.swf'; Target = 'Interface/Consumers/normal.swf' }
      @{ Root = 'Scaleform'; Source = 'movies/Consumer.swf'; Target = 'Interface/Consumers/large.swf' }
    )
  }
  $stagedVariant = $variant.PSObject.Copy()
  $stagedVariant.Archives = @($stagedArchive)
  $stagedPlans = @(Get-BuildPackageArchivePlans -Variants @($stagedVariant) -RepositoryRoot $fixtureRoot -PapyrusSourceRoot $papyrusRoot)
  if ($stagedPlans.Count -ne 1) { throw 'Default staged package inputs did not produce one archive plan.' }
  Assert-TestNames -Actual @($stagedPlans[0].Payloads.Target) -Expected @(
    'Interface/Consumers/normal.swf'
    'Interface/Consumers/large.swf'
    'Scripts/Venworks/Canvas/GlobalConfig.pex'
    'Scripts/Venworks/Canvas/Base/BaseQuest.pex'
  ) -Description 'Default staged package payload inventory'
  $resolvedStagingPrefix = [IO.Path]::GetFullPath($stagingTarget).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (@($stagedPlans[0].Payloads | Where-Object { ![IO.Path]::GetFullPath([string]$_.Source).StartsWith($resolvedStagingPrefix, [StringComparison]::OrdinalIgnoreCase) }).Count -ne 0) {
    throw 'Default package planning used a Papyrus or Scaleform source outside the selected staging tree.'
  }
  foreach ($stagedFixturePath in @(
      (Join-Path $stagingTarget 'Interface/Consumers/normal.swf')
      (Join-Path $stagingTarget 'Interface/Consumers/large.swf')
      (Join-Path $stagingTarget 'Scripts/Venworks/Canvas/GlobalConfig.pex')
      (Join-Path $stagingTarget 'Scripts/Venworks/Canvas/Base/BaseQuest.pex')
    )) {
    Remove-Item -LiteralPath $stagedFixturePath -Force
  }

  if ($IsWindows) {
    $linkedAssetTarget = Join-Path $fixtureRoot 'linked-asset-target'
    $linkedAssetSubdirectory = Join-Path $linkedAssetTarget 'sub'
    $repositoryAncestorLink = Join-Path $repositoryAssets 'linked'
    New-Item -ItemType Directory -Path $linkedAssetSubdirectory | Out-Null
    [IO.File]::WriteAllText((Join-Path $linkedAssetSubdirectory 'external.txt'), 'outside declared asset root')
    New-Item -ItemType Junction -Path $repositoryAncestorLink -Target $linkedAssetTarget | Out-Null
    try {
      foreach ($linkedSource in @('linked/sub', 'linked/sub/external.txt')) {
        $linkedArchive = @{
          FileName = 'Linked.ba2'; Format = 'General'; Compression = 'None'; MaxSizeMB = 2048; IncludePapyrus = $false
          Assets = @(@{ Root = 'Repository'; Source = $linkedSource; Target = 'Payload' })
        }
        $linkedVariant = $variant.PSObject.Copy()
        $linkedVariant.Archives = @($linkedArchive)
        Assert-TestRejected -Description "Package asset Source '$linkedSource' with a Junction ancestor" -MessagePattern 'Source contains a nested reparse point' -Action {
          [void](Get-BuildPackageArchivePlans -Variants @($linkedVariant) -RepositoryRoot $repositoryAssets -PapyrusSourceRoot $papyrusRoot -ScriptsDirectory $scriptsDirectory -ScaleformDirectory $scaleformDirectory)
        }
      }
    }
    finally { Remove-Item -LiteralPath $repositoryAncestorLink -Force }
  }
  else {
    Write-Output 'SKIP: package asset Source Junction-ancestor rejection requires Windows.'
  }

  Write-TestPsc -Path (Join-Path $papyrusRoot 'Venworks/Canvas/NewOwned.psc') -ScriptName 'Venworks:Canvas:NewOwned'
  Write-TestPex -Path (Join-Path $scriptsDirectory 'Venworks/Canvas/NewOwned.pex')
  $addedPlan = @(Get-BuildPackageArchivePlans -Variants @($variant) -RepositoryRoot $fixtureRoot -PapyrusSourceRoot $papyrusRoot -ScriptsDirectory $scriptsDirectory -ScaleformDirectory $scaleformDirectory | Where-Object FileName -CEQ 'DifferentArchiveBase - Main.ba2')[0]
  if ('Scripts\Venworks\Canvas\NewOwned.pex' -cnotin @($addedPlan.Payloads.Target)) { throw 'New namespace source was not automatically packaged.' }
  Remove-Item -LiteralPath (Join-Path $papyrusRoot 'Venworks/Canvas/Base/BaseQuest.psc') -Force
  $deletedPlan = @(Get-BuildPackageArchivePlans -Variants @($variant) -RepositoryRoot $fixtureRoot -PapyrusSourceRoot $papyrusRoot -ScriptsDirectory $scriptsDirectory -ScaleformDirectory $scaleformDirectory | Where-Object FileName -CEQ 'DifferentArchiveBase - Main.ba2')[0]
  if ('Scripts\Venworks\Canvas\Base\BaseQuest.pex' -cin @($deletedPlan.Payloads.Target)) { throw 'Deleted namespace source left a stale PEX in the package plan.' }

  $globalPex = Join-Path $scriptsDirectory 'Venworks/Canvas/GlobalConfig.pex'
  Remove-Item -LiteralPath $globalPex -Force
  Assert-TestRejected -Description 'Missing owned compiled PEX' -MessagePattern 'does not exist' -Action {
    [void](Get-BuildPackageArchivePlans -Variants @($variant) -RepositoryRoot $fixtureRoot -PapyrusSourceRoot $papyrusRoot -ScriptsDirectory $scriptsDirectory -ScaleformDirectory $scaleformDirectory)
  }
  Write-TestPex -Path $globalPex

  $duplicateArchive = @{} + $mainArchive
  $duplicateArchive.Assets = @($mainArchive.Assets) + @(@{ Root = 'Scaleform'; Source = 'movies/Consumer.swf'; Target = 'Interface/Consumers/normal.swf' })
  $duplicateVariant = $variant.PSObject.Copy()
  $duplicateVariant.Archives = @($duplicateArchive)
  Assert-TestRejected -Description 'Duplicate archive target' -MessagePattern 'more than one payload' -Action {
    [void](Get-BuildPackageArchivePlans -Variants @($duplicateVariant) -RepositoryRoot $fixtureRoot -PapyrusSourceRoot $papyrusRoot -ScriptsDirectory $scriptsDirectory -ScaleformDirectory $scaleformDirectory)
  }
  $traversalArchive = @{} + $mainArchive
  $traversalArchive.Assets = @(@{ Root = 'Repository'; Source = '../outside.txt'; Target = 'outside.txt' })
  $traversalVariant = $variant.PSObject.Copy()
  $traversalVariant.Archives = @($traversalArchive)
  Assert-TestRejected -Description 'Traversing package source' -MessagePattern 'traversal' -Action {
    [void](Get-BuildPackageArchivePlans -Variants @($traversalVariant) -RepositoryRoot $fixtureRoot -PapyrusSourceRoot $papyrusRoot -ScriptsDirectory $scriptsDirectory -ScaleformDirectory $scaleformDirectory)
  }
  Assert-TestRejected -Description 'Traversing archive target' -MessagePattern 'traversal' -Action {
    [void](Resolve-BuildArchiveTarget -Root $fixtureRoot -Target '../outside.txt')
  }
  $invalidFilterArchive = @{} + $mainArchive
  $invalidFilterArchive.ExcludeFilters = '('
  $invalidFilterVariant = $variant.PSObject.Copy()
  $invalidFilterVariant.Archives = @($invalidFilterArchive)
  Assert-TestRejected -Description 'Invalid archive filter' -MessagePattern 'regular expression' -Action {
    [void](Get-BuildPackageArchivePlans -Variants @($invalidFilterVariant) -RepositoryRoot $fixtureRoot -PapyrusSourceRoot $papyrusRoot -ScriptsDirectory $scriptsDirectory -ScaleformDirectory $scaleformDirectory)
  }

  $arguments = @(Get-BuildArchive2Arguments -Archive $textureArchive -ArchiveRoot $stagingTarget -OutputPath (Join-Path $fixtureRoot 'candidate.ba2'))
  if ('-format=DDS' -cnotin $arguments -or '-compression=Default' -cnotin $arguments -or '-includeFilters=.*\\.*\.dds' -cnotin $arguments) {
    throw 'Configured Archive2 format, compression, or filters were not preserved.'
  }

  Write-TestBa2 -Path (Join-Path $stagingTarget 'DifferentArchiveBase - Main.ba2')
  [Environment]::SetEnvironmentVariable('TEST_PACKAGE_TARGET', $stagingTarget, 'Process')
  [Environment]::SetEnvironmentVariable('TEST_OTHER_PACKAGE_TARGET', $otherTarget, 'Process')
  $variant.StagingFolderPath = $stagingPath
  $otherVariant = [pscustomobject]@{
    VariantKey = 'OTHER'; EsmFileName = 'Other.esm'; StagingFolderPath = $otherStaging; EnvironmentVariableName = 'TEST_OTHER_PACKAGE_TARGET'; Archives = @()
  }
  Assert-TestRejected -Description 'Missing staging Junction' -MessagePattern 'Junction' -Action {
    [void](Get-BuildPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $otherVariant))
  }
  if ($IsWindows) {
    New-Item -ItemType Junction -Path $stagingPath -Target $stagingTarget | Out-Null
    $junctionPlans = @(Get-BuildPackageArchivePlans -Variants @($variant) -RepositoryRoot $fixtureRoot -PapyrusSourceRoot $papyrusRoot -ScriptsDirectory $scriptsDirectory -ScaleformDirectory $scaleformDirectory)
    if ($junctionPlans.Count -ne 2) { throw 'The configured top-level Staging Junction did not remain a valid package asset root.' }
    $stagingChildArchive = @{
      FileName = 'StagingChildren.ba2'; Format = 'General'; Compression = 'None'; MaxSizeMB = 2048; IncludePapyrus = $false
      Assets = @(
        @{ Root = 'Staging'; Source = 'Textures'; Target = 'Textures' }
        @{ Root = 'Staging'; Source = 'loose.txt'; Target = 'loose.txt' }
      )
    }
    $stagingChildVariant = $variant.PSObject.Copy()
    $stagingChildVariant.Archives = @($stagingChildArchive)
    $stagingChildPlans = @(Get-BuildPackageArchivePlans -Variants @($stagingChildVariant) -RepositoryRoot $fixtureRoot -PapyrusSourceRoot $papyrusRoot -ScriptsDirectory $scriptsDirectory -ScaleformDirectory $scaleformDirectory)
    Assert-TestNames -Actual @($stagingChildPlans[0].Payloads.Target) -Expected @('Textures/surface.dds', 'loose.txt') -Description 'Ordinary child mappings beneath the configured Staging Junction'

    $nestedAssetLink = Join-Path $stagingTarget 'nested-asset-link'
    New-Item -ItemType Junction -Path $nestedAssetLink -Target $linkedAssetTarget | Out-Null
    try {
      Assert-TestRejected -Description 'Nested package asset Junction beneath the configured Staging Junction' -MessagePattern 'nested reparse point' -Action {
        [void](Get-BuildPackageArchivePlans -Variants @($variant) -RepositoryRoot $fixtureRoot -PapyrusSourceRoot $papyrusRoot -ScriptsDirectory $scriptsDirectory -ScaleformDirectory $scaleformDirectory)
      }
    }
    finally { Remove-Item -LiteralPath $nestedAssetLink -Force }

    $operations = @(Get-BuildPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $otherVariant))
    if ($operations.Count -ne 1 -or $operations[0].PluginName -cne 'ExplicitAnchor.esm') { throw 'Explicit ESM install operation was not preserved.' }
    Assert-TestNames -Actual @($operations[0].ArchiveNames) -Expected @('DifferentArchiveBase - Main.ba2', 'DifferentArchiveBase - Textures.ba2') -Description 'Configured archive install names'
    [Environment]::SetEnvironmentVariable('TEST_PACKAGE_TARGET', $otherTarget, 'Process')
    Assert-TestRejected -Description 'Dynamic environment path mismatch' -MessagePattern 'overlap|does not target' -Action {
      [void](Get-BuildPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $otherVariant))
    }
    [Environment]::SetEnvironmentVariable('TEST_PACKAGE_TARGET', $stagingTarget, 'Process')

    $backupPath = Join-Path $fixtureRoot 'managed-backup'
    New-Item -ItemType Directory -Path $backupPath | Out-Null
    $operation = $operations[0]
    Assert-TestNames -Actual @($operation.CandidateNames) -Expected @('ExplicitAnchor.esm', 'DifferentArchiveBase - Main.ba2', 'DifferentArchiveBase - Textures.ba2') -Description 'Flat wrapper candidate inventory'
    if (@($operation.CandidateNames | Where-Object { $_ -is [array] }).Count -ne 0) { throw 'Wrapper candidate inventory contains a nested archive-name array.' }
    $originalNames = @($operation.CandidateNames | Where-Object { Test-Path -LiteralPath (Join-Path $stagingTarget $_) -PathType Leaf })
    Assert-TestNames -Actual $originalNames -Expected @('ExplicitAnchor.esm', 'DifferentArchiveBase - Main.ba2') -Description 'Original managed inventory before induced publication failure'
    $originalHashes = @{}
    foreach ($name in $originalNames) {
      Copy-Item -LiteralPath (Join-Path $stagingTarget $name) -Destination (Join-Path $backupPath $name)
      $originalHashes[$name] = Get-BuildFileSha256 -Path (Join-Path $backupPath $name)
    }
    $operation | Add-Member -NotePropertyName BackupPath -NotePropertyValue $backupPath -Force
    $operation | Add-Member -NotePropertyName OriginalNames -NotePropertyValue $originalNames -Force
    $operation | Add-Member -NotePropertyName OriginalHashes -NotePropertyValue $originalHashes -Force
    $publicationError = $null
    try {
      Write-TestEsm -Path (Join-Path $stagingTarget 'ExplicitAnchor.esm') -Marker 9
      Write-TestBa2 -Path (Join-Path $stagingTarget 'DifferentArchiveBase - Main.ba2') -Marker 9
      Write-TestBa2 -Path (Join-Path $stagingTarget 'DifferentArchiveBase - Textures.ba2') -Marker 9
      throw 'Injected publication failure after the previously absent texture archive was installed.'
    }
    catch {
      $publicationError = $_
      Restore-BuildPackageOperation -Operation $operation
    }
    if ($publicationError.Exception.Message -cnotmatch 'Injected publication failure') { throw 'The multiarchive recovery regression did not reach its induced publication failure.' }
    foreach ($name in $originalNames) {
      if ((Get-BuildFileSha256 -Path (Join-Path $stagingTarget $name)) -cne [string]$originalHashes[$name]) { throw "Recovery changed '$name'." }
    }
    if (Test-Path -LiteralPath (Join-Path $stagingTarget 'DifferentArchiveBase - Textures.ba2')) { throw 'Recovery left the newly installed texture archive behind.' }
    if ([IO.File]::ReadAllText((Join-Path $stagingTarget 'loose.txt')) -cne 'loose payload' -or !(Test-Path -LiteralPath (Join-Path $stagingTarget 'Textures/surface.dds') -PathType Leaf)) {
      throw 'Managed package recovery changed unrelated staged assets.'
    }
    Write-TestBa2 -Path (Join-Path $stagingTarget 'DifferentArchiveBase - Textures.ba2')
    Assert-BuildInstalledPackage -Variant $variant -InstallPath $stagingTarget
  }
  else {
    Write-Output 'SKIP: real Junction routing and publication recovery cases require Windows.'
  }

  $transactionBase = Join-Path $fixtureRoot 'transactions'
  New-Item -ItemType Directory -Path $transactionBase | Out-Null
  Assert-BuildNoIncompletePackageTransactions -TransactionBase $transactionBase
  $retained = Join-Path $transactionBase ([guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $retained | Out-Null
  Write-BuildPackageTransactionJournal -TransactionPath $retained -TransactionId (Split-Path -Leaf $retained) -Status 'Failed' -VariantKeys @('FIXTURE') -Failure 'fixture'
  Assert-TestRejected -Description 'Retained package transaction' -MessagePattern 'manual inspection' -Action {
    Assert-BuildNoIncompletePackageTransactions -TransactionBase $transactionBase
  }
  Remove-Item -LiteralPath $retained -Recurse -Force

  $lockPath = Join-Path $fixtureRoot 'package.lock'
  $lock = Enter-BuildPackageLock -Path $lockPath -TransactionId ([guid]::NewGuid().ToString('N'))
  try {
    Assert-TestRejected -Description 'Same-process competing package lock' -MessagePattern 'exclusive package lock' -Action {
      $competing = Enter-BuildPackageLock -Path $lockPath -TransactionId ([guid]::NewGuid().ToString('N'))
      $competing.Dispose()
    }
  }
  finally { $lock.Dispose() }
  $reacquired = Enter-BuildPackageLock -Path $lockPath -TransactionId ([guid]::NewGuid().ToString('N'))
  $reacquired.Dispose()
}
finally {
  [Environment]::SetEnvironmentVariable('TEST_PACKAGE_TARGET', $originalTarget, 'Process')
  [Environment]::SetEnvironmentVariable('TEST_OTHER_PACKAGE_TARGET', $originalOtherTarget, 'Process')
  if (Test-Path -LiteralPath $fixtureRoot) {
    Assert-BuildRemovalPath -Path $fixtureRoot -AllowedRoot $testBase
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}

Write-Output 'Packaging contracts passed: declarative archive mappings, exact namespace-derived PEX ownership, added/deleted source refresh, filter-before-validation behavior, nested-link rejection with configured Staging Junction support, explicit ESM/archive identities, dynamic Junction routing, multiarchive absence restoration, retained-transaction blocking, and package-lock exclusion.'
