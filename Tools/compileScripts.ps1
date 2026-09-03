<#
.SYNOPSIS
Compiles the Canvas diagnostic scripts through the profile pipeline, never a legacy Staging folder.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$VenworksCoreRepositoryPath,
  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '../.env')
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'compileConsumerDiscoveryScripts.ps1') @PSBoundParameters
