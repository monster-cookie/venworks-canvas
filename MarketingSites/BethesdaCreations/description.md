VENWORKS CANVAS

Venworks Canvas is a shared Player HUD framework for Starfield. Compatible UI add-ons use one common host instead of each add-on replacing the Player HUD on its own.

Canvas is a foundation for compatible add-ons, not a standalone HUD theme. Install the base Creation first, then install the Canvas add-ons you want to use.

PACKAGES

- Venworks Canvas: the required base runtime and shared Player HUD host.
- Venworks Canvas Example: an optional example panel that demonstrates player data, a clock, buff and debuff counts, and rotating effect rows.
- Venworks Canvas Component Gallery: an optional live reference for creators that shows supported Canvas HTML, CSS, components, and data bindings beside their rendered results.

FEATURES

- Gives compatible add-ons a shared Player HUD/UI host and data exchange layer.
- Keeps add-on registration and loading in the Canvas base package.
- Supports normal and large interface modes.
- Renders a focused game-UI subset of HTML and CSS, including styled text, lists, buttons, SVG images, reusable content, and bound data.
- Provides shared player values and named events for compatible panels.
- Lets add-ons publish their own small Canvas datagrams for state and event data.
- Includes complete source and creator documentation for authors building their own Canvas panel.

ROADMAP

Planned improvements:

- Support for custom menus.
- More shared data subscriptions and events.

USAGE

The Canvas base package works in the background and does not add a complete HUD theme by itself. Install a compatible Canvas add-on to add a visible panel.

The optional Example panel demonstrates an independently packaged Canvas add-on, with player data, a clock, buff and debuff counts, and rotating effect rows.

The optional Component Gallery can be opened from the Pause Menu and browsed with Up/Down, the right stick, the mouse wheel, or the scrollbar. Cancel returns to the Pause Menu.

REQUIREMENTS

- Starfield
- Venworks Core Library version 2.1.8 or newer

INSTALLATION

1. Install and enable Venworks Core Library version 2.1.8 or newer.
2. Install and enable Venworks Canvas.
3. Install the optional Example or Component Gallery Creations only if you want them.
4. Keep Core before Canvas and Canvas before its optional add-ons in the load order. Their plugin masters should enforce this order.

COMPATIBILITY

Canvas 1.0 is a Player HUD and UI framework. It owns complete Player HUD and UI files, so another Creation that replaces the same files can overwrite Canvas or be overwritten by it according to load order. Do not combine competing full-HUD replacements unless the authors provide an explicit compatibility patch.

Keep Canvas and its add-ons on mutually compatible versions. The Example and Component Gallery require the Canvas base Creation but are not required by ordinary Canvas add-ons unless their authors say otherwise.

TROUBLESHOOTING

- Confirm Venworks Core Library and Venworks Canvas are installed and enabled.
- Confirm the add-on supports the installed Canvas version.
- Check whether another Creation replaces the same Player HUD files.
- Reproduce the problem on a disposable save with Canvas and one add-on enabled.
- When reporting a problem, include the exact Canvas and add-on versions, load order, save type, platform, and visible behavior.

DOCUMENTATION FOR PLAYERS

Overview, installation, compatibility, and troubleshooting:
https://github.com/monster-cookie/venworks-canvas#readme

DOCUMENTATION FOR CREATORS

Create a Canvas plugin from scratch:
https://github.com/monster-cookie/venworks-canvas/blob/master/Documentation/CreatingACanvasPlugin.md

Canvas HTML and CSS component gallery:
https://github.com/monster-cookie/venworks-canvas/blob/master/Documentation/CanvasComponentGallery.md

Send data with Canvas datagrams:
https://github.com/monster-cookie/venworks-canvas/blob/master/Documentation/CanvasDatagrams.md

SOCIAL PRESENCE

Join the Venworks Discord Community for discussion, support, and beta feedback:
https://discord.gg/DTbmrJDMxZ

I can also usually be found in the Quarter Onion Games Discord Server:
https://discord.gg/quarteronion

Follow me on X as @monstercookiebd:
https://x.com/monstercookiebd

Follow me on Threads as @monstercookiebd:
https://www.threads.net/@monstercookiebd

SOURCE CODE

The complete source code and documentation are available in the Venworks Canvas GitHub repository:
https://github.com/monster-cookie/venworks-canvas
