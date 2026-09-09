# Venworks Canvas and UI Data Layer

## Version 1.0.0 (UNRELEASED)

- Requires Venworks Core Library 2.1.8 or higher.
- Adds support for multiple compatible HUD add-ons to display their panels together in the Player HUD.
- Includes optional Example and Component Gallery panels for testing and demonstration.
- Adds version 2 compatibility negotiation for HUD add-ons while retaining version 1 loading support.
- Lets compatible add-ons receive shared game UI data and named events published by Papyrus scripts. Event delivery is temporary and lossy, with no automatic retry or replay.
- Updates the Example and Component Gallery panels to display received player-data and example-event markers.
- Adds an explicit Example ping command and a visible `pong` response that remains until the Example movie unloads.
- Adds explicit installation and verification commands for the pinned build tools, including retained-cache and offline setup with Adobe license acceptance when extraction is needed.
- Normal compile and Scaleform build commands now publish final loose Papyrus and Scaleform outputs directly into the selected `Staging-*\Scripts` and `Staging-*\Interface` trees for SFCK and Creations handoff; `.work\canvas` remains temporary compiler, build, and package-recovery workspace.
- Adds a Canvas-owned vanilla Player HUD bootstrap patch for `hudmenu.swf`, `hudmenu.gfx`, `hudmenu_lrg.swf`, and `hudmenu_lrg.gfx`, raising Canvas-owned movie outputs from 7 to 11 and the all-variant staged movie inventory from 11 to 15. Canvas does not require VWHUD runtime or build files; VWHUD may build on Canvas.
- Disables Watch display and alert animations while keeping the underlying data available. This is due to the data layer using the custom event systgem the watch defines. When used this way it causes lag and animation glitches.
