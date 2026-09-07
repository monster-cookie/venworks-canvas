<#
.SYNOPSIS
Exercises direct payload, installed archive, exact-Junction, recovery, and process-lock package contracts.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

function Assert-TestRejected {
  param([Parameter(Mandatory = $true)][scriptblock]$Action, [Parameter(Mandatory = $true)][string]$Description)
  $caught = $false
  try { & $Action } catch { $caught = $true }
  if (!$caught) { throw "$Description was accepted." }
}

function Assert-TestNames {
  param([Parameter(Mandatory = $true)][string[]]$Actual, [Parameter(Mandatory = $true)][string[]]$Expected, [Parameter(Mandatory = $true)][string]$Description)
  $actualNames = @($Actual | ForEach-Object { ([string]$_).Replace('\', '/').ToLowerInvariant() } | Sort-Object)
  $expectedNames = @($Expected | ForEach-Object { ([string]$_).Replace('\', '/').ToLowerInvariant() } | Sort-Object)
  if ($actualNames.Count -ne $expectedNames.Count) { throw "$Description count differs. Expected $($expectedNames.Count); found $($actualNames.Count)." }
  for ($index = 0; $index -lt $expectedNames.Count; $index++) {
    if ($actualNames[$index] -cne $expectedNames[$index]) { throw "$Description differs at index $index. Expected '$($expectedNames[$index])'; found '$($actualNames[$index])'." }
  }
}

function Write-TestEsm {
  param([Parameter(Mandatory = $true)][string]$Path, [byte]$Marker = 0)
  $bytes = [byte[]]::new(42)
  [Text.Encoding]::ASCII.GetBytes('TES4').CopyTo($bytes, 0)
  [BitConverter]::GetBytes([uint32]18).CopyTo($bytes, 4)
  $bytes[24] = $Marker
  [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Write-TestPayload {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  [System.IO.File]::WriteAllText($Path, $Text)
}

function Write-TestPapyrusHeaderFixture {
  param([Parameter(Mandatory = $true)][string]$Path)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $bytes = [byte[]]::new(16)
  $bytes[0] = 0xDE
  $bytes[1] = 0xC0
  $bytes[2] = 0x57
  $bytes[3] = 0xFA
  [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Write-TestScaleformHeaderFixture {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][ValidateSet('CWS', 'GFX')][string]$Signature
  )
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $bytes = [byte[]]::new(8)
  [Text.Encoding]::ASCII.GetBytes($Signature).CopyTo($bytes, 0)
  [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Write-TestBa2 {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][hashtable]$Entries)
  $ordered = @($Entries.GetEnumerator() | Sort-Object Key)
  $recordEnd = 32 + (36 * $ordered.Count)
  $dataLength = @($ordered | ForEach-Object { ([byte[]]$_.Value).Length } | Measure-Object -Sum).Sum
  $nameOffset = $recordEnd + $dataLength
  $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  $writer = [System.IO.BinaryWriter]::new($stream, [Text.Encoding]::UTF8, $true)
  try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes('BTDX'))
    $writer.Write([uint32]2)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('GNRL'))
    $writer.Write([uint32]$ordered.Count)
    $writer.Write([uint64]$nameOffset)
    $writer.Write([uint64]0)
    $offset = [uint64]$recordEnd
    foreach ($entry in $ordered) {
      $bytes = [byte[]]$entry.Value
      $writer.Write([uint32]0)
      $writer.Write([byte[]]::new(4))
      $writer.Write([uint32]0)
      $writer.Write([uint32]0)
      $writer.Write($offset)
      $writer.Write([uint32]0)
      $writer.Write([uint32]$bytes.Length)
      $writer.Write([uint32]0)
      $offset += $bytes.Length
    }
    foreach ($entry in $ordered) { $writer.Write([byte[]]$entry.Value) }
    foreach ($entry in $ordered) {
      $nameBytes = [Text.Encoding]::UTF8.GetBytes(([string]$entry.Key).Replace('\', '/'))
      $writer.Write([uint16]$nameBytes.Length)
      $writer.Write($nameBytes)
    }
  }
  finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

$all = @(Get-CanvasStagingSelection)
if ($all.Count -ne $Global:ModuleVariants.Count) { throw 'Default package selection must include every variant.' }
if (@(Get-CanvasStagingSelection -VariantKeys 'CANVAS').Count -ne 1) { throw 'Explicit Canvas package selection failed.' }
foreach ($badKeys in @(@('UNKNOWN'), @('CANVAS', 'CANVAS'))) {
  Assert-TestRejected -Description "Invalid variant selection '$($badKeys -join ', ')'" -Action { [void](Get-CanvasStagingSelection -VariantKeys $badKeys) }
}

$wrapperTokens = $null
$wrapperParseErrors = $null
$wrapperAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'createPackages.ps1'), [ref]$wrapperTokens, [ref]$wrapperParseErrors)
if ($wrapperParseErrors.Count -ne 0) { throw "createPackages.ps1 has $($wrapperParseErrors.Count) parse error(s)." }
$packageTransactionTry = $null
foreach ($candidateTry in @($wrapperAst.FindAll({ param($node) $node -is [Management.Automation.Language.TryStatementAst] }, $true))) {
  $candidateCommands = @($candidateTry.Body.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
  if ($candidateCommands -contains 'Enter-CanvasPackageLock') {
    if ($null -ne $packageTransactionTry) { throw 'createPackages.ps1 contains multiple package-lock transaction scopes.' }
    $packageTransactionTry = $candidateTry
  }
}
if ($null -eq $packageTransactionTry -or $null -eq $packageTransactionTry.Finally) { throw 'createPackages.ps1 does not protect the package-lock transaction with finally.' }
$cleanupOwnershipTries = @($packageTransactionTry.Finally.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] })
if ($cleanupOwnershipTries.Count -ne 1) { throw 'createPackages.ps1 does not contain one lock-owned successful-cleanup scope.' }
$cleanupOwnershipTry = $cleanupOwnershipTries[0]
$cleanupCommands = @($cleanupOwnershipTry.Body.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
if ($cleanupCommands -cnotcontains 'Remove-Item' -or $null -eq $cleanupOwnershipTry.Finally) { throw 'createPackages.ps1 does not perform successful transaction cleanup before its nested release finally.' }
$lockDisposeCalls = @($cleanupOwnershipTry.Finally.FindAll({
  param($node)
  $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
    $node.Expression -is [Management.Automation.Language.VariableExpressionAst] -and
    $node.Expression.VariablePath.UserPath -ceq 'packageLock' -and
    $node.Member.Extent.Text -ceq 'Dispose'
}, $true))
if ($lockDisposeCalls.Count -ne 1) { throw 'createPackages.ps1 does not release the package lock exactly once after successful-cleanup handling.' }

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testBase = Join-Path $repositoryRoot '.work\canvas\pr4-simplification\package'
$fixtureRoot = Join-Path $testBase ('packaging-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
$originalCanvasTarget = [Environment]::GetEnvironmentVariable('TEST_CANVAS_TARGET', 'Process')
$originalExampleTarget = [Environment]::GetEnvironmentVariable('TEST_EXAMPLE_TARGET', 'Process')
try {
  $scriptsDirectory = Join-Path $fixtureRoot 'outputs\scripts'
  $moviesDirectory = Join-Path $fixtureRoot 'outputs\scaleform\movies'
  $playerDirectory = Join-Path $fixtureRoot 'outputs\scaleform\player-hud'
  $shipDirectory = Join-Path $fixtureRoot 'outputs\scaleform\ship-hud'
  New-Item -ItemType Directory -Force -Path $scriptsDirectory, $moviesDirectory, $playerDirectory, $shipDirectory | Out-Null
  $canvas = [pscustomobject]@{
    VariantKey = 'CANVAS'; PackageBaseName = 'FixtureCanvas'; ScaleformOutput = 'CanvasHost.swf'
    PapyrusScripts = @('Venworks\Canvas\GlobalConfig.psc', 'Venworks\Canvas\Enumerations.psc', 'Venworks\Canvas\Base\BaseQuest.psc', 'Venworks\Canvas\Registry.psc')
  }
  $example = [pscustomobject]@{
    VariantKey = 'EXAMPLE'; PackageBaseName = 'FixtureExample'; ScaleformOutput = 'CanvasExample.swf'
    PapyrusScripts = @('Venworks\CanvasExamples\ExampleRegistrar.psc')
  }
  $gallery = [pscustomobject]@{
    VariantKey = 'COMPONENTGALLERY'; PackageBaseName = 'FixtureGallery'; ScaleformOutput = 'CanvasComponentGallery.swf'
    PapyrusScripts = @('Venworks\CanvasComponentGallery\ComponentGalleryRegistrar.psc')
  }
  foreach ($variant in @($canvas, $example, $gallery)) {
    Write-TestScaleformHeaderFixture -Path (Join-Path $moviesDirectory $variant.ScaleformOutput) -Signature 'CWS'
    foreach ($source in @($variant.PapyrusScripts)) {
      Write-TestPapyrusHeaderFixture -Path (Join-Path $scriptsDirectory ([System.IO.Path]::ChangeExtension([string]$source, '.pex')))
    }
  }
  foreach ($name in @('playerhudcomponents.swf', 'playerhudcomponents.gfx', 'playerhudcomponents_lrg.swf', 'playerhudcomponents_lrg.gfx')) {
    $signature = if ([System.IO.Path]::GetExtension($name) -ieq '.gfx') { 'GFX' } else { 'CWS' }
    Write-TestScaleformHeaderFixture -Path (Join-Path $playerDirectory $name) -Signature $signature
  }
  foreach ($name in @('spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf')) {
    Write-TestScaleformHeaderFixture -Path (Join-Path $shipDirectory $name) -Signature 'CWS'
  }

  # Installed dependencies and undeclared output files may be present, but they must never enter a Canvas package.
  $foreignFiles = @(
    (Join-Path $scriptsDirectory 'Venworks\Core\Logging.pex'),
    (Join-Path $playerDirectory 'hudmenu.swf'),
    (Join-Path $playerDirectory 'hudmenu.gfx'),
    (Join-Path $moviesDirectory 'ForeignDependency.swf')
  )
  foreach ($path in $foreignFiles) { Write-TestPayload -Path $path -Text 'foreign-dependency' }

  $payloads = Get-CanvasPackagePayloads -SelectedVariants @($canvas, $example, $gallery) -MoviesDirectory $moviesDirectory -ScriptsDirectory $scriptsDirectory -PlayerDirectory $playerDirectory -ShipDirectory $shipDirectory
  $canvasTargets = @(
    'Interface\venworkscui.swf',
    'Interface\playerhudcomponents.swf',
    'Interface\playerhudcomponents.gfx',
    'Interface\playerhudcomponents_lrg.swf',
    'Interface\playerhudcomponents_lrg.gfx',
    'Interface\spaceshiphudmenu.swf',
    'Interface\spaceshiphudmenu_lrg.swf',
    'Scripts\Venworks\Canvas\GlobalConfig.pex',
    'Scripts\Venworks\Canvas\Enumerations.pex',
    'Scripts\Venworks\Canvas\Base\BaseQuest.pex',
    'Scripts\Venworks\Canvas\Registry.pex'
  )
  $exampleTargets = @(
    'Interface\VenworksCanvas\Consumers\venworks.canvas.example\normal.swf',
    'Interface\VenworksCanvas\Consumers\venworks.canvas.example\large.swf',
    'Scripts\Venworks\CanvasExamples\ExampleRegistrar.pex'
  )
  $galleryTargets = @(
    'Interface\VenworksCanvas\Consumers\venworks.canvas.component-gallery\normal.swf',
    'Interface\VenworksCanvas\Consumers\venworks.canvas.component-gallery\large.swf',
    'Scripts\Venworks\CanvasComponentGallery\ComponentGalleryRegistrar.pex'
  )
  Assert-TestNames -Actual @($payloads['CANVAS'].Target) -Expected $canvasTargets -Description 'CANVAS owned payload inventory'
  Assert-TestNames -Actual @($payloads['EXAMPLE'].Target) -Expected $exampleTargets -Description 'EXAMPLE owned payload inventory'
  Assert-TestNames -Actual @($payloads['COMPONENTGALLERY'].Target) -Expected $galleryTargets -Description 'COMPONENTGALLERY owned payload inventory'
  $allPayloads = @($payloads.Values | ForEach-Object { $_ })
  foreach ($row in $allPayloads) {
    if ((Get-CanvasFileSha256 -Path $row.Source) -cne [string]$row.ExpectedSha256) { throw "Transient payload hash differs for '$($row.Target)'." }
  }
  $allTargets = @($allPayloads.Target | ForEach-Object { ([string]$_).Replace('\', '/').ToLowerInvariant() })
  foreach ($forbiddenTarget in @(
      'scripts/venworks/core/logging.pex',
      'interface/hudmenu.swf',
      'interface/hudmenu.gfx',
      'scripts/venworks/canvas/exampleregistrar.pex',
      'scripts/venworks/canvas/componentgalleryregistrar.pex')) {
    if ($forbiddenTarget -cin $allTargets) { throw "Foreign or retired package target was included: $forbiddenTarget" }
  }
  $exampleOnly = Get-CanvasPackagePayloads -SelectedVariants @($example) -MoviesDirectory $moviesDirectory -ScriptsDirectory $scriptsDirectory
  Assert-TestNames -Actual @($exampleOnly['EXAMPLE'].Target) -Expected $exampleTargets -Description 'Selected EXAMPLE payload inventory'
  $examplePexPath = Join-Path $scriptsDirectory 'Venworks\CanvasExamples\ExampleRegistrar.pex'
  $exampleMoviePath = Join-Path $moviesDirectory 'CanvasExample.swf'
  $truncatedPex = [byte[]]::new(4)
  $truncatedPex[0] = 0xDE
  $truncatedPex[1] = 0xC0
  $truncatedPex[2] = 0x57
  $truncatedPex[3] = 0xFA
  foreach ($invalidPex in @(
      @{ Description = 'Empty selected PEX'; Bytes = [byte[]]::new(0) },
      @{ Description = 'Truncated selected PEX'; Bytes = $truncatedPex },
      @{ Description = 'Invalid-header selected PEX'; Bytes = [byte[]]::new(16) })) {
    [System.IO.File]::WriteAllBytes($examplePexPath, [byte[]]$invalidPex.Bytes)
    Assert-TestRejected -Description ([string]$invalidPex.Description) -Action {
      [void](Get-CanvasPackagePayloads -SelectedVariants @($example) -MoviesDirectory $moviesDirectory -ScriptsDirectory $scriptsDirectory)
    }
    Write-TestPapyrusHeaderFixture -Path $examplePexPath
  }
  foreach ($invalidMovie in @(
      @{ Description = 'Empty selected movie'; Bytes = [byte[]]::new(0) },
      @{ Description = 'Truncated selected movie'; Bytes = [Text.Encoding]::ASCII.GetBytes('CWS') },
      @{ Description = 'Invalid-header selected movie'; Bytes = [Text.Encoding]::ASCII.GetBytes('NOTMOVIE!') })) {
    [System.IO.File]::WriteAllBytes($exampleMoviePath, [byte[]]$invalidMovie.Bytes)
    Assert-TestRejected -Description ([string]$invalidMovie.Description) -Action {
      [void](Get-CanvasPackagePayloads -SelectedVariants @($example) -MoviesDirectory $moviesDirectory -ScriptsDirectory $scriptsDirectory)
    }
    Write-TestScaleformHeaderFixture -Path $exampleMoviePath -Signature 'CWS'
  }
  Remove-Item -LiteralPath (Join-Path $moviesDirectory 'CanvasHost.swf') -Force
  Assert-TestRejected -Description 'Missing selected CanvasHost output' -Action {
    [void](Get-CanvasPackagePayloads -SelectedVariants @($canvas) -MoviesDirectory $moviesDirectory -ScriptsDirectory $scriptsDirectory -PlayerDirectory $playerDirectory -ShipDirectory $shipDirectory)
  }
  Write-TestScaleformHeaderFixture -Path (Join-Path $moviesDirectory 'CanvasHost.swf') -Signature 'CWS'

  $target = Join-Path $fixtureRoot 'target'
  $otherTarget = Join-Path $fixtureRoot 'other-target'
  $staging = Join-Path $fixtureRoot 'staging'
  $otherStaging = Join-Path $fixtureRoot 'other-staging'
  New-Item -ItemType Directory -Path $target, $otherTarget | Out-Null
  Write-TestEsm -Path (Join-Path $target 'Fixture.esm')
  $variant = [pscustomobject]@{ VariantKey = 'CANVAS'; PackageBaseName = 'Fixture'; StagingFolderPath = $staging; EnvironmentVariableName = 'TEST_CANVAS_TARGET' }
  $unselectedVariant = [pscustomobject]@{ VariantKey = 'EXAMPLE'; PackageBaseName = 'Other'; StagingFolderPath = $otherStaging; EnvironmentVariableName = 'TEST_EXAMPLE_TARGET' }
  [Environment]::SetEnvironmentVariable('TEST_CANVAS_TARGET', $target, 'Process')
  [Environment]::SetEnvironmentVariable('TEST_EXAMPLE_TARGET', $otherTarget, 'Process')

  Assert-TestRejected -Description 'Missing staging path preflight' -Action { [void](Get-CanvasPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $unselectedVariant)) }
  New-Item -ItemType Directory -Path $staging | Out-Null
  $beforeOrdinaryBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $target 'Fixture.esm')))
  Assert-TestRejected -Description 'Ordinary staging directory preflight' -Action { [void](Get-CanvasPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $unselectedVariant)) }
  Assert-TestNames -Actual @((Get-ChildItem -LiteralPath $target -Force).Name) -Expected @('Fixture.esm') -Description 'Rejected ordinary-directory physical target inventory'
  if ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $target 'Fixture.esm'))) -cne $beforeOrdinaryBytes) { throw 'Rejected ordinary-directory preflight changed the physical target.' }
  Remove-Item -LiteralPath $staging -Force

  if ($IsWindows) {
    New-Item -ItemType Junction -Path $staging -Target $otherTarget | Out-Null
    Assert-TestRejected -Description 'Wrong Junction target preflight' -Action { [void](Get-CanvasPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $unselectedVariant)) }
    Remove-Item -LiteralPath $staging -Force
    New-Item -ItemType Junction -Path $staging -Target $target | Out-Null
    $operations = @(Get-CanvasPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $unselectedVariant))
    if ($operations.Count -ne 1 -or !(Test-CanvasSamePath -Left $operations[0].InstallPath -Right $target)) { throw 'Correct Junction preflight did not resolve the configured physical target.' }
    [Environment]::SetEnvironmentVariable('TEST_EXAMPLE_TARGET', (Join-Path $target 'nested'), 'Process')
    Assert-TestRejected -Description 'Selected target overlap with an unselected configured target' -Action { [void](Get-CanvasPackageInstallOperations -SelectedVariants @($variant) -AllVariants @($variant, $unselectedVariant)) }
    [Environment]::SetEnvironmentVariable('TEST_EXAMPLE_TARGET', $otherTarget, 'Process')
  }
  else {
    Write-Output 'SKIP: real Junction preflight cases require Windows.'
  }

  $packageDirectory = Join-Path $fixtureRoot 'installed'
  New-Item -ItemType Directory -Path $packageDirectory | Out-Null
  $esmPath = Join-Path $packageDirectory 'Fixture.esm'
  $ba2Path = Join-Path $packageDirectory 'Fixture - Main.ba2'
  Write-TestEsm -Path $esmPath
  Write-TestBa2 -Path $ba2Path -Entries @{ 'Interface/test.swf' = [Text.Encoding]::UTF8.GetBytes('movie'); 'Scripts/test.pex' = [Text.Encoding]::UTF8.GetBytes('script') }
  $entries = @(Get-CanvasGeneralBa2Contents -Path $ba2Path)
  Assert-CanvasInstalledPackage -Variant $variant -InstallPath $packageDirectory -ExpectedEntries $entries
  [System.IO.File]::WriteAllText($esmPath, 'invalid-esm')
  Assert-TestRejected -Description 'Invalid installed ESM header' -Action { Assert-CanvasInstalledPackage -Variant $variant -InstallPath $packageDirectory -ExpectedEntries $entries }
  Write-TestEsm -Path $esmPath
  Write-TestBa2 -Path $ba2Path -Entries @{ 'Interface/test.swf' = [Text.Encoding]::UTF8.GetBytes('changed'); 'Scripts/test.pex' = [Text.Encoding]::UTF8.GetBytes('script') }
  Assert-TestRejected -Description 'Changed installed archive entry' -Action { Assert-CanvasInstalledPackage -Variant $variant -InstallPath $packageDirectory -ExpectedEntries $entries }
  Write-TestBa2 -Path $ba2Path -Entries @{ 'Interface/test.swf' = [Text.Encoding]::UTF8.GetBytes('movie'); 'Scripts/test.pex' = [Text.Encoding]::UTF8.GetBytes('script') }
  [System.IO.File]::WriteAllText((Join-Path $packageDirectory 'extra.txt'), 'extra')
  Assert-TestRejected -Description 'Extra installed package file' -Action { Assert-CanvasInstalledPackage -Variant $variant -InstallPath $packageDirectory -ExpectedEntries $entries }
  Remove-Item -LiteralPath (Join-Path $packageDirectory 'extra.txt') -Force

  $transactionBase = Join-Path $fixtureRoot 'transactions'
  New-Item -ItemType Directory -Path $transactionBase | Out-Null
  Assert-CanvasNoIncompletePackageTransactions -TransactionBase $transactionBase
  $retainedTransaction = Join-Path $transactionBase ([guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $retainedTransaction | Out-Null
  Write-CanvasPackageTransactionJournal -TransactionPath $retainedTransaction -TransactionId (Split-Path -Leaf $retainedTransaction) -Status 'Active' -VariantKeys @('CANVAS')
  Assert-TestRejected -Description 'Retained interrupted transaction' -Action { Assert-CanvasNoIncompletePackageTransactions -TransactionBase $transactionBase }
  Remove-Item -LiteralPath $retainedTransaction -Recurse -Force

  if ($IsWindows) {
    $recoveryBackup = Join-Path $fixtureRoot 'installed-recovery'
    New-Item -ItemType Directory -Path $recoveryBackup | Out-Null
    $originalEsm = Join-Path $recoveryBackup 'Fixture.esm'
    Write-TestEsm -Path $originalEsm
    $originalHash = Get-CanvasFileSha256 -Path $originalEsm
    Write-TestEsm -Path (Join-Path $target 'Fixture.esm') -Marker 9
    [System.IO.File]::WriteAllText((Join-Path $target 'Fixture - Main.ba2'), 'candidate')
    $recoveryOperation = [pscustomobject]@{
      Key = 'CANVAS'; StagingPath = $staging; InstallPath = $target; BackupPath = $recoveryBackup
      CandidateNames = @('Fixture.esm', 'Fixture - Main.ba2'); OriginalNames = @('Fixture.esm'); OriginalHashes = @{ 'Fixture.esm' = $originalHash }
    }
    [System.IO.File]::AppendAllText($originalEsm, 'corrupt')
    $candidateHashBefore = Get-CanvasFileSha256 -Path (Join-Path $target 'Fixture.esm')
    Assert-TestRejected -Description 'Corrupt installed-package recovery backup' -Action { Restore-CanvasPackageOperation -Operation $recoveryOperation }
    if ((Get-CanvasFileSha256 -Path (Join-Path $target 'Fixture.esm')) -cne $candidateHashBefore -or !(Test-Path -LiteralPath (Join-Path $target 'Fixture - Main.ba2') -PathType Leaf)) {
      throw 'Installed-package recovery mutated the candidate before complete backup preflight.'
    }
    Write-TestEsm -Path $originalEsm
    Restore-CanvasPackageOperation -Operation $recoveryOperation
    if ((Get-CanvasFileSha256 -Path (Join-Path $target 'Fixture.esm')) -cne $originalHash -or (Test-Path -LiteralPath (Join-Path $target 'Fixture - Main.ba2'))) {
      throw 'Installed-package recovery did not restore the exact prior inventory and bytes.'
    }
  }

  $lockPath = Join-Path $fixtureRoot 'package.lock'
  $lock = Enter-CanvasPackageLock -Path $lockPath -TransactionId ([guid]::NewGuid().ToString('N'))
  try {
    $childResult = Join-Path $fixtureRoot 'child-lock-result.txt'
    $command = @"
. '$((Join-Path $PSScriptRoot 'sharedConfig.ps1').Replace("'", "''"))' -SkipEnvironment
. '$((Join-Path $PSScriptRoot 'sharedCanvas.ps1').Replace("'", "''"))'
try { `$held = Enter-CanvasPackageLock -Path '$($lockPath.Replace("'", "''"))' -TransactionId '$([guid]::NewGuid().ToString('N'))'; `$held.Dispose(); [IO.File]::WriteAllText('$($childResult.Replace("'", "''"))', 'ACQUIRED') }
catch { [IO.File]::WriteAllText('$($childResult.Replace("'", "''"))', 'REJECTED') }
"@
    $startProcessParameters = @{
      FilePath = (Get-Process -Id $PID).Path
      ArgumentList = @('-NoProfile', '-Command', $command)
      PassThru = $true
    }
    if ($IsWindows) { $startProcessParameters.WindowStyle = 'Hidden' }
    $child = Start-Process @startProcessParameters
    if (!$child.WaitForExit(10000)) { $child.Kill(); throw 'Competing package-lock process did not finish.' }
    if ([System.IO.File]::ReadAllText($childResult) -cne 'REJECTED') { throw 'Competing process acquired an already-held package lock.' }
  }
  finally { $lock.Dispose() }
  $reacquired = Enter-CanvasPackageLock -Path $lockPath -TransactionId ([guid]::NewGuid().ToString('N'))
  $reacquired.Dispose()

  if ($IsWindows) {
    $holderMarker = Join-Path $fixtureRoot 'holder-ready.txt'
    $holderCommand = @"
. '$((Join-Path $PSScriptRoot 'sharedConfig.ps1').Replace("'", "''"))' -SkipEnvironment
. '$((Join-Path $PSScriptRoot 'sharedCanvas.ps1').Replace("'", "''"))'
`$held = Enter-CanvasPackageLock -Path '$($lockPath.Replace("'", "''"))' -TransactionId '$([guid]::NewGuid().ToString('N'))'
[IO.File]::WriteAllText('$($holderMarker.Replace("'", "''"))', 'READY')
Start-Sleep -Seconds 30
"@
    $holder = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-Command', $holderCommand) -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (!(Test-Path -LiteralPath $holderMarker -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
    if (!(Test-Path -LiteralPath $holderMarker -PathType Leaf)) { $holder.Kill(); throw 'Lock-holder process did not reach its barrier.' }
    $holder.Kill()
    $holder.WaitForExit()
    $afterTermination = Enter-CanvasPackageLock -Path $lockPath -TransactionId ([guid]::NewGuid().ToString('N'))
    $afterTermination.Dispose()
  }
}
finally {
  [Environment]::SetEnvironmentVariable('TEST_CANVAS_TARGET', $originalCanvasTarget, 'Process')
  [Environment]::SetEnvironmentVariable('TEST_EXAMPLE_TARGET', $originalExampleTarget, 'Process')
  if (Test-Path -LiteralPath $fixtureRoot) {
    Assert-CanvasRemovalPath -Path $fixtureRoot -AllowedRoot $testBase
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}

Write-Output 'Packaging contracts passed: selected Canvas-owned payload allowlists, installed dependency exclusion, child namespace isolation, direct artifact hashes, exact Junction preflight, exact installed BA2 contents, package recovery, retained transaction blocking, and platform-safe process lock exclusion/termination recovery.'
