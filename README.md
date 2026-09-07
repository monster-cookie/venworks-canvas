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

Dump and assembly are separate, explicit maintainer operations using the template Spriggit commands. Configure `TOOL_PATH_SPRIGGIT`, `SPRIGGIT_VERSION`, and `STEAM_DATA_FOLDER` in `.env`. The scripts use the existing variant definitions to map each staged ESM to `Spriggit/<ESM>/`, without a production-profile directory or generated-plugin baseline.

```powershell
# Serialize all configured staged ESMs to their per-ESM YAML directories.
.\Tools\SpriggitDumpDatabaseToYaml.ps1

# Update only the Example YAML, preserving the other ESM trees.
.\Tools\SpriggitDumpDatabaseToYaml.ps1 -VariantKeys EXAMPLE

# Explicitly assemble YAML back into the selected staged ESM.
.\Tools\SpriggitAssembleDatabaseFromYaml.ps1 -VariantKeys EXAMPLE
```

Assembly writes the selected ESM in staging, so run it only when that authoring change is intended. Neither packaging nor ordinary verification invokes dump or assembly automatically. `-EnvironmentPath` selects an alternate environment file; the former `-Profile` and `-PluginsDirectory` arguments are removed. Missing input ESMs or YAML directories are reported as skipped, and skipped entries are not counted as updated. A nonzero Spriggit exit stops the command. The wrappers do not perform whole-profile swaps or delete retained recovery backups; this does not promise transactional behavior inside Spriggit itself.

Normal authoring YAML lives directly beneath `Spriggit/`. The collision and missing-movie records under `Tests/Fixtures/Spriggit/Faults/` are isolated test data and are not a normal packaging profile.

## Registration and UI loading

Consumers supply a persistent UUID, display name, normal and large movie paths, and descriptor version. Canvas validates the UUID, normalizes accepted UUID forms to lowercase, and treats the normalized value as the stable registry key. Canvas does not generate an identity during registration. A mod author may explicitly use the Venworks Core UUID helper or any other UUID source, but must persist that identity rather than regenerate it on every load.

Registration and UI loading are intentionally separate calls:

1. The consumer calls `TryRegisterConsumer(...)` and retains the returned receipt.
2. Only an accepted, updated, or unchanged registration sets `UI_LOAD_REQUEST_NEEDED`.
3. Outside every guard, the consumer calls `TryRequestUiLoad(owner, consumerId)`.
4. Canvas queues and publishes one load command for that owner-checked registration.

This explicit second call is part of normal consumer startup; it is not a console-driven workflow. Registration does not itself publish to the UI bridge.

The registry initializes `Consumers` only when the saved array is `None`. Existing saved records are preserved. Same-owner descriptor changes update the stored record, while a different owner for the same UUID is rejected. Busy guards return distinct deferred receipts and never masquerade as success or invalid input.

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
2. `Tools/buildScaleform.ps1` builds the selected Canvas consumer movies and, for `CANVAS`, the Player HUD support movies and Ship HUD loader movies through the pinned VWHUD v2-derived toolchain.
3. `Tools/createPackages.ps1` validates the selected build inputs, snapshots the selected configured staging ESMs, creates uncompressed PC Main BA2 archives, and replaces only the exact child files under verified staging junctions.

Plugin authoring is separate from compilation and packaging. The normal package input is the ESM already present in each configured staging target. Packaging records and verifies that input's hash for the transaction; it does not require `.work/canvas/plugins/generation-evidence.json` or a prescribed production ESM hash. Make intended ESM edits through the normal authoring workflow, then rebuild and verify the affected package.

The checked build matrix pins the exact Venworks Core and VWHUD revisions and file hashes used for reproducible artifacts. Venworks Core 2.1.8 or newer is required at runtime.

From the repository root, replace the two example paths with your pinned dependency checkouts:

```powershell
$coreRepository = '<path-to-pinned-Core-checkout>'
$hudRepository = '<path-to-pinned-VWHUD-checkout>'

.\Tools\compileScripts.ps1 -VenworksCoreRepositoryPath $coreRepository
.\Tools\buildScaleform.ps1 -VwHudRepositoryPath $hudRepository
.\Tools\createPackages.ps1 -VenworksCoreRepositoryPath $coreRepository -VwHudRepositoryPath $hudRepository
```

Use `-VariantKeys CANVAS`, `-VariantKeys EXAMPLE`, or `-VariantKeys COMPONENTGALLERY` consistently across compile, Scaleform build, package, and verification commands to select a subset. An omitted variant list means all variants. Selected builds preserve unselected output files and retain only evidence that still matches its source, toolchain, and output. Stale unselected evidence is not relabeled as fresh. A consumer-only package does not require unrelated Player or Ship HUD build directories. A selected operation does not claim that unselected packages were rebuilt or checked against current source.

`createPackages.ps1` reads Archive2 and staging target paths from `.env`, rejects overlapping package targets, and verifies binary headers and exact BA2 inventories. It holds an exclusive process lock at `.work\canvas\package.lock` while preparing, installing, and recording a package transaction. Each run uses its own directory beneath `.work\canvas\package-transactions`, containing the staged ESM snapshots, archive payloads, candidate packages, and recovery copies. Before installation, it checks the selected inputs and candidate hashes again, then verifies each replacement against those same hashes.

Successful installation publishes one receipt per selected variant beneath `.work\canvas\package-receipts`. Verification checks the receipt's variant and package identity, build evidence, ESM input hash, installed ESM/BA2 hashes, and exact archive entry names and hashes. Existing artifacts without a matching receipt need a fresh package run before they can pass this verification. A valid file header alone is insufficient. Unselected receipts are not rewritten by a selected package operation; verification reports missing or stale provenance instead of treating those packages as freshly built.

For a handled installation or receipt-publication failure, recovery checks the original backup inventory and hashes, restores affected packages and prior receipts in reverse order, and verifies the restored bytes. It preserves the staging junctions throughout. Failed transactions retain their recovery directory and a `transaction.json` journal, and report whether restoration completed. A process or power interruption can bypass automatic recovery. A retained transaction directory stops the next package operation for manual inspection, even if the journal records completion but cleanup was interrupted. Do not delete recovery material blindly. The lock file can remain after a process exits; its presence alone does not mean another process still owns the lock.

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

Full artifact and deployed-staging validation:

```powershell
.\Tools\verifyCanvas.ps1 -VenworksCoreRepositoryPath $coreRepository -VwHudRepositoryPath $hudRepository
```

Use `-ArtifactsOnly` with the dependency paths to validate compiled artifacts without checking installed package receipts. Source-only validation runs isolated fixtures beneath `.work`, including actual Windows junction and process cases where supported; non-Windows runs report skipped junction cases explicitly. The tests use stubs where the game toolchain is unavailable, so they do not establish real Spriggit, Archive2, compiler, or Starfield behavior by themselves. Full verification checks the selected current source, pinned inputs, build evidence, ESM/BA2 signatures, hashes, archive inventories, and deployed child files; it does not establish Starfield runtime behavior.

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
8. Isolated fault fixtures: on a separately prepared disposable test installation, confirm a different-owner collision is rejected and a missing movie fails independently while valid consumers continue working. The fault YAML is test data, not a `-Profile Faults` production packaging option.

Capture the Papyrus log for each run. `REGISTRATION_ACK`, `UI_LOAD_QUEUED`, and `UI_LOAD_SUBMITTED` are intermediate evidence; the visible consumer `READY` state is required for UI acceptance.

## PC console diagnostics

These optional commands call functions explicitly declared `Global`. They use fully qualified Papyrus function names, never load-order prefixes, FormIDs, or quest display titles.

```text
cgf "Venworks:Canvas:Registry.ConsoleResolve"
cgf "Venworks:Canvas:Registry.ConsoleEnsureStorage"
cgf "Venworks:Canvas:ComponentGalleryRegistrar.ConsoleResolve"
cgf "Venworks:Canvas:ComponentGalleryRegistrar.ConsoleCheckUiLoadRequest" "beef70b2-024e-4e9b-a8d5-70a0c882c431"
help "VWCANVAS_ComponentGalleryRegistrar" 4 QUST
```

Canvas console functions print one final result through Venworks Core `ConsoleEcho` and also write bounded `VWCANVAS_CONSOLE/1` diagnostics. Visible echo requires the Starfield Papyrus debug logging configuration used by mod authors. Resolution proves only that the packaged global function found its permanent quest and attached script; it does not prove registration, bridge delivery, or rendering.

## Current limits

- The Watch presentation is deliberately disabled while its subscriptions remain available to Canvas.
- Ship HUD and pilot-seat delivery are not runtime accepted.
- PS5 work waits for the first player-facing HUD implementation and hardware-friendly test package.
- Consumer UI-data subscription metadata and host-to-child fanout remain separate lifecycle work.
- The Example's player-facing UTC/local time panel and the full component catalog remain follow-up implementation work.
