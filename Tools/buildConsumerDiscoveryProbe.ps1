[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VwHudRepositoryPath,

  [string]$JavaPath,

  [string]$JpexsJarPath,

  [string]$FlexSdkPath,

  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\movies'),

  [string]$WorkDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\build'),

  [switch]$KeepWork
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$consumerDiscoveryRoot = Join-Path $repositoryRoot 'Scaleform\probes\consumer-discovery'
$consumerDiscoveryWorkRoot = Join-Path $repositoryRoot '.work\consumer-discovery'
$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot
$resolvedVwHudRoot = Assert-VwHudV2Fixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix

if ([string]::IsNullOrWhiteSpace($JavaPath)) {
  $JavaPath = Join-Path $resolvedVwHudRoot '.work\tools\java\bin\java.exe'
}
if ([string]::IsNullOrWhiteSpace($JpexsJarPath)) {
  $JpexsJarPath = Join-Path $resolvedVwHudRoot '.work\tools\jpexs\ffdec.jar'
}
if ([string]::IsNullOrWhiteSpace($FlexSdkPath)) {
  $FlexSdkPath = Join-Path $resolvedVwHudRoot '.work\tools\flex'
}

$sharedMovieScript = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $resolvedVwHudRoot 'Tools\sharedScaleformMovies.ps1') `
  -Description 'VWHUD v2 shared Scaleform movie helper'
. $sharedMovieScript

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$resolvedWorkDirectory = [System.IO.Path]::GetFullPath($WorkDirectory)
if (Test-Path -LiteralPath $resolvedOutputDirectory -PathType Container) {
  Assert-ConsumerDiscoveryRemovalPath -Path $resolvedOutputDirectory -AllowedRoot $consumerDiscoveryWorkRoot
  Remove-Item -LiteralPath $resolvedOutputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory, $resolvedWorkDirectory | Out-Null

$pipelineEvidence = [System.Collections.Generic.List[object]]::new()
foreach ($relativePath in @($matrix.VwHudFixture.RequiredPipelineFiles)) {
  $pipelinePath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedVwHudRoot ([string]$relativePath)) `
    -Description "VWHUD v2 pipeline file '$relativePath'"
  $pipelineEvidence.Add([pscustomobject]@{
    Path = [string]$relativePath
    Sha256 = (Get-FileHash -LiteralPath $pipelinePath -Algorithm SHA256).Hash.ToUpperInvariant()
  })
}

$buildResults = [System.Collections.Generic.List[object]]::new()
foreach ($movie in @($matrix.Movies)) {
  $manifestPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $consumerDiscoveryRoot ([string]$movie.Manifest)) `
    -Description "Consumer-discovery manifest '$($movie.Manifest)'"
  Write-Host -ForegroundColor Green "Building $($movie.Key) through the VWHUD v2-derived deterministic movie pipeline"
  $result = Invoke-ConsumerDiscoveryMovieBuild `
    -ManifestPath $manifestPath `
    -OutputDirectory $resolvedOutputDirectory `
    -WorkDirectory $resolvedWorkDirectory `
    -JavaPath $JavaPath `
    -JpexsJarPath $JpexsJarPath `
    -FlexSdkPath $FlexSdkPath `
    -KeepWork:$KeepWork
  if ($result.OutputFile -cne [string]$movie.Output) {
    throw "Movie '$($movie.Key)' emitted '$($result.OutputFile)' instead of '$($movie.Output)'."
  }
  $buildResults.Add($result)
}

$evidence = [ordered]@{
  Schema = 'VWCANVAS9_CONSUMER_DISCOVERY_BUILD/1'
  GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
  VwHudRevision = [string]$matrix.VwHudFixture.Revision
  VwHudPipeline = @($pipelineEvidence)
  Movies = @($buildResults | ForEach-Object {
    [ordered]@{
      Name = $_.Name
      Role = $_.Role
      OutputFile = $_.OutputFile
      Sha256 = $_.Sha256
      ClassInventory = @($_.ClassInventory)
      BuildPasses = $_.BuildPasses
    }
  })
}
Write-ConsumerDiscoveryUtf8WithoutBom `
  -Path (Join-Path $resolvedOutputDirectory 'build-evidence.json') `
  -Text (($evidence | ConvertTo-Json -Depth 8) + "`n")

Write-Host -ForegroundColor Green "Built and validated $($buildResults.Count) deterministic consumer-discovery movies at $resolvedOutputDirectory"
