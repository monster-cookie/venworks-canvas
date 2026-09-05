<#
.SYNOPSIS
Executes the extracted receiver and subscription bodies in Node with provider fixtures.
.DESCRIPTION
This is a source-derived JavaScript compatibility harness, not Flash, Scaleform or Starfield.
The separate movie build validates ActionScript compilation and class encoding.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourcePath = Join-Path $root 'Scaleform\probes\consumer-discovery\actionscript\CanvasConsumerDiscoveryHost.as'
$source = Get-Content -LiteralPath $sourcePath -Raw
$nodePath = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$functions = @{}
foreach ($name in @('subscribe', 'onCustomAlertsData', 'receiveNote', 'appendCallbackDiagnostic', 'appendAlertDiagnostic')) {
  $match = [regex]::Match($source, '(?ms)      private function ' + $name + '\([^\r\n]*\) : void\s*\{(?<body>.*?)^      \}')
  if (!$match.Success) { throw "Missing receiver method: $name" }
  $functions[$name] = $match.Groups['body'].Value -replace ':(Object|Number|String|int|Error)\b', ''
}
$prefixMatch = [regex]::Match($source, '(?ms)      private function matchAsciiPrefix\([^\r\n]*\) : int\s*\{(?<body>.*?)^      \}')
if (!$prefixMatch.Success) { throw 'Missing receiver method: matchAsciiPrefix' }
$functions.matchAsciiPrefix = $prefixMatch.Groups['body'].Value -replace ':(Object|Number|String|int|Boolean|Error)\b', ''
if ($functions.onCustomAlertsData -match '\bas\s+Array\b' -or $functions.subscribe -match 'getDefinitionByName') {
  throw 'Receiver must use the patched Watch class reference and indexed native collections.'
}
foreach ($token in @(
  'MAX_CALLBACK_DIAGNOSTICS:int = 8',
  'MAX_ALERT_DIAGNOSTICS:int = 16',
  'PROVIDER CALLBACK DIAGNOSTICS SUPPRESSED',
  'PROVIDER ALERT DIAGNOSTICS SUPPRESSED'
)) {
  if (!$source.Contains($token)) { throw "Missing bounded receiver diagnostic contract: $token" }
}
$fixtureJson = $functions | ConvertTo-Json -Compress
$test = @'
const assert = require('node:assert/strict');
const PROVIDER = 'CustomAlertsData';
const ENVELOPE_PREFIX = 'VWC_EVT/1|';
const UI_LOAD_PREFIX = ENVELOPE_PREFIX + 'canvas.ui.load|';
const first = UI_LOAD_PREFIX + 'fixture-a';
const second = UI_LOAD_PREFIX + 'fixture-b';
const folded = 'vwc_evt/1|CANVAS.UI.LOAD|fixture-folded';
function makeHost(disabled = true, ready = true, subscriptionsRestored = true) {
  const host = { disposed: false, subscribed: false, receiveNotes: {}, logs: [], received: [],
    callbackCount: 0, alertDiagnosticCount: 0,
    appendDiagnostic(text) { this.logs.push(text); }, sanitizeText(value) { return String(value); },
    receiveEnvelope(text) { this.received.push(text); } };
  host.receiveNote = new Function('key', 'message', functions.receiveNote);
  const appendCallbackDiagnostic = new Function('message', 'MAX_CALLBACK_DIAGNOSTICS', functions.appendCallbackDiagnostic);
  const appendAlertDiagnostic = new Function('classification', 'characterCount', 'MAX_ALERT_DIAGNOSTICS', functions.appendAlertDiagnostic);
  host.appendCallbackDiagnostic = message => appendCallbackDiagnostic.call(host, message, 8);
  host.appendAlertDiagnostic = (classification, characterCount = -1) => appendAlertDiagnostic.call(host, classification, characterCount, 16);
  host.matchAsciiPrefix = new Function('value', 'prefix', functions.matchAsciiPrefix);
  host.onCustomAlertsData = new Function('param1', 'UI_LOAD_PREFIX', 'ENVELOPE_PREFIX', functions.onCustomAlertsData);
  host.callback = value => host.onCustomAlertsData(value, UI_LOAD_PREFIX, ENVELOPE_PREFIX);
  const manager = { gets: 0, subscribes: 0, unsubscribes: 0, listener: null,
    provider: { dataReady: ready, data: { aAlerts: [{sAlertText: first}] } },
    GetDataFromClient(name, create) { assert.equal(name, PROVIDER); assert.equal(create, true); this.gets++; return this.provider; },
    Subscribe(name, callback) {
      assert.equal(this.gets, 1); this.subscribes++; this.listener = callback;
      if (this.provider.dataReady) callback({get data() { return manager.provider.data; }});
    },
    Unsubscribe(name, callback) { assert.equal(callback, this.listener); this.listener = null; this.unsubscribes++; }
  };
  host.owner = { BottomLeftGroup_mc: {
    getCanvasWatchDisabled: () => disabled,
    getCanvasWatchSubscriptionsRestored: () => subscriptionsRestored,
    getCanvasWatchDataManager: () => manager
  } };
  host.subscribe = () => new Function('PROVIDER', functions.subscribe).call(host, PROVIDER);
  return {host, manager};
}
let checks = 0;
function check(action) { action(); checks++; }
check(() => { const {host,manager} = makeHost(); host.subscribe(); host.subscribe(); assert.deepEqual(host.received,[first]); assert.equal(manager.subscribes,1); assert(host.logs.includes('WATCH SUBSCRIPTIONS RESTORED')); assert(host.logs.includes('WATCH PRESENTATION DISABLED')); });
check(() => { const {host,manager} = makeHost(true,false); host.subscribe(); assert.equal(host.received.length,0); manager.listener({data:{aAlerts:[{sAlertText:'vanilla'}]}}); manager.listener({data:{aAlerts:[{sAlertText:second}]}}); assert.deepEqual(host.received,[second]); assert(host.logs.includes('PROVIDER CALLBACK #2 | ALERTS 1')); assert(host.logs.some(x=>x.includes('UI LOAD | PREFIX EXACT | LENGTH ' + second.length))); });
check(() => { const {host,manager} = makeHost(false); host.subscribe(); assert.equal(manager.subscribes,0); assert(host.logs.some(x=>x.includes('WATCH PRESENTATION ACTIVE'))); });
check(() => { const {host,manager} = makeHost(true,true,false); host.subscribe(); assert.equal(manager.subscribes,0); assert(host.logs.some(x=>x.includes('WATCH SUBSCRIPTIONS NOT RESTORED'))); });
check(() => { const {host,manager} = makeHost(); host.owner = {}; host.subscribe(); assert.equal(manager.gets,0); });
check(() => { const {host,manager} = makeHost(); manager.Subscribe = function(name,callback) { this.listener=callback; throw Error('fixture failure after install'); }; host.subscribe(); assert.equal(manager.listener,null); assert.equal(manager.unsubscribes,1); assert.equal(host.subscribed,false); });
for (const wrapped of [false,true]) {
  for (const indexed of [false,true]) check(() => {
    const {host}=makeHost(); const items=[{sAlertText:first},{sAlertText:second}];
    const data={aAlerts:indexed?{0:items[0],1:items[1],length:2}:items};
    host.callback(wrapped?{get data(){return data;}}:data); assert.deepEqual(host.received,[first,second]);
  });
}
for (const data of [null, {}, {aAlerts:null}, {aAlerts:'bad'}, {aAlerts:{length:'2'}},
  {aAlerts:{length:-1}}, {aAlerts:{length:1.5}}, {aAlerts:{length:Infinity}}, {aAlerts:{length:NaN}},
  {aAlerts:{length:257}}, {data:null}]) check(() => {
  const {host}=makeHost(); host.callback(data); assert.equal(host.received.length,0);
  assert(host.logs.some(x=>x.includes('PAYLOAD REJECTED')));
});
check(() => { const {host}=makeHost(); host.callback({get data(){throw Error('getter failure');}}); assert(host.logs.some(x=>x.includes('PAYLOAD REJECTED'))); });
check(() => { const {host}=makeHost(); host.callback({aAlerts:[null,42,{}, {sAlertText:5}, {sAlertText:first}]}); assert.deepEqual(host.received,[first]); assert.equal(host.logs.filter(x=>x.includes('INVALID ENTRY')).length,4); });
check(() => { const {host}=makeHost(); host.callback({aAlerts:[{sAlertText:'vanilla-private-text'},{sAlertText:'VWC_EVT/1|canvas.registry.snapshot|old'},{sAlertText:first}]}); assert.deepEqual(host.received,[first]); assert(!host.logs.join('').includes('vanilla-private-text')); assert(host.logs.some(x=>x.includes('OTHER | LENGTH 20'))); assert(host.logs.some(x=>x.includes('CANVAS OTHER'))); assert(host.logs.some(x=>x.includes('UI LOAD'))); });
check(() => { const {host}=makeHost(); host.callback({aAlerts:[{sAlertText:folded}]}); assert.deepEqual(host.received,[folded]); assert(host.logs.some(x=>x.includes('UI LOAD | PREFIX ASCII CASE-FOLDED | LENGTH ' + folded.length))); });
check(() => { const {host}=makeHost(); assert.equal(host.matchAsciiPrefix(first,UI_LOAD_PREFIX),1); assert.equal(host.matchAsciiPrefix(folded,UI_LOAD_PREFIX),2); assert.equal(host.matchAsciiPrefix('VWC_ÉVT/1|canvas.ui.load|fixture',UI_LOAD_PREFIX),0); assert.equal(host.matchAsciiPrefix('VWC_EVT/1|canvas.ui.other|fixture',UI_LOAD_PREFIX),0); });
check(() => { const {host}=makeHost(); for(let i=0;i<1000;i++) host.callback({aAlerts:[]}); assert.equal(host.logs.filter(x=>x.includes('PROVIDER CALLBACK #')).length,8); assert.equal(host.logs.filter(x=>x.includes('CALLBACK DIAGNOSTICS SUPPRESSED')).length,1); });
check(() => { const {host}=makeHost(); host.callback({aAlerts:Array.from({length:100},()=>({sAlertText:'vanilla-private-text'}))}); assert.equal(host.logs.filter(x=>x.includes('PROVIDER ALERT #')).length,16); assert.equal(host.logs.filter(x=>x.includes('ALERT DIAGNOSTICS SUPPRESSED')).length,1); assert(!host.logs.join('').includes('vanilla-private-text')); });
check(() => { const {host}=makeHost(); host.disposed=true; host.callback({aAlerts:[{sAlertText:first}]}); host.subscribe(); assert.equal(host.logs.length,0); assert.equal(host.received.length,0); });
check(() => { const {host}=makeHost(); host.callback({aAlerts:Array.from({length:256},()=>({sAlertText:'vanilla'}))}); assert(!host.logs.some(x=>x.includes('REJECTED'))); });
console.log(`PASS ${checks} extracted subscription/receiver fixture checks (Node, not Scaleform).`);
'@
& $nodePath -e ("const functions = $fixtureJson;`n" + $test)
if ($LASTEXITCODE -ne 0) { throw "Receiver fixtures failed: $LASTEXITCODE" }

[xml]$patch = Get-Content -LiteralPath (Join-Path $root 'Scaleform\probes\consumer-discovery\patches\player-hud-watch-disabled.xml') -Raw
if ($patch.actionScriptPatch.script -cne 'BottomLeftGroup') { throw 'Watch patch must target only BottomLeftGroup.' }
$insertions = @($patch.SelectNodes('/actionScriptPatch/insertions/insertion'))
foreach ($token in @('this.disableCanvasWatch();', 'this.AlertTimer.stop();', 'removeChildAt(0);', 'return BSUIDataManager;', 'return false;', 'getCanvasWatchSubscriptionsRestored', 'CanvasWatchSubscriptionsRestored')) {
  if (!($insertions.content.InnerText -join "`n").Contains($token)) { throw "Missing Watch isolation contract: $token" }
}
$onAddedInsertion = @($insertions | Where-Object { $_.anchor.InnerText -ceq '         super.onAddedToStage();' })
if ($onAddedInsertion.Count -ne 1 -or $onAddedInsertion[0].content.InnerText.Contains('return;') -or $onAddedInsertion[0].content.InnerText.Contains('disableCanvasWatch')) {
  throw 'Watch onAddedToStage must continue through every vanilla subscription before presentation teardown.'
}
$subscriptionInsertion = @($insertions | Where-Object { $_.anchor.InnerText -ceq '         BSUIDataManager.Subscribe("CustomAlertsData",this.onCustomAlertsDataChange);' })
if ($subscriptionInsertion.Count -ne 1 -or !$subscriptionInsertion[0].content.InnerText.Contains('this.CanvasWatchSubscriptionsRestored = true;') -or !$subscriptionInsertion[0].content.InnerText.Contains('this.disableCanvasWatch();')) {
  throw 'Watch presentation teardown must run only after the final vanilla subscription.'
}
Write-Host 'Watch subscription-restoration and presentation-isolation patch contracts passed; in-game Watch absence and consumer rendering remain manual acceptance.'
