# venworks-canvas
BGS Scaleform HTML and CSS Engine along with a papyrus data layer. 

## VWCANVAS-9: bridge-disabled PC registration test

The current diagnostic build separates Papyrus consumer registration from UI transport. Canvas does not invoke the Watch Alert API, and the host movie does not subscribe to `CustomAlertsData`. The vanilla watch is not disabled. The static overlay reads `REGISTRATION LOG TEST` and `WATCH BRIDGE DISABLED`; it proves only which host movie is installed, not that consumers registered or loaded.

`RegisterConsumer()` returns a synchronous Papyrus acknowledgement after validating ownership and storing the descriptor. Identical registration is a successful no-op. Consumers wait only while the registry reference is unavailable; once it answers, rejection is terminal for that attempt rather than retried every half-second. Menu openings may perform a new reconciliation attempt, with no bridge publication. Native Papyrus guards serialize registry transactions and each registrar's attempts. An overlapping descriptor update waits instead of being skipped; an update whose registry is unavailable remains pending for a later reconciliation.

After actual registration success, consumers call `RequestUiLoad(owner, consumerId)`. The host reads its stored descriptor and returns `REGISTERED_TRANSPORT_DISABLED` for the correct owner, or `REJECTED_OWNER_UNAVAILABLE`, `REJECTED_CONSUMER_ID`, `REJECTED_NOT_REGISTERED`, or `REJECTED_OWNER_MISMATCH`. A validated request is deliberately **not queued, submitted, or loaded**. Expected negative registration tests do not automatically request UI loads. A disabled UI transport does not undo a successful descriptor update.

### Build and packaging

Use the pinned Core UUID-utilities revision and VWHUD-v2-derived toolchain declared in `Scaleform/probes/consumer-discovery/probe-matrix.psd1`. The profile ESMs now bind fixed UUIDs and were regenerated with the existing Mutagen generator, then independently serialized with Spriggit. The generator and `.work` build inputs are local scratch, not supplied by a fresh checkout; use materialized committed Baseline packages to deploy, or the matching verified profile ESM inputs when rebuilding. The deployable payloads are the ESM and matching BA2 in each of `Staging-Host`, `Staging-ConsumerA`, and `Staging-ConsumerB`.

The Host diagnostic archive includes six pinned Core PEX dependencies, including `Utilities/UUID` and its explicit `Tests/UUIDTests` probe. This is a diagnostic dependency bundle, not a rebuilt or released Core distribution. Core's ESM and existing archives are unchanged. Legacy `compileScripts.ps1`, `createPackages.ps1`, and Spriggit dump entry points now forward to the variant-aware pipeline; the Spriggit assembly entry point fails with an actionable error. Neither `checkRepo.ps1` mode accepts Git LFS pointers, empty files, truncated headers or the wrong binary signature as staged ESM/BA2 content.

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
2. Test Host only, then Host+A, then Host+A+B with the required Core dependency. The overlay must identify bridge-disabled mode; consumer panels should not load. Check the watch and normal gameplay responsiveness.
3. Inspect both the Venworks and Papyrus logs. Expect `REGISTRATION_ACCEPTED` for each real consumer, followed by `REGISTRATION_ACK` and `REGISTERED_TRANSPORT_DISABLED`. The registry count should be zero, one, or two for those Baseline combinations. `REGISTRATION_UNCHANGED` is expected during idempotent menu reconciliation.
4. If registration fails, capture `REGISTRATION_REJECTED` with its field, actual length/limits or character code/index, version, or canonical path mismatch. Do not treat absence of a panel as a descriptor failure in this build. There must be no half-second rejection loop and no Canvas Watch Alert activity.
5. After A+B works, create a disposable test save, exit, reload it with the same packages, and close/reopen the HUD several times. Valid saved records must remain present. `Consumers` is initialized only when `None`; the inert VMAD seed and unavailable owners are pruned. No recorded UI request is replayed.
6. For an older affected host quest whose `OnInit` never installed callbacks, a consumer call into the host restores them. A host-only save with no remaining callback/caller cannot repair itself merely by replacing PEX; invoke `cqf VWCANVAS9_ConsumerDiscoveryRegistry EnsureStorage` once, then reopen the HUD and inspect the recovery/count logs. This does not reset valid registry storage.

After both consumers are confirmed registered, these explicit console probes exercise the UI-request boundary as Consumer B. They do not register another consumer or transmit UI data; read the host's result in the logs:

```text
cqf VWCANVAS9_ConsumerBRegistrar CheckUiLoadRequest "BEEF70B2-024E-4E9B-A8D5-70A0C882C431"
cqf VWCANVAS9_ConsumerBRegistrar CheckUiLoadRequest "a8098c1a-f86e-4b1e-9d7c-5a102bf38460"
cqf VWCANVAS9_ConsumerBRegistrar CheckUiLoadRequest "ea1d08f2-80a9-454a-8051-bd24b99650fc"
```

Expected results are respectively `REGISTERED_TRANSPORT_DISABLED`, `REJECTED_OWNER_MISMATCH`, and `REJECTED_NOT_REGISTERED`. These console probes and save-recovery behavior require human PC execution; build-time checks do not establish their runtime success.

Repeat B's request with `{BeEf70B2-024e-4e9b-A8D5-70A0c882C431}` and `beef70b2024e4e9ba8d570a0c882c431`: both must find B. Nil, whitespace and malformed UUIDs must return `REJECTED_CONSUMER_ID`. To run the included Core probes explicitly:

```text
cgf "Venworks:Core:Tests:UUIDTests.Run"
cgf "Venworks:Core:Tests:UUIDTests.RunGeneration"
```

Inspect Papyrus logs for the UUID test results; compilation alone does not establish their success. For migration, keep a disposable copy of the previously tested legacy-ID save, replace all three packages without renaming plugins, load it and look for `LEGACY_ID_MIGRATED`, A+B registration and a count of two after reload. For UpdatedA, first save Baseline A+B, exit, deploy the verified UpdatedA profile, and load that same disposable save. Expect `DESCRIPTOR_UPDATE_APPLIED`, version 2, and version 2 retained across subsequent HUD openings and save/reload. Exercise rapid repeated menu openings during startup/update and the Faults profile's mixed-case ownership collision; collect logs if updates revert, duplicate rows appear or counts change unexpectedly. These manual checks do not by themselves force every VM interleaving: deterministic simultaneous-owner and unavailable-registry/save-during-update stress remain explicit runtime acceptance cases.

The matrix's `RegistrationRuntimeCases` describe this diagnostic increment. Its original visual `RuntimeCases` remain deferred acceptance requirements, including actual consumer loading, normal/large selection, movie failures, and pilot-seat delivery. Do not re-enable the bridge, claim VWCANVAS-9 complete, or proceed to PS5 acceptance solely from this log-only build.
