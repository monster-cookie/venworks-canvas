# Venworks Canvas and UI Data Layer

## Version 1.0.1 (September 25, 2026)

- Requires Venworks Core Library 2.1.8 or higher.
- Includes an optional Example panel and a separate Component Gallery with `Tag | Syntax | Rendered Result` columns that place HTML examples beside their Canvas-rendered results.
- Adds support for multiple compatible HUD add-ons to display their panels together in the Player HUD.
- Lets compatible add-ons receive shared game UI data and named events published by Papyrus scripts. Unfortunately event delivery is not guarenteed and has no automatic retry or replay.
- Tightens panel loading so stale or duplicate notifications do not activate the wrong panel. Current-build gameplay acceptance is still pending.
- Adds Canvas rendering for packaged HTML/CSS interfaces, including styled text, lists, buttons, SVG images, reusable content, and sample-data displays in the Component Gallery. This is a supported subset of HTML/CSS, not full web-browser compatibility.
- Disables Watch display and alert animations while keeping its underlying data available. This avoids the lag and animation glitches caused when Canvas and Watch presentation use the same event path simultaneously.
