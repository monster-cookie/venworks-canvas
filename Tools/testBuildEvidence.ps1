<#
.SYNOPSIS
Exercises Canvas-owned Scaleform patch and publication helpers.
.DESCRIPTION
Uses local fixture movies and ActionScript text. Java, JPEXS, Apache Flex, and the game runtime are intentionally not invoked.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')
. (Join-Path $PSScriptRoot 'sharedCanvasScaleform.ps1')

function Assert-TestRejected {
  param(
    [Parameter(Mandatory = $true)][string]$Description,
    [Parameter(Mandatory = $true)][scriptblock]$Action,
    [string]$ExpectedMessage
  )

  try {
    & $Action
  }
  catch {
    if (![string]::IsNullOrWhiteSpace($ExpectedMessage) -and !$_.Exception.Message.Contains($ExpectedMessage)) {
      throw "$Description returned an unexpected error: $($_.Exception.Message)"
    }
    return
  }
  throw "$Description was accepted unexpectedly."
}

function Write-TestScaleformMovie {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Signature = 'CWS',
    [string]$Marker = 'fixture'
  )

  $parent = Split-Path -Parent $Path
  if (!(Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  [System.IO.File]::WriteAllBytes($Path, [System.Text.Encoding]::ASCII.GetBytes($Signature + '12345' + $Marker))
}

function Get-TestDirectoryDigest {
  param([Parameter(Mandatory = $true)][string]$Path)

  $rows = @(Get-ChildItem -LiteralPath $Path -Recurse -File | ForEach-Object {
    $relative = [System.IO.Path]::GetRelativePath($Path, $_.FullName).Replace('\', '/')
    "$relative`:$((Get-CanvasFileSha256 -Path $_.FullName))"
  } | Sort-Object)
  return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $rows))))
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtureParent = Join-Path $repositoryRoot '.work\canvas\pr4-simplification\scaleform'
New-Item -ItemType Directory -Force -Path $fixtureParent | Out-Null
$fixtureRoot = Join-Path $fixtureParent ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

try {
  $validMovie = Join-Path $fixtureRoot 'valid.swf'
  Write-TestScaleformMovie -Path $validMovie
  [void](Assert-CanvasScaleformFile -Path $validMovie -Description 'Fixture movie')
  $shortMovie = Join-Path $fixtureRoot 'short.swf'
  [System.IO.File]::WriteAllBytes($shortMovie, [byte[]](1, 2, 3))
  Assert-TestRejected -Description 'Short Scaleform movie' -ExpectedMessage 'too short' -Action {
    [void](Assert-CanvasScaleformFile -Path $shortMovie -Description 'Short fixture')
  }
  $invalidMovie = Join-Path $fixtureRoot 'invalid.swf'
  Write-TestScaleformMovie -Path $invalidMovie -Signature 'BAD'
  Assert-TestRejected -Description 'Invalid Scaleform header' -ExpectedMessage 'unsupported Scaleform header' -Action {
    [void](Assert-CanvasScaleformFile -Path $invalidMovie -Description 'Invalid fixture')
  }

  $patchPath = Join-Path $fixtureRoot 'fixture-patch.xml'
  Write-CanvasUtf8WithoutBom -Path $patchPath -Text @'
<?xml version="1.0" encoding="utf-8"?>
<actionScriptPatch script="Fixture">
  <validation>
    <requiredSourceTokens><token>insertedByCanvas</token></requiredSourceTokens>
    <requiredInspectionTokens><token>insertedByCanvas</token></requiredInspectionTokens>
  </validation>
  <insertions>
    <insertion position="after"><anchor><![CDATA[trace("anchor");]]></anchor><content><![CDATA[
      trace("insertedByCanvas");]]></content></insertion>
  </insertions>
</actionScriptPatch>
'@
  $sourcePath = Join-Path $fixtureRoot 'Fixture.as'
  Write-CanvasUtf8WithoutBom -Path $sourcePath -Text 'trace("anchor");'
  $patch = Get-CanvasActionScriptPatch -PatchPath $patchPath
  Apply-ActionScriptPatch -SourcePath $sourcePath -Patch $patch
  if (![System.IO.File]::ReadAllText($sourcePath).Contains('insertedByCanvas')) {
    throw 'Canvas ActionScript patch did not write its required source token.'
  }
  $missingAnchorPath = Join-Path $fixtureRoot 'missing-anchor.as'
  Write-CanvasUtf8WithoutBom -Path $missingAnchorPath -Text 'trace("different");'
  Assert-TestRejected -Description 'Missing ActionScript anchor' -ExpectedMessage 'found 0' -Action {
    Apply-ActionScriptPatch -SourcePath $missingAnchorPath -Patch $patch
  }
  $duplicateAnchorPath = Join-Path $fixtureRoot 'duplicate-anchor.as'
  Write-CanvasUtf8WithoutBom -Path $duplicateAnchorPath -Text ('trace("anchor");' + "`n" + 'trace("anchor");')
  Assert-TestRejected -Description 'Duplicate ActionScript anchor' -ExpectedMessage 'found 2' -Action {
    Apply-ActionScriptPatch -SourcePath $duplicateAnchorPath -Patch $patch
  }

  $playerNames = @('playerhudcomponents.swf', 'playerhudcomponents.gfx', 'playerhudcomponents_lrg.swf', 'playerhudcomponents_lrg.gfx')
  $playerDefinition = Get-CanvasPlayerHudBuildDefinition -DefinitionPath (Join-Path $repositoryRoot 'Scaleform\canvas\build\player-hud-watch.build.psd1')
  Assert-CanvasExactNames -Actual @($playerDefinition.Movies) -Expected $playerNames -Description 'Player HUD definition fixture'
  $shipDefinitions = @(
    (Get-CanvasPatchedMovieBuildDefinition -ManifestPath (Join-Path $repositoryRoot 'Scaleform\canvas\build\spaceshiphudmenu.build.xml')),
    (Get-CanvasPatchedMovieBuildDefinition -ManifestPath (Join-Path $repositoryRoot 'Scaleform\canvas\build\spaceshiphudmenu-lrg.build.xml'))
  )
  $shipNames = @('spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf')
  Assert-CanvasExactNames -Actual @($shipDefinitions.InputFile) -Expected $shipNames -Description 'Ship HUD input fixture'
  Assert-CanvasExactNames -Actual @($shipDefinitions.OutputFile) -Expected $shipNames -Description 'Ship HUD output fixture'

  $outputRoot = Join-Path $fixtureRoot 'output'
  $publicationWork = Join-Path $fixtureRoot 'publication-work'
  $playerCandidate = Join-Path $fixtureRoot 'player-candidate'
  $playerDestination = Join-Path $outputRoot 'player-hud'
  $shipDestination = Join-Path $outputRoot 'ship-hud'
  New-Item -ItemType Directory -Path $publicationWork, $playerCandidate, $playerDestination, $shipDestination | Out-Null
  foreach ($name in $playerNames) { Write-TestScaleformMovie -Path (Join-Path $playerCandidate $name) -Marker "new-$name" }
  Write-TestScaleformMovie -Path (Join-Path $playerDestination 'obsolete-player.swf') -Marker 'obsolete-player'
  Write-TestScaleformMovie -Path (Join-Path $shipDestination 'retained-ship.swf') -Marker 'retained-ship'
  $unselectedShipDigest = Get-TestDirectoryDigest -Path $shipDestination
  Publish-CanvasValidatedHudOutputSet -CandidateDirectory $playerCandidate -DestinationDirectory $playerDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot -ExpectedFiles $playerNames -Description 'Player HUD fixture'
  Assert-CanvasScaleformOutputSet -Directory $playerDestination -ExpectedFiles $playerNames -Description 'Published Player HUD fixture'
  if ((Get-TestDirectoryDigest -Path $shipDestination) -cne $unselectedShipDigest) {
    throw 'Publishing Player HUD changed the unselected Ship HUD directory.'
  }

  $invalidCandidate = Join-Path $fixtureRoot 'invalid-candidate'
  New-Item -ItemType Directory -Path $invalidCandidate | Out-Null
  foreach ($name in $playerNames) { Write-TestScaleformMovie -Path (Join-Path $invalidCandidate $name) }
  Write-TestScaleformMovie -Path (Join-Path $invalidCandidate 'obsolete-player.swf')
  $playerDigestBeforeAdmission = Get-TestDirectoryDigest -Path $playerDestination
  Assert-TestRejected -Description 'HUD candidate with stale file' -ExpectedMessage 'file inventory differs' -Action {
    Publish-CanvasValidatedHudOutputSet -CandidateDirectory $invalidCandidate -DestinationDirectory $playerDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot -ExpectedFiles $playerNames -Description 'Invalid Player HUD fixture'
  }
  if ((Get-TestDirectoryDigest -Path $playerDestination) -cne $playerDigestBeforeAdmission) {
    throw 'Rejected HUD candidate changed the published destination.'
  }
  $missingCandidate = Join-Path $fixtureRoot 'missing-candidate'
  New-Item -ItemType Directory -Path $missingCandidate | Out-Null
  foreach ($name in $playerNames[0..2]) { Write-TestScaleformMovie -Path (Join-Path $missingCandidate $name) }
  Assert-TestRejected -Description 'HUD candidate with missing file' -ExpectedMessage 'file inventory differs' -Action {
    Publish-CanvasValidatedHudOutputSet -CandidateDirectory $missingCandidate -DestinationDirectory $playerDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot -ExpectedFiles $playerNames -Description 'Incomplete Player HUD fixture'
  }
  if ((Get-TestDirectoryDigest -Path $playerDestination) -cne $playerDigestBeforeAdmission) {
    throw 'Incomplete HUD candidate changed the published destination.'
  }

  $rollbackCandidate = Join-Path $fixtureRoot 'rollback-candidate'
  $rollbackDestination = Join-Path $outputRoot 'rollback-hud'
  New-Item -ItemType Directory -Path $rollbackCandidate, $rollbackDestination | Out-Null
  Write-TestScaleformMovie -Path (Join-Path $rollbackCandidate 'new.swf') -Marker 'new'
  Write-TestScaleformMovie -Path (Join-Path $rollbackDestination 'old.swf') -Marker 'old'
  $rollbackDigest = Get-TestDirectoryDigest -Path $rollbackDestination
  $originalMove = ${function:Invoke-CanvasHudDirectoryMove}
  $script:hudMoveCount = 0
  function Invoke-CanvasHudDirectoryMove {
    param([string]$Source, [string]$Destination)
    $script:hudMoveCount++
    if ($script:hudMoveCount -eq 2) { throw 'Fixture publication failure' }
    Move-Item -LiteralPath $Source -Destination $Destination
  }
  try {
    Assert-TestRejected -Description 'HUD publication failure' -ExpectedMessage 'Fixture publication failure' -Action {
      Publish-CanvasHudOutputSet -CandidateDirectory $rollbackCandidate -DestinationDirectory $rollbackDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot
    }
  }
  finally {
    Set-Item -LiteralPath Function:Invoke-CanvasHudDirectoryMove -Value $originalMove
  }
  if ((Get-TestDirectoryDigest -Path $rollbackDestination) -cne $rollbackDigest -or !(Test-Path -LiteralPath $rollbackCandidate -PathType Container)) {
    throw 'Failed HUD publication did not restore the prior destination and retain the candidate.'
  }

  $cleanupCandidate = Join-Path $fixtureRoot 'cleanup-candidate'
  $cleanupDestination = Join-Path $outputRoot 'cleanup-hud'
  New-Item -ItemType Directory -Path $cleanupCandidate, $cleanupDestination | Out-Null
  Write-TestScaleformMovie -Path (Join-Path $cleanupCandidate 'new.swf') -Marker 'new'
  Write-TestScaleformMovie -Path (Join-Path $cleanupDestination 'old.swf') -Marker 'old'
  $originalRemoval = ${function:Invoke-CanvasHudDirectoryRemoval}
  function Invoke-CanvasHudDirectoryRemoval { param([string]$Path) throw "Fixture cleanup failure: $Path" }
  try {
    Assert-TestRejected -Description 'HUD recovery cleanup failure' -ExpectedMessage 'Fixture cleanup failure' -Action {
      Publish-CanvasHudOutputSet -CandidateDirectory $cleanupCandidate -DestinationDirectory $cleanupDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot
    }
  }
  finally {
    Set-Item -LiteralPath Function:Invoke-CanvasHudDirectoryRemoval -Value $originalRemoval
  }
  if (!(Test-Path -LiteralPath (Join-Path $cleanupDestination 'new.swf') -PathType Leaf) -or
      @(Get-ChildItem -LiteralPath $publicationWork -Directory -Filter 'hud-publication-backup-*').Count -ne 1) {
    throw 'HUD cleanup failure did not retain both the published output and unique recovery directory.'
  }

  $publishedPlayerDigest = Get-TestDirectoryDigest -Path $playerDestination
  $shipCandidate = Join-Path $fixtureRoot 'ship-candidate'
  New-Item -ItemType Directory -Path $shipCandidate | Out-Null
  foreach ($name in $shipNames) { Write-TestScaleformMovie -Path (Join-Path $shipCandidate $name) -Marker "new-$name" }
  Publish-CanvasValidatedHudOutputSet -CandidateDirectory $shipCandidate -DestinationDirectory $shipDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot -ExpectedFiles $shipNames -Description 'Ship HUD fixture'
  if ((Get-TestDirectoryDigest -Path $playerDestination) -cne $publishedPlayerDigest) {
    throw 'Publishing Ship HUD changed the unselected Player HUD directory.'
  }

  $builderPath = Join-Path $repositoryRoot 'Tools\buildScaleform.ps1'
  $tokens = $null
  $parseErrors = $null
  $builderAst = [System.Management.Automation.Language.Parser]::ParseFile($builderPath, [ref]$tokens, [ref]$parseErrors)
  if ($parseErrors.Count -ne 0) { throw "buildScaleform.ps1 does not parse: $($parseErrors[0].Message)" }
  $parameterNames = @($builderAst.ParamBlock.Parameters.Name.VariablePath.UserPath)
  Assert-CanvasExactNames -Actual $parameterNames -Expected @('VariantKeys', 'JavaPath', 'JpexsJarPath', 'FlexSdkPath', 'VanillaInterfacePath', 'OutputDirectory', 'WorkDirectory', 'KeepWork') -Description 'Scaleform build parameters'
  $builderSource = [System.IO.File]::ReadAllText($builderPath)
  if ($builderSource -match '(?i)VwHud|EnvironmentPath|EstablishExpectedHashes|build-evidence|Archive2|TOOL_PATH_ARCHIVER|STEAM_DATA_FOLDER') {
    throw 'Scaleform build still contains a retired repository, environment, extraction, or evidence dependency.'
  }
  if (!$builderSource.Contains('$buildHud -and [string]::IsNullOrWhiteSpace($VanillaInterfacePath)')) {
    throw 'Scaleform build does not condition VanillaInterfacePath on a selected Canvas HUD build.'
  }
  $sharedSource = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'Tools\sharedCanvasScaleform.ps1'))
  if (!$sharedSource.Contains("'-selectclass', `$patch.Script")) {
    throw 'Canvas HUD patch export is not restricted to the declared patch class.'
  }

  Write-Host -ForegroundColor Green 'Canvas Scaleform helper tests passed. Native Java/JPEXS/Flex and game-runtime acceptance were not invoked.'
}
finally {
  if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}
