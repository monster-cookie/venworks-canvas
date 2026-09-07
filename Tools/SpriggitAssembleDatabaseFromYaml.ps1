<#
.SYNOPSIS
Deserializes selected per-ESM Spriggit YAML directories to their configured staging paths.

.PARAMETER VariantKeys
One or more keys from `$Global:ModuleVariants. Omit this parameter to process all module variants. `VariantKey` remains a compatibility alias.

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
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workRoot = Join-Path $repositoryRoot '.work\canvas'
$env:DOTNET_CLI_HOME = Join-Path $workRoot 'spriggit-dotnet-home'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'

Import-CanvasEnvironment -Path $EnvironmentPath
foreach ($requiredName in @('TOOL_PATH_SPRIGGIT', 'STEAM_DATA_FOLDER')) {
  $value = [Environment]::GetEnvironmentVariable($requiredName, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "$requiredName must be configured in $EnvironmentPath."
  }
}

$spriggitPath = Resolve-CanvasExecutable `
  -Path $env:TOOL_PATH_SPRIGGIT `
  -FileName 'Spriggit.CLI.exe' `
  -Description 'Spriggit CLI executable'
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$inputRoot = Join-Path $repositoryRoot 'Spriggit'
$assembledCount = 0
$skippedCount = 0

foreach ($variant in $variants) {
  $fileName = "$($variant.PackageBaseName).esm"
  $pluginInputPath = Join-Path $inputRoot $fileName
  if (!(Test-Path -LiteralPath $pluginInputPath -PathType Container)) {
    Write-Warning "Skipping '$fileName': Spriggit YAML does not exist at '$pluginInputPath'. Staged ESM, if any, was not changed."
    $skippedCount += 1
    continue
  }

  $pluginOutputPath = Join-Path $variant.StagingFolderPath $fileName
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
