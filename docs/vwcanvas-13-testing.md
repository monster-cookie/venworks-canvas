# VWCANVAS-13 documentation and source checks

This guide verifies the VWCANVAS-13 provider inventory and its source evidence. The registration, profile, link, and ownership blocks are read-only and do not build, package, install, deploy, change Plane, change VWHUD, or run a game. The optional Canvas source-only fixture check is separate and creates only ignored .work scratch. Run it from the Canvas repository root in PowerShell 7 or later.

## Prerequisites

Provide a separate read-only checkout of VWHUD at the reviewed commit 0a1c922bca6fd9677d48ce50f5524583937ab77a. The checkout must contain Scaleform/shared/actionscript/venworks/cui/CUIPlayerHudDataContext.as, Scaleform/shared/actionscript/venworks/cui/CUIConditionContext.as, Scaleform/variants/MIN/movies/minimalist-live.psd1, and Scaleform/variants/MIN/patches/minimalist-live.xml. Set the path for the session; do not commit or modify that checkout.

~~~powershell
$ErrorActionPreference = 'Stop'
$vwhudRoot = '<path-to-read-only-vwhud-checkout>'
$vwhudRoot = (Resolve-Path -LiteralPath $vwhudRoot -ErrorAction Stop).Path
$vwhudGitArgs = @('-c', "safe.directory=$vwhudRoot", '-C', $vwhudRoot)
$vwhudCommit = @(git @vwhudGitArgs rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or ($vwhudCommit -join '').Trim() -ne '0a1c922bca6fd9677d48ce50f5524583937ab77a') {
    throw 'VWHUD Git inspection failed or its revision differs from the inventory.'
}
$vwhudStatus = @(git @vwhudGitArgs status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $vwhudStatus.Count -ne 0) {
    throw 'VWHUD inspection failed or its working tree is not clean; preserve existing changes.'
}
~~~

Expected: the checkout exists, native Git reports the immutable VWHUD source commit, and the external checkout has a clean working tree. The process-scoped safe.directory option avoids changing Git configuration.

## Immutable-link and source-anchor checks

Validate source links in the inventory against the expected revision and the Git object at each linked path. Anchors are checked against pinned blob contents, so a later Canvas documentation commit or working-tree source change cannot substitute different source text. This block reads Git objects without fetching or changing either repository.

~~~powershell
$expectedVwhudCommit = '0a1c922bca6fd9677d48ce50f5524583937ab77a'
$expectedCanvasCommit = '7eb92df96975d4513c8ccbc69e766183ff662a2d'
$canvasRoot = (Get-Location).Path
$githubUrls = @([regex]::Matches(
    (Get-Content -LiteralPath '.\docs\vwhud-provider-inventory.md' -Raw),
    'https://github\.com/[^)\s]+'
) | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($githubUrls.Count -eq 0) { throw 'No source links were found.' }
foreach ($url in $githubUrls) {
    $parsed = [regex]::Match($url, '^https://github\.com/monster-cookie/(venworks-honkcore-ta-ui|venworks-canvas)/(blob|tree)/([0-9a-f]{40})(?:/([^#]+))?(?:#L(\d+)(?:-L(\d+))?)?$')
    if (-not $parsed.Success) { throw "Malformed or nonimmutable source link: $url" }
    $isVwhud = $parsed.Groups[1].Value -eq 'venworks-honkcore-ta-ui'
    $expectedCommit = if ($isVwhud) { $expectedVwhudCommit } else { $expectedCanvasCommit }
    $sourceRoot = if ($isVwhud) { $vwhudRoot } else { $canvasRoot }
    if ($parsed.Groups[3].Value -ne $expectedCommit) { throw "Unexpected source revision: $url" }
    $gitArgs = @('-c', "safe.directory=$sourceRoot", '-C', $sourceRoot)
    $relativePath = $parsed.Groups[4].Value
    $objectSpec = if ($relativePath) { "${expectedCommit}:$relativePath" } else { "${expectedCommit}^{tree}" }
    $objectType = @(git @gitArgs cat-file -t $objectSpec)
    if ($LASTEXITCODE -ne 0) { throw "Pinned source object is unavailable: $url" }
    $expectedType = if ($parsed.Groups[2].Value -eq 'blob') { 'blob' } else { 'tree' }
    if (($objectType -join '').Trim() -ne $expectedType) { throw "Wrong linked object type: $url" }
    if ($parsed.Groups[5].Success) {
        if ($expectedType -ne 'blob') { throw "A tree link has a line anchor: $url" }
        $sourceLines = @(git @gitArgs show $objectSpec)
        if ($LASTEXITCODE -ne 0) { throw "Pinned source could not be read: $url" }
        $firstLine = [int]$parsed.Groups[5].Value
        $lastLine = if ($parsed.Groups[6].Success) { [int]$parsed.Groups[6].Value } else { $firstLine }
        if ($firstLine -lt 1 -or $lastLine -lt $firstLine -or $lastLine -gt $sourceLines.Count) {
            throw "Anchor is outside the pinned source: $url"
        }
    }
}
[pscustomobject]@{
    ImmutableVwhudLinks = @($githubUrls | Where-Object { $_ -match 'venworks-honkcore-ta-ui' }).Count
    ImmutableCanvasLinks = @($githubUrls | Where-Object { $_ -match 'venworks-canvas' }).Count
    CanvasBaseline = $expectedCanvasCommit
    VwhudBaseline = $expectedVwhudCommit
}
~~~

Expected: all links use the exact 40-character revision for their repository, every linked Git object exists and has the expected type, and each anchor is within its pinned blob. Missing history fails explicitly; obtaining another checkout or fetching history is a separate operation. Anchor bounds alone do not prove that the linked lines support a claim; review the cited text as well.
## Registration counts and profile checks

Count the actual registration calls and compare the MIN profile to the full source with its declared removals.

~~~powershell
$valueSource = Join-Path $vwhudRoot 'Scaleform/shared/actionscript/venworks/cui/CUIPlayerHudDataContext.as'
$conditionSource = Join-Path $vwhudRoot 'Scaleform/shared/actionscript/venworks/cui/CUIConditionContext.as'
$minProfile = Join-Path $vwhudRoot 'Scaleform/variants/MIN/movies/minimalist-live.psd1'
$minPatch = Join-Path $vwhudRoot 'Scaleform/variants/MIN/patches/minimalist-live.xml'
function Get-RegisteredProviders([string] $path) {
    [regex]::Matches((Get-Content -LiteralPath $path -Raw), 'subscribeProvider\("([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
}
$valueProviders = @(Get-RegisteredProviders $valueSource)
$conditionProviders = @(Get-RegisteredProviders $conditionSource)
$distinctProviders = @($valueProviders + $conditionProviders | Sort-Object -Unique)
$overlapProviders = @($valueProviders | Where-Object { $_ -in $conditionProviders } | Sort-Object -Unique)
$profile = Import-PowerShellDataFile -LiteralPath $minProfile
$minValue = @($profile.ValueProviders)
$minCondition = @($profile.ConditionProviders)
$removedValue = @('WeaponData', 'HUDStarbornPowersData', 'FavoritesData', 'ControlMapData')
$removedCondition = @('WeaponData', 'HUDStarbornPowersData', 'FavoritesData')
$expectedMinValue = @($valueProviders | Where-Object { $_ -notin $removedValue } | Sort-Object)
$expectedMinCondition = @($conditionProviders | Where-Object { $_ -notin $removedCondition } | Sort-Object)
if ($valueProviders.Count -ne 14 -or $conditionProviders.Count -ne 10 -or $distinctProviders.Count -ne 18 -or $overlapProviders.Count -ne 6) {
    throw 'Full registration count mismatch.'
}
if ((Compare-Object $expectedMinValue @($minValue | Sort-Object)) -or (Compare-Object $expectedMinCondition @($minCondition | Sort-Object))) {
    throw 'MIN provider sets do not match the full source minus its declared removals.'
}
if ($minValue.Count -ne 10 -or $minCondition.Count -ne 7 -or @($minValue + $minCondition | Sort-Object -Unique).Count -ne 14) {
    throw 'MIN registration count mismatch.'
}
Write-Output "PASS: Full value=$($valueProviders.Count), condition=$($conditionProviders.Count), distinct=$($distinctProviders.Count), overlap=$($overlapProviders.Count); MIN value=$($minValue.Count), condition=$($minCondition.Count), distinct=14."
~~~

Expected: full 14 value / 10 condition / 18 distinct / six overlaps, and MIN 10 value / seven condition / 14 distinct, with exact MIN provider-set equality.

Check that the MIN patch contains removal replacements for the same provider names and that all 18 distinct channels have a table row in the inventory.

~~~powershell
[xml]$patchXml = Get-Content -LiteralPath $minPatch -Raw
$patchText = $patchXml.OuterXml
foreach ($provider in $removedValue) {
    if ($patchText -notmatch [regex]::Escape($provider)) { throw "MIN patch is missing $provider" }
}
$inventoryText = Get-Content -LiteralPath './docs/vwhud-provider-inventory.md' -Raw
foreach ($provider in $distinctProviders) {
    if ($inventoryText -notmatch ('(?m)^\| ' + [regex]::Escape($provider) + ' \|')) {
        throw "No inventory row exists for $provider"
    }
}
foreach ($required in @('PS5DBG', 'HudModeData', 'ModeVisibilityA', 'No fresh runtime probe')) {
    if ($inventoryText -notmatch [regex]::Escape($required)) { throw "Missing integration or evidence boundary: $required" }
}
Write-Output 'PASS: Patch names, all 18 provider rows, and diagnostic/inherited integration boundaries are present.'
~~~

Expected: no missing provider row, removal name, or integration/evidence boundary. The patch-name check is a coverage check; inspect the linked patch to confirm its replacement semantics.
## Link and ownership checks

Check the delivered file links and the current/future ownership distinction. This does not fetch external links or replace factual source review.

~~~powershell
foreach ($path in @('./docs/vwhud-provider-inventory.md', './docs/vwcanvas-13-testing.md', './README.md', './CHANGELOG.md')) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing delivery file: $path" }
}
$readmeText = Get-Content -LiteralPath './README.md' -Raw
if ($readmeText -notmatch 'docs/vwhud-provider-inventory\.md' -or $readmeText -notmatch 'docs/vwcanvas-13-testing\.md') {
    throw 'README must link both documents.'
}
$changelogText = Get-Content -LiteralPath './CHANGELOG.md' -Raw
if ($changelogText -notmatch 'docs/vwhud-provider-inventory\.md') { throw 'The changelog inventory link is missing.' }
$inventoryText = Get-Content -LiteralPath './docs/vwhud-provider-inventory.md' -Raw
foreach ($required in @('Canvas is the eventual owner of shared acquisition', 'VWHUD retains tactical calculations', 'does not move acquisition into Canvas', 'No new game probe script')) {
    if ($inventoryText -notmatch [regex]::Escape($required)) { throw "Missing ownership boundary: $required" }
}
Write-Output 'PASS: README and changelog links and ownership boundaries are present.'
~~~

Expected: all four delivery files exist, README links both guides, the changelog links the inventory, and the document distinguishes current implementation from future ownership.
## Optional Canvas source-only fixture validation

The documentation checks above are read-only. This separate repository check creates configuration and a log under .work/vwcanvas-13 and fixture-owned scratch elsewhere under .work, including possible retained recovery output under .work/canvas/pr4-simplification. It does not invoke native Papyrus, Java, JPEXS, Flex, Archive2, deployment, or gameplay.

~~~powershell
$validationRoot = Join-Path $PWD '.work\vwcanvas-13'
New-Item -ItemType Directory -Force -Path $validationRoot | Out-Null
$validationEnv = Join-Path $validationRoot 'validation.env'
if (-not (Test-Path -LiteralPath $validationEnv)) {
    Set-Content -LiteralPath $validationEnv -Value '# Nonsecret source-only validation configuration'
}
$validationLog = Join-Path $validationRoot ('source-checks-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '.log')
pwsh -NoProfile -File .\Tools\verifyCanvas.ps1 -SourceOnly -EnvironmentPath $validationEnv 2>&1 | Tee-Object -FilePath $validationLog
$validationExit = $LASTEXITCODE
if ($validationExit -ne 0) { throw "Source-only fixtures failed with exit code $validationExit; inspect $validationLog" }
~~~

Expected: exit code 0 and five focused fixture suites reported as passed, with output retained in the timestamped log. This is source/tooling evidence only and does not establish runtime behavior.
## Runtime follow-up requiring approved instrumentation

No runtime check is included in the executed source gate. A future runtime acceptance pass requires separately approved instrumentation that can record provider name, callback timestamp, null versus no-snapshot state, payload shape, replay ordering, consumer fan-out, and unsubscribe completion for each selected channel. The instrumentation must be reviewed before use and must not be inferred from a source count or a translated model.

The follow-up should measure callback cadence for the 18 full-profile channels and 14 MIN channels, exercise null and missing fields, verify both shared-context consumers where applicable, observe teardown after HUD destruction, and repeat on the intended PC/console targets. The VWHUD diagnostic PlayerData subscription is a separate PS5DBG registration site and should be reported separately from the 18 production channels. Do not add a game probe script or adapter as part of this documentation task.

Expected: no runtime pass is recorded by this guide until an approved instrumented run supplies logs and target/platform details. Runtime, native compiler, packaging, VWHUD integration, and PS5 acceptance remain unrun for VWCANVAS-13.

## Cleanup

The read-only checks create no files. End the PowerShell session to discard its variables. The optional block creates a configuration file when absent and a timestamped log under .work/vwcanvas-13; retain review evidence and remove only files you created after inspecting their exact paths. Fixture suites also own other .work locations and may retain recovery material; follow the fixture output before removing any such directory. Do not delete the external VWHUD checkout, Canvas working files, staging junctions, unrelated reports, or pre-existing recovery output.

## Execution record

Executed: after correcting repeated prerequisite blocks found during review, the coordinator ran the five distinct read-only blocks against the clean pinned VWHUD checkout. The run passed Git-object link/anchor checks, full counts 14/10/18 with six overlaps, exact MIN sets and counts 10/7/14, coverage of all 18 provider rows, and README/changelog links and ownership checks. This evidence applies to the corrected documentation candidate on the VWCANVAS-13 working branch. The coordinator also ran pwsh -NoProfile -File .\Tools\verifyCanvas.ps1 -SourceOnly -EnvironmentPath .work\vwcanvas-13\validation.env with a nonsecret comment-only validation environment; it exited 0 and passed the five focused fixture suites. The optional source-only check creates ignored .work scratch and is separate from the read-only documentation checks.

Not run: external network fetching, native Papyrus or ActionScript compilation, package creation, deployment, Starfield gameplay, provider cadence instrumentation, null/replay/teardown tracing, VWHUD adapter integration, all-platform acceptance, and PS5 hardware acceptance. These require tools, game/runtime access, or separately approved instrumentation and are outside this docs-only change.
