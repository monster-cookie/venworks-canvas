# Venworks Canvas and UI Data Layer

## Version 1.0.4 (UNRELEASED)

- Added support for the HTML privatives that Venworks Customizable HUD needs.
- Added standard inline and external SVG support, including paths, shapes, transforms, and CSS fill and stroke styling.
- Added semantic controls for hiding, disabling, and positioning individual player HUD, spaceship HUD, and Canvas watch elements.
- Expanded meters and layout tools with configurable ranges, directions, segments, partial fills, safe-area anchors, and live visual bindings.
- Improved live data updates so unchanged interface elements are retained and rejected updates preserve the last valid display.
- Added runtime package checks that reject stale Canvas host or Registry files before release packaging.
- Documented that every Canvas document must start with `<!doctype html>`, that element names are lowercase, and that paint keywords such as `currentcolor` are lowercase.
- Accept a static parent of an absolutely positioned element. The element is placed against the nearest relative or absolute ancestor, or against the viewport when every ancestor is static.
- Accept arrays created by a consumer movie when copying HTML data. Their index keys are no longer reported as invalid properties.

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
