<#
.SYNOPSIS
Compiles the Papyrus scripts owned by one or more Canvas package variants.
.DESCRIPTION
Variant membership comes exclusively from sharedConfig.ps1. Canvas sources are compiled
against the currently installed Papyrus sources into an owned temporary candidate before
the selected outputs are promoted beneath .work.
#>
[CmdletBinding()]
param(
  [string[]]$VariantKeys,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),

  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\.work\canvas\scripts')
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workRoot = Join-Path $repositoryRoot '.work\canvas'
$sourceRoot = Join-Path $repositoryRoot 'Papyrus'
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)
Import-CanvasEnvironment -Path $EnvironmentPath

foreach ($requiredName in @('TOOL_PATH_PAPYRUS_COMPILER', 'PAPYRUS_COMPILER_FLAGS', 'PAPYRUS_SCRIPTS_SOURCE_PATH')) {
  $value = [Environment]::GetEnvironmentVariable($requiredName, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "$requiredName must be configured in $EnvironmentPath."
  }
}

$compilerPath = Resolve-CanvasExecutable `
  -Path $env:TOOL_PATH_PAPYRUS_COMPILER `
  -FileName 'PapyrusCompiler.exe' `
  -Description 'Starfield Papyrus compiler'
$flagsPath = $env:PAPYRUS_COMPILER_FLAGS
if (Test-Path -LiteralPath $flagsPath -PathType Container) {
  $flagsPath = Join-Path $flagsPath 'Starfield_Papyrus_Flags.flg'
}
$resolvedFlagsPath = Resolve-CanvasRequiredFile -Path $flagsPath -Description 'Starfield Papyrus flags file'
$resolvedInstalledSourcePath = Resolve-CanvasRequiredDirectory `
  -Path $env:PAPYRUS_SCRIPTS_SOURCE_PATH `
  -Description 'Installed Papyrus source directory'

Assert-CanvasRemovalPath -Path $resolvedOutputDirectory -AllowedRoot $workRoot
New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory | Out-Null

$sourceSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$sources = [System.Collections.Generic.List[string]]::new()
foreach ($variant in $variants) {
  foreach ($relativeSource in @($variant.PapyrusScripts)) {
    if ($sourceSet.Add([string]$relativeSource)) {
      $sources.Add([string]$relativeSource)
    }
  }
}
if ($sources.Count -eq 0) {
  throw 'The selected variants do not declare any Papyrus scripts.'
}

$sourcePaths = @{}
foreach ($relativeSource in $sources) {
  $sourcePaths[$relativeSource] = Resolve-CanvasRequiredFile `
    -Path (Join-Path $sourceRoot $relativeSource) `
    -Description "Canvas Papyrus source '$relativeSource'"
}

$transactionRoot = Join-Path $workRoot ('script-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $transactionRoot | Out-Null
$compiledOutputs = [System.Collections.Generic.List[object]]::new()
try {
  foreach ($relativeSource in $sources) {
    $sourcePath = [string]$sourcePaths[$relativeSource]
    $compilerArguments = @(
      $sourcePath
      '-f'
      '-optimize'
      "-flags=$resolvedFlagsPath"
      "-output=$transactionRoot"
      "-import=$sourceRoot;$resolvedInstalledSourcePath"
      '-ignorecwd'
    )

    $nativeCommandPreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
      & $compilerPath @compilerArguments
      $compilerExitCode = $LASTEXITCODE
    }
    finally {
      $PSNativeCommandUseErrorActionPreference = $nativeCommandPreference
    }
    if ($compilerExitCode -ne 0) {
      throw "Papyrus compilation failed for '$relativeSource' with exit code $compilerExitCode."
    }

    $outputName = [System.IO.Path]::ChangeExtension($relativeSource, '.pex')
    $candidatePath = Join-Path $transactionRoot $outputName
    if (!(Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
      throw "Papyrus compiler did not produce a fresh output for '$relativeSource': $candidatePath"
    }
    $compiledOutputs.Add([pscustomobject]@{
      CandidatePath = $candidatePath
      DestinationPath = Join-Path $resolvedOutputDirectory $outputName
    })
  }

  foreach ($compiledOutput in $compiledOutputs) {
    $destinationPath = [string]$compiledOutput.DestinationPath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationPath) | Out-Null
    $temporaryPath = "$destinationPath.$PID-$([guid]::NewGuid().ToString('N')).new"
    try {
      Copy-Item -LiteralPath ([string]$compiledOutput.CandidatePath) -Destination $temporaryPath
      [System.IO.File]::Move($temporaryPath, $destinationPath, $true)
    }
    finally {
      if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryPath -Force
      }
    }
  }
}
finally {
  if (Test-Path -LiteralPath $transactionRoot -PathType Container) {
    Assert-CanvasRemovalPath -Path $transactionRoot -AllowedRoot $workRoot
    Remove-Item -LiteralPath $transactionRoot -Recurse -Force
  }
}

Write-Host -ForegroundColor Green "Compiled $($compiledOutputs.Count) selected Canvas Papyrus scripts to $resolvedOutputDirectory"
