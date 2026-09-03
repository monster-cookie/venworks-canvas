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
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')

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
if ($moduleVariants.Count -ne 3) {
  throw "ModuleVariants must contain the Host and two demo consumers; found $($moduleVariants.Count)."
}

$requiredUniqueProperties = @(
  "VariantKey",
  "VariantName",
  "PackageBaseName",
  "StagingFolderPath",
  "EnvironmentVariableName"
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

$expectedDefinitions = @(
  [pscustomobject]@{
    VariantKey = "HOST"
    VariantName = "Venworks Canvas Host"
    PackageBaseName = "Venworks-Canvas-Host"
    StagingFolderName = "Staging-Host"
    EnvironmentVariableName = "MODULE_VARIANT_HOST_PATH"
  }
  [pscustomobject]@{
    VariantKey = "CONSUMERA"
    VariantName = "Venworks Canvas Demo Consumer A"
    PackageBaseName = "Venworks-Canvas-ConsumerA"
    StagingFolderName = "Staging-ConsumerA"
    EnvironmentVariableName = "MODULE_VARIANT_CONSUMER_A_PATH"
  }
  [pscustomobject]@{
    VariantKey = "CONSUMERB"
    VariantName = "Venworks Canvas Demo Consumer B"
    PackageBaseName = "Venworks-Canvas-ConsumerB"
    StagingFolderName = "Staging-ConsumerB"
    EnvironmentVariableName = "MODULE_VARIANT_CONSUMER_B_PATH"
  }
)

foreach ($expectedDefinition in $expectedDefinitions) {
  $variantMatches = @($moduleVariants | Where-Object { $_.VariantKey -ceq $expectedDefinition.VariantKey })
  if ($variantMatches.Count -ne 1) {
    throw "Expected exactly one $($expectedDefinition.VariantKey) module variant."
  }

  $variant = $variantMatches[0]
  $expectedStagingPath = Join-Path $repositoryRoot $expectedDefinition.StagingFolderName
  if ($variant.VariantName -cne $expectedDefinition.VariantName -or
      $variant.PackageBaseName -cne $expectedDefinition.PackageBaseName -or
      $variant.EnvironmentVariableName -cne $expectedDefinition.EnvironmentVariableName -or
      !(Test-SamePath -Left $variant.StagingFolderPath -Right $expectedStagingPath)) {
    throw "Module variant '$($expectedDefinition.VariantKey)' does not match the canonical Canvas package definition."
  }
}

if (!$Committed) {
  $configuredVariantTargets = @()
  foreach ($configuredVariant in $moduleVariants) {
    if ([string]::IsNullOrWhiteSpace($configuredVariant.PluginModulePath)) {
      continue
    }

    $configuredTargetPath = Get-NormalizedFullPath -Path $configuredVariant.PluginModulePath
    $matchingTarget = @($configuredVariantTargets | Where-Object {
      Test-SamePath -Left $_.Path -Right $configuredTargetPath
    })
    if ($matchingTarget.Count -ne 0) {
      throw "$($configuredVariant.VariantName) and $($matchingTarget[0].VariantName) cannot use the same physical module folder: $configuredTargetPath"
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
    Assert-ConsumerDiscoveryArtifactHeader -Path $artifactPath
  }

  Write-Host -ForegroundColor Green "$($variant.VariantName) staging and artifacts are valid."
}

Write-Host -ForegroundColor Cyan "`n`n"
Write-Host -ForegroundColor Cyan "**************************************************"
Write-Host -ForegroundColor Cyan "**     Selected Module Variants Are Valid       **"
Write-Host -ForegroundColor Cyan "**************************************************"
Write-Host -ForegroundColor Cyan "`n`n"
