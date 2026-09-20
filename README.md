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

The Example package demonstrates an independently installed Canvas consumer.

The Component Gallery is a live cheatsheet and example UI rendered by Canvas from the Gallery's packaged HTML and CSS. Its `Tag | Syntax | Rendered Result` columns place literal HTML beside the result it produces. Examples cover text, lists, buttons, SVG images, reusable content, and sample data such as bound text, visibility, repeated items, and a meter.

Use the mouse wheel, Up/Down arrow keys, or Page Up/Page Down to browse the Gallery. The current development build still needs in-game verification on PC and PS5; these examples describe Canvas's supported HTML/CSS subset and do not imply full web-browser compatibility.

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

Use [Tools/compileScripts.ps1](Tools/compileScripts.ps1) for Papyrus PEX files and [Tools/buildScaleform.ps1](Tools/buildScaleform.ps1) for SWF/GFX files. Both accept `-VariantKeys` to select a variant. Their default outputs publish to the selected staging targets; use each script's `-OutputDirectory` beneath `.work/canvas` when you need isolated candidate outputs. [Tools/createPackages.ps1](Tools/createPackages.ps1) builds and installs the selected archives from current outputs. [Tools/checkRepo.ps1](Tools/checkRepo.ps1) checks configured metadata and artifacts; its `-Committed` mode reads repository staging paths without requiring installed destination values or staging junctions, but still requires the selected local environment file and expected artifacts. Read each script's parameters and side effects before running a build, package, or staging step.

Compilation, package checks, and archive creation establish different evidence from an in-game check. After changing Papyrus behavior, Scaleform rendering, or package contents, test the relevant installed variant on a disposable save and record the visible result separately from build output.
