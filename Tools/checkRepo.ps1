<#
.SYNOPSIS
Checks configured module metadata, artifacts, and local staging junctions.

.PARAMETER VariantKeys
One or more keys from `$Global:ModuleVariants. Omit this parameter to process all module variants. `VariantKey` remains a compatibility alias.

.PARAMETER Committed
Verifies committed staging artifacts without requiring local environment values or staging junctions.

.PARAMETER EnvironmentPath
Path to the environment file that configures the physical module folders for a local check.
#>
[CmdletBinding()]
param(
  [Alias('VariantKey')]
  [string[]]$VariantKeys,

  [switch]$Committed,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'sharedConfig.ps1')
if (!$Committed) {
  Import-BuildEnvironment -Path $EnvironmentPath
}

function Assert-BuildConfiguredStagingPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$VariantName
  )

  $normalizedPath = Get-BuildNormalizedFullPath -Path $Path
  $repositoryPrefix = $repositoryRoot + [System.IO.Path]::DirectorySeparatorChar
  if (!$normalizedPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Module variant '$VariantName' staging path must remain inside the repository."
  }
}

function Assert-BuildLeafFileName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FileName,

    [Parameter(Mandatory = $true)]
    [string]$Extension,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  if ([string]::IsNullOrWhiteSpace($FileName) -or
      $FileName.Contains('/') -or
      $FileName.Contains('\') -or
      [System.IO.Path]::GetFileName($FileName) -cne $FileName -or
      ![System.IO.Path]::GetExtension($FileName).Equals($Extension, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Description must be a leaf $Extension filename: '$FileName'."
  }
}

$moduleVariants = @($Global:ModuleVariants)
if ($moduleVariants.Count -eq 0) {
  throw 'ModuleVariants must define at least one module variant.'
}

$requiredUniqueProperties = @(
  'VariantKey',
  'VariantName',
  'EsmFileName',
  'PackageBaseName',
  'PapyrusNamespace',
  'StagingFolderPath',
  'EnvironmentVariableName'
)
foreach ($propertyName in $requiredUniqueProperties) {
  foreach ($variant in $moduleVariants) {
    if ($null -eq $variant.PSObject.Properties[$propertyName] -or
        [string]::IsNullOrWhiteSpace([string]$variant.$propertyName)) {
      throw "Every module variant must define $propertyName."
    }
  }
  $values = @($moduleVariants | ForEach-Object { ([string]$_.$propertyName).ToUpperInvariant() })
  if (@($values | Select-Object -Unique).Count -ne $values.Count) {
    throw "Module variant property $propertyName must be unique."
  }
}

foreach ($propertyName in @('ScaleformBuilds', 'Archives')) {
  foreach ($variant in $moduleVariants) {
    if ($null -eq $variant.PSObject.Properties[$propertyName]) {
      throw "Every module variant must define $propertyName."
    }
  }
}

$configuredStagingPaths = @()
foreach ($variant in $moduleVariants) {
  Assert-BuildLeafFileName -FileName $variant.EsmFileName -Extension '.esm' -Description "Module variant '$($variant.VariantKey)' ESM"
  Assert-BuildConfiguredStagingPath -Path $variant.StagingFolderPath -VariantName $variant.VariantKey

  $stagingPath = Get-BuildNormalizedFullPath -Path $variant.StagingFolderPath
  $matchingStagingPath = @($configuredStagingPaths | Where-Object {
    Test-BuildOverlappingPaths -Left $_.Path -Right $stagingPath
  })
  if ($matchingStagingPath.Count -ne 0) {
    throw "$($variant.VariantName) and $($matchingStagingPath[0].VariantName) cannot use identical or nested repository staging paths: $stagingPath"
  }
  $configuredStagingPaths += [pscustomobject]@{
    VariantName = $variant.VariantName
    Path = $stagingPath
  }

  $archiveFileNames = @()
  foreach ($archive in @($variant.Archives)) {
    if ($null -eq $archive) {
      throw "Module variant '$($variant.VariantKey)' archive entries must define FileName."
    }
    $archiveFileName = [string]$archive.FileName
    Assert-BuildLeafFileName -FileName $archiveFileName -Extension '.ba2' -Description "Module variant '$($variant.VariantKey)' archive"
    if ($archiveFileNames -contains $archiveFileName) {
      throw "Module variant '$($variant.VariantKey)' archive FileName values must be unique."
    }
    $archiveFileNames += $archiveFileName
  }
}

if (!$Committed) {
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
}

$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
foreach ($variant in $variants) {
  $stagingPath = Get-BuildNormalizedFullPath -Path $variant.StagingFolderPath
  if (!(Test-Path -LiteralPath $stagingPath -PathType Container)) {
    throw "$($variant.VariantName) staging folder does not exist: $stagingPath"
  }

  $artifactRoot = $stagingPath
  if (!$Committed) {
    $targetPath = Resolve-BuildVariantInstallPath -Variant $variant
    if (!(Test-Path -LiteralPath $targetPath -PathType Container)) {
      throw "$($variant.VariantName) physical module folder does not exist: $targetPath"
    }
    $targetItem = Get-Item -LiteralPath $targetPath -Force
    if (![string]::IsNullOrWhiteSpace([string]$targetItem.LinkType)) {
      throw "$($variant.VariantName) physical module folder must be an ordinary directory, not a link: $targetPath"
    }

    $stagingItem = Get-Item -LiteralPath $stagingPath -Force
    if ($stagingItem.LinkType -ne 'Junction') {
      throw "$($variant.VariantName) staging folder is not a Junction: $stagingPath"
    }
    $targets = @($stagingItem.Target)
    if ($targets.Count -ne 1 -or !(Test-BuildSamePath -Left ([string]$targets[0]) -Right $targetPath)) {
      throw "$($variant.VariantName) staging Junction targets a different physical module folder."
    }
    $artifactRoot = $targetPath
  }

  $expectedArtifactNames = @([string]$variant.EsmFileName)
  $expectedArtifactNames += @($variant.Archives | ForEach-Object { [string]$_.FileName })
  foreach ($artifactName in $expectedArtifactNames) {
    $artifactPath = Join-Path $artifactRoot $artifactName
    if (!(Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
      throw "$($variant.VariantName) is missing expected artifact: $artifactPath"
    }
    Assert-BuildArtifactHeader -Path $artifactPath
  }

  Write-Host -ForegroundColor Green "$($variant.VariantName) staging and configured artifacts are valid."
}

Write-Host -ForegroundColor Cyan "`n`n"
Write-Host -ForegroundColor Cyan '**************************************************'
Write-Host -ForegroundColor Cyan '**     Selected Module Variants Are Valid       **'
Write-Host -ForegroundColor Cyan '**************************************************'
Write-Host -ForegroundColor Cyan "`n`n"
