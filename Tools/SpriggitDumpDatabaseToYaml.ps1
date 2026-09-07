<#
.SYNOPSIS
Serializes selected staged ESMs to their tracked per-ESM Spriggit YAML directories.

.PARAMETER VariantKeys
One or more configured module variant keys. Omit this parameter to process all variants.

.PARAMETER EnvironmentPath
Path to the environment file that configures Spriggit and the Starfield data folder.
#>
[CmdletBinding()]
param(
  [Alias('VariantKey')]
  [string[]]$VariantKeys,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env')
)

$PSNativeCommandUseErrorActionPreference = $false
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1')

Import-BuildEnvironment -Path $EnvironmentPath
foreach ($requiredName in @('TOOL_PATH_SPRIGGIT', 'SPRIGGIT_VERSION', 'STEAM_DATA_FOLDER')) {
  $value = [Environment]::GetEnvironmentVariable($requiredName, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "$requiredName must be configured in $EnvironmentPath."
  }
}

$spriggitPath = Resolve-BuildExecutable `
  -Path $env:TOOL_PATH_SPRIGGIT `
  -FileName 'Spriggit.CLI.exe' `
  -Description 'Spriggit CLI executable'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRoot = Join-Path $repositoryRoot 'Spriggit'
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$updatedCount = 0
$skippedCount = 0

foreach ($variant in $variants) {
  $fileName = [string]$variant.EsmFileName
  if ([string]::IsNullOrWhiteSpace($fileName)) {
    throw "Module variant '$($variant.VariantKey)' does not configure EsmFileName."
  }
  $pluginPath = Join-Path ([string]$variant.StagingFolderPath) $fileName
  if (!(Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
    Write-Warning "Skipping '$fileName': staged ESM does not exist at '$pluginPath'. Existing YAML, if any, was not changed."
    $skippedCount += 1
    continue
  }

  $pluginOutputPath = Join-Path $outputRoot $fileName
  try {
    & $spriggitPath serialize `
      --InputPath $pluginPath `
      --PackageVersion $env:SPRIGGIT_VERSION `
      --OutputPath $pluginOutputPath `
      --Check `
      --GameRelease Starfield `
      --PackageName Spriggit.Yaml `
      --DataFolder $env:STEAM_DATA_FOLDER | Out-Host
    $exitCode = $LASTEXITCODE
  }
  catch {
    throw "Spriggit serialization failed for '$fileName' with exit code $LASTEXITCODE. $($_.Exception.Message)"
  }
  if ($exitCode -ne 0) {
    throw "Spriggit serialization failed for '$fileName' with exit code $exitCode."
  }

  $updatedCount += 1
  Write-Host -ForegroundColor Green "Serialized '$fileName' to '$pluginOutputPath'."
}

Write-Host -ForegroundColor Green "Spriggit serialization completed: $updatedCount updated, $skippedCount skipped."
