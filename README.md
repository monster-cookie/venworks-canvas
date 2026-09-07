# Venworks Canvas

Venworks Canvas is a Starfield Player HUD host and Papyrus registration layer for independently packaged Scaleform consumers.

## Packages

`Tools/sharedConfig.ps1` is the only source of truth for package variants, staging paths, Papyrus ownership, Scaleform manifests, output names, UI namespaces, and Player/Ship HUD inclusion.

| Variant | Plugin | Purpose | Staging root |
| --- | --- | --- | --- |
| `CANVAS` | `Venworks-Canvas.esm` | Registry, Player HUD host, and shared transport | `Staging-Canvas` |
| `EXAMPLE` | `Venworks-Canvas-Example.esm` | Minimal independently registered consumer | `Staging-Example` |
| `COMPONENTGALLERY` | `Venworks-Canvas-ComponentGallery.esm` | Independently registered component gallery | `Staging-ComponentGallery` |

Each staging root must remain a Vortex junction. Packaging may replace the exact ESM and BA2 child files beneath a verified junction, but it must never delete, move, recreate, or retarget the junction itself.

## Local staging setup

Fresh-checkout staging preparation is a maintainer operation. A checkout contains ordinary tracked staging directories; these are suitable for inspecting committed artifacts, but are not an installation target. Configure `MODULE_VARIANT_CANVAS_PATH`, `MODULE_VARIANT_EXAMPLE_PATH`, and `MODULE_VARIANT_COMPONENT_GALLERY_PATH` in `.env` to point to the three distinct physical Vortex module folders.

Preserve the existing package files and prepare the repository staging paths yourself before running setup. `Tools/setupRepo.ps1` creates junctions only where the selected staging paths are absent, and accepts an existing junction only when its target matches the configuration. It checks the complete selection before creating any junction. It does not empty or migrate ordinary directories, restore files through Git, or repair incorrect links. The former `-MigrateExisting` option is removed.

After preparing the paths and package contents, run these commands yourself from the repository root:

```powershell
.\Tools\setupRepo.ps1
.\Tools\checkRepo.ps1
```

Use `-VariantKeys CANVAS`, `EXAMPLE`, or `COMPONENTGALLERY` to check or set up only that variant. `Tools/checkRepo.ps1 -Committed` checks the committed package layout without requiring live junctions; it does not establish that a fresh checkout is ready for installation. Packaging performs its own junction and physical-target checks before preparing an installation.

## Spriggit authoring

Spriggit is an optional, developer-only authoring tool. It can run before build or gameplay tests to serialize selected staged ESMs to `Spriggit/<ESM>/` YAML and, when an authoring change is intended, assemble edited YAML back into the selected staged ESM. Starfield never executes Spriggit or reads YAML at runtime; runtime tests consume ESMs that a developer has already authored or assembled and placed in the configured staging target.

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

Normal authoring YAML lives directly beneath `Spriggit/`. Before running the collision and missing-movie runtime case, prepare the fault fixture from `Tests/Fixtures/Spriggit/Faults/` as developer test data and assemble the resulting ESM into the disposable staging target; the fixture is never a runtime Spriggit input or a normal packaging profile.

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

## Player HUD transport

The current bridge carries only explicit UI-load commands. The wire packet is `VWC_EVT/1|canvas.ui.load|` followed by five decimal-length-prefixed fields: protocol version, normalized consumer UUID, descriptor version, normal movie path, and large movie path. Canvas-owned struct-as-enum selectors choose the supported header and packet type so consumer code cannot supply arbitrary wire identifiers.

The Player HUD host restores the vanilla Watch data subscriptions, then disables Watch presentation before Canvas begins receiving bridge events. The Watch visual tree and alert animation entry points stay inactive while the shared data manager remains available. This prevents the high-volume Watch animation and responsiveness failures observed during development; it is not a general repair for the vanilla Watch implementation.

The host validates each UI-load packet, selects the normal or large asset for the active HUD, and upserts the consumer by UUID. Each consumer loads into its own namespaced movie path. A missing or invalid consumer movie fails independently and cannot occupy a global slot or block another consumer.

The bridge is one-way and lossy. Submission is not delivery or render acknowledgement, and there is no UI-to-Papyrus reply channel. Reopening the Player HUD causes registered consumers to request their UI again. Ship HUD delivery, pilot-seat behavior, and PS5 acceptance remain outside the current PC gate.

## Build pipeline

The production build pipeline has three entry points:

1. `Tools/compileScripts.ps1` compiles the Papyrus sources declared by the selected variants.
2. `Tools/buildScaleform.ps1` builds the selected Canvas consumer movies and, for `CANVAS`, applies the repository-owned Watch and Ship patches to the current vanilla interface inputs.
3. `Tools/createPackages.ps1` validates the selected build inputs, snapshots the selected configured staging ESMs, creates uncompressed PC Main BA2 archives, and replaces only the exact child files under verified staging junctions.

Plugin authoring is separate from compilation and packaging. The normal package input is the ESM already present in each configured staging target. Make intended ESM edits in Creation Kit or another maintainer authoring workflow, place the authored ESM in staging, then compile and package the affected variant. Spriggit dump and assembly are optional, explicit developer commands for preparing or updating that ESM and are never invoked automatically.

Papyrus compilation imports the current installed sources from `PAPYRUS_SCRIPTS_SOURCE_PATH` together with this repository's `Papyrus` tree. The installed Venworks Core creation supplies its own runtime scripts; Canvas does not copy Core source or compiled runtime files into its packages.

From the repository root, select the variants you want to build. `compileScripts.ps1` uses the configured installed Papyrus source path and the Canvas source tree. `buildScaleform.ps1` uses directly configured Java, JPEXS, and Apache Flex paths, or their repository-local `.work/tools` defaults; when `CANVAS` is selected, `-VanillaInterfacePath` must point to the current vanilla `Interface` inputs. Canvas does not clone a VWHUD checkout, invoke a VWHUD helper or compiler, or use a foreign cache or source tree.

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

Use `-VariantKeys CANVAS`, `-VariantKeys EXAMPLE`, or `-VariantKeys COMPONENTGALLERY` consistently across compile, Scaleform build, package, and verification commands to select a subset. An omitted variant list means all variants. A consumer-only build does not require the Canvas Player or Ship HUD inputs. A selected operation does not claim that unselected packages were rebuilt or checked against current source.

`createPackages.ps1` reads Archive2 and staging target paths from `.env`, rejects overlapping package targets, and verifies binary headers and exact BA2 inventories. It holds an exclusive process lock at `.work\canvas\package.lock` while preparing and installing a package transaction. Each run uses its own directory beneath `.work\canvas\package-transactions`, containing staged ESM snapshots, archive payloads, candidate packages, and recovery copies. Transient SHA-256 checks protect copies and replacements during that run; no external repository revision or binary hash is pinned.

Canvas packaging owns the four Canvas PEX files and the CanvasHost movie (`CanvasHost.swf`, archived as `Interface\venworkscui.swf`), the four patched Player HUD Watch files (`playerhudcomponents.swf`, `playerhudcomponents.gfx`, `playerhudcomponents_lrg.swf`, and `playerhudcomponents_lrg.gfx`), and the two patched Ship HUD loader files (`spaceshiphudmenu.swf` and `spaceshiphudmenu_lrg.swf`). Example and Component Gallery own their PEX files and namespaced consumer movies. The installed Venworks Core and VWHUD creations supply their own runtime files; Canvas does not copy, archive, or repackage foreign code. Verification checks the selected files, package headers, and exact archive entries directly and does not require evidence JSON, package receipts, Git history, or pinned hashes.

For a handled installation failure, recovery checks the original backup inventory, restores affected packages in reverse order, and verifies the restored bytes. It preserves the staging junctions throughout. Failed transactions retain their recovery directory for manual inspection. A process or power interruption can bypass automatic recovery. A retained transaction directory stops the next package operation until it is inspected. Do not delete recovery material blindly. The lock file can remain after a process exits; its presence alone does not mean another process still owns the lock.

## Validation

Source-only validation, including all source-contract tests:

```powershell
.\Tools\verifyCanvas.ps1 -SourceOnly
```

Individual contract tests:

```powershell
.\Tools\testConsole.ps1
.\Tools\testGuards.ps1
.\Tools\testPackaging.ps1
.\Tools\testBuildEvidence.ps1
.\Tools\testBuildVariants.ps1
.\Tools\testSpriggit.ps1
.\Tools\testSetup.ps1
.\Tools\testUiLoad.ps1
.\Tools\testUiReceive.ps1
.\Tools\testUuid.ps1
```

Artifact validation:

```powershell
.\Tools\verifyCanvas.ps1 -ArtifactsOnly -VariantKeys CANVAS,EXAMPLE,COMPONENTGALLERY
```

Use `-ArtifactsOnly` with selected variants to validate built files and package payloads directly. Source-only validation runs isolated fixtures beneath `.work`, including actual Windows junction and process cases where supported; non-Windows runs report skipped junction cases explicitly. The tests use stubs where the game toolchain is unavailable, so they do not establish real Spriggit, Archive2, Papyrus compiler, Scaleform compiler, or Starfield behavior by themselves. Artifact verification checks the selected current sources and outputs, ESM/BA2 signatures, and archive inventories; it does not require external checkouts, evidence JSON, package receipts, Git history, or pinned hashes, and it does not establish Starfield runtime behavior.

Prior user-supplied PC gameplay established registration, owner checking, bounded bridge behavior, and visible loading of both permanent-name consumer panels in normal Player HUD mode without renewed Watch lag. That acceptance predates the activation and stale-queue changes described here. Repeat the affected disposable-save and HUD-transition cases for the current build before claiming new runtime acceptance.

## PC runtime acceptance

Deploy through Vortex, confirm all three permanent packages are enabled, and start with a new disposable save. Run these cases in order:

1. Canvas only: the host initializes, Watch presentation remains disabled, no consumer load is submitted, and gameplay remains responsive.
2. Canvas plus Example: registration is acknowledged, one UI load is queued/submitted, and the Example movie becomes visibly ready.
3. Canvas plus both consumers: both UUIDs register and both movies become visibly ready without static slots.
4. Save and reload: records remain unchanged and both consumers explicitly request and visibly restore their UI.
5. Reopen the Player HUD ten times: both consumers reappear without duplicate loaders, guard errors, Watch animation activity, or growing input lag.
6. Rapid HUD transitions: close and reopen the HUD before its deferred reconciliation completes, then repeat with a delayed or busy reset. Deferred requests must recover through bounded retries and both consumers must become ready without an old activation supplying a terminal duplicate receipt.
7. Descriptor changes: in an isolated test consumer, request v1, register v2 before the queued v1 is processed without requesting v2's UI, then register and explicitly request v1 again. The obsolete unsent entry must not suppress the final request. A repeated request after a real reservation must not create another submission.
8. Isolated fault fixtures: on a separately prepared disposable test installation, assemble the fault YAML into the staged ESMs before launching Starfield, then confirm that a different-owner collision is rejected and a missing movie fails independently while valid consumers continue working. The fault YAML is developer test data, not a `-Profile Faults` production packaging option or a runtime input.

Capture the Papyrus log for each run. `REGISTRATION_ACK`, `UI_LOAD_QUEUED`, and `UI_LOAD_SUBMITTED` are intermediate evidence; the visible consumer `READY` state is required for UI acceptance.

## PC console diagnostics

These optional commands call functions explicitly declared `Global`. They use fully qualified Papyrus function names, never load-order prefixes, FormIDs, or quest display titles.

```text
cgf "Venworks:Canvas:Registry.ConsoleResolve"
cgf "Venworks:Canvas:Registry.ConsoleEnsureStorage"
cgf "Venworks:CanvasComponentGallery:ComponentGalleryRegistrar.ConsoleResolve"
cgf "Venworks:CanvasComponentGallery:ComponentGalleryRegistrar.ConsoleCheckUiLoadRequest" "beef70b2-024e-4e9b-a8d5-70a0c882c431"
help "VWCANVAS_ComponentGalleryRegistrar" 4 QUST
```

Canvas console functions print one final result through Venworks Core `ConsoleEcho` and also write bounded `VWCANVAS_CONSOLE/1` diagnostics. Visible echo requires the Starfield Papyrus debug logging configuration used by mod authors. Resolution proves only that the packaged global function found its permanent quest and attached script; it does not prove registration, bridge delivery, or rendering.

## Current limits

- The Watch presentation is deliberately disabled while its subscriptions remain available to Canvas.
- Ship HUD and pilot-seat delivery are not runtime accepted.
- PS5 work waits for the first player-facing HUD implementation and hardware-friendly test package.
- Consumer UI-data subscription metadata and host-to-child fanout remain separate lifecycle work.
- The Example's player-facing UTC/local time panel and the full component catalog remain follow-up implementation work.
