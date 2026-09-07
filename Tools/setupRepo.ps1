<#
.SYNOPSIS
Creates local staging junctions for Canvas module variants whose repository staging paths have been prepared by the maintainer.

.PARAMETER VariantKeys
One or more keys from `$Global:ModuleVariants. Omit this parameter to process all module variants. `VariantKey` remains a compatibility alias.

.PARAMETER EnvironmentPath
Path to the environment file that configures the physical module folders.
#>
[CmdletBinding()]
param(
  [Alias('VariantKey')]
  [string[]]$VariantKeys,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')
Import-CanvasEnvironment -Path $EnvironmentPath
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment

function Get-NormalizedFullPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw 'A filesystem path cannot be empty.'
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
  if ($stagingItem.LinkType -ne 'Junction') {
    throw "Staging path is not a Junction: $StagingPath"
  }

  $actualTargetPath = Get-JunctionTargetPath -Item $stagingItem
  if ($null -eq $actualTargetPath -or !(Test-SamePath -Left $actualTargetPath -Right $ExpectedTargetPath)) {
    throw "Staging Junction does not target its configured physical module folder: $StagingPath"
  }
}

function Get-PathItemIfPresent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  try {
    return Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  }
  catch [System.Management.Automation.ItemNotFoundException] {
    return $null
  }
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

# Validate every selected path before creating a target directory or Junction.
foreach ($variant in $variants) {
  if ([string]::IsNullOrWhiteSpace($variant.PluginModulePath)) {
    throw "$($variant.VariantName) physical module folder is not configured. Set $($variant.EnvironmentVariableName) in $EnvironmentPath."
  }

  $stagingPath = Get-NormalizedFullPath -Path $variant.StagingFolderPath
  $targetPath = Get-NormalizedFullPath -Path $variant.PluginModulePath
  Assert-RepositoryStagingPath -Path $stagingPath

  $targetItem = Get-PathItemIfPresent -Path $targetPath
  if ($null -ne $targetItem) {
    if (!$targetItem.PSIsContainer) {
      throw "$($variant.VariantName) physical module path is not a directory: $targetPath"
    }
    if (![string]::IsNullOrWhiteSpace([string]$targetItem.LinkType)) {
      throw "$($variant.VariantName) physical module path must be an ordinary directory, not a link: $targetPath"
    }
  }

  $operationName = 'Create'
  $stagingItem = Get-PathItemIfPresent -Path $stagingPath
  if ($null -ne $stagingItem) {
    if ($stagingItem.LinkType -eq 'Junction') {
      Assert-JunctionTarget -StagingPath $stagingPath -ExpectedTargetPath $targetPath
      $operationName = 'Configured'
    }
    elseif (![string]::IsNullOrWhiteSpace([string]$stagingItem.LinkType)) {
      throw "$($variant.VariantName) staging path uses unsupported link type '$($stagingItem.LinkType)': $stagingPath"
    }
    elseif ($stagingItem.PSIsContainer) {
      throw "$($variant.VariantName) staging path exists as an ordinary directory. Move or remove it manually before running setup: $stagingPath"
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
  }
}

foreach ($operation in $operations) {
  $variant = $operation.Variant
  Write-Host -ForegroundColor Cyan "Configuring $($variant.VariantName) using $($operation.StagingPath) and linked to $($operation.TargetPath)"

  if ($operation.OperationName -eq 'Configured') {
    Write-Host -ForegroundColor Green "$($variant.VariantName) staging Junction is already configured."
    continue
  }

  if (!(Test-Path -LiteralPath $operation.TargetPath -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $operation.TargetPath | Out-Null
  }
  New-Item -ItemType Junction -Path $operation.StagingPath -Value $operation.TargetPath | Out-Null
  Assert-JunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.TargetPath
}

Write-Host -ForegroundColor Cyan "`n`n"
Write-Host -ForegroundColor Cyan '**************************************************'
Write-Host -ForegroundColor Cyan '**        Variant Junctions Are Configured       **'
Write-Host -ForegroundColor Cyan '**************************************************'
Write-Host -ForegroundColor Cyan "`n`n"
