<#
.SYNOPSIS
Verifies the exact repository-local tools required by the Canvas Scaleform pipeline.
.DESCRIPTION
Checks the pinned installed-file contracts and executes the repository-local Eclipse Temurin JDK, Apache Flex compiler, and JPEXS command line. The JPEXS probe uses and removes a repository-local temporary profile. No source, installed mod, system Java, PATH, or machine-wide environment setting is changed.
.PARAMETER ToolRoot
Installation directory. Defaults to .work/tools in this repository.
.PARAMETER WorkspaceRoot
Temporary verification workspace. Defaults to .work/pipeline-tooling in this repository.
#>
#Requires -Version 7.0

[CmdletBinding()]
param(
  [string]$ToolRoot = (Join-Path $PSScriptRoot '..\.work\tools'),
  [string]$WorkspaceRoot = (Join-Path $PSScriptRoot '..\.work\pipeline-tooling')
)

$PSNativeCommandUseErrorActionPreference = $false
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedPipelineTooling.ps1')

$contract = Get-PipelineToolingContract
$failures = [System.Collections.Generic.List[string]]::new()

function Write-PipelineCheck {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][bool]$Success,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Details
  )

  if ($Success) {
    Write-Information "[PASS] $Name - $Details" -InformationAction Continue
    return
  }
  Write-Information "[FAIL] $Name - $Details" -InformationAction Continue
  $script:failures.Add($Name)
}

$resolvedToolRoot = [System.IO.Path]::GetFullPath($ToolRoot)
$resolvedWorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)
$toolRootSafe = $true
try {
  [void](Assert-PipelineNoReparseTraversal -Path $resolvedToolRoot -Description 'Pipeline tool root')
  if (Test-Path -LiteralPath $resolvedToolRoot) {
    [void](Assert-PipelineOrdinaryTree -Path $resolvedToolRoot -Description 'Pipeline tool root')
  }
}
catch {
  $toolRootSafe = $false
  Write-PipelineCheck -Name 'Pipeline tool root safety' -Success $false -Details $_.Exception.Message
}

$workspaceRootSafe = $true
try {
  [void](Assert-PipelineNoReparseTraversal -Path $resolvedWorkspaceRoot -Description 'Pipeline workspace root')
}
catch {
  $workspaceRootSafe = $false
  Write-PipelineCheck -Name 'Pipeline workspace root safety' -Success $false -Details $_.Exception.Message
}

$javaRoot = Join-Path $resolvedToolRoot 'java'
$jpexsRoot = Join-Path $resolvedToolRoot 'jpexs'
$flexRoot = Join-Path $resolvedToolRoot 'flex'
$javaPath = Join-Path $javaRoot 'bin\java.exe'
$javaReleasePath = Join-Path $javaRoot $contract.Installed.JavaRelease.RelativePath
$javaExecutablePath = Join-Path $javaRoot $contract.Installed.JavaExecutable.RelativePath
$jpexsPath = Join-Path $jpexsRoot $contract.Installed.JpexsJar.RelativePath
$flexDescriptionPath = Join-Path $flexRoot $contract.Installed.FlexDescription.RelativePath
$mxmlcPath = Join-Path $flexRoot $contract.Installed.MxmlcJar.RelativePath
$compcPath = Join-Path $flexRoot $contract.Installed.CompcJar.RelativePath
$flexConfigPath = Join-Path $flexRoot $contract.Installed.FlexConfig.RelativePath
$playerGlobalPath = Join-Path $flexRoot $contract.Installed.PlayerGlobal.RelativePath

$javaPinned = $toolRootSafe -and (Test-PipelineJavaInstallation -Root $javaRoot -Contract $contract)
Write-PipelineCheck -Name "Eclipse Temurin $($contract.Versions.Java) installation contract" -Success $javaPinned -Details "$javaReleasePath; $javaExecutablePath"
$jpexsPinned = $toolRootSafe -and (Test-PipelineJpexsInstallation -Root $jpexsRoot -Contract $contract)
Write-PipelineCheck -Name "JPEXS $($contract.Versions.Jpexs) library contract" -Success $jpexsPinned -Details $jpexsPath
$flexPinned = $toolRootSafe -and (Test-PipelineFlexInstallation -Root $flexRoot -Contract $contract)
Write-PipelineCheck -Name "Apache Flex $($contract.Versions.ApacheFlex) compiler contract" -Success $flexPinned -Details "$flexDescriptionPath; $mxmlcPath; $compcPath; $flexConfigPath"

$playerGlobals = @()
if ($toolRootSafe -and (Test-Path -LiteralPath (Join-Path $flexRoot 'frameworks') -PathType Container)) {
  $playerGlobals = @(Get-ChildItem -LiteralPath (Join-Path $flexRoot 'frameworks') -Filter 'playerglobal.swc' -Recurse -File -ErrorAction SilentlyContinue)
}
$playerGlobalPinned = $toolRootSafe -and (Test-PipelinePlayerGlobalSet -FlexRoot $flexRoot -Contract $contract)
Write-PipelineCheck -Name "Flash Player $($contract.Versions.PlayerGlobal) compiler library contract" -Success $playerGlobalPinned `
  -Details $(if ($playerGlobals.Count -ne 1) { "Expected exactly one playerglobal.swc; found $($playerGlobals.Count)." } else { $playerGlobalPath })

$javaReady = $false
if ($javaPinned) {
  try {
    $javaOutput = @(& $javaPath -version 2>&1 | ForEach-Object { [string]$_ })
    $javaExitCode = $LASTEXITCODE
    $javaText = [string]::Join(' | ', $javaOutput)
    $javaReady = $javaExitCode -eq 0 -and $javaText -match 'Temurin-21\.0\.12\.1\+1' -and $javaText -match '64-Bit Server VM'
    Write-PipelineCheck -Name 'Pinned Java execution and runtime identity' -Success $javaReady -Details $javaText
  }
  catch {
    Write-PipelineCheck -Name 'Pinned Java execution and runtime identity' -Success $false -Details $_.Exception.Message
  }
}
else {
  Write-PipelineCheck -Name 'Pinned Java execution and runtime identity' -Success $false -Details "Pinned Java executable is unavailable: $javaPath"
}

if ($javaReady -and $flexPinned) {
  try {
    $flexOutput = @(& $javaPath -jar $mxmlcPath -version 2>&1 | ForEach-Object { [string]$_ })
    $flexExitCode = $LASTEXITCODE
    $flexText = [string]::Join(' | ', $flexOutput)
    Write-PipelineCheck -Name 'Apache Flex compiler execution' `
      -Success ($flexExitCode -eq 0 -and $flexText -match '^Version 4\.16\.1 build 20171115') -Details $flexText
  }
  catch {
    Write-PipelineCheck -Name 'Apache Flex compiler execution' -Success $false -Details $_.Exception.Message
  }
}
else {
  Write-PipelineCheck -Name 'Apache Flex compiler execution' -Success $false -Details 'Pinned Java or Apache Flex files are unavailable.'
}

if ($javaReady -and $jpexsPinned -and $workspaceRootSafe) {
  $probeRoot = Join-Path $resolvedWorkspaceRoot ('verify-jpexs-' + [guid]::NewGuid().ToString('N'))
  $previousAppData = $env:APPDATA
  try {
    New-Item -ItemType Directory -Path $probeRoot | Out-Null
    $env:APPDATA = $probeRoot
    $jpexsOutput = @(& $javaPath "-Duser.home=$probeRoot" -jar $jpexsPath -help 2>&1 | ForEach-Object { [string]$_ })
    $jpexsExitCode = $LASTEXITCODE
    $jpexsText = [string]::Join(' | ', @($jpexsOutput | Select-Object -First 2))
    Write-PipelineCheck -Name 'JPEXS command-line execution' `
      -Success ($jpexsExitCode -eq 0 -and ([string]::Join("`n", $jpexsOutput)) -match 'JPEXS Free Flash Decompiler v\.26\.2\.1') -Details $jpexsText
  }
  catch {
    Write-PipelineCheck -Name 'JPEXS command-line execution' -Success $false -Details $_.Exception.Message
  }
  finally {
    if ($null -eq $previousAppData) { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue } else { $env:APPDATA = $previousAppData }
    if (Test-Path -LiteralPath $probeRoot -PathType Container) { Invoke-PipelineTreeRemoval -Path $probeRoot -AllowedRoot $resolvedWorkspaceRoot }
  }
}
else {
  Write-PipelineCheck -Name 'JPEXS command-line execution' -Success $false -Details 'Pinned Java or JPEXS files are unavailable, or the verification workspace is unsafe.'
}

if ($failures.Count -eq 0) {
  Write-Information 'Pipeline tooling is ready.' -InformationAction Continue
  exit 0
}

Write-Information "$($failures.Count) pipeline tooling check(s) failed." -InformationAction Continue
Write-Information 'Run Tools/InstallPipelineTooling.ps1 after providing the required pinned archives and Adobe license acceptance when playerglobal.swc must be installed.' -InformationAction Continue
exit 1
