[CmdletBinding()]
param(
  [Alias('Profile')]
  [string]$BuildProfile = 'Production',

  [string[]]$VariantKeys,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),

  [string]$PluginsDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\plugins')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workRoot = Join-Path $repositoryRoot '.work\canvas'
$env:DOTNET_CLI_HOME = Join-Path $workRoot 'spriggit-dotnet-home'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$matrix = Get-CanvasMatrix -RepositoryRoot $repositoryRoot
$resolvedProfile = Resolve-CanvasProfile -Matrix $matrix -BuildProfile $BuildProfile
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$resolvedPluginsDirectory = Resolve-CanvasRequiredDirectory `
  -Path $PluginsDirectory `
  -Description 'Generated plugin directory'

Import-CanvasEnvironment -Path $EnvironmentPath
foreach ($requiredName in @('TOOL_PATH_SPRIGGIT', 'SPRIGGIT_VERSION')) {
  $value = [Environment]::GetEnvironmentVariable($requiredName, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "$requiredName must be configured in $EnvironmentPath."
  }
}
if ([string]$env:SPRIGGIT_VERSION -cne [string]$matrix.Spriggit.Version) {
  throw "SPRIGGIT_VERSION must match the matrix-pinned version '$($matrix.Spriggit.Version)'."
}
$spriggitPath = Resolve-CanvasExecutable `
  -Path $env:TOOL_PATH_SPRIGGIT `
  -FileName 'Spriggit.CLI.exe' `
  -Description 'Spriggit CLI executable'
$spriggitTranslatorName = [string]$matrix.Spriggit.MetadataPackageName
$spriggitTranslatorPath = Resolve-CanvasExecutable `
  -Path (Join-Path $env:LOCALAPPDATA "Temp\Spriggit\Translations\$spriggitTranslatorName\$($matrix.Spriggit.Version)") `
  -FileName "$spriggitTranslatorName.exe" `
  -Description 'Pinned Spriggit Starfield translator executable'
$spriggitCliSha256 = Get-CanvasFileSha256 -Path $spriggitPath
$spriggitTranslatorSha256 = Get-CanvasFileSha256 -Path $spriggitTranslatorPath
if ($spriggitCliSha256 -cne [string]$matrix.Spriggit.CliSha256) {
  throw "Spriggit CLI executable hash drifted. Expected $($matrix.Spriggit.CliSha256); found $spriggitCliSha256."
}
if ($spriggitTranslatorSha256 -cne [string]$matrix.Spriggit.TranslatorSha256) {
  throw "Spriggit translator executable hash drifted. Expected $($matrix.Spriggit.TranslatorSha256); found $spriggitTranslatorSha256."
}
$dataFolder = $resolvedPluginsDirectory
$generationEvidencePath = Resolve-CanvasRequiredFile `
  -Path (Join-Path $resolvedPluginsDirectory 'generation-evidence.json') `
  -Description 'Profile-bound plugin generation evidence'
$generationEvidence = Get-Content -LiteralPath $generationEvidencePath -Raw | ConvertFrom-Json
if ([string]$generationEvidence.Schema -cne 'VWCANVAS_PLUGIN_SET/1' -or
    [string]$generationEvidence.Profile -cne [string]$resolvedProfile.Key -or
    $generationEvidence.BinaryReadback -ne $true) {
  throw "Plugin generation evidence does not match selected profile '$($resolvedProfile.Key)'."
}

$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot ([string]$matrix.Spriggit.OutputRoot)))
$profileOutputPath = Join-Path $outputRoot ([string]$resolvedProfile.Key)
$candidateRoot = Join-Path $workRoot 'spriggit-yaml-candidates'
$candidateProfilePath = Join-Path $candidateRoot ([string]$resolvedProfile.Key)
$backupRoot = Join-Path $workRoot 'spriggit-yaml-backups'
$backupProfilePath = Join-Path $backupRoot ([string]$resolvedProfile.Key)
foreach ($removal in @(
  @{ Path = $candidateProfilePath; Root = $candidateRoot }
  @{ Path = $backupProfilePath; Root = $backupRoot }
  @{ Path = $profileOutputPath; Root = $outputRoot }
)) {
  Assert-CanvasRemovalPath -Path $removal.Path -AllowedRoot $removal.Root
}
foreach ($path in @($candidateProfilePath, $backupProfilePath)) {
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Recurse -Force
  }
}
New-Item -ItemType Directory -Force -Path $candidateProfilePath | Out-Null

$dumpEvidence = [System.Collections.Generic.List[object]]::new()
foreach ($variant in $variants) {
  $fileName = "$($variant.PackageBaseName).esm"
  $pluginPath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $resolvedPluginsDirectory $fileName) `
    -Description "Generated plugin '$fileName'"
  $expectedHash = [string]$resolvedProfile.PluginSha256[[string]$variant.VariantKey]
  $evidenceMatches = @($generationEvidence.Plugins | Where-Object { [string]$_.FileName -ceq $fileName })
  $actualHash = Get-CanvasFileSha256 -Path $pluginPath
  if ($evidenceMatches.Count -ne 1 -or
      [string]$evidenceMatches[0].Sha256 -cne $expectedHash -or
      $actualHash -cne $expectedHash) {
    throw "Generated plugin '$fileName' does not match profile '$($resolvedProfile.Key)'."
  }

  $pluginOutputPath = Join-Path $candidateProfilePath $fileName
  & $spriggitTranslatorPath serialize `
    -i $pluginPath `
    -o $pluginOutputPath `
    -g Starfield `
    -p $spriggitTranslatorName `
    -v ([string]$matrix.Spriggit.Version) `
    -d $dataFolder | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "Spriggit serialization failed for '$fileName' with exit code $LASTEXITCODE."
  }

  $recordDataPath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $pluginOutputPath 'RecordData.yaml') `
    -Description "Spriggit record data for '$fileName'"
  $recordData = [System.IO.File]::ReadAllText($recordDataPath)
  foreach ($token in @(
    "PackageName: $($matrix.Spriggit.MetadataPackageName)"
    "Version: $($matrix.Spriggit.Version)"
    "ModKey: $fileName"
    'GameRelease: Starfield'
  )) {
    if (!$recordData.Contains($token)) {
      throw "Spriggit record data for '$fileName' is missing token '$token'."
    }
  }

  $dumpEvidence.Add([pscustomobject]@{
    Key = [string]$variant.VariantKey
    FileName = $fileName
    EsmSha256 = $actualHash
    Directory = $fileName
    YamlSha256 = (Get-CanvasDirectoryDigest -Path $pluginOutputPath)
  })
}

$spriggitCliSha256After = Get-CanvasFileSha256 -Path $spriggitPath
$spriggitTranslatorSha256After = Get-CanvasFileSha256 -Path $spriggitTranslatorPath
if ($spriggitCliSha256After -cne $spriggitCliSha256 -or
    $spriggitCliSha256After -cne [string]$matrix.Spriggit.CliSha256) {
  throw 'Spriggit CLI executable changed during Spriggit serialization.'
}
if ($spriggitTranslatorSha256After -cne $spriggitTranslatorSha256 -or
    $spriggitTranslatorSha256After -cne [string]$matrix.Spriggit.TranslatorSha256) {
  throw 'Spriggit translator executable changed during Spriggit serialization.'
}

$evidence = [ordered]@{
  Schema = 'VWCANVAS_SPRIGGIT_DUMP/1'
  Profile = [string]$resolvedProfile.Key
  Variants = @($variants.VariantKey)
  PackageName = [string]$matrix.Spriggit.MetadataPackageName
  SpriggitVersion = [string]$matrix.Spriggit.Version
  SpriggitCliSha256 = $spriggitCliSha256
  SpriggitTranslatorSha256 = $spriggitTranslatorSha256
  PluginGenerationEvidenceSha256 = (Get-CanvasFileSha256 -Path $generationEvidencePath)
  Plugins = @($dumpEvidence)
}
Write-CanvasUtf8WithoutBom `
  -Path (Join-Path $candidateProfilePath 'dump-evidence.json') `
  -Text (($evidence | ConvertTo-Json -Depth 10) + "`n")

New-Item -ItemType Directory -Force -Path $outputRoot, $backupRoot | Out-Null
if (Test-Path -LiteralPath $profileOutputPath) {
  Move-Item -LiteralPath $profileOutputPath -Destination $backupProfilePath
}
try {
  Move-Item -LiteralPath $candidateProfilePath -Destination $profileOutputPath
}
catch {
  if (Test-Path -LiteralPath $backupProfilePath) {
    Move-Item -LiteralPath $backupProfilePath -Destination $profileOutputPath
  }
  throw
}
if (Test-Path -LiteralPath $backupProfilePath) {
  Remove-Item -LiteralPath $backupProfilePath -Recurse -Force
}

Write-Host -ForegroundColor Green "Serialized and verified profile '$($resolvedProfile.Key)' ESMs into tracked Spriggit YAML review sources."
