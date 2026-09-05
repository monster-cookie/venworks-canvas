# Venworks Canvas and UI Data Layer

## Version 1.0.0 (UNRELEASED)

- Requires Venworks Core Library 2.1.8 or higher
- Added initial registration system for modders/creators to hook in their creations
- Reworked the PC registration diagnostic to defer startup and retry busy Papyrus guards without waiting inside them.
- Added Canvas-owned struct-as-enum selectors for the supported events and packet types so consumer callers cannot supply invalid values breaking the watch.
- Made the Player HUD receiver accept ASCII case changes in the fixed event header and packet type while preserving the original framed payload for strict parsing.
- Restored `createPackages.ps1` to a standard variant-oriented interface that builds only the selected Host, Consumer A, or Consumer B PC Main archive and never replaces a Vortex staging junction.
- Changed profile staging to replace only selected ESM/BA2 files so Vortex physical module directories and their repository Junctions are never moved, deleted, recreated, or retargeted.
