# venworks-canvas
BGS Scaleform HTML and CSS Engine along with a papyrus data layer. 

## VWCANVAS-9: bridge-disabled PC registration test

The current diagnostic build separates Papyrus consumer registration from UI transport. Canvas does not invoke the Watch Alert API, and the host movie does not subscribe to `CustomAlertsData`. The vanilla watch is not disabled. The static overlay reads `REGISTRATION LOG TEST` and `WATCH BRIDGE DISABLED`; it proves only which host movie is installed, not that consumers registered or loaded.

`TryRegisterConsumer()` returns a caller-owned Papyrus receipt after one nonblocking attempt. `REGISTRATION_ACCEPTED`, `REGISTRATION_UPDATED`, and `REGISTRATION_UNCHANGED` acknowledge stored state; `DEFERRED_REGISTRY_BUSY` is neither acceptance nor rejection. The legacy `RegisterConsumer()` Boolean wrapper remains available, but false now includes contention: new consumers must use the explicit receipt. No acknowledgement establishes UI readiness.

`OnInit` only installs menu callbacks. A supported HUD opening schedules timer-driven reconciliation; it does not resume a waiting `OnInit` stack. Registrars try `AttemptGuard`, then the host tries `RegistryGuard`; neither waits for acquisition. Retry delays, subscriptions and logging run outside both guards. Each deferred sequence has at most 20 attempts at half-second retry intervals, with exhaustion logged and pending data retained for a later event. Overlapping events may create overlapping bounded sequences; no fairness or native-timer ordering guarantee is claimed. The old saved `RegistrationAttemptActive` flag is not consulted as a lock or scheduling gate.

An acquired registrar guard stores a complete pending update before calling the host. Busy/unavailable host results retain it; only acceptance commits active descriptor fields, while terminal rejection clears that submitted pending request. If the registrar guard itself is busy, the input has **not** been stored: the caller must retain and resubmit it. The UpdatedA migration quest does this from its persistent VMAD descriptor until an explicit registration acknowledgement. Known legacy rekey and registration share one host transaction, so busy cannot be misread as an invalid UUID or skipped migration.

After actual registration success, consumers make an explicit `TryRequestUiLoad(owner, consumerId)` call. The host returns `REGISTERED_TRANSPORT_DISABLED` for the stored owner/ID pair, a `REJECTED_*` reason, or a separate `DEFERRED_REGISTRY_BUSY`. The public string-returning `RequestUiLoad` wrapper also logs the result. A validated request is deliberately **not queued, submitted, or loaded**. Expected negative registration tests do not automatically request UI loads. Disabled or busy UI transport does not undo a successful descriptor update; UI contention may trigger later reconciliation without inventing a UI acknowledgement.

### Build and packaging

Use released Venworks Core **2.1.6** with the additional pinned console diagnostic scripts bundled in the Canvas Host BA2, and the VWHUD-v2-derived toolchain declared in `Scaleform/probes/consumer-discovery/probe-matrix.psd1`. Rebuilding requires Core fixture commit `06d9789cc02e2dd64a5a5bc98ae6255ca9f94ba2` (VWCORE-5), with eight pinned source/runtime pairs. The preceding six Core dependency pairs remain byte-identical; the additive console utility and its visual probe are unreleased, not part of Core 2.1.6. Core's ESM, release archives, and version metadata are unchanged. The profile ESMs bind fixed UUIDs and were generated with Mutagen, then independently serialized with Spriggit. The generator and `.work` build inputs are local scratch, not supplied by a fresh checkout; use materialized committed Baseline packages to deploy, or the matching verified profile ESM inputs when rebuilding. The deployable payloads are the ESM and matching BA2 in each of `Staging-Host`, `Staging-ConsumerA`, and `Staging-ConsumerB`.

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

Source-only CI checks all three profiles' typed `Consumers` seeds and quest/header contracts without game tools. Source and artifact verification reject Watch Alert references in Canvas PSC and PEX files. Compilation, PowerShell checks, and the retained parser fixtures are not Papyrus/Scaleform gameplay tests.

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

1. Close Starfield, deploy the new Baseline packages through Vortex, and verify its deployed files match the staging payload. Preserve the same permanent ESM names. Use a disposable pre-Canvas save for each different package combination; do not remove or rename plugins in a valuable save.
2. Test Host only, then Host+A, then Host+A+B with Core 2.1.6. Start with a direct main-menu load, not just an in-game reload. The overlay must identify bridge-disabled mode; consumer panels should not load. Check the watch and normal gameplay responsiveness. Registration is driven by HUD-open callbacks: if startup produced no attempt, reopen a supported HUD and retain the log showing the missed initial event; do not record initial-load success based solely on that workaround.
3. Inspect both the Venworks and Papyrus logs. Expect `REGISTRATION_ACCEPTED` for each real consumer, followed by `REGISTRATION_ACK` and `REGISTERED_TRANSPORT_DISABLED`. The registry count should be zero, one, or two for those Baseline combinations. `REGISTRATION_UNCHANGED` is expected during idempotent menu reconciliation.
4. If registration fails, capture `REGISTRATION_REJECTED` with its bounded field reason or `REJECTED_OWNER_MISMATCH`. Busy results are `DEFERRED_REGISTRY_BUSY` or `DEFERRED_ATTEMPT_BUSY`; a missing registry is `DEFERRED_REGISTRY_UNAVAILABLE`. Busy must never produce `EXPECTED_REGISTRATION_REJECTION`. Each automatic retry sequence must stop after 20 attempts, logging `REGISTRATION_RETRY_EXHAUSTED` or `REGISTRY_RETRY_EXHAUSTED`. Repeated exhaustion without recovery fails acceptance. There must be no terminal-rejection polling loop and no Canvas Watch Alert activity.
5. After A+B works, create a disposable test save, exit, reload it with the same packages, and close/reopen the HUD several times. Valid saved records must remain present. `Consumers` is initialized only when `None`; the inert VMAD seed and unavailable owners are pruned. No recorded UI request is replayed.
6. For an older affected host quest whose `OnInit` never installed callbacks, a consumer call into the host restores them. A host-only save with no remaining callback/caller cannot repair itself merely by replacing PEX; use the separate host recovery commands below after confirming resolution. This does not reset valid registry storage.
7. Search the complete Papyrus log for `Cannot unlock`, `RegistryGuard`, and `AttemptGuard`, including the initial load/revert period. Any native ownership/unlock error is a failed test, even if both consumers eventually register. Confirm that busy read APIs do not invent an empty registry: `GetConsumerCount()` returns -1 when busy; `FindConsumerIndex()` returns -2 when busy and -1 only when absent.

### Global console diagnostics: resolve first

First verify the deployed console-output utility with the following smoke test, then its explicit block probe:

```text
cgf "Venworks:Core:Utilities:Console.ConsoleEcho" "VWCANVAS: echo smoke test"
cgf "Venworks:Core:Tests:ConsoleOutputTests.Run"
```

Require visible `=> VWCANVAS: echo smoke test` before continuing. The Core probe submits eleven lines covering single/block output, blank lines, None/empty arrays and two controlled LF rejection messages, ending in `CONSOLE_TEST_END`; see [Core console output documentation](https://github.com/monster-cookie/starfield-venworks-core/blob/06d9789cc02e2dd64a5a5bc98ae6255ca9f94ba2/Documentation/ConsoleOutput.md) for the exact sequence. The end marker is not an automatic PASS. The compiler rejects `\r` literals, so CR/CRLF rejection is source-checked but not exercised by this VM probe. Capture actual console decoration/errors and stop if the `=> ` prefix behaves unexpectedly. No visible-output acceptance is claimed by build checks.

Each Canvas command below explicitly calls the shared helper and prints one final `=> VWCANVAS: <script>.<function> | <status>` line, including `CONSOLE_RESOLVE_FAILED`. Existing Papyrus return values remain for script callers; CGF return values are not themselves console feedback. The detailed begin/resolution/result logs remain separate. Echoing occurs only on explicit console wrapper paths, outside guarded work, and does not mirror ordinary logging or use the watch bridge.

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

Expected visible results are respectively `REGISTERED_TRANSPORT_DISABLED`, `REJECTED_OWNER_MISMATCH`, and `REJECTED_NOT_REGISTERED`, each with the `VWCANVAS: ConsumerBRegistrar.ConsoleCheckUiLoadRequest` label. Compare each printed result with `CONSOLE_RESULT | Status=...` in the logs. `DEFERRED_REGISTRY_BUSY` is inconclusive, not acceptance or rejection: let gameplay advance and manually retry the same command. These console probes and save-recovery behavior require human PC execution; build-time checks do not establish their runtime success. Manual lookup wrappers for owned fixture quests do not replace dynamic consumer registration or introduce coordinated consumer slots.

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

The matrix's `RegistrationRuntimeCases` describe this diagnostic increment. Its original visual `RuntimeCases` remain deferred acceptance requirements, including actual consumer loading, normal/large selection, movie failures, and pilot-seat delivery. Do not re-enable the bridge, claim VWCANVAS-9 complete, or proceed to PS5 acceptance solely from this log-only build.
