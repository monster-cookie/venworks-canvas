# Canvas HTML and CSS component gallery

The Canvas Component Gallery is a live in-game reference for mod creators. Every row pairs a supported tag or binding with the exact document syntax and the result Canvas rendered from it.

The images on this page are lossless section crops from the supplied in-game captures. They are split at the Gallery's actual section boundaries so each image supports the table beside it; the original full-page screenshots are not used as document pages.

These captures show one PC run of the Gallery. They document the visible result of that captured build, but they do not verify this checkout or establish broader PC or PS5 acceptance.

## Open the in-game Gallery

Install and enable both the Venworks Canvas base package and the optional Venworks Canvas Component Gallery package. Open the Gallery from the Pause Menu, then use Up/Down, the right stick, the mouse wheel, or the scrollbar to browse. Cancel returns to the Pause Menu.

The Gallery is an authoring reference and separate example package. Players do not need it for another Canvas add-on unless that add-on explicitly lists it as a requirement.

## Read a Gallery row

| Column | Meaning |
| --- | --- |
| Tag | The supported HTML element, Canvas component, binding, or Gallery data key. |
| Syntax | The exact declarative syntax used by the Gallery document. |
| Rendered result | What the captured Gallery displayed from that syntax and its sample data. |

## Write tags in lowercase

Canvas matches the preamble and every element name exactly. Each HTML or SVG document, including a file loaded with `vw-include`, must begin with `<!doctype html>`. Element names are lowercase: `<html>`, `<div>`, `<svg>`, `<vw-hud-target>`. `<!DOCTYPE html>`, `<HTML>`, and `<Div>` fail parsing as malformed syntax at the first differing byte. Attribute names are lowercase too. `viewBox` is the one accepted exception, and Canvas treats it as `viewbox`. Paint keywords are lowercase as well: `none`, `currentcolor`, and `transparent`. `currentColor` is rejected. Text inside an element keeps the case you write.

## Text and document flow

![Lossless crop of the Text and Document Flow Gallery table from H1 through DIV](Images/ComponentGallery/text-and-document-flow.png)

![Lossless continuation crop of the Text and Document Flow Gallery table for lists and button](Images/ComponentGallery/lists-and-button.png)

| Tag | Syntax | Rendered result |
| --- | --- | --- |
| `h1` | `<h1 class="demo-h1">My First Heading</h1>` | Large `MY FIRST HEADING` text. |
| `h2` | `<h2 class="demo-h2">Section Heading</h2>` | `SECTION HEADING` text. |
| `h3` | `<h3 class="demo-h3">Topic Heading</h3>` | `TOPIC HEADING` text. |
| `h4` | `<h4 class="demo-h4">Detail Heading</h4>` | `DETAIL HEADING` text. |
| `h5` | `<h5 class="demo-h5">Minor Heading</h5>` | `MINOR HEADING` text. |
| `h6` | `<h6 class="demo-h6">Small Heading</h6>` | `SMALL HEADING` text. |
| `p` | `<p>Canvas renders paragraph text.</p>` | One paragraph reading `CANVAS RENDERS PARAGRAPH TEXT.` |
| `span` | `<p>Text with a <span class="demo-accent">highlight</span>.</p>` | Paragraph text with `HIGHLIGHT` styled in amber. |
| `br` | `<p>First line<br></br>Second line</p>` | `FIRST LINE` and `SECOND LINE` on separate lines. |
| `hr` | `<hr></hr>` | A horizontal rule. |
| `div` | `<div class="demo-panel"><p>Grouped content</p></div>` | `GROUPED CONTENT` inside a bordered panel. |
| `ul` / `li` | `<ul><li>Alpha</li><li>Beta</li></ul>` | A bulleted `ALPHA`, `BETA` list. |
| `ol` / `li` | `<ol><li>First</li><li>Second</li></ol>` | A numbered `FIRST`, `SECOND` list. |
| `button` | `<button class="demo-button">Continue</button>` | A cyan `CONTINUE` button surface. |

The button row demonstrates rendering only. Canvas does not turn arbitrary HTML into browser-style form handling; add-on behavior still belongs in the consumer.

## Structure, assets, and reusable components

![Lossless crop of the Structure, Assets and Reusable Components Gallery table](Images/ComponentGallery/structure-assets-reusable-components.png)

| Tag | Syntax | Rendered result |
| --- | --- | --- |
| `section` | `<section class="demo-panel"><p>Section content</p></section>` | `SECTION CONTENT` inside a bordered panel. |
| `img` with SVG | `<img class="demo-image" src="gallery-icon.svg" alt="Canvas gallery icon"></img>` | The packaged Gallery SVG displayed as a white square. |
| `svg` / `path` | `<svg class="demo-svg" viewbox="0 0 16 16"><path d="M 1 1 L 15 1 L 15 15 L 1 15 Z" fill="#66ffff"></path></svg>` | A cyan square rendered from the inline path. |
| `template` / `vw-use` | `<template id="sampletemplate"><p>Reusable content</p></template><vw-use template="#sampletemplate"></vw-use>` | The template instance displays `REUSABLE CONTENT`. |
| `vw-include` | `<vw-include src="include-example.html"></vw-include>` | The packaged include displays `LOADED FROM INCLUDE-EXAMPLE.HTML`. |

Keep all consumer-owned images, stylesheets, includes, entry documents, and consumer SWFs beneath the fixed loader root `Interface/VenworksCanvas/Consumers/<your-namespace>/`. Registration URLs omit the leading `Interface/`. This directory does not contain copied Canvas framework files; Canvas rejects absolute paths, parent-directory traversal, remote URLs, and custom resource roots.

## HUD artwork and live meters

Canvas HTML/2 accepts standard inline SVG elements including `path`, `rect`, `circle`, `ellipse`, `polygon`, `polyline`, and bounded `g` transforms. The same geometry and styling rules apply to packaged `.svg` images. Use SVG `fill` and `stroke` attributes or the matching CSS properties.

```html
<svg viewBox="0 0 320 64">
  <g transform="translate(4 4)" fill="#061722" stroke="#2dcbff" stroke-width="2">
    <path d="M 16 0 L 296 0 Q 312 0 312 16 L 312 40 C 312 52 300 56 288 56 L 16 56 Q 0 56 0 40 L 0 16 Q 0 0 16 0 Z"></path>
    <circle cx="28" cy="28" r="12" fill="#2dcbff"></circle>
  </g>
</svg>
```

Meters accept an explicit numeric range, fill direction, segment count, gap, and partial-segment behavior. Existing meters without these attributes retain their prior 0–1 behavior and also accept percentage values above 1.

```html
<vw-meter class="health" value="player.healthpercentage" min="0" max="100" direction="right" segments="16" gap="2" partial="true"></vw-meter>
```

Valid directions are `right`, `left`, `up`, and `down`. Set `partial="false"` when only complete segments should fill.

## Position and stacking

![Lossless crop of the Position and Stacking Gallery table](Images/ComponentGallery/position-and-stacking.png)

| Tag | Syntax | Rendered result |
| --- | --- | --- |
| `position` / `z-index` | `<div class="demo-position-stage"><div class="demo-position-back">Back layer</div><div class="demo-position-front">Front layer</div></div>` with a relative stage and two absolutely positioned children using `z-index: 1` and `z-index: 2` | The cyan `FRONT LAYER` overlaps the blue `BACK LAYER`. |

The exact Gallery CSS is:

```css
.demo-position-stage { position: relative; width: 420px; height: 110px; }
.demo-position-back { position: absolute; left: 20px; top: 20px; z-index: 1; }
.demo-position-front { position: absolute; left: 160px; top: 42px; z-index: 2; }
```

A static parent is valid. Canvas places the absolute element against the nearest ancestor whose position is `relative` or `absolute`. When every ancestor is static, the viewport is the containing block. `data-vw-anchor` is separate and still requires the anchored element itself to be `position: absolute`.

## Safe-area placement and presentation bindings

Use `data-vw-anchor` on absolutely positioned content to attach it to `top-left`, `top-center`, `top-right`, `center-left`, `center`, `center-right`, `bottom-left`, `bottom-center`, or `bottom-right` in the host safe area. CSS offsets remain in Canvas's 1920×1080 design space.

```html
<div class="status-panel" data-vw-anchor="bottom-right">Status</div>
```

Bind live position and presentation values from the consumer's current data snapshot. Canvas validates finite values and bounded ranges before changing the display.

```html
<div data-vw-x="marker.x" data-vw-y="marker.y" data-vw-rotation="marker.rotation" data-vw-opacity="marker.opacity" data-vw-scale="marker.scale">Contact</div>
```

An image can select only from the packaged paths declared by `data-vw-assets`.

```html
<img src="icons/default.svg" data-vw-asset="theme.icon" data-vw-assets="icons/default.svg icons/alert.svg"></img>
```

## Semantic HUD targets and native symbols

Player and ship consumers can declare presentation suppression with stable target names instead of Bethesda display-object paths. `disabled="true"` hides the target and suspends Canvas-owned work for targets such as the custom watch. CSS `visibility: hidden` and `display: none` suppress the declaration's presentation.

```html
<vw-hud-target target="player.crosshair" disabled="true"></vw-hud-target>
<vw-hud-target target="player.meters" disabled="true"></vw-hud-target>
<vw-hud-target target="ship.reticle" disabled="true"></vw-hud-target>
<vw-hud-target target="canvas.watch" disabled="true"></vw-hud-target>
```

Use `player.all` or `ship.all` only when the consumer intentionally suppresses every cataloged surface for that host. Canvas combines requests from multiple consumers, never forces an engine-hidden object visible, and releases one consumer's requests on replacement, failure, or unload. Disabling presentation does not disable game actions, shared event delivery, or vanilla scripts.

Approved host artwork is exposed through named symbols. The current names are `vehicle-exit-prompt`, `weapon-icon`, and `compass-marker`.

```html
<vw-symbol name="vehicle-exit-prompt"></vw-symbol>
<vw-symbol name="weapon-icon" value="weapon.icon"></vw-symbol>
<vw-symbol name="compass-marker" value="marker"></vw-symbol>
```

Canvas copies the approved artwork into the consumer. The native control retains its placement and input ownership. A missing target or unsupported symbol produces a contained render diagnostic.

## Canvas data layer

![Lossless crop of the Canvas Data Layer Gallery table](Images/ComponentGallery/canvas-data-layer.png)

| Binding or component | Syntax | Captured result |
| --- | --- | --- |
| `data-vw-text` | `<p data-vw-text="sampletext"></p>` | `BOUND THROUGH CANVAS DATA` |
| `data-vw-format` | `<p data-vw-text="sampleformat" data-vw-format="Score: {value}"></p>` | `SCORE: 42` |
| `data-vw-template` | `<p data-vw-template="Score: {sampleformat:integer}"></p>` | `SCORE: 42` |
| `setData` sample | `<p data-vw-text="sampleupdates"></p>` | `MENU-LOCAL SAMPLE DATA` |
| `data-vw-visible` | `<div data-vw-visible="samplevisible">Visible when true</div>` | `VISIBLE WHEN TRUE` because the sample value is true. |
| `vw-state` | `<vw-state when="samplevisible"><p>Active state</p></vw-state>` | `ACTIVE STATE` because the sample value is true. |
| Event `vw-state` | `<vw-state name="pingstate" event="venworks.canvas.example.ping"><p>Ping event activated this state</p></vw-state>` | `PING EVENT ACTIVATED THIS STATE` after the Gallery dispatches its sample event. |
| `vw-repeat` | `<vw-repeat items="sampleitems"><p>Repeated item</p></vw-repeat>` | Three `REPEATED ITEM` rows for the three sample items. |
| `data-vw-for-each` | `<div data-vw-for-each="sampleitems" data-vw-text="item"></div>` | `ALPHA ITEM`, `BETA ITEM`, and `GAMMA ITEM`. |
| `vw-meter` | `<vw-meter class="demo-meter" value="samplemeter"></vw-meter>` | A meter filled to the sample value of 72. |

The consumer owns the values. It obtains the HTML bridge during lifecycle `ready`, keeps a complete view model, and calls `setData(model)` after an accepted change. Calling `setData()` synchronously validates and applies the document's complete bound state, so publish the full model rather than a one-field patch. Canvas retains compatible display objects during data-only updates; if validation rejects a snapshot, `setData()` throws and the last valid display remains.

Object items used by `data-vw-for-each` expose their properties. Scalar items expose `item`. A missing array renders no rows. The current binding limit rejects a non-array value or an array containing more than 256 items.

## Live player placeholders

![Lossless crop of the live player-value rows in the Gallery](Images/ComponentGallery/live-player-values.png)

![Lossless crop of the player template rows in the Gallery](Images/ComponentGallery/live-player-templates.png)

The Gallery adapter subscribes to `PlayerData` and `PlayerFrequentData`, validates selected game fields, and supplies these keys to its own document. The captured numbers below are examples from that play session, not fixed values.

| Gallery key | Syntax | Captured result |
| --- | --- | --- |
| `player.name` | `<p data-vw-text="player.name"></p>` | `VENPI DE LOSTE` |
| `player.level` | `<p data-vw-text="player.level"></p>` | `150` |
| `player.levelxp` | `<p data-vw-text="player.levelxp"></p>` | `15134.5` |
| `player.nextlevelxp` | `<p data-vw-text="player.nextlevelxp"></p>` | `19195` |
| `player.xppercentage` | `<p data-vw-text="player.xppercentage"></p>` | `78.84605365980725` |
| `player.health` | `<p data-vw-text="player.health"></p>` | `3057` |
| `player.maxhealth` | `<p data-vw-text="player.maxhealth"></p>` | `3057` |
| `player.healthpercentage` | `<p data-vw-text="player.healthpercentage"></p>` | `100` |
| `player.oxygen` | `<p data-vw-text="player.oxygen"></p>` | `105` |
| `player.maxoxygen` | `<p data-vw-text="player.maxoxygen"></p>` | `105` |
| `player.oxygenpercentage` | `<p data-vw-text="player.oxygenpercentage"></p>` | `100` |
| `player.carbondioxide` | `<p data-vw-text="player.carbondioxide"></p>` | `0` |
| `player.carbondioxidepercentage` | `<p data-vw-text="player.carbondioxidepercentage"></p>` | `0` |
| `power.current` | `<p data-vw-text="power.current"></p>` | `60` |
| `power.maximum` | `<p data-vw-text="power.maximum"></p>` | `60` |
| `power.percentage` | `<p data-vw-text="power.percentage"></p>` | `100` |
| Identity template | `<p data-vw-template="{player.name} \| LEVEL {player.level:integer}"></p>` | `VENPI DE LOSTE \| LEVEL 150` |
| XP template | `<p data-vw-template="XP {player.levelxp:integer}/{player.nextlevelxp:integer}"></p>` | `XP 15135/19195` |
| Health template | `<p data-vw-template="HEALTH {player.health:integer}/{player.maxhealth:integer}"></p>` | `HEALTH 3057/3057` |
| O2 template | `<p data-vw-template="O2 {player.oxygen:integer}/{player.maxoxygen:integer}"></p>` | `O2 105/105` |
| CO2 template | `<p data-vw-template="CO2 {player.carbondioxide:integer} ({player.carbondioxidepercentage:percent})"></p>` | `CO2 0 (0%)` |
| Power template | `<p data-vw-template="POWER {power.current:integer}/{power.maximum:integer}"></p>` | `POWER 60/60` |

These keys are the Gallery's view model, not automatic global variables available to every Canvas document. To use the same information, request the relevant UI channels in `getCanvasRegistration()`, validate the source fields, store the values in your own model, and publish the complete model through the HTML bridge.

| UI channel | Fields used by the Gallery |
| --- | --- |
| `PlayerData` | `sName`, `uLevel`, `fLevelXP`, `fNextLevelXP` |
| `PlayerFrequentData` | `fHealth`, `fMaxHealth`, `fOxygen`, `fMaxO2CO2`, `fCarbonDioxide`, `fStarPower`, `fMaxStarPower` |

The Gallery calculates percentage keys from the matching current and maximum values and clamps each result to 0-100. The implementation is in [CanvasComponentGallery.as](../Scaleform/component-gallery/actionscript/CanvasComponentGallery.as).

## Supported scope

Use the Gallery as the visible compatibility reference for Canvas's supported subset. Do not assume browser behavior, JavaScript, inline event handlers, forms, frames, navigation, remote resources, arbitrary ActionScript access, or unsupported CSS will work. Prefer small local documents, explicit dimensions, simple flex layouts, packaged SVG assets, and data supplied by the consumer bridge.

For a complete add-on walkthrough, continue with [Create a Canvas plugin from scratch](CreatingACanvasPlugin.md). For Papyrus-to-consumer messages, see [Send data with Canvas datagrams](CanvasDatagrams.md).
