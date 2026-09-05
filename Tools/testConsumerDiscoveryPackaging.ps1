<#
.SYNOPSIS
Runs isolated negative binary-header fixtures against the same checker used in normal and Committed repository validation.

.PARAMETER ExerciseArchiveCreation
Builds a disposable Host archive through junction-backed package fixtures to verify
selection, fail-before-replacement behavior, and junction preservation.
#>
[CmdletBinding()]
param(
  [switch]$ExerciseArchiveCreation
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')
$selectionMatrix = @{ Staging = @(@{ Key = 'Host' }, @{ Key = 'ConsumerA' }, @{ Key = 'ConsumerB' }) }
$hostSelection = @(Get-ConsumerDiscoveryStagingSelection -Matrix $selectionMatrix -HostOnly)
if ($hostSelection.Count -ne 1 -or $hostSelection[0].Key -cne 'Host' -or $selectionMatrix.Staging.Count -ne 3) {
  throw 'Host-only selection changed the matrix or selected consumer packages.'
}
if (@(Get-ConsumerDiscoveryStagingSelection -Matrix $selectionMatrix).Count -ne 3) { throw 'Default staging must retain all three variants.' }
foreach ($badKeys in @(@('Host','Host','ConsumerA'), @('Host','ConsumerA'), @('Host','ConsumerA','consumerb'))) {
  $caught = $false
  try { [void](Get-ConsumerDiscoveryStagingSelection -Matrix @{ Staging = @($badKeys | ForEach-Object { @{ Key = $_ } }) } -HostOnly) } catch { $caught = $true }
  if (!$caught) { throw 'A noncanonical staging matrix was accepted.' }
}
$stageSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'stageConsumerDiscoveryProbe.ps1') -Raw
foreach ($contract in @('foreach ($staging in $selectedStaging)', 'if ($selected) { Copy-Item -LiteralPath $pluginSource', 'Selected and unselected package targets must be disjoint.', 'if ($selected -and $entryHash -cne [string]$entryRecordsByPath[$entryPath].Sha256)', 'if (!$selected) {', 'Selected = $selected', '[System.IO.File]::Move($temporaryPath, $destinationPath, $true)', 'prior ESM/BA2 files were restored without replacing their directory or Junction')) {
  if (!$stageSource.Contains($contract)) { throw "Missing Host-only staging safety contract: $contract" }
}
if ($stageSource.Contains('$entryHash -cne [string]$entryHashesByPath[$entryPath]')) {
  throw 'Host-only staging still compares unselected consumer PEX bytes with a fresh compiler run.'
}
foreach ($forbiddenSwap in @('Move-Item -LiteralPath $operation.InstallPath', 'Move-Item -LiteralPath $operation.CandidatePath -Destination $operation.InstallPath', 'Remove-Item -LiteralPath $operation.InstallPath -Recurse')) {
  if ($stageSource.Contains($forbiddenSwap)) { throw "Staging still replaces a physical package directory beneath its Junction: $forbiddenSwap" }
}
$packageSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'createPackages.ps1') -Raw
foreach ($contract in @(
  '[Alias("VariantKey")]',
  '[string[]]$VariantKeys',
  '[switch]$Committed',
  '$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)',
  '$stagingItem.LinkType -ne "Junction"',
  '[System.IO.File]::Move($candidateArchivePath, $archivePath, $true)',
  'has no loose PC Main payload to archive; its existing BA2 was not changed.'
)) {
  if (!$packageSource.Contains($contract)) { throw "Missing standard variant packaging contract: $contract" }
}
foreach ($forbiddenContract in @(
  'stageConsumerDiscoveryProbe.ps1',
  'ProbeProfile',
  'VwHudRepositoryPath',
  'VenworksCoreRepositoryPath',
  'Main_XBox.ba2',
  'Main_PS.ba2',
  'Textures.ba2',
  'Remove-Item -LiteralPath $stagingFolderPath',
  'Remove-Item -LiteralPath $packageOutputPath'
)) {
  if ($packageSource.Contains($forbiddenContract)) { throw "createPackages retained a forbidden feature-specific or destructive contract: $forbiddenContract" }
}
$archiveCreationMatches = [regex]::Matches($packageSource, '\$archiveName = "\$\(\$variant\.PackageBaseName\) - Main\.ba2"')
if ($archiveCreationMatches.Count -ne 1) { throw 'createPackages must define exactly one PC Main archive name per selected variant.' }
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('canvas-artifact-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$pointer = [Text.Encoding]::UTF8.GetBytes("version https://git-lfs.github.com/spec/v1`noid sha256:012345`nsize 4096`n")
$rejections = 0
foreach ($extension in @('esm','ba2')) {
  foreach ($fixture in @(
    @{ Name = 'pointer'; Bytes = $pointer },
    @{ Name = 'empty'; Bytes = [byte[]]::new(0) },
    @{ Name = 'truncated'; Bytes = [byte[]]::new(8) },
    @{ Name = 'wrong-magic'; Bytes = [byte[]]::new(64) }
  )) {
    $path = Join-Path $fixtureRoot ($fixture.Name + '.' + $extension)
    [System.IO.File]::WriteAllBytes($path, $fixture.Bytes)
    $rejected = $false
    try { Assert-ConsumerDiscoveryArtifactHeader -Path $path } catch { $rejected = $true }
    if (!$rejected) { throw "Invalid binary was accepted: $path" }
    $rejections += 1
  }
}
$checker = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'checkRepo.ps1') -Raw
$badEsm = [byte[]]::new(64)
[Text.Encoding]::ASCII.GetBytes('TES4').CopyTo($badEsm, 0)
[BitConverter]::GetBytes([uint32]1000).CopyTo($badEsm, 4)
$badBa2 = [byte[]]::new(64)
[Text.Encoding]::ASCII.GetBytes('BTDX').CopyTo($badBa2, 0)
[BitConverter]::GetBytes([uint32]2).CopyTo($badBa2, 4)
[Text.Encoding]::ASCII.GetBytes('GNRL').CopyTo($badBa2, 8)
[BitConverter]::GetBytes([uint32]1).CopyTo($badBa2, 12)
[BitConverter]::GetBytes([uint64]32).CopyTo($badBa2, 16)
foreach ($fixture in @(@{ Name = 'truncated-body.esm'; Bytes = $badEsm }, @{ Name = 'truncated-record-table.ba2'; Bytes = $badBa2 })) {
  $path = Join-Path $fixtureRoot $fixture.Name
  [IO.File]::WriteAllBytes($path, $fixture.Bytes)
  $rejected = $false
  try { Assert-ConsumerDiscoveryArtifactHeader -Path $path } catch { $rejected = $true }
  if (!$rejected) { throw "Invalid header with a valid signature was accepted: $path" }
  $rejections += 1
}
if (!$checker.Contains('Assert-ConsumerDiscoveryArtifactHeader -Path $artifactPath')) { throw 'checkRepo does not use the tested binary checker.' }
foreach ($file in @('compileScripts.ps1','createPackages.ps1','SpriggitDumpDatabaseToYaml.ps1','SpriggitAssembleDatabaseFromYaml.ps1')) {
  $body = Get-Content -LiteralPath (Join-Path $PSScriptRoot $file) -Raw
  if ($body -match '(?i)\./Staging/|\.\\Staging\\|\bdeserialize\b') { throw "Legacy Staging/assembly path retained in $file." }
}
$assemblyRejected = $false
try { & (Join-Path $PSScriptRoot 'SpriggitAssembleDatabaseFromYaml.ps1') } catch { $assemblyRejected = $_.Exception.Message -like 'Spriggit assembly is disabled*' }
if (!$assemblyRejected) { throw 'Spriggit assembly did not fail closed.' }

if ($ExerciseArchiveCreation) {
  $sharedConfigurationVariable = Get-Variable -Name SharedConfigurationLoaded -Scope Global -ErrorAction SilentlyContinue
  if ($null -eq $sharedConfigurationVariable -or $sharedConfigurationVariable.Value -ne $true) {
    . (Join-Path $PSScriptRoot 'sharedConfig.ps1')
  }

  $packageFixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('canvas-package-tests-' + [guid]::NewGuid().ToString('N'))
  $physicalRoot = Join-Path $packageFixtureRoot 'physical'
  $stagingRoot = Join-Path $packageFixtureRoot 'staging'
  New-Item -ItemType Directory -Path $physicalRoot, $stagingRoot | Out-Null
  $fixtureVariants = @(
    [pscustomobject]@{ VariantKey = 'HOST'; VariantName = 'Fixture Host'; PackageBaseName = 'Venworks-Canvas-Host'; StagingFolderPath = (Join-Path $stagingRoot 'Staging-Host'); EnvironmentVariableName = 'FIXTURE_HOST'; PluginModulePath = (Join-Path $physicalRoot 'Host') }
    [pscustomobject]@{ VariantKey = 'CONSUMERA'; VariantName = 'Fixture Consumer A'; PackageBaseName = 'Venworks-Canvas-ConsumerA'; StagingFolderPath = (Join-Path $stagingRoot 'Staging-ConsumerA'); EnvironmentVariableName = 'FIXTURE_CONSUMER_A'; PluginModulePath = (Join-Path $physicalRoot 'ConsumerA') }
    [pscustomobject]@{ VariantKey = 'CONSUMERB'; VariantName = 'Fixture Consumer B'; PackageBaseName = 'Venworks-Canvas-ConsumerB'; StagingFolderPath = (Join-Path $stagingRoot 'Staging-ConsumerB'); EnvironmentVariableName = 'FIXTURE_CONSUMER_B'; PluginModulePath = (Join-Path $physicalRoot 'ConsumerB') }
  )
  $originalVariants = $Global:ModuleVariants
  $junctionPaths = [System.Collections.Generic.List[string]]::new()
  try {
    foreach ($variant in $fixtureVariants) {
      New-Item -ItemType Directory -Path $variant.PluginModulePath | Out-Null
      New-Item -ItemType Junction -Path $variant.StagingFolderPath -Target $variant.PluginModulePath | Out-Null
      $junctionPaths.Add([string]$variant.StagingFolderPath)
      [System.IO.File]::WriteAllBytes(
        (Join-Path $variant.PluginModulePath "$($variant.PackageBaseName).esm"),
        [System.Text.Encoding]::ASCII.GetBytes('TES4 fixture')
      )
      $interfacePath = Join-Path $variant.PluginModulePath 'Interface'
      New-Item -ItemType Directory -Path $interfacePath | Out-Null
      [System.IO.File]::WriteAllBytes(
        (Join-Path $interfacePath "$($variant.VariantKey.ToLowerInvariant()).swf"),
        [System.Text.Encoding]::ASCII.GetBytes("FWS fixture $($variant.VariantKey)")
      )
      [System.IO.File]::WriteAllBytes(
        (Join-Path $variant.PluginModulePath "$($variant.PackageBaseName) - Main.ba2"),
        [System.Text.Encoding]::ASCII.GetBytes("existing $($variant.VariantKey)")
      )
    }
    $Global:ModuleVariants = $fixtureVariants

    $consumerAArchive = Join-Path $fixtureVariants[1].PluginModulePath 'Venworks-Canvas-ConsumerA - Main.ba2'
    $consumerBArchive = Join-Path $fixtureVariants[2].PluginModulePath 'Venworks-Canvas-ConsumerB - Main.ba2'
    $consumerAHashBefore = (Get-FileHash -LiteralPath $consumerAArchive -Algorithm SHA256).Hash
    $consumerBHashBefore = (Get-FileHash -LiteralPath $consumerBArchive -Algorithm SHA256).Hash
    $hostTargetBefore = [string](Get-Item -LiteralPath $fixtureVariants[0].StagingFolderPath -Force).Target

    & (Join-Path $PSScriptRoot 'createPackages.ps1') -VariantKeys HOST

    $hostArchive = Join-Path $fixtureVariants[0].PluginModulePath 'Venworks-Canvas-Host - Main.ba2'
    Assert-ConsumerDiscoveryArtifactHeader -Path $hostArchive
    if ((Get-FileHash -LiteralPath $consumerAArchive -Algorithm SHA256).Hash -cne $consumerAHashBefore -or
        (Get-FileHash -LiteralPath $consumerBArchive -Algorithm SHA256).Hash -cne $consumerBHashBefore) {
      throw 'Selecting Host changed an unselected consumer archive.'
    }
    $hostStagingItem = Get-Item -LiteralPath $fixtureVariants[0].StagingFolderPath -Force
    if ($hostStagingItem.LinkType -cne 'Junction' -or [string]$hostStagingItem.Target -cne $hostTargetBefore) {
      throw 'Host packaging replaced or retargeted its staging Junction.'
    }

    $hostHashBeforeFailure = (Get-FileHash -LiteralPath $hostArchive -Algorithm SHA256).Hash
    Remove-Item -LiteralPath (Join-Path $fixtureVariants[0].PluginModulePath 'Interface\host.swf') -Force
    $emptyRejected = $false
    try { & (Join-Path $PSScriptRoot 'createPackages.ps1') -VariantKeys HOST } catch { $emptyRejected = $_.Exception.Message -like '*has no loose PC Main payload to archive*' }
    if (!$emptyRejected) { throw 'A package with no loose PC Main payload was accepted.' }
    if ((Get-FileHash -LiteralPath $hostArchive -Algorithm SHA256).Hash -cne $hostHashBeforeFailure) {
      throw 'The existing Host archive changed after an empty-payload rejection.'
    }

    $originalHostTarget = [string]$fixtureVariants[0].PluginModulePath
    $fixtureVariants[0].PluginModulePath = [System.IO.Path]::GetFullPath((Join-Path $physicalRoot 'WrongHost'))
    New-Item -ItemType Directory -Path $fixtureVariants[0].PluginModulePath | Out-Null
    $wrongTargetRejected = $false
    try { & (Join-Path $PSScriptRoot 'createPackages.ps1') -VariantKeys HOST } catch { $wrongTargetRejected = $_.Exception.Message -like '*does not target its configured physical module folder*' }
    $fixtureVariants[0].PluginModulePath = $originalHostTarget
    if (!$wrongTargetRejected) { throw 'A mismatched Host staging Junction target was accepted.' }

    foreach ($badVariantKeys in @(@('UNKNOWN'), @('HOST', 'HOST'))) {
      $badSelectionRejected = $false
      try { & (Join-Path $PSScriptRoot 'createPackages.ps1') -VariantKeys $badVariantKeys } catch { $badSelectionRejected = $true }
      if (!$badSelectionRejected) { throw "Invalid package variant selection was accepted: $($badVariantKeys -join ',')" }
    }
  }
  finally {
    $Global:ModuleVariants = $originalVariants
    foreach ($junctionPath in $junctionPaths) {
      if (Test-Path -LiteralPath $junctionPath) {
        [System.IO.Directory]::Delete($junctionPath)
      }
    }
    $resolvedPackageFixtureRoot = [System.IO.Path]::GetFullPath($packageFixtureRoot)
    $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (!$resolvedPackageFixtureRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove package fixture outside the temporary root: $resolvedPackageFixtureRoot"
    }
    if (Test-Path -LiteralPath $resolvedPackageFixtureRoot) {
      Remove-Item -LiteralPath $resolvedPackageFixtureRoot -Recurse -Force
    }
  }

  Write-Output 'Archive creation fixture passed: selected Host only, preserved every Junction, rejected empty input before replacement, and rejected invalid variant/target selections.'
}

Write-Output "Packaging contracts passed: standard variant-only createPackages, $rejections binary rejections, and disabled assembly; retained at $fixtureRoot"
