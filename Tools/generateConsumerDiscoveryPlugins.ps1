[CmdletBinding()]
param(
  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\plugins'),

  [switch]$NoRestore
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectPath = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $PSScriptRoot 'ConsumerDiscoveryPluginGenerator\Venworks.Canvas.ConsumerDiscovery.PluginGenerator.csproj') `
  -Description 'Mutagen consumer-discovery plugin generator project'
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$workRoot = Join-Path $repositoryRoot '.work\consumer-discovery'

if (Test-Path -LiteralPath $resolvedOutputDirectory -PathType Container) {
  Assert-ConsumerDiscoveryRemovalPath -Path $resolvedOutputDirectory -AllowedRoot $workRoot
  Remove-Item -LiteralPath $resolvedOutputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory | Out-Null

$env:DOTNET_CLI_HOME = Join-Path $repositoryRoot '.work\dotnet-home'
$env:NUGET_PACKAGES = Join-Path $repositoryRoot '.work\nuget-packages'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'

if (!$NoRestore) {
  & dotnet restore $projectPath --locked-mode
  if ($LASTEXITCODE -ne 0) {
    throw "Locked Mutagen restore failed with exit code $LASTEXITCODE."
  }
}

& dotnet run --project $projectPath --no-restore -- --output $resolvedOutputDirectory
if ($LASTEXITCODE -ne 0) {
  throw "Consumer-discovery plugin generation failed with exit code $LASTEXITCODE."
}

$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot
foreach ($plugin in @($matrix.Plugins)) {
  [void](Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedOutputDirectory ([string]$plugin.FileName)) `
    -Description "Generated plugin '$($plugin.Key)'")
}

Write-Host -ForegroundColor Green "Generated and read back $(@($matrix.Plugins).Count) deterministic Mutagen plugins at $resolvedOutputDirectory"
