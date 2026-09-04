# Venworks Canvas and UI Data Layer

## Version 1.0.0 (UNRELEASED)

- Add an explicit consumer-controlled UI-load step after Papyrus registration, with a bounded, coalescing, load-only Watch bridge queue and Player HUD consumer loading diagnostics. No UI delivery acknowledgement is claimed.
- Preserve registration persistence and ESM identities while resetting presentation bookkeeping for HUD recreation; keep console ownership checks non-transmitting and use Core's corrected RM> prefix.
- Add load-packet/source regression checks and retain guard, UUID, packaging and Spriggit serialization gates. PC visible loading, watch responsiveness and UI recreation require human acceptance; ship/pilot-seat and PS5 delivery remain deferred.
- Requires Venworks Core Library 2.1.6 or higher
- Bundle the pinned VWCORE-5 `Utilities/Console` helper and visual probe in the diagnostic Host BA2; explicitly print one labeled result from each Canvas global console command without mirroring normal logs or using the UI bridge.
- Added initial registration system for modders/creators to hook in their creations
- Reworked the PC registration diagnostic to defer startup and retry busy Papyrus guards without waiting inside them; in-game guard/save-load acceptance remains pending.
- Added real global console wrappers with runtime quest resolution, explicit ownership probes and separate saved-quest recovery; console invocation and small-master lookup require PC validation.
