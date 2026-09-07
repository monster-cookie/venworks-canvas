<#
.SYNOPSIS
Builds and installs selected Canvas packages from current Canvas-owned outputs.
.DESCRIPTION
The maintainer must prepare each staging path as an exact Junction to its configured physical module folder.
Packaging holds one process-owned lock across candidate creation, installation, and successful transaction cleanup.
Failed transactions retain their unique directory beneath .work/canvas for recovery inspection.
#>
[CmdletBinding()]
param(
  [string[]]$VariantKeys,
  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),
  [string]$ScriptsDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scripts'),
  [string]$ScaleformDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scaleform'),
  [string]$ArchiveRootsDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\package-transactions')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

function Copy-CanvasVerifiedFile {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][string]$Description
  )
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
  Copy-Item -LiteralPath $Source -Destination $Destination
  if ((Get-CanvasFileSha256 -Path $Source) -cne $ExpectedSha256 -or (Get-CanvasFileSha256 -Path $Destination) -cne $ExpectedSha256) {
    throw "$Description changed while it was copied."
  }
}

function Install-CanvasVerifiedFile {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][string]$Description
  )
  $temporaryPath = "$Destination.$PID-$([guid]::NewGuid().ToString('N')).new"
  try {
    Copy-CanvasVerifiedFile -Source $Source -Destination $temporaryPath -ExpectedSha256 $ExpectedSha256 -Description $Description
    [System.IO.File]::Move($temporaryPath, $Destination, $true)
    if ((Get-CanvasFileSha256 -Path $Destination) -cne $ExpectedSha256) { throw "$Description differs after installation." }
  }
  finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
  }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workRoot = Join-Path $repositoryRoot '.work\canvas'
$allVariants = @(Get-ModuleVariants)
$selectedVariants = @(Get-CanvasStagingSelection -VariantKeys $VariantKeys)
Import-CanvasEnvironment -Path $EnvironmentPath
if ([string]::IsNullOrWhiteSpace($env:TOOL_PATH_ARCHIVER)) { throw "TOOL_PATH_ARCHIVER must be configured in $EnvironmentPath." }
$archive2Path = Resolve-CanvasExecutable -Path $env:TOOL_PATH_ARCHIVER -FileName 'Archive2.exe' -Description 'Archive2 executable'

# Finish every staging/Junction/source-ESM check before creating candidates or acquiring shared write state.
$operations = @(Get-CanvasPackageInstallOperations -SelectedVariants $selectedVariants -AllVariants $allVariants)
$resolvedScriptsDirectory = Resolve-CanvasRequiredDirectory -Path $ScriptsDirectory -Description 'Compiled Canvas Papyrus script directory'
$resolvedScaleformDirectory = Resolve-CanvasRequiredDirectory -Path $ScaleformDirectory -Description 'Built Canvas Scaleform output directory'
$resolvedMoviesDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'movies') -Description 'Built Canvas movie directory'
$playerDirectory = $null
$shipDirectory = $null
if (@($selectedVariants | Where-Object { [string]$_.VariantKey -ceq 'CANVAS' }).Count -ne 0) {
  $playerDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'player-hud') -Description 'Built Player HUD output directory'
  $shipDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'ship-hud') -Description 'Built Ship HUD output directory'
}
$payloads = Get-CanvasPackagePayloads `
  -SelectedVariants $selectedVariants `
  -MoviesDirectory $resolvedMoviesDirectory `
  -ScriptsDirectory $resolvedScriptsDirectory `
  -PlayerDirectory $playerDirectory `
  -ShipDirectory $shipDirectory

$transactionId = [guid]::NewGuid().ToString('N')
$transactionBase = [System.IO.Path]::GetFullPath($ArchiveRootsDirectory)
Assert-CanvasRemovalPath -Path $transactionBase -AllowedRoot $workRoot
$transactionPath = Join-Path $transactionBase $transactionId
$lockPath = Join-Path $workRoot 'package.lock'
$packageLock = $null
$installedOperations = [System.Collections.Generic.List[object]]::new()
$completed = $false
$transactionCreated = $false
try {
  $packageLock = Enter-CanvasPackageLock -Path $lockPath -TransactionId $transactionId
  New-Item -ItemType Directory -Force -Path $transactionBase | Out-Null
  Assert-CanvasNoIncompletePackageTransactions -TransactionBase $transactionBase
  New-Item -ItemType Directory -Path $transactionPath | Out-Null
  $transactionCreated = $true
  Write-CanvasPackageTransactionJournal -TransactionPath $transactionPath -TransactionId $transactionId -Status 'Active' -VariantKeys @($selectedVariants.VariantKey)
  $candidateRoot = Join-Path $transactionPath 'candidates'
  $archiveRootBase = Join-Path $transactionPath 'archive-roots'
  $backupRoot = Join-Path $transactionPath 'installed-backups'
  New-Item -ItemType Directory -Path $candidateRoot, $archiveRootBase, $backupRoot | Out-Null

  $candidateRecords = [System.Collections.Generic.List[object]]::new()
  foreach ($operation in $operations) {
    $key = [string]$operation.Key
    $candidateDirectory = Join-Path $candidateRoot $key
    $archiveRoot = Join-Path $archiveRootBase $key
    New-Item -ItemType Directory -Path $candidateDirectory, $archiveRoot | Out-Null
    $sourceEsmSha = Get-CanvasFileSha256 -Path $operation.SourcePluginPath
    $candidateEsmPath = Join-Path $candidateDirectory $operation.PluginName
    Copy-CanvasVerifiedFile -Source $operation.SourcePluginPath -Destination $candidateEsmPath -ExpectedSha256 $sourceEsmSha -Description "$key live ESM snapshot"
    $expectedEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($payload in @($payloads[$key])) {
      $sourceSha = [string]$payload.ExpectedSha256
      $archivePath = Resolve-CanvasArchiveTarget -Root $archiveRoot -Target ([string]$payload.Target)
      Copy-CanvasVerifiedFile -Source $payload.Source -Destination $archivePath -ExpectedSha256 $sourceSha -Description "$key payload '$($payload.Target)'"
      $expectedEntries.Add([ordered]@{ Path = ([string]$payload.Target).Replace('\', '/').ToLowerInvariant(); Sha256 = $sourceSha })
    }
    $candidateArchivePath = Join-Path $candidateDirectory $operation.ArchiveName
    & $archive2Path "$archiveRoot\" "-root=$archiveRoot\" "-create=$candidateArchivePath" '-format=General' '-compression=None' '-maxSizeMB=2048' '-excludeFilters=.*\\meta\.ini|.*\\.*\.dds|.*\\.*\.btc|.*\\.*\.esp|.*\\.*\.esm|.*\\.*\.ba2'
    if ($LASTEXITCODE -ne 0) { throw "Archive2 failed to build the $key archive with exit code $LASTEXITCODE." }
    [void](Resolve-CanvasRequiredFile -Path $candidateArchivePath -Description "$key candidate BA2")
    Assert-CanvasArtifactHeader -Path $candidateArchivePath
    Assert-CanvasArchiveContents -Actual @(Get-CanvasGeneralBa2Contents -Path $candidateArchivePath) -Expected @($expectedEntries) -Description "$key candidate archive"
    $operation | Add-Member -NotePropertyName CandidatePath -NotePropertyValue $candidateDirectory -Force
    $operation | Add-Member -NotePropertyName CandidateNames -NotePropertyValue @($operation.PluginName, $operation.ArchiveName) -Force
    $candidateRecords.Add([pscustomobject]@{
      Operation = $operation
      SourceEsmSha256 = $sourceEsmSha
      CandidateEsmPath = $candidateEsmPath
      CandidateEsmSha256 = Get-CanvasFileSha256 -Path $candidateEsmPath
      CandidateArchivePath = $candidateArchivePath
      CandidateArchiveSha256 = Get-CanvasFileSha256 -Path $candidateArchivePath
      Entries = @($expectedEntries)
    })
  }

  foreach ($record in $candidateRecords) {
    if ((Get-CanvasFileSha256 -Path $record.Operation.SourcePluginPath) -cne [string]$record.SourceEsmSha256 -or
        (Get-CanvasFileSha256 -Path $record.CandidateEsmPath) -cne [string]$record.CandidateEsmSha256 -or
        (Get-CanvasFileSha256 -Path $record.CandidateArchivePath) -cne [string]$record.CandidateArchiveSha256) {
      throw "$($record.Operation.Key) validated input or candidate changed before installation."
    }
    foreach ($payload in @($payloads[[string]$record.Operation.Key])) {
      if ((Get-CanvasFileSha256 -Path $payload.Source) -cne [string]$payload.ExpectedSha256) {
        throw "$($record.Operation.Key) package payload changed before installation: $($payload.Target)"
      }
    }
    Assert-CanvasArchiveContents -Actual @(Get-CanvasGeneralBa2Contents -Path $record.CandidateArchivePath) -Expected @($record.Entries) -Description "$($record.Operation.Key) immediate candidate archive"
  }

  foreach ($record in $candidateRecords) {
    $operation = $record.Operation
    Assert-CanvasJunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.InstallPath
    $backupPath = Join-Path $backupRoot $operation.Key
    New-Item -ItemType Directory -Path $backupPath | Out-Null
    $originalItems = @(Get-ChildItem -LiteralPath $operation.InstallPath -Force)
    $originalHashes = @{}
    foreach ($item in $originalItems) {
      $hash = Get-CanvasFileSha256 -Path $item.FullName
      Copy-CanvasVerifiedFile -Source $item.FullName -Destination (Join-Path $backupPath $item.Name) -ExpectedSha256 $hash -Description "$($operation.Key) installed backup '$($item.Name)'"
      $originalHashes[$item.Name] = $hash
    }
    $operation | Add-Member -NotePropertyName BackupPath -NotePropertyValue $backupPath -Force
    $operation | Add-Member -NotePropertyName OriginalNames -NotePropertyValue @($originalItems.Name) -Force
    $operation | Add-Member -NotePropertyName OriginalHashes -NotePropertyValue $originalHashes -Force
    $installedOperations.Add($operation)
    Install-CanvasVerifiedFile -Source $record.CandidateEsmPath -Destination (Join-Path $operation.InstallPath $operation.PluginName) -ExpectedSha256 $record.CandidateEsmSha256 -Description "$($operation.Key) candidate ESM"
    Install-CanvasVerifiedFile -Source $record.CandidateArchivePath -Destination (Join-Path $operation.InstallPath $operation.ArchiveName) -ExpectedSha256 $record.CandidateArchiveSha256 -Description "$($operation.Key) candidate BA2"
    Assert-CanvasJunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.InstallPath
    Assert-CanvasInstalledPackage -Variant $operation.Variant -InstallPath $operation.InstallPath -ExpectedEntries @($record.Entries)
  }

  Write-CanvasPackageTransactionJournal -TransactionPath $transactionPath -TransactionId $transactionId -Status 'Complete' -VariantKeys @($selectedVariants.VariantKey)
  $completed = $true
}
catch {
  $packageError = $_
  $recoveryErrors = [System.Collections.Generic.List[string]]::new()
  for ($index = $installedOperations.Count - 1; $index -ge 0; $index--) {
    try { Restore-CanvasPackageOperation -Operation $installedOperations[$index] }
    catch { $recoveryErrors.Add("Package recovery failed for '$($installedOperations[$index].Key)': $($_.Exception.Message)") }
  }
  if (!$transactionCreated) { throw $packageError }
  try {
    Write-CanvasPackageTransactionJournal -TransactionPath $transactionPath -TransactionId $transactionId -Status 'Failed' -VariantKeys @($selectedVariants.VariantKey) -Failure $packageError.Exception.Message
  }
  catch { $recoveryErrors.Add("Transaction journal update failed: $($_.Exception.Message)") }
  if ($recoveryErrors.Count -ne 0) {
    throw "Canvas package transaction $transactionId failed and recovery is incomplete. Recovery material remains at $transactionPath. $($packageError.Exception.Message) $([string]::Join(' | ', $recoveryErrors))"
  }
  throw "Canvas package transaction $transactionId failed; installed files were restored. Recovery material remains at $transactionPath. $($packageError.Exception.Message)"
}
finally {
  try {
    if ($completed -and (Test-Path -LiteralPath $transactionPath -PathType Container)) {
      Assert-CanvasRemovalPath -Path $transactionPath -AllowedRoot $workRoot
      Remove-Item -LiteralPath $transactionPath -Recurse -Force
    }
  }
  finally {
    if ($null -ne $packageLock) { $packageLock.Dispose() }
  }
}
Write-Host -ForegroundColor Green "Packaged $($selectedVariants.VariantKey -join ', ') from current Canvas-owned outputs."
