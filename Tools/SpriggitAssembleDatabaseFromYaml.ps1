<#
.SYNOPSIS
Deserializes selected per-ESM Spriggit YAML directories to their configured staging paths.

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
foreach ($requiredName in @('TOOL_PATH_SPRIGGIT', 'STEAM_DATA_FOLDER')) {
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
$inputRoot = Join-Path $repositoryRoot 'Spriggit'
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$assembledCount = 0
$skippedCount = 0

foreach ($variant in $variants) {
  $fileName = [string]$variant.EsmFileName
  if ([string]::IsNullOrWhiteSpace($fileName)) {
    throw "Module variant '$($variant.VariantKey)' does not configure EsmFileName."
  }
  $pluginInputPath = Join-Path $inputRoot $fileName
  if (!(Test-Path -LiteralPath $pluginInputPath -PathType Container)) {
    Write-Warning "Skipping '$fileName': Spriggit YAML does not exist at '$pluginInputPath'. Staged ESM, if any, was not changed."
    $skippedCount += 1
    continue
  }

  $pluginOutputPath = Join-Path ([string]$variant.StagingFolderPath) $fileName
  try {
    & $spriggitPath deserialize `
      --InputPath $pluginInputPath `
      --OutputPath $pluginOutputPath `
      --DataFolder $env:STEAM_DATA_FOLDER | Out-Host
    $exitCode = $LASTEXITCODE
  }
  catch {
    throw "Spriggit assembly failed for '$fileName' with exit code $LASTEXITCODE. $($_.Exception.Message)"
  }
  if ($exitCode -ne 0) {
    throw "Spriggit assembly failed for '$fileName' with exit code $exitCode."
  }

  $assembledCount += 1
  Write-Host -ForegroundColor Green "Assembled '$fileName' to '$pluginOutputPath'."
}

Write-Host -ForegroundColor Green "Spriggit assembly completed: $assembledCount assembled, $skippedCount skipped."
