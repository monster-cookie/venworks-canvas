<#
.SYNOPSIS
Creates local staging junctions for selected module variants whose repository staging paths have been prepared by the maintainer.

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
. (Join-Path $PSScriptRoot 'sharedConfig.ps1')
Import-BuildEnvironment -Path $EnvironmentPath

function Get-BuildPathItemIfPresent {
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

function Assert-BuildRepositoryStagingPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $normalizedPath = Get-BuildNormalizedFullPath -Path $Path
  $repositoryPrefix = $repositoryRoot + [System.IO.Path]::DirectorySeparatorChar
  if (!$normalizedPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Staging path must remain inside the repository: $normalizedPath"
  }
}

function Get-BuildJunctionTargetPath {
  param(
    [Parameter(Mandatory = $true)]
    [System.IO.DirectoryInfo]$Item
  )

  $targets = @($Item.Target)
  if ($targets.Count -ne 1) {
    return $null
  }
  return Get-BuildNormalizedFullPath -Path ([string]$targets[0])
}

function Assert-BuildJunctionTarget {
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

  $actualTargetPath = Get-BuildJunctionTargetPath -Item $stagingItem
  if ($null -eq $actualTargetPath -or !(Test-BuildSamePath -Left $actualTargetPath -Right $ExpectedTargetPath)) {
    throw "Staging Junction does not target its configured physical module folder: $StagingPath"
  }
}

$moduleVariants = @($Global:ModuleVariants)
if ($moduleVariants.Count -eq 0) {
  throw 'ModuleVariants must define at least one module variant.'
}

$configuredStagingPaths = @()
foreach ($configuredVariant in $moduleVariants) {
  $configuredStagingPath = Get-BuildNormalizedFullPath -Path $configuredVariant.StagingFolderPath
  Assert-BuildRepositoryStagingPath -Path $configuredStagingPath
  $matchingStagingPath = @($configuredStagingPaths | Where-Object {
    Test-BuildOverlappingPaths -Left $_.Path -Right $configuredStagingPath
  })
  if ($matchingStagingPath.Count -ne 0) {
    throw "$($configuredVariant.VariantName) and $($matchingStagingPath[0].VariantName) cannot use identical or nested repository staging paths: $configuredStagingPath"
  }
  $configuredStagingPaths += [pscustomobject]@{
    VariantName = $configuredVariant.VariantName
    Path = $configuredStagingPath
  }
}

$configuredVariantTargets = @()
foreach ($configuredVariant in $moduleVariants) {
  $environmentValue = [System.Environment]::GetEnvironmentVariable(
    [string]$configuredVariant.EnvironmentVariableName,
    [System.EnvironmentVariableTarget]::Process
  )
  if ([string]::IsNullOrWhiteSpace($environmentValue)) {
    continue
  }

  $configuredTargetPath = Resolve-BuildVariantInstallPath -Variant $configuredVariant
  $matchingTarget = @($configuredVariantTargets | Where-Object {
    Test-BuildOverlappingPaths -Left $_.Path -Right $configuredTargetPath
  })
  if ($matchingTarget.Count -ne 0) {
    throw "$($configuredVariant.VariantName) and $($matchingTarget[0].VariantName) cannot use identical or nested physical module folders: $configuredTargetPath"
  }
  $matchingStagingPath = @($configuredStagingPaths | Where-Object {
    Test-BuildOverlappingPaths -Left $_.Path -Right $configuredTargetPath
  })
  if ($matchingStagingPath.Count -ne 0) {
    throw "$($configuredVariant.VariantName) physical module folder cannot overlap a repository staging path: $($matchingStagingPath[0].Path)"
  }
  $configuredVariantTargets += [pscustomobject]@{
    VariantName = $configuredVariant.VariantName
    Path = $configuredTargetPath
  }
}

$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$operations = @()

# Validate every selected operation before creating any target directory or Junction.
foreach ($variant in $variants) {
  $stagingPath = Get-BuildNormalizedFullPath -Path $variant.StagingFolderPath
  $targetPath = Resolve-BuildVariantInstallPath -Variant $variant
  Assert-BuildRepositoryStagingPath -Path $stagingPath

  $stagingParentPath = Split-Path -Parent $stagingPath
  $stagingParentItem = Get-BuildPathItemIfPresent -Path $stagingParentPath
  if ($null -eq $stagingParentItem -or !$stagingParentItem.PSIsContainer) {
    throw "$($variant.VariantName) staging parent directory must be prepared before setup: $stagingParentPath"
  }

  $targetItem = Get-BuildPathItemIfPresent -Path $targetPath
  if ($null -ne $targetItem) {
    if (!$targetItem.PSIsContainer) {
      throw "$($variant.VariantName) physical module path is not a directory: $targetPath"
    }
    if (![string]::IsNullOrWhiteSpace([string]$targetItem.LinkType)) {
      throw "$($variant.VariantName) physical module path must be an ordinary directory, not a link: $targetPath"
    }
  }

  $operationName = 'Create'
  $stagingItem = Get-BuildPathItemIfPresent -Path $stagingPath
  if ($null -ne $stagingItem) {
    if ($stagingItem.LinkType -eq 'Junction') {
      Assert-BuildJunctionTarget -StagingPath $stagingPath -ExpectedTargetPath $targetPath
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
  Assert-BuildJunctionTarget -StagingPath $operation.StagingPath -ExpectedTargetPath $operation.TargetPath
}

Write-Host -ForegroundColor Cyan "`n`n"
Write-Host -ForegroundColor Cyan '**************************************************'
Write-Host -ForegroundColor Cyan '**        Variant Junctions Are Configured       **'
Write-Host -ForegroundColor Cyan '**************************************************'
Write-Host -ForegroundColor Cyan "`n`n"
