# Venworks Canvas and UI Data Layer

## Version 1.0.5 (October 3, 2026)

- The Player HUD now shows a boot animation until the first HUD panel is ready.
- Added the specialized HTML support that Venworks Customizable HUD needs.
- Added SVG images, including shapes, paths, movement, and fill and outline colors.
- You can hide, turn off, or move individual parts of the player HUD, the spaceship HUD, and the Canvas watch.
- Starfield Chronomark watch is not part of the Canvas HUD, and restoring the original watch files breaks the data layer and the whole HUD.
- Meters and layout tools can use custom ranges, fill direction, segments, partial fills, screen-edge placement, and live values.
- The Canvas watch compass uses the game's location icons, including their effects. The icons move, resize, and fade as you turn and as markers update.
- The Component Gallery stays open when the menu resizes or changes page.
- Text and meter fills stay in place when the HUD refreshes an existing frame.
- An absolutely positioned element lines up with the nearest positioned parent, or with the screen when no parent is positioned.
- A repeating list can include up to 65,536 items. A value that only happens to have a length is still treated as one item, not a list.
- Every Canvas HTML document must start with `<!doctype html>`. Tag names and color keywords such as `currentcolor` must be lowercase.

## Version 1.0.3 (September 25, 2026)

- Misc documentation updates and hooking up to Nexus API for automatic uploads.

## Version 1.0.1 (September 25, 2026)

- Requires Venworks Core Library 2.1.8 or higher.
- Includes an optional Example panel and a separate Component Gallery with `Tag | Syntax | Rendered Result` columns that place HTML examples beside their Canvas-rendered results.
- Adds support for multiple compatible HUD add-ons to display their panels together in the Player HUD.
- Lets compatible add-ons receive shared game UI data and named events published by Papyrus scripts. Unfortunately event delivery is not guarenteed and has no automatic retry or replay.
- Tightens panel loading so stale or duplicate notifications do not activate the wrong panel. Current-build gameplay acceptance is still pending.
- Adds Canvas rendering for packaged HTML/CSS interfaces, including styled text, lists, buttons, SVG images, reusable content, and sample-data displays in the Component Gallery. This is a supported subset of HTML/CSS, not full web-browser compatibility.
- Disables Watch display and alert animations while keeping its underlying data available. This avoids the lag and animation glitches caused when Canvas and Watch presentation use the same event path simultaneously.
