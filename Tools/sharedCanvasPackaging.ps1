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

function Get-CanvasGeneralBa2Contents {
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

function Assert-CanvasArchiveContents {
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

function Get-CanvasPackagePayloads {
  param(
    [Parameter(Mandatory = $true)][object[]]$SelectedVariants,
    [Parameter(Mandatory = $true)][string]$MoviesDirectory,
    [Parameter(Mandatory = $true)][string]$ScriptsDirectory,
    [string]$PlayerDirectory,
    [string]$ShipDirectory
  )

  $playerNames = @('playerhudcomponents.swf', 'playerhudcomponents.gfx', 'playerhudcomponents_lrg.swf', 'playerhudcomponents_lrg.gfx')
  $shipNames = @('spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf')
  $payloads = @{}
  foreach ($variant in $SelectedVariants) {
    $key = [string]$variant.VariantKey
    $rows = [System.Collections.Generic.List[object]]::new()
    $movieSource = Join-Path $MoviesDirectory ([string]$variant.ScaleformOutput)
    switch ($key) {
      'CANVAS' {
        if ([string]::IsNullOrWhiteSpace($PlayerDirectory) -or [string]::IsNullOrWhiteSpace($ShipDirectory)) {
          throw 'CANVAS packaging requires Player HUD and Ship HUD output directories.'
        }
        $rows.Add([pscustomobject]@{ Source = $movieSource; Target = 'Interface\venworkscui.swf' })
        foreach ($name in $playerNames) { $rows.Add([pscustomobject]@{ Source = (Join-Path $PlayerDirectory $name); Target = "Interface\$name" }) }
        foreach ($name in $shipNames) { $rows.Add([pscustomobject]@{ Source = (Join-Path $ShipDirectory $name); Target = "Interface\$name" }) }
      }
      'EXAMPLE' {
        $rows.Add([pscustomobject]@{ Source = $movieSource; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.example\normal.swf' })
        $rows.Add([pscustomobject]@{ Source = $movieSource; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.example\large.swf' })
      }
      'COMPONENTGALLERY' {
        $rows.Add([pscustomobject]@{ Source = $movieSource; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.component-gallery\normal.swf' })
        $rows.Add([pscustomobject]@{ Source = $movieSource; Target = 'Interface\VenworksCanvas\Consumers\venworks.canvas.component-gallery\large.swf' })
      }
      default { throw "Package payload mapping is missing for '$key'." }
    }
    foreach ($script in @($variant.PapyrusScripts)) {
      $relativeOutput = [System.IO.Path]::ChangeExtension(([string]$script), '.pex')
      $rows.Add([pscustomobject]@{ Source = (Join-Path $ScriptsDirectory $relativeOutput); Target = "Scripts\$relativeOutput" })
    }
    $resolvedRows = @($rows | ForEach-Object {
      $row = $_
      $target = ([string]$_.Target).Replace('/', '\')
      $description = "$key payload '$target'"
      $source = switch ([System.IO.Path]::GetExtension($target).ToLowerInvariant()) {
        '.pex' { Assert-CanvasPapyrusFile -Path ([string]$row.Source) -Description $description }
        '.swf' { Assert-CanvasScaleformFile -Path ([string]$row.Source) -Description $description }
        '.gfx' { Assert-CanvasScaleformFile -Path ([string]$row.Source) -Description $description }
        default { throw "$description has an unsupported package payload type." }
      }
      [pscustomobject]@{
        Source = $source
        Target = $target
        ExpectedSha256 = Get-CanvasFileSha256 -Path $source
      }
    })
    $targetNames = @($resolvedRows | ForEach-Object { ([string]$_.Target).Replace('\', '/').ToLowerInvariant() })
    if (@($targetNames | Select-Object -Unique).Count -ne $targetNames.Count) { throw "$key package payload contains duplicate archive targets." }
    $payloads[$key] = $resolvedRows
  }
  return $payloads
}

function Assert-CanvasInstalledPackage {
  param(
    [Parameter(Mandatory = $true)][object]$Variant,
    [Parameter(Mandatory = $true)][string]$InstallPath,
    [Parameter(Mandatory = $true)][object[]]$ExpectedEntries
  )

  $key = [string]$Variant.VariantKey
  $pluginName = "$($Variant.PackageBaseName).esm"
  $archiveName = "$($Variant.PackageBaseName) - Main.ba2"
  $directory = Resolve-CanvasRequiredDirectory -Path $InstallPath -Description "$key installed package directory"
  $items = @(Get-ChildItem -LiteralPath $directory -Force)
  if (@($items | Where-Object { $_.PSIsContainer }).Count -ne 0) { throw "$key installed package contains a directory." }
  Assert-CanvasExactNames -Actual @($items.Name) -Expected @($pluginName, $archiveName) -Description "$key installed package inventory"
  $pluginPath = Resolve-CanvasRequiredFile -Path (Join-Path $directory $pluginName) -Description "$key installed ESM"
  $archivePath = Resolve-CanvasRequiredFile -Path (Join-Path $directory $archiveName) -Description "$key installed BA2"
  Assert-CanvasArtifactHeader -Path $pluginPath
  Assert-CanvasArtifactHeader -Path $archivePath
  $actualEntries = @(Get-CanvasGeneralBa2Contents -Path $archivePath)
  Assert-CanvasArchiveContents -Actual $actualEntries -Expected $ExpectedEntries -Description "$key installed archive"
}
