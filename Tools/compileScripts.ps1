<#
.SYNOPSIS
Compiles the Papyrus scripts owned by one or more configured module variants.
.DESCRIPTION
Variant membership comes from each variant's exact Papyrus namespace. Sources compile into
a unique work candidate before selected outputs are promoted, preserving unselected outputs.

.PARAMETER VariantKeys
One or more configured module variant keys. Omit this parameter to compile every configured variant. VariantKey is accepted as an alias.

.PARAMETER EnvironmentPath
Environment file used only by the first successful shared configuration initialization in the current PowerShell session. Later calls in that session reuse the loaded configuration; start a fresh process to select a different file.

.PARAMETER OutputDirectory
Directory that receives compiled PEX files. The configured BuildSettings.ScriptsDirectory is used by default. The resolved directory must be contained by BuildSettings.WorkRoot.
#>
[CmdletBinding()]
param(
  [Alias('VariantKey')]
  [string[]]$VariantKeys,

  [string]$EnvironmentPath = (Join-Path $PSScriptRoot '..\.env'),

  [string]$OutputDirectory
)

$PSNativeCommandUseErrorActionPreference = $false
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedVariants.ps1')
. (Join-Path $PSScriptRoot 'sharedBuild.ps1')

$sharedConfigurationVariable = Get-Variable -Name SharedConfigurationLoaded -Scope Global -ErrorAction SilentlyContinue
if ($null -eq $sharedConfigurationVariable -or ![bool]$sharedConfigurationVariable.Value) {
  Write-Host -ForegroundColor Green 'Importing Shared Configuration'
  . (Join-Path $PSScriptRoot 'sharedConfig.ps1') -EnvironmentPath $EnvironmentPath
}

foreach ($settingName in @('WorkRoot', 'PapyrusSourceRoot', 'ScriptsDirectory')) {
  if ($null -eq $Global:BuildSettings -or [string]::IsNullOrWhiteSpace([string]$Global:BuildSettings[$settingName])) {
    throw "BuildSettings.$settingName must be configured."
  }
}

foreach ($requiredName in @('TOOL_PATH_PAPYRUS_COMPILER', 'PAPYRUS_COMPILER_FLAGS', 'PAPYRUS_SCRIPTS_SOURCE_PATH')) {
  $value = [Environment]::GetEnvironmentVariable($requiredName, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "$requiredName must be configured in $EnvironmentPath."
  }
}

$workRoot = Get-BuildNormalizedFullPath -Path ([string]$Global:BuildSettings.WorkRoot)
$sourceRoot = Resolve-BuildRequiredDirectory `
  -Path ([string]$Global:BuildSettings.PapyrusSourceRoot) `
  -Description 'Project Papyrus source root'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = [string]$Global:BuildSettings.ScriptsDirectory
}
$resolvedOutputDirectory = Get-BuildNormalizedFullPath -Path $OutputDirectory
$variants = @(Get-ModuleVariants -VariantKeys $VariantKeys)

$compilerPath = Resolve-BuildExecutable `
  -Path $env:TOOL_PATH_PAPYRUS_COMPILER `
  -FileName 'PapyrusCompiler.exe' `
  -Description 'Starfield Papyrus compiler'
$flagsPath = $env:PAPYRUS_COMPILER_FLAGS
if (Test-Path -LiteralPath $flagsPath -PathType Container) {
  $flagsPath = Join-Path $flagsPath 'Starfield_Papyrus_Flags.flg'
}
$resolvedFlagsPath = Resolve-BuildRequiredFile -Path $flagsPath -Description 'Starfield Papyrus flags file'
$resolvedInstalledSourcePath = Resolve-BuildRequiredDirectory `
  -Path $env:PAPYRUS_SCRIPTS_SOURCE_PATH `
  -Description 'Installed Papyrus source directory'

Assert-BuildRemovalPath -Path $resolvedOutputDirectory -AllowedRoot $workRoot
[IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null

$relativeOutputs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$sources = [Collections.Generic.List[object]]::new()
foreach ($variant in $variants) {
  foreach ($source in @(Get-BuildPapyrusSources -Variant $variant -SourceRoot $sourceRoot)) {
    if ($relativeOutputs.Add([string]$source.RelativeOutput)) {
      $sources.Add($source)
    }
    elseif (@($sources | Where-Object {
          [string]::Equals([string]$_.RelativeSource, [string]$source.RelativeSource, [StringComparison]::OrdinalIgnoreCase)
        }).Count -eq 0) {
      throw "Selected Papyrus namespaces produce the same output '$($source.RelativeOutput)'."
    }
  }
}
if ($sources.Count -eq 0) {
  throw 'The selected variants do not own any Papyrus sources.'
}

$transactionRoot = Join-Path $workRoot ('script-build-' + [guid]::NewGuid().ToString('N'))
Assert-BuildRemovalPath -Path $transactionRoot -AllowedRoot $workRoot
[IO.Directory]::CreateDirectory($transactionRoot) | Out-Null
$compiledOutputs = [Collections.Generic.List[object]]::new()
try {
  foreach ($source in $sources) {
    $compilerArguments = @(
      [string]$source.Source
      '-f'
      '-optimize'
      "-flags=$resolvedFlagsPath"
      "-output=$transactionRoot"
      "-import=$sourceRoot;$resolvedInstalledSourcePath"
      '-ignorecwd'
    )

    try {
      & $compilerPath @compilerArguments | Out-Host
      $compilerExitCode = $LASTEXITCODE
    }
    catch {
      throw "Papyrus compilation failed for '$($source.RelativeSource)' with exit code $LASTEXITCODE. $($_.Exception.Message)"
    }
    if ($compilerExitCode -ne 0) {
      throw "Papyrus compilation failed for '$($source.RelativeSource)' with exit code $compilerExitCode."
    }

    $candidatePath = Join-Path $transactionRoot ([string]$source.RelativeOutput)
    if (!(Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
      throw "Papyrus compiler did not produce a fresh output for '$($source.RelativeSource)': $candidatePath"
    }
    $compiledOutputs.Add([pscustomobject]@{
      CandidatePath = $candidatePath
      DestinationPath = Join-Path $resolvedOutputDirectory ([string]$source.RelativeOutput)
    })
  }

  foreach ($compiledOutput in $compiledOutputs) {
    $destinationPath = [string]$compiledOutput.DestinationPath
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destinationPath)) | Out-Null
    $temporaryPath = "$destinationPath.$PID-$([guid]::NewGuid().ToString('N')).new"
    try {
      Copy-Item -LiteralPath ([string]$compiledOutput.CandidatePath) -Destination $temporaryPath
      [IO.File]::Move($temporaryPath, $destinationPath, $true)
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
    Assert-BuildRemovalPath -Path $transactionRoot -AllowedRoot $workRoot
    Remove-Item -LiteralPath $transactionRoot -Recurse -Force
  }
}

Write-Host -ForegroundColor Green "Compiled $($compiledOutputs.Count) selected Papyrus scripts to $resolvedOutputDirectory"
