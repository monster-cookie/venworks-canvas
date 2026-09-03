<#
.SYNOPSIS
Serializes the selected Canvas profile for code review. Never assembles a plugin from YAML.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$PluginsDirectory,
  [Alias('Profile')][ValidateSet('Baseline','Faults','UpdatedA')][string]$ProbeProfile = 'Baseline',
  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '../.env')
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'dumpConsumerDiscoveryPluginsToYaml.ps1') @PSBoundParameters
