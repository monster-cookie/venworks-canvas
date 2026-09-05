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

## Player HUD transport

The current bridge carries only explicit UI-load commands. The wire packet is `VWC_EVT/1|canvas.ui.load|` followed by five decimal-length-prefixed fields: protocol version, normalized consumer UUID, descriptor version, normal movie path, and large movie path. Canvas-owned struct-as-enum selectors choose the supported header and packet type so consumer code cannot supply arbitrary wire identifiers.

The Player HUD host restores the vanilla Watch data subscriptions, then disables Watch presentation before Canvas begins receiving bridge events. The Watch visual tree and alert animation entry points stay inactive while the shared data manager remains available. This prevents the high-volume Watch animation and responsiveness failures observed during development; it is not a general repair for the vanilla Watch implementation.

The host validates each UI-load packet, selects the normal or large asset for the active HUD, and upserts the consumer by UUID. Each consumer loads into its own namespaced movie path. A missing or invalid consumer movie fails independently and cannot occupy a global slot or block another consumer.

The bridge is one-way and lossy. Submission is not delivery or render acknowledgement, and there is no UI-to-Papyrus reply channel. Reopening the Player HUD causes registered consumers to request their UI again. Ship HUD delivery, pilot-seat behavior, and PS5 acceptance remain outside the current PC gate.

## Build pipeline

The production build pipeline has three entry points:

1. `Tools/compileScripts.ps1` compiles the Papyrus sources declared by the selected variants.
2. `Tools/buildScaleform.ps1` builds the selected Canvas consumer movies and, for `CANVAS`, the Player HUD support movies and Ship HUD loader movies through the pinned VWHUD v2-derived toolchain.
3. `Tools/createPackages.ps1` validates all inputs, serializes the generated ESMs to reviewable Spriggit YAML, creates uncompressed PC Main BA2 archives, and swaps only the exact child files under verified staging junctions.

Plugin authoring is a separate maintainer operation. `createPackages.ps1` requires a complete generated plugin set plus `generation-evidence.json` in `.work/canvas/plugins`. Spriggit YAML is a review representation only and is never an assembly source. `Tools/SpriggitAssembleDatabaseFromYaml.ps1` remains available solely as a fail-closed guard against accidental assembly.

The checked build matrix pins the exact Venworks Core and VWHUD revisions and file hashes used for reproducible artifacts. Venworks Core 2.1.8 or newer is required at runtime.

From the repository root:

```powershell
$coreRepository = 'C:\Repositories\Venworks\starfield-venworks-core'
$hudRepository = 'C:\Repositories\Venworks\venworks-honkcore-ta-ui'

.\Tools\compileScripts.ps1 -VenworksCoreRepositoryPath $coreRepository
.\Tools\buildScaleform.ps1 -VwHudRepositoryPath $hudRepository
.\Tools\createPackages.ps1 -Profile Production -VenworksCoreRepositoryPath $coreRepository -VwHudRepositoryPath $hudRepository
```

Use `-VariantKeys CANVAS`, `-VariantKeys EXAMPLE`, or `-VariantKeys COMPONENTGALLERY` to select a subset. An omitted variant list means all variants. Unselected staging packages must already contain exactly their expected ESM and BA2 because full verification checks the complete deployed set.

`createPackages.ps1` reads Archive2 and staging target paths from `.env`, rejects overlapping package targets, verifies binary headers and exact BA2 inventories, and records hashes before replacing any deployed child file. A failed swap restores the prior child files without replacing the staging directory or junction.

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
.\Tools\testUiLoad.ps1
.\Tools\testUiReceive.ps1
.\Tools\testUuid.ps1
```

Full artifact and deployed-staging validation:

```powershell
.\Tools\verifyCanvas.ps1 -Profile Production -VenworksCoreRepositoryPath $coreRepository -VwHudRepositoryPath $hudRepository
```

These commands validate source contracts, pinned inputs, generated evidence, ESM/BA2 signatures, hashes, archive inventories, and deployed child files. They do not establish Starfield runtime behavior.

Prior PC gameplay established the registration, owner checking, bounded bridge path, and independent visible loading of two consumer movies without renewed Watch lag. Because this cleanup establishes the permanent plugin and package identities, a new disposable save created with the permanent names must repeat the Player HUD acceptance cases before runtime closure is claimed.

## PC runtime acceptance

Deploy through Vortex, confirm all three permanent packages are enabled, and start with a new disposable save. Run these cases in order:

1. Canvas only: the host initializes, Watch presentation remains disabled, no consumer load is submitted, and gameplay remains responsive.
2. Canvas plus Example: registration is acknowledged, one UI load is queued/submitted, and the Example movie becomes visibly ready.
3. Canvas plus both consumers: both UUIDs register and both movies become visibly ready without static slots.
4. Save and reload: records remain unchanged and both consumers explicitly request and visibly restore their UI.
5. Reopen the Player HUD ten times: both consumers reappear without duplicate loaders, guard errors, Watch animation activity, or growing input lag.
6. Fault profile: the different-owner collision is rejected and the missing movie fails independently while the valid consumers continue working.

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
