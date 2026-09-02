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
$resolvedVwHudRoot = Assert-PinnedVwHudToolchainFixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix

if ([string]::IsNullOrWhiteSpace($JavaPath)) {
  $JavaPath = Join-Path $resolvedVwHudRoot '.work\tools\java\bin\java.exe'
}
if ([string]::IsNullOrWhiteSpace($JpexsJarPath)) {
  $JpexsJarPath = Join-Path $resolvedVwHudRoot '.work\tools\jpexs\ffdec.jar'
}
if ([string]::IsNullOrWhiteSpace($FlexSdkPath)) {
  $FlexSdkPath = Join-Path $resolvedVwHudRoot '.work\tools\flex'
}

$pipelineEvidence = [System.Collections.Generic.List[object]]::new()
foreach ($relativePath in @($matrix.VwHudFixture.AuxiliaryDerivedFiles)) {
  $pipelinePath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedVwHudRoot ([string]$relativePath)) `
    -Description "Pinned VWHUD toolchain file '$relativePath'"
  $pipelineEvidence.Add([pscustomobject]@{
    Path = [string]$relativePath
    Sha256 = (Get-FileHash -LiteralPath $pipelinePath -Algorithm SHA256).Hash.ToUpperInvariant()
  })
}
$sharedMovieScript = Resolve-ConsumerDiscoveryRequiredFile `
  -Path (Join-Path $resolvedVwHudRoot 'Tools\sharedScaleformMovies.ps1') `
  -Description 'Pinned VWHUD shared Scaleform movie helper used by the VWCANVAS build'
. $sharedMovieScript
$env:APPDATA = Join-Path $repositoryRoot '.work\appdata'

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$resolvedWorkDirectory = [System.IO.Path]::GetFullPath($WorkDirectory)
if (Test-Path -LiteralPath $resolvedOutputDirectory -PathType Container) {
  Assert-ConsumerDiscoveryRemovalPath -Path $resolvedOutputDirectory -AllowedRoot $consumerDiscoveryWorkRoot
  Remove-Item -LiteralPath $resolvedOutputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory, $resolvedWorkDirectory | Out-Null

$buildResults = [System.Collections.Generic.List[object]]::new()
foreach ($movie in @($matrix.Movies)) {
  $manifestPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $consumerDiscoveryRoot ([string]$movie.Manifest)) `
    -Description "Consumer-discovery manifest '$($movie.Manifest)'"
  Write-Host -ForegroundColor Green "Building $($movie.Key) through the VWCANVAS-owned, VWHUD-v2-derived deterministic movie pipeline"
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

foreach ($pipelineFile in @($pipelineEvidence)) {
  $pipelinePath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedVwHudRoot ([string]$pipelineFile.Path)) `
    -Description "Pinned VWHUD toolchain file '$($pipelineFile.Path)'"
  $currentHash = (Get-FileHash -LiteralPath $pipelinePath -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($currentHash -cne [string]$pipelineFile.Sha256) {
    throw "Pinned VWHUD toolchain file '$($pipelineFile.Path)' changed during the auxiliary movie build."
  }
}
foreach ($result in @($buildResults)) {
  $currentManifestHash = (Get-FileHash -LiteralPath ([string]$result.ManifestPath) -Algorithm SHA256).Hash.ToUpperInvariant()
  $currentSourceHash = (Get-FileHash -LiteralPath ([string]$result.SourcePath) -Algorithm SHA256).Hash.ToUpperInvariant()
  $currentOutputHash = (Get-FileHash -LiteralPath (Join-Path $resolvedOutputDirectory ([string]$result.OutputFile)) -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($currentManifestHash -cne [string]$result.ManifestSha256 -or
      $currentSourceHash -cne [string]$result.SourceSha256 -or
      $currentOutputHash -cne [string]$result.Sha256) {
    throw "Movie '$($result.Name)' input or output changed before complete build evidence could be written."
  }
}

$evidence = [ordered]@{
  Schema = 'VWCANVAS9_CONSUMER_DISCOVERY_BUILD/3'
  GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
  CanvasPipeline = 'VWCANVAS_OWNED_VWHUD_V2_DERIVED/1'
  VwHudRevision = [string]$matrix.VwHudFixture.Revision
  VwHudDerivedHelpers = @($pipelineEvidence)
  Movies = @($buildResults | ForEach-Object {
    [ordered]@{
      Name = $_.Name
      Role = $_.Role
      OutputFile = $_.OutputFile
      Sha256 = $_.Sha256
      Manifest = ([System.IO.Path]::GetRelativePath($consumerDiscoveryRoot, [string]$_.ManifestPath)).Replace('\', '/')
      ManifestSha256 = $_.ManifestSha256
      Source = ([System.IO.Path]::GetRelativePath($consumerDiscoveryRoot, [string]$_.SourcePath)).Replace('\', '/')
      SourceSha256 = $_.SourceSha256
      ClassInventory = @($_.ClassInventory)
      BuildPasses = $_.BuildPasses
    }
  })
}
Write-ConsumerDiscoveryUtf8WithoutBom `
  -Path (Join-Path $resolvedOutputDirectory 'build-evidence.json') `
  -Text (($evidence | ConvertTo-Json -Depth 8) + "`n")

Write-Host -ForegroundColor Green "Built and validated $($buildResults.Count) deterministic consumer-discovery movies at $resolvedOutputDirectory"
