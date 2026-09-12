<#
.SYNOPSIS
Exercises Canvas-owned Scaleform patch and publication helpers.
.DESCRIPTION
Uses local fixture movies and ActionScript text. Java, JPEXS, Apache Flex, and the game runtime are intentionally not invoked.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedVariants.ps1')
. (Join-Path $PSScriptRoot 'sharedBuild.ps1')
$sharedConfiguration = Get-Variable -Name SharedConfigurationLoaded -Scope Global -ErrorAction SilentlyContinue
if ($null -eq $sharedConfiguration -or ![bool]$sharedConfiguration.Value) {
  . (Join-Path $PSScriptRoot 'sharedConfig.ps1')
}
. (Join-Path $PSScriptRoot 'sharedScaleform.ps1')
. (Join-Path $PSScriptRoot 'sharedPackaging.ps1')

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

  $displayPatchPath = Join-Path $fixtureRoot 'display-mode-patch.xml'
  Write-BuildUtf8WithoutBom -Path $displayPatchPath -Text @'
<?xml version="1.0" encoding="utf-8"?>
<actionScriptPatch script="Fixture">
  <validation>
    <requiredSourceTokens><token>displayMode:String = "__VWCANVAS_DISPLAY_MODE__"</token></requiredSourceTokens>
    <requiredInspectionTokens><token>displayMode:String = "__VWCANVAS_DISPLAY_MODE__"</token></requiredInspectionTokens>
  </validation>
  <insertions>
    <insertion position="after"><anchor><![CDATA[trace("anchor");]]></anchor><content><![CDATA[
      var displayMode:String = "__VWCANVAS_DISPLAY_MODE__";]]></content></insertion>
  </insertions>
</actionScriptPatch>
'@
  Assert-TestRejected -Description 'Missing parameterized patch DisplayMode' -ExpectedMessage 'requires DisplayMode' -Action {
    [void](Get-BuildActionScriptPatch -PatchPath $displayPatchPath)
  }
  Assert-TestRejected -Description 'Invalid parameterized patch DisplayMode' -ExpectedMessage "unsupported DisplayMode 'compact'" -Action {
    [void](Get-BuildActionScriptPatch -PatchPath $displayPatchPath -DisplayMode 'compact')
  }
  Assert-TestRejected -Description 'DisplayMode on unparameterized patch' -ExpectedMessage 'does not support DisplayMode' -Action {
    [void](Get-BuildActionScriptPatch -PatchPath $patchPath -DisplayMode 'normal')
  }
  $normalDisplayPatch = Get-BuildActionScriptPatch -PatchPath $displayPatchPath -DisplayMode 'normal'
  $displaySourcePath = Join-Path $fixtureRoot 'DisplayFixture.as'
  Write-BuildUtf8WithoutBom -Path $displaySourcePath -Text 'trace("anchor");'
  Apply-BuildActionScriptPatch -SourcePath $displaySourcePath -Patch $normalDisplayPatch
  $displaySource = [IO.File]::ReadAllText($displaySourcePath)
  if (!$displaySource.Contains('displayMode:String = "normal"') -or $displaySource.Contains('__VWCANVAS_DISPLAY_MODE__') -or $displaySource.Contains('displayMode:String = "large"')) {
    throw 'Parameterized ActionScript patch did not select only the configured normal display mode.'
  }
  $largeDisplayPatch = Get-BuildActionScriptPatch -PatchPath $displayPatchPath -DisplayMode 'large'
  if (@($largeDisplayPatch.RequiredInspectionTokens).Count -ne 1 -or $largeDisplayPatch.RequiredInspectionTokens[0] -cne 'displayMode:String = "large"') {
    throw 'Parameterized ActionScript patch did not produce an exact large-mode inspection token.'
  }

  $playerLoaderPatchPath = Join-Path $repositoryRoot 'Scaleform\canvas\patches\player-hud-auxiliary-loader.xml'
  $playerLoaderPatch = Get-BuildActionScriptPatch -PatchPath $playerLoaderPatchPath -DisplayMode 'normal'
  $playerLoaderSourcePath = Join-Path $fixtureRoot 'HUDMenu.as'
  Write-BuildUtf8WithoutBom -Path $playerLoaderSourcePath -Text @'
package
{
   import flash.display.Loader;
   import flash.display.MovieClip;
   import flash.events.Event;
   import flash.net.URLRequest;

   public class HUDMenu extends MovieClip
   {
      private var SkillPatchLoader:Loader = null;

      override protected function onSetSafeRect() : void
      {
      }

      override public function onAddedToStage() : void
      {
         super.onAddedToStage();
         BSUIDataManager.Subscribe("HudModeData",function(param1:Object):* {});
      }
   }
}
'@
  Apply-BuildActionScriptPatch -SourcePath $playerLoaderSourcePath -Patch $playerLoaderPatch
  $playerLoaderSource = [System.IO.File]::ReadAllText($playerLoaderSourcePath)
  $startIndex = $playerLoaderSource.IndexOf('this.startVenworksCanvasRegistry();', [System.StringComparison]::Ordinal)
  $hudSubscriptionIndex = $playerLoaderSource.IndexOf('BSUIDataManager.Subscribe("HudModeData"', [System.StringComparison]::Ordinal)
  $directAttachIndex = $playerLoaderSource.IndexOf('addChild(this.VenworksCanvasRegistryBridge);', [System.StringComparison]::Ordinal)
  $deferredIndex = $playerLoaderSource.IndexOf('addEventListener(Event.ENTER_FRAME,this.onVenworksCanvasRegistryDeferredInitialize', [System.StringComparison]::Ordinal)
  $initializeIndex = $playerLoaderSource.IndexOf('this.VenworksCanvasRegistryBridge["initialize"](this,{"protocol":"VWCANVAS_HOST/1","hostKind":"player","displayMode":"normal"})', [System.StringComparison]::Ordinal)
  if ($startIndex -lt 0 -or $hudSubscriptionIndex -le $startIndex) {
    throw 'Player HUD auxiliary loader does not start from HUDMenu onAddedToStage before the vanilla HUD subscriptions.'
  }
  if ($directAttachIndex -lt 0 -or $deferredIndex -le $directAttachIndex -or $initializeIndex -le $deferredIndex) {
    throw 'Player HUD auxiliary loader does not attach CanvasHost directly and defer initialization by one frame.'
  }
  if ($playerLoaderSource.Contains('__VWCANVAS_DISPLAY_MODE__') -or $playerLoaderSource.Contains('"displayMode":"large"')) {
    throw 'Player HUD auxiliary loader normal-mode patch retained an unresolved or wrong display mode.'
  }
  if ($playerLoaderSource -match '(?i)VwHud') {
    throw 'Player HUD auxiliary loader unexpectedly depends on VWHUD.'
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

  $auxiliarySourceRoot = Join-Path $fixtureRoot 'auxiliary-source'
  $auxiliaryBuildRoot = Join-Path $auxiliarySourceRoot 'build'
  $auxiliaryAppRoot = Join-Path $auxiliarySourceRoot 'app'
  $auxiliaryCommonRoot = Join-Path $auxiliarySourceRoot 'common'
  $auxiliaryOutputRoot = Join-Path $fixtureRoot 'auxiliary-output'
  $auxiliaryWorkRoot = Join-Path $fixtureRoot 'auxiliary-work'
  $auxiliaryFlexRoot = Join-Path $fixtureRoot 'auxiliary-flex'
  $auxiliaryFrameworksRoot = Join-Path $auxiliaryFlexRoot 'frameworks'
  $auxiliaryJava = Join-Path $fixtureRoot 'auxiliary-java.exe'
  $auxiliaryJpexs = Join-Path $fixtureRoot 'auxiliary-ffdec.jar'
  $auxiliaryManifest = Join-Path $auxiliaryBuildRoot 'auxiliary.build.xml'
  New-Item -ItemType Directory -Path $auxiliaryBuildRoot, $auxiliaryAppRoot, $auxiliaryCommonRoot, (Join-Path $auxiliaryFlexRoot 'lib'), $auxiliaryFrameworksRoot | Out-Null
  Write-BuildUtf8WithoutBom -Path (Join-Path $auxiliaryAppRoot 'Main.as') -Text "package app`n{`n  import app.LocalHelper;`n  import common.Helper;`n  public class Main { }`n}"
  Write-BuildUtf8WithoutBom -Path (Join-Path $auxiliaryAppRoot 'LocalHelper.as') -Text "package app`n{`n  public class LocalHelper { }`n}"
  Write-BuildUtf8WithoutBom -Path (Join-Path $auxiliaryCommonRoot 'Helper.as') -Text "package common`n{`n  public class Helper { }`n}"
  Write-BuildUtf8WithoutBom -Path $auxiliaryManifest -Text @'
<movieBuild name="auxiliary" role="consumer" outputFile="Auxiliary.swf" documentClass="../app/Main.as" className="app.Main" stageWidth="640" stageHeight="480" frameRate="30">
  <requiredTokens><token>AUXILIARY_TOKEN</token></requiredTokens>
  <forbiddenTokens><token>FORBIDDEN_TOKEN</token></forbiddenTokens>
</movieBuild>
'@
  foreach ($filePath in @(
    $auxiliaryJava,
    $auxiliaryJpexs,
    (Join-Path $auxiliaryFlexRoot 'lib\mxmlc.jar'),
    (Join-Path $auxiliaryFrameworksRoot 'flex-config.xml'),
    (Join-Path $auxiliaryFrameworksRoot 'playerglobal.swc')
  )) {
    [System.IO.File]::WriteAllBytes($filePath, [byte[]](0))
  }
  $script:includeAuxiliaryDocumentClass = $true
  $originalAuxiliaryJavaJar = ${function:Invoke-BuildJavaJar}
  function Invoke-BuildJavaJar {
    param([string]$JavaPath, [string]$JarPath, [string[]]$Arguments, [string]$Description)
    if ([System.IO.Path]::GetFullPath($JavaPath) -cne [System.IO.Path]::GetFullPath($auxiliaryJava)) {
      throw "Auxiliary fixture received unexpected native tool paths for $Description."
    }
    $mxmlcJarPath = Join-Path $auxiliaryFlexRoot 'lib\mxmlc.jar'
    if ([System.IO.Path]::GetFullPath($JarPath) -ceq [System.IO.Path]::GetFullPath($mxmlcJarPath)) {
      $sourcePathIndex = [Array]::IndexOf($Arguments, '-compiler.source-path')
      $outputIndex = [Array]::IndexOf($Arguments, '-output')
      $isolatedSourceRoot = if ($sourcePathIndex -ge 0) { [string]$Arguments[$sourcePathIndex + 1] } else { '' }
      if ($Description -cne 'Apache Flex Scaleform compilation' -or
          $sourcePathIndex -lt 0 -or $outputIndex -lt 0 -or
          [System.IO.Path]::GetFullPath([string]$Arguments[$sourcePathIndex + 2]) -cne [System.IO.Path]::GetFullPath($auxiliaryAppRoot) -or
          [System.IO.Path]::GetFullPath([string]$Arguments[$sourcePathIndex + 3]) -cne [System.IO.Path]::GetFullPath($auxiliarySourceRoot) -or
          [string]$Arguments[$sourcePathIndex + 4] -cne '-compiler.debug=false' -or
          !(Test-Path -LiteralPath (Join-Path $isolatedSourceRoot 'Main.as') -PathType Leaf) -or
          !(Test-Path -LiteralPath (Join-Path ([string]$Arguments[$sourcePathIndex + 2]) 'LocalHelper.as') -PathType Leaf) -or
          !(Test-Path -LiteralPath (Join-Path ([string]$Arguments[$sourcePathIndex + 3]) 'common\Helper.as') -PathType Leaf) -or
          [System.IO.Path]::GetFullPath([string]$Arguments[-1]) -cne [System.IO.Path]::GetFullPath((Join-Path $isolatedSourceRoot 'Main.as'))) {
        throw 'Scaleform compiler arguments did not preserve the configured auxiliary source-root contract.'
      }
      Write-TestScaleformMovie -Path ([string]$Arguments[$outputIndex + 1]) -Marker 'compiled-auxiliary'
      return
    }
    if ([System.IO.Path]::GetFullPath($JarPath) -cne [System.IO.Path]::GetFullPath($auxiliaryJpexs)) {
      throw "Auxiliary fixture received unexpected native tool paths for $Description."
    }
    if ($Arguments[0] -ceq '-swf2xml') {
      Write-BuildUtf8WithoutBom -Path $Arguments[2] -Text '<swf><tags><item type="FileAttributesTag" hasMetadata="false"/></tags></swf>'
      return
    }
    if ($Arguments[0] -ceq '-xml2swf') {
      Write-TestScaleformMovie -Path $Arguments[2] -Marker 'normalized-auxiliary'
      return
    }
    if ($Arguments[0] -ceq '-format' -and $Arguments[2] -ceq '-export') {
      New-Item -ItemType Directory -Force -Path $Arguments[4] | Out-Null
      if ($script:includeAuxiliaryDocumentClass) {
        Write-BuildUtf8WithoutBom -Path (Join-Path $Arguments[4] 'Main.as') -Text "package app`n{`n  public class Main { public static var marker:String = 'AUXILIARY_TOKEN'; }`n}"
      }
      Write-BuildUtf8WithoutBom -Path (Join-Path $Arguments[4] 'Helper.as') -Text "package common`n{`n  public class Helper { }`n}"
      return
    }
    throw "Unexpected auxiliary JPEXS invocation for $Description."
  }
  try {
    $auxiliaryResult = Invoke-BuildScaleformMovieBuild -ManifestPath $auxiliaryManifest -OutputDirectory $auxiliaryOutputRoot -WorkDirectory $auxiliaryWorkRoot -JavaPath $auxiliaryJava -JpexsJarPath $auxiliaryJpexs -FlexSdkPath $auxiliaryFlexRoot -ScaleformSourceRoot $auxiliarySourceRoot
    if ($auxiliaryResult.OutputFile -cne 'Auxiliary.swf' -or !(Test-Path -LiteralPath (Join-Path $auxiliaryOutputRoot 'Auxiliary.swf') -PathType Leaf)) {
      throw 'Scaleform movie build did not publish the auxiliary-source fixture output.'
    }
    $script:includeAuxiliaryDocumentClass = $false
    Assert-TestRejected -Description 'Missing declared Scaleform document class' -ExpectedMessage "does not export declared class 'app.Main'" -Action {
      [void](Assert-BuildScaleformMovie -JavaPath $auxiliaryJava -JpexsJarPath $auxiliaryJpexs -MoviePath (Join-Path $auxiliaryOutputRoot 'Auxiliary.swf') -WorkPath (Join-Path $auxiliaryWorkRoot 'missing-document-class') -Definition (Get-BuildScaleformMovieDefinition -ManifestPath $auxiliaryManifest))
    }
  }
  finally {
    $script:includeAuxiliaryDocumentClass = $true
    Set-Item -LiteralPath Function:Invoke-BuildJavaJar -Value $originalAuxiliaryJavaJar
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
  $originalDisplayModeJavaJar = ${function:Invoke-BuildJavaJar}
  $script:compiledDisplayModeSource = $null
  function Invoke-BuildJavaJar {
    param([string]$JavaPath, [string]$JarPath, [string[]]$Arguments, [string]$Description)
    if ([IO.Path]::GetFullPath($JavaPath) -cne [IO.Path]::GetFullPath($fakeJavaPath) -or
        [IO.Path]::GetFullPath($JarPath) -cne [IO.Path]::GetFullPath($fakeJpexsPath)) {
      throw "Display-mode inspection fixture received unexpected native tool paths for $Description."
    }
    if ($Arguments -contains '-selectclass') {
      $exportIndex = [Array]::IndexOf($Arguments, '-export')
      Write-BuildUtf8WithoutBom -Path (Join-Path ([string]$Arguments[$exportIndex + 2]) 'Fixture.as') -Text 'trace("anchor");'
      return
    }
    if ($Arguments -contains '-importScript') {
      $importIndex = [Array]::IndexOf($Arguments, '-importScript')
      $exportDirectory = [string]$Arguments[$importIndex + 3]
      $script:compiledDisplayModeSource = [IO.File]::ReadAllText((Join-Path $exportDirectory 'Fixture.as'))
      Write-TestScaleformMovie -Path ([string]$Arguments[$importIndex + 2]) -Marker 'display-mode'
      return
    }
    if ($Arguments -contains '-export') {
      $exportIndex = [Array]::IndexOf($Arguments, '-export')
      Write-BuildUtf8WithoutBom -Path (Join-Path ([string]$Arguments[$exportIndex + 2]) 'Fixture.as') -Text $script:compiledDisplayModeSource
      return
    }
    throw "Unexpected display-mode inspection invocation: $Description"
  }
  try {
    foreach ($displayMode in @('normal', 'large')) {
      $displayModeOutput = Join-Path $fixtureRoot "native-$displayMode.swf"
      [void](Invoke-BuildPatchedScaleformMovie -InputPath $nativeInputPath -OutputPath $displayModeOutput -PatchPath $displayPatchPath -DisplayMode $displayMode -JavaPath $fakeJavaPath -JpexsJarPath $fakeJpexsPath -FlexSdkPath $fakeFlexPath -WorkDirectory (Join-Path $fixtureRoot "native-$displayMode-work"))
      if (!$script:compiledDisplayModeSource.Contains("displayMode:String = `"$displayMode`"") -or
          $script:compiledDisplayModeSource.Contains('__VWCANVAS_DISPLAY_MODE__') -or
          $script:compiledDisplayModeSource.Contains("displayMode:String = `"$(if ($displayMode -ceq 'normal') { 'large' } else { 'normal' })`"")) {
        throw "Compiled Scaleform inspection did not retain only the selected '$displayMode' display mode."
      }
    }
  }
  finally {
    Set-Item -LiteralPath Function:Invoke-BuildJavaJar -Value $originalDisplayModeJavaJar
  }
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

  $parameterizedVariant = [pscustomobject]@{
    VariantKey = 'PARAMETERIZED'
    ScaleformBuilds = @(@{
      Name = 'parameterized-patch'
      Kind = 'Patch'
      OutputSet = 'parameterized-output'
      PatchPath = [System.IO.Path]::GetRelativePath($repositoryRoot, $displayPatchPath)
      Outputs = @(@{ InputFile = 'input_lrg.swf'; OutputFile = 'output_lrg.swf'; DisplayMode = 'large' })
    })
  }
  $parameterizedJobs = @(ConvertTo-BuildScaleformJobs -Variants @($parameterizedVariant) -RepositoryRoot $repositoryRoot)
  if ($parameterizedJobs.Count -ne 1 -or $parameterizedJobs[0].Outputs[0].DisplayMode -cne 'large') {
    throw 'Scaleform job conversion did not preserve the configured output DisplayMode.'
  }
  $missingDisplayModeVariant = $parameterizedVariant.PSObject.Copy()
  $missingDisplayModeVariant.ScaleformBuilds = @(@{} + $parameterizedVariant.ScaleformBuilds[0])
  $missingDisplayModeVariant.ScaleformBuilds[0].Name = 'missing-display-mode'
  $missingDisplayModeVariant.ScaleformBuilds[0].Outputs = @(@{ InputFile = 'input.swf'; OutputFile = 'output.swf' })
  Assert-TestRejected -Description 'Missing output DisplayMode' -ExpectedMessage 'requires DisplayMode' -Action {
    [void](ConvertTo-BuildScaleformJobs -Variants @($missingDisplayModeVariant) -RepositoryRoot $repositoryRoot)
  }
  $invalidDisplayModeVariant = $parameterizedVariant.PSObject.Copy()
  $invalidDisplayModeVariant.ScaleformBuilds = @(@{} + $parameterizedVariant.ScaleformBuilds[0])
  $invalidDisplayModeVariant.ScaleformBuilds[0].Name = 'invalid-display-mode'
  $invalidDisplayModeVariant.ScaleformBuilds[0].Outputs = @(@{ InputFile = 'input.swf'; OutputFile = 'output.swf'; DisplayMode = 'compact' })
  Assert-TestRejected -Description 'Invalid output DisplayMode' -ExpectedMessage "unsupported DisplayMode 'compact'" -Action {
    [void](ConvertTo-BuildScaleformJobs -Variants @($invalidDisplayModeVariant) -RepositoryRoot $repositoryRoot)
  }
  $wrongDisplayModeVariant = $parameterizedVariant.PSObject.Copy()
  $wrongDisplayModeVariant.ScaleformBuilds = @(@{} + $parameterizedVariant.ScaleformBuilds[0])
  $wrongDisplayModeVariant.ScaleformBuilds[0].Name = 'wrong-display-mode'
  $wrongDisplayModeVariant.ScaleformBuilds[0].Outputs = @(@{ InputFile = 'input.swf'; OutputFile = 'output.swf'; DisplayMode = 'large' })
  Assert-TestRejected -Description 'DisplayMode mismatched with output filename' -ExpectedMessage "must use DisplayMode 'normal'" -Action {
    [void](ConvertTo-BuildScaleformJobs -Variants @($wrongDisplayModeVariant) -RepositoryRoot $repositoryRoot)
  }

  $safeNestedFlexJobs = @(ConvertTo-BuildScaleformJobs -RepositoryRoot $repositoryRoot -Variants @(
    [pscustomobject]@{ VariantKey = 'FLEX-PARENT'; ScaleformBuilds = @(@{ Name = 'flex-parent'; Kind = 'Flex'; OutputSet = 'nested-flex'; ManifestPath = $auxiliaryManifest; Outputs = @(@{ OutputFile = 'Auxiliary.swf' }) }) }
    [pscustomobject]@{ VariantKey = 'FLEX-CHILD'; ScaleformBuilds = @(@{ Name = 'flex-child'; Kind = 'Flex'; OutputSet = 'nested-flex/child'; ManifestPath = $auxiliaryManifest; Outputs = @(@{ OutputFile = 'Auxiliary.swf' }) }) }
  ))
  if ($safeNestedFlexJobs.Count -ne 2) {
    throw 'Scaleform ownership validation rejected safe nested Flex output sets.'
  }

  $safeMixedJobs = @(ConvertTo-BuildScaleformJobs -RepositoryRoot $repositoryRoot -Variants @(
    [pscustomobject]@{ VariantKey = 'MIXED-FLEX'; ScaleformBuilds = @(@{ Name = 'mixed-flex'; Kind = 'Flex'; OutputSet = 'mixed'; ManifestPath = $auxiliaryManifest; Outputs = @(@{ OutputFile = 'Auxiliary.swf' }) }) }
    [pscustomobject]@{ VariantKey = 'MIXED-PATCH'; ScaleformBuilds = @(@{ Name = 'mixed-patch'; Kind = 'Patch'; OutputSet = 'mixed/child'; PatchPath = $patchPath; Outputs = @(@{ InputFile = 'input.swf'; OutputFile = 'patched.swf' }) }) }
  ))
  if ($safeMixedJobs.Count -ne 2) {
    throw 'Scaleform ownership validation rejected a safe Flex ancestor with a nested Patch output set.'
  }

  $safeSiblingJobs = @(ConvertTo-BuildScaleformJobs -RepositoryRoot $repositoryRoot -Variants @(
    [pscustomobject]@{ VariantKey = 'PLAYER'; ScaleformBuilds = @(@{ Name = 'sibling-player'; Kind = 'Patch'; OutputSet = 'hud/player'; PatchPath = $patchPath; Outputs = @(@{ InputFile = 'input.swf'; OutputFile = 'player.swf' }) }) }
    [pscustomobject]@{ VariantKey = 'SHIP'; ScaleformBuilds = @(@{ Name = 'sibling-ship'; Kind = 'Patch'; OutputSet = 'HUD\ship'; PatchPath = $patchPath; Outputs = @(@{ InputFile = 'input.swf'; OutputFile = 'ship.swf' }) }) }
  ))
  if ($safeSiblingJobs.Count -ne 2) {
    throw 'Scaleform ownership validation rejected sibling Patch output sets.'
  }

  Assert-TestRejected -Description 'Flex file and nested output-set directory collision' -ExpectedMessage 'conflicts with output-set directory' -Action {
    [void](ConvertTo-BuildScaleformJobs -RepositoryRoot $repositoryRoot -Variants @(
      [pscustomobject]@{ VariantKey = 'FILE'; ScaleformBuilds = @(@{ Name = 'collision-file'; Kind = 'Flex'; OutputSet = 'collision'; ManifestPath = $auxiliaryManifest; Outputs = @(@{ OutputFile = 'Auxiliary.swf' }) }) }
      [pscustomobject]@{ VariantKey = 'DIRECTORY'; ScaleformBuilds = @(@{ Name = 'collision-directory'; Kind = 'Patch'; OutputSet = 'collision/Auxiliary.swf'; PatchPath = $patchPath; Outputs = @(@{ InputFile = 'input.swf'; OutputFile = 'patched.swf' }) }) }
    ))
  }

  $configuredJobs = @(ConvertTo-BuildScaleformJobs -Variants @(Get-ModuleVariants) -RepositoryRoot $repositoryRoot)
  Assert-BuildExactNames -Actual @($configuredJobs.Name) -Expected @('canvas-host', 'player-watch', 'player-loader', 'ship-loader', 'canvas-example', 'canvas-component-gallery') -Description 'Configured Scaleform jobs'
  if (@($configuredJobs | Where-Object { $_.OutputSet -ceq 'movies' }).Count -ne 3) {
    throw 'Configured Scaleform ownership validation did not preserve the shared Flex movie output set.'
  }
  $playerJob = @($configuredJobs | Where-Object { $_.Name -ceq 'player-watch' })[0]
  $playerNames = @('playerhudcomponents.swf', 'playerhudcomponents.gfx', 'playerhudcomponents_lrg.swf', 'playerhudcomponents_lrg.gfx')
  Assert-BuildExactNames -Actual @($playerJob.Outputs.InputFile) -Expected $playerNames -Description 'Player HUD input configuration'
  Assert-BuildExactNames -Actual @($playerJob.Outputs.OutputFile) -Expected $playerNames -Description 'Player HUD output configuration'
  $playerLoaderJob = @($configuredJobs | Where-Object { $_.Name -ceq 'player-loader' })[0]
  $playerLoaderNames = @('hudmenu.swf', 'hudmenu.gfx', 'hudmenu_lrg.swf', 'hudmenu_lrg.gfx')
  Assert-BuildExactNames -Actual @($playerLoaderJob.Outputs.InputFile) -Expected $playerLoaderNames -Description 'Player HUD loader input configuration'
  Assert-BuildExactNames -Actual @($playerLoaderJob.Outputs.OutputFile) -Expected $playerLoaderNames -Description 'Player HUD loader output configuration'
  Assert-BuildExactNames -Actual @($playerLoaderJob.Outputs | ForEach-Object { "$($_.OutputFile)=$($_.DisplayMode)" }) -Expected @(
    'hudmenu.swf=normal'
    'hudmenu.gfx=normal'
    'hudmenu_lrg.swf=large'
    'hudmenu_lrg.gfx=large'
  ) -Description 'Player HUD loader output/display-mode configuration'
  $canvasVariant = @(Get-ModuleVariants -VariantKeys CANVAS)[0]
  $playerLoaderAssets = @($canvasVariant.Archives | ForEach-Object { @($_.Assets) } | Where-Object { [string]$_.Root -ceq 'Scaleform' -and [string]$_.Source -clike 'player-hud-loader/*' })
  Assert-BuildExactNames -Actual @($playerLoaderAssets.Source) -Expected @($playerLoaderNames | ForEach-Object { "player-hud-loader/$_" }) -Description 'Player HUD loader archive sources'
  Assert-BuildExactNames -Actual @($playerLoaderAssets.Target) -Expected @($playerLoaderNames | ForEach-Object { "Interface/$_" }) -Description 'Player HUD loader archive targets'
  $shipJob = @($configuredJobs | Where-Object { $_.Name -ceq 'ship-loader' })[0]
  $shipNames = @('spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf')
  Assert-BuildExactNames -Actual @($shipJob.Outputs.InputFile) -Expected $shipNames -Description 'Ship HUD input configuration'
  Assert-BuildExactNames -Actual @($shipJob.Outputs.OutputFile) -Expected $shipNames -Description 'Ship HUD output configuration'
  Assert-BuildExactNames -Actual @($shipJob.Outputs | ForEach-Object { "$($_.OutputFile)=$($_.DisplayMode)" }) -Expected @(
    'spaceshiphudmenu.swf=normal'
    'spaceshiphudmenu_lrg.swf=large'
  ) -Description 'Ship HUD output/display-mode configuration'

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

  $mappedStagingRoot = Join-Path $fixtureRoot 'mapped-staging'
  New-Item -ItemType Directory -Path $mappedStagingRoot | Out-Null
  $mappedResult = [pscustomobject]@{
    VariantKey = 'MAPPED'
    JobName = 'consumer'
    OutputSet = 'movies'
    OutputFile = 'Consumer.swf'
    Path = $movieCandidate
  }
  $mappedVariant = [pscustomobject]@{
    VariantKey = 'MAPPED'
    StagingFolderPath = $mappedStagingRoot
    Archives = @(@{
      Assets = @(
        @{ Root = 'Scaleform'; Source = 'movies/Consumer.swf'; Target = 'Interface/Consumers/normal.swf' }
        @{ Root = 'Scaleform'; Source = 'movies/Consumer.swf'; Target = 'Interface/Consumers/large.swf' }
      )
    })
  }
  $mappedPlans = @(Get-BuildScaleformStagingPlans -Variants @($mappedVariant) -Results @($mappedResult))
  Assert-BuildExactNames -Actual @($mappedPlans.Target) -Expected @('Interface/Consumers/normal.swf', 'Interface/Consumers/large.swf') -Description 'One-to-many Scaleform staging targets'
  foreach ($plan in $mappedPlans) {
    Publish-BuildScaleformFile -CandidatePath ([string]$plan.CandidatePath) -DestinationPath ([string]$plan.DestinationPath) -AllowedRoot $mappedStagingRoot
  }
  foreach ($target in @($mappedPlans.Target)) {
    [void](Assert-BuildScaleformFile -Path (Join-Path $mappedStagingRoot $target) -Description "Mapped staging target '$target'")
  }
  Assert-TestRejected -Description 'Unmapped selected Scaleform output' -ExpectedMessage 'does not have a staging target mapping' -Action {
    $unmappedVariant = $mappedVariant.PSObject.Copy()
    $unmappedVariant.Archives = @()
    [void](Get-BuildScaleformStagingPlans -Variants @($unmappedVariant) -Results @($mappedResult))
  }
  Assert-TestRejected -Description 'Ambiguous Scaleform staging target' -ExpectedMessage 'is ambiguously mapped' -Action {
    $ambiguousVariant = $mappedVariant.PSObject.Copy()
    $ambiguousVariant.Archives = @(@{
      Assets = @(
        @{ Root = 'Scaleform'; Source = 'movies/Consumer.swf'; Target = 'Interface/Consumers/normal.swf' }
        @{ Root = 'Scaleform'; Source = 'other/Other.swf'; Target = 'Interface/Consumers/normal.swf' }
      )
    })
    $otherResult = [pscustomobject]@{ VariantKey = 'MAPPED'; JobName = 'other'; OutputSet = 'other'; OutputFile = 'Other.swf'; Path = $movieCandidate }
    [void](Get-BuildScaleformStagingPlans -Variants @($ambiguousVariant) -Results @($mappedResult, $otherResult))
  }

  $hazardRoot = Join-Path $fixtureRoot 'flex-hazard'
  $hazardOutput = Join-Path $hazardRoot 'output'
  $hazardWork = Join-Path $hazardRoot 'work'
  $hazardDestination = Join-Path $hazardOutput 'movies'
  $hazardFirstOutput = Join-Path $hazardDestination 'first.swf'
  $hazardSecondOutput = Join-Path $hazardDestination 'second.swf'
  New-Item -ItemType Directory -Path $hazardDestination, $hazardSecondOutput | Out-Null
  Write-TestScaleformMovie -Path $hazardFirstOutput -Marker 'original-first'
  $hazardFirstHash = Get-BuildFileSha256 -Path $hazardFirstOutput
  $hazardJobs = @(
    [pscustomobject]@{ Name = 'hazard-first'; Kind = 'Flex'; OutputSet = 'movies'; ManifestPath = 'first'; PatchPath = $null; Outputs = @([pscustomobject]@{ InputFile = $null; OutputFile = 'first.swf' }); VariantKey = 'FIRST' }
    [pscustomobject]@{ Name = 'hazard-second'; Kind = 'Flex'; OutputSet = 'movies'; ManifestPath = 'second'; PatchPath = $null; Outputs = @([pscustomobject]@{ InputFile = $null; OutputFile = 'second.swf' }); VariantKey = 'SECOND' }
  )
  $originalHazardMovieBuild = ${function:Invoke-BuildScaleformMovieBuild}
  $hazardWorkPrefix = [System.IO.Path]::GetFullPath($hazardWork).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
  function Invoke-BuildScaleformMovieBuild {
    param(
      [string]$ManifestPath, [string]$OutputDirectory, [string]$WorkDirectory, [string]$JavaPath,
      [string]$JpexsJarPath, [string]$FlexSdkPath, [string]$ScaleformSourceRoot, [switch]$KeepWork
    )
    if ($ManifestPath -cnotin @('first', 'second') -or
        ![System.IO.Path]::GetFullPath($OutputDirectory).StartsWith($hazardWorkPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        ![System.IO.Path]::GetFullPath($WorkDirectory).StartsWith($hazardWorkPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFullPath($JavaPath) -cne [System.IO.Path]::GetFullPath($auxiliaryJava) -or
        [System.IO.Path]::GetFullPath($JpexsJarPath) -cne [System.IO.Path]::GetFullPath($auxiliaryJpexs) -or
        [System.IO.Path]::GetFullPath($FlexSdkPath) -cne [System.IO.Path]::GetFullPath($auxiliaryFlexRoot) -or
        [System.IO.Path]::GetFullPath($ScaleformSourceRoot) -cne [System.IO.Path]::GetFullPath($auxiliarySourceRoot) -or
        $KeepWork.IsPresent) {
      throw 'Flex hazard fixture received unexpected job arguments.'
    }
    $outputFile = "$ManifestPath.swf"
    $path = Join-Path $OutputDirectory $outputFile
    Write-TestScaleformMovie -Path $path -Marker "candidate-$ManifestPath"
    return [pscustomobject]@{ Name = $ManifestPath; Role = 'fixture'; OutputFile = $outputFile; Path = $path }
  }
  try {
    Assert-TestRejected -Description 'Flex destination directory hazard' -ExpectedMessage 'output destination is a directory' -Action {
      [void](Invoke-BuildScaleformJobs -Jobs $hazardJobs -JavaPath $auxiliaryJava -JpexsJarPath $auxiliaryJpexs -FlexSdkPath $auxiliaryFlexRoot -ScaleformSourceRoot $auxiliarySourceRoot -OutputDirectory $hazardOutput -WorkDirectory $hazardWork -AllowedRoot $hazardRoot)
    }
  }
  finally {
    Set-Item -LiteralPath Function:Invoke-BuildScaleformMovieBuild -Value $originalHazardMovieBuild
  }
  if ((Get-BuildFileSha256 -Path $hazardFirstOutput) -cne $hazardFirstHash -or !(Test-Path -LiteralPath $hazardSecondOutput -PathType Container)) {
    throw 'Flex destination preflight changed an existing output before rejecting a later directory hazard.'
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
    VariantKey = 'RECOVERY'
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
  Assert-BuildExactNames -Actual $parameterNames -Expected @('EnvironmentPath', 'VariantKeys', 'JavaPath', 'JpexsJarPath', 'FlexSdkPath', 'VanillaInterfacePath', 'OutputDirectory', 'WorkDirectory', 'KeepWork') -Description 'Scaleform build parameters'
  $builderHelp = Get-Help -Name $builderPath -Full
  foreach ($parameterName in $parameterNames) {
    $helpParameters = @($builderHelp.parameters.parameter | Where-Object { $_.name -ceq $parameterName })
    $descriptionText = if ($helpParameters.Count -eq 1) { [string]::Join(' ', @($helpParameters[0].description.Text)) } else { '' }
    if ([string]::IsNullOrWhiteSpace($descriptionText)) {
      throw "Scaleform build parameter '$parameterName' does not have comment-based help."
    }
  }

  $savedBuildSettings = $Global:BuildSettings
  $savedModuleVariants = $Global:ModuleVariants
  $savedSharedConfigurationLoaded = $Global:SharedConfigurationLoaded
  $missingToolRoot = Join-Path $fixtureRoot 'missing-tools'
  $emptyVariant = [pscustomobject]@{
    VariantKey = 'EMPTY'
    PapyrusNamespace = 'Fixture:Empty'
    ScaleformBuilds = @()
  }
  $unselectedVariant = [pscustomobject]@{
    VariantKey = 'UNSELECTED'
    PapyrusNamespace = 'Fixture:Unselected'
    ScaleformBuilds = @(@{
      Name = 'unselected-flex'
      Kind = 'Flex'
      OutputSet = 'unselected'
      ManifestPath = $auxiliaryManifest
      Outputs = @(@{ OutputFile = 'Auxiliary.swf' })
    })
  }
  try {
    $Global:SharedConfigurationLoaded = $true
    $wrapperOutput = Join-Path $fixtureRoot 'wrapper-output'
    $Global:BuildSettings = @{
      WorkRoot = $fixtureRoot
      ScaleformSourceRoot = $auxiliarySourceRoot
    }
    $Global:ModuleVariants = @($emptyVariant, $unselectedVariant)
    & $builderPath `
      -EnvironmentPath (Join-Path $fixtureRoot 'unused.env') `
      -VariantKeys 'EMPTY' `
      -JavaPath (Join-Path $missingToolRoot 'java.exe') `
      -JpexsJarPath (Join-Path $missingToolRoot 'ffdec.jar') `
      -FlexSdkPath (Join-Path $missingToolRoot 'flex')

    $duplicateJob = @{
      Name = 'duplicate-flex'
      Kind = 'Flex'
      OutputSet = 'shared'
      ManifestPath = $auxiliaryManifest
      Outputs = @(@{ OutputFile = 'Auxiliary.swf' })
    }
    $Global:ModuleVariants = @(
      [pscustomobject]@{ VariantKey = 'FIRST'; PapyrusNamespace = 'Fixture:First'; ScaleformBuilds = @($duplicateJob) }
      [pscustomobject]@{
        VariantKey = 'SECOND'
        PapyrusNamespace = 'Fixture:Second'
        ScaleformBuilds = @(@{
          Name = 'second-duplicate-flex'
          Kind = 'Flex'
          OutputSet = 'shared'
          ManifestPath = $auxiliaryManifest
          Outputs = @(@{ OutputFile = 'Auxiliary.swf' })
        })
      }
    )
    Assert-TestRejected -Description 'Unselected duplicate Scaleform output ownership' -ExpectedMessage 'declared more than once' -Action {
      & $builderPath `
        -EnvironmentPath (Join-Path $fixtureRoot 'unused.env') `
        -VariantKeys 'FIRST' `
        -JavaPath (Join-Path $missingToolRoot 'java.exe') `
        -JpexsJarPath (Join-Path $missingToolRoot 'ffdec.jar') `
        -FlexSdkPath (Join-Path $missingToolRoot 'flex')
    }

    $Global:ModuleVariants = @(
      [pscustomobject]@{
        VariantKey = 'PARENT'
        PapyrusNamespace = 'Fixture:Parent'
        ScaleformBuilds = @(@{
          Name = 'parent-patch'
          Kind = 'Patch'
          OutputSet = 'hud'
          PatchPath = $patchPath
          Outputs = @(@{ InputFile = 'parent-input.swf'; OutputFile = 'parent.swf' })
        })
      }
      [pscustomobject]@{
        VariantKey = 'CHILD'
        PapyrusNamespace = 'Fixture:Child'
        ScaleformBuilds = @(@{
          Name = 'child-patch'
          Kind = 'Patch'
          OutputSet = 'HUD\child'
          PatchPath = $patchPath
          Outputs = @(@{ InputFile = 'child-input.swf'; OutputFile = 'child.swf' })
        })
      }
    )
    $unselectedChildOutput = Join-Path $wrapperOutput 'hud\child\child.swf'
    Write-TestScaleformMovie -Path $unselectedChildOutput -Marker 'unselected-child'
    $unselectedChildHash = Get-BuildFileSha256 -Path $unselectedChildOutput
    Assert-TestRejected -Description 'Selected parent Patch directory ownership' -ExpectedMessage 'owns a directory containing' -Action {
      & $builderPath `
        -EnvironmentPath (Join-Path $fixtureRoot 'unused.env') `
        -VariantKeys 'PARENT' `
        -JavaPath (Join-Path $missingToolRoot 'java.exe') `
        -JpexsJarPath (Join-Path $missingToolRoot 'ffdec.jar') `
        -FlexSdkPath (Join-Path $missingToolRoot 'flex')
    }
    if ((Get-BuildFileSha256 -Path $unselectedChildOutput) -cne $unselectedChildHash) {
      throw 'Scaleform ownership preflight changed an unselected child output.'
    }
  }
  finally {
    $Global:BuildSettings = $savedBuildSettings
    $Global:ModuleVariants = $savedModuleVariants
    $Global:SharedConfigurationLoaded = $savedSharedConfigurationLoaded
  }

  $builderSource = [System.IO.File]::ReadAllText($builderPath)
  if ($builderSource -match '(?i)VwHud|EstablishExpectedHashes|build-evidence|Archive2|TOOL_PATH_ARCHIVER|STEAM_DATA_FOLDER') {
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
