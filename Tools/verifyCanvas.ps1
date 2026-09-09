<#
.SYNOPSIS
Verifies Canvas source contracts, selected build outputs, and installed package files.

.PARAMETER SourceOnly
Run the focused source checks without requiring native build outputs or installed packages.

.PARAMETER ArtifactsOnly
Also inspect the selected build inputs, then stop before checking installed packages.

.PARAMETER VariantKeys
Select configured module variants. Omit to select all variants.

.PARAMETER EnvironmentPath
Required environment file for the first successful configuration load in this PowerShell session. Later calls reuse that configuration; start a new process to select another file.

.PARAMETER ScaleformDirectory
Alternative directory containing Scaleform output sets to inspect instead of each selected variant's staged target files when SourceOnly is not selected.

.PARAMETER ScriptsDirectory
Alternative directory containing compiled Papyrus scripts to inspect instead of each selected variant's staged Scripts directory when SourceOnly is not selected.
#>
[CmdletBinding()]
param(
  [switch]$SourceOnly,
  [switch]$ArtifactsOnly,
  [string[]]$VariantKeys,
  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '../.env'),
  [string]$ScaleformDirectory,
  [string]$ScriptsDirectory
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedVariants.ps1')
. (Join-Path $PSScriptRoot 'sharedBuild.ps1')
$configurationLoaded = Get-Variable -Name SharedConfigurationLoaded -Scope Global -ErrorAction SilentlyContinue
if ($null -eq $configurationLoaded -or !$configurationLoaded.Value) {
  Write-Host -ForegroundColor Green 'Importing Shared Configuration'
  . (Join-Path $PSScriptRoot 'sharedConfig.ps1') -EnvironmentPath $EnvironmentPath
}
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
  'testConsole.ps1',
  'testGuards.ps1',
  'testPackaging.ps1',
  'testBuildVariants.ps1',
  'testBuildEvidence.ps1',
  'testSpriggit.ps1',
  'testSetup.ps1',
  'testScaleformSetup.ps1',
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

$operations = @(Get-BuildPackageInstallOperations -SelectedVariants $variants -AllVariants $allVariants)
foreach ($operation in $operations) {
  Assert-BuildInstalledPackage -Variant $operation.Variant -InstallPath $operation.InstallPath
}
Write-Host -ForegroundColor Green "Verified configured installed package files and headers for $($variants.VariantKey -join ', ')."
