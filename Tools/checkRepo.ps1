<#
.SYNOPSIS
Checks Canvas module metadata, artifacts, and local staging junctions.

.PARAMETER VariantKeys
One or more keys from `$Global:ModuleVariants. Omit this parameter to process
all module variants. `VariantKey` remains a compatibility alias.

.PARAMETER Committed
Verifies committed staging artifacts without requiring local environment values
or staging junctions.
#>
[CmdletBinding()]
param(
  [Alias("VariantKey")]
  [string[]]$VariantKeys,

  [switch]$Committed
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$loadedConfigurationRoot = Get-Variable -Name SharedConfigurationRepositoryRoot -Scope Global -ErrorAction SilentlyContinue
$environmentConfigurationLoaded = Get-Variable -Name SharedConfigurationEnvironmentLoaded -Scope Global -ErrorAction SilentlyContinue
if ($null -eq $loadedConfigurationRoot -or
    (!$Committed -and ($null -eq $environmentConfigurationLoaded -or !$environmentConfigurationLoaded.Value)) -or
    ![string]::Equals(
      [System.IO.Path]::GetFullPath([string]$loadedConfigurationRoot.Value),
      $repositoryRoot,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
  Write-Host -ForegroundColor Green "Importing Shared Configuration"
  if ($Committed) {
    . "$PSScriptRoot\sharedConfig.ps1" -SkipEnvironment
  }
  else {
    . "$PSScriptRoot\sharedConfig.ps1"
  }
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

$moduleVariants = @($Global:ModuleVariants)
if ($moduleVariants.Count -eq 0) {
  throw 'ModuleVariants must define at least one Canvas package variant.'
}

$requiredUniqueProperties = @(
  "VariantKey",
  "VariantName",
  "PackageBaseName",
  "StagingFolderPath",
  "EnvironmentVariableName",
  "ScaleformManifest",
  "ScaleformOutput"
)
foreach ($propertyName in $requiredUniqueProperties) {
  $values = @($moduleVariants | ForEach-Object { [string]$_.$propertyName })
  if (@($values | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -ne 0) {
    throw "Every module variant must define $propertyName."
  }
  if (@($values | Select-Object -Unique).Count -ne $values.Count) {
    throw "Module variant property $propertyName must be unique."
  }
}

foreach ($variant in $moduleVariants) {
  if (@($variant.PapyrusScripts).Count -eq 0 -or
      @($variant.PapyrusScripts | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -ne 0) {
    throw "Module variant '$($variant.VariantKey)' must declare at least one Papyrus source."
  }
  if (![System.IO.Path]::GetFullPath([string]$variant.StagingFolderPath).StartsWith(
      $repositoryRoot + [System.IO.Path]::DirectorySeparatorChar,
      [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Module variant '$($variant.VariantKey)' staging path must remain inside the repository."
  }
}

if (!$Committed) {
  $configuredStagingPaths = @($moduleVariants | ForEach-Object {
    [pscustomobject]@{
      VariantName = $_.VariantName
      Path = (Get-NormalizedFullPath -Path $_.StagingFolderPath)
    }
  })
  $configuredVariantTargets = @()
  foreach ($configuredVariant in $moduleVariants) {
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
}

$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
foreach ($variant in $variants) {
  $stagingPath = Get-NormalizedFullPath -Path $variant.StagingFolderPath
  if (!(Test-Path -LiteralPath $stagingPath -PathType Container)) {
    throw "$($variant.VariantName) staging folder does not exist: $stagingPath"
  }

  if (!$Committed) {
    if ([string]::IsNullOrWhiteSpace($variant.PluginModulePath)) {
      throw "$($variant.VariantName) physical module folder is not configured. Set $($variant.EnvironmentVariableName) in .env."
    }
    $targetPath = Get-NormalizedFullPath -Path $variant.PluginModulePath
    if (!(Test-Path -LiteralPath $targetPath -PathType Container)) {
      throw "$($variant.VariantName) physical module folder does not exist: $targetPath"
    }

    $stagingItem = Get-Item -LiteralPath $stagingPath -Force
    if ($stagingItem.LinkType -ne "Junction") {
      throw "$($variant.VariantName) staging folder is not a Junction: $stagingPath"
    }
    $targets = @($stagingItem.Target)
    if ($targets.Count -ne 1 -or !(Test-SamePath -Left ([string]$targets[0]) -Right $targetPath)) {
      throw "$($variant.VariantName) staging Junction targets a different physical module folder."
    }
  }

  $expectedArtifacts = @(
    "$($variant.PackageBaseName).esm",
    "$($variant.PackageBaseName) - Main.ba2"
  )
  foreach ($artifactName in $expectedArtifacts) {
    $artifactPath = Join-Path $stagingPath $artifactName
    if (!(Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
      throw "$($variant.VariantName) is missing expected artifact: $artifactPath"
    }
    Assert-CanvasArtifactHeader -Path $artifactPath
  }

  Write-Host -ForegroundColor Green "$($variant.VariantName) staging and artifacts are valid."
}

Write-Host -ForegroundColor Cyan "`n`n"
Write-Host -ForegroundColor Cyan "**************************************************"
Write-Host -ForegroundColor Cyan "**     Selected Module Variants Are Valid       **"
Write-Host -ForegroundColor Cyan "**************************************************"
Write-Host -ForegroundColor Cyan "`n`n"
