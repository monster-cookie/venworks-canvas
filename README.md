# venworks-canvas
BGS Scaleform HTML and CSS Engine along with a papyrus data layer. 

## VWCANVAS-9: bridge-disabled PC registration test

The current diagnostic build separates Papyrus consumer registration from UI transport. Canvas does not invoke the Watch Alert API, and the host movie does not subscribe to `CustomAlertsData`. The vanilla watch is not disabled. The static overlay reads `REGISTRATION LOG TEST` and `WATCH BRIDGE DISABLED`; it proves only which host movie is installed, not that consumers registered or loaded.

`RegisterConsumer()` returns a synchronous Papyrus acknowledgement after validating ownership and storing the descriptor. Identical registration is a successful no-op. Consumers wait only while the registry reference is unavailable; once it answers, rejection is terminal for that attempt rather than retried every half-second. Menu openings may perform a new reconciliation attempt, with no bridge publication. An overlapping attempt is skipped.

After actual registration success, consumers call `RequestUiLoad(owner, consumerId)`. The host reads its stored descriptor and returns `REGISTERED_TRANSPORT_DISABLED` for the correct owner, or `REJECTED_OWNER_UNAVAILABLE`, `REJECTED_CONSUMER_ID`, `REJECTED_NOT_REGISTERED`, or `REJECTED_OWNER_MISMATCH`. A validated request is deliberately **not queued, submitted, or loaded**. Expected negative registration tests do not automatically request UI loads. A disabled UI transport does not undo a successful descriptor update.

### Build and packaging

Use the existing pinned Core fixture and VWHUD-v2-derived toolchain declared in `Scaleform/probes/consumer-discovery/probe-matrix.psd1`. No new dependency or plugin-generation step is required for this increment. Existing verified profile ESMs are inputs; `.work` build inputs are local scratch and are not supplied by a fresh checkout. The deployable payloads are the ESM and matching BA2 in each of `Staging-Host`, `Staging-ConsumerA`, and `Staging-ConsumerB`.

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

### PC test sequence

1. Close Starfield, deploy the new Baseline packages through Vortex, and verify its deployed files match the staging payload. Preserve the same permanent ESM names. Use a disposable pre-Canvas save for each different package combination; do not remove or rename plugins in a valuable save.
2. Test Host only, then Host+A, then Host+A+B with the required Core dependency. The overlay must identify bridge-disabled mode; consumer panels should not load. Check the watch and normal gameplay responsiveness.
3. Inspect both the Venworks and Papyrus logs. Expect `REGISTRATION_ACCEPTED` for each real consumer, followed by `REGISTRATION_ACK` and `REGISTERED_TRANSPORT_DISABLED`. The registry count should be zero, one, or two for those Baseline combinations. `REGISTRATION_UNCHANGED` is expected during idempotent menu reconciliation.
4. If registration fails, capture `REGISTRATION_REJECTED` with its field, actual length/limits or character code/index, version, or canonical path mismatch. Do not treat absence of a panel as a descriptor failure in this build. There must be no half-second rejection loop and no Canvas Watch Alert activity.
5. After A+B works, create a disposable test save, exit, reload it with the same packages, and close/reopen the HUD several times. Valid saved records must remain present. `Consumers` is initialized only when `None`; the inert VMAD seed and unavailable owners are pruned. No recorded UI request is replayed.
6. For an older affected host quest whose `OnInit` never installed callbacks, a consumer call into the host restores them. A host-only save with no remaining callback/caller cannot repair itself merely by replacing PEX; invoke `cqf VWCANVAS9_ConsumerDiscoveryRegistry EnsureStorage` once, then reopen the HUD and inspect the recovery/count logs. This does not reset valid registry storage.

After both consumers are confirmed registered, these explicit console probes exercise the UI-request boundary as Consumer B. They do not register another consumer or transmit UI data; read the host's result in the logs:

```text
cqf VWCANVAS9_ConsumerBRegistrar CheckUiLoadRequest "venworks.canvas.probe.consumer-b"
cqf VWCANVAS9_ConsumerBRegistrar CheckUiLoadRequest "venworks.canvas.probe.consumer-a"
cqf VWCANVAS9_ConsumerBRegistrar CheckUiLoadRequest "venworks.canvas.probe.not-registered"
```

Expected results are respectively `REGISTERED_TRANSPORT_DISABLED`, `REJECTED_OWNER_MISMATCH`, and `REJECTED_NOT_REGISTERED`. These console probes and save-recovery behavior require human PC execution; build-time checks do not establish their runtime success.

The matrix's `RegistrationRuntimeCases` describe this diagnostic increment. Its original visual `RuntimeCases` remain deferred acceptance requirements, including actual consumer loading, normal/large selection, movie failures, and pilot-seat delivery. Do not re-enable the bridge, claim VWCANVAS-9 complete, or proceed to PS5 acceptance solely from this log-only build.
