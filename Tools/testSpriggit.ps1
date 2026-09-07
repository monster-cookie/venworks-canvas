<#
.SYNOPSIS
Exercises Canvas Spriggit routing and failure behavior against a stub CLI in an isolated repository fixture.
#>
[CmdletBinding()]
param()

$PSNativeCommandUseErrorActionPreference = $false
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testWorkRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot '.work\canvas\authoring-remediation-tests'))
$fixtureRoot = Join-Path $testWorkRoot ('spriggit-' + [guid]::NewGuid().ToString('N'))
$fixtureRepository = Join-Path $fixtureRoot 'repository'
$fixtureTools = Join-Path $fixtureRepository 'Tools'
$stubRoot = Join-Path $fixtureRoot 'stub'
$stubPath = Join-Path $stubRoot 'Spriggit.CLI.ps1'
$stubLog = Join-Path $fixtureRoot 'spriggit-calls.jsonl'
$environmentPath = Join-Path $fixtureRepository '.env'
$powerShellPath = (Get-Process -Id $PID).Path

function Assert-TestCondition {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$Condition,

    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  if (!$Condition) {
    throw $Message
  }
}

function Write-TestText {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text
  )

  $parent = Split-Path -Parent $Path
  if (!(Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Set-TestEnvironment {
  param([string]$FailOperation = '')

  $lines = @(
    "TOOL_PATH_SPRIGGIT=$stubPath"
    'SPRIGGIT_VERSION=0.40.1'
    "STEAM_DATA_FOLDER=$(Join-Path $fixtureRoot 'starfield-data')"
    "SPRIGGIT_STUB_LOG=$stubLog"
  )
  if (![string]::IsNullOrWhiteSpace($FailOperation)) {
    $lines += "SPRIGGIT_STUB_FAIL_OPERATION=$FailOperation"
  }
  Write-TestText -Path $environmentPath -Text ([string]::Join("`n", $lines) + "`n")
}

function Invoke-ChildScript {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,

    [string[]]$ArgumentList = @()
  )

  $output = @(& $powerShellPath -NoProfile -File $ScriptPath @ArgumentList 2>&1 | ForEach-Object { [string]$_ })
  return [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = $output
  }
}

function Assert-ChildSuccess {
  param(
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Result,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  if ($Result.ExitCode -ne 0) {
    throw "$Description failed with exit code $($Result.ExitCode): $([string]::Join([Environment]::NewLine, $Result.Output))"
  }
}

function Get-TestCalls {
  if (!(Test-Path -LiteralPath $stubLog -PathType Leaf)) {
    return @()
  }
  return @(Get-Content -LiteralPath $stubLog | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Get-ArgumentValue {
  param(
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Call,

    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $arguments = @($Call.Arguments | ForEach-Object { [string]$_ })
  $index = [Array]::IndexOf($arguments, $Name)
  if ($index -lt 0 -or $index + 1 -ge $arguments.Count) {
    throw "Stub call lacks argument '$Name'."
  }
  return $arguments[$index + 1]
}

function Get-TestDirectoryDigest {
  param([Parameter(Mandatory = $true)][string]$Path)

  $rows = @(Get-ChildItem -LiteralPath $Path -Recurse -File | ForEach-Object {
    $relativePath = [System.IO.Path]::GetRelativePath($Path, $_.FullName).Replace('\', '/')
    "$relativePath`:$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
  } | Sort-Object)
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes([string]::Join("`n", $rows))
  return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))
}

function Assert-SafeFixturePath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $fullRoot = $testWorkRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  if (!$fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing fixture cleanup outside the authoring test root: $fullPath"
  }
}

New-Item -ItemType Directory -Force -Path $fixtureTools, $stubRoot, (Join-Path $fixtureRoot 'starfield-data') | Out-Null
foreach ($fileName in @('sharedConfig.ps1', 'sharedCanvas.ps1', 'sharedCanvasBuildEvidence.ps1', 'sharedCanvasPackaging.ps1', 'SpriggitDumpDatabaseToYaml.ps1', 'SpriggitAssembleDatabaseFromYaml.ps1')) {
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination (Join-Path $fixtureTools $fileName)
}

$stubSource = @'
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$cliArguments = @($args)
$operation = if ($cliArguments.Count -gt 0) { [string]$cliArguments[0] } else { '' }
$record = [ordered]@{ Operation = $operation; Arguments = @($cliArguments | ForEach-Object { [string]$_ }) }
[System.IO.File]::AppendAllText($env:SPRIGGIT_STUB_LOG, (($record | ConvertTo-Json -Compress) + "`n"), [System.Text.UTF8Encoding]::new($false))
if ([string]$env:SPRIGGIT_STUB_FAIL_OPERATION -ceq $operation) {
  $global:LASTEXITCODE = 23
  return
}

function Get-StubArgument {
  param([string]$Name)
  $index = [Array]::IndexOf([object[]]$script:cliArguments, $Name)
  if ($index -lt 0 -or $index + 1 -ge $script:cliArguments.Count) { throw "Missing stub argument: $Name" }
  return [string]$script:cliArguments[$index + 1]
}

switch ($operation) {
  'serialize' {
    $inputPath = Get-StubArgument -Name '--InputPath'
    $outputPath = Get-StubArgument -Name '--OutputPath'
    New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $outputPath 'RecordData.yaml'), "SerializedInput: $([System.IO.Path]::GetFileName($inputPath))`n", [System.Text.UTF8Encoding]::new($false))
  }
  'deserialize' {
    $inputPath = Get-StubArgument -Name '--InputPath'
    $outputPath = Get-StubArgument -Name '--OutputPath'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath) | Out-Null
    [System.IO.File]::WriteAllText($outputPath, "AssembledInput: $([System.IO.Path]::GetFileName($inputPath))`n", [System.Text.UTF8Encoding]::new($false))
  }
  default { throw "Unexpected stub operation: $operation" }
}
$global:LASTEXITCODE = 0
'@
Write-TestText -Path $stubPath -Text $stubSource
Set-TestEnvironment

$variants = @(
  @{ Key = 'CANVAS'; BaseName = 'Venworks-Canvas'; Staging = 'Staging-Canvas' }
  @{ Key = 'EXAMPLE'; BaseName = 'Venworks-Canvas-Example'; Staging = 'Staging-Example' }
  @{ Key = 'COMPONENTGALLERY'; BaseName = 'Venworks-Canvas-ComponentGallery'; Staging = 'Staging-ComponentGallery' }
)
foreach ($variant in $variants) {
  $esmPath = Join-Path $fixtureRepository "$($variant.Staging)\$($variant.BaseName).esm"
  Write-TestText -Path $esmPath -Text "fixture $($variant.Key)`n"
}

$dumpScript = Join-Path $fixtureTools 'SpriggitDumpDatabaseToYaml.ps1'
$assembleScript = Join-Path $fixtureTools 'SpriggitAssembleDatabaseFromYaml.ps1'

try {
  $result = Invoke-ChildScript -ScriptPath $dumpScript -ArgumentList @('-EnvironmentPath', $environmentPath)
  Assert-ChildSuccess -Result $result -Description 'All-variant Spriggit serialization'
  $serializeCalls = @(Get-TestCalls | Where-Object { $_.Operation -ceq 'serialize' })
  Assert-TestCondition ($serializeCalls.Count -eq 3) 'Expected three serialize calls.'
  foreach ($variant in $variants) {
    $fileName = "$($variant.BaseName).esm"
    $call = @($serializeCalls | Where-Object { (Get-ArgumentValue -Call $_ -Name '--InputPath') -ceq (Join-Path $fixtureRepository "$($variant.Staging)\$fileName") })
    Assert-TestCondition ($call.Count -eq 1) "Expected one serialize call for $fileName."
    Assert-TestCondition ((Get-ArgumentValue -Call $call[0] -Name '--OutputPath') -ceq (Join-Path $fixtureRepository "Spriggit\$fileName")) "Unexpected YAML route for $fileName."
    Assert-TestCondition ((Get-ArgumentValue -Call $call[0] -Name '--PackageVersion') -ceq '0.40.1') "Unexpected package version for $fileName."
    Assert-TestCondition ((Get-ArgumentValue -Call $call[0] -Name '--GameRelease') -ceq 'Starfield') "Unexpected game release for $fileName."
    Assert-TestCondition ((Get-ArgumentValue -Call $call[0] -Name '--PackageName') -ceq 'Spriggit.Yaml') "Unexpected package name for $fileName."
    Assert-TestCondition ((Get-ArgumentValue -Call $call[0] -Name '--DataFolder') -ceq (Join-Path $fixtureRoot 'starfield-data')) "Unexpected data folder for $fileName."
    Assert-TestCondition (@($call[0].Arguments) -contains '--Check') "Serialize call for $fileName omitted --Check."
  }

  $exampleYaml = Join-Path $fixtureRepository 'Spriggit\Venworks-Canvas-Example.esm'
  Write-TestText -Path (Join-Path $exampleYaml 'local-edit.yaml') -Text "preserve local edit`n"
  $exampleDigest = Get-TestDirectoryDigest -Path $exampleYaml
  $result = Invoke-ChildScript -ScriptPath $dumpScript -ArgumentList @('-VariantKeys', 'CANVAS', '-EnvironmentPath', $environmentPath)
  Assert-ChildSuccess -Result $result -Description 'Single-variant Spriggit serialization'
  Assert-TestCondition ((Get-TestDirectoryDigest -Path $exampleYaml) -ceq $exampleDigest) 'Single-variant serialization changed an unselected YAML tree.'

  $canvasEsm = Join-Path $fixtureRepository 'Staging-Canvas\Venworks-Canvas.esm'
  $canvasYaml = Join-Path $fixtureRepository 'Spriggit\Venworks-Canvas.esm'
  $canvasDigest = Get-TestDirectoryDigest -Path $canvasYaml
  $callCountBeforeSkip = @(Get-TestCalls).Count
  Remove-Item -LiteralPath $canvasEsm -Force
  $result = Invoke-ChildScript -ScriptPath $dumpScript -ArgumentList @('-VariantKeys', 'CANVAS', '-EnvironmentPath', $environmentPath)
  Assert-ChildSuccess -Result $result -Description 'Missing-input Spriggit serialization'
  Assert-TestCondition (@($result.Output | Where-Object { $_ -match '1 skipped' }).Count -gt 0) 'Missing staged ESM was not reported as skipped.'
  Assert-TestCondition (@(Get-TestCalls).Count -eq $callCountBeforeSkip) 'Missing staged ESM invoked the Spriggit CLI.'
  Assert-TestCondition ((Get-TestDirectoryDigest -Path $canvasYaml) -ceq $canvasDigest) 'Missing staged ESM changed existing YAML.'

  $retainedBackup = Join-Path $fixtureRepository '.work\canvas\spriggit-yaml-backups\Production\retained.txt'
  $retainedCandidate = Join-Path $fixtureRepository '.work\canvas\spriggit-yaml-candidates\Production\retained.txt'
  Write-TestText -Path $retainedBackup -Text "retained backup`n"
  Write-TestText -Path $retainedCandidate -Text "retained candidate`n"
  $backupHash = (Get-FileHash -LiteralPath $retainedBackup -Algorithm SHA256).Hash
  $candidateHash = (Get-FileHash -LiteralPath $retainedCandidate -Algorithm SHA256).Hash
  Write-TestText -Path $canvasEsm -Text "fixture CANVAS failure`n"
  Set-TestEnvironment -FailOperation 'serialize'
  $result = Invoke-ChildScript -ScriptPath $dumpScript -ArgumentList @('-VariantKeys', 'CANVAS', '-EnvironmentPath', $environmentPath)
  Assert-TestCondition ($result.ExitCode -ne 0) 'Serializer nonzero exit was accepted.'
  Assert-TestCondition (@($result.Output | Where-Object { $_ -match 'exit code 23' }).Count -gt 0) 'Serializer failure omitted its exit code.'
  Assert-TestCondition (((Get-FileHash -LiteralPath $retainedBackup -Algorithm SHA256).Hash) -ceq $backupHash) 'Serializer failure changed a retained recovery backup.'
  Assert-TestCondition (((Get-FileHash -LiteralPath $retainedCandidate -Algorithm SHA256).Hash) -ceq $candidateHash) 'Serializer failure changed an old candidate directory.'
  Assert-TestCondition ((Get-TestDirectoryDigest -Path $exampleYaml) -ceq $exampleDigest) 'Serializer failure changed an unrelated YAML tree.'

  Set-TestEnvironment
  $result = Invoke-ChildScript -ScriptPath $dumpScript -ArgumentList @('-VariantKeys', 'CANVAS', '-EnvironmentPath', $environmentPath)
  Assert-ChildSuccess -Result $result -Description 'Repeated Spriggit serialization'
  Assert-TestCondition (((Get-FileHash -LiteralPath $retainedBackup -Algorithm SHA256).Hash) -ceq $backupHash) 'Repeated serialization removed a retained recovery backup.'

  foreach ($variant in $variants) {
    $esmPath = Join-Path $fixtureRepository "$($variant.Staging)\$($variant.BaseName).esm"
    if (Test-Path -LiteralPath $esmPath) { Remove-Item -LiteralPath $esmPath -Force }
  }
  $result = Invoke-ChildScript -ScriptPath $assembleScript -ArgumentList @('-EnvironmentPath', $environmentPath)
  Assert-ChildSuccess -Result $result -Description 'All-variant isolated Spriggit assembly'
  $deserializeCalls = @(Get-TestCalls | Where-Object { $_.Operation -ceq 'deserialize' })
  Assert-TestCondition ($deserializeCalls.Count -eq 3) 'Expected three deserialize calls.'
  foreach ($variant in $variants) {
    $fileName = "$($variant.BaseName).esm"
    $expectedInput = Join-Path $fixtureRepository "Spriggit\$fileName"
    $call = @($deserializeCalls | Where-Object { (Get-ArgumentValue -Call $_ -Name '--InputPath') -ceq $expectedInput })
    Assert-TestCondition ($call.Count -eq 1) "Expected one deserialize call for $fileName."
    Assert-TestCondition ((Get-ArgumentValue -Call $call[0] -Name '--OutputPath') -ceq (Join-Path $fixtureRepository "$($variant.Staging)\$fileName")) "Unexpected assembly route for $fileName."
    Assert-TestCondition ((Get-ArgumentValue -Call $call[0] -Name '--DataFolder') -ceq (Join-Path $fixtureRoot 'starfield-data')) "Unexpected assembly data folder for $fileName."
  }

  $exampleEsm = Join-Path $fixtureRepository 'Staging-Example\Venworks-Canvas-Example.esm'
  Write-TestText -Path $exampleEsm -Text "preserve assembled local edit`n"
  $exampleEsmHash = (Get-FileHash -LiteralPath $exampleEsm -Algorithm SHA256).Hash
  $result = Invoke-ChildScript -ScriptPath $assembleScript -ArgumentList @('-VariantKeys', 'CANVAS', '-EnvironmentPath', $environmentPath)
  Assert-ChildSuccess -Result $result -Description 'Single-variant isolated Spriggit assembly'
  Assert-TestCondition (((Get-FileHash -LiteralPath $exampleEsm -Algorithm SHA256).Hash) -ceq $exampleEsmHash) 'Single-variant assembly changed an unselected staged ESM.'

  $componentYaml = Join-Path $fixtureRepository 'Spriggit\Venworks-Canvas-ComponentGallery.esm'
  $componentEsm = Join-Path $fixtureRepository 'Staging-ComponentGallery\Venworks-Canvas-ComponentGallery.esm'
  $componentEsmHash = (Get-FileHash -LiteralPath $componentEsm -Algorithm SHA256).Hash
  Remove-Item -LiteralPath $componentYaml -Recurse -Force
  $callCountBeforeSkip = @(Get-TestCalls).Count
  $result = Invoke-ChildScript -ScriptPath $assembleScript -ArgumentList @('-VariantKeys', 'COMPONENTGALLERY', '-EnvironmentPath', $environmentPath)
  Assert-ChildSuccess -Result $result -Description 'Missing-input isolated Spriggit assembly'
  Assert-TestCondition (@($result.Output | Where-Object { $_ -match '1 skipped' }).Count -gt 0) 'Missing YAML input was not reported as skipped.'
  Assert-TestCondition (@(Get-TestCalls).Count -eq $callCountBeforeSkip) 'Missing YAML input invoked the Spriggit CLI.'
  Assert-TestCondition (((Get-FileHash -LiteralPath $componentEsm -Algorithm SHA256).Hash) -ceq $componentEsmHash) 'Missing YAML input changed the staged ESM.'

  Set-TestEnvironment -FailOperation 'deserialize'
  $result = Invoke-ChildScript -ScriptPath $assembleScript -ArgumentList @('-VariantKeys', 'CANVAS', '-EnvironmentPath', $environmentPath)
  Assert-TestCondition ($result.ExitCode -ne 0) 'Assembler nonzero exit was accepted.'
  Assert-TestCondition (@($result.Output | Where-Object { $_ -match 'exit code 23' }).Count -gt 0) 'Assembler failure omitted its exit code.'
  Assert-TestCondition (((Get-FileHash -LiteralPath $exampleEsm -Algorithm SHA256).Hash) -ceq $exampleEsmHash) 'Assembler failure changed an unrelated staged ESM.'

  $result = Invoke-ChildScript -ScriptPath $dumpScript -ArgumentList @('-Profile', 'Faults')
  Assert-TestCondition ($result.ExitCode -ne 0) 'Retired -Profile parameter was accepted.'
  $result = Invoke-ChildScript -ScriptPath $assembleScript -ArgumentList @('-PluginsDirectory', (Join-Path $fixtureRoot 'plugins'))
  Assert-TestCondition ($result.ExitCode -ne 0) 'Retired -PluginsDirectory parameter was accepted.'
  Assert-TestCondition (!(Test-Path -LiteralPath (Join-Path $fixtureRepository 'Spriggit\Production'))) 'Serialization recreated the retired Production profile.'
  Assert-TestCondition (!(Test-Path -LiteralPath (Join-Path $fixtureRepository 'Spriggit\Faults'))) 'Serialization created a normal Faults profile.'

  Write-Output 'Spriggit authoring tests passed: three-ESM and single-ESM routing, template flags, skipped inputs, CLI failures, repeated runs, retained recovery material, retired parameters, and isolated assembly.'
}
finally {
  if (Test-Path -LiteralPath $fixtureRoot) {
    Assert-SafeFixturePath -Path $fixtureRoot
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}
