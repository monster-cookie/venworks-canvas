# Venworks Canvas and UI Data Layer

## Version 1.0.0 (UNRELEASED)

- Requires Venworks Core Library 2.1.6 or higher
- Bundle the pinned, unreleased VWCORE-5 `Utilities/Console` helper and visual probe in the diagnostic Host BA2; explicitly print one labeled result from each Canvas global console command without changing return values, logging, guard behavior, or the disabled watch bridge. Visible console output remains a PC acceptance gate.
- Added initial registration system for modders/creators to hook in their creations
- Reworked the PC registration diagnostic to defer startup and retry busy Papyrus guards without waiting inside them; in-game guard/save-load acceptance remains pending.
- Added real global console wrappers with runtime quest resolution, explicit ownership probes and separate saved-quest recovery; console invocation and small-master lookup require PC validation.
