# Venworks Canvas

Venworks Canvas is a shared Starfield Player HUD framework used by compatible Venworks UI packages. It provides the common HUD host required by participating add-ons.

## Packages

| Package | Purpose | Required |
| --- | --- | --- |
| Venworks Canvas | Base runtime and shared HUD host | Yes |
| Venworks Canvas Example | Optional example consumer | No |
| Venworks Canvas Component Gallery | Optional live cheatsheet of Canvas HTML/CSS examples | No |

Install the base Canvas package before any package that lists Canvas as a requirement. The Example and Component Gallery are separate optional packages and are not included in the base runtime.

## Installation

Install and enable Venworks Canvas with your normal Starfield mod manager. Keep the Canvas base package and participating add-ons on mutually compatible versions.

Canvas owns several Player HUD files. Another mod that replaces the same complete HUD files can overwrite Canvas or be overwritten by it according to package and load order. Do not combine competing full-HUD replacements unless the package authors provide an explicit compatibility patch.

Start with a new or disposable save when evaluating a new Canvas build. Existing saves and independently packaged add-ons are not automatically migrated when a package changes its registration or files.

## Optional examples

The Example package demonstrates an independently installed Canvas consumer. Its Papyrus registrar publishes status-effect snapshots; a Canvas-side adapter commits complete snapshots, and the Example's packaged HTML/CSS renders the clock, buff and debuff counts, pending or empty states, and effect rows. When more than eight effects are active, the view rotates through every page every six seconds.

The Component Gallery is a live cheatsheet and example UI rendered by Canvas from the Gallery's packaged HTML and CSS. Its `Tag | Syntax | Rendered Result` columns place literal HTML beside the result it produces. Examples cover text, lists, buttons, SVG images, reusable content, and sample data such as bound text, visibility, repeated items, and a meter.

Use the mouse wheel, Up/Down arrow keys, or Page Up/Page Down to browse the Gallery. The current development build still needs in-game verification on PC and PS5; these examples describe Canvas's supported HTML/CSS subset and do not imply full web-browser compatibility.

### HTML data binding for repeated rows

Canvas HTML contract `VWCANVAS_HTML/2` supports `data-vw-for-each` on `div` and `li`. Give it the name of an array in `setData`; Canvas repeats the element for each item and resolves bindings inside it with the same item scope as `vw-repeat`. Object items expose their properties, while scalar items expose `item`. Missing arrays render no rows; non-array values and arrays over 256 items are rejected by the existing binding limits. `vw-repeat` remains supported for repeating a group of child elements.

```html
<div data-vw-for-each="effects" data-vw-text="label"></div>
```

The Example sends only the current eight-row page to the HTML bridge. Its effect arrays remain separate from clock values, and the bridge receives updates after complete effect snapshots, accepted removals, page changes, or a visible clock-minute change. A published Papyrus event and a compiled package still require an in-game display check.

Canvas event topics are ASCII case insensitive and are delivered to consumers in lowercase. The native Custom Watch alert transport can also change ASCII casing inside event bodies, so application protocols must use case-insensitive ASCII or a case-safe encoding.

[Canvas datagrams](Documentation/CanvasDatagrams.md) provide a generic atomic envelope with a stream topic, application message type, independent schema version, encoding, and opaque payload. Canvas does not enumerate application packet types, add ordering metadata, or interpret payload semantics. A small number of subscribed streams can therefore carry any number of mod-owned message types such as status state, GPS samples, and combat occurrences.

`VWCANVAS_CONSUMER/3` assigns a `drop`, `latest`, or `fifo` startup policy to each subscribed stream. `latest` retains one queued datagram per message type, schema version, and encoding in that stream, including valid state received before the consumer SWF establishes its membership. `fifo` preserves bounded occurrence traffic after membership exists. Existing `VWCANVAS_CONSUMER/2` registrations remain supported: `queueEventsUntilReady: false` maps to `drop`, and `true` maps to `fifo`.

On Player HUD activation, Canvas replays saved consumer descriptors from its registry in bounded atomic load batches. The host validates the entire batch and begins loading its consumers concurrently. A newly installed or updated consumer still uses the existing individual load command after registration; consumer registrars should register without an arbitrary startup delay so later HUD recreations can use the central replay path.

## Current compatibility

- Current work targets the Player HUD. Ship HUD and pilot-seat delivery are not accepted yet.
- Canvas renders its own procedural Chronomark surface from ordinary HUD providers; patched Player HUD outputs structurally exclude the native Watch UI. Custom Watch alerts remain reserved for Canvas data-layer transport and are not rendered by the Chronomark surface.
- PS5 acceptance remains pending a player-visible Canvas build and hardware testing.
- Event submission is not proof that a consumer displayed an event. Player-visible behavior must be confirmed in game.

## Troubleshooting

If a Canvas add-on does not appear:

1. Confirm the Canvas base package is installed and enabled.
2. Confirm the add-on version supports the installed Canvas version.
3. Check for another package replacing the same Player HUD files.
4. Reproduce the problem on a disposable save with Canvas and one add-on enabled.
5. Report the exact Canvas/add-on versions, package order, save type, and visible behavior to the package maintainer.

## Maintainer and contributor workflow

Work from the repository root with PowerShell 7. [Tools/sharedConfig.ps1](Tools/sharedConfig.ps1) defines the `CANVAS`, `EXAMPLE`, and `COMPONENTGALLERY` variants, their Papyrus namespaces, Scaleform jobs, and package contents. Edit sources under `Papyrus/` and `Scaleform/`; use the configured tools to produce build outputs rather than treating generated files as source.

### Local setup

Build scripts load a local `.env` file by default, or another file selected with `-EnvironmentPath`. Keep that file and `.work/` local; both are ignored by Git. The first successful configuration load in a PowerShell process is reused by later script calls, so start a fresh process when selecting a different environment file. Never put credentials or machine-specific paths in tracked documentation or source files.

Papyrus compilation requires `TOOL_PATH_PAPYRUS_COMPILER`, `PAPYRUS_COMPILER_FLAGS`, and `PAPYRUS_SCRIPTS_SOURCE_PATH` in the selected local environment. Packaging also requires `TOOL_PATH_ARCHIVER`. Publishing to a module requires the corresponding `MODULE_VARIANT_CANVAS_PATH`, `MODULE_VARIANT_EXAMPLE_PATH`, or `MODULE_VARIANT_COMPONENT_GALLERY_PATH` and a verified staging junction prepared with [Tools/setupRepo.ps1](Tools/setupRepo.ps1). Inspect that script before running it because it changes local junctions.

Canvas Scaleform builds use the pinned local JDK, JPEXS, Apache Flex, and Player 11.1 inputs checked by [Tools/VerifyPipelineTooling.ps1](Tools/VerifyPipelineTooling.ps1). [Tools/InstallPipelineTooling.ps1](Tools/InstallPipelineTooling.ps1) can provision missing inputs into `.work/tools`; it may download archives and requires acceptance of the Adobe license when extracting the Player 11.1 library. Patch jobs also require matching vanilla Interface movies supplied through `-VanillaInterfacePath`.

### Prepare staging

Set the selected variant's `MODULE_VARIANT_*_PATH` value to its intended physical module folder before publishing files. Run `pwsh -NoProfile -File .\Tools\setupRepo.ps1 -VariantKeys CANVAS` for the Canvas base variant, or substitute `EXAMPLE` or `COMPONENTGALLERY`. The script validates the selected paths, creates a missing physical folder and its repository staging junction, and rejects an ordinary directory or wrong junction already occupying the staging path. Skip this step when building only to an isolated `-OutputDirectory` beneath `.work/canvas`.

### Build workflow

Verify the pinned Scaleform tools with `pwsh -NoProfile -File .\Tools\VerifyPipelineTooling.ps1` before a native Scaleform build. Compile Papyrus and build Scaleform with the actual configured toolchain when those sources change; a source pattern or separate fixture cannot establish the behavior of the compiled output.

Use [Tools/compileScripts.ps1](Tools/compileScripts.ps1) for Papyrus PEX files and [Tools/buildScaleform.ps1](Tools/buildScaleform.ps1) for SWF/GFX files. Both accept `-VariantKeys` to select a variant. Their default outputs publish temporary loose inputs to the selected staging targets; use each script's `-OutputDirectory` beneath `.work/canvas` when you need isolated candidate outputs. [Tools/createPackages.ps1](Tools/createPackages.ps1) builds and installs the selected archives from current outputs, verifies the installed ESM and BA2 files, and then removes every matching loose archive payload so Starfield cannot shadow the archive with a staged copy. If installation, verification, or cleanup fails, the transaction restores the prior package and prior loose inputs. A later package run must recreate the needed loose inputs or receive them through `-ScriptsDirectory` and `-ScaleformDirectory`. [Tools/checkRepo.ps1](Tools/checkRepo.ps1) checks configured metadata and artifacts and rejects archive-shadowing loose payloads; its `-Committed` mode reads repository staging paths without requiring installed destination values or staging junctions, but still requires the selected local environment file and expected artifacts. Read each script's parameters and side effects before running a build, package, or staging step.

Compilation, package checks, and archive creation establish different evidence from an in-game check. After changing Papyrus behavior, Scaleform rendering, or package contents, test the relevant installed variant on a disposable save and record the visible result separately from build output.

### In-game environmental weather checks

Install the Canvas build under test and, when checking status-effect rows, the optional Example package. Use a disposable PC save, stand outdoors, and set **Settings > Gameplay > Environmental Damage & Afflictions** to Normal or Advanced. Console use can affect achievements and create a separate save path. Check the character Status menu, suit-protection warnings, and the Canvas HUD after each command; a changed sky alone does not establish that an environmental effect reached the player.

`forceweather <weather ID>` (alias `fw`) switches the current weather immediately. Try these base-game weather records one at a time; the planet and location determine whether a weather condition also applies a hazard to the player.

| Weather | Command | Candidate observation |
| --- | --- | --- |
| Rain | `forceweather 000C3048` | Rain-related status on a planet that supports it |
| Heavy rain | `forceweather 000C3049` | Stronger rain and any associated status |
| Sandstorm | `forceweather 000C304A` | Airborne exposure or poor air quality |
| Heavy sandstorm | `forceweather 000C304B` | Stronger sandstorm and any associated status |
| Snow | `forceweather 000C304C` | Cold exposure |
| Heavy snow | `forceweather 000C304D` | Stronger snow and cold exposure |
| Thunderstorm | `forceweather 000C304E` | Storm visuals and any associated alerts |
| Clear | `forceweather 0002B07E` | Clear-weather comparison after a test |

There is no verified `forceweather` option here that guarantees radiation exposure. Test solar radiation outdoors on a planet that has that planetary hazard; `set gamehour to 12` can move the test to noon, but does not create radiation. If a weather command changes only the sky, move to a planet or location that naturally supports the desired condition and check the Status menu again. Use `setweather <weather ID>` when testing the gradual weather transition instead of the immediate switch.

For a direct diagnostic of a named weather status, use `player.addspell <spell ID>`, then `player.removespell <same spell ID>` before trying the next one. These commands test a spell on the player; they do not establish that weather naturally applied it or that the complete suit-protection and alert lifecycle ran. The following IDs are base-game `SPEL` records:

| Named weather status | Spell ID |
| --- | --- |
| Freezing Rain | `001639EB` |
| Corrosive Rain | `00281ECB` |
| Scalding Rain | `00281ECD` |
| Freezing Cold and Snow | `00163A02` |
| Intense Heat | `00163A03` |
| Poor Air Quality | `00163FE7` |
| Corrosive Particulates | `00163A05` |
| Corrosive Vapor | `001639F8` |
| Freezing Vapor | `001639F9` |
| Scalding Vapor | `00163A00` |

For example, enter `player.addspell 00281ECB`, inspect the result, then enter `player.removespell 00281ECB`. The [Example registrar](Papyrus/Venworks/CanvasExamples/ExampleRegistrar.psc) explicitly recognizes Corrosive Rain as a named weather-status row; other weather spells are useful for checking native environmental behavior but do not by themselves promise an Example row.

Use `help "Corrosive Rain" 4 SPEL` or `help "Weather_Rain" 4 WTHR` to check IDs in the installed game. Compare `player.getav ENV_Damage_Soak` before and after exposure to inspect the player's suit-protection value. Return to shelter or reload the disposable save to check that naturally applied effects clear; `forceweather 0002B07E` only supplies a clear-weather comparison.

Weather IDs are listed in the [Starfield weather guide](https://framedsc.com/GameGuides/starfield.htm); spell IDs and names can be checked against [Starfield game-record data](https://rrryutaro.hatenablog.com/entry/2023/10/15/151155) and the [Starfield Community Patch's environmental-weather record list](https://github.com/Starfield-Community-Patch/Starfield-Community-Patch/issues/1142). Bethesda's [planetary-effects guide](https://help.bethesda.net/app/answers/detail/a_id/61498/) describes the environmental behavior to observe.
