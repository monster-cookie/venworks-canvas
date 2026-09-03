<#
.SYNOPSIS
Builds the three profile-bound diagnostic packages using the existing validated staging pipeline.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$VwHudRepositoryPath,
  [Parameter(Mandatory = $true)][string]$VenworksCoreRepositoryPath,
  [Parameter(Mandatory = $true)][string]$PluginsDirectory,
  [Alias('Profile')][ValidateSet('Baseline','Faults','UpdatedA')][string]$ProbeProfile = 'Baseline',
  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '../.env')
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'stageConsumerDiscoveryProbe.ps1') @PSBoundParameters
