<#
.SYNOPSIS
Exercises the reusable build configuration, environment, and Papyrus source contracts.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-TestCondition {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if (!$Condition) {
    throw $Message
  }
}

function Write-TestText {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
  )

  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
  [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Write-TestBa2 {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$ArchiveType,
    [Parameter(Mandatory = $true)][uint64]$NameOffset
  )

  $length = [Math]::Max(80, [int]$NameOffset + 2)
  $bytes = [byte[]]::new($length)
  [Array]::Copy([Text.Encoding]::ASCII.GetBytes('BTDX'), 0, $bytes, 0, 4)
  [Array]::Copy([BitConverter]::GetBytes([uint32]2), 0, $bytes, 4, 4)
  [Array]::Copy([Text.Encoding]::ASCII.GetBytes($ArchiveType), 0, $bytes, 8, 4)
  [Array]::Copy([BitConverter]::GetBytes([uint32]1), 0, $bytes, 12, 4)
  [Array]::Copy([BitConverter]::GetBytes($NameOffset), 0, $bytes, 16, 8)
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
  [IO.File]::WriteAllBytes($Path, $bytes)
}

if ($null -eq (Get-Command -Name Get-BuildPapyrusSources -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'sharedBuild.ps1')
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testBase = Join-Path $repositoryRoot '.work\build-pipeline-tests'
$fixtureRoot = Join-Path $testBase ('foundation-' + [guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $fixtureRoot 'Papyrus'
$environmentPath = Join-Path $fixtureRoot 'quoted.env'
$invalidEnvironmentPath = Join-Path $fixtureRoot 'invalid.env'
$environmentNames = @(
  'VENWORKS_BUILD_TEST_PLAIN',
  'VENWORKS_BUILD_TEST_DOUBLE',
  'VENWORKS_BUILD_TEST_SINGLE',
  'VENWORKS_BUILD_TEST_INSTALL'
)
$savedEnvironment = @{}
foreach ($environmentName in $environmentNames) {
  $savedEnvironment[$environmentName] = [Environment]::GetEnvironmentVariable($environmentName, 'Process')
}
$buildSettingsVariable = Get-Variable -Name BuildSettings -Scope Global -ErrorAction SilentlyContinue
$moduleVariantsVariable = Get-Variable -Name ModuleVariants -Scope Global -ErrorAction SilentlyContinue
$hadBuildSettings = $null -ne $buildSettingsVariable
$hadModuleVariants = $null -ne $moduleVariantsVariable
$savedBuildSettings = if ($hadBuildSettings) { $buildSettingsVariable.Value } else { $null }
$savedModuleVariants = if ($hadModuleVariants) { $moduleVariantsVariable.Value } else { $null }

try {
  Write-TestText -Path (Join-Path $sourceRoot 'Venworks\Canvas\Base\BaseQuest.psc') -Text "ScriptName Venworks:Canvas:Base:BaseQuest`n"
  Write-TestText -Path (Join-Path $sourceRoot 'Venworks\Canvas\Registry.psc') -Text "ScriptName Venworks:Canvas:Registry`n"
  Write-TestText -Path (Join-Path $sourceRoot 'Venworks\CanvasExamples\ExampleRegistrar.psc') -Text "ScriptName Venworks:CanvasExamples:ExampleRegistrar`n"
  Write-TestText -Path (Join-Path $sourceRoot 'Venworks\CanvasExtra\Extra.psc') -Text "ScriptName Venworks:CanvasExtra:Extra`n"

  $Global:BuildSettings = @{
    WorkRoot = Join-Path $fixtureRoot 'work'
    PapyrusSourceRoot = $sourceRoot
    ScriptsDirectory = Join-Path $fixtureRoot 'work\scripts'
    ScaleformSourceRoot = Join-Path $fixtureRoot 'Scaleform'
    ScaleformDirectory = Join-Path $fixtureRoot 'work\scaleform'
  }
  $canvasArguments = [object[]]@(
    'CANVAS', 'Canvas', 'Canvas-Authoring.esm', 'Canvas-Archive', 'Venworks:Canvas',
    (Join-Path $fixtureRoot 'Staging-Canvas'), 'VENWORKS_BUILD_TEST_INSTALL', [object[]]@(), [object[]]@()
  )
  $exampleArguments = [object[]]@(
    'EXAMPLE', 'Example', 'Example-Authoring.esm', 'Example-Archive', 'Venworks:CanvasExamples',
    (Join-Path $fixtureRoot 'Staging-Example'), 'VENWORKS_BUILD_TEST_INSTALL', [object[]]@(), [object[]]@()
  )
  $canvasVariant = New-Object -TypeName ModuleVariant -ArgumentList $canvasArguments
  $exampleVariant = New-Object -TypeName ModuleVariant -ArgumentList $exampleArguments
  $Global:ModuleVariants = @($canvasVariant, $exampleVariant)

  $expectedProperties = @(
    'Archives', 'EnvironmentVariableName', 'EsmFileName', 'PackageBaseName', 'PapyrusNamespace',
    'ScaleformBuilds', 'StagingFolderPath', 'VariantKey', 'VariantName'
  )
  $actualProperties = @(([type]'ModuleVariant').GetProperties().Name)
  Assert-BuildExactNames -Actual $actualProperties -Expected $expectedProperties -Description 'ModuleVariant properties'

  $allVariants = @(Get-ModuleVariants)
  Assert-TestCondition ($allVariants.Count -eq 2) 'Default variant selection did not return every configured variant.'
  $selectedVariants = @(Get-ModuleVariants -VariantKeys @(' example ', 'canvas'))
  Assert-TestCondition (
    $selectedVariants.Count -eq 2 -and
    [string]$selectedVariants[0].VariantKey -ceq 'EXAMPLE' -and
    [string]$selectedVariants[1].VariantKey -ceq 'CANVAS'
  ) 'Variant selection did not preserve requested order or case-insensitive matching.'
  foreach ($invalidKeys in @(@('CANVAS', 'canvas'), @('UNKNOWN'), @(''))) {
    $rejected = $false
    try {
      [void](Get-ModuleVariants -VariantKeys $invalidKeys)
    }
    catch {
      $rejected = $true
    }
    Assert-TestCondition $rejected "Invalid variant selection '$($invalidKeys -join ', ')' was accepted."
  }

  $canvasSources = @(Get-BuildPapyrusSources -Variant $canvasVariant)
  $canvasRelativeSources = @($canvasSources.RelativeSource | ForEach-Object { $_.Replace('\', '/') })
  Assert-BuildExactNames `
    -Actual $canvasRelativeSources `
    -Expected @('Venworks/Canvas/Base/BaseQuest.psc', 'Venworks/Canvas/Registry.psc') `
    -Description 'Exact Canvas namespace discovery'
  Assert-TestCondition (@($canvasSources.RelativeOutput | Where-Object { $_ -notlike '*.pex' }).Count -eq 0) 'Papyrus output mappings did not use the PEX extension.'
  Assert-TestCondition (@($canvasRelativeSources | Where-Object { $_ -match 'CanvasExamples|CanvasExtra' }).Count -eq 0) 'Exact Canvas discovery included a sibling namespace.'

  $addedSource = Join-Path $sourceRoot 'Venworks\Canvas\Added.psc'
  Write-TestText -Path $addedSource -Text "ScriptName Venworks:Canvas:Added`n"
  Assert-TestCondition (@(Get-BuildPapyrusSources -Variant $canvasVariant).Count -eq 3) 'A newly added namespace source was not discovered.'
  Remove-Item -LiteralPath $addedSource -Force
  Assert-TestCondition (@(Get-BuildPapyrusSources -Variant $canvasVariant).Count -eq 2) 'A deleted namespace source remained in discovery.'

  $mismatchedSource = Join-Path $sourceRoot 'Venworks\Canvas\Mismatch.psc'
  Write-TestText -Path $mismatchedSource -Text "ScriptName Venworks:Canvas:Different`n"
  $mismatchRejected = $false
  try {
    [void](Get-BuildPapyrusSources -Variant $canvasVariant)
  }
  catch {
    $mismatchRejected = $_.Exception.Message -match 'declares.+instead of'
  }
  Assert-TestCondition $mismatchRejected 'A Papyrus ScriptName that disagreed with its source path was accepted.'
  Remove-Item -LiteralPath $mismatchedSource -Force

  Write-TestText -Path $environmentPath -Text @'
# Values must split only on the first equals sign.
VENWORKS_BUILD_TEST_PLAIN=plain=value
VENWORKS_BUILD_TEST_DOUBLE="C:\Value Folder\double=value"
VENWORKS_BUILD_TEST_SINGLE=' spaced=single value '
'@
  Import-BuildEnvironment -Path $environmentPath
  Assert-TestCondition ($env:VENWORKS_BUILD_TEST_PLAIN -ceq 'plain=value') 'The environment parser truncated an unquoted value containing equals.'
  Assert-TestCondition ($env:VENWORKS_BUILD_TEST_DOUBLE -ceq 'C:\Value Folder\double=value') 'The environment parser changed a double-quoted value containing spaces and equals.'
  Assert-TestCondition ($env:VENWORKS_BUILD_TEST_SINGLE -ceq ' spaced=single value ') 'The environment parser changed a single-quoted value containing spaces and equals.'

  Write-TestText -Path $invalidEnvironmentPath -Text "INVALID ENVIRONMENT ENTRY`n"
  $invalidEnvironmentRejected = $false
  try {
    Import-BuildEnvironment -Path $invalidEnvironmentPath
  }
  catch {
    $invalidEnvironmentRejected = $true
  }
  Assert-TestCondition $invalidEnvironmentRejected 'An invalid environment entry was accepted.'

  $firstInstallPath = Join-Path $fixtureRoot 'Install One'
  $secondInstallPath = Join-Path $fixtureRoot 'Install Two'
  $env:VENWORKS_BUILD_TEST_INSTALL = $firstInstallPath
  Assert-TestCondition (Test-BuildSamePath -Left (Resolve-BuildVariantInstallPath -Variant $canvasVariant) -Right $firstInstallPath) 'The first dynamic variant install path was not resolved.'
  $env:VENWORKS_BUILD_TEST_INSTALL = $secondInstallPath
  Assert-TestCondition (Test-BuildSamePath -Left (Resolve-BuildVariantInstallPath -Variant $canvasVariant) -Right $secondInstallPath) 'The changed dynamic variant install path was not resolved.'
  Assert-TestCondition (Test-BuildOverlappingPaths -Left $fixtureRoot -Right $secondInstallPath) 'Nested paths were not recognized as overlapping.'
  Assert-TestCondition (!(Test-BuildOverlappingPaths -Left $firstInstallPath -Right $secondInstallPath)) 'Sibling paths were incorrectly recognized as overlapping.'

  $generalArchive = Join-Path $fixtureRoot 'general.ba2'
  $textureArchive = Join-Path $fixtureRoot 'textures.ba2'
  $invalidTextureArchive = Join-Path $fixtureRoot 'invalid-textures.ba2'
  Write-TestBa2 -Path $generalArchive -ArchiveType 'GNRL' -NameOffset 68
  Write-TestBa2 -Path $textureArchive -ArchiveType 'DX10' -NameOffset 32
  Write-TestBa2 -Path $invalidTextureArchive -ArchiveType 'DX10' -NameOffset 31
  Assert-BuildArtifactHeader -Path $generalArchive
  Assert-BuildArtifactHeader -Path $textureArchive
  $invalidTextureRejected = $false
  try {
    Assert-BuildArtifactHeader -Path $invalidTextureArchive
  }
  catch {
    $invalidTextureRejected = $true
  }
  Assert-TestCondition $invalidTextureRejected 'A DX10 BA2 with a name table before the minimum offset was accepted.'

  # These fixtures exercise header admission only; they are not complete Scaleform movies.
  $compressedGfx = Join-Path $fixtureRoot 'compressed-header.gfx'
  $shortCompressedGfx = Join-Path $fixtureRoot 'short-compressed-header.gfx'
  $unknownScaleform = Join-Path $fixtureRoot 'unknown-header.gfx'
  [IO.File]::WriteAllBytes($compressedGfx, [byte[]]@(0x43, 0x46, 0x58, 0x0C, 0x08, 0x00, 0x00, 0x00))
  [IO.File]::WriteAllBytes($shortCompressedGfx, [byte[]]@(0x43, 0x46, 0x58, 0x0C, 0x07, 0x00, 0x00))
  [IO.File]::WriteAllBytes($unknownScaleform, [byte[]]@(0x58, 0x59, 0x5A, 0x0C, 0x08, 0x00, 0x00, 0x00))
  [void](Assert-BuildScaleformFile -Path $compressedGfx -Description 'Compressed GFx header fixture')
  $shortScaleformRejected = $false
  try {
    [void](Assert-BuildScaleformFile -Path $shortCompressedGfx -Description 'Short compressed GFx header fixture')
  }
  catch {
    $shortScaleformRejected = $_.Exception.Message -match 'too short'
  }
  Assert-TestCondition $shortScaleformRejected 'A seven-byte CFX header was accepted.'
  $unknownScaleformRejected = $false
  try {
    [void](Assert-BuildScaleformFile -Path $unknownScaleform -Description 'Unknown Scaleform header fixture')
  }
  catch {
    $unknownScaleformRejected = $_.Exception.Message -match "unsupported Scaleform header 'XYZ'"
  }
  Assert-TestCondition $unknownScaleformRejected 'An unknown eight-byte Scaleform signature was accepted.'

  Write-Output 'Reusable build pipeline tests passed: variant selection, exact dynamic namespace discovery, declaration validation, quoted environment parsing, dynamic install paths, GNRL/DX10 artifact headers, and CFX Scaleform header admission.'
}
finally {
  foreach ($environmentName in $environmentNames) {
    [Environment]::SetEnvironmentVariable($environmentName, $savedEnvironment[$environmentName], 'Process')
  }
  if ($hadBuildSettings) {
    Set-Variable -Name BuildSettings -Scope Global -Value $savedBuildSettings
  }
  else {
    Remove-Variable -Name BuildSettings -Scope Global -ErrorAction SilentlyContinue
  }
  if ($hadModuleVariants) {
    Set-Variable -Name ModuleVariants -Scope Global -Value $savedModuleVariants
  }
  else {
    Remove-Variable -Name ModuleVariants -Scope Global -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
    $resolvedFixtureRoot = Get-BuildNormalizedFullPath -Path $fixtureRoot
    $resolvedTestBase = Get-BuildNormalizedFullPath -Path $testBase
    if (!$resolvedFixtureRoot.StartsWith($resolvedTestBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove build-pipeline fixture outside $resolvedTestBase."
    }
    Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
  }
}
