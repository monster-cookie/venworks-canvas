<#
.SYNOPSIS
Installs the exact repository-local tools required by the Canvas Scaleform pipeline.
.DESCRIPTION
Do not remove this entrypoint without replacing its pinned, cache-aware provisioning. Canvas needs a legacy Adobe Flex 4.6 Player 11.1 compiler library whose end-of-life download may disappear, plus the exact Eclipse Temurin Windows x64 HotSpot JDK, JPEXS, and Apache Flex versions validated by this repository. A system Java installation or a newer SDK is not a compatible substitute for these pinned build inputs.

The installer reuses exact existing files, validates every cached or downloaded archive by byte length and SHA-256, stages and validates candidates before replacement, and invokes the separate verifier after installation. It does not change system Java, PATH, or machine-wide environment variables.
.PARAMETER AcceptAdobeLicense
Confirms that the caller reviewed and accepts the Adobe Flex SDK license before this script extracts Player 11.1 playerglobal.swc. An already-valid compiler library can be reused without this switch.
.PARAMETER ArtifactCachePath
Optional read-only directory checked before the repository-local cache. For example, this may point at an ArtLibrary ToolingCache checkout. Missing artifacts fall back to the pinned original download locations unless Offline is selected.
.PARAMETER Offline
Prohibits downloads. Every required archive must already exist in ArtifactCachePath or the repository-local cache.
.PARAMETER ToolRoot
Installation directory. Defaults to .work/tools in this repository.
.PARAMETER WorkspaceRoot
Repository-local cache, download, extraction, and verification workspace. Defaults to .work/pipeline-tooling in this repository.
#>
#Requires -Version 7.0

[CmdletBinding()]
param(
  [switch]$AcceptAdobeLicense,
  [string]$ArtifactCachePath,
  [switch]$Offline,
  [string]$ToolRoot = (Join-Path $PSScriptRoot '..\.work\tools'),
  [string]$WorkspaceRoot = (Join-Path $PSScriptRoot '..\.work\pipeline-tooling')
)

$PSNativeCommandUseErrorActionPreference = $false
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedPipelineTooling.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$contract = Get-PipelineToolingContract
Invoke-PipelineToolingInstall -Contract $contract -RepositoryRoot $repositoryRoot `
  -ToolRoot $ToolRoot -WorkspaceRoot $WorkspaceRoot -ArtifactCachePath $ArtifactCachePath `
  -Offline:$Offline -AcceptAdobeLicense:$AcceptAdobeLicense

& (Join-Path $PSScriptRoot 'VerifyPipelineTooling.ps1') -ToolRoot $ToolRoot -WorkspaceRoot $WorkspaceRoot
exit $LASTEXITCODE
