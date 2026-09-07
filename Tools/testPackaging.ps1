<#
.SYNOPSIS
Exercises installed-receipt, exact-Junction, archive-inventory, and process-lock package contracts.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

function Assert-TestRejected {
  param([Parameter(Mandatory = $true)][scriptblock]$Action, [Parameter(Mandatory = $true)][string]$Description)
  $caught = $false
  try { & $Action } catch { $caught = $true }
  if (!$caught) { throw "$Description was accepted." }
}

function Write-TestEsm {
  param([Parameter(Mandatory = $true)][string]$Path, [byte]$Marker = 0)
  $bytes = [byte[]]::new(42)
  [Text.Encoding]::ASCII.GetBytes('TES4').CopyTo($bytes, 0)
  [BitConverter]::GetBytes([uint32]18).CopyTo($bytes, 4)
  $bytes[24] = $Marker
  [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Write-TestBa2 {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][hashtable]$Entries)
  $ordered = @($Entries.GetEnumerator() | Sort-Object Key)
  $recordEnd = 32 + (36 * $ordered.Count)
  $dataLength = @($ordered | ForEach-Object { ([byte[]]$_.Value).Length } | Measure-Object -Sum).Sum
  $nameOffset = $recordEnd + $dataLength
  $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  $writer = [System.IO.BinaryWriter]::new($stream, [Text.Encoding]::UTF8, $true)
  try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes('BTDX'))
    $writer.Write([uint32]2)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('GNRL'))
    $writer.Write([uint32]$ordered.Count)
    $writer.Write([uint64]$nameOffset)
    $writer.Write([uint64]0)
    $offset = [uint64]$recordEnd
    foreach ($entry in $ordered) {
      $bytes = [byte[]]$entry.Value
      $writer.Write([uint32]0)
      $writer.Write([byte[]]::new(4))
      $writer.Write([uint32]0)
      $writer.Write([uint32]0)
      $writer.Write($offset)
      $writer.Write([uint32]0)
      $writer.Write([uint32]$bytes.Length)
      $writer.Write([uint32]0)
      $offset += $bytes.Length
    }
    foreach ($entry in $ordered) { $writer.Write([byte[]]$entry.Value) }
    foreach ($entry in $ordered) {
      $nameBytes = [Text.Encoding]::UTF8.GetBytes(([string]$entry.Key).Replace('\', '/'))
      $writer.Write([uint16]$nameBytes.Length)
      $writer.Write($nameBytes)
    }
  }
  finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

$all = @(Get-CanvasStagingSelection)
if ($all.Count -ne $Global:ModuleVariants.Count) { throw 'Default package selection must include every variant.' }
if (@(Get-CanvasStagingSelection -VariantKeys 'CANVAS').Count -ne 1) { throw 'Explicit Canvas package selection failed.' }
foreach ($badKeys in @(@('UNKNOWN'), @('CANVAS', 'CANVAS'))) {
  Assert-TestRejected -Description "Invalid variant selection '$($badKeys -join ', ')'" -Action { [void](Get-CanvasStagingSelection -VariantKeys $badKeys) }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testBase = Join-Path $repositoryRoot '.work\canvas\build-remediation-tests'
$fixtureRoot = Join-Path $testBase ('packaging-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
$originalCanvasTarget = [Environment]::GetEnvironmentVariable('TEST_CANVAS_TARGET', 'Process')
$originalExampleTarget = [Environment]::GetEnvironmentVariable('TEST_EXAMPLE_TARGET', 'Process')
try {
  $target = Join-Path $fixtureRoot 'target'
  $otherTarget = Join-Path $fixtureRoot 'other-target'
  $staging = Join-Path $fixtureRoot 'staging'
  $otherStaging = Join-Path $fixtureRoot 'other-staging'
  New-Item -ItemType Directory -Path $target, $otherTarget | Out-Null
  $proofSource = Join-Path $fixtureRoot 'proof-source.json'
  Write-CanvasUtf8WithoutBom -Path $proofSource -Text "{`"Marker`":`"admitted`"}`n"
  $proofSnapshot = Get-CanvasJsonEvidenceSnapshot -Path $proofSource -Description 'Fixture proof' -TransactionFileName 'proof.json'
  if ([string]$proofSnapshot.Value.Marker -cne 'admitted' -or
      [string]$proofSnapshot.Sha256 -cne [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([byte[]]$proofSnapshot.Bytes))) {
    throw 'Evidence snapshot object and hash did not come from the same captured bytes.'
  }
  $proofDirectory = Join-Path $fixtureRoot 'proof-copy'
  New-Item -ItemType Directory -Path $proofDirectory | Out-Null
  Write-CanvasJsonEvidenceSnapshot -Snapshot $proofSnapshot -Directory $proofDirectory
  [System.IO.File]::WriteAllText($proofSource, '{"Marker":"changed"}')
  if ((Get-CanvasFileSha256 -Path $proofSnapshot.TransactionPath) -cne [string]$proofSnapshot.Sha256 -or
      (Get-CanvasFileSha256 -Path $proofSource) -ceq [string]$proofSnapshot.Sha256) {
    throw 'Immutable evidence snapshot did not preserve and distinguish the admitted bytes.'
  }

  $payloadFixture = Join-Path $fixtureRoot 'payload-fixture'
  $payloadMovie = Join-Path $payloadFixture 'movies\Canvas.swf'
  $payloadCore = Join-Path $payloadFixture 'core\Staging\Scripts\Core.pex'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $payloadMovie), (Split-Path -Parent $payloadCore) | Out-Null
  [System.IO.File]::WriteAllText($payloadMovie, 'movie')
  [System.IO.File]::WriteAllText($payloadCore, 'core')
  $admittedMovieHash = Get-CanvasFileSha256 -Path $payloadMovie
  $pinnedCoreHash = Get-CanvasFileSha256 -Path $payloadCore
  $payloadVariant = [pscustomobject]@{ VariantKey = 'CANVAS'; PapyrusScripts = @() }
  $payloadMovieEvidence = [pscustomobject]@{ Movies = @([pscustomobject]@{ VariantKey = 'CANVAS'; OutputFile = 'Canvas.swf'; Sha256 = $admittedMovieHash }) }
  $payloadMatrix = @{ VenworksCoreFixture = @{ RuntimeScripts = @(@{ Source = 'Staging/Scripts/Core.pex'; Target = 'Scripts/Core.pex'; Sha256 = $pinnedCoreHash }) } }
  $admittedPayloads = @(Get-CanvasPackagePayloads -SelectedVariants @($payloadVariant) -CompileEvidence ([pscustomobject]@{ Scripts = @() }) -MovieEvidence $payloadMovieEvidence -MoviesDirectory (Split-Path -Parent $payloadMovie) -ScriptsDirectory $payloadFixture -VenworksCoreRepositoryPath (Join-Path $payloadFixture 'core') -Matrix $payloadMatrix -PlayerDirectory $payloadFixture -PlayerEvidence ([pscustomobject]@{ Movies = @() }) -ShipDirectory $payloadFixture -ShipEvidence ([pscustomobject]@{ Movies = @() }) | ForEach-Object { $_['CANVAS'] })
  if ($admittedPayloads.Count -ne 2 -or
      [string]@($admittedPayloads | Where-Object Target -CEQ 'Interface\venworkscui.swf')[0].ExpectedSha256 -cne $admittedMovieHash -or
      [string]@($admittedPayloads | Where-Object Target -CEQ 'Scripts\Core.pex')[0].ExpectedSha256 -cne $pinnedCoreHash) {
    throw 'Package payloads did not retain admitted movie and pinned Core hashes.'
  }
  Write-TestEsm -Path (Join-Path $target 'Fixture.esm')
  $variant = [pscustomobject]@{ VariantKey = 'CANVAS'; PackageBaseName = 'Fixture'; StagingFolderPath = $staging; EnvironmentVariableName = 'TEST_CANVAS_TARGET' }
  $unselectedVariant = [pscustomobject]@{ VariantKey = 'EXAMPLE'; PackageBaseName = 'Other'; StagingFolderPath = $otherStaging; EnvironmentVariableName = 'TEST_EXAMPLE_TARGET' }
  [Environment]::SetEnvironmentVariable('TEST_CANVAS_TARGET', $target, 'Process')
  [Environment]::SetEnvironmentVariable('TEST_EXAMPLE_TARGET', $otherTarget, 'Process')

  Assert-TestRejected -Description 'Missing staging path preflight' -Action { [void](Get-CanvasPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $unselectedVariant)) }
  New-Item -ItemType Directory -Path $staging | Out-Null
  $beforeOrdinary = Get-CanvasDirectoryDigest -Path $target
  Assert-TestRejected -Description 'Ordinary staging directory preflight' -Action { [void](Get-CanvasPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $unselectedVariant)) }
  if ((Get-CanvasDirectoryDigest -Path $target) -cne $beforeOrdinary) { throw 'Rejected ordinary-directory preflight changed the physical target.' }
  Remove-Item -LiteralPath $staging -Force

  if ($IsWindows) {
    New-Item -ItemType Junction -Path $staging -Target $otherTarget | Out-Null
    Assert-TestRejected -Description 'Wrong Junction target preflight' -Action { [void](Get-CanvasPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $unselectedVariant)) }
    Remove-Item -LiteralPath $staging -Force
    New-Item -ItemType Junction -Path $staging -Target $target | Out-Null
    $operations = @(Get-CanvasPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $unselectedVariant))
    if ($operations.Count -ne 1 -or !(Test-CanvasSamePath -Left $operations[0].InstallPath -Right $target)) { throw 'Correct Junction preflight did not resolve the configured physical target.' }
    [Environment]::SetEnvironmentVariable('TEST_EXAMPLE_TARGET', (Join-Path $target 'nested'), 'Process')
    Assert-TestRejected -Description 'Selected target overlap with an unselected configured target' -Action { [void](Get-CanvasPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $unselectedVariant)) }
    [Environment]::SetEnvironmentVariable('TEST_EXAMPLE_TARGET', $otherTarget, 'Process')
  }
  else {
    Write-Output 'SKIP: real Junction preflight cases require Windows.'
  }

  $packageDirectory = Join-Path $fixtureRoot 'installed'
  $receiptsDirectory = Join-Path $fixtureRoot 'receipts'
  New-Item -ItemType Directory -Path $packageDirectory, $receiptsDirectory | Out-Null
  $esmPath = Join-Path $packageDirectory 'Fixture.esm'
  $ba2Path = Join-Path $packageDirectory 'Fixture - Main.ba2'
  Write-TestEsm -Path $esmPath
  Write-TestBa2 -Path $ba2Path -Entries @{ 'Interface/test.swf' = [Text.Encoding]::UTF8.GetBytes('movie'); 'Scripts/test.pex' = [Text.Encoding]::UTF8.GetBytes('script') }
  $entries = @(Get-CanvasGeneralBa2Evidence -Path $ba2Path)
  $esmSha = Get-CanvasFileSha256 -Path $esmPath
  $ba2Sha = Get-CanvasFileSha256 -Path $ba2Path
  $compileSha = 'A' * 64
  $scaleformSha = 'B' * 64
  $receipt = [ordered]@{
    Schema = 'VWCANVAS_PACKAGE_RECEIPT/2'; TransactionId = [guid]::NewGuid().ToString('N'); VariantKey = 'CANVAS'; PackageBaseName = 'Fixture'
    SourceEsm = [ordered]@{ File = 'Fixture.esm'; Sha256 = $esmSha }
    BuildEvidence = [ordered]@{ CompileEvidenceSha256 = $compileSha; ScaleformEvidenceSha256 = $scaleformSha }
    Candidate = [ordered]@{ Plugin = [ordered]@{ File = 'Fixture.esm'; Sha256 = $esmSha }; Archive = [ordered]@{ File = 'Fixture - Main.ba2'; Sha256 = $ba2Sha; Entries = $entries } }
    Installed = [ordered]@{ Plugin = [ordered]@{ File = 'Fixture.esm'; Sha256 = $esmSha }; Archive = [ordered]@{ File = 'Fixture - Main.ba2'; Sha256 = $ba2Sha; Entries = $entries } }
  }
  Assert-CanvasPackageReceipt -Receipt ([pscustomobject]$receipt) -Variant $variant -InstallPath $packageDirectory -ExpectedEntries $entries -CompileEvidenceSha256 $compileSha -ScaleformEvidenceSha256 $scaleformSha
  Write-CanvasUtf8WithoutBom -Path (Join-Path $receiptsDirectory 'CANVAS.json') -Text (($receipt | ConvertTo-Json -Depth 10) + "`n")
  [void](Get-CanvasPackageReceipts -ReceiptDirectory $receiptsDirectory -RequiredVariantKeys @('CANVAS'))

  Write-TestEsm -Path $esmPath -Marker 1
  Assert-TestRejected -Description 'Different valid-header installed ESM' -Action { Assert-CanvasPackageReceipt -Receipt ([pscustomobject]$receipt) -Variant $variant -InstallPath $packageDirectory -ExpectedEntries $entries -CompileEvidenceSha256 $compileSha -ScaleformEvidenceSha256 $scaleformSha }
  Write-TestEsm -Path $esmPath
  Write-TestBa2 -Path $ba2Path -Entries @{ 'Interface/test.swf' = [Text.Encoding]::UTF8.GetBytes('changed'); 'Scripts/test.pex' = [Text.Encoding]::UTF8.GetBytes('script') }
  Assert-TestRejected -Description 'Changed installed archive entry' -Action { Assert-CanvasPackageReceipt -Receipt ([pscustomobject]$receipt) -Variant $variant -InstallPath $packageDirectory -ExpectedEntries $entries -CompileEvidenceSha256 $compileSha -ScaleformEvidenceSha256 $scaleformSha }
  Write-TestBa2 -Path $ba2Path -Entries @{ 'Interface/test.swf' = [Text.Encoding]::UTF8.GetBytes('movie'); 'Scripts/test.pex' = [Text.Encoding]::UTF8.GetBytes('script') }
  [System.IO.File]::WriteAllText((Join-Path $packageDirectory 'extra.txt'), 'extra')
  Assert-TestRejected -Description 'Extra installed package file' -Action { Assert-CanvasPackageReceipt -Receipt ([pscustomobject]$receipt) -Variant $variant -InstallPath $packageDirectory -ExpectedEntries $entries -CompileEvidenceSha256 $compileSha -ScaleformEvidenceSha256 $scaleformSha }
  Remove-Item -LiteralPath (Join-Path $packageDirectory 'extra.txt') -Force
  Copy-Item -LiteralPath (Join-Path $receiptsDirectory 'CANVAS.json') -Destination (Join-Path $receiptsDirectory 'duplicate.json')
  Assert-TestRejected -Description 'Duplicate variant receipt' -Action { [void](Get-CanvasPackageReceipts -ReceiptDirectory $receiptsDirectory -RequiredVariantKeys @('CANVAS')) }
  Remove-Item -LiteralPath (Join-Path $receiptsDirectory 'duplicate.json') -Force
  Assert-TestRejected -Description 'Missing variant receipt' -Action { [void](Get-CanvasPackageReceipts -ReceiptDirectory $receiptsDirectory -RequiredVariantKeys @('EXAMPLE')) }
  [System.IO.File]::WriteAllText((Join-Path $receiptsDirectory 'EXAMPLE.json'), '{ invalid')
  [void](Get-CanvasPackageReceipts -ReceiptDirectory $receiptsDirectory -RequiredVariantKeys @('CANVAS') -WarningAction SilentlyContinue)
  Remove-Item -LiteralPath (Join-Path $receiptsDirectory 'EXAMPLE.json') -Force

  $receiptDestination = Join-Path $fixtureRoot 'published-receipt.json'
  $receiptBackup = Join-Path $fixtureRoot 'published-receipt.backup.json'
  [System.IO.File]::WriteAllText($receiptBackup, 'old-receipt')
  [System.IO.File]::WriteAllText($receiptDestination, 'new-receipt')
  $publication = [pscustomobject]@{ Destination = $receiptDestination; Backup = $receiptBackup; OriginalSha256 = Get-CanvasFileSha256 -Path $receiptBackup }
  Restore-CanvasReceiptPublication -Publication $publication
  if ([System.IO.File]::ReadAllText($receiptDestination) -cne 'old-receipt') { throw 'Receipt publication recovery did not restore the prior receipt.' }
  [System.IO.File]::WriteAllText($receiptDestination, 'newer-receipt')
  [System.IO.File]::WriteAllText($receiptBackup, 'corrupt-backup')
  $destinationHashBefore = Get-CanvasFileSha256 -Path $receiptDestination
  Assert-TestRejected -Description 'Corrupt receipt publication backup' -Action { Restore-CanvasReceiptPublication -Publication $publication }
  if ((Get-CanvasFileSha256 -Path $receiptDestination) -cne $destinationHashBefore) { throw 'Failed receipt recovery changed the published receipt before backup preflight.' }

  $transactionBase = Join-Path $fixtureRoot 'transactions'
  New-Item -ItemType Directory -Path $transactionBase | Out-Null
  Assert-CanvasNoIncompletePackageTransactions -TransactionBase $transactionBase
  $retainedTransaction = Join-Path $transactionBase ([guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $retainedTransaction | Out-Null
  Write-CanvasPackageTransactionJournal -TransactionPath $retainedTransaction -TransactionId (Split-Path -Leaf $retainedTransaction) -Status 'Active' -VariantKeys @('CANVAS')
  Assert-TestRejected -Description 'Retained interrupted transaction' -Action { Assert-CanvasNoIncompletePackageTransactions -TransactionBase $transactionBase }
  Remove-Item -LiteralPath $retainedTransaction -Recurse -Force

  if ($IsWindows) {
    $recoveryBackup = Join-Path $fixtureRoot 'installed-recovery'
    New-Item -ItemType Directory -Path $recoveryBackup | Out-Null
    $originalEsm = Join-Path $recoveryBackup 'Fixture.esm'
    Write-TestEsm -Path $originalEsm
    $originalHash = Get-CanvasFileSha256 -Path $originalEsm
    Write-TestEsm -Path (Join-Path $target 'Fixture.esm') -Marker 9
    [System.IO.File]::WriteAllText((Join-Path $target 'Fixture - Main.ba2'), 'candidate')
    $recoveryOperation = [pscustomobject]@{
      Key = 'CANVAS'; StagingPath = $staging; InstallPath = $target; BackupPath = $recoveryBackup
      CandidateNames = @('Fixture.esm', 'Fixture - Main.ba2'); OriginalNames = @('Fixture.esm'); OriginalHashes = @{ 'Fixture.esm' = $originalHash }
    }
    [System.IO.File]::AppendAllText($originalEsm, 'corrupt')
    $candidateHashBefore = Get-CanvasFileSha256 -Path (Join-Path $target 'Fixture.esm')
    Assert-TestRejected -Description 'Corrupt installed-package recovery backup' -Action { Restore-CanvasPackageOperation -Operation $recoveryOperation }
    if ((Get-CanvasFileSha256 -Path (Join-Path $target 'Fixture.esm')) -cne $candidateHashBefore -or !(Test-Path -LiteralPath (Join-Path $target 'Fixture - Main.ba2') -PathType Leaf)) {
      throw 'Installed-package recovery mutated the candidate before complete backup preflight.'
    }
    Write-TestEsm -Path $originalEsm
    Restore-CanvasPackageOperation -Operation $recoveryOperation
    if ((Get-CanvasFileSha256 -Path (Join-Path $target 'Fixture.esm')) -cne $originalHash -or (Test-Path -LiteralPath (Join-Path $target 'Fixture - Main.ba2'))) {
      throw 'Installed-package recovery did not restore the exact prior inventory and bytes.'
    }
  }

  $lockPath = Join-Path $fixtureRoot 'package.lock'
  $lock = Enter-CanvasPackageLock -Path $lockPath -TransactionId ([guid]::NewGuid().ToString('N'))
  try {
    $childResult = Join-Path $fixtureRoot 'child-lock-result.txt'
    $command = @"
. '$((Join-Path $PSScriptRoot 'sharedConfig.ps1').Replace("'", "''"))' -SkipEnvironment
. '$((Join-Path $PSScriptRoot 'sharedCanvas.ps1').Replace("'", "''"))'
try { `$held = Enter-CanvasPackageLock -Path '$($lockPath.Replace("'", "''"))' -TransactionId '$([guid]::NewGuid().ToString('N'))'; `$held.Dispose(); [IO.File]::WriteAllText('$($childResult.Replace("'", "''"))', 'ACQUIRED') }
catch { [IO.File]::WriteAllText('$($childResult.Replace("'", "''"))', 'REJECTED') }
"@
    $startProcessParameters = @{
      FilePath = (Get-Process -Id $PID).Path
      ArgumentList = @('-NoProfile', '-Command', $command)
      PassThru = $true
    }
    if ($IsWindows) { $startProcessParameters.WindowStyle = 'Hidden' }
    $child = Start-Process @startProcessParameters
    if (!$child.WaitForExit(10000)) { $child.Kill(); throw 'Competing package-lock process did not finish.' }
    if ([System.IO.File]::ReadAllText($childResult) -cne 'REJECTED') { throw 'Competing process acquired an already-held package lock.' }
  }
  finally { $lock.Dispose() }
  $reacquired = Enter-CanvasPackageLock -Path $lockPath -TransactionId ([guid]::NewGuid().ToString('N'))
  $reacquired.Dispose()

  if ($IsWindows) {
    $holderMarker = Join-Path $fixtureRoot 'holder-ready.txt'
    $holderCommand = @"
. '$((Join-Path $PSScriptRoot 'sharedConfig.ps1').Replace("'", "''"))' -SkipEnvironment
. '$((Join-Path $PSScriptRoot 'sharedCanvas.ps1').Replace("'", "''"))'
`$held = Enter-CanvasPackageLock -Path '$($lockPath.Replace("'", "''"))' -TransactionId '$([guid]::NewGuid().ToString('N'))'
[IO.File]::WriteAllText('$($holderMarker.Replace("'", "''"))', 'READY')
Start-Sleep -Seconds 30
"@
    $holder = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-Command', $holderCommand) -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (!(Test-Path -LiteralPath $holderMarker -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
    if (!(Test-Path -LiteralPath $holderMarker -PathType Leaf)) { $holder.Kill(); throw 'Lock-holder process did not reach its barrier.' }
    $holder.Kill()
    $holder.WaitForExit()
    $afterTermination = Enter-CanvasPackageLock -Path $lockPath -TransactionId ([guid]::NewGuid().ToString('N'))
    $afterTermination.Dispose()
  }
}
finally {
  [Environment]::SetEnvironmentVariable('TEST_CANVAS_TARGET', $originalCanvasTarget, 'Process')
  [Environment]::SetEnvironmentVariable('TEST_EXAMPLE_TARGET', $originalExampleTarget, 'Process')
  if (Test-Path -LiteralPath $fixtureRoot) {
    Assert-CanvasRemovalPath -Path $fixtureRoot -AllowedRoot $testBase
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}

Write-Output 'Packaging contracts passed: exact Junction preflight, selected/unselected target isolation, single-read proof snapshots, admitted movie/Core hashes, candidate-bound installed receipts, exact BA2 entries/inventories, duplicate/missing evidence rejection, retained-transaction blocking, publication/package recovery preflight, and platform-safe process-held lock exclusion/termination recovery.'
