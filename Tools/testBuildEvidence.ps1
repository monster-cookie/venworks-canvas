<#
.SYNOPSIS
Exercises Canvas-owned Scaleform patch and publication helpers.
.DESCRIPTION
Uses local fixture movies and ActionScript text. Java, JPEXS, Apache Flex, and the game runtime are intentionally not invoked.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1')
. (Join-Path $PSScriptRoot 'sharedScaleform.ps1')

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
    "$relative`:$((Get-BuildFileSha256 -Path $_.FullName))"
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
  [void](Assert-BuildScaleformFile -Path $validMovie -Description 'Fixture movie')
  $shortMovie = Join-Path $fixtureRoot 'short.swf'
  [System.IO.File]::WriteAllBytes($shortMovie, [byte[]](1, 2, 3))
  Assert-TestRejected -Description 'Short Scaleform movie' -ExpectedMessage 'too short' -Action {
    [void](Assert-BuildScaleformFile -Path $shortMovie -Description 'Short fixture')
  }
  $invalidMovie = Join-Path $fixtureRoot 'invalid.swf'
  Write-TestScaleformMovie -Path $invalidMovie -Signature 'BAD'
  Assert-TestRejected -Description 'Invalid Scaleform header' -ExpectedMessage 'unsupported Scaleform header' -Action {
    [void](Assert-BuildScaleformFile -Path $invalidMovie -Description 'Invalid fixture')
  }

  $patchPath = Join-Path $fixtureRoot 'fixture-patch.xml'
  Write-BuildUtf8WithoutBom -Path $patchPath -Text @'
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
  Write-BuildUtf8WithoutBom -Path $sourcePath -Text 'trace("anchor");'
  $patch = Get-BuildActionScriptPatch -PatchPath $patchPath
  Apply-BuildActionScriptPatch -SourcePath $sourcePath -Patch $patch
  if (![System.IO.File]::ReadAllText($sourcePath).Contains('insertedByCanvas')) {
    throw 'Canvas ActionScript patch did not write its required source token.'
  }
  $missingAnchorPath = Join-Path $fixtureRoot 'missing-anchor.as'
  Write-BuildUtf8WithoutBom -Path $missingAnchorPath -Text 'trace("different");'
  Assert-TestRejected -Description 'Missing ActionScript anchor' -ExpectedMessage 'found 0' -Action {
    Apply-BuildActionScriptPatch -SourcePath $missingAnchorPath -Patch $patch
  }
  $duplicateAnchorPath = Join-Path $fixtureRoot 'duplicate-anchor.as'
  Write-BuildUtf8WithoutBom -Path $duplicateAnchorPath -Text ('trace("anchor");' + "`n" + 'trace("anchor");')
  Assert-TestRejected -Description 'Duplicate ActionScript anchor' -ExpectedMessage 'found 2' -Action {
    Apply-BuildActionScriptPatch -SourcePath $duplicateAnchorPath -Patch $patch
  }

  $normalizationWork = Join-Path $fixtureRoot 'normalization-work'
  $normalizedMovie = Join-Path $normalizationWork 'normalized.swf'
  New-Item -ItemType Directory -Path $normalizationWork | Out-Null
  $originalNormalizerJavaJar = ${function:Invoke-BuildJavaJar}
  $script:normalizerInvocationCount = 0
  function Invoke-BuildJavaJar {
    param([string]$JavaPath, [string]$JarPath, [string[]]$Arguments, [string]$Description)
    if ($JavaPath -cne 'fixture-java' -or $JarPath -cne 'fixture-jpexs') {
      throw "Scaleform normalizer forwarded unexpected tool paths: Java '$JavaPath', JPEXS '$JarPath'."
    }
    $script:normalizerInvocationCount++
    if ($Arguments[0] -ceq '-swf2xml') {
      Write-BuildUtf8WithoutBom -Path $Arguments[2] -Text '<swf><tags><item type="FileAttributesTag" hasMetadata="true"/><item type="MetadataTag"/><item type="ProductInfoTag"/></tags></swf>'
      return
    }
    if ($Arguments[0] -ceq '-xml2swf') {
      Write-TestScaleformMovie -Path $Arguments[2] -Marker 'normalized'
      return
    }
    throw "Unexpected normalizer invocation: $Description"
  }
  try {
    ConvertTo-BuildNormalizedScaleformMovie -JavaPath 'fixture-java' -JpexsJarPath 'fixture-jpexs' -InputPath 'fixture-input' -OutputPath $normalizedMovie -WorkPath $normalizationWork
    if ($script:normalizerInvocationCount -ne 2) {
      throw "Scaleform normalizer invoked its tool seam $script:normalizerInvocationCount times instead of twice."
    }
    [void](Assert-BuildScaleformFile -Path $normalizedMovie -Description 'Normalized fixture movie')
    [xml]$normalizedXml = Get-Content -LiteralPath (Join-Path $normalizationWork 'normalized.xml') -Raw
    if ($normalizedXml.SelectNodes('/swf/tags/item[@type="MetadataTag" or @type="ProductInfoTag"]').Count -ne 0 -or
        [string]$normalizedXml.SelectSingleNode('/swf/tags/item[@type="FileAttributesTag"]').hasMetadata -cne 'false') {
      throw 'Scaleform normalizer did not remove volatile metadata from the actual XML conversion path.'
    }

    $preexistingWork = Join-Path $fixtureRoot 'normalization-preexisting'
    New-Item -ItemType Directory -Path $preexistingWork | Out-Null
    Write-BuildUtf8WithoutBom -Path (Join-Path $preexistingWork 'compiled.xml') -Text '<existing/>'
    $script:normalizerInvocationCount = 0
    Assert-TestRejected -Description 'Preexisting normalizer work path' -ExpectedMessage 'must be fresh' -Action {
      ConvertTo-BuildNormalizedScaleformMovie -JavaPath 'fixture-java' -JpexsJarPath 'fixture-jpexs' -InputPath 'fixture-input' -OutputPath (Join-Path $preexistingWork 'normalized.swf') -WorkPath $preexistingWork
    }
    if ($script:normalizerInvocationCount -ne 0) {
      throw 'Scaleform normalizer invoked its tool seam after rejecting a preexisting work path.'
    }
  }
  finally {
    Set-Item -LiteralPath Function:Invoke-BuildJavaJar -Value $originalNormalizerJavaJar
  }

  $nativeInputPath = Join-Path $fixtureRoot 'native-input.swf'
  $nativeOutputPath = Join-Path $fixtureRoot 'native-output.swf'
  $fakeJavaPath = Join-Path $fixtureRoot 'java.exe'
  $fakeJpexsPath = Join-Path $fixtureRoot 'ffdec.jar'
  $fakeFlexPath = Join-Path $fixtureRoot 'flex'
  Write-TestScaleformMovie -Path $nativeInputPath
  [System.IO.File]::WriteAllBytes($fakeJavaPath, [byte[]](0))
  [System.IO.File]::WriteAllBytes($fakeJpexsPath, [byte[]](0))
  New-Item -ItemType Directory -Path $fakeFlexPath | Out-Null
  $originalJavaJar = ${function:Invoke-BuildJavaJar}
  function Invoke-BuildJavaJar { throw 'Fixture native failure' }
  try {
    Assert-TestRejected -Description 'Native Scaleform tool failure' -ExpectedMessage 'Fixture native failure' -Action {
      [void](Invoke-BuildPatchedScaleformMovie -InputPath $nativeInputPath -OutputPath $nativeOutputPath -PatchPath $patchPath -JavaPath $fakeJavaPath -JpexsJarPath $fakeJpexsPath -FlexSdkPath $fakeFlexPath -WorkDirectory (Join-Path $fixtureRoot 'native-work'))
    }
  }
  finally {
    Set-Item -LiteralPath Function:Invoke-BuildJavaJar -Value $originalJavaJar
  }
  if (Test-Path -LiteralPath $nativeOutputPath) {
    throw 'Failed native Scaleform job left an output candidate.'
  }
  Write-TestScaleformMovie -Path $nativeOutputPath
  Assert-TestRejected -Description 'Preexisting native output' -ExpectedMessage 'not fresh' -Action {
    [void](Invoke-BuildPatchedScaleformMovie -InputPath $nativeInputPath -OutputPath $nativeOutputPath -PatchPath $patchPath -JavaPath $fakeJavaPath -JpexsJarPath $fakeJpexsPath -FlexSdkPath $fakeFlexPath -WorkDirectory (Join-Path $fixtureRoot 'native-work'))
  }

  $arbitraryVariant = [pscustomobject]@{
    VariantKey = 'ARBITRARY'
    ScaleformBuilds = @(@{
      Name = 'arbitrary-patch'
      Kind = 'Patch'
      OutputSet = 'arbitrary-output'
      PatchPath = [System.IO.Path]::GetRelativePath($repositoryRoot, $patchPath)
      Outputs = @(@{ InputFile = 'input.swf'; OutputFile = 'output.swf' })
    })
  }
  $arbitraryJobs = @(ConvertTo-BuildScaleformJobs -Variants @($arbitraryVariant) -RepositoryRoot $repositoryRoot)
  if ($arbitraryJobs.Count -ne 1 -or $arbitraryJobs[0].VariantKey -cne 'ARBITRARY' -or $arbitraryJobs[0].OutputSet -cne 'arbitrary-output') {
    throw 'Scaleform job conversion did not preserve arbitrary variant configuration.'
  }

  $configuredJobs = @(ConvertTo-BuildScaleformJobs -Variants @(Get-ModuleVariants) -RepositoryRoot $repositoryRoot)
  Assert-BuildExactNames -Actual @($configuredJobs.Name) -Expected @('canvas-host', 'player-watch', 'ship-loader', 'canvas-example', 'canvas-component-gallery') -Description 'Configured Scaleform jobs'
  $playerJob = @($configuredJobs | Where-Object { $_.Name -ceq 'player-watch' })[0]
  $playerNames = @('playerhudcomponents.swf', 'playerhudcomponents.gfx', 'playerhudcomponents_lrg.swf', 'playerhudcomponents_lrg.gfx')
  Assert-BuildExactNames -Actual @($playerJob.Outputs.InputFile) -Expected $playerNames -Description 'Player HUD input configuration'
  Assert-BuildExactNames -Actual @($playerJob.Outputs.OutputFile) -Expected $playerNames -Description 'Player HUD output configuration'
  $shipJob = @($configuredJobs | Where-Object { $_.Name -ceq 'ship-loader' })[0]
  $shipNames = @('spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf')
  Assert-BuildExactNames -Actual @($shipJob.Outputs.InputFile) -Expected $shipNames -Description 'Ship HUD input configuration'
  Assert-BuildExactNames -Actual @($shipJob.Outputs.OutputFile) -Expected $shipNames -Description 'Ship HUD output configuration'

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
  Publish-BuildValidatedScaleformOutputSet -CandidateDirectory $playerCandidate -DestinationDirectory $playerDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot -ExpectedFiles $playerNames -Description 'Player HUD fixture'
  Assert-BuildScaleformOutputSet -Directory $playerDestination -ExpectedFiles $playerNames -Description 'Published Player HUD fixture'
  if ((Get-TestDirectoryDigest -Path $shipDestination) -cne $unselectedShipDigest) {
    throw 'Publishing Player HUD changed the unselected Ship HUD directory.'
  }

  $invalidCandidate = Join-Path $fixtureRoot 'invalid-candidate'
  New-Item -ItemType Directory -Path $invalidCandidate | Out-Null
  foreach ($name in $playerNames) { Write-TestScaleformMovie -Path (Join-Path $invalidCandidate $name) }
  Write-TestScaleformMovie -Path (Join-Path $invalidCandidate 'obsolete-player.swf')
  $playerDigestBeforeAdmission = Get-TestDirectoryDigest -Path $playerDestination
  Assert-TestRejected -Description 'HUD candidate with stale file' -ExpectedMessage 'file inventory differs' -Action {
    Publish-BuildValidatedScaleformOutputSet -CandidateDirectory $invalidCandidate -DestinationDirectory $playerDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot -ExpectedFiles $playerNames -Description 'Invalid Player HUD fixture'
  }
  if ((Get-TestDirectoryDigest -Path $playerDestination) -cne $playerDigestBeforeAdmission) {
    throw 'Rejected HUD candidate changed the published destination.'
  }
  $missingCandidate = Join-Path $fixtureRoot 'missing-candidate'
  New-Item -ItemType Directory -Path $missingCandidate | Out-Null
  foreach ($name in $playerNames[0..2]) { Write-TestScaleformMovie -Path (Join-Path $missingCandidate $name) }
  Assert-TestRejected -Description 'HUD candidate with missing file' -ExpectedMessage 'file inventory differs' -Action {
    Publish-BuildValidatedScaleformOutputSet -CandidateDirectory $missingCandidate -DestinationDirectory $playerDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot -ExpectedFiles $playerNames -Description 'Incomplete Player HUD fixture'
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
  $originalMove = ${function:Invoke-BuildScaleformDirectoryMove}
  $script:hudMoveCount = 0
  function Invoke-BuildScaleformDirectoryMove {
    param([string]$Source, [string]$Destination)
    $script:hudMoveCount++
    if ($script:hudMoveCount -eq 2) { throw 'Fixture publication failure' }
    Move-Item -LiteralPath $Source -Destination $Destination
  }
  try {
    Assert-TestRejected -Description 'HUD publication failure' -ExpectedMessage 'Fixture publication failure' -Action {
      Publish-BuildScaleformOutputSet -CandidateDirectory $rollbackCandidate -DestinationDirectory $rollbackDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot
    }
  }
  finally {
    Set-Item -LiteralPath Function:Invoke-BuildScaleformDirectoryMove -Value $originalMove
  }
  if ((Get-TestDirectoryDigest -Path $rollbackDestination) -cne $rollbackDigest -or !(Test-Path -LiteralPath $rollbackCandidate -PathType Container)) {
    throw 'Failed HUD publication did not restore the prior destination and retain the candidate.'
  }

  $cleanupCandidate = Join-Path $fixtureRoot 'cleanup-candidate'
  $cleanupDestination = Join-Path $outputRoot 'cleanup-hud'
  New-Item -ItemType Directory -Path $cleanupCandidate, $cleanupDestination | Out-Null
  Write-TestScaleformMovie -Path (Join-Path $cleanupCandidate 'new.swf') -Marker 'new'
  Write-TestScaleformMovie -Path (Join-Path $cleanupDestination 'old.swf') -Marker 'old'
  $originalRemoval = ${function:Invoke-BuildScaleformDirectoryRemoval}
  function Invoke-BuildScaleformDirectoryRemoval { param([string]$Path) throw "Fixture cleanup failure: $Path" }
  try {
    Assert-TestRejected -Description 'HUD recovery cleanup failure' -ExpectedMessage 'Fixture cleanup failure' -Action {
      Publish-BuildScaleformOutputSet -CandidateDirectory $cleanupCandidate -DestinationDirectory $cleanupDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot
    }
  }
  finally {
    Set-Item -LiteralPath Function:Invoke-BuildScaleformDirectoryRemoval -Value $originalRemoval
  }
  if (!(Test-Path -LiteralPath (Join-Path $cleanupDestination 'new.swf') -PathType Leaf) -or
      @(Get-ChildItem -LiteralPath $publicationWork -Directory -Filter 'scaleform-publication-backup-*').Count -ne 1) {
    throw 'HUD cleanup failure did not retain both the published output and unique recovery directory.'
  }

  $publishedPlayerDigest = Get-TestDirectoryDigest -Path $playerDestination
  $shipCandidate = Join-Path $fixtureRoot 'ship-candidate'
  New-Item -ItemType Directory -Path $shipCandidate | Out-Null
  foreach ($name in $shipNames) { Write-TestScaleformMovie -Path (Join-Path $shipCandidate $name) -Marker "new-$name" }
  Publish-BuildValidatedScaleformOutputSet -CandidateDirectory $shipCandidate -DestinationDirectory $shipDestination -WorkDirectory $publicationWork -AllowedRoot $fixtureRoot -ExpectedFiles $shipNames -Description 'Ship HUD fixture'
  if ((Get-TestDirectoryDigest -Path $playerDestination) -cne $publishedPlayerDigest) {
    throw 'Publishing Ship HUD changed the unselected Player HUD directory.'
  }

  $movieCandidate = Join-Path $fixtureRoot 'selected-movie.swf'
  $movieDestination = Join-Path $outputRoot 'movies'
  New-Item -ItemType Directory -Path $movieDestination | Out-Null
  Write-TestScaleformMovie -Path $movieCandidate -Marker 'selected-new'
  Write-TestScaleformMovie -Path (Join-Path $movieDestination 'selected.swf') -Marker 'selected-old'
  Write-TestScaleformMovie -Path (Join-Path $movieDestination 'unselected.swf') -Marker 'unselected'
  $unselectedHash = Get-BuildFileSha256 -Path (Join-Path $movieDestination 'unselected.swf')
  Publish-BuildScaleformFile -CandidatePath $movieCandidate -DestinationPath (Join-Path $movieDestination 'selected.swf') -AllowedRoot $fixtureRoot
  if ((Get-BuildFileSha256 -Path (Join-Path $movieDestination 'unselected.swf')) -cne $unselectedHash) {
    throw 'Publishing a selected movie changed an unselected movie output.'
  }

  $orchestrationRoot = Join-Path $fixtureRoot 'orchestration'
  $orchestrationInput = Join-Path $orchestrationRoot 'input'
  $orchestrationOutput = Join-Path $orchestrationRoot 'output'
  $orchestrationWork = Join-Path $orchestrationRoot 'work'
  $orchestrationFlex = Join-Path $orchestrationRoot 'flex'
  $orchestrationDestination = Join-Path $orchestrationOutput 'recovery-set'
  New-Item -ItemType Directory -Path $orchestrationInput, $orchestrationDestination, $orchestrationFlex | Out-Null
  $orchestrationInputMovie = Join-Path $orchestrationInput 'input.swf'
  $orchestrationPriorMovie = Join-Path $orchestrationDestination 'prior.swf'
  $orchestrationJava = Join-Path $orchestrationRoot 'java.exe'
  $orchestrationJpexs = Join-Path $orchestrationRoot 'ffdec.jar'
  Write-TestScaleformMovie -Path $orchestrationInputMovie -Marker 'input'
  Write-TestScaleformMovie -Path $orchestrationPriorMovie -Marker 'prior-output'
  [System.IO.File]::WriteAllBytes($orchestrationJava, [byte[]](0))
  [System.IO.File]::WriteAllBytes($orchestrationJpexs, [byte[]](0))
  $priorMovieHash = Get-BuildFileSha256 -Path $orchestrationPriorMovie
  $orchestrationJob = [pscustomobject]@{
    Name = 'recovery-job'
    Kind = 'Patch'
    OutputSet = 'recovery-set'
    PatchPath = 'fixture-patch'
    Outputs = @([pscustomobject]@{ InputFile = 'input.swf'; OutputFile = 'candidate.swf' })
  }
  $originalPatchedMovieBuild = ${function:Invoke-BuildPatchedScaleformMovie}
  $originalOrchestrationMove = ${function:Invoke-BuildScaleformDirectoryMove}
  $script:orchestrationMoveCount = 0
  $script:orchestrationBackupPath = $null
  $orchestrationWorkPrefix = [System.IO.Path]::GetFullPath($orchestrationWork).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
  function Invoke-BuildPatchedScaleformMovie {
    param([string]$InputPath, [string]$OutputPath, [string]$PatchPath, [string]$JavaPath, [string]$JpexsJarPath, [string]$FlexSdkPath, [string]$WorkDirectory, [switch]$KeepWork)
    if ([System.IO.Path]::GetFullPath($InputPath) -cne [System.IO.Path]::GetFullPath($orchestrationInputMovie) -or
        [System.IO.Path]::GetFullPath($JavaPath) -cne [System.IO.Path]::GetFullPath($orchestrationJava) -or
        [System.IO.Path]::GetFullPath($JpexsJarPath) -cne [System.IO.Path]::GetFullPath($orchestrationJpexs) -or
        [System.IO.Path]::GetFullPath($FlexSdkPath) -cne [System.IO.Path]::GetFullPath($orchestrationFlex) -or
        $PatchPath -cne 'fixture-patch' -or
        ![System.IO.Path]::GetFullPath($OutputPath).StartsWith($orchestrationWorkPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        ![System.IO.Path]::GetFullPath($WorkDirectory).StartsWith($orchestrationWorkPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $KeepWork.IsPresent) {
      throw 'Scaleform orchestration did not forward the configured patch job arguments to the movie builder.'
    }
    Write-TestScaleformMovie -Path $OutputPath -Marker 'candidate-output'
    return $OutputPath
  }
  function Invoke-BuildScaleformDirectoryMove {
    param([string]$Source, [string]$Destination)
    $script:orchestrationMoveCount++
    if ($script:orchestrationMoveCount -eq 1) {
      $script:orchestrationBackupPath = $Destination
      Move-Item -LiteralPath $Source -Destination $Destination
      return
    }
    throw "Fixture orchestration move failure $script:orchestrationMoveCount"
  }
  $orchestrationError = $null
  try {
    try {
      [void](Invoke-BuildScaleformJobs -Jobs @($orchestrationJob) -JavaPath $orchestrationJava -JpexsJarPath $orchestrationJpexs -FlexSdkPath $orchestrationFlex -InputDirectory $orchestrationInput -OutputDirectory $orchestrationOutput -WorkDirectory $orchestrationWork -AllowedRoot $orchestrationRoot)
    }
    catch {
      $orchestrationError = $_.Exception.Message
    }
  }
  finally {
    Set-Item -LiteralPath Function:Invoke-BuildPatchedScaleformMovie -Value $originalPatchedMovieBuild
    Set-Item -LiteralPath Function:Invoke-BuildScaleformDirectoryMove -Value $originalOrchestrationMove
  }
  if ($orchestrationError -notmatch "Recovery remains at '([^']+)'" -or $script:orchestrationMoveCount -ne 3) {
    throw "Scaleform orchestration did not report the injected failed restoration: $orchestrationError"
  }
  $reportedRecoveryPath = $Matches[1]
  if ([System.IO.Path]::GetFullPath($reportedRecoveryPath) -cne [System.IO.Path]::GetFullPath($script:orchestrationBackupPath) -or
      !(Test-Path -LiteralPath $reportedRecoveryPath -PathType Container) -or
      (Get-BuildFileSha256 -Path (Join-Path $reportedRecoveryPath 'prior.swf')) -cne $priorMovieHash) {
    throw 'Scaleform orchestration did not retain the reported prior-output recovery bytes.'
  }
  $retainedCandidates = @(Get-ChildItem -LiteralPath $orchestrationWork -Recurse -File -Filter 'candidate.swf')
  if ($retainedCandidates.Count -ne 1) {
    throw 'Scaleform orchestration did not retain the failed publication candidate with its recovery material.'
  }

  $builderPath = Join-Path $repositoryRoot 'Tools\buildScaleform.ps1'
  $tokens = $null
  $parseErrors = $null
  $builderAst = [System.Management.Automation.Language.Parser]::ParseFile($builderPath, [ref]$tokens, [ref]$parseErrors)
  if ($parseErrors.Count -ne 0) { throw "buildScaleform.ps1 does not parse: $($parseErrors[0].Message)" }
  $parameterNames = @($builderAst.ParamBlock.Parameters.Name.VariablePath.UserPath)
  Assert-BuildExactNames -Actual $parameterNames -Expected @('VariantKeys', 'JavaPath', 'JpexsJarPath', 'FlexSdkPath', 'VanillaInterfacePath', 'OutputDirectory', 'WorkDirectory', 'KeepWork') -Description 'Scaleform build parameters'
  $builderSource = [System.IO.File]::ReadAllText($builderPath)
  if ($builderSource -match '(?i)VwHud|EnvironmentPath|EstablishExpectedHashes|build-evidence|Archive2|TOOL_PATH_ARCHIVER|STEAM_DATA_FOLDER') {
    throw 'Scaleform build still contains a retired repository, environment, extraction, or evidence dependency.'
  }
  $sharedSource = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'Tools\sharedScaleform.ps1'))
  if (!$sharedSource.Contains("'-selectclass', `$patch.Script")) {
    throw 'Scaleform patch export is not restricted to the declared patch class.'
  }

  Write-Host -ForegroundColor Green 'Canvas Scaleform helper tests passed. Native Java/JPEXS/Flex and game-runtime acceptance were not invoked.'
}
finally {
  if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}
