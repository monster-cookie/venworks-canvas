# Venworks Canvas and UI Data Layer

## Version 1.0.0 (UNRELEASED)

- Requires Venworks Core Library 2.1.8 or higher.
- Adds support for multiple compatible HUD add-ons to display their panels together in the Player HUD.
- Includes an optional Example panel and a separate Component Gallery with `Tag | Syntax | Rendered Result` columns that place HTML examples beside their Canvas-rendered results.
- Adds version 2 compatibility negotiation for HUD add-ons while retaining version 1 loading support.
- Lets compatible add-ons receive shared game UI data and named events published by Papyrus scripts. Event delivery is temporary and lossy, with no automatic retry or replay.
- Updates the Example panel to display received player-data and example-event markers.
- Adds an explicit Example ping command and a visible `pong` response that remains until the Example movie unloads.
- Tightens panel loading so stale or duplicate notifications do not activate the wrong panel. Current-build gameplay acceptance is still pending.
- Adds Canvas rendering for packaged HTML/CSS interfaces, including styled text, lists, buttons, images, reusable content, and sample-data displays in the Component Gallery. This is a supported subset of HTML/CSS, not full web-browser compatibility; current-build PC and PS5 gameplay acceptance remains pending.
- Adds mouse-wheel, Up/Down arrow-key, and Page Up/Page Down navigation through the Component Gallery examples.
- Disables Watch display and alert animations while keeping its underlying data available. This avoids the lag and animation glitches caused when Canvas and Watch presentation use the same event path simultaneously.
