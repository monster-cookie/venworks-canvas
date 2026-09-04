# venworks-canvas
BGS Scaleform HTML and CSS Engine along with a papyrus data layer. 

## VWCANVAS-9: explicit consumer UI-loading PC test

Registration remains entirely Papyrus-side. A consumer first registers its persistent UUID and descriptor, checks the result, then explicitly calls `TryRequestUiLoad(owner, consumerId)` when ready. Registration itself never queues or publishes UI work. The demo registrars make these two calls in sequence during normal startup, without console commands. The Player HUD overlay identifies `EXPLICIT UI LOAD TEST`; actual A/B panels and `READY` diagnostics, not the banner, establish visible loading.

`TryRegisterConsumer()` returns a caller-owned Papyrus receipt after one nonblocking attempt. `REGISTRATION_ACCEPTED`, `REGISTRATION_UPDATED`, and `REGISTRATION_UNCHANGED` acknowledge stored state; `DEFERRED_REGISTRY_BUSY` is neither acceptance nor rejection. The legacy `RegisterConsumer()` Boolean wrapper remains available, but false now includes contention: new consumers must use the explicit receipt. No acknowledgement establishes UI readiness.

`OnInit` only installs menu callbacks. A supported HUD opening schedules timer-driven reconciliation; it does not resume a waiting `OnInit` stack. Registrars try `AttemptGuard`, then the host tries `RegistryGuard`; neither waits for acquisition. Retry delays, subscriptions and logging run outside both guards. Each deferred sequence has at most 20 attempts at half-second retry intervals, with exhaustion logged and pending data retained for a later event. Overlapping events may create overlapping bounded sequences; no fairness or native-timer ordering guarantee is claimed. The old saved `RegistrationAttemptActive` flag is not consulted as a lock or scheduling gate.

An acquired registrar guard stores a complete pending update before calling the host. Busy/unavailable host results retain it; only acceptance commits active descriptor fields, while terminal rejection clears that submitted pending request. If the registrar guard itself is busy, the input has **not** been stored: the caller must retain and resubmit it. The UpdatedA migration quest does this from its persistent VMAD descriptor until an explicit registration acknowledgement. Known legacy rekey and registration share one host transaction, so busy cannot be misread as an invalid UUID or skipped migration.

The explicit second step obtains paths and version from the owner-checked registered descriptor. It returns `UI_LOAD_QUEUED`, `UI_LOAD_ALREADY_REQUESTED`, a `REJECTED_*` reason, or a distinct `DEFERRED_*` result. Queuing is not submission; `UI_LOAD_SUBMITTED` is logged only after the native call returns and is not delivery or rendering acknowledgement. `CheckUiLoadRequest` / `TryCheckUiLoadRequest` are separate non-transmitting diagnostics and return `REGISTERED_UI_LOAD_ELIGIBLE` for a valid owner/UUID pair. Expected negative registration fixtures never request UI loads. A deferred load never undoes an accepted descriptor update.

### Load-only transport and presentation state

The only active bridge packet is one ASCII envelope: `VWC_EVT/1|canvas.ui.load|` followed by five decimal-length-prefixed fields in this order: protocol `1`, normalized consumer UUID, descriptor version, normal movie path, and large movie path. Each field is encoded as `<length>:<value>`; the complete packet is limited to 512 characters. The old registry snapshot and diagnostic publishers and their host ingress remain disabled.

Pending work is capped at 32 requests, not 32 registrations. Requests coalesce by UUID; identical owner/descriptor requests are suppressed during the current Player HUD activation. A ticketed pump reserves one request under a nonblocking guard, rechecks its registered owner and descriptor, then invokes the native bridge outside every guard. The next submission is scheduled at least one second after completing the preceding submission path. Local contention retries stop after 20 attempts. Completion retries never invoke the native bridge again. Expiring timer tickets and activation reset prevent saved scheduling state from permanently suppressing future requests.

A new observed Player HUD activation resets only presentation bookkeeping. The demos reconcile registration and explicitly request loading again, including when registration returns `REGISTRATION_UNCHANGED`. It does not reset `Consumers` or an acknowledged descriptor update. Queued work is not a durable delivery promise; a missed event is not automatically retransmitted for lack of acknowledgement. Invalidated timer tickets are inert. The new transient structs/fields may be serialized by Papyrus, so they are explicitly reset on the HUD callback rather than assumed to disappear on save/reload.

The Player HUD owns one `CustomAlertsData` subscription, primes the provider, validates load commands, selects normal/large assets, and upserts only the named consumer. Repeated identical loads do not create duplicate loaders. Loader failures and stale callbacks are isolated, and disposal removes owned loaders/listeners/subscriptions. The ship host deliberately reports `SHIP UI TRANSPORT DEFERRED` and does not subscribe in this phase.

The vanilla watch is not disabled or repaired. Low-frequency load events still use its shared, lossy transport; cached provider data, HUD-startup timing, in-flight menu transitions, another mod consuming the channel, and watch animation side effects remain runtime risks. UUID/owner checks are Papyrus API checks, not authentication of an arbitrary packet from another mod. No UI-to-Papyrus reply channel, guaranteed ordering/delivery, or production compatibility is claimed.

### Build and packaging

Use released Venworks Core **2.1.6** with the additional pinned console diagnostic scripts bundled in the Canvas Host BA2, and the VWHUD-v2-derived toolchain declared in `Scaleform/probes/consumer-discovery/probe-matrix.psd1`. Rebuilding requires Core fixture commit `fce6fadcb110f8a462c41680a1147d3c36e8421f` (VWCORE-5), with eight pinned source/runtime pairs. Compared with the preceding Canvas pin, only the Console source/runtime pair changed to the user-tested `RM>` prefix; the other seven pinned pairs are unchanged. This diagnostic bundle is not a new Core release. Core's ESM, release archives, and version metadata are unchanged. The profile ESMs bind fixed UUIDs and were generated with Mutagen, then independently serialized with Spriggit. The generator and `.work` build inputs are local scratch, not supplied by a fresh checkout; use materialized committed Baseline packages to deploy, or the matching verified profile ESM inputs when rebuilding. The deployable payloads are the ESM and matching BA2 in each of `Staging-Host`, `Staging-ConsumerA`, and `Staging-ConsumerB`.

The Host diagnostic archive includes eight pinned Core PEX dependencies: its existing six, plus `Utilities/Console` and `Tests/ConsoleOutputTests`. This is a diagnostic dependency bundle, not a rebuilt or released Core distribution. Do not deploy the new Canvas scripts without the matching Host BA2; an older Host lacks the echo helper. Legacy `compileScripts.ps1`, `createPackages.ps1`, and Spriggit dump entry points now forward to the variant-aware pipeline; the Spriggit assembly entry point fails with an actionable error. Neither `checkRepo.ps1` mode accepts Git LFS pointers, empty files, truncated headers or the wrong binary signature as staged ESM/BA2 content.

From the repository root, supply verified fixture paths through `$coreFixture`, `$hudFixture`, and the selected profile's existing plugin directory through `$plugins`:

```powershell
.\Tools\verifyConsumerDiscoveryProbe.ps1 -SourceOnly -ProbeProfile Baseline
.\Tools\compileConsumerDiscoveryScripts.ps1 -VenworksCoreRepositoryPath $coreFixture
.\Tools\buildConsumerDiscoveryProbe.ps1 -VwHudRepositoryPath $hudFixture
.\Tools\dumpConsumerDiscoveryPluginsToYaml.ps1 -ProbeProfile Baseline -PluginsDirectory $plugins
.\Tools\verifyConsumerDiscoveryProbe.ps1 -ArtifactsOnly -ProbeProfile Baseline -PluginsDirectory $plugins -VwHudRepositoryPath $hudFixture -VenworksCoreRepositoryPath $coreFixture
.\Tools\stageConsumerDiscoveryProbe.ps1 -ProbeProfile Baseline -PluginsDirectory $plugins -VwHudRepositoryPath $hudFixture -VenworksCoreRepositoryPath $coreFixture
.\Tools\verifyConsumerDiscoveryProbe.ps1 -ProbeProfile Baseline -PluginsDirectory $plugins -VwHudRepositoryPath $hudFixture -VenworksCoreRepositoryPath $coreFixture
.\Tools\checkRepo.ps1 -VariantKeys HOST,CONSUMERA,CONSUMERB
```

Run source, artifact, serialization, and stage verification for Baseline, Faults, and UpdatedA using each profile's matching plugin directory; finish with Baseline staged. Staging invokes Spriggit serialization itself, retains the exact Vortex junctions, and rejects equal or nested installation targets before swaps. Spriggit is review-only: never assemble ESMs from YAML. The permanent ESM names, FormIDs, masters, small-master flags, and non-RunOnce quest configuration remain unchanged.

Source-only CI checks all three profiles' typed `Consumers` seeds and quest/header contracts without game tools. Source and artifact verification permit the single guarded-reservation/post-guard Watch Alert submission site only in Registry; all other Canvas scripts remain forbidden from calling it. Focused wire/source tests live in `Tools/testConsumerDiscoveryUiLoad.ps1`. Compilation, PowerShell checks, and the retained parser fixtures are not Papyrus/Scaleform gameplay tests.

`Tools/testConsumerDiscoveryGuards.ps1` checks guard/lifecycle source contracts, follows local helper calls for logging/wait/subscription/scheduling hazards, and rejects deliberate unsafe source mutations held in memory. It is included in source verification and the UUID checks. It does not execute the Papyrus VM or establish lock behavior across save/load. The compiler output can be isolated with `compileConsumerDiscoveryScripts.ps1 -OutputDirectory <fresh-directory-under-.work/consumer-discovery>`; pass that same directory as `-ScriptsDirectory` to subsequent artifact, staging and full verification commands.

`Tools/testConsumerDiscoveryConsole.ps1` checks the real `Global` declarations, permanent plugin/file-local record mappings, failure guards, unchanged UUID input and B ownership, separate recovery dispatch, and documented commands. Its negative mutations are in memory only. Source verification includes it; neither this check nor compilation proves that the game console can invoke the packaged functions or resolve these small-master records.

### Persistent UUID identity

Every new consumer supplies a stable, non-nil UUID separately from its display name and safe asset namespace. Acceptable shapes are dashed D (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`), braced D, and compact 32-hex N, in any combination of upper/lower case. Whitespace, URNs and malformed values are rejected rather than repaired. Papyrus compares decoded UUID values because VM string interning may preserve earlier casing; ActionScript normalizes every external UUID intake to a lowercase dashed key. Asset folders are not renamed to UUIDs, and display labels are not registration identities.

| Consumer | Permanent UUID | Existing asset namespace |
| --- | --- | --- |
| A | `a8098c1a-f86e-4b1e-9d7c-5a102bf38460` | `venworks.canvas.probe.consumer-a` |
| B | `beef70b2-024e-4e9b-a8d5-70a0c882c431` | `venworks.canvas.probe.consumer-b` |
| Missing-movie probe | `cad7cd56-217a-4e62-a98d-42c3adad07b5` | `venworks.canvas.probe.missing` |

Only those known legacy demo keys are explicitly translated by the registrars. The registry rekeys an existing row only for its current quest owner and never resets the array; this also covers new UUID VMAD defaults encountering saved legacy rows. Unknown legacy names fail closed. The Faults profile attempts A's uppercase UUID from a different quest owner, which must be rejected without changing A.

Core exposes structural validation, parsing, formatting, value comparison and an explicit pure-Papyrus `GenerateV4()` helper. Structural validation permits nil; Canvas rejects nil as an identity. Generation uses the game's non-cryptographic random source: no cryptographic security or guaranteed uniqueness is claimed. Canvas never calls the generator or invents an identity when one is missing. An author may use any UUID source and must retain the result, not regenerate it on every load.

### PC test sequence

1. Close Starfield and deploy all matching Baseline packages through Vortex. Verify deployed files match staging; retain permanent filenames. Use disposable saves and a separate pre-Canvas save for each package combination.
2. Load directly from the main menu, with no console command required. Test Host only, Host+A, then Host+A+B. Host only should submit no consumer commands. A should produce one load submission, and A+B two spaced submissions, followed by their visible panels. The host should show `RX LOAD`, `LOAD`, then `READY` per consumer. Allow approximately 15 seconds of unpaused gameplay with the console closed.
3. Match `REGISTRATION_ACCEPTED` / `REGISTRATION_UNCHANGED` and `REGISTRATION_ACK` to separate `UI_LOAD_QUEUED` / `UI_LOAD_SUBMITTED` logs. The healthy Baseline count is zero, one, or two. A submitted command without a visible panel is not a pass; retain the host diagnostics and full Papyrus/Venworks logs.
4. Stop on renewed lag/watch animation problems, native guard ownership/unlock errors, repeated submissions without a new HUD activation/descriptor, or repeated retry exhaustion. Busy/inactive/full-queue results are deferred, never registration rejection or UI readiness. There are no bridge heartbeats or whole-registry snapshots.
5. Your earlier registration-only reload test was reported successful with `REGISTRATION_UNCHANGED`. For this build, save/reload with the same packages and exercise repeated HUD teardown/recreation: retain the registered records and restore both panels without duplicate loaders. Record a missed initial HUD callback or event as a failure, even if reopening the HUD recovers it.
6. After Baseline works, test normal/large selection, then UpdatedA (version 2 visible and persistent) and Faults (owner collision logged in Papyrus; missing movie fails in the host while A/B remain visible). Change one profile at a time; never rename plugins in a save. Ship HUD, pilot-seat delivery, and PS5 are deferred.
7. Search the entire log, including initial load/revert, for `Cannot unlock`, `RegistryGuard`, and `AttemptGuard`. A native ownership error fails acceptance even if loading later succeeds. Build-time tests do not establish Papyrus VM scheduling or guard safety.
8. Old saved quests without installed callbacks still use the separate recovery commands below. Replacing PEX is not claimed to repair orphaned guards or corrupted saved stacks. A normal fresh deployment must not depend on recovery commands.

### Global console diagnostics: resolve first

These diagnostics are optional for UI loading. PC console echo requires the user's debug-logging configuration; use `[Papyrus] bEnableLogging=1` and `bEnableTrace=1`. The exact individually required flag has not been isolated. Neither gameplay registration nor UI loading depends on these flags. To check the deployed utility, run:

```text
cgf "Venworks:Core:Utilities:Console.ConsoleEcho" "VWCANVAS: echo smoke test"
cgf "Venworks:Core:Tests:ConsoleOutputTests.Run"
```

Require visible `RM> VWCANVAS: echo smoke test` before continuing. The Core probe submits eleven lines covering single/block output, blank lines, None/empty arrays and two controlled LF rejection messages, ending in `CONSOLE_TEST_END`; see [Core console output documentation](https://github.com/monster-cookie/starfield-venworks-core/blob/fce6fadcb110f8a462c41680a1147d3c36e8421f/Documentation/ConsoleOutput.md) for the exact sequence. The end marker is not an automatic PASS. The compiler rejects `\r` literals, so CR/CRLF rejection is source-checked but not exercised by this VM probe. Capture actual console decoration/errors and stop if the `RM> ` prefix behaves unexpectedly. No visible-output acceptance is claimed by build checks.

Each Canvas command below explicitly calls the shared helper and prints one final `RM> VWCANVAS: <script>.<function> | <status>` line, including `CONSOLE_RESOLVE_FAILED`. Existing Papyrus return values remain for script callers; CGF return values are not themselves console feedback. The detailed begin/resolution/result logs remain separate. Echoing occurs only on explicit console wrapper paths, outside guarded work, and does not mirror ordinary logging or use the watch bridge.

These commands target functions explicitly declared `Global` in the existing packaged scripts. Their first console argument is a qualified function name, never a FormID. Inside Papyrus, each wrapper resolves its own quest using `Game.GetFormFromFile` with the permanent plugin name and file-local record ID, then checks both the form and attached-script cast for `None`. The diagnostic mappings are Host registry `0x000800`, Consumer B registrar `0x000800`, and UpdatedA migration `0x000801` in their respective ESMs. Bethesda's installed `SQ_FollowersScript.GetScript()` uses this lookup/cast pattern; that source precedent does not establish runtime acceptance for these small-master fixtures. Do not copy runtime load-order prefixes from LOOT, xEdit or the Creation Kit.

After both consumers are confirmed registered, run only the resolution gate first:

```text
cgf "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar.ConsoleResolve"
```

Inspect the Papyrus/Venworks log for `VWCANVAS_CONSOLE/1 | CONSOLE_BEGIN`, then `CONSOLE_RESOLVED | Form=... | RuntimeFormId=...`. This proves only that the packaged function ran and resolved its quest/script, not registration or UI readiness. No begin marker means invocation/loading is not confirmed. `CONSOLE_TARGET_NOT_FOUND` or `CONSOLE_SCRIPT_NOT_BOUND` means stop and capture the console output and logs; the wrapper returns `CONSOLE_RESOLVE_FAILED` without forwarding work. The resolution-only command does not initialize storage, register consumers, or schedule retries. The migration quest exists only in UpdatedA: its missing-target result under Baseline or Faults is expected.

Optional in-game quest discovery uses the **Editor ID**, not the display title: `help "VWCANVAS9_ConsumerBRegistrar" 4 QUST`. This is a diagnostic aid, not an input requirement for the global wrappers.

Once resolution succeeds, these explicit probes exercise the UI-request boundary as Consumer B. Each forwards the input unchanged through B's existing instance method and passes B as the owner. They do not register another consumer, transmit UI data, or schedule retries; the existing registry request path can initialize missing storage and prune invalid owners. Read `CONSOLE_RESULT | Status=...` and the host's result in the logs:

```text
cgf "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar.ConsoleCheckUiLoadRequest" "BEEF70B2-024E-4E9B-A8D5-70A0C882C431"
cgf "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar.ConsoleCheckUiLoadRequest" "a8098c1a-f86e-4b1e-9d7c-5a102bf38460"
cgf "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerBRegistrar.ConsoleCheckUiLoadRequest" "ea1d08f2-80a9-454a-8051-bd24b99650fc"
```

Expected visible results are respectively `REGISTERED_UI_LOAD_ELIGIBLE`, `REJECTED_OWNER_MISMATCH`, and `REJECTED_NOT_REGISTERED`, each with the `VWCANVAS: ConsumerBRegistrar.ConsoleCheckUiLoadRequest` label. Compare each printed result with `CONSOLE_RESULT | Status=...` in the logs. `DEFERRED_REGISTRY_BUSY` is inconclusive, not acceptance or rejection: let gameplay advance and manually retry the same command. These console probes and save-recovery behavior require human PC execution; build-time checks do not establish their runtime success. Manual lookup wrappers for owned fixture quests do not replace dynamic consumer registration or introduce coordinated consumer slots.

Repeat B's request with `{BeEf70B2-024e-4e9b-A8D5-70A0c882C431}` and `beef70b2024e4e9ba8d570a0c882c431`: both must find B. Nil, whitespace and malformed UUIDs must return `REJECTED_CONSUMER_ID`. To run the included Core probes explicitly:

```text
cgf "Venworks:Core:Tests:UUIDTests.Run"
cgf "Venworks:Core:Tests:UUIDTests.RunGeneration"
```

Inspect Papyrus logs for the UUID test results; compilation alone does not establish their success. For migration, keep a disposable copy of the previously tested legacy-ID save, replace all three packages without renaming plugins, load it and look for `LEGACY_ID_MIGRATED`, A+B registration and a count of two after reload. For UpdatedA, first save Baseline A+B, exit, deploy the verified UpdatedA profile, and load that same disposable save. Expect `DESCRIPTOR_UPDATE_APPLIED`, version 2, and version 2 retained across subsequent HUD openings and save/reload. Exercise rapid repeated menu openings during startup/update and the Faults profile's mixed-case ownership collision; collect logs if updates revert, duplicate rows appear or counts change unexpectedly. These manual checks do not by themselves force every VM interleaving: deterministic simultaneous-owner and unavailable-registry/save-during-update stress remain explicit runtime acceptance cases.

### Separate, explicit saved-quest recovery

For the affected host-only save, resolve first and continue only on `CONSOLE_RESOLVED`:

```text
cgf "Venworks:Canvas:Probes:ConsumerDiscovery:Registry.ConsoleResolve"
cgf "Venworks:Canvas:Probes:ConsumerDiscovery:Registry.ConsoleEnsureStorage"
```

The second command restores menu subscriptions, makes one nonblocking storage attempt, and logs its actual result outside the guard. Expect `REGISTRY_READY`, or manually retry an inconclusive `DEFERRED_REGISTRY_BUSY` after gameplay advances. Reopen the HUD and inspect recovery/count logs; valid registry records must be retained.

For an affected **UpdatedA** save only, resolve its separate migration quest before requesting recovery:

```text
cgf "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerAUpdateMigration.ConsoleResolve"
cgf "Venworks:Canvas:Probes:ConsumerDiscovery:ConsumerAUpdateMigration.ConsoleRetryUpdate"
```

`CONSOLE_RETRY_REQUESTED` means the existing recovery method was called, not that an update succeeded. It restores subscriptions and schedules the retained request only if the saved update is not already acknowledged. The migration quest reports `DESCRIPTOR_UPDATE_ACK | Version=2` only after registration acceptance. `DESCRIPTOR_UPDATE_RETRY_EXHAUSTED` retains its request for a later HUD opening. No acknowledged update is reset. Replacing PEX is not claimed to repair already-corrupted saved stacks or orphaned native guard ownership; test older saves separately from a clean pre-Canvas baseline.

### Papyrus guard investigation and modding-notes gate

The preceding UUID build produced three native guard unlock/ownership errors on `OnInit` call paths during a user-confirmed direct main-menu save load. Registration continued afterward, so the log did not prove a permanent deadlock, but that path failed runtime acceptance. It entered registry guards during initialization and held registrar guards across unavailable-registry waits; registry workers also logged and registered menu callbacks. The exact engine-level cause of the ownership errors has not been established.

Bethesda's installed `SQ_ParentScript.HandleCriticalHit` uses `TryLockGuard` / `EndTryLockGuard` and explicitly skips overlapping work. That is source evidence for the nonblocking pattern, not proof that arbitrary save/load or nested-guard use is safe. The current Canvas implementation instead returns a deferred receipt so required registration/update work is retained and can be retried. No C# monitor, reentrancy, fairness, thread-affinity, or automatic recovery semantics are assumed.

After direct PC evidence validates the path, prepare the community modding-notes article with a minimal reproducible example, tested game/compiler versions, the failed pattern, observed guard behavior, startup/save-load constraints, busy-result handling and unresolved limits. Until those tests pass this is a diagnostic implementation, not a verified community recipe. Site publication is a separate handoff using the actual site repository/workflow; no site content has been published by this change.

The matrix separates registration checks from visible loading cases. Player HUD A/B, normal/large selection, update/failure isolation, and UI recreation are this increment's PC gates. Ship/pilot-seat delivery and PS5 remain deferred. Neither compilation nor source/reference-parser tests establish those runtime outcomes. Do not claim VWCANVAS-9 or the broader VWCANVAS-16 lifecycle complete from this build.
