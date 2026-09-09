<#
.SYNOPSIS
Exercises selected Papyrus builds with an isolated compiler fixture.
.DESCRIPTION
The fixture verifies namespace-derived variant selection, installed-source imports, compiler failures, missing
fresh outputs, and preservation of existing selected and unselected output bytes.
#>
[CmdletBinding()]
param()

$PSNativeCommandUseErrorActionPreference = $false
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-TestText {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
  )

  [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path)) | Out-Null
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Assert-TestText {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Expected,
    [Parameter(Mandatory = $true)][string]$Description
  )

  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "$Description is missing: $Path"
  }
  $actual = [System.IO.File]::ReadAllText($Path)
  if ($actual -cne $Expected) {
    throw "$Description changed. Expected '$Expected'; found '$actual'."
  }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$compileScriptPath = Join-Path $PSScriptRoot 'compileScripts.ps1'
$sharedVariantsPath = Join-Path $PSScriptRoot 'sharedVariants.ps1'
$powerShellPath = (Get-Process -Id $PID).Path
$testBase = Join-Path $repositoryRoot '.work\canvas\pr4-simplification\papyrus'
$fixtureRoot = Join-Path $testBase ('compile-' + [guid]::NewGuid().ToString('N'))
$installedSourceRoot = Join-Path $fixtureRoot 'installed-sources'
$flagsPath = Join-Path $fixtureRoot 'Starfield_Papyrus_Flags.flg'
$fakeCompilerPath = Join-Path $fixtureRoot 'fakePapyrusCompiler.ps1'
$canvasSourceRoot = Join-Path $repositoryRoot 'Papyrus'

function New-TestEnvironment {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Mode,
    [Parameter(Mandatory = $true)][string]$LogPath
  )

  $lines = @(
    "TOOL_PATH_PAPYRUS_COMPILER=$fakeCompilerPath"
    "PAPYRUS_COMPILER_FLAGS=$flagsPath"
    "PAPYRUS_SCRIPTS_SOURCE_PATH=$installedSourceRoot"
    "VWCANVAS_TEST_SOURCE_ROOT=$canvasSourceRoot"
    "VWCANVAS_TEST_COMPILER_MODE=$Mode"
    "VWCANVAS_TEST_COMPILER_LOG=$LogPath"
  )
  Write-TestText -Path $Path -Text ([string]::Join([Environment]::NewLine, $lines) + [Environment]::NewLine)
}

function Invoke-TestCompile {
  param(
    [Parameter(Mandatory = $true)][string]$VariantKey,
    [Parameter(Mandatory = $true)][string]$EnvironmentPath,
    [string]$OutputDirectory
  )

  $arguments = @('-NoProfile', '-File', $compileScriptPath, '-VariantKeys', $VariantKey, '-EnvironmentPath', $EnvironmentPath)
  if (![string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $arguments += @('-OutputDirectory', $OutputDirectory)
  }
  $output = @(& $powerShellPath @arguments 2>&1)
  return [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = @($output | ForEach-Object { [string]$_ })
  }
}

function Get-TestCompilerLog {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
    return @()
  }
  return @(Get-Content -LiteralPath $Path | ForEach-Object { $_ | ConvertFrom-Json })
}

New-Item -ItemType Directory -Force -Path $fixtureRoot, $installedSourceRoot | Out-Null
try {
  Write-TestText -Path $flagsPath -Text 'fixture flags'
  Write-TestText `
    -Path (Join-Path $installedSourceRoot 'Venworks\Core\Base\BaseQuest.psc') `
    -Text 'ScriptName Venworks:Core:Base:BaseQuest'

  $fakeCompiler = @'
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($args.Count -lt 1) { throw 'Fake compiler did not receive a source path.' }
$sourcePath = [System.IO.Path]::GetFullPath([string]$args[0])
$outputArguments = @($args | Where-Object { [string]$_ -like '-output=*' })
$importArguments = @($args | Where-Object { [string]$_ -like '-import=*' })
if ($outputArguments.Count -ne 1 -or $importArguments.Count -ne 1) {
  throw 'Fake compiler requires exactly one output and import argument.'
}

$sourceRoot = [System.IO.Path]::GetFullPath($env:VWCANVAS_TEST_SOURCE_ROOT)
$relativeSource = [System.IO.Path]::GetRelativePath($sourceRoot, $sourcePath)
$outputRoot = [System.IO.Path]::GetFullPath(([string]$outputArguments[0]).Substring(8))
$importPaths = @(([string]$importArguments[0]).Substring(8).Split(';') | ForEach-Object {
  [System.IO.Path]::GetFullPath($_)
})
$logEntry = [ordered]@{
  Source = $relativeSource.Replace('\', '/')
  OutputRoot = $outputRoot
  Imports = $importPaths
  Arguments = @($args | ForEach-Object { [string]$_ })
}
[System.IO.File]::AppendAllText(
  $env:VWCANVAS_TEST_COMPILER_LOG,
  (($logEntry | ConvertTo-Json -Compress) + [Environment]::NewLine),
  [System.Text.UTF8Encoding]::new($false)
)

if ($env:VWCANVAS_TEST_COMPILER_MODE -ceq 'Fail') {
  Set-Variable -Name LASTEXITCODE -Value 23 -Scope 1
  return
}
if ($env:VWCANVAS_TEST_COMPILER_MODE -ceq 'Missing') {
  Set-Variable -Name LASTEXITCODE -Value 0 -Scope 1
  return
}
if ($env:VWCANVAS_TEST_COMPILER_MODE -cne 'Success') {
  throw "Unknown fake compiler mode '$env:VWCANVAS_TEST_COMPILER_MODE'."
}

$outputRelativePath = [System.IO.Path]::ChangeExtension($relativeSource, '.pex')
$outputPath = Join-Path $outputRoot $outputRelativePath
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outputPath)) | Out-Null
[System.IO.File]::WriteAllText(
  $outputPath,
  "compiled:$($relativeSource.Replace('\', '/'))",
  [System.Text.UTF8Encoding]::new($false)
)
Set-Variable -Name LASTEXITCODE -Value 0 -Scope 1
'@
  Write-TestText -Path $fakeCompilerPath -Text ($fakeCompiler + [Environment]::NewLine)

  $overlapProbePath = Join-Path $fixtureRoot 'test-overlapping-namespaces.ps1'
  $overlapProbe = @'
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$SharedVariantsPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. $SharedVariantsPath

$Global:ModuleVariants = @(
  [pscustomobject]@{ VariantKey = 'PARENT'; PapyrusNamespace = 'Venworks:Owned' }
  [pscustomobject]@{ VariantKey = 'CHILD'; PapyrusNamespace = 'Venworks:Owned:Child' }
)
Get-ModuleVariants -VariantKeys 'CHILD' | Out-Null
'@
  Write-TestText -Path $overlapProbePath -Text ($overlapProbe + [Environment]::NewLine)
  $overlapOutput = @(& $powerShellPath -NoProfile -File $overlapProbePath -SharedVariantsPath $sharedVariantsPath 2>&1)
  if ($LASTEXITCODE -eq 0 -or [string]::Join(' | ', @($overlapOutput | ForEach-Object { [string]$_ })) -notmatch 'overlap') {
    throw "Selecting a child key did not reject overlapping configured Papyrus namespaces: $([string]::Join(' | ', @($overlapOutput | ForEach-Object { [string]$_ })))"
  }

  $selectedRelativeOutput = 'Venworks\CanvasExamples\ExampleRegistrar.pex'
  $unselectedRelativeOutput = 'Venworks\Canvas\Registry.pex'

  $successOutputDirectory = Join-Path $fixtureRoot 'success-output'
  $successSelectedPath = Join-Path $successOutputDirectory $selectedRelativeOutput
  $successUnselectedPath = Join-Path $successOutputDirectory $unselectedRelativeOutput
  $successEnvironmentPath = Join-Path $fixtureRoot 'success.env'
  $successLogPath = Join-Path $fixtureRoot 'success.log'
  Write-TestText -Path $successSelectedPath -Text 'stale selected bytes'
  Write-TestText -Path $successUnselectedPath -Text 'preserved unselected bytes'
  New-TestEnvironment -Path $successEnvironmentPath -Mode 'Success' -LogPath $successLogPath

  $success = Invoke-TestCompile `
    -VariantKey 'EXAMPLE' `
    -EnvironmentPath $successEnvironmentPath `
    -OutputDirectory $successOutputDirectory
  if ($success.ExitCode -ne 0) {
    throw "Selected EXAMPLE compile failed: $([string]::Join(' | ', $success.Output))"
  }
  Assert-TestText `
    -Path $successSelectedPath `
    -Expected 'compiled:Venworks/CanvasExamples/ExampleRegistrar.psc' `
    -Description 'Selected EXAMPLE output'
  Assert-TestText `
    -Path $successUnselectedPath `
    -Expected 'preserved unselected bytes' `
    -Description 'Unselected CANVAS output'

  $successLog = @(Get-TestCompilerLog -Path $successLogPath)
  if ($successLog.Count -ne 1 -or [string]$successLog[0].Source -cne 'Venworks/CanvasExamples/ExampleRegistrar.psc') {
    throw 'EXAMPLE selection did not compile exactly its discovered Papyrus namespace source.'
  }
  $actualImports = @($successLog[0].Imports | ForEach-Object { [System.IO.Path]::GetFullPath([string]$_) })
  $expectedImports = @(
    [System.IO.Path]::GetFullPath($canvasSourceRoot)
    [System.IO.Path]::GetFullPath($installedSourceRoot)
  )
  if ($actualImports.Count -ne 2 -or
      [string]$actualImports[0] -cne [string]$expectedImports[0] -or
      [string]$actualImports[1] -cne [string]$expectedImports[1]) {
    throw "Compiler imports were not exactly Canvas plus installed sources: $([string]::Join(';', $actualImports))"
  }
  $candidateOutputRoot = [System.IO.Path]::GetFullPath([string]$successLog[0].OutputRoot)
  $workRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot '.work\canvas'))
  if (!$candidateOutputRoot.StartsWith(
      $workRoot + [System.IO.Path]::DirectorySeparatorChar,
      [System.StringComparison]::OrdinalIgnoreCase) -or
      $candidateOutputRoot -ceq [System.IO.Path]::GetFullPath($successOutputDirectory) -or
      (Test-Path -LiteralPath $candidateOutputRoot)) {
    throw 'Selected output was not compiled in a fresh, cleaned Canvas work candidate.'
  }

  $failureOutputDirectory = Join-Path $fixtureRoot 'failure-output'
  $failureSelectedPath = Join-Path $failureOutputDirectory $selectedRelativeOutput
  $failureUnselectedPath = Join-Path $failureOutputDirectory $unselectedRelativeOutput
  $failureEnvironmentPath = Join-Path $fixtureRoot 'failure.env'
  $failureLogPath = Join-Path $fixtureRoot 'failure.log'
  Write-TestText -Path $failureSelectedPath -Text 'selected bytes before compiler failure'
  Write-TestText -Path $failureUnselectedPath -Text 'unselected bytes before compiler failure'
  New-TestEnvironment -Path $failureEnvironmentPath -Mode 'Fail' -LogPath $failureLogPath

  $failure = Invoke-TestCompile `
    -VariantKey 'EXAMPLE' `
    -EnvironmentPath $failureEnvironmentPath `
    -OutputDirectory $failureOutputDirectory
  if ($failure.ExitCode -eq 0 -or [string]::Join(' | ', $failure.Output) -notmatch 'exit code 23') {
    throw "Compiler exit 23 was not reported: $([string]::Join(' | ', $failure.Output))"
  }
  Assert-TestText `
    -Path $failureSelectedPath `
    -Expected 'selected bytes before compiler failure' `
    -Description 'Selected output after compiler failure'
  Assert-TestText `
    -Path $failureUnselectedPath `
    -Expected 'unselected bytes before compiler failure' `
    -Description 'Unselected output after compiler failure'

  $missingOutputDirectory = Join-Path $fixtureRoot 'missing-output'
  $missingSelectedPath = Join-Path $missingOutputDirectory $selectedRelativeOutput
  $missingEnvironmentPath = Join-Path $fixtureRoot 'missing.env'
  $missingLogPath = Join-Path $fixtureRoot 'missing.log'
  Write-TestText -Path $missingSelectedPath -Text 'selected bytes before missing output'
  New-TestEnvironment -Path $missingEnvironmentPath -Mode 'Missing' -LogPath $missingLogPath

  $missing = Invoke-TestCompile `
    -VariantKey 'EXAMPLE' `
    -EnvironmentPath $missingEnvironmentPath `
    -OutputDirectory $missingOutputDirectory
  if ($missing.ExitCode -eq 0 -or [string]::Join(' | ', $missing.Output) -notmatch 'did not produce a fresh output') {
    throw "Missing compiler output was not rejected: $([string]::Join(' | ', $missing.Output))"
  }
  Assert-TestText `
    -Path $missingSelectedPath `
    -Expected 'selected bytes before missing output' `
    -Description 'Selected output after missing compiler output'

  if ($IsWindows) {
    $stagingProbePath = Join-Path $fixtureRoot 'invoke-staging-compile.ps1'
    $sharedBuildPath = Join-Path $PSScriptRoot 'sharedBuild.ps1'
    $stagingProbe = @'
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$CompileScriptPath,
  [Parameter(Mandatory = $true)][string]$SharedBuildPath,
  [Parameter(Mandatory = $true)][string]$EnvironmentPath,
  [Parameter(Mandatory = $true)][string]$WorkRoot,
  [Parameter(Mandatory = $true)][string]$PapyrusSourceRoot,
  [Parameter(Mandatory = $true)][string]$SelectedStagingPath,
  [Parameter(Mandatory = $true)][string]$UnselectedStagingPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. $SharedBuildPath
Import-BuildEnvironment -Path $EnvironmentPath
$Global:BuildSettings = @{ WorkRoot = $WorkRoot; PapyrusSourceRoot = $PapyrusSourceRoot }
$Global:ModuleVariants = @(
  [pscustomobject]@{ VariantKey = 'EXAMPLE'; PapyrusNamespace = 'Venworks:CanvasExamples'; StagingFolderPath = $SelectedStagingPath; EnvironmentVariableName = 'TEST_SELECTED_STAGE_PATH' }
  [pscustomobject]@{ VariantKey = 'CANVAS'; PapyrusNamespace = 'Venworks:Canvas'; StagingFolderPath = $UnselectedStagingPath; EnvironmentVariableName = 'TEST_UNSELECTED_STAGE_PATH' }
)
$Global:SharedConfigurationLoaded = $true
& $CompileScriptPath -VariantKeys 'EXAMPLE' -EnvironmentPath $EnvironmentPath
'@
    Write-TestText -Path $stagingProbePath -Text ($stagingProbe + [Environment]::NewLine)
    $selectedTarget = Join-Path $fixtureRoot 'selected-installed'
    $unselectedTarget = Join-Path $fixtureRoot 'unselected-installed'
    $selectedStaging = Join-Path $fixtureRoot 'selected-staging'
    $unselectedStaging = Join-Path $fixtureRoot 'unselected-staging'
    $stagingWorkRoot = Join-Path $fixtureRoot 'staging-work'
    New-Item -ItemType Directory -Path $selectedTarget, $unselectedTarget, $stagingWorkRoot | Out-Null
    New-Item -ItemType Junction -Path $selectedStaging -Target $selectedTarget | Out-Null
    New-Item -ItemType Junction -Path $unselectedStaging -Target $unselectedTarget | Out-Null

    $stagedSelectedPath = Join-Path (Join-Path $selectedTarget 'Scripts') $selectedRelativeOutput
    $stagedUnselectedPath = Join-Path (Join-Path $unselectedTarget 'Scripts') $unselectedRelativeOutput
    $unrelatedStagedPath = Join-Path $selectedTarget 'Interface/unrelated.swf'
    Write-TestText -Path $stagedSelectedPath -Text 'stale selected staged bytes'
    Write-TestText -Path $stagedUnselectedPath -Text 'preserved unselected staged bytes'
    Write-TestText -Path $unrelatedStagedPath -Text 'preserved unrelated staged bytes'
    $stagingSuccessEnvironment = Join-Path $fixtureRoot 'staging-success.env'
    $stagingSuccessLog = Join-Path $fixtureRoot 'staging-success.log'
    New-TestEnvironment -Path $stagingSuccessEnvironment -Mode 'Success' -LogPath $stagingSuccessLog
    [IO.File]::AppendAllText($stagingSuccessEnvironment, "TEST_SELECTED_STAGE_PATH=$selectedTarget$([Environment]::NewLine)TEST_UNSELECTED_STAGE_PATH=$unselectedTarget$([Environment]::NewLine)", [Text.UTF8Encoding]::new($false))

    $stagingSuccessOutput = @(& $powerShellPath -NoProfile -File $stagingProbePath -CompileScriptPath $compileScriptPath -SharedBuildPath $sharedBuildPath -EnvironmentPath $stagingSuccessEnvironment -WorkRoot $stagingWorkRoot -PapyrusSourceRoot $canvasSourceRoot -SelectedStagingPath $selectedStaging -UnselectedStagingPath $unselectedStaging 2>&1)
    if ($LASTEXITCODE -ne 0) {
      throw "Default staged EXAMPLE compile failed: $([string]::Join(' | ', @($stagingSuccessOutput | ForEach-Object { [string]$_ })))"
    }
    Assert-TestText -Path $stagedSelectedPath -Expected 'compiled:Venworks/CanvasExamples/ExampleRegistrar.psc' -Description 'Default staged EXAMPLE output'
    Assert-TestText -Path $stagedUnselectedPath -Expected 'preserved unselected staged bytes' -Description 'Unselected staged CANVAS output'
    Assert-TestText -Path $unrelatedStagedPath -Expected 'preserved unrelated staged bytes' -Description 'Unrelated staged asset'

    Write-TestText -Path $stagedSelectedPath -Text 'selected staged bytes before compiler failure'
    $stagingFailureEnvironment = Join-Path $fixtureRoot 'staging-failure.env'
    $stagingFailureLog = Join-Path $fixtureRoot 'staging-failure.log'
    New-TestEnvironment -Path $stagingFailureEnvironment -Mode 'Fail' -LogPath $stagingFailureLog
    [IO.File]::AppendAllText($stagingFailureEnvironment, "TEST_SELECTED_STAGE_PATH=$selectedTarget$([Environment]::NewLine)TEST_UNSELECTED_STAGE_PATH=$unselectedTarget$([Environment]::NewLine)", [Text.UTF8Encoding]::new($false))
    $stagingFailureOutput = @(& $powerShellPath -NoProfile -File $stagingProbePath -CompileScriptPath $compileScriptPath -SharedBuildPath $sharedBuildPath -EnvironmentPath $stagingFailureEnvironment -WorkRoot $stagingWorkRoot -PapyrusSourceRoot $canvasSourceRoot -SelectedStagingPath $selectedStaging -UnselectedStagingPath $unselectedStaging 2>&1)
    if ($LASTEXITCODE -eq 0 -or [string]::Join(' | ', @($stagingFailureOutput | ForEach-Object { [string]$_ })) -notmatch 'exit code 23') {
      throw "Default staged compiler failure was not reported: $([string]::Join(' | ', @($stagingFailureOutput | ForEach-Object { [string]$_ })))"
    }
    Assert-TestText -Path $stagedSelectedPath -Expected 'selected staged bytes before compiler failure' -Description 'Default staged output after compiler failure'
    Assert-TestText -Path $stagedUnselectedPath -Expected 'preserved unselected staged bytes' -Description 'Unselected staged output after selected compiler failure'
    Assert-TestText -Path $unrelatedStagedPath -Expected 'preserved unrelated staged bytes' -Description 'Unrelated staged asset after compiler failure'
  }
  else {
    Write-Output 'SKIP: default Papyrus staging publication requires Windows Junction support.'
  }
}
finally {
  if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
    $resolvedFixtureRoot = [System.IO.Path]::GetFullPath($fixtureRoot)
    $resolvedTestBase = [System.IO.Path]::GetFullPath($testBase)
    if (!$resolvedFixtureRoot.StartsWith(
        $resolvedTestBase + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove Papyrus test fixture outside $resolvedTestBase."
    }
    Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
  }
}

Write-Output 'Papyrus selected-build tests passed: namespace-derived selection, overlapping-namespace rejection before filtering, installed-source imports, explicit alternative output, default guarded staging publication, compiler and missing-output failures, and selected/unselected byte preservation.'
