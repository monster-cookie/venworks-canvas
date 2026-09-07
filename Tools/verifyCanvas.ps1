<#
.SYNOPSIS
Verifies Canvas source contracts, selected build outputs, and installed package files.
#>
[CmdletBinding()]
param(
  [switch]$SourceOnly,
  [switch]$ArtifactsOnly,
  [string[]]$VariantKeys,
  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '../.env'),
  [string]$ScaleformDirectory = (Join-Path $PSScriptRoot '../.work/canvas/scaleform'),
  [string]$ScriptsDirectory = (Join-Path $PSScriptRoot '../.work/canvas/scripts')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1')
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')
. (Join-Path $PSScriptRoot 'sharedScaleform.ps1')
. (Join-Path $PSScriptRoot 'sharedPackaging.ps1')

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$allVariants = @(Get-ModuleVariants)
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
foreach ($variant in $allVariants) {
  [void](Get-BuildPapyrusSources -Variant $variant -SourceRoot $Global:BuildSettings.PapyrusSourceRoot)
}
[void](ConvertTo-BuildScaleformJobs -Variants $allVariants -RepositoryRoot $repositoryRoot)

foreach ($sourceContractTest in @(
  'testBuildPipeline.ps1',
  'testConsole.ps1',
  'testGuards.ps1',
  'testPackaging.ps1',
  'testBuildVariants.ps1',
  'testBuildEvidence.ps1',
  'testSpriggit.ps1',
  'testSetup.ps1',
  'testUiLoad.ps1',
  'testUiReceive.ps1',
  'testUuid.ps1'
)) {
  & (Resolve-BuildRequiredFile -Path (Join-Path $PSScriptRoot $sourceContractTest) -Description "Source contract test '$sourceContractTest'")
}
if ($SourceOnly) {
  Write-Host -ForegroundColor Green 'Verified Canvas source identities and focused build/source contracts.'
  return
}

[void](Get-BuildPackageArchivePlans -Variants $variants -RepositoryRoot $repositoryRoot `
  -PapyrusSourceRoot $Global:BuildSettings.PapyrusSourceRoot -ScriptsDirectory $ScriptsDirectory -ScaleformDirectory $ScaleformDirectory)
if ($ArtifactsOnly) {
  Write-Host -ForegroundColor Green "Verified current Canvas-owned build inputs for $($variants.VariantKey -join ', ')."
  return
}

Import-BuildEnvironment -Path $EnvironmentPath
$operations = @(Get-BuildPackageInstallOperations -SelectedVariants $variants -AllVariants $allVariants)
foreach ($operation in $operations) {
  Assert-BuildInstalledPackage -Variant $operation.Variant -InstallPath $operation.InstallPath
}
Write-Host -ForegroundColor Green "Verified configured installed package files and headers for $($variants.VariantKey -join ', ')."
