<#
.SYNOPSIS
Exercises the fail-closed native Watch structural-removal pipeline.
.DESCRIPTION
Uses synthetic JPEXS movie XML and mocked native tool calls. Java, JPEXS, Apache Flex, and the game runtime are intentionally not invoked.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedBuild.ps1')
. (Join-Path $PSScriptRoot 'sharedScaleform.ps1')

function Assert-WatchTestRejected {
  param(
    [Parameter(Mandatory = $true)][string]$Description,
    [Parameter(Mandatory = $true)][scriptblock]$Action,
    [Parameter(Mandatory = $true)][string]$ExpectedMessage
  )

  try {
    & $Action
  }
  catch {
    if (!$_.Exception.Message.Contains($ExpectedMessage)) {
      throw "$Description returned an unexpected error: $($_.Exception.Message)"
    }
    return
  }
  throw "$Description was accepted unexpectedly."
}

function Write-WatchTestMovie {
  param([Parameter(Mandatory = $true)][string]$Path)

  $parent = Split-Path -Parent $Path
  if (!(Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  [System.IO.File]::WriteAllBytes($Path, [System.Text.Encoding]::ASCII.GetBytes('CWS12345watch-removal-fixture'))
}

function Write-WatchTestXml {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$AdditionalRootTags = '',
    [string]$WatchDepth = '46',
    [string]$WatchCharacterId = '77',
    [string]$WatchClassCharacterId = '77'
  )

  Write-BuildUtf8WithoutBom -Path $Path -Text @"
<swf>
  <tags>
    <item type="DefineSpriteTag" spriteId="77"><subTags /></item>
    <item type="DefineSpriteTag" spriteId="9"><subTags /></item>
    <item type="PlaceObject2Tag" characterId="$WatchCharacterId" depth="$WatchDepth" name="WatchFaceComponent_mc" placeFlagHasCharacter="true" placeFlagHasName="true" placeFlagMove="false" />
    $AdditionalRootTags
    <item type="SymbolClassTag">
      <tags><item>9</item><item>$WatchClassCharacterId</item></tags>
      <names><item>OtherClass</item><item>BottomLeftGroup</item></names>
    </item>
  </tags>
</swf>
"@
}

function Write-WatchHudMenuTestXml {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$AdditionalRootTags = '',
    [string]$Depth = '2'
  )

  Write-BuildUtf8WithoutBom -Path $Path -Text @"
<swf>
  <tags>
    <item type="PlaceObject3Tag" className="BottomLeftGroup" depth="$Depth" name="BottomLeftGroup_mc" placeFlagHasCharacter="false" placeFlagHasClassName="true" placeFlagHasName="true" placeFlagMove="false" />
    $AdditionalRootTags
  </tags>
</swf>
"@
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtureParent = Join-Path $repositoryRoot '.work\canvas\vwcanvas-21-watch-removal-tests'
New-Item -ItemType Directory -Force -Path $fixtureParent | Out-Null
$fixtureRoot = Join-Path $fixtureParent ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

try {
  $patchPath = Join-Path $fixtureRoot 'watch-removal.xml'
  Write-BuildUtf8WithoutBom -Path $patchPath -Text '<watchRemoval schema="VWCANVAS_WATCH_REMOVAL/1" instanceName="WatchFaceComponent_mc" className="BottomLeftGroup" placeTagType="PlaceObject2Tag" rootDepth="46" />'
  $patch = Get-BuildScaleformPatchDefinition -PatchPath $patchPath
  if ($patch.Kind -cne 'WatchRemoval' -or $patch.RootDepth -ne 46) {
    throw 'Watch removal patch definition did not retain its structural contract.'
  }
  Assert-WatchTestRejected -Description 'Watch removal DisplayMode' -ExpectedMessage 'does not support DisplayMode' -Action {
    [void](Get-BuildScaleformPatchDefinition -PatchPath $patchPath -DisplayMode 'large')
  }

  $referenceRewrite = Get-BuildWatchReferenceRewrite -RewritePath (Join-Path $repositoryRoot 'Scaleform\canvas\build\player-hud-watch-references-removed.xml')
  $rewriteSourcePath = Join-Path $fixtureRoot 'HUDMenu.as'
  $rewriteSource = [string]::Join("`n`n", @($referenceRewrite.ExactRemovals)) + "`n" + $referenceRewrite.RangeReplacements[0].StartAnchor + "`n         this.__animFactory_BottomLeftGroup_mcaf1.addTargetInfo(this,`"BottomLeftGroup_mc`",0,true,0,true,null,-1);`n         }`n      }`n      `n" + $referenceRewrite.RangeReplacements[0].EndAnchor + "`n      {`n      }"
  $spanStart = $rewriteSource.IndexOf($referenceRewrite.RangeReplacements[0].StartAnchor, [System.StringComparison]::Ordinal)
  $spanEnd = $rewriteSource.IndexOf($referenceRewrite.RangeReplacements[0].EndAnchor, [System.StringComparison]::Ordinal)
  $referenceRewrite.RangeReplacements[0].ExpectedSpanSha256 = @(Get-BuildStringSha256 -Value $rewriteSource.Substring($spanStart, $spanEnd - $spanStart))
  Write-BuildUtf8WithoutBom -Path $rewriteSourcePath -Text $rewriteSource
  Apply-BuildWatchReferenceRewrite -SourcePath $rewriteSourcePath -Rewrite $referenceRewrite
  $rewrittenSource = [System.IO.File]::ReadAllText($rewriteSourcePath)
  if ($rewrittenSource.Contains('BottomLeftGroup_mc') -or !$rewrittenSource.Contains('public function __setPerspectiveProjection_')) {
    throw 'Watch reference rewrite did not remove the native target while retaining the following HUDMenu method.'
  }
  $injectedRewriteSource = Join-Path $fixtureRoot 'HUDMenu-injected.as'
  $injectionAnchor = '         this.__animFactory_BottomLeftGroup_mcaf1.addTargetInfo(this,"BottomLeftGroup_mc",0,true,0,true,null,-1);'
  Write-BuildUtf8WithoutBom -Path $injectedRewriteSource -Text $rewriteSource.Replace($injectionAnchor, $injectionAnchor + "`n         initializeOtherHudFeature();")
  Assert-WatchTestRejected -Description 'Injected HUDMenu constructor statement' -ExpectedMessage 'unexpected' -Action {
    Apply-BuildWatchReferenceRewrite -SourcePath $injectedRewriteSource -Rewrite $referenceRewrite
  }
  $driftedRewriteSource = Join-Path $fixtureRoot 'HUDMenu-drifted.as'
  Write-BuildUtf8WithoutBom -Path $driftedRewriteSource -Text $rewriteSource.Replace($referenceRewrite.ExactRemovals[0], '')
  Assert-WatchTestRejected -Description 'Drifted HUDMenu Watch reference' -ExpectedMessage 'found 0' -Action {
    Apply-BuildWatchReferenceRewrite -SourcePath $driftedRewriteSource -Rewrite $referenceRewrite
  }

  $validXml = Join-Path $fixtureRoot 'valid.xml'
  $removedXml = Join-Path $fixtureRoot 'removed.xml'
  Write-WatchTestXml -Path $validXml
  $characterId = Remove-BuildWatchFromScaleformXml -InputPath $validXml -OutputPath $removedXml -Patch $patch
  if ($characterId -ne 77) {
    throw "Watch removal returned unexpected character id $characterId."
  }
  [xml]$removedMovie = Get-Content -LiteralPath $removedXml -Raw
  Assert-BuildWatchRemovedScaleformXml -Movie $removedMovie -Patch $patch -CharacterId $characterId -Description 'Watch removal fixture'

  $hudMenuXml = Join-Path $fixtureRoot 'hudmenu.xml'
  $hudMenuRemovedXml = Join-Path $fixtureRoot 'hudmenu-removed.xml'
  Write-WatchHudMenuTestXml -Path $hudMenuXml
  Remove-BuildWatchClassPlacementFromScaleformXml -InputPath $hudMenuXml -OutputPath $hudMenuRemovedXml -Removal $referenceRewrite.StructuralRemoval
  [xml]$hudMenuRemovedMovie = Get-Content -LiteralPath $hudMenuRemovedXml -Raw
  Assert-BuildWatchClassPlacementAbsent -Movie $hudMenuRemovedMovie -Removal $referenceRewrite.StructuralRemoval -Description 'HUDMenu structural-removal fixture'

  $duplicateHudMenuXml = Join-Path $fixtureRoot 'hudmenu-duplicate.xml'
  Write-WatchHudMenuTestXml -Path $duplicateHudMenuXml -AdditionalRootTags '<item type="PlaceObject3Tag" className="BottomLeftGroup" depth="99" name="UnexpectedWatch_mc" placeFlagHasCharacter="false" placeFlagHasClassName="true" placeFlagHasName="true" placeFlagMove="false" />'
  Assert-WatchTestRejected -Description 'Additional HUDMenu Watch class placement' -ExpectedMessage 'expected one root' -Action {
    Remove-BuildWatchClassPlacementFromScaleformXml -InputPath $duplicateHudMenuXml -OutputPath (Join-Path $fixtureRoot 'hudmenu-duplicate-output.xml') -Removal $referenceRewrite.StructuralRemoval
  }

  $boundHudMenuXml = Join-Path $fixtureRoot 'hudmenu-bound.xml'
  Write-WatchHudMenuTestXml -Path $boundHudMenuXml -AdditionalRootTags '<item type="SymbolClassTag"><tags><item>77</item></tags><names><item>BottomLeftGroup</item></names></item>'
  Assert-WatchTestRejected -Description 'HUDMenu Watch character binding' -ExpectedMessage 'character binding' -Action {
    Remove-BuildWatchClassPlacementFromScaleformXml -InputPath $boundHudMenuXml -OutputPath (Join-Path $fixtureRoot 'hudmenu-bound-output.xml') -Removal $referenceRewrite.StructuralRemoval
  }

  $duplicateXml = Join-Path $fixtureRoot 'duplicate.xml'
  Write-WatchTestXml -Path $duplicateXml -AdditionalRootTags '<item type="PlaceObject2Tag" characterId="77" depth="47" name="WatchFaceComponent_mc" placeFlagHasCharacter="true" placeFlagHasName="true" placeFlagMove="false" />'
  Assert-WatchTestRejected -Description 'Duplicate Watch placement' -ExpectedMessage 'found 2' -Action {
    [void](Remove-BuildWatchFromScaleformXml -InputPath $duplicateXml -OutputPath (Join-Path $fixtureRoot 'duplicate-output.xml') -Patch $patch)
  }

  $otherPlacementXml = Join-Path $fixtureRoot 'other-placement.xml'
  Write-WatchTestXml -Path $otherPlacementXml -AdditionalRootTags '<item type="PlaceObject2Tag" characterId="77" depth="47" name="UnexpectedWatch_mc" placeFlagHasCharacter="true" placeFlagHasName="true" placeFlagMove="false" />'
  Assert-WatchTestRejected -Description 'Additional Watch character placement' -ExpectedMessage 'exactly one placement' -Action {
    [void](Remove-BuildWatchFromScaleformXml -InputPath $otherPlacementXml -OutputPath (Join-Path $fixtureRoot 'other-placement-output.xml') -Patch $patch)
  }

  $wrongDepthXml = Join-Path $fixtureRoot 'wrong-depth.xml'
  Write-WatchTestXml -Path $wrongDepthXml -WatchDepth '45'
  Assert-WatchTestRejected -Description 'Drifted Watch placement' -ExpectedMessage 'does not match the required type, depth, and construction flags' -Action {
    [void](Remove-BuildWatchFromScaleformXml -InputPath $wrongDepthXml -OutputPath (Join-Path $fixtureRoot 'wrong-depth-output.xml') -Patch $patch)
  }

  $wrongBindingXml = Join-Path $fixtureRoot 'wrong-binding.xml'
  Write-WatchTestXml -Path $wrongBindingXml -WatchClassCharacterId '9'
  Assert-WatchTestRejected -Description 'Drifted Watch SymbolClass binding' -ExpectedMessage 'SymbolClass binding' -Action {
    [void](Remove-BuildWatchFromScaleformXml -InputPath $wrongBindingXml -OutputPath (Join-Path $fixtureRoot 'wrong-binding-output.xml') -Patch $patch)
  }

  $safeScripts = Join-Path $fixtureRoot 'safe-scripts'
  New-Item -ItemType Directory -Path $safeScripts | Out-Null
  Write-BuildUtf8WithoutBom -Path (Join-Path $safeScripts 'BottomLeftGroup.as') -Text 'public class BottomLeftGroup {}'
  Write-BuildUtf8WithoutBom -Path (Join-Path $safeScripts 'OtherClass.as') -Text 'public class OtherClass {}'
  Assert-BuildWatchRemovedActionScript -ScriptsDirectory $safeScripts -Patch $patch
  Write-BuildUtf8WithoutBom -Path (Join-Path $safeScripts 'OtherClass.as') -Text 'public class OtherClass { private var watch:BottomLeftGroup; }'
  Assert-WatchTestRejected -Description 'Reachable Watch class reference' -ExpectedMessage 'class reference' -Action {
    Assert-BuildWatchRemovedActionScript -ScriptsDirectory $safeScripts -Patch $patch
  }

  $nativeInput = Join-Path $fixtureRoot 'native-input.swf'
  $nativeOutput = Join-Path $fixtureRoot 'native-output.swf'
  $fakeJava = Join-Path $fixtureRoot 'java.exe'
  $fakeJpexs = Join-Path $fixtureRoot 'ffdec.jar'
  Write-WatchTestMovie -Path $nativeInput
  [System.IO.File]::WriteAllBytes($fakeJava, [byte[]](0))
  [System.IO.File]::WriteAllBytes($fakeJpexs, [byte[]](0))
  $originalJavaJar = ${function:Invoke-BuildJavaJar}
  $script:watchTestTransformedXml = $null
  $script:watchTestNativeCalls = 0
  function Invoke-BuildJavaJar {
    param([string]$JavaPath, [string]$JarPath, [string[]]$Arguments, [string]$Description)

    if ([System.IO.Path]::GetFullPath($JavaPath) -cne [System.IO.Path]::GetFullPath($fakeJava) -or
        [System.IO.Path]::GetFullPath($JarPath) -cne [System.IO.Path]::GetFullPath($fakeJpexs)) {
      throw "Watch removal fixture received unexpected native tool paths for $Description."
    }
    $script:watchTestNativeCalls++
    if ($Arguments[0] -ceq '-swf2xml') {
      if ($null -eq $script:watchTestTransformedXml) {
        Write-WatchTestXml -Path $Arguments[2]
      }
      else {
        Write-BuildUtf8WithoutBom -Path $Arguments[2] -Text $script:watchTestTransformedXml
      }
      return
    }
    if ($Arguments[0] -ceq '-xml2swf') {
      $script:watchTestTransformedXml = [System.IO.File]::ReadAllText($Arguments[1])
      Write-WatchTestMovie -Path $Arguments[2]
      return
    }
    if ($Arguments[0] -ceq '-format' -and $Arguments -contains '-export') {
      $exportIndex = [Array]::IndexOf($Arguments, '-export')
      $scripts = Join-Path $Arguments[$exportIndex + 2] 'scripts'
      New-Item -ItemType Directory -Force -Path $scripts | Out-Null
      Write-BuildUtf8WithoutBom -Path (Join-Path $scripts 'BottomLeftGroup.as') -Text 'public class BottomLeftGroup {}'
      Write-BuildUtf8WithoutBom -Path (Join-Path $scripts 'OtherClass.as') -Text 'public class OtherClass {}'
      return
    }
    throw "Unexpected Watch removal fixture invocation: $Description"
  }
  try {
    [void](Invoke-BuildPatchedScaleformMovie -InputPath $nativeInput -OutputPath $nativeOutput -PatchPath $patchPath -JavaPath $fakeJava -JpexsJarPath $fakeJpexs -FlexSdkPath (Join-Path $fixtureRoot 'intentionally-missing-flex') -WorkDirectory (Join-Path $fixtureRoot 'native-work'))
  }
  finally {
    Set-Item -LiteralPath Function:Invoke-BuildJavaJar -Value $originalJavaJar
  }
  if ($script:watchTestNativeCalls -ne 4 -or !(Test-Path -LiteralPath $nativeOutput -PathType Leaf)) {
    throw 'Watch removal dispatcher did not complete the four-step XML rebuild and inspection flow.'
  }

  Write-Host -ForegroundColor Green 'Canvas native Watch structural-removal tests passed. Native Java/JPEXS and game-runtime acceptance were not invoked.'
}
finally {
  if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
    Assert-BuildRemovalPath -Path $fixtureRoot -AllowedRoot $fixtureParent
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}
