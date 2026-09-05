# Venworks Canvas and UI Data Layer

## Version 1.0.0 (UNRELEASED)

- Requires Venworks Core Library 2.1.8 or higher.
- Added a persistent, owner-checked UUID registry for independently packaged Canvas consumers.
- Added explicit registration receipts and a separate UI-load request step so registration remains Papyrus-side until a consumer asks to load its movie.
- Added bounded, nonblocking guard and timer handling that keeps logging, scheduling, subscriptions, waits, and UI bridge calls outside acquired guards.
- Added Canvas-owned event-header and packet-type selectors with strict framed-packet validation and ASCII case handling at UI intake.
- Added dynamic Player HUD loading for multiple namespaced consumer movies without static slots.
- Restored the Watch data subscriptions while disabling its presentation before Canvas bridge traffic begins.
- Established permanent Canvas, Example, and Component Gallery plugin, archive, staging, script, and Scaleform identities.
- Consolidated the production build pipeline into `compileScripts.ps1`, `buildScaleform.ps1`, and `createPackages.ps1`.
- Centralized all package variant definitions in `sharedConfig.ps1`.
- Made Spriggit YAML dumping variant-aware while retaining assembly as an explicit fail-closed operation.
- Made packaging replace only exact ESM and BA2 child files beneath verified Vortex junctions.
