# Venworks Canvas

Venworks Canvas is a Starfield Player HUD host and Papyrus registration layer for independently packaged Scaleform consumers. Compatible HUD add-ons can receive shared game UI data and named events published by Papyrus scripts.

## Packages

`Tools/sharedVariants.ps1` provides the reusable `ModuleVariant` model and selection helpers. `Tools/sharedConfig.ps1` is the Canvas-owned configuration entrypoint that loads the environment under the guarded session contract and publishes Canvas build values, variant definitions, staging paths, Papyrus namespaces, Scaleform jobs, and archive outputs. The shared executors in `Tools/sharedBuild.ps1`, `Tools/sharedScaleform.ps1`, and `Tools/sharedPackaging.ps1` provide the reusable behavior; this repository keeps the Canvas values and product-owned source and patch data.

| Variant | ESM | Papyrus namespace | Purpose | Staging root |
| --- | --- | --- | --- | --- |
| `CANVAS` | `Venworks-Canvas.esm` | `Venworks:Canvas` | Registry, Player HUD host, and shared transport | `Staging-Canvas` |
| `EXAMPLE` | `Venworks-Canvas-Example.esm` | `Venworks:CanvasExamples` | Minimal independently registered consumer | `Staging-Example` |
| `COMPONENTGALLERY` | `Venworks-Canvas-ComponentGallery.esm` | `Venworks:CanvasComponentGallery` | Independently registered component gallery | `Staging-ComponentGallery` |

Each `ModuleVariant` supplies `VariantKey`, `VariantName`, `EsmFileName`, `PackageBaseName`, `PapyrusNamespace`, `StagingFolderPath`, the `.env` variable name for the physical destination, and declarative `ScaleformBuilds` and `Archives` entries. `EsmFileName` is explicit and may differ from the archive base name. Papyrus ownership comes from the configured namespace directory, so new sources under that boundary enter the selected package automatically and similarly named sibling namespaces remain excluded.

Canvas Scaleform jobs identify the Flex or patch operation, its manifest or patch input, output set, and output filenames. Canvas archive entries declare the Main BA2 filename, format, compression, size limit, Papyrus inclusion, and exact Scaleform-to-archive mappings; the shared archiver does not impose a project-wide format or asset extension policy.

Each staging root must remain a Vortex junction. Packaging may replace the exact ESM and BA2 child files beneath a verified junction, but it must never delete, move, recreate, or retarget the junction itself.

After setup has configured a staging junction, the selected variant's `Staging-*\Scripts` and `Staging-*\Interface` trees are the normal loose-output and package-input roots. `.work\canvas` is reserved for temporary compiler, build, and package-recovery data. Normal compile and Scaleform build commands publish their selected outputs to staging automatically, so the workflow does not require a manual copy step.

## Local staging setup

Fresh-checkout staging preparation is a maintainer operation. A checkout contains ordinary tracked staging directories; these are suitable for inspecting committed artifacts, but are not an installation target. Configure the environment-variable names used by the selected `ModuleVariant` entries, including `MODULE_VARIANT_CANVAS_PATH`, `MODULE_VARIANT_EXAMPLE_PATH`, and `MODULE_VARIANT_COMPONENT_GALLERY_PATH`, in `.env` to point to the three distinct physical Vortex module folders.

Remove or relocate ordinary checkout staging directories and preserve any package files before running setup. `Tools/setupRepo.ps1` creates junctions only where the selected staging paths are absent, and accepts an existing junction only when its target matches the configuration. It checks the complete selection before creating any junction. It does not empty or migrate ordinary directories, restore files through Git, or repair incorrect links. The former `-MigrateExisting` option is removed.

Production entry points initialize `Tools/sharedConfig.ps1` through one guarded call per PowerShell session. The first successful initialization selects the requested `-EnvironmentPath`, and values from that file override inherited environment values. Later guarded calls reuse the initialized configuration; start a new `pwsh` process to select a different environment file. There is no skip flag or pure-configuration mode.

After preparing the paths and package contents, run these commands yourself from the repository root:

```powershell
.\Tools\setupRepo.ps1
.\Tools\checkRepo.ps1
```

Use `-VariantKeys CANVAS`, `EXAMPLE`, or `COMPONENTGALLERY` to check or set up only that variant. `Tools/checkRepo.ps1 -Committed` checks the committed package layout without requiring live junctions; it does not establish that a fresh checkout is ready for installation. Packaging performs its own junction and physical-target checks before preparing an installation.

## Spriggit authoring

Spriggit is an optional, developer-only authoring tool. It can run before build or gameplay tests to serialize selected staged ESMs to `Spriggit/<ESM>/` YAML and, when an authoring change is intended, assemble edited YAML back into the selected staged ESM. The wrappers route by each variant's explicit `EsmFileName`; they do not infer an ESM from an archive name. Starfield never executes Spriggit or reads YAML at runtime; runtime tests consume ESMs that a developer has already authored or assembled and placed in the configured staging target.

Configure `TOOL_PATH_SPRIGGIT`, `SPRIGGIT_VERSION`, and `STEAM_DATA_FOLDER` in `.env`; these settings are used only by the explicit authoring wrappers. The wrappers use the existing variant definitions to route each staged ESM to its own YAML directory.

```powershell
# Serialize all configured staged ESMs to their per-ESM YAML directories.
.\Tools\SpriggitDumpDatabaseToYaml.ps1

# Update only the Example YAML, preserving the other ESM trees.
.\Tools\SpriggitDumpDatabaseToYaml.ps1 -VariantKeys EXAMPLE

# Explicitly assemble YAML back into the selected staged ESM.
.\Tools\SpriggitAssembleDatabaseFromYaml.ps1 -VariantKeys EXAMPLE
```

Assembly writes the selected ESM in staging, so run it only when that authoring change is intended. Neither packaging, compilation, nor ordinary verification invokes dump or assembly automatically. `-EnvironmentPath` selects an alternate environment file; the former `-Profile` and `-PluginsDirectory` arguments are removed. Missing input ESMs or YAML directories are reported as skipped, and skipped entries are not counted as updated. A nonzero Spriggit exit stops the command. The wrappers do not perform whole-profile swaps or delete retained recovery backups; this does not promise transactional behavior inside Spriggit itself.

Authoring YAML lives directly beneath `Spriggit/`.

## Registration and UI loading

Consumers supply a persistent UUID, display name, normal and large movie paths, and descriptor version. Canvas validates the UUID, normalizes accepted UUID forms to lowercase, and treats the normalized value as the stable registry key. Canvas does not generate an identity during registration. A mod author may explicitly use the Venworks Core UUID helper or any other UUID source, but must persist that identity rather than regenerate it on every load.

Registration and UI loading are intentionally separate calls:

1. The consumer calls `TryRegisterConsumer(...)` and retains the returned receipt.
2. Only an accepted, updated, or unchanged registration sets `UI_LOAD_REQUEST_NEEDED`.
3. Outside every guard, the consumer calls `TryRequestUiLoad(owner, consumerId)`.
4. Canvas queues and publishes one load command for that owner-checked registration.

This explicit second call is part of normal consumer startup; it is not a console-driven workflow. Registration does not itself publish to the UI bridge.

The registry initializes `Consumers` only when the saved array is `None`. Existing saved records are preserved. Same-owner descriptor changes update the stored record, while a different owner for the same UUID is rejected. Busy guards return distinct deferred receipts and never masquerade as success or invalid input.

Child registrar scripts belong to their package namespaces. The Example registrar is authored under `Papyrus/Venworks/CanvasExamples/ExampleRegistrar.psc`, compiles to `Scripts/Venworks/CanvasExamples/ExampleRegistrar.pex`, and is archived only in the Example package; the Component Gallery registrar follows the corresponding `Papyrus/Venworks/CanvasComponentGallery/ComponentGalleryRegistrar.psc` and `Scripts/Venworks/CanvasComponentGallery/ComponentGalleryRegistrar.pex` paths. Both child registrars continue to call the shared `Venworks:Canvas:Registry` and `Venworks:Canvas:Base:BaseQuest` interfaces, which remain Canvas-owned.

Moving a Papyrus script changes its runtime script identity. Existing ESM script attachments and saved instances do not rebind automatically, so a maintainer must update or author the affected ESM bindings in Creation Kit or by explicitly assembling modified YAML with the new script names, recompile and repackage the child variant, and test with a new disposable save. Editor IDs, Form IDs, and ESM names remain unchanged; this workflow does not assemble into live staging, rewrite binary plugins, or migrate existing saves automatically.

`OnInit` installs menu callbacks only. Registration attempts and presentation reconciliation use bounded timers and nonblocking `TryLockGuard` sections. Logging, waits, scheduling, menu subscription changes, and the native UI bridge all remain outside acquired guards.

Requests made while a new HUD activation awaits reconciliation return a deferred result and use the existing bounded registrar retry path. The activation generation is checked again before reservation and dispatch. Obsolete unsent queue entries are discarded, so restoring a previous valid descriptor can request a load again. A real reservation still suppresses duplicate submission; these checks do not add delivery acknowledgements or automatic resend of a lost event.

## Consumer compatibility and subscriptions

Existing `VWCANVAS_CONSUMER/1` movies retain their loading and disposal behavior. Add-on authors opt into shared UI data and Canvas events through `VWCANVAS_CONSUMER/2`: the loaded movie declares a supported contract version range, requested `uiChannels`, and exact `eventTopics` in `getCanvasRegistration()`, then implements `handleUIData`, `handleCanvasEvent`, and `handleLifecycle`. This host selects contract version 2 when it falls within the declared range. An incompatible range or invalid declaration prevents that movie from becoming ready.

Canvas shares each requested game-data subscription across consumers and delivers updates only to the movies that requested that channel. Named events go only to ready movies subscribed to the exact topic; topic names are case-sensitive. Subscriptions end when a movie unloads and are recreated when it loads again. The host admits up to 32 version 2 consumers at once; each can request channels from the 18 supported names and up to 16 event topics. These are enforced limits, not measured performance targets.

Both bundled demonstration panels request `PlayerData` and `venworks.canvas.example.ping`. The Example displays lowercase `pong` when its event handler receives that exact topic and keeps the result visible through later player-data updates until the movie unloads. Component Gallery displays `EVENT` followed by the first 32 characters of the body; later player-data updates can replace its event marker. The Example's `ConsolePing` command publishes the custom event through Canvas for an explicit in-game check.

For a version 2 add-on, install a Canvas host that supports version 2 alongside the updated consumer package. The existing Papyrus registration record and UI-load request stay unchanged; the contract version is separate from the consumer's descriptor revision. This change adds no automatic package or save migration, and current-build save compatibility still needs gameplay validation. See the [consumer contract](docs/consumer-descriptor-contract.md) for declarations and publishing examples, and [consumer compatibility](docs/consumer-compatibility.md) for update and failure behavior.

The VWHUD provider inventory is maintained as a Plane page attached to [VWCANVAS-13](https://app.plane.so/venworks/projects/b9432d80-7966-48dd-86ea-f8eb5668bbd3/issues/3c75d048-9d58-4178-88cc-d94787ee62d4). The same work item contains the temporary testing handoff and runtime evidence gaps.

## Player HUD transport

The bridge carries explicit UI-load commands and named Canvas events. The UI-load packet remains `VWC_EVT/1|canvas.ui.load|` followed by five decimal-length-prefixed fields: protocol version, normalized consumer UUID, descriptor version, normal movie path, and large movie path. Canvas-owned struct-as-enum selectors choose the supported header and packet type so consumer code cannot supply arbitrary wire identifiers.

The Player HUD host restores the vanilla Watch data subscriptions, then disables Watch presentation before Canvas begins receiving bridge events. The Watch visual tree and alert animation entry points stay inactive while the shared data manager remains available. This prevents the high-volume Watch animation and responsiveness failures observed during development; it is not a general repair for the vanilla Watch implementation.

The Canvas package owns the vanilla Player HUD bootstrap patch for `hudmenu.swf`, `hudmenu.gfx`, `hudmenu_lrg.swf`, and `hudmenu_lrg.gfx`. Canvas can therefore initialize its host without a VWHUD runtime or build output. If another package replaces one of these files, the effective HUD behavior depends on package and load order; Canvas does not merge a foreign HUD replacement automatically.

The host validates each UI-load packet, selects the normal or large asset for the active HUD, and upserts the consumer by UUID. Each consumer loads into its own namespaced movie path. A missing or invalid consumer movie fails independently and cannot occupy a global slot or block another consumer.

The bridge is one-way and lossy. Submission is not delivery or render acknowledgement, and there is no UI-to-Papyrus reply channel. Reopening the Player HUD causes registered consumers to request their UI again. Ship HUD delivery, pilot-seat behavior, and PS5 acceptance remain outside the current PC gate.

Papyrus authors publish a named event with `TryPublishCanvasEvent(eventTopic, body)` on the Canvas registry and inspect its returned status. This makes one attempt; Canvas does not queue, retry, or retain the event for a later subscriber. UI loads take priority, and events share the existing one-second submission gate with them. Busy or rate-limited attempts return a deferred status; invalid arguments or an inactive HUD are rejected, and an activation change can cancel a reserved attempt. `EVENT_SUBMITTED` confirms only native submission.

Use a dotted topic such as `venworks.canvas.example.ping`; `canvas.` is reserved. Topics are 3–96 characters, bodies are 0–400 printable ASCII characters, and the complete packet must also fit within 512 characters, so the longest topic and body cannot always be combined. Topics identify recipients; they do not authenticate the publisher. Use events for temporary UI notifications that can tolerate loss.

## Build tooling setup

Maintainers must install the pinned Scaleform tools before building. Run `Tools/InstallPipelineTooling.ps1` in PowerShell 7 on Windows for this explicit setup step; ordinary build commands do not download or install dependencies. The pipeline needs a specific Eclipse Temurin Java version and flavor, plus the legacy Adobe Flex SDK's Player 11.1 `playerglobal.swc`, so an arbitrary system Java or newer SDK is not a substitute.

| Tool | Required version |
| --- | --- |
| Eclipse Temurin, Windows x64 HotSpot JDK | `21.0.12.1+1` |
| JPEXS Free Flash Decompiler | `26.2.1` |
| Apache Flex SDK | `4.16.1` |
| Adobe Flex SDK, used only for Player 11.1 `playerglobal.swc` | `4.6.0.23201B` |

Review the Adobe Flex SDK license before choosing `-AcceptAdobeLicense`. The installer requires that option when it needs to extract the Adobe artifact; an already verified matching playerglobal file can be reused without extraction. From the repository root, after accepting the license:

```powershell
.\Tools\InstallPipelineTooling.ps1 -AcceptAdobeLicense
.\Tools\VerifyPipelineTooling.ps1
```

Tools install beneath `.work\tools` by default, with downloads and temporary setup files beneath `.work\pipeline-tooling`. Setup verifies pinned archive sizes and SHA-256 checksums, checks selected installed files against their pins, and stages and checks replacements for missing or invalid components before installation. It runs the verifier automatically; rerun `VerifyPipelineTooling.ps1` separately whenever you need to check the tools. A successful check ends with `Pipeline tooling is ready.` Verification checks the installed tools; it does not build or package Canvas, supply the game's vanilla Interface files, or install the Papyrus compiler and Archive2.

To use a retained artifact cache, pass its directory with `-ArtifactCachePath`. The installer reads that directory without changing it, then uses its own local cache or downloads the pinned artifacts when needed. Add `-Offline` to forbid downloads:

```powershell
.\Tools\InstallPipelineTooling.ps1 -ArtifactCachePath '<path-to-artifact-cache>' -Offline -AcceptAdobeLicense
.\Tools\VerifyPipelineTooling.ps1
```

If an offline run reports a missing archive, place the named pinned archive in your cache and rerun, or rerun without `-Offline` when downloads are available. A checksum mismatch means the file cannot be used; obtain the matching artifact before trying again. `-ToolRoot` and `-WorkspaceRoot` override the installation and setup-work directories; use the same values when verifying. For a non-default tool root, also pass the resulting Java, JPEXS, and Flex paths explicitly to the build commands below.

## Build pipeline

The production build pipeline has three entry points backed by the reusable helpers in `Tools/sharedVariants.ps1`, `Tools/sharedBuild.ps1`, `Tools/sharedScaleform.ps1`, and `Tools/sharedPackaging.ps1`:

1. `Tools/compileScripts.ps1` selects variants, compiles every `.psc` file beneath each selected `PapyrusNamespace` directory, and publishes the selected PEX files into each variant's verified `Staging-*\Scripts` tree.
2. `Tools/buildScaleform.ps1` executes the selected declarative `ScaleformBuilds` jobs and publishes the mapped final SWF and GFX outputs into each variant's verified `Staging-*\Interface` tree, including configured normal and large consumer paths. Canvas-owned ActionScript, manifest, Watch, Ship, and UI protocol data remain in this repository.
3. `Tools/createPackages.ps1` validates the selected staged ESM and loose build inputs, creates the configured BA2 outputs, and replaces only the exact child files under verified staging junctions.

Plugin authoring is separate from compilation and packaging. The normal package input is the explicit ESM already present in each configured staging target. Make intended ESM edits in Creation Kit or another maintainer authoring workflow, place the authored ESM in staging, then compile and package the affected variant. Spriggit dump and assembly are optional, explicit developer commands for preparing or updating that ESM and are never invoked automatically.

Papyrus compilation imports the current installed sources from `PAPYRUS_SCRIPTS_SOURCE_PATH` together with this repository's `Papyrus` tree. The installed Venworks Core creation supplies its own runtime scripts; Canvas does not copy Core source or compiled runtime files into its packages. Namespace discovery uses the configured directory boundary, so a similarly prefixed namespace such as `Venworks:CanvasExamples` is not included in the `Venworks:Canvas` package.

From the repository root, select the variants you want to build. With no output overrides, `compileScripts.ps1` publishes selected PEX files into each variant's verified `Staging-*\Scripts` tree and `buildScaleform.ps1` publishes mapped final SWF and GFX files into that variant's verified `Staging-*\Interface` tree. `createPackages.ps1` consumes those staged loose outputs and the explicit staged ESM. `.work\canvas` remains the temporary compiler, build, and package-recovery workspace, so normal commands need no manual copy. Explicit `-OutputDirectory`, `-ScriptsDirectory`, or `-ScaleformDirectory` values retain their deliberate alternative output or input behavior and must be supplied consistently when a run intentionally uses them. `buildScaleform.ps1` uses directly configured Java, JPEXS, and Apache Flex paths, or their repository-local `.work/tools` defaults; when a selected Canvas job consumes vanilla HUD inputs, `-VanillaInterfacePath` must point to the current vanilla `Interface` inputs. Canvas does not clone a VWHUD checkout, invoke a VWHUD helper or compiler, or use VWHUD source, binaries, or build output as an input.

```powershell
$canvasToolArguments = @{
  VariantKeys = @('CANVAS', 'EXAMPLE', 'COMPONENTGALLERY')
  VanillaInterfacePath = '<path-to-current-vanilla-Interface>'
  JavaPath = '<path-to-java.exe>'
  JpexsJarPath = '<path-to-ffdec.jar>'
  FlexSdkPath = '<path-to-apache-flex-sdk>'
}

./Tools/compileScripts.ps1 -VariantKeys $canvasToolArguments.VariantKeys
./Tools/buildScaleform.ps1 -VariantKeys CANVAS -VanillaInterfacePath $canvasToolArguments.VanillaInterfacePath -JavaPath $canvasToolArguments.JavaPath -JpexsJarPath $canvasToolArguments.JpexsJarPath -FlexSdkPath $canvasToolArguments.FlexSdkPath
./Tools/buildScaleform.ps1 -VariantKeys EXAMPLE,COMPONENTGALLERY -JavaPath $canvasToolArguments.JavaPath -JpexsJarPath $canvasToolArguments.JpexsJarPath -FlexSdkPath $canvasToolArguments.FlexSdkPath
./Tools/createPackages.ps1 -VariantKeys $canvasToolArguments.VariantKeys
```

The VS Code `Build Scaleform` task prompts for the current vanilla Starfield interface directory (or a game root containing `Interface`) and passes it as `-VanillaInterfacePath`; it does not store a machine-specific path.

Use `-VariantKeys CANVAS`, `-VariantKeys EXAMPLE`, or `-VariantKeys COMPONENTGALLERY` consistently across compile, Scaleform build, package, and verification commands to select a subset. An omitted variant list means all variants. A consumer-only build does not require the Canvas Player or Ship HUD inputs. A selected operation does not claim that unselected packages were rebuilt or checked against current source.

`createPackages.ps1` reads Archive2 and staging target paths from `.env`, consumes the selected staged ESM and loose outputs, applies the selected `Archives` definitions, rejects overlapping package targets, and verifies the configured source and output files. It holds an exclusive process lock at `.work\canvas\package.lock` while preparing and installing a package transaction. Each run uses its own directory beneath `.work\canvas\package-transactions`, containing staged ESM snapshots, archive payloads, candidate packages, and recovery copies. Transient SHA-256 checks protect copies and replacements during that run; no external repository revision or binary hash is pinned.

Canvas `Archives` entries own the Canvas ESM and the configured archive payloads: the four Canvas PEX files and 11 Canvas-owned movie outputs consisting of the CanvasHost movie (`CanvasHost.swf`, archived as `Interface\venworkscui.swf`), the four vanilla Player HUD bootstrap files (`hudmenu.swf`, `hudmenu.gfx`, `hudmenu_lrg.swf`, and `hudmenu_lrg.gfx`), the four patched Player HUD Watch files (`playerhudcomponents.swf`, `playerhudcomponents.gfx`, `playerhudcomponents_lrg.swf`, and `playerhudcomponents_lrg.gfx`), and the two patched Ship HUD loader files (`spaceshiphudmenu.swf` and `spaceshiphudmenu_lrg.swf`). Example and Component Gallery own their PEX files and namespaced consumer movies, bringing the all-variant staged inventory to 15 movie outputs and 21 loose files. The installed Venworks Core creation supplies its own runtime scripts. Canvas builds and packages its own HUD bootstrap and does not copy, archive, invoke, or require VWHUD source, binaries, helpers, or build output. The intended dependency direction is one-way: VWHUD may build on Canvas, while Canvas does not depend on VWHUD. Packaging verifies the configured source and output files and publishes only the selected ESM and archive names beneath their verified junctions; unrelated staged asset directories and files remain untouched. Archive format, compression, filters, and size limits come from configuration rather than a global BA2 restriction, and the checks do not require evidence JSON, package receipts, Git history, or pinned hashes.

For a handled installation failure, recovery checks the original backup inventory, restores affected packages in reverse order, and verifies the restored bytes. It preserves the staging junctions throughout. Failed transactions retain their recovery directory for manual inspection. A process or power interruption can bypass automatic recovery. A retained transaction directory stops the next package operation until it is inspected. Do not delete recovery material blindly. The lock file can remain after a process exits; its presence alone does not mean another process still owns the lock.

## Validation

Source layout and local PowerShell tooling checks:

```powershell
.\Tools\verifyCanvas.ps1 -SourceOnly
```

Hosted CI runs this source-only verification and PowerShell lint only; it does not claim native Papyrus, Scaleform, Archive2, Spriggit, game, or platform acceptance.

The five individual tooling checks exercise the actual PowerShell setup, build-routing, patch/publication, and packaging helpers with isolated fixtures. They do not execute or model Papyrus or ActionScript lifecycle behavior:

```powershell
.\Tools\testPackaging.ps1
.\Tools\testBuildVariants.ps1
.\Tools\testBuildEvidence.ps1
.\Tools\testSetup.ps1
.\Tools\testScaleformSetup.ps1
```

Artifact validation:

```powershell
.\Tools\verifyCanvas.ps1 -ArtifactsOnly -VariantKeys CANVAS,EXAMPLE,COMPONENTGALLERY
```

Use `-ArtifactsOnly` with selected variants to run the repository checks and inspect the current staged Papyrus and Scaleform build inputs needed to plan the configured archives. This mode does not invoke Archive2, install packages, inspect the staging junctions, or establish installed-package or Starfield runtime behavior.

Source review and repository checks inspect code and build/setup behavior without running Canvas in Starfield. The local checks use isolated fixtures beneath `.work`, including Windows junction and process cases where supported; non-Windows runs report skipped junction cases explicitly. `testScaleformSetup.ps1` checks the installer with small fixture archives. Use `VerifyPipelineTooling.ps1` separately to check the pinned installed files and execute the real Java, Flex, and JPEXS tools.

The build commands above run the actual Papyrus and Flex compilers. Successful compilation confirms that those compilers accept the selected sources and produce output; it does not prove UI loading, callback delivery, save compatibility, or gameplay responsiveness. Confirm those behaviors with the in-game checks below using the exact packages being evaluated.

Prior user-supplied PC gameplay established registration, owner checking, bounded bridge behavior, and visible loading of both permanent-name consumer panels in normal Player HUD mode without renewed Watch lag. That acceptance predates the activation and stale-queue changes, version 2 subscriptions, named events, and Canvas-owned HUDMenu bootstrap patch described here. Repeat the affected disposable-save, HUD-transition, data, and event cases for the current build before claiming new runtime acceptance.

## PC runtime acceptance

Use the [VWCANVAS-10 testing guide](docs/vwcanvas-10-testing.md) for the current lifecycle change, exact installation prerequisites, copyable Example commands, expected results, cleanup, and the remaining diagnostic-consumer coverage. The cases below are an acceptance checklist, not recorded passes.

Deploy through Vortex, confirm all three permanent packages are enabled, and start with a new disposable save. Run these cases in order:

1. Canvas only: the host initializes, Watch presentation remains disabled, no consumer load is submitted, and gameplay remains responsive.
2. Canvas plus Example: registration is acknowledged, one UI load is queued/submitted, and the Example movie becomes visibly ready.
3. Canvas plus both consumers: both UUIDs register and both movies become visibly ready without static slots.
4. Save and reload: records remain unchanged and both consumers explicitly request and visibly restore their UI.
5. Reopen the Player HUD ten times: both consumers reappear without duplicate loaders, guard errors, Watch animation activity, or growing input lag.
6. Rapid HUD transitions: close and reopen the HUD before its deferred reconciliation completes, then repeat with a delayed or busy reset. Deferred requests must recover through bounded retries and both consumers must become ready without an old activation supplying a terminal duplicate receipt.
7. Descriptor changes: in an isolated test consumer, request v1, register v2 before the queued v1 is processed without requesting v2's UI, then register and explicitly request v1 again. The obsolete unsent entry must not suppress the final request. A repeated request after a real reservation must not create another submission.
8. Shared data: with both bundled consumers enabled, confirm both become ready and show `DATA PlayerData` when that provider sends data. Reopen the HUD and confirm both resume updates.
9. Example ping/pong: after the Example is visibly ready and UI loads have settled, run `cgf "Venworks:CanvasExamples:ExampleRegistrar.ConsolePing"`, close the console, and confirm the Example displays lowercase `pong`. Record the returned status: `EVENT_SUBMITTED` proves only native submission, so the visible `pong` is also required. If the attempt is deferred, let the pending UI work and cooldown finish before invoking the command again. Confirm later `PlayerData` updates do not erase `pong`. Reopen the HUD, verify the new Example movie has no `pong` before another ping, then invoke the command again and confirm the result returns. If Component Gallery is enabled, it also receives this topic and may briefly show its event-body marker.
10. Compatibility: with isolated test consumers, check that a legacy version 1 movie still loads, while an incompatible version 2 range or invalid subscription fails without stopping the other panels.

Capture the Papyrus log for each run. `REGISTRATION_ACK`, `UI_LOAD_QUEUED`, and `UI_LOAD_SUBMITTED` are intermediate evidence; confirm the host's `READY` diagnostic and a visibly loaded consumer panel for UI acceptance. The version 2 sample marker can change from `READY V2` to a data or event message immediately, so capture the relevant visible updates as well.

## PC console diagnostics

These optional commands call functions explicitly declared `Global`. They use fully qualified Papyrus function names, never load-order prefixes, FormIDs, or quest display titles.

```text
cgf "Venworks:Canvas:Registry.ConsoleResolve"
cgf "Venworks:Canvas:Registry.ConsoleEnsureStorage"
cgf "Venworks:CanvasComponentGallery:ComponentGalleryRegistrar.ConsoleResolve"
cgf "Venworks:CanvasComponentGallery:ComponentGalleryRegistrar.ConsoleCheckUiLoadRequest" "beef70b2-024e-4e9b-a8d5-70a0c882c431"
cgf "Venworks:CanvasExamples:ExampleRegistrar.ConsoleResolve"
cgf "Venworks:CanvasExamples:ExampleRegistrar.ConsolePing"
help "VWCANVAS_ComponentGalleryRegistrar" 4 QUST
```

Canvas console functions print one final result through Venworks Core `ConsoleEcho` and also write bounded `VWCANVAS_CONSOLE/1` diagnostics. Visible echo requires the Starfield Papyrus debug logging configuration used by mod authors. Resolution proves only that the packaged global function found its permanent quest and attached script; it does not prove registration, bridge delivery, or rendering.

`ExampleRegistrar.ConsolePing` makes one explicit publication attempt for `venworks.canvas.example.ping` using the Example's configured Canvas registry. Run it after the Example movie is visibly ready. It does not register the consumer, request its UI, or schedule retries. A missing Example quest/script reports `CONSOLE_RESOLVE_FAILED`; an unavailable registry or busy/inactive transport reports the actual unavailable, deferred, or rejected status. Only receiving the event changes the Example's display to `pong`.

## Current limits

- The Watch presentation is deliberately disabled while its subscriptions remain available to Canvas.
- Ship HUD and pilot-seat delivery are not runtime accepted.
- PS5 work waits for the first player-facing HUD implementation and hardware-friendly test package.
- Version 2 data subscriptions and named-event delivery still require current-build PC gameplay validation; source checks or compilation alone do not establish runtime acceptance.
- The Example's player-facing UTC/local time panel and the full component catalog remain follow-up implementation work.
