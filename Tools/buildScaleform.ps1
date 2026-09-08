<#
.SYNOPSIS
Builds the configured Scaleform artifacts for the selected module variants.
.DESCRIPTION
Executes the selected configuration's Flex movie and ActionScript patch jobs using Java, JPEXS, and Apache Flex.
.PARAMETER EnvironmentPath
Environment file used only when shared build configuration has not already been initialized in the current PowerShell session.
.PARAMETER VariantKeys
Module variant keys to build. Omit this parameter to build every configured variant.
.PARAMETER JavaPath
Java executable used to run JPEXS and the Apache Flex compiler.
.PARAMETER JpexsJarPath
Path to the JPEXS ffdec.jar file used to normalize, patch, and inspect Scaleform movies.
.PARAMETER FlexSdkPath
Path to the Apache Flex SDK containing mxmlc.jar, flex-config.xml, and playerglobal.swc.
.PARAMETER VanillaInterfacePath
Directory containing the current input movies for selected patch jobs, either directly or beneath an Interface child directory.
.PARAMETER OutputDirectory
Alternative build output directory used instead of publishing final loose files to the selected variants' staging targets. It must be beneath BuildSettings.WorkRoot and also accepts the OutputDir alias.
.PARAMETER WorkDirectory
Temporary build directory. Defaults beneath BuildSettings.WorkRoot and also accepts the WorkDir alias.
.PARAMETER KeepWork
Retains temporary compiler, patch, and recovery work for inspection.
#>
[CmdletBinding()]
param(
  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '../.env'),

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
. (Join-Path $PSScriptRoot 'sharedVariants.ps1')
. (Join-Path $PSScriptRoot 'sharedBuild.ps1')
$sharedConfiguration = Get-Variable -Name SharedConfigurationLoaded -Scope Global -ErrorAction SilentlyContinue
if ($null -eq $sharedConfiguration -or ![bool]$sharedConfiguration.Value) {
  . (Join-Path $PSScriptRoot 'sharedConfig.ps1') -EnvironmentPath $EnvironmentPath
}
. (Join-Path $PSScriptRoot 'sharedScaleform.ps1')
. (Join-Path $PSScriptRoot 'sharedPackaging.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$allVariants = @(Get-ModuleVariants)
$allJobs = @(ConvertTo-BuildScaleformJobs -Variants $allVariants -RepositoryRoot $repositoryRoot)
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
$selectedVariantKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($variant in $variants) {
  [void]$selectedVariantKeys.Add([string]$variant.VariantKey)
}
$jobs = @($allJobs | Where-Object { $selectedVariantKeys.Contains([string]$_.VariantKey) })
if ($jobs.Count -eq 0) {
  Write-Host -ForegroundColor Green "No Scaleform builds are configured for $([string]::Join(', ', @($variants.VariantKey)))."
  return
}

$useStagingOutput = [string]::IsNullOrWhiteSpace($OutputDirectory)
$stagingOperations = if ($useStagingOutput) {
  @(Get-BuildStagingOperations -SelectedVariants $variants -AllVariants $allVariants)
}
else { @() }
if ($useStagingOutput) {
  $OutputDirectory = Join-Path ([string]$Global:BuildSettings.WorkRoot) ('scaleform-output-' + [guid]::NewGuid().ToString('N'))
}
if ([string]::IsNullOrWhiteSpace($WorkDirectory)) {
  $WorkDirectory = Join-Path ([string]$Global:BuildSettings.WorkRoot) 'scaleform-build'
}

$results = @()
try {
  $results = @(Invoke-BuildScaleformJobs `
    -Jobs $jobs `
    -JavaPath $JavaPath `
    -JpexsJarPath $JpexsJarPath `
    -FlexSdkPath $FlexSdkPath `
    -ScaleformSourceRoot ([string]$Global:BuildSettings.ScaleformSourceRoot) `
    -InputDirectory $VanillaInterfacePath `
    -OutputDirectory $OutputDirectory `
    -WorkDirectory $WorkDirectory `
    -AllowedRoot ([string]$Global:BuildSettings.WorkRoot) `
    -KeepWork:$KeepWork)

  if ($useStagingOutput) {
    $publicationPlans = @(Get-BuildScaleformStagingPlans -Variants $variants -Results $results)
    $stagingOperationsByKey = @{}
    foreach ($operation in $stagingOperations) {
      $stagingOperationsByKey[[string]$operation.Key] = $operation
    }
    foreach ($plan in $publicationPlans) {
      $allowedRoot = [string]$stagingOperationsByKey[[string]$plan.VariantKey].StagingPath
      [void](Assert-BuildPublicationDestination -Path ([string]$plan.DestinationPath) -AllowedRoot $allowedRoot)
    }
    foreach ($operation in $stagingOperations) {
      Assert-BuildJunctionTarget -StagingPath ([string]$operation.StagingPath) -ExpectedTargetPath ([string]$operation.InstallPath)
    }
    foreach ($plan in $publicationPlans) {
      $allowedRoot = [string]$stagingOperationsByKey[[string]$plan.VariantKey].StagingPath
      Publish-BuildScaleformFile -CandidatePath ([string]$plan.CandidatePath) -DestinationPath ([string]$plan.DestinationPath) -AllowedRoot $allowedRoot
    }
    Write-Host -ForegroundColor Green "Built and staged $($results.Count) selected Scaleform outputs across $($publicationPlans.Count) loose-file targets for $([string]::Join(', ', @($variants.VariantKey)))"
  }
  else {
    Write-Host -ForegroundColor Green "Built $($results.Count) selected Scaleform outputs for $([string]::Join(', ', @($variants.VariantKey))) at alternative output $([System.IO.Path]::GetFullPath($OutputDirectory))"
  }
}
finally {
  if ($useStagingOutput -and (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    if ($KeepWork) {
      Write-Host -ForegroundColor Yellow "Scaleform output candidates retained at $([System.IO.Path]::GetFullPath($OutputDirectory))"
    }
    else {
      Assert-BuildRemovalPath -Path $OutputDirectory -AllowedRoot ([string]$Global:BuildSettings.WorkRoot)
      Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
    }
  }
}
