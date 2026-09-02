[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VwHudRepositoryPath,

  [string]$Archive2Path,

  [string]$MoviesDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\movies'),

  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\packages'),

  [string]$LooseOutputDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\loose'),

  [string]$ArchiveRootsDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\archive-roots')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$consumerDiscoveryWorkRoot = Join-Path $repositoryRoot '.work\consumer-discovery'
$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot
$resolvedVwHudRoot = Assert-VwHudV2Fixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
$hostMovieEvidence = @(Get-VwHudHostMovieEvidence -VwHudRepositoryPath $resolvedVwHudRoot -Matrix $matrix)

if ([string]::IsNullOrWhiteSpace($Archive2Path)) {
  if ([string]::IsNullOrWhiteSpace($env:TOOL_PATH_ARCHIVER)) {
    throw 'Archive2Path or TOOL_PATH_ARCHIVER must identify the VWHUD v2-compatible Archive2 tool.'
  }
  $Archive2Path = Join-Path $env:TOOL_PATH_ARCHIVER 'Archive2.exe'
}
$resolvedArchive2Path = Resolve-ConsumerDiscoveryRequiredFile -Path $Archive2Path -Description 'Archive2 executable'
$resolvedMoviesDirectory = Resolve-ConsumerDiscoveryRequiredDirectory `
  -Path $MoviesDirectory `
  -Description 'Built consumer-discovery movie directory'
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$resolvedLooseOutputDirectory = [System.IO.Path]::GetFullPath($LooseOutputDirectory)
$resolvedArchiveRootsDirectory = [System.IO.Path]::GetFullPath($ArchiveRootsDirectory)

foreach ($generatedDirectory in @($resolvedOutputDirectory, $resolvedLooseOutputDirectory, $resolvedArchiveRootsDirectory)) {
  if (Test-Path -LiteralPath $generatedDirectory -PathType Container) {
    Assert-ConsumerDiscoveryRemovalPath -Path $generatedDirectory -AllowedRoot $consumerDiscoveryWorkRoot
    Remove-Item -LiteralPath $generatedDirectory -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
}

$pluginSourcePath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $repositoryRoot 'Staging\Venworks-Canvas.esm') `
  -Description 'Canvas probe plugin source'
Assert-ConsumerDiscoveryNotGitLfsPointer -Path $pluginSourcePath -Description 'Canvas probe plugin source'

$movieByKey = @{}
foreach ($movie in @($matrix.Movies)) {
  $movieByKey[[string]$movie.Key] = $movie
}
$slotByIndex = @{}
foreach ($slot in @($matrix.Slots)) {
  $slotByIndex[[int]$slot.Index] = $slot
}

$packageEvidence = [System.Collections.Generic.List[object]]::new()
foreach ($package in @($matrix.Packages)) {
  $packageKey = [string]$package.Key
  $packageBaseName = [string]$package.BaseName
  $movieDefinition = $movieByKey[[string]$package.MovieKey]
  if ($null -eq $movieDefinition) {
    throw "Package '$packageKey' references unknown movie '$($package.MovieKey)'."
  }
  $builtMoviePath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedMoviesDirectory ([string]$movieDefinition.Output)) `
    -Description "Built movie for package '$packageKey'"
  $archiveRoot = Join-Path $resolvedArchiveRootsDirectory $packageKey
  $packageOutput = Join-Path $resolvedOutputDirectory $packageKey
  $looseOutput = Join-Path $resolvedLooseOutputDirectory $packageKey
  New-Item -ItemType Directory -Force -Path $archiveRoot, $packageOutput, $looseOutput | Out-Null

  $expectedEntries = [System.Collections.Generic.List[string]]::new()
  if ([string]$package.Role -ceq 'Host') {
    foreach ($hostMovie in @($matrix.VwHudFixture.HostMovies)) {
      $sourcePath = Resolve-ConsumerDiscoveryRequiredFile `
        -Path (Join-Path $resolvedVwHudRoot ([string]$hostMovie.Source)) `
        -Description "Pinned VWHUD host movie '$($hostMovie.Source)'"
      $targetPath = Join-Path $archiveRoot ([string]$hostMovie.Target)
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null
      Copy-Item -LiteralPath $sourcePath -Destination $targetPath
      $expectedEntries.Add(([string]$hostMovie.Target).Replace('\', '/'))
    }
    $hostTargetPath = Join-Path $archiveRoot 'Interface\venworkscui.swf'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $hostTargetPath) | Out-Null
    Copy-Item -LiteralPath $builtMoviePath -Destination $hostTargetPath
    $expectedEntries.Add('Interface/venworkscui.swf')
  }
  elseif ([string]$package.Role -ceq 'Consumer') {
    $slot = $slotByIndex[[int]$package.Slot]
    if ($null -eq $slot) {
      throw "Package '$packageKey' references unknown slot '$($package.Slot)'."
    }
    foreach ($targetRelativePath in @([string]$slot.NormalPath, [string]$slot.LargePath)) {
      $targetPath = Join-Path $archiveRoot $targetRelativePath
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null
      Copy-Item -LiteralPath $builtMoviePath -Destination $targetPath
      $expectedEntries.Add($targetRelativePath.Replace('\', '/'))
    }
  }
  else {
    throw "Package '$packageKey' has unsupported role '$($package.Role)'."
  }

  $pluginPath = Join-Path $packageOutput "$packageBaseName.esm"
  Copy-Item -LiteralPath $pluginSourcePath -Destination $pluginPath
  Copy-Item -LiteralPath (Join-Path $archiveRoot 'Interface') -Destination $looseOutput -Recurse
  Copy-Item -LiteralPath $pluginSourcePath -Destination (Join-Path $looseOutput "$packageBaseName.esm")
  $archives = [System.Collections.Generic.List[object]]::new()
  foreach ($archiveTarget in @('Main', 'Main_PS')) {
    $archivePath = Join-Path $packageOutput "$packageBaseName - $archiveTarget.ba2"
    $archiveArguments = @(
      "$archiveRoot\",
      "-root=$archiveRoot\",
      "-create=$archivePath",
      '-format=General',
      '-compression=None',
      '-maxSizeMB=2048',
      '-excludeFilters=.*\\meta\.ini|.*\\.*\.dds|.*\\.*\.btc|.*\\.*\.esp|.*\\.*\.esm|.*\\.*\.ba2'
    )
    & $resolvedArchive2Path @archiveArguments
    if ($LASTEXITCODE -ne 0) {
      throw "Archive2 failed for package '$packageKey' target '$archiveTarget' with exit code $LASTEXITCODE."
    }
    [void](Resolve-ConsumerDiscoveryRequiredFile `
      -Path $archivePath `
      -Description "Generated $packageKey $archiveTarget archive")
    $entries = @(Get-ConsumerDiscoveryGeneralBa2Entries -Path $archivePath)
    $actualNames = @($entries.Name | ForEach-Object { $_.Replace('\', '/').ToLowerInvariant() } | Sort-Object)
    $sortedExpectedEntries = @($expectedEntries | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
    if ($actualNames.Count -ne $sortedExpectedEntries.Count -or
        [string]::Join("`n", $actualNames) -cne [string]::Join("`n", $sortedExpectedEntries)) {
      throw "Package '$packageKey' $archiveTarget archive inventory does not match its explicit payload."
    }
    $compressedEntries = @($entries | Where-Object { [uint32]$_.PackedSize -ne 0 })
    if ($compressedEntries.Count -ne 0) {
      throw "Package '$packageKey' $archiveTarget archive contains compressed General entries."
    }
    $archives.Add([pscustomobject]@{
      Target = $archiveTarget
      File = [System.IO.Path]::GetFileName($archivePath)
      Sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToUpperInvariant()
      Entries = @($actualNames)
    })
  }

  $packageFiles = @(Get-ChildItem -LiteralPath $packageOutput -File | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{
      File = $_.Name
      Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    }
  })
  $looseFiles = @(Get-ChildItem -LiteralPath $looseOutput -Recurse -File | Sort-Object FullName | ForEach-Object {
    [pscustomobject]@{
      File = $_.FullName.Substring($looseOutput.Length + 1).Replace('\', '/')
      Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    }
  })
  $packageEvidence.Add([pscustomobject]@{
    Key = $packageKey
    BaseName = $packageBaseName
    MovieKey = [string]$package.MovieKey
    LooseFiles = $looseFiles
    PackageFiles = $packageFiles
    Archives = @($archives)
  })
  Write-Host -ForegroundColor Green "Created archive-only probe package '$packageKey' at $packageOutput"
}

$evidence = [ordered]@{
  Schema = 'VWCANVAS9_CONSUMER_DISCOVERY_PACKAGES/1'
  GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
  VwHudRevision = [string]$matrix.VwHudFixture.Revision
  VwHudHostMovies = $hostMovieEvidence
  PluginSourceSha256 = (Get-FileHash -LiteralPath $pluginSourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
  Packages = @($packageEvidence)
}
Write-ConsumerDiscoveryUtf8WithoutBom `
  -Path (Join-Path $resolvedOutputDirectory 'package-evidence.json') `
  -Text (($evidence | ConvertTo-Json -Depth 12) + "`n")

Write-Host -ForegroundColor Green "Created and inventoried $($packageEvidence.Count) loose and archive-only consumer-discovery probe packages."
