[CmdletBinding()]
param(
  [switch]$SkipEnvironment
)

# Abort on first error
$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = "Stop"

class CanvasModuleVariant {
  [string]$VariantKey
  [string]$VariantName
  [string]$PackageBaseName
  [string]$StagingFolderPath
  [string]$EnvironmentVariableName
  [string]$PluginModulePath

  CanvasModuleVariant(
    [string]$variantKey,
    [string]$variantName,
    [string]$packageBaseName,
    [string]$stagingFolderPath,
    [string]$environmentVariableName,
    [string]$pluginModulePath
  ) {
    $this.VariantKey = $variantKey
    $this.VariantName = $variantName
    $this.PackageBaseName = $packageBaseName
    $this.StagingFolderPath = $stagingFolderPath
    $this.EnvironmentVariableName = $environmentVariableName
    $this.PluginModulePath = $pluginModulePath
  }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$environmentPath = Join-Path $repositoryRoot ".env"

if (!$SkipEnvironment) {
  if (!(Test-Path -LiteralPath $environmentPath -PathType Leaf)) {
    throw "ERROR: .env file must be created and configured to run this."
  }

  Write-Host -ForegroundColor Green "Importing ENV Settings from .env file"
  foreach ($environmentLine in Get-Content -LiteralPath $environmentPath) {
    $trimmedLine = $environmentLine.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith("#")) {
      continue
    }

    $separatorIndex = $environmentLine.IndexOf("=")
    if ($separatorIndex -le 0) {
      throw "Invalid .env entry: expected NAME=VALUE."
    }

    $name = $environmentLine.Substring(0, $separatorIndex).Trim()
    $value = $environmentLine.Substring($separatorIndex + 1).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
      throw "Invalid .env entry: environment variable name cannot be empty."
    }

    Set-Item -LiteralPath "env:$name" -Value $value
  }

  Write-Host -ForegroundColor Yellow "`nTool Settings:"
  Write-Host -ForegroundColor Yellow "BGS Papyrus Compiler path is $ENV:TOOL_PATH_PAPYRUS_COMPILER"
  Write-Host -ForegroundColor Yellow "BGS Archive2 path is $ENV:TOOL_PATH_ARCHIVER"
  Write-Host -ForegroundColor Yellow "BGS xtexconv path is $ENV:TOOL_PATH_XTEXCONV"
  Write-Host -ForegroundColor Yellow "BGS AssetWatcher path is $ENV:TOOL_PATH_ASSET_WATCHER"
  Write-Host -ForegroundColor Yellow "BGS AssetWatcher Plugins path is $ENV:TOOL_PATH_ASSET_WATCHER_PLUGINS"
  Write-Host -ForegroundColor Yellow "`nSpriggit Settings:"
  Write-Host -ForegroundColor Yellow "Spriggit CLI path is $ENV:TOOL_PATH_SPRIGGIT"
  Write-Host -ForegroundColor Yellow "Spriggit Version is $ENV:SPRIGGIT_VERSION"
  Write-Host -ForegroundColor Yellow "`nSteam Settings:"
  Write-Host -ForegroundColor Yellow "Starfield game folder is set to $ENV:STEAM_GAME_FOLDER."
  Write-Host -ForegroundColor Yellow "Starfield data folder is set to $ENV:STEAM_DATA_FOLDER."
  Write-Host -ForegroundColor Yellow "`nPapyrus Settings:"
  Write-Host -ForegroundColor Yellow "BGS Papyrus Compiler Flags files is $ENV:PAPYRUS_COMPILER_FLAGS"
  Write-Host -ForegroundColor Yellow "BGS Papyrus Script path is $ENV:PAPYRUS_SCRIPTS_PATH"
  Write-Host -ForegroundColor Yellow "BGS Papyrus Source path is $ENV:PAPYRUS_SCRIPTS_SOURCE_PATH"
  Write-Host -ForegroundColor Yellow "`nModule Settings:"
  Write-Host -ForegroundColor Yellow "Legacy Module Database Folder is $ENV:MODULE_DATABASE_PATH"
  Write-Host -ForegroundColor Yellow "Host Module Folder is $ENV:MODULE_VARIANT_HOST_PATH"
  Write-Host -ForegroundColor Yellow "Demo Consumer A Module Folder is $ENV:MODULE_VARIANT_CONSUMER_A_PATH"
  Write-Host -ForegroundColor Yellow "Demo Consumer B Module Folder is $ENV:MODULE_VARIANT_CONSUMER_B_PATH"
  Write-Host -ForegroundColor Yellow "Module Scripting Folder is $ENV:MODULE_SCRIPTS_PATH"
  Write-Host -ForegroundColor Yellow "Module Scripting Source Folder is $ENV:MODULE_SCRIPTS_SOURCE_PATH"
}

$Global:ModuleVariants = @(
  [CanvasModuleVariant]::new(
    "HOST",
    "Venworks Canvas Host",
    "VWCANVAS9-Host",
    (Join-Path $repositoryRoot "Staging-Host"),
    "MODULE_VARIANT_HOST_PATH",
    "$ENV:MODULE_VARIANT_HOST_PATH"
  )

  [CanvasModuleVariant]::new(
    "CONSUMERA",
    "Venworks Canvas Demo Consumer A",
    "VWCANVAS9-ConsumerA",
    (Join-Path $repositoryRoot "Staging-ConsumerA"),
    "MODULE_VARIANT_CONSUMER_A_PATH",
    "$ENV:MODULE_VARIANT_CONSUMER_A_PATH"
  )

  [CanvasModuleVariant]::new(
    "CONSUMERB",
    "Venworks Canvas Demo Consumer B",
    "VWCANVAS9-ConsumerB",
    (Join-Path $repositoryRoot "Staging-ConsumerB"),
    "MODULE_VARIANT_CONSUMER_B_PATH",
    "$ENV:MODULE_VARIANT_CONSUMER_B_PATH"
  )
)

function Global:Get-ModuleVariants {
  [CmdletBinding()]
  param(
    [Alias("VariantKey")]
    [string[]]$VariantKeys
  )

  if ($null -eq $VariantKeys -or $VariantKeys.Count -eq 0) {
    return @($Global:ModuleVariants)
  }

  $normalizedKeys = @($VariantKeys | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) {
      throw "Variant keys cannot be empty."
    }
    $_.Trim().ToUpperInvariant()
  })
  if (@($normalizedKeys | Select-Object -Unique).Count -ne $normalizedKeys.Count) {
    throw "Variant keys cannot be repeated."
  }

  $selectedVariants = foreach ($normalizedKey in $normalizedKeys) {
    $matchingVariants = @($Global:ModuleVariants | Where-Object {
      [string]$_.VariantKey -eq $normalizedKey
    })
    if ($matchingVariants.Count -ne 1) {
      throw "Unknown module variant key '$normalizedKey'."
    }
    $matchingVariants[0]
  }

  return @($selectedVariants)
}

$Global:Databases = @(
  "Venworks-Canvas.esm"
)

$Global:ScriptingNamespaceModuleCompany = "Venworks"
$Global:ScriptingNamespaceModuleName = "Canvas"
$Global:SharedConfigurationRepositoryRoot = $repositoryRoot
$Global:SharedConfigurationEnvironmentLoaded = !$SkipEnvironment
$Global:SharedConfigurationLoaded = $true

if (!$SkipEnvironment) {
  Write-Host -ForegroundColor Yellow "Papyrus Scripting namespace for module is $Global:ScriptingNamespaceModuleCompany`:$Global:ScriptingNamespaceModuleName"

  Write-Host -ForegroundColor Yellow "`nGame Database Files:"
  foreach ($database in $Global:Databases) {
    Write-Host -ForegroundColor Yellow $database
  }
  Write-Host -ForegroundColor Yellow "`n"
}
