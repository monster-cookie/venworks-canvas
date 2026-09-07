$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-CanvasSamePath {
  param(
    [Parameter(Mandatory = $true)][string]$Left,
    [Parameter(Mandatory = $true)][string]$Right
  )

  return [string]::Equals(
    (Get-CanvasNormalizedFullPath -Path $Left),
    (Get-CanvasNormalizedFullPath -Path $Right),
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

function Get-CanvasJsonEvidenceSnapshot {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description,
    [Parameter(Mandatory = $true)][string]$TransactionFileName
  )

  $resolvedPath = Resolve-CanvasRequiredFile -Path $Path -Description $Description
  $bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
  $sha256 = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))
  try {
    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $value = $text | ConvertFrom-Json
  }
  catch {
    throw "$Description is not valid UTF-8 JSON: $($_.Exception.Message)"
  }
  return [pscustomobject]@{
    SourcePath = $resolvedPath
    TransactionFileName = $TransactionFileName
    Bytes = $bytes
    Sha256 = $sha256
    Value = $value
  }
}

function Write-CanvasJsonEvidenceSnapshot {
  param(
    [Parameter(Mandatory = $true)][object]$Snapshot,
    [Parameter(Mandatory = $true)][string]$Directory
  )

  $destination = Join-Path $Directory ([string]$Snapshot.TransactionFileName)
  [System.IO.File]::WriteAllBytes($destination, [byte[]]$Snapshot.Bytes)
  if ((Get-CanvasFileSha256 -Path $destination) -cne [string]$Snapshot.Sha256) {
    throw "Admitted evidence snapshot differs after writing '$destination'."
  }
  $Snapshot | Add-Member -NotePropertyName TransactionPath -NotePropertyValue $destination -Force
}

function Get-CanvasJunctionTarget {
  param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Item)

  $targets = @($Item.Target)
  if ($targets.Count -ne 1) { return $null }
  return Get-CanvasNormalizedFullPath -Path ([string]$targets[0])
}

function Assert-CanvasJunctionTarget {
  param(
    [Parameter(Mandatory = $true)][string]$StagingPath,
    [Parameter(Mandatory = $true)][string]$ExpectedTargetPath
  )

  $item = Get-Item -LiteralPath $StagingPath -Force -ErrorAction SilentlyContinue
  if ($null -eq $item -or !$item.PSIsContainer -or [string]$item.LinkType -cne 'Junction') {
    throw "Staging path must be an existing Junction prepared by the maintainer: $StagingPath"
  }
  $actualTarget = Get-CanvasJunctionTarget -Item $item
  if ($null -eq $actualTarget -or !(Test-CanvasSamePath -Left $actualTarget -Right $ExpectedTargetPath)) {
    throw "Staging Junction does not target its configured physical module folder: $StagingPath"
  }
}

function Resolve-CanvasArchiveTarget {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Target
  )

  if ([string]::IsNullOrWhiteSpace($Target) -or [System.IO.Path]::IsPathRooted($Target) -or $Target.Contains(':')) {
    throw "Archive payload target must be a non-rooted relative path: '$Target'."
  }
  $segments = $Target.Split([char[]]@('\', '/'), [System.StringSplitOptions]::None)
  if (@($segments | Where-Object { [string]::IsNullOrEmpty($_) -or $_ -ceq '.' -or $_ -ceq '..' }).Count -ne 0) {
    throw "Archive payload target contains an empty or traversal segment: '$Target'."
  }
  $rootPath = Get-CanvasNormalizedFullPath -Path $Root
  $targetPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $Target))
  if (!$targetPath.StartsWith($rootPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Archive payload target escapes its package root: '$Target'."
  }
  return $targetPath
}

function Get-CanvasPackageInstallOperations {
  param(
    [Parameter(Mandatory = $true)][object[]]$SelectedVariants,
    [Parameter(Mandatory = $true)][object[]]$AllVariants
  )

  $allStagingPaths = @($AllVariants | ForEach-Object { Get-CanvasNormalizedFullPath -Path ([string]$_.StagingFolderPath) })
  $selectedKeys = @($SelectedVariants | ForEach-Object { [string]$_.VariantKey })
  $configuredTargets = @($AllVariants | ForEach-Object {
    $configured = [Environment]::GetEnvironmentVariable([string]$_.EnvironmentVariableName, 'Process')
    if (![string]::IsNullOrWhiteSpace($configured)) {
      [pscustomobject]@{ Key = [string]$_.VariantKey; Path = Get-CanvasNormalizedFullPath -Path $configured }
    }
  })
  for ($left = 0; $left -lt $configuredTargets.Count; $left++) {
    for ($right = $left + 1; $right -lt $configuredTargets.Count; $right++) {
      if (($configuredTargets[$left].Key -in $selectedKeys -or $configuredTargets[$right].Key -in $selectedKeys) -and
          (Test-CanvasOverlappingPaths -Left $configuredTargets[$left].Path -Right $configuredTargets[$right].Path)) {
        throw "$($configuredTargets[$left].Key) and $($configuredTargets[$right].Key) configured physical module folders overlap."
      }
    }
  }
  $operations = [System.Collections.Generic.List[object]]::new()
  foreach ($variant in @($SelectedVariants)) {
    $key = [string]$variant.VariantKey
    $stagingPath = Get-CanvasNormalizedFullPath -Path ([string]$variant.StagingFolderPath)
    $configuredTarget = [Environment]::GetEnvironmentVariable([string]$variant.EnvironmentVariableName, 'Process')
    if ([string]::IsNullOrWhiteSpace($configuredTarget)) {
      throw "$key physical module folder is not configured. Set $($variant.EnvironmentVariableName) before packaging."
    }
    $targetPath = Get-CanvasNormalizedFullPath -Path $configuredTarget
    if (@($allStagingPaths | Where-Object { Test-CanvasOverlappingPaths -Left $_ -Right $targetPath }).Count -ne 0) {
      throw "$key physical module folder cannot overlap a repository staging path: $targetPath"
    }
    if (@($operations | Where-Object { Test-CanvasOverlappingPaths -Left ([string]$_.InstallPath) -Right $targetPath }).Count -ne 0) {
      throw "Selected physical module folders must be disjoint: $targetPath"
    }

    Assert-CanvasJunctionTarget -StagingPath $stagingPath -ExpectedTargetPath $targetPath
    $targetItem = Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $targetItem -or !$targetItem.PSIsContainer -or $null -ne $targetItem.LinkType) {
      throw "$key physical module target must be an existing real directory: $targetPath"
    }

    $pluginName = "$($variant.PackageBaseName).esm"
    $archiveName = "$($variant.PackageBaseName) - Main.ba2"
    $items = @(Get-ChildItem -LiteralPath $targetPath -Force)
    if (@($items | Where-Object { $_.PSIsContainer }).Count -ne 0) {
      throw "$key physical module target may contain only its canonical ESM and optional BA2."
    }
    $names = @($items.Name)
    if ($pluginName -cnotin $names -or @($names | Where-Object { $_ -cne $pluginName -and $_ -cne $archiveName }).Count -ne 0) {
      throw "$key physical module target must contain its live '$pluginName' and may contain only '$archiveName' in addition."
    }
    $pluginPath = Resolve-CanvasRequiredFile -Path (Join-Path $targetPath $pluginName) -Description "$key live staging ESM"
    Assert-CanvasArtifactHeader -Path $pluginPath
    $archivePath = Join-Path $targetPath $archiveName
    if (Test-Path -LiteralPath $archivePath -PathType Leaf) { Assert-CanvasArtifactHeader -Path $archivePath }
    $operations.Add([pscustomobject]@{
      Key = $key
      Variant = $variant
      StagingPath = $stagingPath
      InstallPath = $targetPath
      PluginName = $pluginName
      ArchiveName = $archiveName
      SourcePluginPath = $pluginPath
    })
  }
  return @($operations)
}

function Enter-CanvasPackageLock {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$TransactionId
  )

  $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  try {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
  }
  catch [System.IO.IOException] {
    throw "Another Canvas package process owns the exclusive package lock: $Path"
  }
  try {
    $content = [System.Text.UTF8Encoding]::new($false).GetBytes("VWCANVAS_PACKAGE_LOCK/1`nTransaction=$TransactionId`nProcess=$PID`n")
    $stream.SetLength(0)
    $stream.Write($content, 0, $content.Length)
    $stream.Flush($true)
    return $stream
  }
  catch {
    $stream.Dispose()
    throw
  }
}

function Assert-CanvasNoIncompletePackageTransactions {
  param([Parameter(Mandatory = $true)][string]$TransactionBase)

  $base = [System.IO.Path]::GetFullPath($TransactionBase)
  if (!(Test-Path -LiteralPath $base -PathType Container)) { return }
  $retained = @(Get-ChildItem -LiteralPath $base -Directory -Force)
  if ($retained.Count -ne 0) {
    $descriptions = @($retained | ForEach-Object {
      $journalPath = Join-Path $_.FullName 'transaction.json'
      if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
        try {
          $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
          "$($_.Name) [$($journal.Status)]"
        }
        catch { "$($_.Name) [unreadable journal]" }
      }
      else { "$($_.Name) [missing journal]" }
    })
    throw "Retained Canvas package transaction directories require manual inspection before packaging: $([string]::Join(', ', $descriptions))"
  }
}

function Write-CanvasPackageTransactionJournal {
  param(
    [Parameter(Mandatory = $true)][string]$TransactionPath,
    [Parameter(Mandatory = $true)][string]$TransactionId,
    [Parameter(Mandatory = $true)][string]$Status,
    [Parameter(Mandatory = $true)][string[]]$VariantKeys,
    [string]$Failure
  )

  $journal = [ordered]@{
    Schema = 'VWCANVAS_PACKAGE_TRANSACTION/1'
    TransactionId = $TransactionId
    ProcessId = $PID
    Status = $Status
    Variants = @($VariantKeys)
    Failure = if ([string]::IsNullOrWhiteSpace($Failure)) { $null } else { $Failure }
  }
  Write-CanvasUtf8WithoutBom -Path (Join-Path $TransactionPath 'transaction.json') -Text (($journal | ConvertTo-Json -Depth 5) + "`n")
}

function Restore-CanvasReceiptPublication {
  param([Parameter(Mandatory = $true)][object]$Publication)

  if ($null -eq $Publication.Backup) {
    if (Test-Path -LiteralPath $Publication.Destination -PathType Leaf) { Remove-Item -LiteralPath $Publication.Destination -Force }
    return
  }
  $backupPath = Resolve-CanvasRequiredFile -Path ([string]$Publication.Backup) -Description 'Prior package receipt backup'
  $expectedHash = [string]$Publication.OriginalSha256
  if ($expectedHash -cnotmatch '^[0-9A-F]{64}$' -or (Get-CanvasFileSha256 -Path $backupPath) -cne $expectedHash) {
    throw 'Prior package receipt backup failed recovery preflight.'
  }
  $destination = [string]$Publication.Destination
  $temporaryPath = "$destination.$PID-$([guid]::NewGuid().ToString('N')).restore"
  try {
    Copy-Item -LiteralPath $backupPath -Destination $temporaryPath
    if ((Get-CanvasFileSha256 -Path $temporaryPath) -cne $expectedHash) { throw 'Prior package receipt restore copy differs.' }
    [System.IO.File]::Move($temporaryPath, $destination, $true)
    if ((Get-CanvasFileSha256 -Path $destination) -cne $expectedHash) { throw 'Prior package receipt differs after recovery.' }
  }
  finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
  }
}

function Restore-CanvasPackageOperation {
  param([Parameter(Mandatory = $true)][object]$Operation)

  Assert-CanvasJunctionTarget -StagingPath $Operation.StagingPath -ExpectedTargetPath $Operation.InstallPath
  $backupItems = @(Get-ChildItem -LiteralPath $Operation.BackupPath -Force)
  if (@($backupItems | Where-Object { $_.PSIsContainer }).Count -ne 0) { throw "$($Operation.Key) recovery backup contains a directory." }
  Assert-CanvasExactNames -Actual @($backupItems.Name) -Expected @($Operation.OriginalNames) -Description "$($Operation.Key) recovery backup inventory"
  foreach ($name in @($Operation.OriginalNames)) {
    $backupPath = Resolve-CanvasRequiredFile -Path (Join-Path $Operation.BackupPath $name) -Description "$($Operation.Key) recovery file '$name'"
    if (!$Operation.OriginalHashes.ContainsKey($name) -or (Get-CanvasFileSha256 -Path $backupPath) -cne [string]$Operation.OriginalHashes[$name]) {
      throw "$($Operation.Key) recovery backup failed preflight for '$name'."
    }
  }

  foreach ($name in @($Operation.CandidateNames)) {
    $installedPath = Join-Path $Operation.InstallPath $name
    if (Test-Path -LiteralPath $installedPath -PathType Leaf) { Remove-Item -LiteralPath $installedPath -Force }
  }
  foreach ($name in @($Operation.OriginalNames)) {
    $backupPath = Join-Path $Operation.BackupPath $name
    $destination = Join-Path $Operation.InstallPath $name
    $expectedHash = [string]$Operation.OriginalHashes[$name]
    $temporaryPath = "$destination.$PID-$([guid]::NewGuid().ToString('N')).restore"
    try {
      Copy-Item -LiteralPath $backupPath -Destination $temporaryPath
      if ((Get-CanvasFileSha256 -Path $temporaryPath) -cne $expectedHash) { throw "$($Operation.Key) recovery copy differs for '$name'." }
      [System.IO.File]::Move($temporaryPath, $destination, $true)
      if ((Get-CanvasFileSha256 -Path $destination) -cne $expectedHash) { throw "$($Operation.Key) restored file differs for '$name'." }
    }
    finally {
      if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
  }
  $restored = @(Get-ChildItem -LiteralPath $Operation.InstallPath -Force)
  if (@($restored | Where-Object { $_.PSIsContainer }).Count -ne 0) { throw "$($Operation.Key) restored package contains a directory." }
  Assert-CanvasExactNames -Actual @($restored.Name) -Expected @($Operation.OriginalNames) -Description "$($Operation.Key) restored inventory"
}

function Get-CanvasGeneralBa2Evidence {
  param([Parameter(Mandatory = $true)][string]$Path)

  $rows = [System.Collections.Generic.List[object]]::new()
  $normalizedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($entry in @(Get-CanvasGeneralBa2Entries -Path $Path)) {
    if ([uint32]$entry.PackedSize -ne 0) { throw "Canvas archive contains compressed entry '$($entry.Name)'." }
    $name = ([string]$entry.Name).Replace('\', '/').ToLowerInvariant()
    if (!$normalizedNames.Add($name)) { throw "Canvas archive contains duplicate entry '$name'." }
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = [Convert]::ToHexString($algorithm.ComputeHash((Read-CanvasGeneralBa2EntryBytes -Entry $entry))) }
    finally { $algorithm.Dispose() }
    $rows.Add([ordered]@{ Path = $name; Sha256 = $hash })
  }
  return @($rows | Sort-Object Path)
}

function Assert-CanvasArchiveEvidenceRows {
  param(
    [Parameter(Mandatory = $true)][object[]]$Actual,
    [Parameter(Mandatory = $true)][object[]]$Expected,
    [Parameter(Mandatory = $true)][string]$Description
  )

  Assert-CanvasExactNames -Actual @($Actual | ForEach-Object { ([string]$_.Path).ToLowerInvariant() }) -Expected @($Expected | ForEach-Object { ([string]$_.Path).ToLowerInvariant() }) -Description "$Description path inventory"
  foreach ($expectedRow in @($Expected)) {
    $path = ([string]$expectedRow.Path).ToLowerInvariant()
    $matchingRows = @($Actual | Where-Object { ([string]$_.Path).ToLowerInvariant() -ceq $path })
    if ($matchingRows.Count -ne 1 -or [string]$matchingRows[0].Sha256 -cne [string]$expectedRow.Sha256) {
      throw "$Description differs for '$path'."
    }
  }
}

function Get-CanvasPackageReceipts {
  param(
    [Parameter(Mandatory = $true)][string]$ReceiptDirectory,
    [Parameter(Mandatory = $true)][string[]]$RequiredVariantKeys
  )

  $directory = Resolve-CanvasRequiredDirectory -Path $ReceiptDirectory -Description 'Canvas package receipt directory'
  $receipts = [System.Collections.Generic.List[object]]::new()
  foreach ($receiptFile in @(Get-ChildItem -LiteralPath $directory -File -Filter '*.json')) {
    try {
      $receipt = Get-Content -LiteralPath $receiptFile.FullName -Raw | ConvertFrom-Json
      $receipt | Add-Member -NotePropertyName EvidenceFileName -NotePropertyValue $receiptFile.Name -Force
      $receipts.Add($receipt)
    }
    catch {
      if ($receiptFile.BaseName -in $RequiredVariantKeys) { throw "Required package receipt '$($receiptFile.Name)' is unreadable: $($_.Exception.Message)" }
      Write-Warning "Unselected package receipt '$($receiptFile.Name)' is unreadable and was not validated."
    }
  }
  foreach ($key in $RequiredVariantKeys) {
    $matchingReceipts = @($receipts | Where-Object { [string]$_.VariantKey -ceq $key })
    if ($matchingReceipts.Count -ne 1) { throw "Package evidence must contain exactly one receipt for '$key'; found $($matchingReceipts.Count)." }
    if ([string]$matchingReceipts[0].EvidenceFileName -cne "$key.json") { throw "Required package receipt for '$key' is not stored at its canonical filename '$key.json'." }
  }
  foreach ($key in $RequiredVariantKeys) {
    if (@($receipts | Where-Object { [string]$_.VariantKey -ceq $key }).Count -ne 1) { throw "Package evidence contains duplicate variant receipts for '$key'." }
  }
  return @($receipts)
}

function Get-CanvasPackagePayloads {
  param(
    [Parameter(Mandatory = $true)][object[]]$SelectedVariants,
    [Parameter(Mandatory = $true)][object]$CompileEvidence,
    [Parameter(Mandatory = $true)][object]$MovieEvidence,
    [Parameter(Mandatory = $true)][string]$MoviesDirectory,
    [Parameter(Mandatory = $true)][string]$ScriptsDirectory,
    [Parameter(Mandatory = $true)][string]$VenworksCoreRepositoryPath,
    [Parameter(Mandatory = $true)][hashtable]$Matrix,
    [string]$PlayerDirectory,
    [object]$PlayerEvidence,
    [string]$ShipDirectory,
    [object]$ShipEvidence
  )

  $payloads = @{}
  foreach ($variant in $SelectedVariants) {
    $key = [string]$variant.VariantKey
    $rows = [System.Collections.Generic.List[object]]::new()
    $movieRow = @($MovieEvidence.Movies | Where-Object { [string]$_.VariantKey -ceq $key })
    if ($movieRow.Count -ne 1) { throw "Canvas movie evidence does not contain exactly one '$key' package input." }
    $movieSource = Resolve-CanvasRequiredFile -Path (Join-Path $MoviesDirectory ([string]$movieRow[0].OutputFile)) -Description "$key Canvas movie"
    switch ($key) {
      'CANVAS' {
        if ($null -eq $PlayerEvidence -or $null -eq $ShipEvidence -or
            [string]::IsNullOrWhiteSpace($PlayerDirectory) -or [string]::IsNullOrWhiteSpace($ShipDirectory)) {
          throw 'CANVAS packaging requires validated Player HUD and Ship HUD evidence.'
        }
        $rows.Add([pscustomobject]@{ Source = $movieSource; Target = 'Interface\venworkscui.swf'; ExpectedSha256 = [string]$movieRow[0].Sha256 })
        foreach ($movie in @($ShipEvidence.Movies)) { $rows.Add([pscustomobject]@{ Source = (Join-Path $ShipDirectory ([string]$movie.File)); Target = "Interface\$($movie.File)"; ExpectedSha256 = [string]$movie.Sha256 }) }
        foreach ($movie in @($PlayerEvidence.Movies)) { $rows.Add([pscustomobject]@{ Source = (Join-Path $PlayerDirectory ([string]$movie.File)); Target = "Interface\$($movie.File)"; ExpectedSha256 = [string]$movie.Sha256 }) }
      }
      'EXAMPLE' {
        $rows.Add([pscustomobject]@{ Source = $movieSource; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.example\normal.swf'; ExpectedSha256 = [string]$movieRow[0].Sha256 })
        $rows.Add([pscustomobject]@{ Source = $movieSource; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.example\large.swf'; ExpectedSha256 = [string]$movieRow[0].Sha256 })
      }
      'COMPONENTGALLERY' {
        $rows.Add([pscustomobject]@{ Source = $movieSource; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.component-gallery\normal.swf'; ExpectedSha256 = [string]$movieRow[0].Sha256 })
        $rows.Add([pscustomobject]@{ Source = $movieSource; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.component-gallery\large.swf'; ExpectedSha256 = [string]$movieRow[0].Sha256 })
      }
      default { throw "Package payload mapping is missing for '$key'." }
    }
    foreach ($script in @($variant.PapyrusScripts)) {
      $relativeOutput = [System.IO.Path]::ChangeExtension(([string]$script), '.pex')
      $canonicalSource = ([string]$script).Replace('\', '/')
      $compileRow = @($CompileEvidence.Scripts | Where-Object { ([string]$_.Source).Replace('\', '/') -ceq $canonicalSource })
      if ($compileRow.Count -ne 1 -or [string]$compileRow[0].Output -cne $relativeOutput.Replace('\', '/')) {
        throw "$key package payload does not resolve exactly one admitted compile row for '$canonicalSource'."
      }
      $rows.Add([pscustomobject]@{ Source = (Join-Path $ScriptsDirectory $relativeOutput); Target = "Scripts\$relativeOutput"; ExpectedSha256 = [string]$compileRow[0].Sha256 })
    }
    if ($key -ceq 'CANVAS') {
      foreach ($coreScript in @($Matrix.VenworksCoreFixture.RuntimeScripts)) {
        $rows.Add([pscustomobject]@{ Source = (Join-Path $VenworksCoreRepositoryPath ([string]$coreScript.Source)); Target = ([string]$coreScript.Target).Replace('/', '\'); ExpectedSha256 = [string]$coreScript.Sha256 })
      }
    }
    $resolvedRows = @($rows | ForEach-Object {
      [pscustomobject]@{
        Source = Resolve-CanvasRequiredFile -Path ([string]$_.Source) -Description "$key payload '$($_.Target)'"
        Target = ([string]$_.Target).Replace('/', '\')
        ExpectedSha256 = [string]$_.ExpectedSha256
      }
    })
    foreach ($row in $resolvedRows) {
      if ([string]$row.ExpectedSha256 -cnotmatch '^[0-9A-F]{64}$') { throw "$key package payload has an invalid admitted hash for '$($row.Target)'." }
    }
    $targetNames = @($resolvedRows | ForEach-Object { ([string]$_.Target).Replace('\', '/').ToLowerInvariant() })
    if (@($targetNames | Select-Object -Unique).Count -ne $targetNames.Count) { throw "$key package payload contains duplicate archive targets." }
    $payloads[$key] = $resolvedRows
  }
  return $payloads
}

function Assert-CanvasPackageReceipt {
  param(
    [Parameter(Mandatory = $true)][object]$Receipt,
    [Parameter(Mandatory = $true)][object]$Variant,
    [Parameter(Mandatory = $true)][string]$InstallPath,
    [Parameter(Mandatory = $true)][object[]]$ExpectedEntries,
    [Parameter(Mandatory = $true)][string]$CompileEvidenceSha256,
    [Parameter(Mandatory = $true)][string]$ScaleformEvidenceSha256
  )

  $key = [string]$Variant.VariantKey
  $pluginName = "$($Variant.PackageBaseName).esm"
  $archiveName = "$($Variant.PackageBaseName) - Main.ba2"
  if ([string]$Receipt.Schema -cne 'VWCANVAS_PACKAGE_RECEIPT/2' -or
      [string]$Receipt.VariantKey -cne $key -or [string]$Receipt.PackageBaseName -cne [string]$Variant.PackageBaseName -or
      [string]$Receipt.BuildEvidence.CompileEvidenceSha256 -cne $CompileEvidenceSha256 -or
      [string]$Receipt.BuildEvidence.ScaleformEvidenceSha256 -cne $ScaleformEvidenceSha256) {
    throw "$key package receipt identity or build provenance differs."
  }
  $transactionGuid = [guid]::Empty
  if (![guid]::TryParseExact([string]$Receipt.TransactionId, 'N', [ref]$transactionGuid)) {
    throw "$key package receipt has an invalid transaction identity."
  }
  $items = @(Get-ChildItem -LiteralPath $InstallPath -Force)
  if (@($items | Where-Object { $_.PSIsContainer }).Count -ne 0) { throw "$key installed package contains a directory." }
  Assert-CanvasExactNames -Actual @($items.Name) -Expected @($pluginName, $archiveName) -Description "$key installed package inventory"
  $pluginPath = Resolve-CanvasRequiredFile -Path (Join-Path $InstallPath $pluginName) -Description "$key installed ESM"
  $archivePath = Resolve-CanvasRequiredFile -Path (Join-Path $InstallPath $archiveName) -Description "$key installed BA2"
  Assert-CanvasArtifactHeader -Path $pluginPath
  Assert-CanvasArtifactHeader -Path $archivePath
  $pluginSha = Get-CanvasFileSha256 -Path $pluginPath
  $archiveSha = Get-CanvasFileSha256 -Path $archivePath
  if ([string]$Receipt.SourceEsm.File -cne $pluginName -or
      [string]$Receipt.Candidate.Plugin.File -cne $pluginName -or [string]$Receipt.Installed.Plugin.File -cne $pluginName -or
      [string]$Receipt.Candidate.Archive.File -cne $archiveName -or [string]$Receipt.Installed.Archive.File -cne $archiveName -or
      [string]$Receipt.SourceEsm.Sha256 -cne $pluginSha -or
      [string]$Receipt.Candidate.Plugin.Sha256 -cne $pluginSha -or [string]$Receipt.Installed.Plugin.Sha256 -cne $pluginSha -or
      [string]$Receipt.Candidate.Archive.Sha256 -cne $archiveSha -or [string]$Receipt.Installed.Archive.Sha256 -cne $archiveSha) {
    throw "$key installed package hashes do not match the validated input and candidate receipt."
  }
  $actualEntries = @(Get-CanvasGeneralBa2Evidence -Path $archivePath)
  Assert-CanvasArchiveEvidenceRows -Actual $actualEntries -Expected @($Receipt.Candidate.Archive.Entries) -Description "$key candidate archive evidence"
  Assert-CanvasArchiveEvidenceRows -Actual $actualEntries -Expected @($Receipt.Installed.Archive.Entries) -Description "$key installed archive evidence"
  Assert-CanvasArchiveEvidenceRows -Actual $actualEntries -Expected $ExpectedEntries -Description "$key current package payload"
}
