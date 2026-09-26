<#
.SYNOPSIS
Builds and installs selected configured packages from current repository-owned outputs.
.DESCRIPTION
The maintainer must prepare each staging path as an exact Junction to its configured physical module folder. Packaging holds one process-owned lock across candidate creation, installation, and successful transaction cleanup. Failed transactions remain beneath the configured work root for recovery inspection.
.PARAMETER VariantKeys
Builds only the listed module variant keys. When omitted, every configured variant is packaged.
.PARAMETER EnvironmentPath
Specifies the environment file for the first successful shared-configuration initialization in the current PowerShell session. Later guarded script calls reuse that initialized configuration and ignore another EnvironmentPath until a new session starts.
.PARAMETER ScriptsDirectory
Uses an alternative directory containing compiled Papyrus PEX files for this packaging run instead of each selected variant's staged Scripts directory.
.PARAMETER ScaleformDirectory
Uses an alternative directory containing built Scaleform output sets for this packaging run instead of each selected variant's staged Scaleform target files.
.PARAMETER ArchiveRootsDirectory
Overrides the transaction workspace beneath the configured build work root. Failed transactions remain there for recovery inspection.
.PARAMETER SkipEnvironment
Skip importing the build environment file. Use when only configuration constants are needed (e.g., in CI packaging).
.PARAMETER BuildOnly
Build archives only without installing to physical module folders. Use for CI where staging paths are not Junctions.
#>
[CmdletBinding()]
param(
  [string[]]$VariantKeys,
  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),
  [string]$ScriptsDirectory,
  [string]$ScaleformDirectory,
  [string]$ArchiveRootsDirectory,
  [switch]$SkipEnvironment,
  [switch]$BuildOnly,
  [switch]$CleanupLooseFiles
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedVariants.ps1')
. (Join-Path $PSScriptRoot 'sharedBuild.ps1')
if (!(Test-Path -LiteralPath 'Variable:Global:SharedConfigurationLoaded') -or !$Global:SharedConfigurationLoaded) {
  . (Join-Path $PSScriptRoot 'sharedConfig.ps1') -EnvironmentPath $EnvironmentPath -SkipEnvironment:$SkipEnvironment
}
. (Join-Path $PSScriptRoot 'sharedPackaging.ps1')

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($ArchiveRootsDirectory)) { $ArchiveRootsDirectory = Join-Path ([string]$Global:BuildSettings.WorkRoot) 'package-transactions' }
if ([string]::IsNullOrWhiteSpace($env:TOOL_PATH_ARCHIVER)) { throw 'TOOL_PATH_ARCHIVER must be configured by the initialized build environment.' }
$archive2Path = Resolve-BuildExecutable -Path $env:TOOL_PATH_ARCHIVER -FileName 'Archive2.exe' -Description 'Archive2 executable'
$allVariants = @(Get-ModuleVariants)
$selectedVariants = @(Get-ModuleVariants -VariantKeys $VariantKeys)

# Complete every source, Junction, configuration, and payload check before acquiring shared write state.
$operations = @(Get-BuildPackageInstallOperations -SelectedVariants $selectedVariants -AllVariants $allVariants)
$plans = @(Get-BuildPackageArchivePlans `
  -Variants $selectedVariants `
  -RepositoryRoot $repositoryRoot `
  -PapyrusSourceRoot ([string]$Global:BuildSettings.PapyrusSourceRoot) `
  -ScriptsDirectory $ScriptsDirectory `
  -ScaleformDirectory $ScaleformDirectory)
foreach ($variant in $selectedVariants) {
  if (@($plans | Where-Object { [string]$_.VariantKey -ceq [string]$variant.VariantKey }).Count -ne @($variant.Archives).Count) {
    throw "Package archive plan count differs for '$($variant.VariantKey)'."
  }
}
foreach ($operation in $operations) {
  $variantPlans = @($plans | Where-Object { [string]$_.VariantKey -ceq [string]$operation.Key })
  $operation | Add-Member -NotePropertyName LoosePayloadTargets -NotePropertyValue @(Get-BuildPackagePlanPayloadTargets -Plans $variantPlans) -Force
}

$transactionId = [guid]::NewGuid().ToString('N')
$transactionBase = [IO.Path]::GetFullPath($ArchiveRootsDirectory)
$workRoot = [IO.Path]::GetFullPath([string]$Global:BuildSettings.WorkRoot)
Assert-BuildRemovalPath -Path $transactionBase -AllowedRoot $workRoot
$transactionPath = Join-Path $transactionBase $transactionId
$lockPath = Join-Path $workRoot 'package.lock'
$packageLock = $null
$installedOperations = [Collections.Generic.List[object]]::new()
$completed = $false
$transactionCreated = $false
try {
  $packageLock = Enter-BuildPackageLock -Path $lockPath -TransactionId $transactionId
  New-Item -ItemType Directory -Force -Path $transactionBase | Out-Null
  Assert-BuildNoIncompletePackageTransactions -TransactionBase $transactionBase
  New-Item -ItemType Directory -Path $transactionPath | Out-Null
  $transactionCreated = $true
  Write-BuildPackageTransactionJournal -TransactionPath $transactionPath -TransactionId $transactionId -Status 'Active' -VariantKeys @($selectedVariants.VariantKey)
  $candidateRoot = Join-Path $transactionPath 'candidates'
  $archiveRootBase = Join-Path $transactionPath 'archive-roots'
  $backupRoot = Join-Path $transactionPath 'installed-backups'
  New-Item -ItemType Directory -Path $candidateRoot, $archiveRootBase, $backupRoot | Out-Null

  $candidateRecords = [Collections.Generic.List[object]]::new()
  foreach ($operation in $operations) {
    $key = [string]$operation.Key
    $candidateDirectory = Join-Path $candidateRoot $key
    New-Item -ItemType Directory -Path $candidateDirectory | Out-Null
    $sourceEsmSha = Get-BuildFileSha256 -Path $operation.SourcePluginPath
    $candidateEsmPath = Join-Path $candidateDirectory $operation.PluginName
    Copy-BuildVerifiedFile -Source $operation.SourcePluginPath -Destination $candidateEsmPath -ExpectedSha256 $sourceEsmSha -Description "$key live ESM snapshot"

    $archiveRecords = [Collections.Generic.List[object]]::new()
    $variantPlans = @($plans | Where-Object { [string]$_.VariantKey -ceq $key })
    for ($archiveIndex = 0; $archiveIndex -lt $variantPlans.Count; $archiveIndex++) {
      $plan = $variantPlans[$archiveIndex]
      $archiveRoot = Join-Path (Join-Path $archiveRootBase $key) $archiveIndex
      New-Item -ItemType Directory -Path $archiveRoot | Out-Null
      foreach ($payload in @($plan.Payloads)) {
        $destination = Resolve-BuildArchiveTarget -Root $archiveRoot -Target ([string]$payload.Target)
        Copy-BuildVerifiedFile -Source $payload.Source -Destination $destination -ExpectedSha256 ([string]$payload.ExpectedSha256) -Description "$key payload '$($payload.Target)'"
      }
      $candidateArchivePath = Join-Path $candidateDirectory $plan.FileName
      [void](Invoke-BuildArchive2 -Archive2Path $archive2Path -Archive $plan.Archive -ArchiveRoot $archiveRoot -OutputPath $candidateArchivePath -Description "$key archive '$($plan.FileName)'")
      $archiveRecords.Add([pscustomobject]@{
        Plan = $plan
        CandidatePath = $candidateArchivePath
        CandidateSha256 = Get-BuildFileSha256 -Path $candidateArchivePath
      })
    }
    $candidateRecords.Add([pscustomobject]@{
      Operation = $operation
      SourceEsmSha256 = $sourceEsmSha
      CandidateEsmPath = $candidateEsmPath
      CandidateEsmSha256 = Get-BuildFileSha256 -Path $candidateEsmPath
      Archives = @($archiveRecords)
    })
  }

  foreach ($record in $candidateRecords) {
    if ((Get-BuildFileSha256 -Path $record.Operation.SourcePluginPath) -cne [string]$record.SourceEsmSha256 -or
        (Get-BuildFileSha256 -Path $record.CandidateEsmPath) -cne [string]$record.CandidateEsmSha256) {
      throw "$($record.Operation.Key) validated ESM input or candidate changed before installation."
    }
    foreach ($archiveRecord in @($record.Archives)) {
      if ((Get-BuildFileSha256 -Path $archiveRecord.CandidatePath) -cne [string]$archiveRecord.CandidateSha256) {
        throw "$($record.Operation.Key) candidate archive changed before installation: $($archiveRecord.Plan.FileName)"
      }
      foreach ($payload in @($archiveRecord.Plan.Payloads)) {
        if ((Get-BuildFileSha256 -Path $payload.Source) -cne [string]$payload.ExpectedSha256) {
          throw "$($record.Operation.Key) package payload changed before installation: $($payload.Target)"
        }
      }
    }
  }

  if ($BuildOnly) {
    foreach ($record in $candidateRecords) {
      $operation = $record.Operation
      $stagingPath = $operation.StagingPath

      Install-BuildVerifiedFile -Source $record.CandidateEsmPath -Destination (Join-Path $stagingPath $operation.PluginName) -ExpectedSha256 $record.CandidateEsmSha256 -Description "$($operation.Key) candidate ESM"
      foreach ($archiveRecord in @($record.Archives)) {
        Install-BuildVerifiedFile -Source $archiveRecord.CandidatePath -Destination (Join-Path $stagingPath $archiveRecord.Plan.FileName) -ExpectedSha256 $archiveRecord.CandidateSha256 -Description "$($operation.Key) candidate archive '$($archiveRecord.Plan.FileName)'"
      }
      Write-Host -ForegroundColor Green "Built archives for $($operation.Key) to $stagingPath"
    }
    Write-BuildPackageTransactionJournal -TransactionPath $transactionPath -TransactionId $transactionId -Status 'Complete' -VariantKeys @($selectedVariants.VariantKey)
    $completed = $true
    return
  }

  foreach ($record in $candidateRecords) {
    $operation = $record.Operation
    Assert-BuildJunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.InstallPath
    $backupPath = Join-Path $backupRoot $operation.Key
    New-Item -ItemType Directory -Path $backupPath | Out-Null
    $looseBackupRoot = Join-Path $backupPath 'loose-payloads'
    New-Item -ItemType Directory -Path $looseBackupRoot | Out-Null
    $originalNames = [Collections.Generic.List[string]]::new()
    $originalHashes = @{}
    foreach ($name in @($operation.ManagedNames)) {
      $installedPath = Join-Path $operation.InstallPath $name
      if (!(Test-Path -LiteralPath $installedPath -PathType Leaf)) { continue }
      $hash = Get-BuildFileSha256 -Path $installedPath
      Copy-BuildVerifiedFile -Source $installedPath -Destination (Join-Path $backupPath $name) -ExpectedSha256 $hash -Description "$($operation.Key) installed backup '$name'"
      $originalNames.Add($name)
      $originalHashes[$name] = $hash
    }
    $originalLoosePayloadTargets = [Collections.Generic.List[string]]::new()
    $originalLoosePayloadHashes = @{}
    foreach ($target in @($operation.LoosePayloadTargets)) {
      $installedPath = Resolve-BuildArchiveTarget -Root $operation.InstallPath -Target $target
      $installedItem = Get-Item -LiteralPath $installedPath -Force -ErrorAction SilentlyContinue
      if ($null -eq $installedItem) { continue }
      if ($installedItem.PSIsContainer) { throw "$($operation.Key) loose package payload target is a directory: $installedPath" }
      $hash = Get-BuildFileSha256 -Path $installedPath
      $backupDestination = Resolve-BuildArchiveTarget -Root $looseBackupRoot -Target $target
      Copy-BuildVerifiedFile -Source $installedPath -Destination $backupDestination -ExpectedSha256 $hash -Description "$($operation.Key) loose-payload backup '$target'"
      $originalLoosePayloadTargets.Add($target)
      $originalLoosePayloadHashes[$target] = $hash
    }
    $operation | Add-Member -NotePropertyName BackupPath -NotePropertyValue $backupPath -Force
    $operation | Add-Member -NotePropertyName OriginalNames -NotePropertyValue @($originalNames) -Force
    $operation | Add-Member -NotePropertyName OriginalHashes -NotePropertyValue $originalHashes -Force
    $operation | Add-Member -NotePropertyName OriginalLoosePayloadTargets -NotePropertyValue @($originalLoosePayloadTargets) -Force
    $operation | Add-Member -NotePropertyName OriginalLoosePayloadHashes -NotePropertyValue $originalLoosePayloadHashes -Force
    $installedOperations.Add($operation)

    Install-BuildVerifiedFile -Source $record.CandidateEsmPath -Destination (Join-Path $operation.InstallPath $operation.PluginName) -ExpectedSha256 $record.CandidateEsmSha256 -Description "$($operation.Key) candidate ESM"
    foreach ($archiveRecord in @($record.Archives)) {
      Install-BuildVerifiedFile -Source $archiveRecord.CandidatePath -Destination (Join-Path $operation.InstallPath $archiveRecord.Plan.FileName) -ExpectedSha256 $archiveRecord.CandidateSha256 -Description "$($operation.Key) candidate archive '$($archiveRecord.Plan.FileName)'"
    }
    Assert-BuildJunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.InstallPath
    foreach ($target in @($operation.LoosePayloadTargets)) {
      $installedPath = Resolve-BuildArchiveTarget -Root $operation.InstallPath -Target $target
      $installedItem = Get-Item -LiteralPath $installedPath -Force -ErrorAction SilentlyContinue
      if ($null -eq $installedItem) { continue }
      if ($installedItem.PSIsContainer) { throw "$($operation.Key) loose package payload target is a directory: $installedPath" }
      Remove-Item -LiteralPath $installedPath -Force
    }
    Assert-BuildInstalledPackage -Variant $operation.Variant -InstallPath $operation.InstallPath -LoosePayloadTargets $operation.LoosePayloadTargets
  }

  Write-BuildPackageTransactionJournal -TransactionPath $transactionPath -TransactionId $transactionId -Status 'Complete' -VariantKeys @($selectedVariants.VariantKey)
  $completed = $true
  if ($CleanupLooseFiles) {
    foreach ($variant in $selectedVariants) {
      $staging = $variant.StagingFolderPath
      if (Test-Path (Join-Path $staging 'Scaleform')) {
        Remove-Item (Join-Path $staging 'Scaleform') -Recurse -Force
        Write-Host "Cleaned Scaleform loose files from $staging"
      }
      if (Test-Path (Join-Path $staging 'Scripts')) {
        Remove-Item (Join-Path $staging 'Scripts') -Recurse -Force
        Write-Host "Cleaned Scripts loose files from $staging"
      }
    }
  }
}
catch {
  $packageError = $_
  $recoveryErrors = [Collections.Generic.List[string]]::new()
  for ($index = $installedOperations.Count - 1; $index -ge 0; $index--) {
    try { Restore-BuildPackageOperation -Operation $installedOperations[$index] }
    catch { $recoveryErrors.Add("Package recovery failed for '$($installedOperations[$index].Key)': $($_.Exception.Message)") }
  }
  if (!$transactionCreated) { throw $packageError }
  try {
    Write-BuildPackageTransactionJournal -TransactionPath $transactionPath -TransactionId $transactionId -Status 'Failed' -VariantKeys @($selectedVariants.VariantKey) -Failure $packageError.Exception.Message
  }
  catch { $recoveryErrors.Add("Transaction journal update failed: $($_.Exception.Message)") }
  if ($recoveryErrors.Count -ne 0) {
    throw "Package transaction $transactionId failed and recovery is incomplete. Recovery material remains at $transactionPath. $($packageError.Exception.Message) $([string]::Join(' | ', $recoveryErrors))"
  }
  throw "Package transaction $transactionId failed; managed files were restored. Recovery material remains at $transactionPath. $($packageError.Exception.Message)"
}
finally {
  if ($null -ne $packageLock) {
    try {
      if ($completed -and $transactionCreated -and (Test-Path -LiteralPath $transactionPath -PathType Container)) {
        Assert-BuildRemovalPath -Path $transactionPath -AllowedRoot $transactionBase
        Remove-Item -LiteralPath $transactionPath -Recurse -Force
      }
    }
    finally {
      $packageLock.Dispose()
    }
  }
}

Write-Output "Packages created and installed for: $([string]::Join(', ', @($selectedVariants.VariantKey)))"
