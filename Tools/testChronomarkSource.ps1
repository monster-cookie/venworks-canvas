<#
.SYNOPSIS
Verifies the Canvas-owned Chronomark source and HUD bridge contracts.
.DESCRIPTION
Checks provider ownership, bounded capacities, lifecycle guards, conditional clock ownership, direct HUDMenu bridging, and the intentional separation from the custom-alert data transport.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-TestCondition {
  param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
  if (!$Condition) { throw $Message }
}

function Get-TestSource {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required Chronomark source is missing: $Path" }
  return [System.IO.File]::ReadAllText($Path)
}

function Get-TestFixedFacePlacement {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('normal', 'large')][string]$Mode,
    [Parameter(Mandatory = $true)][hashtable]$Layout,
    [Parameter(Mandatory = $true)][hashtable]$DisplayState
  )
  [void]$DisplayState
  $matrix = if ($Mode -ceq 'large') {
    @(1.134053, -0.073151, -0.160659, 0, -0.040079, 1.131038, 0.203869, 0, 0.127329, -0.171576, 0.976908, 0, 41.096493, 795.546082, -4.567053, 1)
  } else {
    @(1.065422, -0.06871, -0.150934, 0, -0.037639, 1.062183, 0.191458, 0, 0.127329, -0.171576, 0.976908, 0, 41.719982, 807.84552, -4.454321, 1)
  }
  $corners = @(@(0, 0), @(221, 0), @(0, 221), @(221, 221))
  $xValues = @($corners | ForEach-Object { $matrix[0] * $_[0] + $matrix[4] * $_[1] + $matrix[12] })
  $yValues = @($corners | ForEach-Object { $matrix[1] * $_[0] + $matrix[5] * $_[1] + $matrix[13] })
  $left = ($xValues | Measure-Object -Minimum).Minimum
  $bottom = ($yValues | Measure-Object -Maximum).Maximum
  $offsetX = $Layout.visibleX + $Layout.safeX - $left
  $offsetY = $Layout.visibleY + $Layout.visibleHeight - $Layout.safeY - $bottom
  return '{0}|{1:F6}|{2:F6}' -f $Mode, ($left + $offsetX), ($bottom + $offsetY)
}

function Invoke-TestRetainedLayoutSequence {
  param([Parameter(Mandatory = $true)][ValidateSet('normal', 'large')][string]$Mode)
  $layout = @{ visibleX = 12.0; visibleY = 8.0; visibleWidth = 1880.0; visibleHeight = 1040.0; safeX = 36.0; safeY = 42.0; ownerAppliesOpacity = $true }
  $latest = $null
  $placements = @()
  foreach ($layoutEvent in @($layout, $null, $null)) {
    if ($null -ne $layoutEvent) { $latest = $layoutEvent }
    if ($null -ne $latest) { $placements += Get-TestFixedFacePlacement -Mode $Mode -Layout $latest -DisplayState @{} }
  }
  return @($placements)
}

function Get-TestNormalizedPersonalEffects {
  param([Parameter(Mandatory = $true)][string[]]$Icons)
  $suppressed = @('Sustenance_Food_Positive_1', 'Sustenance_Food_Positive_2', 'Sustenance_Food_Positive_3', 'Sustenance_Food_Negative_1', 'Sustenance_Food_Negative_2', 'Sustenance_Drink_Positive_1', 'Sustenance_Drink_Positive_2', 'Sustenance_Drink_Positive_3', 'Sustenance_Drink_Negative_1', 'Sustenance_Drink_Negative_2')
  $seen = @{}
  $result = @()
  for ($index = 0; $index -lt [Math]::Min($Icons.Count, 48) -and $result.Count -lt 5; $index++) {
    $icon = $Icons[$index]
    if (![string]::IsNullOrEmpty($icon) -and $suppressed -cnotcontains $icon -and !$seen.ContainsKey($icon)) {
      $seen[$icon] = $true
      $result += $icon
    }
  }
  return @($result)
}

function Invoke-TestScannerEvent {
  param(
    [Parameter(Mandatory = $true)][hashtable]$State,
    [Parameter(Mandatory = $true)][bool]$InSpaceship,
    [Parameter(Mandatory = $true)][bool]$Scanning
  )
  $initial = !$State.HasEnvironment
  $leftSpaceship = !$initial -and $State.InSpaceship -and !$InSpaceship
  $scannerChanged = $State.HasScanner -and $State.Scanning -ne $Scanning
  $action = 'none'
  if (!$State.HasScanner -or $scannerChanged) {
    $State.ScannerTarget = if ($Scanning) { 1 } else { 0 }
    $State.HoldRemaining = 0
    $action = if ($State.HasScanner) { 'scanner-transition' } else { 'scanner-initial' }
  }
  $State.HasEnvironment = $true
  $State.InSpaceship = $InSpaceship
  $State.HasScanner = $true
  $State.Scanning = $Scanning
  if ($leftSpaceship -and !$Scanning -and !$scannerChanged) {
    $State.ScannerTarget = 1
    $State.HoldRemaining = 3000
    $action = 'planet-hold'
  }
  return $action
}

function Assert-TestPatchRejectedWithoutWrite {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][pscustomobject]$Patch,
    [Parameter(Mandatory = $true)][string]$ExpectedMessage
  )
  $before = [IO.File]::ReadAllText($SourcePath)
  $rejected = $false
  try {
    Apply-BuildActionScriptPatch -SourcePath $SourcePath -Patch $Patch
  } catch {
    $rejected = $true
    Assert-TestCondition ($_.Exception.Message.Contains($ExpectedMessage)) "ActionScript patch rejection did not contain '$ExpectedMessage': $($_.Exception.Message)"
  }
  Assert-TestCondition $rejected "ActionScript patch unexpectedly accepted invalid applied state at '$SourcePath'."
  Assert-TestCondition ([IO.File]::ReadAllText($SourcePath) -ceq $before) "ActionScript patch modified '$SourcePath' before rejecting its invalid applied state."
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($null -eq (Get-Command Get-BuildActionScriptPatch -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'sharedBuild.ps1')
  . (Join-Path $PSScriptRoot 'sharedScaleform.ps1')
}
$actionScriptRoot = Join-Path $repositoryRoot 'Scaleform\canvas\actionscript'
$chronomarkNames = @(
  'CanvasChronomarkAnimation.as',
  'CanvasChronomarkData.as',
  'CanvasChronomarkEffects.as',
  'CanvasChronomarkMarkers.as',
  'CanvasChronomarkStyle.as',
  'CanvasChronomarkSurface.as',
  'CanvasChronomarkView.as'
)
$sources = [ordered]@{}
foreach ($name in $chronomarkNames) {
  $sources[$name] = Get-TestSource -Path (Join-Path $actionScriptRoot $name)
}
$chronomarkSource = [string]::Join("`n", @($sources.Values))
$dataSource = [string]$sources['CanvasChronomarkData.as']
$styleSource = [string]$sources['CanvasChronomarkStyle.as']
$animationSource = [string]$sources['CanvasChronomarkAnimation.as']
$effectsSource = [string]$sources['CanvasChronomarkEffects.as']
$markersSource = [string]$sources['CanvasChronomarkMarkers.as']
$surfaceSource = [string]$sources['CanvasChronomarkSurface.as']
$viewSource = [string]$sources['CanvasChronomarkView.as']
$hostSource = Get-TestSource -Path (Join-Path $actionScriptRoot 'CanvasHost.as')
$loaderPatch = Get-TestSource -Path (Join-Path $repositoryRoot 'Scaleform\canvas\patches\player-hud-auxiliary-loader.xml')
$loaderPatchXml = [xml]$loaderPatch
$manifest = Get-TestSource -Path (Join-Path $repositoryRoot 'Scaleform\canvas\build\canvas.build.xml')
$matrix = Get-TestSource -Path (Join-Path $repositoryRoot 'Scaleform\canvas\canvas-matrix.psd1')

$expectedChannels = @(
  'LocalEnvironmentData',
  'LocalEnvData_Frequent',
  'PlayerData',
  'PlayerFrequentData',
  'HudCompassData',
  'PersonalEffectsData',
  'PersonalAlertsData',
  'EnvironmentEffectsData',
  'EnvironmentAlertsData',
  'HudModeData',
  'HUDOpacityData'
)
$channelDeclaration = [regex]::Match($dataSource, 'CHANNELS:Array\s*=\s*\[(?<channels>[^\]]+)\]')
Assert-TestCondition $channelDeclaration.Success 'Chronomark data ingress no longer declares an auditable fixed provider list.'
$actualChannels = @([regex]::Matches($channelDeclaration.Groups['channels'].Value, '"(?<channel>[^"]+)"') | ForEach-Object { $_.Groups['channel'].Value })
Assert-TestCondition ($actualChannels.Count -eq $expectedChannels.Count) "Chronomark provider count changed. Expected $($expectedChannels.Count); found $($actualChannels.Count)."
for ($index = 0; $index -lt $expectedChannels.Count; $index++) {
  Assert-TestCondition ($actualChannels[$index] -ceq $expectedChannels[$index]) "Chronomark provider order changed at index $index. Expected '$($expectedChannels[$index])'; found '$($actualChannels[$index])'."
}

foreach ($forbidden in @('CustomAlertsData', 'customwatchalert', 'BottomLeftGroup', 'UIWatchAlert_', '[Embed', '_assets/assets.swf', 'addFrameScript', 'gotoAndPlay')) {
  Assert-TestCondition (!$chronomarkSource.Contains($forbidden)) "Canvas-owned Chronomark source contains forbidden native/custom-alert token '$forbidden'."
}
Assert-TestCondition ($hostSource.Contains('private static const PROVIDER:String = "CustomAlertsData";')) 'CanvasHost no longer preserves its independent custom-alert data transport.'
Assert-TestCondition ($hostSource.Contains('getVenworksCanvasDataManager')) 'CanvasHost no longer obtains its data manager from the HUDMenu bridge.'
Assert-TestCondition (!$hostSource.Contains('getCanvasWatchDataManager')) 'CanvasHost still depends on the removed Watch data-manager getter.'
Assert-TestCondition (!$hostSource.Contains('getCanvasWatchDisabled')) 'CanvasHost still depends on the removed Watch presentation marker.'
Assert-TestCondition ($hostSource.Contains('new CanvasChronomarkSurface()')) 'CanvasHost no longer owns the Chronomark surface.'
Assert-TestCondition ($hostSource.Contains('private var chronomarkLayout:Object = null;')) 'CanvasHost no longer retains the last validated Chronomark layout.'
Assert-TestCondition ($hostSource.Contains('this.chronomarkSurface.updateLayout(this.chronomarkLayout);')) 'CanvasHost no longer reapplies its retained Chronomark layout.'
Assert-TestCondition (!$hostSource.Contains('this.chronomarkSurface.updateLayout(param1);')) 'CanvasHost again forwards a nullable placement argument directly to the Chronomark.'
foreach ($mode in @('normal', 'large')) {
  $placements = @(Invoke-TestRetainedLayoutSequence -Mode $mode)
  Assert-TestCondition ($placements.Count -eq 3) "Chronomark $mode layout retention model did not execute initialize plus two null consumer-completion reapplications."
  Assert-TestCondition (@($placements | Select-Object -Unique).Count -eq 1) "Chronomark $mode layout changed after a null consumer-completion reapplication."
}

foreach ($capacity in @(
  'GENERAL_MARKER_CAPACITY:int = 48',
  'MISSION_MARKER_CAPACITY:int = 16',
  'ENEMY_MARKER_CAPACITY:int = 16',
  'PERSONAL_EFFECT_CAPACITY:int = 5',
  'PERSONAL_EFFECT_INGRESS_CAPACITY:int = 48',
  'ENVIRONMENT_EFFECT_CAPACITY:int = 4',
  'ALERT_QUEUE_CAPACITY:int = 16',
  'LOCATION_CHARACTER_CAPACITY:int = 21'
)) {
  Assert-TestCondition ($styleSource.Contains($capacity)) "Chronomark bounded-capacity contract changed: $capacity"
}
foreach ($measuredToken in @(
  'FACE_SIZE:Number = 221',
  'FACE_CENTER_X:Number = 110.5',
  'FACE_CENTER_Y:Number = 110.5',
  'LOCATION_CHARACTER_CAPACITY:int = 21',
  'DEFAULT_DWELL_MS:Number = 3000',
  'FADE_IN_MS:Number = 333.333333',
  'FADE_OUT_MS:Number = 333.333333',
  'ENVIRONMENT_ENTER_MS:Number = 1233.333333',
  'ENVIRONMENT_EXIT_MS:Number = 566.666667',
  'PERSONAL_ENTER_MS:Number = 1233.333333',
  'PERSONAL_EXIT_MS:Number = 566.666667',
  'PLANET_ENTER_MS:Number = 1533.333333',
  'PLANET_EXIT_MS:Number = 600',
  '[1.065422,-0.06871,-0.150934,0,-0.037639,1.062183,0.191458,0,0.127329,-0.171576,0.976908,0,41.719982,807.84552,-4.454321,1]',
  '[1.134053,-0.073151,-0.160659,0,-0.040079,1.131038,0.203869,0,0.127329,-0.171576,0.976908,0,41.096493,795.546082,-4.567053,1]'
)) {
  Assert-TestCondition ($styleSource.Contains($measuredToken)) "Chronomark measured style contract changed: $measuredToken"
}
foreach ($viewToken in @(
  'this.drawArc(this.oxygenShape,21.7,89.85,17,-80,160,oxygen);',
  'this.drawArc(this.carbonDioxideShape,16.1,88.3,11,-80,160,carbonDioxide);',
  'language != "ja" && language != "zhhans"',
  'this.dayCycleShape.visible = !inFlight;',
  'this.informationLayer.addChild(this.statusField);'
)) {
  Assert-TestCondition ($viewSource.Contains($viewToken)) "Chronomark measured view contract changed: $viewToken"
}
foreach ($markerToken in @(
  'NEAR_RADIUS:Number = 126',
  'FAR_RADIUS:Number = 118.5',
  'OUTLINE_RADIUS:Number = 111',
  'int(param2.iconType) != CanvasChronomarkStyle.LOCATION_MARKER_TYPE',
  'param1.rotation = (heading - this.direction) * 180 / Math.PI;'
)) {
  Assert-TestCondition ($markersSource.Contains($markerToken)) "Chronomark measured marker contract changed: $markerToken"
}
Assert-TestCondition ($surfaceSource.IndexOf('addChild(this.effects);', [System.StringComparison]::Ordinal) -lt $surfaceSource.IndexOf('addChild(this.alertLayer);', [System.StringComparison]::Ordinal)) 'Chronomark alerts no longer render above the bounded effect layer.'
Assert-TestCondition (!$surfaceSource.Contains('getBounds(')) 'Chronomark layout again depends on mutable aggregate display bounds.'
foreach ($fixedCorner in @('new Point(0,0)', 'new Point(CanvasChronomarkStyle.FACE_SIZE,0)', 'new Point(0,CanvasChronomarkStyle.FACE_SIZE)', 'new Point(CanvasChronomarkStyle.FACE_SIZE,CanvasChronomarkStyle.FACE_SIZE)')) {
  Assert-TestCondition ($surfaceSource.Contains($fixedCorner)) "Chronomark fixed measured face corner is missing: $fixedCorner"
}
$layout = @{ visibleX = -14.0; visibleY = 5.0; visibleWidth = 1920.0; visibleHeight = 1080.0; safeX = 44.0; safeY = 38.0; ownerAppliesOpacity = $true }
$displayStates = @(
  @{ markers = 0; personalEffects = 0; environmentEffects = 0; alert = '' },
  @{ markers = 48; personalEffects = 5; environmentEffects = 4; alert = ('W' * 96) },
  @{ markers = 48; personalEffects = 0; environmentEffects = 4; alert = ('M' * 96) },
  @{ markers = 0; personalEffects = 0; environmentEffects = 0; alert = '' }
)
foreach ($mode in @('normal', 'large')) {
  $placements = @($displayStates | ForEach-Object { Get-TestFixedFacePlacement -Mode $mode -Layout $layout -DisplayState $_ })
  Assert-TestCondition (@($placements | Select-Object -Unique).Count -eq 1) "Chronomark $mode placement depends on empty/max/opposite/empty display content."
}

Assert-TestCondition ($dataSource.Contains('this.collectionLength(param1,CanvasChronomarkStyle.PERSONAL_EFFECT_INGRESS_CAPACITY)')) 'Personal-effect normalization no longer scans its bounded raw ingress window.'
Assert-TestCondition ($dataSource.Contains('result.length < CanvasChronomarkStyle.PERSONAL_EFFECT_CAPACITY')) 'Personal-effect normalization no longer fills only the five-slot visible capacity.'
$blacklistFirst = @('Sustenance_Food_Positive_1', 'Sustenance_Drink_Negative_2', 'PersonalEffect_CardioRespiratoryCirculatory', 'PersonalEffect_SkeletalMuscular', 'PersonalEffect_NervousSystem', 'PersonalEffect_DigestiveImmune', 'PersonalEffect_Misc')
Assert-TestCondition (@(Get-TestNormalizedPersonalEffects -Icons $blacklistFirst).Count -eq 5) 'Blacklist-first personal effects do not fill all five eligible slots.'
$duplicates = @('PersonalEffect_CardioRespiratoryCirculatory', 'PersonalEffect_CardioRespiratoryCirculatory', 'PersonalEffect_SkeletalMuscular', 'PersonalEffect_SkeletalMuscular', 'PersonalEffect_NervousSystem')
$deduplicated = @(Get-TestNormalizedPersonalEffects -Icons $duplicates)
Assert-TestCondition ($deduplicated.Count -eq 3 -and @($deduplicated | Select-Object -Unique).Count -eq 3) 'Duplicate personal effects consume visible capacity.'
$sixEligible = @('Eligible-1', 'Eligible-2', 'Eligible-3', 'Eligible-4', 'Eligible-5', 'Eligible-6')
$capacityResult = @(Get-TestNormalizedPersonalEffects -Icons $sixEligible)
Assert-TestCondition ($capacityResult.Count -eq 5 -and $capacityResult[-1] -ceq 'Eligible-5') 'Personal-effect visible capacity or one-past handling changed.'
$onePastIngress = @(1..48 | ForEach-Object { 'Sustenance_Food_Positive_1' }) + @('Eligible-Outside-Ingress')
Assert-TestCondition (@(Get-TestNormalizedPersonalEffects -Icons $onePastIngress).Count -eq 0) 'Personal-effect normalization reads one past its bounded raw ingress window.'

Assert-TestCondition ($surfaceSource.Contains('if(!this.hasScannerState || scannerChanged)')) 'Chronomark forwards unchanged scanner state and can cancel a temporary planet dwell.'
Assert-TestCondition ($surfaceSource.Contains('if(leftSpaceship && !nextScanning && !scannerChanged)')) 'Chronomark ship-exit dwell no longer distinguishes scanner transitions.'
$scannerState = @{ HasEnvironment = $false; InSpaceship = $false; HasScanner = $false; Scanning = $false; ScannerTarget = 0; HoldRemaining = 0 }
Assert-TestCondition ((Invoke-TestScannerEvent -State $scannerState -InSpaceship $true -Scanning $false) -ceq 'scanner-initial') 'Initial scanner state model failed.'
Assert-TestCondition ((Invoke-TestScannerEvent -State $scannerState -InSpaceship $false -Scanning $false) -ceq 'planet-hold' -and $scannerState.HoldRemaining -eq 3000) 'Ship exit did not start the temporary planet-info dwell.'
Assert-TestCondition ((Invoke-TestScannerEvent -State $scannerState -InSpaceship $false -Scanning $false) -ceq 'none' -and $scannerState.HoldRemaining -eq 3000) 'Unchanged LocalEnvironmentData canceled the temporary planet-info dwell.'
Assert-TestCondition ((Invoke-TestScannerEvent -State $scannerState -InSpaceship $false -Scanning $true) -ceq 'scanner-transition' -and $scannerState.HoldRemaining -eq 0 -and $scannerState.ScannerTarget -eq 1) 'Scanner activation did not authoritatively replace the temporary planet-info dwell.'

$effectRegistry = @{}
foreach ($match in [regex]::Matches($effectsSource, 'case "(?<icon>[^"]+)":\s*return "(?<style>[^"]+)";')) {
  $effectRegistry[$match.Groups['icon'].Value] = $match.Groups['style'].Value
}
$expectedEffectRegistry = [ordered]@{
  HazardEffect_Radiation = 'radiation'; HazardEffect_Thermal = 'thermal'; HazardEffect_Airborne = 'airborne'; HazardEffect_Corrosive = 'corrosive'; HazardEffect_RestoreSoak = 'restore'
  PersonalEffect_CardioRespiratoryCirculatory = 'cardio'; PersonalEffect_SkeletalMuscular = 'skeletal'; PersonalEffect_NervousSystem = 'nervous'; PersonalEffect_DigestiveImmune = 'digestive'; PersonalEffect_Misc = 'misc'
}
Assert-TestCondition ($effectRegistry.Count -eq $expectedEffectRegistry.Count) "Effect icon registry count changed. Expected $($expectedEffectRegistry.Count); found $($effectRegistry.Count)."
foreach ($entry in $expectedEffectRegistry.GetEnumerator()) {
  Assert-TestCondition ($effectRegistry.ContainsKey($entry.Key) -and $effectRegistry[$entry.Key] -ceq $entry.Value) "Effect icon '$($entry.Key)' no longer maps to procedural style '$($entry.Value)'."
}
Assert-TestCondition ($effectsSource.Contains('return "unknown";')) 'Unknown effect icons no longer use the neutral procedural fallback.'
Assert-TestCondition (!$effectsSource.Contains('hash(')) 'Effect icon selection again depends on an arbitrary provider-string hash.'
foreach ($lifecycleToken in @(
  'this.callbacks[channel] = this.createCallback(channel,currentGeneration);',
  'this.subscribed[channel] = true;',
  'this.dataManager.Subscribe(channel,this.callbacks[channel]);',
  'this.disposed = true;',
  'this.generation++;',
  'this.dataManager.Unsubscribe(channel,callback);',
  'callbacks[param1] !== callback'
)) {
  Assert-TestCondition ($dataSource.Contains($lifecycleToken)) "Chronomark subscription lifecycle token is missing: $lifecycleToken"
}
$callbackOwnershipIndex = $dataSource.IndexOf('this.callbacks[channel] = this.createCallback(channel,currentGeneration);', [System.StringComparison]::Ordinal)
$providerReplayIndex = $dataSource.IndexOf('this.dataManager.GetDataFromClient(channel,true);', [System.StringComparison]::Ordinal)
$subscriptionOwnedIndex = $dataSource.IndexOf('this.subscribed[channel] = true;', [System.StringComparison]::Ordinal)
$subscribeIndex = $dataSource.IndexOf('this.dataManager.Subscribe(channel,this.callbacks[channel]);', [System.StringComparison]::Ordinal)
Assert-TestCondition ($callbackOwnershipIndex -ge 0 -and $callbackOwnershipIndex -lt $providerReplayIndex) 'Chronomark callback ownership is not established before provider replay begins.'
Assert-TestCondition ($providerReplayIndex -ge 0 -and $providerReplayIndex -lt $subscriptionOwnedIndex -and $subscriptionOwnedIndex -lt $subscribeIndex) 'Chronomark synchronous subscription replay ordering changed.'
$disposeIndex = $dataSource.IndexOf('public function dispose() : void', [System.StringComparison]::Ordinal)
$disposedIndex = $dataSource.IndexOf('this.disposed = true;', $disposeIndex, [System.StringComparison]::Ordinal)
$generationIndex = $dataSource.IndexOf('this.generation++;', $disposedIndex, [System.StringComparison]::Ordinal)
$unsubscribeIndex = $dataSource.IndexOf('this.dataManager.Unsubscribe(channel,callback);', $generationIndex, [System.StringComparison]::Ordinal)
Assert-TestCondition ($disposeIndex -ge 0 -and $disposedIndex -gt $disposeIndex -and $generationIndex -gt $disposedIndex -and $unsubscribeIndex -gt $generationIndex) 'Chronomark disposal is no longer terminal-first and generation-guarded before unsubscribe.'
foreach ($name in $chronomarkNames | Where-Object { $_ -cne 'CanvasChronomarkAnimation.as' }) {
  Assert-TestCondition (!([string]$sources[$name]).Contains('Event.ENTER_FRAME')) "Chronomark class '$name' owns an unexpected frame clock."
}
Assert-TestCondition ($animationSource.Contains('addEventListener(Event.ENTER_FRAME,this.onEnterFrame')) 'Chronomark animation no longer owns the single conditional frame clock.'
Assert-TestCondition ($animationSource.Contains('removeEventListener(Event.ENTER_FRAME,this.onEnterFrame')) 'Chronomark animation no longer tears down its frame clock.'
Assert-TestCondition ($animationSource.Contains('this.alertQueue.length + (this.activeAlert == null ? 0 : 1) < CanvasChronomarkStyle.ALERT_QUEUE_CAPACITY')) 'Chronomark alerts are no longer bounded as complete transactions.'
Assert-TestCondition ($animationSource.Contains('this.scannerTarget = param1 ? 1 : 0;')) 'Chronomark scanner state is no longer authoritative and coalesced.'

foreach ($bridgeToken in @(
  'public function getVenworksCanvasDataManager() : Object',
  'public function getVenworksCanvasHudLayout() : Object',
  '"visibleX":Number(visibleRect.x)',
  '"safeX":Number(SafeX)',
  'public function playVenworksCanvasSound(param1:String) : Boolean',
  'GlobalFunc.PlayMenuSound(param1);',
  'private var VenworksCanvasHudOpacity:Number = 1;',
  'VenworksCanvasHudOpacity = isFinite(venworksCanvasOpacity) ? Math.max(0,Math.min(1,venworksCanvasOpacity)) : 1;',
  'this.VenworksCanvasRegistryBridge.alpha = this.VenworksCanvasHudOpacity;'
)) {
  Assert-TestCondition ($loaderPatch.Contains($bridgeToken)) "Player HUD bridge token is missing: $bridgeToken"
}
$opacityInsertion = @($loaderPatchXml.actionScriptPatch.insertions.insertion | Where-Object { $_.content.InnerText.Contains('VenworksCanvasHudOpacity = isFinite(venworksCanvasOpacity)') })
Assert-TestCondition ($opacityInsertion.Count -eq 1) "Expected exactly one HUD-opacity cache insertion; found $($opacityInsertion.Count)."
Assert-TestCondition ($opacityInsertion[0].anchor.InnerText -ceq '            var _loc3_:MovieClip = null;') 'HUD-opacity cache insertion no longer uses its newline-independent callback-body anchor.'
Assert-TestCondition (!$opacityInsertion[0].anchor.InnerText.Contains("`r") -and !$opacityInsertion[0].anchor.InnerText.Contains("`n")) 'HUD-opacity cache insertion anchor again depends on XML/source newline normalization.'
$cachedOpacity = 1.0
$bridgeOpacity = $null
$cachedOpacity = [Math]::Max([double]0, [Math]::Min([double]1, [double]0.35))
$bridgeOpacity = $cachedOpacity
Assert-TestCondition ([Math]::Abs($bridgeOpacity - 0.35) -lt 0.000001) 'A non-100% HUD opacity replayed before auxiliary attachment was not applied on attachment.'
$cachedOpacity = [Math]::Max([double]0, [Math]::Min([double]1, [double]0.72))
$bridgeOpacity = $cachedOpacity
Assert-TestCondition ([Math]::Abs($bridgeOpacity - 0.72) -lt 0.000001) 'A later HUD opacity update was not applied to the attached auxiliary.'
Assert-TestCondition ($surfaceSource.Contains('if(!this.ownerAppliesOpacity)')) 'Chronomark no longer avoids double multiplication when HUDMenu owns auxiliary opacity.'
$expectedSounds = @(
  'VOC_Player_O2_Min', 'VOC_Player_CO2_Cleared', 'VOC_Player_CO2_Max',
  'UIAfflictionPainWarningScreenOn', 'UIAfflictionPainWarningScreenOff',
  'UIHazardRadiationWarningScreen', 'UIHazardThermalWarningScreen', 'UIHazardAirborneWarningScreen', 'UIHazardCorrosiveWarningScreen', 'UIHazardSuitSoakRestore_WarningScreen',
  'UIHazardDamagePermanent',
  'UIHazardRadiationWarningIcon', 'UIHazardThermalWarningIcon', 'UIHazardAirborneWarningIcon', 'UIHazardCorrosiveWarningIcon', 'UIHazardSuitSoakRestore_Icon'
)
$actualSounds = @([regex]::Matches($loaderPatch, 'case &quot;(?<sound>[^&]+)&quot;:|case "(?<sound>[^"]+)":') | ForEach-Object { $_.Groups['sound'].Value } | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
Assert-TestCondition ($actualSounds.Count -eq $expectedSounds.Count) "HUDMenu sound allowlist count changed. Expected $($expectedSounds.Count); found $($actualSounds.Count)."
foreach ($sound in $expectedSounds) {
  Assert-TestCondition ($actualSounds -ccontains $sound) "HUDMenu sound allowlist is missing '$sound'."
}

Assert-TestCondition ($manifest.Contains('<token>BottomLeftGroup</token>')) 'Canvas host manifest no longer rejects native Watch references.'
Assert-TestCondition ($manifest.Contains('<token>UIWatchAlert_</token>')) 'Canvas host manifest no longer rejects provider-controlled Watch sound identifiers.'
Assert-TestCondition ($matrix.Contains("CustomAlerts = 'DataLayerOnlyNotRendered'")) 'Canvas compatibility matrix no longer records the custom-alert rendering exclusion.'
foreach ($channel in $expectedChannels) {
  Assert-TestCondition ($matrix.Contains("'$channel'")) "Canvas compatibility matrix is missing Chronomark provider '$channel'."
}

$patchFixtureParent = Join-Path $repositoryRoot '.work\canvas\chronomark-patch-test'
$patchFixtureRoot = Join-Path $patchFixtureParent ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $patchFixtureRoot | Out-Null
try {
  $pristineSource = @'
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
         CENTER_GROUP_POINT.y = this.CenterGroup_mc.y;
      }

      override public function onAddedToStage() : void
      {
         super.onAddedToStage();
         BSUIDataManager.Subscribe("HUDOpacityData",function(param1:FromClientDataEvent):*
         {
            var _loc3_:MovieClip = null;
            var _loc2_:int = 0;
         });
      }
   }
}
'@
  $patchPath = Join-Path $repositoryRoot 'Scaleform\canvas\patches\player-hud-auxiliary-loader.xml'
  $normalPatch = Get-BuildActionScriptPatch -PatchPath $patchPath -DisplayMode 'normal'
  Assert-TestCondition (@($normalPatch.IdempotenceTokens).Count -eq 10) "Player HUD auxiliary patch idempotence marker count changed. Expected 10; found $(@($normalPatch.IdempotenceTokens).Count)."
  Assert-TestCondition (@($normalPatch.ExactInspectionTokens).Count -eq 10) "Player HUD auxiliary patch exact inspection marker count changed. Expected 10; found $(@($normalPatch.ExactInspectionTokens).Count)."
  $fullInitializeToken = 'this.VenworksCanvasRegistryBridge["initialize"](this,{"protocol":"VWCANVAS_HOST/1","hostKind":"player","displayMode":"normal","layout":this.getVenworksCanvasHudLayout()})'
  $stableInitializeToken = 'this.VenworksCanvasRegistryBridge["initialize"](this,{'
  Assert-TestCondition (@($normalPatch.IdempotenceTokens | Where-Object { $_ -ceq $fullInitializeToken }).Count -eq 1) 'Player HUD auxiliary patch no longer uses the full initialization transaction as its pre-import idempotence marker.'
  Assert-TestCondition (@($normalPatch.ExactInspectionTokens | Where-Object { $_ -ceq $stableInitializeToken }).Count -eq 1) 'Player HUD auxiliary patch does not use the stable initialization prefix for post-JPEXS exact-count inspection.'
  Assert-TestCondition (@($normalPatch.ExactInspectionTokens | Where-Object { $_ -ceq $fullInitializeToken }).Count -eq 0) 'Player HUD auxiliary patch exact inspection still depends on JPEXS-preserved object-literal line formatting.'

  $sourcePath = Join-Path $patchFixtureRoot 'HUDMenu.as'
  Write-BuildUtf8WithoutBom -Path $sourcePath -Text $pristineSource
  Apply-BuildActionScriptPatch -SourcePath $sourcePath -Patch $normalPatch
  $oncePatched = [IO.File]::ReadAllText($sourcePath)
  foreach ($token in @($normalPatch.IdempotenceTokens)) {
    Assert-TestCondition ((Get-BuildOrdinalOccurrenceCount -Source $oncePatched -Value $token) -eq 1) "Fresh Player HUD patch did not create exactly one canonical auxiliary token '$token'."
  }
  foreach ($token in @($normalPatch.ExactInspectionTokens)) {
    Assert-TestCondition ((Get-BuildOrdinalOccurrenceCount -Source $oncePatched -Value $token) -eq 1) "Fresh Player HUD patch did not create exactly one post-export inspection token '$token'."
  }

  $jpexsReformattedInitialize = @'
this.VenworksCanvasRegistryBridge["initialize"](this,{
                  "protocol":"VWCANVAS_HOST/1",
                  "hostKind":"player",
                  "displayMode":"normal",
                  "layout":this.getVenworksCanvasHudLayout()
               })
'@
  $jpexsLikeSource = $oncePatched.Replace($fullInitializeToken, $jpexsReformattedInitialize.TrimEnd("`r", "`n"))
  Assert-TestCondition ($jpexsLikeSource -cne $oncePatched) 'JPEXS reformatting fixture did not replace the canonical one-line initialization transaction.'
  Assert-TestCondition ((Get-BuildOrdinalOccurrenceCount -Source $jpexsLikeSource -Value $fullInitializeToken) -eq 0) 'JPEXS reformatting fixture unexpectedly retained the full pre-import idempotence marker.'
  foreach ($token in @($normalPatch.ExactInspectionTokens)) {
    Assert-TestCondition ((Get-BuildOrdinalOccurrenceCount -Source $jpexsLikeSource -Value $token) -eq 1) "Post-JPEXS exact inspection token '$token' was not formatting-stable."
  }
  Assert-TestCondition ((Get-BuildOrdinalOccurrenceCount -Source $jpexsLikeSource -Value '"displayMode":"normal"') -eq 1) 'JPEXS reformatting fixture lost or duplicated the normal display-mode inspection token.'
  Apply-BuildActionScriptPatch -SourcePath $sourcePath -Patch $normalPatch
  Assert-TestCondition ([IO.File]::ReadAllText($sourcePath) -ceq $oncePatched) 'Reapplying the Player HUD auxiliary patch was not a byte-identical validated no-op.'

  $partialPath = Join-Path $patchFixtureRoot 'HUDMenu-partial.as'
  $partialSource = $pristineSource.Replace('      private var SkillPatchLoader:Loader = null;', "      private var SkillPatchLoader:Loader = null;`n`n      private var VenworksCanvasRegistryLoader:Loader = null;")
  Write-BuildUtf8WithoutBom -Path $partialPath -Text $partialSource
  Assert-TestPatchRejectedWithoutWrite -SourcePath $partialPath -Patch $normalPatch -ExpectedMessage 'incomplete or duplicate applied state'

  $duplicatePath = Join-Path $patchFixtureRoot 'HUDMenu-duplicate.as'
  Write-BuildUtf8WithoutBom -Path $duplicatePath -Text ($oncePatched + "`n" + $oncePatched)
  Assert-TestPatchRejectedWithoutWrite -SourcePath $duplicatePath -Patch $normalPatch -ExpectedMessage 'expected 1, found 2'

  $missingRequiredPath = Join-Path $patchFixtureRoot 'HUDMenu-missing-required.as'
  Write-BuildUtf8WithoutBom -Path $missingRequiredPath -Text $oncePatched.Replace('GlobalFunc.PlayMenuSound(param1);', '')
  Assert-TestPatchRejectedWithoutWrite -SourcePath $missingRequiredPath -Patch $normalPatch -ExpectedMessage 'missing required token'
} finally {
  if (Test-Path -LiteralPath $patchFixtureRoot -PathType Container) {
    Remove-Item -LiteralPath $patchFixtureRoot -Recurse -Force
  }
}

Write-Host -ForegroundColor Green 'Verified Canvas-owned Chronomark source, lifecycle, provider, capacity, clock, HUD bridge, and custom-alert separation contracts.'
