<#
.SYNOPSIS
Creates the PC Main archive for one or more configured Canvas module variants.

.PARAMETER VariantKeys
One or more keys from the configured Canvas module variants. Omit this parameter
to process every configured variant. VariantKey remains a compatibility alias.

.PARAMETER Committed
Uses the committed staging directories directly instead of requiring local
Vortex junctions and their configured physical module folders.
#>
[CmdletBinding()]
param(
  [Alias("VariantKey")]
  [string[]]$VariantKeys,

  [switch]$Committed
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = "Stop"

if (!$Global:SharedConfigurationLoaded) {
  Write-Host -ForegroundColor Green "Importing Shared Configuration"
  if ($Committed) {
    . "$PSScriptRoot/sharedConfig.ps1" -SkipEnvironment
  }
  else {
    . "$PSScriptRoot/sharedConfig.ps1"
  }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

function Get-NormalizedPackagePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-SamePackagePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Left,

    [Parameter(Mandatory = $true)]
    [string]$Right
  )

  return [string]::Equals(
    (Get-NormalizedPackagePath -Path $Left),
    (Get-NormalizedPackagePath -Path $Right),
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

function Assert-NotGitLfsPointer {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  $stream = [System.IO.File]::OpenRead($Path)
  try {
    $buffer = [byte[]]::new([Math]::Min(128, [int]$stream.Length))
    [void]$stream.Read($buffer, 0, $buffer.Length)
  }
  finally {
    $stream.Dispose()
  }

  $prefix = [System.Text.Encoding]::UTF8.GetString($buffer)
  if ($prefix.StartsWith("version https://git-lfs.github.com/spec/v1", [System.StringComparison]::Ordinal)) {
    throw "$Description remains a Git LFS pointer: $Path"
  }
}

if ([string]::IsNullOrWhiteSpace($ENV:TOOL_PATH_ARCHIVER)) {
  throw "TOOL_PATH_ARCHIVER must name the directory containing Archive2.exe."
}
$archive2Path = Join-Path $ENV:TOOL_PATH_ARCHIVER "Archive2.exe"
if (!(Test-Path -LiteralPath $archive2Path -PathType Leaf)) {
  throw "Archive2.exe was not found at the TOOL_PATH_ARCHIVER location."
}

$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
foreach ($variant in $variants) {
  $stagingFolderPath = Get-NormalizedPackagePath -Path $variant.StagingFolderPath
  if (!(Test-Path -LiteralPath $stagingFolderPath -PathType Container)) {
    throw "$($variant.VariantName) staging folder does not exist: $stagingFolderPath"
  }

  if ($Committed) {
    $packageOutputPath = $stagingFolderPath
  }
  else {
    if ([string]::IsNullOrWhiteSpace($variant.PluginModulePath)) {
      throw "$($variant.VariantName) physical module folder is not configured. Set $($variant.EnvironmentVariableName) in .env."
    }

    $packageOutputPath = Get-NormalizedPackagePath -Path $variant.PluginModulePath
    if (!(Test-Path -LiteralPath $packageOutputPath -PathType Container)) {
      throw "$($variant.VariantName) physical module folder does not exist: $packageOutputPath"
    }

    $stagingItem = Get-Item -LiteralPath $stagingFolderPath -Force
    if ($stagingItem.LinkType -ne "Junction") {
      throw "$($variant.VariantName) staging folder must be a Junction: $stagingFolderPath"
    }
    $stagingTargets = @($stagingItem.Target)
    if ($stagingTargets.Count -ne 1 -or
        !(Test-SamePackagePath -Left ([string]$stagingTargets[0]) -Right $packageOutputPath)) {
      throw "$($variant.VariantName) staging Junction does not target its configured physical module folder."
    }
  }

  $pluginPath = Join-Path $stagingFolderPath "$($variant.PackageBaseName).esm"
  if (!(Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
    throw "$($variant.VariantName) is missing its required root plugin: $pluginPath"
  }
  if ((Get-Item -LiteralPath $pluginPath).Length -le 0) {
    throw "$($variant.VariantName) root plugin is empty: $pluginPath"
  }
  Assert-NotGitLfsPointer -Path $pluginPath -Description "$($variant.VariantName) root plugin"

  $loosePayloadFiles = @(Get-ChildItem -LiteralPath $stagingFolderPath -File -Recurse | Where-Object {
    $_.Name -cne "meta.ini" -and
    $_.Extension -notin @(".dds", ".btc", ".esp", ".esm", ".ba2")
  })
  if ($loosePayloadFiles.Count -eq 0) {
    throw "$($variant.VariantName) has no loose PC Main payload to archive; its existing BA2 was not changed."
  }

  $archiveName = "$($variant.PackageBaseName) - Main.ba2"
  $archivePath = Join-Path $packageOutputPath $archiveName
  $candidateArchivePath = Join-Path $packageOutputPath ".$(($variant.PackageBaseName))-Main-$PID-$([guid]::NewGuid().ToString('N')).ba2"
  $stagingRootArgument = $stagingFolderPath.TrimEnd('\', '/') + '\'
  $archiveArguments = @(
    $stagingRootArgument
    "-root=$stagingRootArgument"
    "-create=$candidateArchivePath"
    "-format=General"
    "-compression=None"
    "-maxSizeMB=2048"
    '-excludeFilters=.*\\meta\.ini|.*\\.*\.dds|.*\\.*\.btc|.*\\.*\.esp|.*\\.*\.esm|.*\\.*\.ba2'
  )

  try {
    Write-Host -ForegroundColor Green "Creating $archiveName from $stagingFolderPath"
    & $archive2Path @archiveArguments
    if ($LASTEXITCODE -ne 0) {
      throw "Archive2 failed to build $archiveName with exit code $LASTEXITCODE."
    }
    if (!(Test-Path -LiteralPath $candidateArchivePath -PathType Leaf)) {
      throw "Archive2 did not create the expected candidate archive: $candidateArchivePath"
    }
    if ((Get-Item -LiteralPath $candidateArchivePath).Length -le 0) {
      throw "Archive2 created an empty candidate archive: $candidateArchivePath"
    }

    [System.IO.File]::Move($candidateArchivePath, $archivePath, $true)
  }
  finally {
    if (Test-Path -LiteralPath $candidateArchivePath -PathType Leaf) {
      Remove-Item -LiteralPath $candidateArchivePath -Force
    }
  }

  Write-Host -ForegroundColor Green "Created $($variant.VariantName) PC Main archive: $archivePath"
}

Write-Host -ForegroundColor Cyan "`n`n"
Write-Host -ForegroundColor Cyan "**************************************************"
Write-Host -ForegroundColor Cyan "**  Selected Canvas PC Main Archives Created   **"
Write-Host -ForegroundColor Cyan "**************************************************"
Write-Host -ForegroundColor Cyan "`n`n"
