# VWCANVAS-10 Starfield testing guide

Use this guide to evaluate the consumer lifecycle changes with the exact candidate packages you intend to test. A successful PowerShell check or native compile does not establish that a panel loads, receives data, survives HUD recreation, or cleans up correctly in Starfield. The runtime steps in this guide have not been run for this change.

## Prepare the candidate

1. Record the candidate revision, any uncommitted changes, the native compiler results, and the exact package files used for the run. Build and package preparation follows [the README](../README.md#build-pipeline); inspect the actual build output before deployment. Do not substitute previously staged binaries for the candidate being evaluated.
2. Use a separate PC test profile with Starfield, Venworks Core Library 2.1.8 or higher, and a new disposable save. Preserve a pre-Canvas save and your normal mod profile. Enable the Papyrus debug logging configuration used by your existing mod-author setup; visible Canvas console echo depends on it. Record the game version and the normal or large HUD configuration used.
3. Prepare the following permanent package pairs through the existing Vortex workflow. Enable Core and Canvas for the baseline, then add Example, then Component Gallery. Record which files win any deployment conflict. Build scripts, packaging, Vortex deployment, and ESM authoring can change local installation state; this guide is a manual handoff, not authorization for an agent to perform those operations.

| Module | Plugin | Archive |
| --- | --- | --- |
| Canvas | `Venworks-Canvas.esm` | `Venworks-Canvas - Main.ba2` |
| Example | `Venworks-Canvas-Example.esm` | `Venworks-Canvas-Example - Main.ba2` |
| Component Gallery | `Venworks-Canvas-ComponentGallery.esm` | `Venworks-Canvas-ComponentGallery - Main.ba2` |

Canvas packages its host as `Interface\venworkscui.swf`. Example uses `Interface\VenworksCanvas\Consumers\venworks.canvas.example\normal.swf` and `large.swf`; Component Gallery uses the equivalent files under `venworks.canvas.component-gallery`. The current configuration maps each consumer's same compiled movie to its normal and large archive paths. Check both HUD configurations; two paths alone do not prove both were exercised.

## Run the bundled Example checks

1. Start the disposable save with Core and Canvas only. Confirm gameplay remains responsive and the Watch presentation and alert animation stay disabled. Capture any host diagnostics. No optional consumer panel should appear.
2. Exit the game, enable Example in the test profile, and start from the preserved pre-Canvas save. Open the console and run the commands below. `CONSOLE_RESOLVED` confirms each permanent quest/script binding only. Close the console and wait for the Example panel to load.

```text
cgf "Venworks:Canvas:Registry.ConsoleResolve"
cgf "Venworks:CanvasExamples:ExampleRegistrar.ConsoleResolve"
```

3. Capture the Papyrus `REGISTRATION_ACK`, `UI_LOAD_QUEUED`, and `UI_LOAD_SUBMITTED` diagnostics when emitted, and capture the host's `READY` diagnostic and visible Example panel. The Example UUID is `a8098c1a-f86e-4b1e-9d7c-5a102bf38460`. Intermediate registration or submission receipts are insufficient for a pass. The panel can change quickly from `READY V2` to `DATA PlayerData` when player data arrives; record the latter as evidence that a data callback reached this movie.
4. Once the Example is visibly ready and queued UI work has settled, open the console and run the ping command below. Close the console and require the panel to display lowercase `pong`. Record the returned status alongside the visible result. `EVENT_SUBMITTED` reports native submission only. If the result is deferred, allow pending work and cooldown to finish before making another explicit attempt; this command does not schedule a retry.

```text
cgf "Venworks:CanvasExamples:ExampleRegistrar.ConsolePing"
```

5. Continue playing and wait for further player-data activity. The Example must retain `pong`; later player-data callbacks must not overwrite it. The panel does not display a data counter, so this observation alone does not prove how many callbacks occurred.
6. Save in a new disposable slot, return to the main menu, and reload that slot. Require the Example panel to return and receive player data. Its new movie must start without the previous `pong`. Repeat the ping command and require a new `pong`.
7. Repeat the main-menu/reload cycle ten times, recording each result and whether input responsiveness degrades. This is a repeatable recreation check; an ordinary menu overlay is not proof that `HUDMenu` or the Canvas host was destroyed. For any faster HUD close/open sequence, retain evidence that the host was actually recreated before counting it as a lifecycle case.
8. Exit the game, enable Component Gallery as well, and repeat loading and ping from the preserved pre-Canvas save. Both consumer panels must load and receive `PlayerData`. The Gallery also subscribes to the Example topic and can show an event-body marker; only the Example is expected to retain `pong`. A problem with one panel must not prevent the other from continuing to receive its supported callbacks.
9. Repeat the applicable checks with the large HUD assets selected through your supported game configuration. Record the actual selected assets and observations. If you cannot establish which assets the game loaded, mark large-HUD coverage unverified.

If a binding reports `CONSOLE_RESOLVE_FAILED`, check the enabled permanent plugin and its packaged script before interpreting any UI result. If registration succeeds but the panel never appears, preserve the Papyrus log and visible host diagnostics, including `MISSING` or `INVALID` messages, and inspect the installed consumer movie paths. Repeating the ping cannot register or load a missing panel.

## Run the optional diagnostic movies

The VWCANVAS-14 subscriptions registry probe is packaged separately from the four fault-injection movies below. With the current Canvas and Example packages enabled, run `cgf "Venworks:CanvasExamples:ExampleRegistrar.ConsoleSubscriptionsProbe"`, close the console, and require the visible `PASS 5 / 5 | FAIL 0` and `ALL REGISTRY DIAGNOSTICS PASSED` marker. Then run `cgf "Venworks:CanvasExamples:ExampleRegistrar.ConsoleRestoreExample"` to restore the normal Example descriptor. The subscriptions probe uses a fake provider manager inside Scaleform and does not establish native Bethesda provider delivery.

Four test-only ActionScript movies are supplied under [Scaleform/canvas/diagnostics](../Scaleform/canvas/diagnostics). They execute as real consumers in Starfield and deliberately fail callbacks or dispatch bounded loader notifications. They are excluded from the production variants and packages. Their source and manifests are supplied; compiling or installing them is a separate step, and none of the game cases below has been run for this change.

| Manifest under `Scaleform/canvas/diagnostics/build` | Compiled movie | Purpose |
| --- | --- | --- |
| `callback-probe.build.xml` | `CanvasCallbackProbe.swf` | Counts callbacks, injects one duplicate INIT and COMPLETE, and alternates Error/string failures on data and event delivery. |
| `ready-failure-probe.build.xml` | `CanvasReadyFailureProbe.swf` | Throws a string from the ready callback. |
| `registration-failure-probe.build.xml` | `CanvasRegistrationFailureProbe.swf` | Throws a string from the first registration callback. |
| `complete-before-init-probe.build.xml` | `CanvasCompleteBeforeInitProbe.swf` | Injects COMPLETE during registration, before initialization has finished. |

Each movie reuses the Example UUID, namespace, descriptor version, `PlayerData` subscription, and ping topic. No additional plugin, Papyrus registrar, keyboard binding, or in-movie selector is required. Keep the existing Example plugin and Component Gallery enabled, and select exactly one probe movie per run.

### Build one diagnostic movie

From the repository root in a fresh PowerShell session, use the existing configured `.env` and replace the three tool-path placeholders below with the Java, JPEXS, and Flex paths verified by [the build-tool setup procedure](../README.md#build-tooling-setup). Select one manifest from the table. This calls the actual Flex/JPEXS build helper and writes the selected SWF under `.work\canvas\vwcanvas-10\probes`; it does not stage, package, or deploy it. A successful command is compiler/build evidence only.

```powershell
. .\Tools\sharedConfig.ps1
. .\Tools\sharedScaleform.ps1
. .\Tools\sharedPackaging.ps1

$probeManifest = '.\Scaleform\canvas\diagnostics\build\callback-probe.build.xml'
$probeDefinition = Get-BuildScaleformMovieDefinition -ManifestPath $probeManifest
$probeBuild = @{
  ManifestPath = $probeManifest
  OutputDirectory = Join-Path $PWD '.work\canvas\vwcanvas-10\probes'
  WorkDirectory = Join-Path $PWD ('.work\canvas\vwcanvas-10\probe-work\' + $probeDefinition.ClassName)
  JavaPath = '<path-to-java.exe>'
  JpexsJarPath = '<path-to-ffdec.jar>'
  FlexSdkPath = '<path-to-apache-flex-sdk>'
  ScaleformSourceRoot = Join-Path $PWD 'Scaleform\canvas'
  KeepWork = $true
}
Invoke-BuildScaleformMovieBuild @probeBuild
```

### Install one test override

The local VWCANVAS-10 handoff provides the following archives under `.work\canvas\vwcanvas-10\game-overrides`. They are ignored local artifacts, not production packages or files supplied by a fresh checkout; rebuild the selected source if they are unavailable. The candidate builds used the real Flex/JPEXS tools, and the archive movie paths and bytes were checked against those outputs. This is build/artifact evidence only; installation and Starfield execution remain unrun.

| Local archive | Movie files contained |
| --- | --- |
| `VWCANVAS-10-HostCandidate.zip` | `Interface\venworkscui.swf` |
| `VWCANVAS-10-CanvasCallbackProbe.zip` | Example `normal.swf` and `large.swf`, both from `CanvasCallbackProbe.swf` |
| `VWCANVAS-10-CanvasReadyFailureProbe.zip` | Example `normal.swf` and `large.swf`, both from `CanvasReadyFailureProbe.swf` |
| `VWCANVAS-10-CanvasRegistrationFailureProbe.zip` | Example `normal.swf` and `large.swf`, both from `CanvasRegistrationFailureProbe.swf` |
| `VWCANVAS-10-CanvasCompleteBeforeInitProbe.zip` | Example `normal.swf` and `large.swf`, both from `CanvasCompleteBeforeInitProbe.swf` |

1. Obtain the native-compiled movie matching the recorded candidate and manifest. With Starfield closed, create a separate disposable Vortex test override containing two identical copies of that movie at `Interface\VenworksCanvas\Consumers\venworks.canvas.example\normal.swf` and `Interface\VenworksCanvas\Consumers\venworks.canvas.example\large.swf`. Enable only this probe override and ensure it wins over the Example's two movie paths. Do not replace the Example plugin or alter the production package. If a prepared test overlay is provided, inspect that it contains exactly those two paths before enabling it.
2. Confirm the evaluated Canvas host also wins at `Interface\venworkscui.swf`. A host-only candidate overlay changes that movie alone; it still needs the existing Canvas package and its HUD bootstrap assets. Record the host and probe artifacts together so the new probe is not accidentally testing an older host.
3. Launch the disposable save with Canvas, Example, Gallery, and the selected probe. Repeat each probe in a separate launch. For all failure cases, require Gallery to remain usable: observe its player-data marker, invoke the existing Example ping after loading settles, and look for Gallery's `EVENT ping` marker. A failure probe's own marker is normally removed before becoming visible; use the host diagnostics for its result.

### Callback counts, duplicate notifications, and data/event failures

Use `CanvasCallbackProbe.swf`. Its visible heading is `VWCANVAS CALLBACK PROBE | TEST ONLY`; it replaces the normal Example panel and never displays `pong`.

1. Wait for loading to settle. Require `REG 1`, `READY 1`, `DUP INIT 1`, and `DUP COMPLETE 1` on the panel, plus the host's `READY` diagnostic for the Example UUID. The probe injects INIT once during registration and COMPLETE once during ready. Higher registration or ready counts fail the duplicate-admission check. The duplicate COMPLETE occurs after the host has removed its loader listeners, so this observation does not independently prove the completing-phase guard.
2. Wait for `PlayerData` delivery. Require `DATA` to increase and the host to report `UI DATA CALLBACK ERROR` for the Example UUID. Odd-numbered data callbacks throw an `Error`; even-numbered callbacks throw a string. At least two observed callbacks are needed to cover both inputs. If only one arrives, record string-data coverage as not run. Gallery must continue to receive player data.
3. Run the ping command below after UI loading and the transport cooldown settle, close the console, and record the visible `EVENT` count and the host's `EVENT CALLBACK ERROR` diagnostic. Make a second explicit ping attempt after the cooldown and require a second received event. The first received event throws an `Error`, the second a string. Count visible received events, not command attempts: a deferred or lost publication does not exercise the callback.

```text
cgf "Venworks:CanvasExamples:ExampleRegistrar.ConsolePing"
```

4. Continue observing later data or event counts. They must increase despite earlier failures; the probe remains eligible for delivery, and Gallery remains usable. This probe throws on every data/event callback, so increasing counts prove continued eligibility, not a later successful callback return. Canvas logs these failures rather than automatically removing this consumer.
5. Save in a disposable slot, return to the main menu, and reload it. Require fresh `REG 1` and `READY 1`, continued data/event delivery, and a healthy Gallery. During teardown, this probe throws an `Error` from unload and a string from dispose. Successful recreation is a smoke check for recovery through cleanup failures; the disappearing marker does not preserve unload/dispose counts or prove their exact order.

### Registration, ready, and ordering failures

Exit Starfield and replace the disposable override's two movie files with the next selected probe before each run. Require the corresponding host diagnostic for UUID `a8098c1a-f86e-4b1e-9d7c-5a102bf38460`, no successful host `READY` for that probe, and a healthy Gallery. Do not use the absence of a panel alone as proof that the intended fault executed.

| Movie | Automatic trigger | Expected host diagnostic |
| --- | --- | --- |
| `CanvasReadyFailureProbe.swf` | A string is thrown from ready after registration succeeds. | `INVALID <uuid> | READY CALLBACK | READY FAILURE PROBE STRING` |
| `CanvasRegistrationFailureProbe.swf` | A string is thrown from its first registration callback. | `INVALID <uuid> | REGISTRATION FAILURE PROBE STRING` |
| `CanvasCompleteBeforeInitProbe.swf` | One COMPLETE is dispatched during registration, while initialization is unfinished. | `INVALID <uuid> | missing initialized contract` |

The first case tests teardown after a failed ready callback; the latter two test rejection before readiness. The failing movies do not provide persistent callback logs, so these observations establish rejection and healthy-consumer continuity, not precise teardown counts. `CanvasCompleteBeforeInitProbe` tests completion during initialization, not a delayed old-loader completion after replacement. Repeat the applicable runs with the normal and large HUD assets selected in separate configurations, recording which files actually loaded.

## Lifecycle coverage still requiring additional controls

The probes supply concrete fault triggers, but do not provide a general lifecycle harness or access to private host methods. These deeper cases remain unrun and cannot be established from the supplied panels alone:

| Case | Missing observation or control |
| --- | --- |
| Exact ready/data replay order | Persistent per-instance callback traces that distinguish retained replay from a later live update. The displayed counters alone do not record this sequence. |
| Removal or replacement during data/event handling | A separately reviewed test-only trigger for same-host removal/replacement. Public consumer callbacks do not provide a host removal method. |
| Exact unload/dispose counts and post-removal delivery | A persistent observer that survives the disappearing marker. The probe's visible teardown counters vanish when it is removed. |
| Late old-loader completion/error after replacement | A controlled delayed loader and known replacement instance. Rapid reloads alone do not guarantee this ordering. |
| Independent completing-phase guard | A reviewed trigger that reaches this guard independently of listener removal; the supplied duplicate COMPLETE normally encounters already-removed listeners. |
| Separate cleanup-failure cases | Independent unload-only and dispose-only faults. The callback probe currently triggers both during the same teardown. |

Record the diagnostic source, compiled movie, triggering action, instance identity where observable, diagnostics, and result. Do not report passes from a translated script, simulated lifecycle, source-pattern check, or an unobserved ordering. A VWHUD Canvas adapter is not available in the inspected VWHUD source, so these checks do not establish VWHUD integration. Ship HUD/pilot-seat behavior and PS5 acceptance remain separate, unrun platform checks.

## Local verification and result record

Run the source/tooling verification from the repository root in PowerShell:

```powershell
.\Tools\verifyCanvas.ps1 -SourceOnly
```

This runs source-layout checks and five actual PowerShell tooling checks: packaging, build variants, Scaleform patch/publication helpers, staging setup, and Scaleform tool setup. It does not execute or model Papyrus or ActionScript. The real Papyrus and Flex compiler commands in the README establish compiler acceptance only. Artifact verification establishes its documented staged-input checks only; it does not establish that the game loaded those files.

Record each check as passed, failed, or not run, including the candidate, command or manual action, configuration, result, and log/screenshot location. Preserve separate results for tooling, native compilation, packaging, common-path PC gameplay, diagnostic lifecycle boundaries, normal/large HUD assets, Ship HUD, PS5, and VWHUD integration. No runtime or platform pass is recorded by this guide.

## Cleanup

Exit Starfield. Disable and remove only the disposable probe and host-candidate overrides created for this test, and restore the prior test-profile enablement and deployment through Vortex. Verify that the original Example movie wins again at both normal and large paths before running its ordinary `pong` check. Keep the disposable saves and captured logs only as long as needed for diagnosis, then use the preserved pre-Canvas save or your untouched normal profile. Do not continue a normal playthrough from a test save after changing or removing these packages. Preserve build or package recovery directories until any failed operation has been inspected; do not delete staging junctions or recovery material as a test cleanup shortcut.
