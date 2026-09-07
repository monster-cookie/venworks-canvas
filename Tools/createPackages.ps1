<#
.SYNOPSIS
Builds and installs selected Canvas packages from current staging ESMs and source-bound build outputs.
.DESCRIPTION
The maintainer must prepare each staging path as an exact Junction to its configured physical module folder.
Packaging holds one process-owned lock across candidate creation, installation, and receipt publication. Failed
transactions retain their unique directory beneath .work/canvas for recovery inspection.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$VwHudRepositoryPath,
  [Parameter(Mandatory = $true)][string]$VenworksCoreRepositoryPath,
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
$matrix = Get-CanvasMatrix -RepositoryRoot $repositoryRoot
$allVariants = @(Get-ModuleVariants)
$selectedVariants = @(Get-CanvasStagingSelection -VariantKeys $VariantKeys)
Import-CanvasEnvironment -Path $EnvironmentPath
if ([string]::IsNullOrWhiteSpace($env:TOOL_PATH_ARCHIVER)) { throw "TOOL_PATH_ARCHIVER must be configured in $EnvironmentPath." }
$archive2Path = Resolve-CanvasExecutable -Path $env:TOOL_PATH_ARCHIVER -FileName 'Archive2.exe' -Description 'Archive2 executable'

# Finish every staging/Junction/source-ESM check before creating candidates or acquiring shared write state.
$operations = @(Get-CanvasPackageInstallOperations -SelectedVariants $selectedVariants -AllVariants $allVariants)
$resolvedVwHudRoot = Assert-PinnedVwHudToolchainFixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
$resolvedVenworksCoreRoot = Assert-PinnedVenworksCoreFixture -VenworksCoreRepositoryPath $VenworksCoreRepositoryPath -Matrix $matrix
$resolvedScriptsDirectory = Resolve-CanvasRequiredDirectory -Path $ScriptsDirectory -Description 'Compiled Papyrus script directory'
$resolvedScaleformDirectory = Resolve-CanvasRequiredDirectory -Path $ScaleformDirectory -Description 'Built Scaleform output directory'
$resolvedMoviesDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'movies') -Description 'Built Canvas movie directory'

foreach ($name in @('TOOL_PATH_PAPYRUS_COMPILER', 'PAPYRUS_COMPILER_FLAGS')) {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) { throw "$name must be configured in $EnvironmentPath." }
}
$compilerPath = Resolve-CanvasExecutable -Path $env:TOOL_PATH_PAPYRUS_COMPILER -FileName 'PapyrusCompiler.exe' -Description 'Papyrus compiler'
$flagsPath = $env:PAPYRUS_COMPILER_FLAGS
if (Test-Path -LiteralPath $flagsPath -PathType Container) { $flagsPath = Join-Path $flagsPath 'Starfield_Papyrus_Flags.flg' }
$compileToolchain = Get-CanvasCompileToolchainEvidence -RepositoryRoot $repositoryRoot -CompilerPath $compilerPath -FlagsPath $flagsPath -VenworksCoreRepositoryPath $resolvedVenworksCoreRoot -Matrix $matrix
$compileEvidencePath = Resolve-CanvasRequiredFile -Path (Join-Path $resolvedScriptsDirectory 'compile-evidence.json') -Description 'Papyrus compile evidence'
$compileEvidenceSnapshot = Get-CanvasJsonEvidenceSnapshot -Path $compileEvidencePath -Description 'Papyrus compile evidence' -TransactionFileName 'compile-evidence.json'
$compileEvidence = $compileEvidenceSnapshot.Value
Assert-CanvasCompileEvidence -Evidence $compileEvidence -RepositoryRoot $repositoryRoot -OutputDirectory $resolvedScriptsDirectory -Variants $selectedVariants -Toolchain $compileToolchain

$javaPath = Join-Path $resolvedVwHudRoot '.work\tools\java\bin\java.exe'
$jpexsPath = Join-Path $resolvedVwHudRoot '.work\tools\jpexs\ffdec.jar'
$flexPath = Join-Path $resolvedVwHudRoot '.work\tools\flex'
$scaleformToolchain = Get-CanvasScaleformToolchainEvidence -RepositoryRoot $repositoryRoot -VwHudRepositoryPath $resolvedVwHudRoot -JavaPath $javaPath -JpexsJarPath $jpexsPath -FlexSdkPath $flexPath -Matrix $matrix
$movieEvidencePath = Resolve-CanvasRequiredFile -Path (Join-Path $resolvedMoviesDirectory 'build-evidence.json') -Description 'Canvas movie evidence'
$movieEvidenceSnapshot = Get-CanvasJsonEvidenceSnapshot -Path $movieEvidencePath -Description 'Canvas movie evidence' -TransactionFileName 'canvas-movies-evidence.json'
$movieEvidence = $movieEvidenceSnapshot.Value
Assert-CanvasMovieEvidence -Evidence $movieEvidence -RepositoryRoot $repositoryRoot -MoviesDirectory $resolvedMoviesDirectory -Variants $selectedVariants -Toolchain $scaleformToolchain
$scaleformEvidencePath = Resolve-CanvasRequiredFile -Path (Join-Path $resolvedScaleformDirectory 'build-evidence.json') -Description 'Scaleform aggregate evidence'
$scaleformEvidenceSnapshot = Get-CanvasJsonEvidenceSnapshot -Path $scaleformEvidencePath -Description 'Scaleform aggregate evidence' -TransactionFileName 'scaleform-evidence.json'
$scaleformEvidence = $scaleformEvidenceSnapshot.Value
$requiresPlayerHud = @($selectedVariants | Where-Object { $_.IncludesPlayerHud }).Count -gt 0
$requiresShipHud = @($selectedVariants | Where-Object { $_.IncludesShipHud }).Count -gt 0
$playerEvidence = $null
$playerEvidenceSnapshot = $null
$shipEvidence = $null
$shipEvidenceSnapshot = $null
$playerDirectory = $null
$shipDirectory = $null
if ($requiresPlayerHud) {
  $playerDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'player-hud') -Description 'Player HUD output directory'
  $playerEvidenceSnapshot = Get-CanvasJsonEvidenceSnapshot -Path (Join-Path $playerDirectory 'build-evidence.json') -Description 'Player HUD evidence' -TransactionFileName 'player-hud-evidence.json'
  $playerEvidence = $playerEvidenceSnapshot.Value
  Assert-CanvasPlayerHudEvidence -Evidence $playerEvidence -RepositoryRoot $repositoryRoot -VwHudRepositoryPath $resolvedVwHudRoot -PlayerDirectory $playerDirectory -Matrix $matrix
}
if ($requiresShipHud) {
  $shipDirectory = Resolve-CanvasRequiredDirectory -Path (Join-Path $resolvedScaleformDirectory 'ship-hud') -Description 'Ship HUD output directory'
  $shipEvidenceSnapshot = Get-CanvasJsonEvidenceSnapshot -Path (Join-Path $shipDirectory 'build-evidence.json') -Description 'Ship HUD evidence' -TransactionFileName 'ship-hud-evidence.json'
  $shipEvidence = $shipEvidenceSnapshot.Value
  Assert-CanvasShipHudEvidence -Evidence $shipEvidence -RepositoryRoot $repositoryRoot -VwHudRepositoryPath $resolvedVwHudRoot -ShipDirectory $shipDirectory -Matrix $matrix
}
Assert-CanvasScaleformAggregateEvidence -Evidence $scaleformEvidence -ScaleformDirectory $resolvedScaleformDirectory -RequiredVariantKeys @($selectedVariants.VariantKey) -RequirePlayerHud $requiresPlayerHud -RequireShipHud $requiresShipHud
if ([string]$scaleformEvidence.CanvasMoviesEvidenceSha256 -cne [string]$movieEvidenceSnapshot.Sha256 -or
    ($requiresPlayerHud -and [string]$scaleformEvidence.PlayerHudEvidenceSha256 -cne [string]$playerEvidenceSnapshot.Sha256) -or
    ($requiresShipHud -and [string]$scaleformEvidence.ShipHudEvidenceSha256 -cne [string]$shipEvidenceSnapshot.Sha256)) {
  throw 'Admitted Scaleform aggregate evidence does not bind the admitted child evidence documents.'
}
$admittedEvidenceSnapshots = @($compileEvidenceSnapshot, $movieEvidenceSnapshot, $scaleformEvidenceSnapshot)
if ($null -ne $playerEvidenceSnapshot) { $admittedEvidenceSnapshots += $playerEvidenceSnapshot }
if ($null -ne $shipEvidenceSnapshot) { $admittedEvidenceSnapshots += $shipEvidenceSnapshot }

$payloads = Get-CanvasPackagePayloads `
  -SelectedVariants $selectedVariants `
  -CompileEvidence $compileEvidence `
  -MovieEvidence $movieEvidence `
  -MoviesDirectory $resolvedMoviesDirectory `
  -ScriptsDirectory $resolvedScriptsDirectory `
  -VenworksCoreRepositoryPath $resolvedVenworksCoreRoot `
  -Matrix $matrix `
  -PlayerDirectory $playerDirectory `
  -PlayerEvidence $playerEvidence `
  -ShipDirectory $shipDirectory `
  -ShipEvidence $shipEvidence

$transactionId = [guid]::NewGuid().ToString('N')
$transactionBase = [System.IO.Path]::GetFullPath($ArchiveRootsDirectory)
Assert-CanvasRemovalPath -Path $transactionBase -AllowedRoot $workRoot
$transactionPath = Join-Path $transactionBase $transactionId
$lockPath = Join-Path $workRoot 'package.lock'
$receiptDirectory = Join-Path $workRoot 'package-receipts'
$packageLock = $null
$installedOperations = [System.Collections.Generic.List[object]]::new()
$publishedReceipts = [System.Collections.Generic.List[object]]::new()
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
  $receiptCandidateRoot = Join-Path $transactionPath 'receipt-candidates'
  $admittedEvidenceRoot = Join-Path $transactionPath 'admitted-evidence'
  New-Item -ItemType Directory -Path $candidateRoot, $archiveRootBase, $backupRoot, $receiptCandidateRoot, $admittedEvidenceRoot | Out-Null
  foreach ($snapshot in $admittedEvidenceSnapshots) {
    Write-CanvasJsonEvidenceSnapshot -Snapshot $snapshot -Directory $admittedEvidenceRoot
    if ((Get-CanvasFileSha256 -Path ([string]$snapshot.SourcePath)) -cne [string]$snapshot.Sha256) {
      throw "Admitted evidence changed before transaction snapshot: $($snapshot.SourcePath)"
    }
  }

  $candidateRecords = [System.Collections.Generic.List[object]]::new()
  foreach ($operation in $operations) {
    $key = [string]$operation.Key
    $candidateDirectory = Join-Path $candidateRoot $key
    $archiveRoot = Join-Path $archiveRootBase $key
    New-Item -ItemType Directory -Path $candidateDirectory, $archiveRoot | Out-Null
    $sourceEsmSha = Get-CanvasFileSha256 -Path $operation.SourcePluginPath
    $candidateEsmPath = Join-Path $candidateDirectory $operation.PluginName
    Copy-CanvasVerifiedFile -Source $operation.SourcePluginPath -Destination $candidateEsmPath -ExpectedSha256 $sourceEsmSha -Description "$key live ESM snapshot"
    $inputRows = [System.Collections.Generic.List[object]]::new()
    $expectedEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($payload in @($payloads[$key])) {
      $sourceSha = [string]$payload.ExpectedSha256
      $archivePath = Resolve-CanvasArchiveTarget -Root $archiveRoot -Target ([string]$payload.Target)
      Copy-CanvasVerifiedFile -Source $payload.Source -Destination $archivePath -ExpectedSha256 $sourceSha -Description "$key payload '$($payload.Target)'"
      $canonicalTarget = ([string]$payload.Target).Replace('\', '/').ToLowerInvariant()
      $inputRows.Add([ordered]@{ Target = $canonicalTarget; SourceSha256 = $sourceSha })
      $expectedEntries.Add([ordered]@{ Path = $canonicalTarget; Sha256 = $sourceSha })
    }
    $candidateArchivePath = Join-Path $candidateDirectory $operation.ArchiveName
    & $archive2Path "$archiveRoot\" "-root=$archiveRoot\" "-create=$candidateArchivePath" '-format=General' '-compression=None' '-maxSizeMB=2048' '-excludeFilters=.*\\meta\.ini|.*\\.*\.dds|.*\\.*\.btc|.*\\.*\.esp|.*\\.*\.esm|.*\\.*\.ba2'
    if ($LASTEXITCODE -ne 0) { throw "Archive2 failed to build the $key archive with exit code $LASTEXITCODE." }
    [void](Resolve-CanvasRequiredFile -Path $candidateArchivePath -Description "$key candidate BA2")
    Assert-CanvasArtifactHeader -Path $candidateArchivePath
    $archiveEntries = @(Get-CanvasGeneralBa2Evidence -Path $candidateArchivePath)
    Assert-CanvasArchiveEvidenceRows -Actual $archiveEntries -Expected @($expectedEntries) -Description "$key candidate archive"
    $operation | Add-Member -NotePropertyName CandidatePath -NotePropertyValue $candidateDirectory -Force
    $operation | Add-Member -NotePropertyName CandidateNames -NotePropertyValue @($operation.PluginName, $operation.ArchiveName) -Force
    $candidateRecords.Add([pscustomobject]@{
      Operation = $operation
      SourceEsmSha256 = $sourceEsmSha
      CandidateEsmPath = $candidateEsmPath
      CandidateEsmSha256 = Get-CanvasFileSha256 -Path $candidateEsmPath
      CandidateArchivePath = $candidateArchivePath
      CandidateArchiveSha256 = Get-CanvasFileSha256 -Path $candidateArchivePath
      Entries = @($archiveEntries)
      Inputs = @($inputRows)
    })
  }

  foreach ($snapshot in $admittedEvidenceSnapshots) {
    if ((Get-CanvasFileSha256 -Path ([string]$snapshot.SourcePath)) -cne [string]$snapshot.Sha256 -or
        (Get-CanvasFileSha256 -Path ([string]$snapshot.TransactionPath)) -cne [string]$snapshot.Sha256) {
      throw "Admitted evidence changed before package installation: $($snapshot.SourcePath)"
    }
  }
  foreach ($record in $candidateRecords) {
    if ((Get-CanvasFileSha256 -Path $record.Operation.SourcePluginPath) -cne [string]$record.SourceEsmSha256 -or
        (Get-CanvasFileSha256 -Path $record.CandidateEsmPath) -cne [string]$record.CandidateEsmSha256 -or
        (Get-CanvasFileSha256 -Path $record.CandidateArchivePath) -cne [string]$record.CandidateArchiveSha256) {
      throw "$($record.Operation.Key) validated input or candidate changed before installation."
    }
    $payloadRows = @($payloads[[string]$record.Operation.Key])
    for ($index = 0; $index -lt $payloadRows.Count; $index++) {
      if ([string]$record.Inputs[$index].SourceSha256 -cne [string]$payloadRows[$index].ExpectedSha256 -or
          (Get-CanvasFileSha256 -Path $payloadRows[$index].Source) -cne [string]$payloadRows[$index].ExpectedSha256) {
        throw "$($record.Operation.Key) package payload changed before installation: $($record.Inputs[$index].Target)"
      }
    }
    Assert-CanvasArchiveEvidenceRows -Actual @(Get-CanvasGeneralBa2Evidence -Path $record.CandidateArchivePath) -Expected @($record.Entries) -Description "$($record.Operation.Key) immediate candidate archive"
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
    $receipt = [ordered]@{
      Schema = 'VWCANVAS_PACKAGE_RECEIPT/2'
      TransactionId = $transactionId
      VariantKey = [string]$operation.Key
      PackageBaseName = [string]$operation.Variant.PackageBaseName
      SourceEsm = [ordered]@{ File = [string]$operation.PluginName; Sha256 = [string]$record.SourceEsmSha256 }
      BuildEvidence = [ordered]@{
        CompileEvidenceSha256 = [string]$compileEvidenceSnapshot.Sha256
        ScaleformEvidenceSha256 = [string]$scaleformEvidenceSnapshot.Sha256
        VenworksCoreRevision = [string]$matrix.VenworksCoreFixture.Revision
        VwHudRevision = [string]$matrix.VwHudFixture.Revision
      }
      Candidate = [ordered]@{
        Plugin = [ordered]@{ File = [string]$operation.PluginName; Sha256 = [string]$record.CandidateEsmSha256 }
        Archive = [ordered]@{ File = [string]$operation.ArchiveName; Sha256 = [string]$record.CandidateArchiveSha256; Entries = @($record.Entries) }
      }
      Installed = [ordered]@{
        Plugin = [ordered]@{ File = [string]$operation.PluginName; Sha256 = Get-CanvasFileSha256 -Path (Join-Path $operation.InstallPath $operation.PluginName) }
        Archive = [ordered]@{ File = [string]$operation.ArchiveName; Sha256 = Get-CanvasFileSha256 -Path (Join-Path $operation.InstallPath $operation.ArchiveName); Entries = @(Get-CanvasGeneralBa2Evidence -Path (Join-Path $operation.InstallPath $operation.ArchiveName)) }
      }
    }
    $receiptPath = Join-Path $receiptCandidateRoot "$($operation.Key).json"
    Write-CanvasUtf8WithoutBom -Path $receiptPath -Text (($receipt | ConvertTo-Json -Depth 12) + "`n")
    Assert-CanvasPackageReceipt -Receipt (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json) -Variant $operation.Variant -InstallPath $operation.InstallPath -ExpectedEntries @($record.Entries) -CompileEvidenceSha256 ([string]$compileEvidenceSnapshot.Sha256) -ScaleformEvidenceSha256 ([string]$scaleformEvidenceSnapshot.Sha256)
    $record | Add-Member -NotePropertyName ReceiptPath -NotePropertyValue $receiptPath -Force
  }

  New-Item -ItemType Directory -Force -Path $receiptDirectory | Out-Null
  foreach ($record in $candidateRecords) {
    $destination = Join-Path $receiptDirectory "$($record.Operation.Key).json"
    $publication = [pscustomobject]@{ Destination = $destination; Backup = $null; OriginalSha256 = $null }
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
      $backup = Join-Path $transactionPath "receipt-backups\$($record.Operation.Key).json"
      $hash = Get-CanvasFileSha256 -Path $destination
      Copy-CanvasVerifiedFile -Source $destination -Destination $backup -ExpectedSha256 $hash -Description "$($record.Operation.Key) prior receipt backup"
      $publication.Backup = $backup
      $publication.OriginalSha256 = $hash
    }
    $publishedReceipts.Add($publication)
    $receiptHash = Get-CanvasFileSha256 -Path $record.ReceiptPath
    Install-CanvasVerifiedFile -Source $record.ReceiptPath -Destination $destination -ExpectedSha256 $receiptHash -Description "$($record.Operation.Key) package receipt"
  }
  $published = @(Get-CanvasPackageReceipts -ReceiptDirectory $receiptDirectory -RequiredVariantKeys @($selectedVariants.VariantKey))
  foreach ($record in $candidateRecords) {
    $receipt = @($published | Where-Object { [string]$_.VariantKey -ceq [string]$record.Operation.Key })[0]
    Assert-CanvasPackageReceipt -Receipt $receipt -Variant $record.Operation.Variant -InstallPath $record.Operation.InstallPath -ExpectedEntries @($record.Entries) -CompileEvidenceSha256 ([string]$compileEvidenceSnapshot.Sha256) -ScaleformEvidenceSha256 ([string]$scaleformEvidenceSnapshot.Sha256)
  }
  Write-CanvasPackageTransactionJournal -TransactionPath $transactionPath -TransactionId $transactionId -Status 'Complete' -VariantKeys @($selectedVariants.VariantKey)
  $completed = $true
}
catch {
  $packageError = $_
  $recoveryErrors = [System.Collections.Generic.List[string]]::new()
  for ($index = $publishedReceipts.Count - 1; $index -ge 0; $index--) {
    $publication = $publishedReceipts[$index]
    try { Restore-CanvasReceiptPublication -Publication $publication }
    catch { $recoveryErrors.Add("Receipt recovery failed for '$($publication.Destination)': $($_.Exception.Message)") }
  }
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
  throw "Canvas package transaction $transactionId failed; installed files and receipts were restored. Recovery material remains at $transactionPath. $($packageError.Exception.Message)"
}
finally {
  if ($null -ne $packageLock) { $packageLock.Dispose() }
}

if ($completed -and (Test-Path -LiteralPath $transactionPath -PathType Container)) {
  Assert-CanvasRemovalPath -Path $transactionPath -AllowedRoot $workRoot
  Remove-Item -LiteralPath $transactionPath -Recurse -Force
}
Write-Host -ForegroundColor Green "Packaged $($selectedVariants.VariantKey -join ', ') from current staging ESM snapshots and published source-bound installed receipts."
