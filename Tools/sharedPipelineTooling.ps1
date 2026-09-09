#Requires -Version 7.0

Set-StrictMode -Version Latest

function Get-PipelineToolingContract {
  return [pscustomobject]@{
    Versions = [pscustomobject]@{
      Java = '21.0.12.1+1'
      Jpexs = '26.2.1'
      ApacheFlex = '4.16.1'
      AdobeFlex = '4.6.0.23201B'
      PlayerGlobal = '11.1'
    }
    Artifacts = [ordered]@{
      Java = [pscustomobject]@{
        FileName = 'OpenJDK21U-jdk_x64_windows_hotspot_21.0.12.1_1.zip'
        Uri = 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_windows_hotspot_21.0.12.1_1.zip'
        Length = [int64]205073461
        Sha256 = 'f9d6e191ab098c0d416e7d588a24420a8621cd2f4720dab2459b8b7b2d2d8b4e'
      }
      Jpexs = [pscustomobject]@{
        FileName = 'ffdec_26.2.1.zip'
        Uri = 'https://github.com/jindrapetrik/jpexs-decompiler/releases/download/version26.2.1/ffdec_26.2.1.zip'
        Length = [int64]19824405
        Sha256 = '0333b56998a55bd83f4e0deb678a811fcdc45607582b4f5dd438309c8c3ad5ce'
      }
      ApacheFlex = [pscustomobject]@{
        FileName = 'apache-flex-sdk-4.16.1-bin.zip'
        Uri = 'https://archive.apache.org/dist/flex/4.16.1/binaries/apache-flex-sdk-4.16.1-bin.zip'
        Length = [int64]72396756
        Sha256 = '757aa19299c8a9c8af0901c1ae35f97fa94b7af0b0a9abc2bab04fe61d756e8b'
      }
      AdobeFlex = [pscustomobject]@{
        FileName = 'flex_sdk_4.6.0.23201B.zip'
        Uri = 'https://fpdownload.adobe.com/pub/flex/sdk/builds/flex4.6/flex_sdk_4.6.0.23201B.zip'
        Length = [int64]343973963
        Sha256 = '622b63f29de44600ff8d4231174a70fcb3085812c0e146a42e91877ca8b46798'
      }
    }
    Installed = [pscustomobject]@{
      JavaRelease = [pscustomobject]@{
        RelativePath = 'release'
        Length = [int64]1664
        Sha256 = '07117c72ce033949c14878e07fbf2fe23f59a1f8c90a6d1351b5c89099847ce7'
      }
      JavaExecutable = [pscustomobject]@{
        RelativePath = 'bin\java.exe'
        Length = [int64]50304
        Sha256 = '82051fdab26319d77d20cc0065045d05ec00b3e3d05f44935d7c06b96b621d55'
      }
      JpexsJar = [pscustomobject]@{
        RelativePath = 'ffdec.jar'
        Length = [int64]5075015
        Sha256 = '090ab695053ad94cba6408574c7d7eea20ec60b6ae789ee6056a23f45106762f'
      }
      FlexDescription = [pscustomobject]@{
        RelativePath = 'flex-sdk-description.xml'
        Length = [int64]994
        Sha256 = 'e8bfe5fc4195379edab4044b0495d6cf10cf1be19ebeb400690344981d1538dd'
      }
      FlexConfig = [pscustomobject]@{
        RelativePath = 'frameworks\flex-config.xml'
        Length = [int64]19529
        Sha256 = '08cc21404b146d3f623f4176a8e19734d35e81ea852d802283748708511d4fca'
      }
      MxmlcJar = [pscustomobject]@{
        RelativePath = 'lib\mxmlc.jar'
        Length = [int64]2107651
        Sha256 = 'cc07d749e376715e650271a9875289e49d94234902fff5e5fae287c478c8557b'
      }
      CompcJar = [pscustomobject]@{
        RelativePath = 'lib\compc.jar'
        Length = [int64]5066
        Sha256 = '843b4f9728d168abf3342585b47959d6120fa89718368e5d9acf636b2e7c6946'
      }
      PlayerGlobal = [pscustomobject]@{
        RelativePath = 'frameworks\libs\player\11.1\playerglobal.swc'
        Length = [int64]337288
        Sha256 = '2bbd5ffff3bb20c117db7206080079479b04c4b55d68dd21ab31b6566c99fb6b'
      }
    }
  }
}

function Test-PipelineSamePath {
  param(
    [Parameter(Mandatory = $true)][string]$Left,
    [Parameter(Mandatory = $true)][string]$Right
  )

  $resolvedLeft = [System.IO.Path]::GetFullPath($Left).TrimEnd('\', '/')
  $resolvedRight = [System.IO.Path]::GetFullPath($Right).TrimEnd('\', '/')
  return [string]::Equals($resolvedLeft, $resolvedRight, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PipelinePathWithinRoot {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root
  )

  $resolvedPath = [System.IO.Path]::GetFullPath($Path)
  $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
  $prefix = $resolvedRoot + [System.IO.Path]::DirectorySeparatorChar
  return $resolvedPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-PipelinePathWithinRoot {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $resolvedPath = [System.IO.Path]::GetFullPath($Path)
  $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
  if (!(Test-PipelinePathWithinRoot -Path $resolvedPath -Root $resolvedRoot)) {
    throw "$Description must remain within '$resolvedRoot': $resolvedPath"
  }
  return $resolvedPath
}

function Assert-PipelineNoReparseTraversal {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $resolvedPath = [System.IO.Path]::GetFullPath($Path)
  $pathRoot = [System.IO.Path]::GetPathRoot($resolvedPath)
  if (Test-PipelineSamePath -Left $resolvedPath -Right $pathRoot) {
    throw "$Description cannot be a filesystem root: $resolvedPath"
  }

  $cursor = $resolvedPath
  while (![string]::IsNullOrWhiteSpace($cursor)) {
    if (Test-Path -LiteralPath $cursor) {
      $item = Get-Item -LiteralPath $cursor -Force
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description traverses a reparse point: $cursor"
      }
    }
    if (Test-PipelineSamePath -Left $cursor -Right $pathRoot) { break }
    $cursor = [System.IO.Path]::GetDirectoryName($cursor)
  }
  return $resolvedPath
}

function Assert-PipelineOrdinaryTree {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $resolvedPath = Assert-PipelineNoReparseTraversal -Path $Path -Description $Description
  if (!(Test-Path -LiteralPath $resolvedPath -PathType Container)) {
    throw "$Description is not an ordinary directory: $resolvedPath"
  }
  $reparseItems = @(Get-ChildItem -LiteralPath $resolvedPath -Recurse -Force -ErrorAction Stop | Where-Object {
    ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
  })
  if ($reparseItems.Count -ne 0) {
    throw "$Description contains a reparse point: $($reparseItems[0].FullName)"
  }
  return $resolvedPath
}

function Test-PipelineFileContract {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$FileContract
  )

  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $file = Get-Item -LiteralPath $Path -Force
  if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
  if ($file.Length -ne [int64]$FileContract.Length) { return $false }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ceq ([string]$FileContract.Sha256).ToLowerInvariant()
}

function Assert-PipelineFileContract {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$FileContract,
    [Parameter(Mandatory = $true)][string]$Description
  )

  if (!(Test-PipelineFileContract -Path $Path -FileContract $FileContract)) {
    throw "$Description failed its pinned byte-length or SHA-256 contract: $Path"
  }
  return [System.IO.Path]::GetFullPath($Path)
}

function Test-PipelineJavaInstallation {
  param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$Contract)
  return (
    (Test-PipelineFileContract -Path (Join-Path $Root $Contract.Installed.JavaRelease.RelativePath) -FileContract $Contract.Installed.JavaRelease) -and
    (Test-PipelineFileContract -Path (Join-Path $Root $Contract.Installed.JavaExecutable.RelativePath) -FileContract $Contract.Installed.JavaExecutable)
  )
}

function Test-PipelineJpexsInstallation {
  param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$Contract)
  return Test-PipelineFileContract -Path (Join-Path $Root $Contract.Installed.JpexsJar.RelativePath) -FileContract $Contract.Installed.JpexsJar
}

function Test-PipelineFlexInstallation {
  param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$Contract)
  return (
    (Test-PipelineFileContract -Path (Join-Path $Root $Contract.Installed.FlexDescription.RelativePath) -FileContract $Contract.Installed.FlexDescription) -and
    (Test-PipelineFileContract -Path (Join-Path $Root $Contract.Installed.FlexConfig.RelativePath) -FileContract $Contract.Installed.FlexConfig) -and
    (Test-PipelineFileContract -Path (Join-Path $Root $Contract.Installed.MxmlcJar.RelativePath) -FileContract $Contract.Installed.MxmlcJar) -and
    (Test-PipelineFileContract -Path (Join-Path $Root $Contract.Installed.CompcJar.RelativePath) -FileContract $Contract.Installed.CompcJar)
  )
}

function Test-PipelinePlayerGlobalInstallation {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Contract)

  if (!(Test-PipelineFileContract -Path $Path -FileContract $Contract.Installed.PlayerGlobal)) { return $false }
  try {
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
      $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
      return $entries.Count -eq 2 -and $entries -contains 'catalog.xml' -and $entries -contains 'library.swf'
    }
    finally {
      $archive.Dispose()
    }
  }
  catch {
    return $false
  }
}

function Test-PipelinePlayerGlobalSet {
  param([Parameter(Mandatory = $true)][string]$FlexRoot, [Parameter(Mandatory = $true)]$Contract)

  $frameworksRoot = Join-Path $FlexRoot 'frameworks'
  if (!(Test-Path -LiteralPath $frameworksRoot -PathType Container)) { return $false }
  $expectedPath = Join-Path $FlexRoot $Contract.Installed.PlayerGlobal.RelativePath
  $playerGlobalMatches = @(Get-ChildItem -LiteralPath $frameworksRoot -Filter 'playerglobal.swc' -Recurse -File -ErrorAction SilentlyContinue)
  return (
    $playerGlobalMatches.Count -eq 1 -and
    (Test-PipelineSamePath -Left $playerGlobalMatches[0].FullName -Right $expectedPath) -and
    (Test-PipelinePlayerGlobalInstallation -Path $expectedPath -Contract $Contract)
  )
}

function Invoke-PipelineTreeRemoval {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$AllowedRoot
  )

  $resolvedPath = Assert-PipelinePathWithinRoot -Path $Path -Root $AllowedRoot -Description 'Removal path'
  if (!(Test-Path -LiteralPath $resolvedPath)) { return }
  [void](Assert-PipelineOrdinaryTree -Path $resolvedPath -Description 'Removal path')
  Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

function Expand-PipelinePinnedArchive {
  param(
    [Parameter(Mandatory = $true)][string]$ArchivePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][string]$AllowedRoot
  )

  $resolvedDestination = Assert-PipelinePathWithinRoot -Path $DestinationPath -Root $AllowedRoot -Description 'Archive extraction destination'
  if (Test-Path -LiteralPath $resolvedDestination) {
    throw "Archive extraction destination already exists: $resolvedDestination"
  }
  New-Item -ItemType Directory -Path $resolvedDestination | Out-Null

  try {
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $archive = [System.IO.Compression.ZipFile]::OpenRead([System.IO.Path]::GetFullPath($ArchivePath))
    try {
      foreach ($entry in $archive.Entries) {
        $entryName = $entry.FullName.Replace('\', '/')
        $trimmedEntryName = $entryName.TrimEnd('/')
        $segments = @($trimmedEntryName.Split('/', [System.StringSplitOptions]::None))
        $unixKind = (($entry.ExternalAttributes -shr 16) -band 0xF000)
        $windowsReparse = ($entry.ExternalAttributes -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0
        if ([string]::IsNullOrWhiteSpace($trimmedEntryName) -or
            [System.IO.Path]::IsPathFullyQualified($entryName) -or
            $entryName.StartsWith('/') -or
            $segments -contains '.' -or $segments -contains '..' -or $segments -contains '' -or
            $unixKind -eq 0xA000 -or $windowsReparse) {
          throw "Pinned archive contains an unsafe path or link entry: $entryName"
        }
        foreach ($segment in $segments) {
          if ($segment.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            throw "Pinned archive contains an invalid path entry: $entryName"
          }
        }

        $targetPath = Assert-PipelinePathWithinRoot -Path (Join-Path $resolvedDestination $trimmedEntryName) -Root $resolvedDestination -Description 'Archive entry'
        if (!$seenPaths.Add($targetPath)) {
          throw "Pinned archive contains a duplicate output path: $entryName"
        }
        if ($entryName.EndsWith('/') -or [string]::IsNullOrEmpty($entry.Name)) {
          New-Item -ItemType Directory -Force -Path $targetPath | Out-Null
          continue
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $false)
      }
    }
    finally {
      $archive.Dispose()
    }
    [void](Assert-PipelineOrdinaryTree -Path $resolvedDestination -Description 'Extracted archive')
  }
  catch {
    if (Test-Path -LiteralPath $resolvedDestination -PathType Container) {
      Invoke-PipelineTreeRemoval -Path $resolvedDestination -AllowedRoot $AllowedRoot
    }
    throw
  }
  return $resolvedDestination
}

function Copy-PipelineZipEntry {
  param(
    [Parameter(Mandatory = $true)][string]$ArchivePath,
    [Parameter(Mandatory = $true)][string]$EntryName,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][string]$AllowedRoot
  )

  $resolvedDestination = Assert-PipelinePathWithinRoot -Path $DestinationPath -Root $AllowedRoot -Description 'ZIP entry destination'
  if (Test-Path -LiteralPath $resolvedDestination) { throw "ZIP entry destination already exists: $resolvedDestination" }
  $archive = [System.IO.Compression.ZipFile]::OpenRead([System.IO.Path]::GetFullPath($ArchivePath))
  try {
    $entryMatches = @($archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -ceq $EntryName.Replace('\', '/') })
    if ($entryMatches.Count -ne 1) {
      throw "Pinned archive must contain exactly one '$EntryName' entry; found $($entryMatches.Count)."
    }
    $unixKind = (($entryMatches[0].ExternalAttributes -shr 16) -band 0xF000)
    $windowsReparse = ($entryMatches[0].ExternalAttributes -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0
    if ($unixKind -eq 0xA000 -or $windowsReparse) {
      throw "Pinned archive entry '$EntryName' is a link or reparse point."
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedDestination) | Out-Null
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entryMatches[0], $resolvedDestination, $false)
  }
  finally {
    $archive.Dispose()
  }
  return $resolvedDestination
}

function Copy-PipelineArtifactToPrivateStaging {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][string]$AllowedRoot,
    [Parameter(Mandatory = $true)]$Artifact
  )

  $source = [System.IO.Path]::GetFullPath($SourcePath)
  $destination = Assert-PipelinePathWithinRoot -Path $DestinationPath -Root $AllowedRoot -Description 'Private artifact destination'
  if (Test-Path -LiteralPath $destination) { throw "Private artifact destination already exists: $destination" }
  $destinationDirectory = Split-Path -Parent $destination
  New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
  [void](Assert-PipelineNoReparseTraversal -Path $destinationDirectory -Description 'Private artifact directory')

  try {
    $inputStream = [System.IO.File]::Open($source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
      $outputStream = [System.IO.File]::Open($destination, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
      try {
        $inputStream.CopyTo($outputStream)
        $outputStream.Flush($true)
      }
      finally {
        $outputStream.Dispose()
      }
    }
    finally {
      $inputStream.Dispose()
    }
    [void](Assert-PipelineFileContract -Path $destination -FileContract $Artifact -Description "Private copy of pinned artifact '$($Artifact.FileName)'")
  }
  catch {
    if (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination -Force }
    throw
  }
  return $destination
}

function Resolve-PipelineArtifact {
  param(
    [Parameter(Mandatory = $true)]$Artifact,
    [string]$ArtifactCachePath,
    [Parameter(Mandatory = $true)][string]$LocalCachePath,
    [Parameter(Mandatory = $true)][string]$DownloadPath,
    [Parameter(Mandatory = $true)][string]$PrivateArtifactPath,
    [Parameter(Mandatory = $true)][string]$PrivateArtifactRoot,
    [switch]$Offline,
    [scriptblock]$DownloadAction,
    [scriptblock]$AfterArtifactSelectedAction
  )

  $cacheDirectories = [System.Collections.Generic.List[string]]::new()
  if (![string]::IsNullOrWhiteSpace($ArtifactCachePath)) {
    $cacheDirectories.Add([System.IO.Path]::GetFullPath($ArtifactCachePath))
  }
  $resolvedLocalCache = [System.IO.Path]::GetFullPath($LocalCachePath)
  if (!($cacheDirectories | Where-Object { Test-PipelineSamePath -Left $_ -Right $resolvedLocalCache })) {
    $cacheDirectories.Add($resolvedLocalCache)
  }

  $selectedPath = $null
  foreach ($cacheDirectory in $cacheDirectories) {
    $candidate = Join-Path $cacheDirectory $Artifact.FileName
    if (Test-Path -LiteralPath $candidate) {
      [void](Assert-PipelineFileContract -Path $candidate -FileContract $Artifact -Description "Pinned artifact '$($Artifact.FileName)'")
      Write-Information "Using pinned cached artifact: $candidate" -InformationAction Continue
      $selectedPath = [System.IO.Path]::GetFullPath($candidate)
      break
    }
  }

  if ($null -eq $selectedPath -and $Offline) {
    $searched = [string]::Join("', '", @($cacheDirectories | ForEach-Object { Join-Path $_ $Artifact.FileName }))
    throw "Pinned artifact '$($Artifact.FileName)' was not found at '$searched'. Offline mode prevents download."
  }

  if ($null -eq $selectedPath) {
    New-Item -ItemType Directory -Force -Path $resolvedLocalCache, $DownloadPath | Out-Null
    $temporaryPath = Join-Path $DownloadPath ($Artifact.FileName + '.' + [guid]::NewGuid().ToString('N') + '.download')
    try {
      Write-Information "Downloading pinned artifact: $($Artifact.Uri)" -InformationAction Continue
      if ($null -ne $DownloadAction) {
        & $DownloadAction $Artifact.Uri $temporaryPath
      }
      else {
        Invoke-WebRequest -Uri $Artifact.Uri -OutFile $temporaryPath -UseBasicParsing
      }
      [void](Assert-PipelineFileContract -Path $temporaryPath -FileContract $Artifact -Description "Downloaded artifact '$($Artifact.FileName)'")
      $cachePath = Join-Path $resolvedLocalCache $Artifact.FileName
      if (Test-Path -LiteralPath $cachePath) {
        [void](Assert-PipelineFileContract -Path $cachePath -FileContract $Artifact -Description "Pinned local cache artifact '$($Artifact.FileName)'")
      }
      else {
        Move-Item -LiteralPath $temporaryPath -Destination $cachePath
        [void](Assert-PipelineFileContract -Path $cachePath -FileContract $Artifact -Description "Pinned local cache artifact '$($Artifact.FileName)'")
      }
      $selectedPath = [System.IO.Path]::GetFullPath($cachePath)
    }
    finally {
      if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
  }

  if ($null -ne $AfterArtifactSelectedAction) {
    & $AfterArtifactSelectedAction $selectedPath $Artifact
  }
  return Copy-PipelineArtifactToPrivateStaging -SourcePath $selectedPath -DestinationPath $PrivateArtifactPath `
    -AllowedRoot $PrivateArtifactRoot -Artifact $Artifact
}

function Publish-PipelineToolDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$CandidatePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][string]$CandidateRoot,
    [Parameter(Mandatory = $true)][string]$ToolRoot,
    [Parameter(Mandatory = $true)][scriptblock]$Validator,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $candidate = Assert-PipelinePathWithinRoot -Path $CandidatePath -Root $CandidateRoot -Description "$Description candidate"
  $destination = Assert-PipelinePathWithinRoot -Path $DestinationPath -Root $ToolRoot -Description "$Description destination"
  [void](Assert-PipelineOrdinaryTree -Path $candidate -Description "$Description candidate")
  if (!(& $Validator $candidate)) { throw "$Description candidate failed validation before installation: $candidate" }
  if (Test-Path -LiteralPath $destination) { [void](Assert-PipelineOrdinaryTree -Path $destination -Description "$Description existing installation") }

  $backup = $destination + '.backup-' + [guid]::NewGuid().ToString('N')
  [void](Assert-PipelinePathWithinRoot -Path $backup -Root $ToolRoot -Description "$Description backup")
  $hadDestination = Test-Path -LiteralPath $destination -PathType Container
  if ($hadDestination) { Move-Item -LiteralPath $destination -Destination $backup }

  try {
    Move-Item -LiteralPath $candidate -Destination $destination
    if (!(& $Validator $destination)) { throw "$Description failed validation after installation." }
  }
  catch {
    $cause = $_.Exception.Message
    $rollbackFailure = $null
    try {
      if (Test-Path -LiteralPath $destination -PathType Container) {
        Move-Item -LiteralPath $destination -Destination $candidate
      }
      if ($hadDestination -and (Test-Path -LiteralPath $backup -PathType Container)) {
        Move-Item -LiteralPath $backup -Destination $destination
      }
    }
    catch {
      $rollbackFailure = $_.Exception.Message
    }
    if ($null -ne $rollbackFailure) {
      throw "$Description installation failed and rollback was incomplete. Retained backup: $backup. Cause: $cause. Rollback: $rollbackFailure"
    }
    throw "$Description installation failed; the previous installation was restored. Cause: $cause"
  }

  if (Test-Path -LiteralPath $backup -PathType Container) { Invoke-PipelineTreeRemoval -Path $backup -AllowedRoot $ToolRoot }
}

function Publish-PipelineToolFile {
  param(
    [Parameter(Mandatory = $true)][string]$CandidatePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][string]$CandidateRoot,
    [Parameter(Mandatory = $true)][string]$ToolRoot,
    [Parameter(Mandatory = $true)][scriptblock]$Validator,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $candidate = Assert-PipelinePathWithinRoot -Path $CandidatePath -Root $CandidateRoot -Description "$Description candidate"
  $destination = Assert-PipelinePathWithinRoot -Path $DestinationPath -Root $ToolRoot -Description "$Description destination"
  if (!(& $Validator $candidate)) { throw "$Description candidate failed validation before installation: $candidate" }
  if ((Test-Path -LiteralPath $destination) -and !(Test-Path -LiteralPath $destination -PathType Leaf)) {
    throw "$Description destination exists but is not an ordinary file: $destination"
  }
  if (Test-Path -LiteralPath $destination -PathType Leaf) {
    $destinationItem = Get-Item -LiteralPath $destination -Force
    if (($destinationItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "$Description destination is a reparse point: $destination"
    }
  }
  $destinationDirectory = Split-Path -Parent $destination
  New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
  [void](Assert-PipelineNoReparseTraversal -Path $destinationDirectory -Description "$Description destination directory")

  $backup = $destination + '.backup-' + [guid]::NewGuid().ToString('N')
  [void](Assert-PipelinePathWithinRoot -Path $backup -Root $ToolRoot -Description "$Description backup")
  $hadDestination = Test-Path -LiteralPath $destination -PathType Leaf
  if ($hadDestination) { Move-Item -LiteralPath $destination -Destination $backup }
  try {
    Move-Item -LiteralPath $candidate -Destination $destination
    if (!(& $Validator $destination)) { throw "$Description failed validation after installation." }
  }
  catch {
    $cause = $_.Exception.Message
    $rollbackFailure = $null
    try {
      if (Test-Path -LiteralPath $destination -PathType Leaf) { Move-Item -LiteralPath $destination -Destination $candidate }
      if ($hadDestination -and (Test-Path -LiteralPath $backup -PathType Leaf)) { Move-Item -LiteralPath $backup -Destination $destination }
    }
    catch {
      $rollbackFailure = $_.Exception.Message
    }
    if ($null -ne $rollbackFailure) {
      throw "$Description installation failed and rollback was incomplete. Retained backup: $backup. Cause: $cause. Rollback: $rollbackFailure"
    }
    throw "$Description installation failed; the previous file was restored. Cause: $cause"
  }
  if (Test-Path -LiteralPath $backup -PathType Leaf) { Remove-Item -LiteralPath $backup -Force }
}

function Invoke-PipelineToolingInstall {
  param(
    [Parameter(Mandatory = $true)]$Contract,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$ToolRoot,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [string]$ArtifactCachePath,
    [switch]$Offline,
    [switch]$AcceptAdobeLicense,
    [scriptblock]$DownloadAction,
    [scriptblock]$AfterArtifactSelectedAction
  )

  [void](Assert-PipelineNoReparseTraversal -Path $RepositoryRoot -Description 'Repository root')
  $resolvedToolRoot = Assert-PipelineNoReparseTraversal -Path $ToolRoot -Description 'Pipeline tool root'
  $resolvedWorkspaceRoot = Assert-PipelineNoReparseTraversal -Path $WorkspaceRoot -Description 'Pipeline workspace root'
  if ((Test-PipelinePathWithinRoot -Path $resolvedToolRoot -Root $resolvedWorkspaceRoot) -or
      (Test-PipelinePathWithinRoot -Path $resolvedWorkspaceRoot -Root $resolvedToolRoot) -or
      (Test-PipelineSamePath -Left $resolvedToolRoot -Right $resolvedWorkspaceRoot)) {
    throw 'Pipeline tool and workspace roots must be separate, non-overlapping directories.'
  }
  New-Item -ItemType Directory -Force -Path $resolvedToolRoot, $resolvedWorkspaceRoot | Out-Null
  [void](Assert-PipelineOrdinaryTree -Path $resolvedToolRoot -Description 'Pipeline tool root')
  [void](Assert-PipelineOrdinaryTree -Path $resolvedWorkspaceRoot -Description 'Pipeline workspace root')

  $javaRoot = Join-Path $resolvedToolRoot 'java'
  $jpexsRoot = Join-Path $resolvedToolRoot 'jpexs'
  $flexRoot = Join-Path $resolvedToolRoot 'flex'
  foreach ($existingRoot in @($javaRoot, $jpexsRoot, $flexRoot)) {
    if (Test-Path -LiteralPath $existingRoot) { [void](Assert-PipelineOrdinaryTree -Path $existingRoot -Description 'Existing pipeline tool installation') }
  }
  $playerGlobalPath = Join-Path $flexRoot $Contract.Installed.PlayerGlobal.RelativePath
  $needJava = !(Test-PipelineJavaInstallation -Root $javaRoot -Contract $Contract)
  $needJpexs = !(Test-PipelineJpexsInstallation -Root $jpexsRoot -Contract $Contract)
  $baseFlexValid = Test-PipelineFlexInstallation -Root $flexRoot -Contract $Contract
  $hasReusablePlayerGlobal = Test-PipelinePlayerGlobalInstallation -Path $playerGlobalPath -Contract $Contract
  $playerGlobalMatches = @()
  if (Test-Path -LiteralPath (Join-Path $flexRoot 'frameworks') -PathType Container) {
    $playerGlobalMatches = @(Get-ChildItem -LiteralPath (Join-Path $flexRoot 'frameworks') -Filter 'playerglobal.swc' -Recurse -File -ErrorAction SilentlyContinue)
  }
  $hasUnexpectedPlayerGlobal = $playerGlobalMatches.Count -gt 0 -and
    !(Test-PipelinePlayerGlobalSet -FlexRoot $flexRoot -Contract $Contract)
  $needFlex = !$baseFlexValid -or $hasUnexpectedPlayerGlobal
  $needPlayerGlobal = !$hasReusablePlayerGlobal

  if ($needPlayerGlobal -and !$AcceptAdobeLicense) {
    throw "Installing Flash Player $($Contract.Versions.PlayerGlobal) playerglobal.swc requires Adobe Flex SDK license acceptance. Review the license, then rerun with -AcceptAdobeLicense."
  }

  $localCache = Join-Path $resolvedWorkspaceRoot 'cache'
  $downloadRoot = Join-Path $resolvedWorkspaceRoot 'downloads'
  $stagingParent = Join-Path $resolvedWorkspaceRoot 'staging'
  New-Item -ItemType Directory -Force -Path $localCache, $downloadRoot, $stagingParent | Out-Null
  $stagingRoot = Join-Path $stagingParent ([guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $stagingRoot | Out-Null

  try {
    $resolvedArtifacts = @{}
    $privateArtifactRoot = Join-Path $stagingRoot 'artifacts'
    foreach ($artifactName in @(
      $(if ($needJava) { 'Java' }),
      $(if ($needJpexs) { 'Jpexs' }),
      $(if ($needFlex) { 'ApacheFlex' }),
      $(if ($needPlayerGlobal) { 'AdobeFlex' })
    ) | Where-Object { $_ }) {
      $resolvedArtifacts[$artifactName] = Resolve-PipelineArtifact -Artifact $Contract.Artifacts[$artifactName] `
        -ArtifactCachePath $ArtifactCachePath -LocalCachePath $localCache -DownloadPath $downloadRoot `
        -PrivateArtifactPath (Join-Path $privateArtifactRoot $Contract.Artifacts[$artifactName].FileName) `
        -PrivateArtifactRoot $stagingRoot -Offline:$Offline -DownloadAction $DownloadAction `
        -AfterArtifactSelectedAction $AfterArtifactSelectedAction
    }

    $javaCandidate = $null
    if ($needJava) {
      $javaExtract = Expand-PipelinePinnedArchive -ArchivePath $resolvedArtifacts.Java -DestinationPath (Join-Path $stagingRoot 'java-archive') -AllowedRoot $stagingRoot
      $topDirectories = @(Get-ChildItem -LiteralPath $javaExtract -Directory -Force)
      $topFiles = @(Get-ChildItem -LiteralPath $javaExtract -File -Force)
      if ($topDirectories.Count -ne 1 -or $topFiles.Count -ne 0) {
        throw "Pinned Temurin archive must contain exactly one top-level directory; found $($topDirectories.Count) directories and $($topFiles.Count) files."
      }
      $javaCandidate = $topDirectories[0].FullName
      if (!(Test-PipelineJavaInstallation -Root $javaCandidate -Contract $Contract)) {
        throw "Pinned Temurin $($Contract.Versions.Java) archive did not produce the expected Windows x64 HotSpot JDK."
      }
    }

    $jpexsCandidate = $null
    if ($needJpexs) {
      $jpexsCandidate = Expand-PipelinePinnedArchive -ArchivePath $resolvedArtifacts.Jpexs -DestinationPath (Join-Path $stagingRoot 'jpexs') -AllowedRoot $stagingRoot
      if (!(Test-PipelineJpexsInstallation -Root $jpexsCandidate -Contract $Contract)) {
        throw "Pinned JPEXS $($Contract.Versions.Jpexs) archive did not produce the expected installation."
      }
    }

    $flexCandidate = $null
    if ($needFlex) {
      $flexCandidate = Expand-PipelinePinnedArchive -ArchivePath $resolvedArtifacts.ApacheFlex -DestinationPath (Join-Path $stagingRoot 'flex') -AllowedRoot $stagingRoot
      if (!(Test-PipelineFlexInstallation -Root $flexCandidate -Contract $Contract)) {
        throw "Pinned Apache Flex $($Contract.Versions.ApacheFlex) archive did not produce the expected installation."
      }
      $candidatePlayerGlobal = Join-Path $flexCandidate $Contract.Installed.PlayerGlobal.RelativePath
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $candidatePlayerGlobal) | Out-Null
      if ($hasReusablePlayerGlobal) {
        Copy-Item -LiteralPath $playerGlobalPath -Destination $candidatePlayerGlobal
      }
      else {
        [void](Copy-PipelineZipEntry -ArchivePath $resolvedArtifacts.AdobeFlex `
          -EntryName 'frameworks/libs/player/11.1/playerglobal.swc' -DestinationPath $candidatePlayerGlobal -AllowedRoot $stagingRoot)
      }
      if (!(Test-PipelinePlayerGlobalInstallation -Path $candidatePlayerGlobal -Contract $Contract)) {
        throw "Pinned Adobe Flex $($Contract.Versions.AdobeFlex) did not provide the expected Player $($Contract.Versions.PlayerGlobal) compiler library."
      }
    }

    $playerGlobalCandidate = $null
    if (!$needFlex -and $needPlayerGlobal) {
      $playerGlobalCandidate = Join-Path $stagingRoot 'playerglobal.swc'
      [void](Copy-PipelineZipEntry -ArchivePath $resolvedArtifacts.AdobeFlex `
        -EntryName 'frameworks/libs/player/11.1/playerglobal.swc' -DestinationPath $playerGlobalCandidate -AllowedRoot $stagingRoot)
      if (!(Test-PipelinePlayerGlobalInstallation -Path $playerGlobalCandidate -Contract $Contract)) {
        throw "Pinned Adobe Flex $($Contract.Versions.AdobeFlex) did not provide the expected Player $($Contract.Versions.PlayerGlobal) compiler library."
      }
    }

    if ($needJava) {
      Publish-PipelineToolDirectory -CandidatePath $javaCandidate -DestinationPath $javaRoot -CandidateRoot $stagingRoot -ToolRoot $resolvedToolRoot `
        -Description "Eclipse Temurin $($Contract.Versions.Java) Windows x64 HotSpot JDK" `
        -Validator { param($path) Test-PipelineJavaInstallation -Root $path -Contract $Contract }
      Write-Information "Installed pinned Eclipse Temurin $($Contract.Versions.Java) Windows x64 HotSpot JDK." -InformationAction Continue
    }
    else { Write-Information "Pinned Eclipse Temurin $($Contract.Versions.Java) installation is already valid." -InformationAction Continue }

    if ($needJpexs) {
      Publish-PipelineToolDirectory -CandidatePath $jpexsCandidate -DestinationPath $jpexsRoot -CandidateRoot $stagingRoot -ToolRoot $resolvedToolRoot `
        -Description "JPEXS $($Contract.Versions.Jpexs)" `
        -Validator { param($path) Test-PipelineJpexsInstallation -Root $path -Contract $Contract }
      Write-Information "Installed pinned JPEXS $($Contract.Versions.Jpexs)." -InformationAction Continue
    }
    else { Write-Information "Pinned JPEXS $($Contract.Versions.Jpexs) installation is already valid." -InformationAction Continue }

    if ($needFlex) {
      Publish-PipelineToolDirectory -CandidatePath $flexCandidate -DestinationPath $flexRoot -CandidateRoot $stagingRoot -ToolRoot $resolvedToolRoot `
        -Description "Apache Flex $($Contract.Versions.ApacheFlex)" `
        -Validator {
          param($path)
          (Test-PipelineFlexInstallation -Root $path -Contract $Contract) -and
            (Test-PipelinePlayerGlobalInstallation -Path (Join-Path $path $Contract.Installed.PlayerGlobal.RelativePath) -Contract $Contract)
        }
      Write-Information "Installed pinned Apache Flex $($Contract.Versions.ApacheFlex) with Player $($Contract.Versions.PlayerGlobal) compiler library." -InformationAction Continue
    }
    else {
      Write-Information "Pinned Apache Flex $($Contract.Versions.ApacheFlex) installation is already valid." -InformationAction Continue
      if ($needPlayerGlobal) {
        Publish-PipelineToolFile -CandidatePath $playerGlobalCandidate -DestinationPath $playerGlobalPath -CandidateRoot $stagingRoot -ToolRoot $resolvedToolRoot `
          -Description "Player $($Contract.Versions.PlayerGlobal) compiler library" `
          -Validator { param($path) Test-PipelinePlayerGlobalInstallation -Path $path -Contract $Contract }
        Write-Information "Installed pinned Player $($Contract.Versions.PlayerGlobal) compiler library." -InformationAction Continue
      }
      else { Write-Information "Pinned Player $($Contract.Versions.PlayerGlobal) compiler library is already valid." -InformationAction Continue }
    }

    if (!(Test-PipelineJavaInstallation -Root $javaRoot -Contract $Contract) -or
        !(Test-PipelineJpexsInstallation -Root $jpexsRoot -Contract $Contract) -or
        !(Test-PipelineFlexInstallation -Root $flexRoot -Contract $Contract) -or
        !(Test-PipelinePlayerGlobalSet -FlexRoot $flexRoot -Contract $Contract)) {
      throw 'Pipeline tooling failed final installed-file verification.'
    }
    Write-Information 'Pinned pipeline tooling files are installed.' -InformationAction Continue
  }
  finally {
    if (Test-Path -LiteralPath $stagingRoot -PathType Container) { Invoke-PipelineTreeRemoval -Path $stagingRoot -AllowedRoot $stagingParent }
  }
}
