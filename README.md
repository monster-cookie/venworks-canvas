# Venworks Canvas

Venworks Canvas is a shared Starfield Player HUD framework used by compatible Venworks UI packages. It provides the common HUD host required by participating add-ons.

## Packages

| Package | Purpose | Required |
| --- | --- | --- |
| Venworks Canvas | Base runtime and shared HUD host | Yes |
| Venworks Canvas Example | Optional example consumer | No |
| Venworks Canvas Component Gallery | Optional preview of Canvas HTML/CSS components | No |

Install the base Canvas package before any package that lists Canvas as a requirement. The Example and Component Gallery are separate optional packages and are not included in the base runtime.

## Installation

Install and enable Venworks Canvas with your normal Starfield mod manager. Keep the Canvas base package and participating add-ons on mutually compatible versions.

Canvas owns several Player HUD files. Another mod that replaces the same complete HUD files can overwrite Canvas or be overwritten by it according to package and load order. Do not combine competing full-HUD replacements unless the package authors provide an explicit compatibility patch.

Start with a new or disposable save when evaluating a new Canvas build. Existing saves and independently packaged add-ons are not automatically migrated when a package changes its registration or files.

## Optional examples

The Example package demonstrates an independently installed Canvas consumer.

The Component Gallery is the example documentation for the Canvas HTML/CSS surface. Each gallery entry presents its source followed by the control produced from that source. The current development build can load and parse the Gallery document, but CSS evaluation, data binding, layout, and visible native rendering are still under development; do not install the current Gallery expecting a completed visible catalog.

## Current compatibility

- Current work targets the Player HUD. Ship HUD and pilot-seat delivery are not accepted yet.
- The vanilla Watch presentation is disabled while Canvas uses its underlying data path.
- PS5 acceptance remains pending a player-visible Canvas build and hardware testing.
- Event submission is not proof that a consumer displayed an event. Player-visible behavior must be confirmed in game.

## Troubleshooting

If a Canvas add-on does not appear:

1. Confirm the Canvas base package is installed and enabled.
2. Confirm the add-on version supports the installed Canvas version.
3. Check for another package replacing the same Player HUD files.
4. Reproduce the problem on a disposable save with Canvas and one add-on enabled.
5. Report the exact Canvas/add-on versions, package order, save type, and visible behavior to the package maintainer.
