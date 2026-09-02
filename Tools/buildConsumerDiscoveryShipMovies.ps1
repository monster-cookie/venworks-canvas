[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VwHudRepositoryPath,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),

  [string]$JavaPath,

  [string]$JpexsJarPath,

  [string]$VanillaInterfacePath = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\vanilla-interface'),

  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\ship-movies'),

  [string]$WorkDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\ship-build'),

  [switch]$KeepWork
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workRoot = Join-Path $repositoryRoot '.work\consumer-discovery'
$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot
$resolvedVwHudRoot = Assert-VwHudV2Fixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
Import-ConsumerDiscoveryEnvironment -Path $EnvironmentPath

if ([string]::IsNullOrWhiteSpace($JavaPath)) {
  $JavaPath = Join-Path $resolvedVwHudRoot '.work\tools\java\bin\java.exe'
}
if ([string]::IsNullOrWhiteSpace($JpexsJarPath)) {
  $JpexsJarPath = Join-Path $resolvedVwHudRoot '.work\tools\jpexs\ffdec.jar'
}
$resolvedJavaPath = Resolve-ConsumerDiscoveryRequiredFile -Path $JavaPath -Description 'VWHUD Java runtime'
$resolvedJpexsPath = Resolve-ConsumerDiscoveryRequiredFile -Path $JpexsJarPath -Description 'VWHUD JPEXS jar'
$resolvedVanillaPath = [System.IO.Path]::GetFullPath($VanillaInterfacePath)
$normalVanillaMovie = Join-Path $resolvedVanillaPath 'Interface\spaceshiphudmenu.swf'
$largeVanillaMovie = Join-Path $resolvedVanillaPath 'Interface\spaceshiphudmenu_lrg.swf'
$vanillaMoviesPath = Join-Path $resolvedVanillaPath 'Interface'

if (!(Test-Path -LiteralPath $normalVanillaMovie -PathType Leaf) -or
    !(Test-Path -LiteralPath $largeVanillaMovie -PathType Leaf)) {
  foreach ($requiredName in @('TOOL_PATH_ARCHIVER', 'STEAM_DATA_FOLDER')) {
    $value = [Environment]::GetEnvironmentVariable($requiredName, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) {
      throw "$requiredName must be configured in $EnvironmentPath to extract the vanilla Ship HUD movies."
    }
  }
  $archive2Path = Resolve-ConsumerDiscoveryExecutable `
    -Path $env:TOOL_PATH_ARCHIVER `
    -FileName 'Archive2.exe' `
    -Description 'Archive2 executable'
  $interfaceArchive = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $env:STEAM_DATA_FOLDER 'Starfield - Interface.ba2') `
    -Description 'Starfield vanilla interface archive'
  if (Test-Path -LiteralPath $resolvedVanillaPath -PathType Container) {
    Assert-ConsumerDiscoveryRemovalPath -Path $resolvedVanillaPath -AllowedRoot $workRoot
    Remove-Item -LiteralPath $resolvedVanillaPath -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $resolvedVanillaPath | Out-Null
  & $archive2Path $interfaceArchive "-extract=$resolvedVanillaPath" -quiet
  if ($LASTEXITCODE -ne 0) {
    throw "Archive2 failed to extract the vanilla interface archive with exit code $LASTEXITCODE."
  }
}

[void](Resolve-ConsumerDiscoveryRequiredFile -Path $normalVanillaMovie -Description 'Vanilla normal Ship HUD movie')
[void](Resolve-ConsumerDiscoveryRequiredFile -Path $largeVanillaMovie -Description 'Vanilla large Ship HUD movie')

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$resolvedWorkDirectory = [System.IO.Path]::GetFullPath($WorkDirectory)
foreach ($generatedDirectory in @($resolvedOutputDirectory, $resolvedWorkDirectory)) {
  if (Test-Path -LiteralPath $generatedDirectory -PathType Container) {
    Assert-ConsumerDiscoveryRemovalPath -Path $generatedDirectory -AllowedRoot $workRoot
    Remove-Item -LiteralPath $generatedDirectory -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
}

$compileScript = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $resolvedVwHudRoot 'Tools\compileScaleform.ps1') `
  -Description 'VWHUD v2 underlying Scaleform compiler'
$manifestPaths = @(
  (Join-Path $repositoryRoot 'Scaleform\probes\consumer-discovery\build\spaceshiphudmenu.build.xml')
  (Join-Path $repositoryRoot 'Scaleform\probes\consumer-discovery\build\spaceshiphudmenu-lrg.build.xml')
)
$env:APPDATA = Join-Path $repositoryRoot '.work\appdata'
& $compileScript `
  -JavaPath $resolvedJavaPath `
  -JpexsJarPath $resolvedJpexsPath `
  -VanillaInterfacePath $vanillaMoviesPath `
  -OutputDirectory $resolvedOutputDirectory `
  -WorkDirectory $resolvedWorkDirectory `
  -ManifestPath $manifestPaths `
  -SkipOverrides `
  -KeepWork:$KeepWork
if ($LASTEXITCODE -ne 0) {
  throw "VWHUD Ship HUD build failed with exit code $LASTEXITCODE."
}

foreach ($outputName in @('spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf')) {
  [void](Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedOutputDirectory $outputName) `
    -Description "Patched Ship HUD movie '$outputName'")
}

Write-Host -ForegroundColor Green "Built and hash-validated both Ship HUD movies through the pinned VWHUD v2 pipeline at $resolvedOutputDirectory"
