# Canvas consumer compatibility

This document explains how existing consumers coexist with the version 2 Canvas host and how maintainers should upgrade, roll back, and diagnose consumer compatibility. It complements the field-level [consumer descriptor contract](consumer-descriptor-contract.md).

## Compatibility matrix

| Component | Existing behavior | Version 2 behavior |
| --- | --- | --- |
| Saved native registration | `ConsumerRegistration` keeps the owner, UUID, display name, normal path, large path, and descriptor revision. | The saved shape remains unchanged; subscription and callback metadata belongs to the loaded movie lifetime. |
| UI-load request | Registration and UI loading are separate explicit operations using the five-field `VWC_EVT/1|canvas.ui.load|` packet. | The same registration and UI-load sequence is used. The descriptor revision must still match the loaded movie. |
| Loaded movie protocol | `VWCANVAS_CONSUMER/1` validates its protocol, normalized UUID, and integer descriptor revision, then supports loading and optional disposal; `assetNamespace` is ignored. | `VWCANVAS_CONSUMER/2` adds strict asset-namespace and API-range validation, bounded declarations, shared data/event routing, and fixed callbacks. |
| Host API | The current host recognizes the legacy protocol. | The current host selects API `2` when the declared range includes `2`. |
| Event transport | No version 1 consumer receives data or Canvas events. | `VWC_EVT/1|canvas.event|` carries one temporary Papyrus-origin event to exact ready topic subscribers. |
| Rollback state | Existing saved rows and descriptor values remain available to explicit callers. | Re-register the compatible prior descriptor and explicitly request its UI load; Canvas does not migrate saved metadata automatically. |

An older host that does not recognize `VWCANVAS_CONSUMER/2` cannot load a version 2 consumer as a negotiated consumer. Install a host containing the version 2 implementation with the updated consumer package. Existing version 1 movies remain the compatibility path for a host or package that has not adopted the new callbacks.

## Upgrade procedure

1. Keep the consumer's persistent UUID and the paired normal/large movie namespace stable unless the asset identity is intentionally changing.
2. Keep the native registration record and the explicit registration-then-UI-load sequence. The descriptor revision is the consumer asset/configuration revision; it is not the host API version.
3. Change the loaded movie declaration to `VWCANVAS_CONSUMER/2`, set numeric `minimumContractVersion` and `maximumContractVersion` values that include `2`, and set `version` to the descriptor revision registered by Papyrus.
4. Implement the fixed `handleUIData`, `handleCanvasEvent`, and `handleLifecycle` functions before requesting data or event delivery.
5. Request only exact approved UI channels and valid event topics. Preserve topic case consistently because declaration and routing comparisons are case-sensitive.
6. Build and install the Canvas host and consumer package together, then open the Player HUD and wait for the `ready` lifecycle state before expecting initial data or events.
7. Exercise both bundled consumers or an isolated consumer: confirm `READY V2`, confirm the requested data callback, publish a short event after UI loads settle, and confirm that an unrequested or case-different topic is not delivered.

The version 2 metadata is reconstructed each time the movie loads. It is not written into the saved native registration record, so reopening the HUD or reloading the movie repeats handshake validation and subscription setup.

## Explicit rollback

Rollback is a compatible package and explicit registration operation, not an automatic save migration.

1. Restore a consumer movie that matches the host: a version 1 declaration for the legacy load/dispose path or a version 2 declaration whose fields and callbacks satisfy API version 2.
2. Re-register the prior descriptor values with the same owning Quest and prior descriptor revision, or install the prior package whose descriptor matches the saved row.
3. Call `TryRequestUiLoad` explicitly after the accepted registration and allow the host to unload the current loader before loading the prior movie.
4. Reopen the Player HUD and verify the consumer's ready state and visible behavior in a disposable save.

Changing a descriptor revision or movie path causes the host to replace that consumer loader. A failed replacement does not promise that the previous movie remains loaded. Re-register and re-request the known compatible prior descriptor explicitly when restoring the previous revision.

## Isolation and failure behavior

Canvas validates each loaded movie independently. A missing movie, invalid descriptor, incompatible API range, invalid subscription declaration, missing fixed callback, unavailable provider, or failed channel subscription unloads that consumer and does not occupy a global consumer slot or prevent other consumers from becoming ready.

Data and event routing also isolate consumers. Canvas captures one exact provider callback per channel, takes a recipient snapshot for each dispatch, checks the loader identity and generation before invoking a callback, and catches a callback exception per recipient. Removing the final channel consumer invalidates its local subscription, callback identity, and retained snapshot before native `Unsubscribe`; a provider callback rechecks that exact identity after reading its payload and before retaining or dispatching the snapshot. Routing membership is removed before the unload lifecycle callback and `dispose()` call, so an obsolete consumer cannot receive later data or events. A synchronous callback that never returns cannot be interrupted by Canvas.

The loaded SWFs are compiled mod code trusted by this integration. Fixed callback names and exception containment prevent accidental cross-consumer routing and keep failures bounded, but they do not create a hostile-code sandbox, authenticate a publisher, or preempt arbitrary ActionScript.

## Event delivery and recovery limits

`EVENT_SUBMITTED` means that Canvas accepted the packet at the native submission site. It does not mean that a consumer received, displayed, or rendered the event. The shared Watch transport is one-way and lossy, with no UI acknowledgement, delivery receipt, event queue, retained event store, automatic retry, or replay after a HUD reload.

Use events for temporary notifications that can tolerate loss. The persistent registration record retains registration data only: owner, consumer identity, display name, movie paths, and descriptor revision. It does not persist subscription declarations, callback references, provider snapshots, named events, or other consumer lifecycle state. After a reload, a subscribed provider may replay its own latest snapshot when Canvas resubscribes, but that replay is provider data observed during resubscription rather than persisted consumer state. Busy, UI-pending, and rate-limited receipts may be retried by an explicit caller at an appropriate later point; invalid arguments, an inactive HUD, and an activation-cancelled reservation need a new valid attempt under the documented conditions.

UI loads and named events share one monotonic serial ticket space and one one-second native submission gate. A positive ticket owns pending UI pump work and can expire or be released after its bounded retry window; releasing positive ownership cannot clear a negative ticket. After a UI load or event is reserved, negative ownership survives native submission and activation cancellation until the matching one-second cleanup succeeds. Ordinary deferrals do not restart or replace that negative owner. A changed HUD activation may reschedule cleanup only for a matching completed ticket; exhausted cleanup remains fail-closed because no timestamp-based reclaim is safe.

Topic namespaces select recipients only. A valid publisher can submit another consumer's topic, and a namespace does not prove publisher identity. A topic is delivered only to ready consumers that declared the exact same case-sensitive string; an event sent before readiness or with no exact subscriber is discarded.

## Host and platform boundaries

The current Player HUD host restores the vanilla Watch data subscriptions and then disables Watch presentation and alert animation while retaining the shared data manager for Canvas. This is the data source used by the approved `uiChannels` catalog.

Ship HUD delivery and pilot-seat behavior are not accepted by this consumer contract. The current Canvas host defers the Ship HUD transport path, so a consumer should not use Player HUD data or event readiness as evidence of Ship HUD support. PS5 acceptance remains pending a player-facing HUD implementation and human hardware evidence.

The current VWHUD workload is represented by 18 distinct approved data channels across 24 request sites. The 32-consumer, 18-channel, 16-topic, 576-channel-membership, 512-topic-membership, and packet field limits are enforced Canvas boundaries. They are not measured performance ceilings and do not define HTML Engine rendering budgets; HTML numeric limits require separate implementation and measurement.

## Validation evidence and limits

The current evidence classes answer different questions and must be reported separately.

### Specification and manual acceptance vectors

Use the valid and invalid descriptor, handshake, event, lifecycle, subscription, timer, teardown, and rollback cases in the [consumer descriptor contract](consumer-descriptor-contract.md) as specification and review vectors. They define expected boundaries for implementation review or a manual test; they are not an executable Papyrus, ActionScript, Scaleform, Watch, timer, or Starfield runtime model.

### Repository source checks

`pwsh -NoProfile -File Tools/verifyCanvas.ps1 -SourceOnly` runs the configured source, setup, build-contract, and fixture checks, including [testUiLoad.ps1](../Tools/testUiLoad.ps1), [testUiReceive.ps1](../Tools/testUiReceive.ps1), and [testUuid.ps1](../Tools/testUuid.ps1). Run those three checks individually when isolating a result: `testUiLoad.ps1` inspects source and a translated UI lifecycle model, `testUiReceive.ps1` executes extracted receiver and subscription bodies in Node with provider fixtures, and `testUuid.ps1` checks UUID and source-level guard contracts. They do not execute the Papyrus VM, ActionScript in Scaleform, the Watch provider, native timers or event transport, or Starfield rendering, so a passing result is source or fixture evidence only.

### Language compiler, build, and package evidence

The actual-language and artifact steps are [compileScripts.ps1](../Tools/compileScripts.ps1), [buildScaleform.ps1](../Tools/buildScaleform.ps1), and [createPackages.ps1](../Tools/createPackages.ps1), with the required variant and tool arguments documented in the repository [build pipeline](../README.md#build-pipeline). With normal defaults, `compileScripts.ps1` publishes selected PEX files into each variant's verified `Staging-*\Scripts` tree, `buildScaleform.ps1` publishes mapped final SWF and GFX files into the corresponding `Staging-*\Interface` tree, and `createPackages.ps1` consumes those staged loose outputs together with the explicit staged ESM. `.work\canvas` holds temporary compiler, build, and package-recovery data. Explicit `-OutputDirectory`, `-ScriptsDirectory`, or `-ScaleformDirectory` values retain their alternative output or input behavior and must be matched across commands when an isolated directory is intentional. Successful Papyrus or ActionScript/Scaleform compilation confirms that the selected compiler accepted the sources and produced the selected artifacts. Successful packaging confirms the selected package transaction and configured outputs. These results do not establish Papyrus VM execution, callback delivery, Watch provider behavior, timer ownership, event delivery, package installation in the game, rendering, Ship HUD behavior, or PS5 acceptance.

### Player HUD manual acceptance

Use the exact packages under evaluation, a disposable save, and a current PC Player HUD run to establish runtime behavior. Capture both Papyrus diagnostics and visible panel behavior, and keep this evidence separate from source checks and compiler or packaging output.

1. Registration and UI load: register the consumer with its owning Quest, request UI loading explicitly, and confirm the accepted or queued receipt, the host `READY` diagnostic, and a visibly loaded movie for the selected normal or large path.
2. Timer and transition recovery: repeat UI-load and event attempts during the one-second submission gate, close and reopen the HUD around deferred reconciliation, and exercise a delayed or busy reset. UI work must retain priority, duplicate submissions must not occur, and a matching cleanup must permit the next attempt.
3. Shared subscriptions and provider replay: enable both bundled consumers, confirm both become ready and receive `PlayerData`, and reopen the HUD. The latest provider snapshot must arrive after each consumer becomes ready, including when the provider replays synchronously during subscription, while Watch presentation remains disabled.
4. Events and delivery loss: publish a requested topic only after consumers are ready and UI loads settle, confirm the exact ready subscribers receive the body, and confirm that pre-ready, unrequested, and case-different topics are discarded without replay after reload. Record that `EVENT_SUBMITTED` alone does not prove delivery or rendering.
5. Teardown and isolation: unload a consumer during or immediately after a shared data or event dispatch, then trigger another provider update and event. The removed consumer must receive nothing further, delayed callbacks for an invalidated channel callback must be ignored, and remaining current recipients must continue receiving updates.
6. Rollback: deliberately load an invalid or incompatible consumer package, confirm only that consumer unloads, then restore the known compatible descriptor and call registration followed by an explicit UI-load request. Verify the prior movie reaches `READY` without a stale queued request or duplicate native submission.

Report the exact command and result for the snapshot under review rather than inferring runtime success from source matching, translated models, compiler output, or package creation.
