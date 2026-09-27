# Create a Canvas plugin from scratch

This guide is for Starfield mod creators who want to build an independently packaged Canvas panel. It follows the same boundaries as the shipped Venworks Canvas Example: an ESM registers the panel, a Papyrus script publishes game state, a small Scaleform movie connects the panel to Canvas, and local HTML/CSS defines what the player sees.

The examples target the current Canvas 1.0 development contract. Canvas is a focused game UI renderer, not a web browser, so start with the elements and styles shown in the [Component Gallery](CanvasComponentGallery.md).

## What you will make

```text
Start Game Enabled quest
  -> Papyrus registrar
  -> Canvas registry and data layer
  -> your Scaleform consumer
  -> your HTML and CSS panel
```

Your finished mod should contain:

- One light-master ESM with a Start Game Enabled quest.
- One compiled Papyrus registrar script.
- One Canvas consumer SWF, usually used for both normal and large display modes.
- One local HTML entry document and its CSS, SVG, and included HTML files.
- One BA2 containing the compiled script and Interface files.

The Canvas base package remains a separate requirement. Do not copy Canvas host files into your add-on.

The shipped Example is a working source map for these pieces:

| Piece | Repository source |
| --- | --- |
| Plugin header and records | [`Spriggit/Venworks-Canvas-Example.esm`](../Spriggit/Venworks-Canvas-Example.esm) |
| Quest registrar and state publisher | [ExampleRegistrar.psc](../Papyrus/Venworks/CanvasExamples/ExampleRegistrar.psc) |
| Canvas consumer adapter | [CanvasExample.as](../Scaleform/canvas/actionscript/CanvasExample.as) |
| Effect datagram adapter | [CanvasExampleEffectsAdapter.as](../Scaleform/canvas/actionscript/CanvasExampleEffectsAdapter.as) |
| HTML entry document | [index.html](../Scaleform/canvas/resources/example/index.html) |
| Panel stylesheet | [example.css](../Scaleform/canvas/resources/example/example.css) |
| Scaleform movie manifest | [example.build.xml](../Scaleform/canvas/build/example.build.xml) |
| Build and package mapping | The `EXAMPLE` variant in [sharedConfig.ps1](../Tools/sharedConfig.ps1) |

Use those files to compare structure and lifecycle behavior while giving an independently released add-on its own plugin name, UUID, namespace, records, and package.

## Prerequisites

- Venworks Canvas and Venworks Core Library 2.1.8 or later installed as authoring masters.
- A Starfield plugin editor that can create the quest and bind script properties.
- The Starfield Papyrus compiler with the Starfield, Venworks Core, and Canvas script sources available.
- An ActionScript 3 compiler compatible with the repository's Apache Flex and Player 11.1 build target.
- Archive2 or another packaging workflow that preserves the paths in this guide.
- A new or disposable PC save for the first in-game test.

If you are building this repository's unchanged Example, its configured variant key is `EXAMPLE`. The repository's local setup and build-tool prerequisites are documented in the [maintainer workflow](../README.md#maintainer-and-contributor-workflow).

## 1. Choose permanent identities

Choose these values before creating records or files. They must agree across the ESM, Papyrus properties, SWF registration, and packaged paths.

| Identity | Example used in this guide | Rule |
| --- | --- | --- |
| Plugin file | `Acme-Canvas-Example.esm` | Use a unique filename and do not rename it after release without a migration plan. |
| Papyrus namespace | `Acme:CanvasExample` | Keep every compiled script for this plugin under the same namespace. |
| Asset namespace | `acme.canvas-example` | Use lowercase ASCII letters, digits, dots, and hyphens. This becomes part of the Interface path. |
| Consumer UUID | `your-generated-uuid` | Generate a new UUID once. Never reuse the UUID from the shipped Example or Gallery. |
| Display name | `Acme Canvas Example` | This is the readable name Canvas reports in diagnostics. |
| Descriptor version | `1` | Increase it when an installed update must replace the registered movie descriptor. |

The consumer UUID stored on the quest must exactly match the `consumerId` returned by the SWF. The asset namespace in the SWF must exactly match the folder containing the SWF and HTML resources.

## 2. Create the HTML panel

Create `index.html` and `panel.css` in a local resource folder. This starter displays complete data supplied by the Scaleform consumer; HTML does not read game data by itself.

```html
<!doctype html>
<html>
  <head>
    <title>Acme Canvas Example</title>
    <meta charset="utf-8"></meta>
    <link rel="stylesheet" href="panel.css"></link>
  </head>
  <body>
    <main class="panel">
      <h1>PLAYER STATUS</h1>
      <p data-vw-template="{playername} | LEVEL {playerlevel:integer}"></p>
      <p data-vw-template="HEALTH {health:integer}/{maxhealth:integer}"></p>
      <vw-meter class="health-meter" value="healthpercent"></vw-meter>
    </main>
  </body>
</html>
```

```css
.panel { display: flex; flex-direction: column; width: 460px; margin: 28px 32px; padding: 14px; gap: 8px; color: #e3fdff; background-color: #141414d1; border-width: 1px; border-style: solid; border-color: #3aadfc; font-family: $MAIN_Font_Bold; font-size: 18px; line-height: 26px; }
.panel h1 { margin: 0px; color: #66ffff; font-size: 24px; line-height: 30px; }
.panel p { margin: 0px; }
.health-meter { width: 420px; height: 14px; color: #66ffff; background-color: #26313a; }
```

Keep every linked file beneath your consumer folder. Use relative paths such as `panel.css`, `icons/status.svg`, or `partials/effects.html`; do not use absolute paths, parent-directory traversal, or remote URLs.

## 3. Create the Scaleform consumer

The SWF is the adapter between Canvas and your document. It declares the data it needs, keeps a complete view model, and gives that model to the HTML bridge.

Start from [CanvasExample.as](../Scaleform/canvas/actionscript/CanvasExample.as) when you need a Player HUD panel, or [CanvasComponentGallery.as](../Scaleform/component-gallery/actionscript/CanvasComponentGallery.as) when you need a menu-only panel. Replace every shipped identity with your own.

Your registration should have this shape:

```actionscript
public function getCanvasRegistration() : Object
{
   return {
      "protocol":"VWCANVAS_CONSUMER/3",
      "consumerId":"your-generated-uuid",
      "assetNamespace":"acme.canvas-example",
      "version":1,
      "minimumContractVersion":3,
      "maximumContractVersion":3,
      "hostKinds":["player"],
      "uiChannels":["PlayerData","PlayerFrequentData"],
      "eventSubscriptions":[],
      "marker":"ACME_CANVAS_EXAMPLE"
   };
}

public function getCanvasHtmlRegistration() : Object
{
   return {"contract":"VWCANVAS_HTML/2","entryDocument":"index.html"};
}
```

Canvas calls three fixed callbacks on a current consumer:

| Callback | What your SWF should do |
| --- | --- |
| `handleUIData(channel, data)` | Copy only validated values from a requested game UI channel into your saved view model, then publish the complete model. |
| `handleCanvasEvent(topic, body)` | Decode and validate a subscribed Canvas datagram, commit the complete accepted update, then publish. Leave the previous valid model unchanged when validation fails. |
| `handleLifecycle(state, detail)` | On `ready`, obtain the HTML bridge, set the viewport, and publish the initial model. On `unload`, release the bridge and any timers or listeners. |

Also expose `dispose()` and release the same timers, listeners, and references there. Check that `detail.features` contains `htmlRendering` and that `detail.html` supplies the bridge methods you use before storing it.

Treat `setData()` as a complete document update. Keep values received from different UI channels in one saved object and submit a complete snapshot after each accepted change. Sending a one-field object can remove bindings that were supplied by an earlier update.

The Gallery demonstrates these live mappings:

| UI channel | Useful fields shown by the Gallery |
| --- | --- |
| `PlayerData` | `sName`, `uLevel`, `fLevelXP`, `fNextLevelXP` |
| `PlayerFrequentData` | `fHealth`, `fMaxHealth`, `fOxygen`, `fMaxO2CO2`, `fCarbonDioxide`, `fStarPower`, `fMaxStarPower` |

Validate field presence, type, range, and string length before adding a value to the model. The Gallery's own mappings are in [CanvasComponentGallery.as](../Scaleform/component-gallery/actionscript/CanvasComponentGallery.as).

## 4. Build the consumer movie

Compile the document class as an ActionScript 3 movie targeting the same Player 11.1 runtime as Canvas. The shipped Example manifest is [example.build.xml](../Scaleform/canvas/build/example.build.xml).

Your build must produce a consumer movie, not a second Canvas host. Do not embed Canvas's HTML parser, renderer, subscription manager, or host classes in the consumer SWF. The consumer should contain only its adapter and any small, add-on-owned data helpers.

If one movie adapts to the viewport, package the same SWF as both `normal.swf` and `large.swf`. Use separate builds only when the two display modes genuinely require different movies.

## 5. Create the Papyrus registrar

Create a Start Game Enabled quest and attach a registrar script that extends `Venworks:Canvas:Base:BaseQuest`. The registration-only [ComponentGalleryRegistrar.psc](../Papyrus/Venworks/CanvasComponentGallery/ComponentGalleryRegistrar.psc) is the best baseline for a new add-on. The larger [ExampleRegistrar.psc](../Papyrus/Venworks/CanvasExamples/ExampleRegistrar.psc) adds effect discovery, complete-state datagrams, recovery refreshes, and diagnostics specific to the shipped Example.

Rename the script namespace and its module name, then retain these behaviors from the baseline:

1. Register for `HUDMenu` open/close events in `OnInit()` and schedule the first registration attempt without an arbitrary startup delay.
2. Call `Registry.TryRegisterConsumer(Self, ConsumerId, DisplayName, NormalMoviePath, LargeMoviePath, DescriptorVersion)`.
3. Treat `REGISTRATION_ACCEPTED`, `REGISTRATION_UPDATED`, and `REGISTRATION_UNCHANGED` as stored registrations.
4. After a stored registration that needs an immediate load, call `Registry.TryRequestUiLoad(Self, ConsumerId)` outside any registrar guard.
5. Retry only deferred results, keep the input for the retry, and stop after a bounded number of attempts.
6. Log the returned operation receipts after guards have been released. A successful receipt is not proof that the panel rendered.

Bind these quest properties:

| Property | Value for this guide |
| --- | --- |
| `Registry` | The `VWCANVAS_Registry` quest from `Venworks-Canvas.esm` |
| `ConsumerId` | Your permanent UUID |
| `DisplayName` | `Acme Canvas Example` |
| `NormalMoviePath` | `VenworksCanvas/Consumers/acme.canvas-example/normal.swf` |
| `LargeMoviePath` | `VenworksCanvas/Consumers/acme.canvas-example/large.swf` |
| `DescriptorVersion` | `1` |
| `ExpectedRegistration` | `True` |
| `InitialDelaySeconds` | `0.0`; retained by the current baseline for saved-script compatibility and not used as a startup delay |

For the exact shipped Example, also create its buff and debuff FormLists and matching label arrays. Keep the list and label order aligned. Those records are application-specific and are not required by Canvas itself.

## 6. Add mod-owned data

Use Canvas UI channels for data already supplied by the game UI. Use Canvas datagrams for a complete state or occurrence produced by your Papyrus code.

For example, a Papyrus publisher can send a complete panel state:

```papyrus
OperationResult result = Registry.TryPublishCanvasDatagram(
  "acme.canvas-example.status",
  "panel.state",
  1,
  "ci-ascii",
  "ready|42"
)
Registry.LogOperation(result)
```

Add the topic to the SWF registration when you use it:

```actionscript
"eventSubscriptions":[
   {"topic":"acme.canvas-example.status","startup":"latest"}
]
```

Decode the body with `CanvasDatagramCodec.decode(body)`, confirm `messageType`, `schemaVersion`, `encoding`, and your payload fields, then update the saved view model. See [Canvas datagrams](CanvasDatagrams.md) for the creator-friendly delivery rules and startup choices.

## 7. Author the ESM

Create a light master with these masters:

- `Starfield.esm`
- `Venworks-Core.esm`
- `Venworks-Canvas.esm`

Add one quest, mark it Start Game Enabled and Starts Enabled, attach your compiled registrar, and fill every mandatory property. The shipped Example uses local Form ID `000800`, but your plugin can use its own valid local form IDs; never assume another add-on's local IDs belong to your plugin.

Save the plugin, reopen it in your authoring tool, and verify the masters, quest flags, script name, and every bound property before packaging.

## 8. Package the files

The installed layout must resolve to these paths:

```text
Data/
  Acme-Canvas-Example.esm
  Acme-Canvas-Example - Main.ba2

Acme-Canvas-Example - Main.ba2
  Scripts/Acme/CanvasExample/Registrar.pex
  Interface/VenworksCanvas/Consumers/acme.canvas-example/normal.swf
  Interface/VenworksCanvas/Consumers/acme.canvas-example/large.swf
  Interface/VenworksCanvas/Consumers/acme.canvas-example/index.html
  Interface/VenworksCanvas/Consumers/acme.canvas-example/panel.css
```

Keep source files out of the player package unless you intentionally distribute a separate source archive. Do not place loose copies of packaged Interface or Script files beside the BA2; loose files can shadow the archive during testing.

When rebuilding this repository's shipped Example, the configured commands are:

```powershell
pwsh -NoProfile -File .\Tools\compileScripts.ps1 -VariantKeys EXAMPLE
pwsh -NoProfile -File .\Tools\buildScaleform.ps1 -VariantKeys EXAMPLE
pwsh -NoProfile -File .\Tools\createPackages.ps1 -VariantKeys EXAMPLE
```

These commands require the repository's local `.env`, authoring tools, verified staging junction, and configured module destination. Read the [build workflow](../README.md#build-workflow) before running them. A separate add-on repository needs equivalent build configuration for its own namespace and files; do not add a third-party variant to Canvas merely to package an unrelated mod.

## 9. Test in increasing scope

Test each layer separately so a packaging success is not mistaken for a visible result.

1. Inspect the ESM after saving and confirm its masters, quest, script, and properties.
2. Compile the registrar with no Papyrus errors.
3. Compile the SWF and confirm the movie contains your own UUID, namespace, contract, callbacks, and HTML registration.
4. Inspect the BA2 and confirm every file uses the exact packaged path.
5. Install Canvas plus only your add-on on a disposable save.
6. Open the Player HUD and confirm the initial HTML appears.
7. Change or trigger each data source and confirm the visible values update.
8. Close and reopen the HUD, load the save again, and confirm there is still one panel rather than duplicate loaders.
9. Test normal and large interface modes separately.

For every failure, record the Canvas version, add-on version, package order, save type, display mode, visible behavior, and relevant Canvas/Papyrus log lines. A registration or `EVENT_SUBMITTED` result confirms only that the request was accepted at that boundary; it does not confirm delivery or rendering.

## Common mistakes

- Reusing the shipped Example or Gallery UUID.
- Letting the ESM UUID, SWF UUID, namespace, movie paths, or descriptor version disagree.
- Expecting HTML bindings to read game state without the consumer calling `setData()`.
- Sending partial `setData()` objects and accidentally removing earlier values.
- Treating `ci-ascii` payload text as case preserving.
- Using one topic for both current state and replayable occurrences even though they need different startup behavior.
- Loading remote assets, JavaScript, browser APIs, forms, navigation, or unsupported CSS.
- Packaging a second copy of Canvas host classes inside the consumer SWF.
- Claiming gameplay success from source inspection, compilation, or archive contents alone.
