<#
.SYNOPSIS
Checks variant selection, binary-header rejection, and junction-preserving package source contracts.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

$all = @(Get-CanvasStagingSelection)
if ($all.Count -ne $Global:ModuleVariants.Count) {
  throw 'Default package selection must include every sharedConfig.ps1 variant.'
}
$canvas = @(Get-CanvasStagingSelection -VariantKeys 'CANVAS')
if ($canvas.Count -ne 1 -or $canvas[0].VariantKey -cne 'CANVAS') {
  throw 'Explicit Canvas package selection failed.'
}
foreach ($badKeys in @(@('UNKNOWN'), @('CANVAS', 'CANVAS'))) {
  $caught = $false
  try { [void](Get-CanvasStagingSelection -VariantKeys $badKeys) } catch { $caught = $true }
  if (!$caught) { throw "Invalid package variant selection was accepted: $($badKeys -join ', ')" }
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pathTestRoot = Join-Path $repositoryRoot '.work\canvas\path-validation-tests'
$equalPath = Join-Path $pathTestRoot 'Equality'
$parentPath = Join-Path $pathTestRoot 'Parent'
$childPath = Join-Path $parentPath 'Child'
$ordinarySiblingLeft = Join-Path $pathTestRoot 'First'
$ordinarySiblingRight = Join-Path $pathTestRoot 'Second'
$stagingPath = Join-Path $pathTestRoot 'Staging-Canvas'
$stagingChildTarget = Join-Path $stagingPath 'PhysicalTarget'
$physicalParentTarget = Join-Path $pathTestRoot 'PhysicalModules'
$stagingInsideTarget = Join-Path $physicalParentTarget 'Staging-Example'
$pathCases = @(
  @{ Name = 'case-insensitive equality'; Left = $equalPath; Right = (Join-Path $pathTestRoot 'eQUALITY'); Expected = $true },
  @{ Name = 'parent before child'; Left = $parentPath; Right = $childPath; Expected = $true },
  @{ Name = 'child before parent'; Left = $childPath; Right = $parentPath; Expected = $true },
  @{ Name = 'ordinary siblings'; Left = $ordinarySiblingLeft; Right = $ordinarySiblingRight; Expected = $false },
  @{ Name = 'target inside staging'; Left = $stagingChildTarget; Right = $stagingPath; Expected = $true },
  @{ Name = 'staging inside target'; Left = $physicalParentTarget; Right = $stagingInsideTarget; Expected = $true }
)
foreach ($pathCase in $pathCases) {
  $actual = Test-CanvasOverlappingPaths -Left $pathCase.Left -Right $pathCase.Right
  if ($actual -ne $pathCase.Expected) {
    throw "Path overlap regression failed: $($pathCase.Name)"
  }
}

$validSiblingPaths = @(
  (Join-Path $pathTestRoot 'Canvas'),
  (Join-Path $pathTestRoot 'Canvas - Example'),
  (Join-Path $pathTestRoot 'Canvas - Component Gallery')
)
for ($leftIndex = 0; $leftIndex -lt $validSiblingPaths.Count; $leftIndex++) {
  for ($rightIndex = $leftIndex + 1; $rightIndex -lt $validSiblingPaths.Count; $rightIndex++) {
    if (Test-CanvasOverlappingPaths -Left $validSiblingPaths[$leftIndex] -Right $validSiblingPaths[$rightIndex]) {
      throw 'Common-prefix sibling paths were treated as overlapping.'
    }
  }
}

$filesystemRoot = [System.IO.Path]::GetPathRoot($pathTestRoot)
$rootChild = Join-Path $filesystemRoot 'canvas-path-validation-root-child'
if (!(Test-CanvasOverlappingPaths -Left $filesystemRoot -Right $rootChild)) {
  throw 'Filesystem root ancestry was not preserved.'
}

$sharedSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'sharedCanvas.ps1') -Raw
$packageSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'createPackages.ps1') -Raw
$setupSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'setupRepo.ps1') -Raw
$checkSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'checkRepo.ps1') -Raw
if ($sharedSource -notmatch '(?m)^function Test-CanvasOverlappingPaths\s*\{') {
  throw 'Shared Canvas helpers do not define the path overlap predicate.'
}
if ($packageSource -match '(?m)^function Test-CanvasOverlappingPaths\s*\{') {
  throw 'Package creation duplicates the shared path overlap predicate.'
}
foreach ($topologySource in @(
  @{ Name = 'setupRepo.ps1'; Source = $setupSource },
  @{ Name = 'checkRepo.ps1'; Source = $checkSource }
)) {
  foreach ($contract in @(
    ". (Join-Path `$PSScriptRoot 'sharedCanvas.ps1')",
    '$configuredStagingPaths',
    'Test-CanvasOverlappingPaths',
    'cannot use identical or nested physical module folders',
    'cannot overlap a repository staging path'
  )) {
    if (!$topologySource.Source.Contains($contract)) {
      throw "$($topologySource.Name) is missing topology safety contract: $contract"
    }
  }
  if ($topologySource.Source.Contains('Test-SamePath -Left $_.Path -Right $configuredTargetPath')) {
    throw "$($topologySource.Name) regressed to equality-only physical target validation."
  }
  $overlapTopologyCalls = [regex]::Matches(
    $topologySource.Source,
    'Test-CanvasOverlappingPaths -Left \$_\.Path -Right \$configuredTargetPath'
  ).Count
  if ($overlapTopologyCalls -lt 2) {
    throw "$($topologySource.Name) must validate target-to-target and target-to-staging overlap."
  }
}
$setupTopologyIndex = $setupSource.IndexOf('$configuredStagingPaths = @(')
$setupMutationIndex = $setupSource.IndexOf('New-Item -ItemType Directory -Force -Path $operation.TargetPath')
if ($setupTopologyIndex -lt 0 -or $setupMutationIndex -lt 0 -or $setupTopologyIndex -gt $setupMutationIndex) {
  throw 'setupRepo.ps1 does not validate topology before filesystem mutation.'
}
foreach ($contract in @(
  '. (Join-Path $PSScriptRoot ''sharedConfig.ps1'') -SkipEnvironment',
  '. (Join-Path $PSScriptRoot ''sharedCanvas.ps1'')',
  '$selectedVariants = @(Get-CanvasStagingSelection -VariantKeys $VariantKeys)',
  '$configuredPhysicalTargets',
  'cannot use identical or nested physical module folders',
  'physical module folder cannot overlap a repository staging path',
  '$stagingItem.LinkType -eq ''Junction''',
  'installed package must be empty or contain exactly the candidate ESM and BA2 file set.',
  '[System.IO.File]::Move($temporaryPath, $destinationPath, $true)',
  'prior ESM/BA2 files were restored without replacing their directory or Junction'
)) {
  if (!$packageSource.Contains($contract)) {
    throw "Missing package safety contract: $contract"
  }
}
foreach ($forbiddenContract in @(
  'Remove-Item -LiteralPath $operation.InstallPath -Recurse',
  'Move-Item -LiteralPath $operation.InstallPath',
  'Move-Item -LiteralPath $operation.CandidatePath -Destination $operation.InstallPath',
  'Main_XBox.ba2',
  'Main_PS.ba2',
  '-compression=Default'
)) {
  if ($packageSource.Contains($forbiddenContract)) {
    throw "Package source retained a destructive or unsupported contract: $forbiddenContract"
  }
}

$testWorkRoot = Join-Path $repositoryRoot '.work\canvas'
$fixtureRoot = Join-Path $testWorkRoot ('test-packaging-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
try {
  $pointer = [Text.Encoding]::UTF8.GetBytes("version https://git-lfs.github.com/spec/v1`noid sha256:012345`nsize 4096`n")
  $rejections = 0
  foreach ($extension in @('esm', 'ba2')) {
    foreach ($fixture in @(
      @{ Name = 'pointer'; Bytes = $pointer },
      @{ Name = 'empty'; Bytes = [byte[]]::new(0) },
      @{ Name = 'truncated'; Bytes = [byte[]]::new(8) },
      @{ Name = 'wrong-magic'; Bytes = [byte[]]::new(64) }
    )) {
      $path = Join-Path $fixtureRoot ($fixture.Name + '.' + $extension)
      [System.IO.File]::WriteAllBytes($path, $fixture.Bytes)
      $rejected = $false
      try { Assert-CanvasArtifactHeader -Path $path } catch { $rejected = $true }
      if (!$rejected) { throw "Invalid $extension binary fixture was accepted: $($fixture.Name)" }
      $rejections += 1
    }
  }
}
finally {
  if (Test-Path -LiteralPath $fixtureRoot) {
    Assert-CanvasRemovalPath -Path $fixtureRoot -AllowedRoot $testWorkRoot
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}

$assemblyRejected = $false
try { & (Join-Path $PSScriptRoot 'SpriggitAssembleDatabaseFromYaml.ps1') } catch { $assemblyRejected = $_.Exception.Message -like 'Spriggit assembly is disabled*' }
if (!$assemblyRejected) { throw 'Spriggit assembly did not fail closed.' }

Write-Output "Packaging contracts passed: shared variant selection, path topology validation, junction-preserving child-file replacement, eight binary rejections, and disabled Spriggit assembly."
