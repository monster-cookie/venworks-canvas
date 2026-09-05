<#
.SYNOPSIS
Creates local staging junctions for Canvas module variants.

.PARAMETER VariantKeys
One or more keys from `$Global:ModuleVariants. Omit this parameter to process
all module variants. `VariantKey` remains a compatibility alias.

.PARAMETER MigrateExisting
Safely migrates an existing real staging directory into its configured physical
module directory before replacing it with a verified junction.
#>
[CmdletBinding()]
param(
  [Alias("VariantKey")]
  [string[]]$VariantKeys,

  [switch]$MigrateExisting
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')
$loadedConfigurationRoot = Get-Variable -Name SharedConfigurationRepositoryRoot -Scope Global -ErrorAction SilentlyContinue
$environmentConfigurationLoaded = Get-Variable -Name SharedConfigurationEnvironmentLoaded -Scope Global -ErrorAction SilentlyContinue
if ($null -eq $loadedConfigurationRoot -or
    $null -eq $environmentConfigurationLoaded -or
    !$environmentConfigurationLoaded.Value -or
    ![string]::Equals(
      [System.IO.Path]::GetFullPath([string]$loadedConfigurationRoot.Value),
      $repositoryRoot,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
  Write-Host -ForegroundColor Green "Importing Shared Configuration"
  . "$PSScriptRoot\sharedConfig.ps1"
}

function Get-NormalizedFullPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "A filesystem path cannot be empty."
  }

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
  if ($fullPath.Length -gt $pathRoot.Length) {
    return $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  }
  return $fullPath
}

function Test-SamePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Left,

    [Parameter(Mandatory = $true)]
    [string]$Right
  )

  return [string]::Equals(
    (Get-NormalizedFullPath -Path $Left),
    (Get-NormalizedFullPath -Path $Right),
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

function Assert-RepositoryStagingPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $normalizedPath = Get-NormalizedFullPath -Path $Path
  $parentPath = Split-Path -Parent $normalizedPath
  if (!(Test-SamePath -Left $parentPath -Right $repositoryRoot)) {
    throw "Staging path must be a direct child of the repository root: $normalizedPath"
  }
}

function Get-JunctionTargetPath {
  param(
    [Parameter(Mandatory = $true)]
    [System.IO.DirectoryInfo]$Item
  )

  $targets = @($Item.Target)
  if ($targets.Count -ne 1) {
    return $null
  }
  return Get-NormalizedFullPath -Path ([string]$targets[0])
}

function Assert-JunctionTarget {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StagingPath,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedTargetPath
  )

  $stagingItem = Get-Item -LiteralPath $StagingPath -Force
  if ($stagingItem.LinkType -ne "Junction") {
    throw "Staging path is not a Junction: $StagingPath"
  }

  $actualTargetPath = Get-JunctionTargetPath -Item $stagingItem
  if ($null -eq $actualTargetPath -or !(Test-SamePath -Left $actualTargetPath -Right $ExpectedTargetPath)) {
    throw "Staging Junction does not target its configured physical module folder: $StagingPath"
  }
}

function Get-DirectoryManifest {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $rootPath = Get-NormalizedFullPath -Path $Path
  $entries = foreach ($item in Get-ChildItem -LiteralPath $rootPath -Force -Recurse) {
    $relativePath = [System.IO.Path]::GetRelativePath($rootPath, $item.FullName)
    if ($item.PSIsContainer) {
      [pscustomobject]@{
        Kind = "Directory"
        RelativePath = $relativePath
        Length = 0L
        Sha256 = ""
      }
    }
    else {
      [pscustomobject]@{
        Kind = "File"
        RelativePath = $relativePath
        Length = [long]$item.Length
        Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
      }
    }
  }

  return @($entries | Sort-Object Kind, RelativePath)
}

function Assert-DirectoryContentsMatch {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedPath,

    [Parameter(Mandatory = $true)]
    [string]$ActualPath
  )

  $expectedManifest = @(Get-DirectoryManifest -Path $ExpectedPath)
  $actualManifest = @(Get-DirectoryManifest -Path $ActualPath)
  if ($expectedManifest.Count -ne $actualManifest.Count) {
    throw "Directory inventories differ between '$ExpectedPath' and '$ActualPath'."
  }

  for ($index = 0; $index -lt $expectedManifest.Count; $index++) {
    $expectedEntry = $expectedManifest[$index]
    $actualEntry = $actualManifest[$index]
    if ($expectedEntry.Kind -cne $actualEntry.Kind -or
        $expectedEntry.RelativePath -cne $actualEntry.RelativePath -or
        $expectedEntry.Length -ne $actualEntry.Length -or
        $expectedEntry.Sha256 -cne $actualEntry.Sha256) {
      throw "Directory contents differ at '$($expectedEntry.RelativePath)' between '$ExpectedPath' and '$ActualPath'."
    }
  }
}

function Copy-DirectoryContents {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
  )

  foreach ($sourceItem in Get-ChildItem -LiteralPath $SourcePath -Force) {
    Copy-Item -LiteralPath $sourceItem.FullName -Destination $DestinationPath -Recurse -Force
  }
}

function Remove-VerifiedBackupDirectory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BackupPath,

    [Parameter(Mandatory = $true)]
    [string]$OriginalStagingPath
  )

  $normalizedBackupPath = Get-NormalizedFullPath -Path $BackupPath
  $expectedPrefix = "$(Get-NormalizedFullPath -Path $OriginalStagingPath).setupRepo-backup-"
  $backupParent = Split-Path -Parent $normalizedBackupPath
  if (!(Test-SamePath -Left $backupParent -Right $repositoryRoot) -or
      !$normalizedBackupPath.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove an unexpected backup path: $normalizedBackupPath"
  }

  Remove-Item -LiteralPath $normalizedBackupPath -Recurse -Force
}

$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$operations = @()
$configuredStagingPaths = @($Global:ModuleVariants | ForEach-Object {
  $configuredStagingPath = Get-NormalizedFullPath -Path $_.StagingFolderPath
  Assert-RepositoryStagingPath -Path $configuredStagingPath
  [pscustomobject]@{
    VariantName = $_.VariantName
    Path = $configuredStagingPath
  }
})
$configuredVariantTargets = @()
foreach ($configuredVariant in $Global:ModuleVariants) {
  if ([string]::IsNullOrWhiteSpace($configuredVariant.PluginModulePath)) {
    continue
  }

  $configuredTargetPath = Get-NormalizedFullPath -Path $configuredVariant.PluginModulePath
  $matchingTarget = @($configuredVariantTargets | Where-Object {
    Test-CanvasOverlappingPaths -Left $_.Path -Right $configuredTargetPath
  })
  if ($matchingTarget.Count -ne 0) {
    throw "$($configuredVariant.VariantName) and $($matchingTarget[0].VariantName) cannot use identical or nested physical module folders: $configuredTargetPath"
  }
  $matchingStagingPath = @($configuredStagingPaths | Where-Object {
    Test-CanvasOverlappingPaths -Left $_.Path -Right $configuredTargetPath
  })
  if ($matchingStagingPath.Count -ne 0) {
    throw "$($configuredVariant.VariantName) physical module folder cannot overlap a repository staging path: $($matchingStagingPath[0].Path)"
  }
  $configuredVariantTargets += [pscustomobject]@{
    VariantName = $configuredVariant.VariantName
    Path = $configuredTargetPath
  }
}

foreach ($variant in $variants) {
  if ([string]::IsNullOrWhiteSpace($variant.PluginModulePath)) {
    throw "$($variant.VariantName) physical module folder is not configured. Set $($variant.EnvironmentVariableName) in .env."
  }

  $stagingPath = Get-NormalizedFullPath -Path $variant.StagingFolderPath
  $targetPath = Get-NormalizedFullPath -Path $variant.PluginModulePath
  Assert-RepositoryStagingPath -Path $stagingPath

  if (Test-Path -LiteralPath $targetPath) {
    if (!(Test-Path -LiteralPath $targetPath -PathType Container)) {
      throw "$($variant.VariantName) physical module path is not a directory: $targetPath"
    }
  }

  $operationName = "Create"
  $targetWasEmpty = !(Test-Path -LiteralPath $targetPath) -or
    @(Get-ChildItem -LiteralPath $targetPath -Force).Count -eq 0
  if (Test-Path -LiteralPath $stagingPath) {
    $stagingItem = Get-Item -LiteralPath $stagingPath -Force
    if ($stagingItem.LinkType -eq "Junction") {
      Assert-JunctionTarget -StagingPath $stagingPath -ExpectedTargetPath $targetPath
      $operationName = "Configured"
    }
    elseif ($stagingItem.PSIsContainer) {
      if (!$MigrateExisting) {
        throw "$($variant.VariantName) staging path exists and is not a Junction. Rerun with -MigrateExisting after reviewing the configured target: $stagingPath"
      }
      if (!$targetWasEmpty) {
        Assert-DirectoryContentsMatch -ExpectedPath $stagingPath -ActualPath $targetPath
      }
      $operationName = "Migrate"
    }
    else {
      throw "$($variant.VariantName) staging path exists and is not a directory: $stagingPath"
    }
  }

  $operations += [pscustomobject]@{
    Variant = $variant
    OperationName = $operationName
    StagingPath = $stagingPath
    TargetPath = $targetPath
    TargetWasEmpty = $targetWasEmpty
  }
}

foreach ($operation in $operations) {
  $variant = $operation.Variant
  Write-Host -ForegroundColor Cyan "Configuring $($variant.VariantName) using $($operation.StagingPath) and linked to $($operation.TargetPath)"

  if ($operation.OperationName -eq "Configured") {
    Write-Host -ForegroundColor Green "$($variant.VariantName) staging Junction is already configured."
    continue
  }

  if (!(Test-Path -LiteralPath $operation.TargetPath -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $operation.TargetPath | Out-Null
  }

  if ($operation.OperationName -eq "Create") {
    New-Item -ItemType Junction -Path $operation.StagingPath -Value $operation.TargetPath | Out-Null
    Assert-JunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.TargetPath
    continue
  }

  $backupPath = "$($operation.StagingPath).setupRepo-backup-$([guid]::NewGuid().ToString('N'))"
  Assert-RepositoryStagingPath -Path $backupPath
  Move-Item -LiteralPath $operation.StagingPath -Destination $backupPath
  try {
    New-Item -ItemType Junction -Path $operation.StagingPath -Value $operation.TargetPath | Out-Null
    if ($operation.TargetWasEmpty) {
      Copy-DirectoryContents -SourcePath $backupPath -DestinationPath $operation.TargetPath
    }
    Assert-DirectoryContentsMatch -ExpectedPath $backupPath -ActualPath $operation.TargetPath
    Assert-JunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.TargetPath
    Remove-VerifiedBackupDirectory -BackupPath $backupPath -OriginalStagingPath $operation.StagingPath
  }
  catch {
    $migrationError = $_.Exception.Message
    if (Test-Path -LiteralPath $operation.StagingPath) {
      $failedStagingItem = Get-Item -LiteralPath $operation.StagingPath -Force
      if ($failedStagingItem.LinkType -eq "Junction") {
        Remove-Item -LiteralPath $operation.StagingPath -Force
      }
    }
    if ((Test-Path -LiteralPath $backupPath -PathType Container) -and
        !(Test-Path -LiteralPath $operation.StagingPath)) {
      Move-Item -LiteralPath $backupPath -Destination $operation.StagingPath
    }
    $restored = (Test-Path -LiteralPath $operation.StagingPath -PathType Container) -and
      (Get-Item -LiteralPath $operation.StagingPath -Force).LinkType -ne "Junction" -and
      !(Test-Path -LiteralPath $backupPath)
    if ($restored) {
      throw "$($variant.VariantName) migration failed and its original staging directory was restored. The physical target may contain a partial copy. $migrationError"
    }
    throw "$($variant.VariantName) migration failed and automatic restoration could not be verified. The backup remains at '$backupPath' when present. $migrationError"
  }
}

Write-Host -ForegroundColor Cyan "`n`n"
Write-Host -ForegroundColor Cyan "**************************************************"
Write-Host -ForegroundColor Cyan "**        Variant Junctions Are Configured       **"
Write-Host -ForegroundColor Cyan "**************************************************"
Write-Host -ForegroundColor Cyan "`n`n"
