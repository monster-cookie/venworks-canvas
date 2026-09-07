<#
.SYNOPSIS
Builds the configured Scaleform artifacts for the selected module variants.
.DESCRIPTION
Executes the selected configuration's Flex movie and ActionScript patch jobs using Java, JPEXS, and Apache Flex.
#>
[CmdletBinding()]
param(
  [string[]]$VariantKeys,

  [string]$JavaPath = (Join-Path $PSScriptRoot '..\.work\tools\java\bin\java.exe'),

  [string]$JpexsJarPath = (Join-Path $PSScriptRoot '..\.work\tools\jpexs\ffdec.jar'),

  [string]$FlexSdkPath = (Join-Path $PSScriptRoot '..\.work\tools\flex'),

  [string]$VanillaInterfacePath,

  [Alias('OutputDir')]
  [string]$OutputDirectory,

  [Alias('WorkDir')]
  [string]$WorkDirectory,

  [switch]$KeepWork
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1')
. (Join-Path $PSScriptRoot 'sharedScaleform.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$jobs = @(ConvertTo-BuildScaleformJobs -Variants $variants -RepositoryRoot $repositoryRoot)
if ($jobs.Count -eq 0) {
  Write-Host -ForegroundColor Green "No Scaleform builds are configured for $([string]::Join(', ', @($variants.VariantKey)))."
  return
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = [string]$Global:BuildSettings.ScaleformDirectory
}
if ([string]::IsNullOrWhiteSpace($WorkDirectory)) {
  $WorkDirectory = Join-Path ([string]$Global:BuildSettings.WorkRoot) 'scaleform-build'
}

$results = @(Invoke-BuildScaleformJobs `
  -Jobs $jobs `
  -JavaPath $JavaPath `
  -JpexsJarPath $JpexsJarPath `
  -FlexSdkPath $FlexSdkPath `
  -InputDirectory $VanillaInterfacePath `
  -OutputDirectory $OutputDirectory `
  -WorkDirectory $WorkDirectory `
  -AllowedRoot ([string]$Global:BuildSettings.WorkRoot) `
  -KeepWork:$KeepWork)

Write-Host -ForegroundColor Green "Built $($results.Count) selected Scaleform outputs for $([string]::Join(', ', @($variants.VariantKey))) at $([System.IO.Path]::GetFullPath($OutputDirectory))"
