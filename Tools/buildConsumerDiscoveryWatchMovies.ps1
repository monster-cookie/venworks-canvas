<#
.SYNOPSIS
Builds the four Canvas-owned Watch-disabled movies through the pinned VWHUD compiler.
.DESCRIPTION
Uses fresh scratch directories, verifies pinned vanilla inputs and unrelated decompiled classes,
and compares two independent builds. EstablishExpectedHashes writes only scratch hash files;
its outputs cannot be staged until the reviewed hashes are pinned in the build definition.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$VwHudRepositoryPath,
  [Parameter(Mandatory = $true)][string]$VanillaInterfacePath,
  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.work\consumer-discovery\watch-movies'),
  [string]$JavaPath,
  [string]$JpexsJarPath,
  [switch]$EstablishExpectedHashes
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$matrix = Get-ConsumerDiscoveryMatrix -RepositoryRoot $repositoryRoot
$hudRoot = Assert-PinnedVwHudToolchainFixture -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $matrix
$definitionPath = Join-Path $repositoryRoot 'Scaleform\probes\consumer-discovery\build\player-hud-watch.build.psd1'
$definition = Import-PowerShellDataFile -LiteralPath $definitionPath
$patchPath = [IO.Path]::GetFullPath((Join-Path (Split-Path $definitionPath -Parent) $definition.Patch))
$compilerPath = Join-Path $hudRoot 'Tools\compileScaleform.ps1'
if (!$JavaPath) { $JavaPath = Join-Path $hudRoot '.work\tools\java\bin\java.exe' }
if (!$JpexsJarPath) { $JpexsJarPath = Join-Path $hudRoot '.work\tools\jpexs\ffdec.jar' }
$JavaPath = Resolve-ConsumerDiscoveryRequiredFile -Path $JavaPath -Description 'Pinned Java runtime'
$JpexsJarPath = Resolve-ConsumerDiscoveryRequiredFile -Path $JpexsJarPath -Description 'Pinned JPEXS jar'
$vanillaRoot = Resolve-ConsumerDiscoveryRequiredDirectory -Path $VanillaInterfacePath -Description 'Extracted vanilla Interface'
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$workRoot = Join-Path $repositoryRoot '.work\consumer-discovery'
Assert-ConsumerDiscoveryRemovalPath -Path $outputRoot -AllowedRoot $workRoot
if (Test-Path -LiteralPath $outputRoot) { throw 'Use a fresh output directory; existing Watch outputs are never replaced.' }
$expectedNames = @('playerhudcomponents.swf', 'playerhudcomponents.gfx', 'playerhudcomponents_lrg.swf', 'playerhudcomponents_lrg.gfx')
if (@($definition.Movies).Count -ne 4 -or
    @($definition.Movies.File | Sort-Object -Unique).Count -ne 4 -or
    @($definition.Movies | Where-Object { $_.File -cnotin $expectedNames }).Count -ne 0) {
  throw 'Watch build definition must contain exactly the four normal/large SWF/GFX variants.'
}
$inputEvidence = @($definitionPath, $patchPath, $compilerPath | ForEach-Object {
  [ordered]@{ Path = $_; Sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash }
})
foreach ($movie in $definition.Movies) {
  $inputPath = Join-Path $vanillaRoot $movie.File
  if ((Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash -cne $movie.VanillaSha256) {
    throw "Vanilla Watch input hash mismatch: $($movie.File)"
  }
  if (!$EstablishExpectedHashes -and $movie.OutputSha256 -cnotmatch '^[0-9A-F]{64}$') {
    throw "A reviewed output hash must be pinned before building $($movie.File)."
  }
}
$scratch = Join-Path $workRoot ('watch-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch, $outputRoot | Out-Null
$env:APPDATA = Join-Path $repositoryRoot '.work\appdata'
$manifests = @()
foreach ($movie in $definition.Movies) {
  $name = [string]$movie.File
  $manifest = Join-Path $scratch ($name + '.xml')
  $hash = if ($EstablishExpectedHashes) { '0' * 64 } else { $movie.OutputSha256 }
  Write-ConsumerDiscoveryUtf8WithoutBom -Path (Join-Path $scratch ($name + '.vanilla.sha256')) -Text ($movie.VanillaSha256 + "  $name`r`n")
  Write-ConsumerDiscoveryUtf8WithoutBom -Path (Join-Path $scratch ($name + '.expected.sha256')) -Text ($hash + "  $name`r`n")
  $escapedPatch = [System.Security.SecurityElement]::Escape([IO.Path]::GetRelativePath($scratch, $patchPath))
  $xml = "<scaleformBuild name=`"watch-$name`" mode=`"auxiliary-bootstrap`" inputFile=`"$name`" outputFile=`"$name`" vanillaHashFile=`"$name.vanilla.sha256`" expectedHashFile=`"$name.expected.sha256`"><actionScriptPatches><patch path=`"$escapedPatch`" /></actionScriptPatches></scaleformBuild>"
  Write-ConsumerDiscoveryUtf8WithoutBom -Path $manifest -Text $xml
  $manifests += $manifest
}
foreach ($pass in @(1, 2)) {
  & $compilerPath -JavaPath $JavaPath -JpexsJarPath $JpexsJarPath -VanillaInterfacePath $vanillaRoot `
    -OutputDirectory (Join-Path $scratch "pass-$pass") -WorkDirectory (Join-Path $scratch "work-$pass") `
    -ManifestPath $manifests -SkipOverrides -KeepWork -UpdateExpectedHashes:($EstablishExpectedHashes -and $pass -eq 1)
  if ($LASTEXITCODE -ne 0) { throw "Watch build pass $pass failed: $LASTEXITCODE" }
}
$outputs = @()
foreach ($movie in $definition.Movies) {
  $first = Join-Path $scratch ('pass-1\' + $movie.File)
  $second = Join-Path $scratch ('pass-2\' + $movie.File)
  $hash = (Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash
  if ($hash -cne (Get-FileHash -LiteralPath $second -Algorithm SHA256).Hash) {
    throw "Non-deterministic Watch output: $($movie.File)"
  }
  if ((Get-FileHash -LiteralPath (Join-Path $vanillaRoot $movie.File) -Algorithm SHA256).Hash -cne $movie.VanillaSha256) {
    throw "Watch input changed during compilation: $($movie.File)"
  }
  Copy-Item -LiteralPath $second -Destination (Join-Path $outputRoot $movie.File)
  $outputs += [ordered]@{ File = $movie.File; Sha256 = $hash }
}
foreach ($buildInput in $inputEvidence) {
  if ((Get-FileHash -LiteralPath $buildInput.Path -Algorithm SHA256).Hash -cne $buildInput.Sha256) { throw "Build input changed: $($buildInput.Path)" }
}
$evidence = [ordered]@{
  Schema = $definition.Schema
  PinnedOutputs = !$EstablishExpectedHashes
  VwHudRevision = $matrix.VwHudFixture.Revision
  DefinitionSha256 = $inputEvidence[0].Sha256
  PatchSha256 = $inputEvidence[1].Sha256
  CompilerSha256 = $inputEvidence[2].Sha256
  Movies = $outputs
}
Write-ConsumerDiscoveryUtf8WithoutBom -Path (Join-Path $outputRoot 'build-evidence.json') -Text (($evidence | ConvertTo-Json -Depth 5) + "`n")
Write-Host -ForegroundColor Green "Built four deterministic Watch-disabled movies. Pinned outputs: $(!$EstablishExpectedHashes). Scratch retained: $scratch"
