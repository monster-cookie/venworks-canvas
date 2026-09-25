# Bethesda Creations listing metadata

## Public listing

- Title: `Venworks Canvas`
- Summary: `A shared Player HUD framework for compatible Starfield UI add-ons.`
- Game: `Starfield`
- Suggested tags: `UI`, `Utilities`
- Release status: `Unreleased`; do not publish until the selected platform package and player-visible runtime scenario are validated.
- Version: `1.0.0` after the release commit is merged and tagged.
- Pricing: Confirm in the live publishing form.
- Platforms: Select only platforms backed by the final release packages and platform-specific acceptance. The repository currently records current-build PC and PS5 gameplay acceptance as pending and does not establish Xbox acceptance.

## Requirements and compatibility

- Required Creation: `Venworks Core Library`, version `2.1.8` or newer.
- Plugin master: `Venworks-Core.esm`.
- The optional Example and Component Gallery also require the Canvas base Creation.
- Canvas owns complete Player HUD files and can conflict with other Creations that replace those files. Do not claim compatibility without an explicit patch or verified integration.
- Canvas `1.0.0` should be described as a Player HUD framework. Ship HUD and pilot-seat support are not release claims.

## Creation structure

Publish the base and optional packages as distinct Creations so their requirements remain clear:

1. `Venworks Canvas` — required base framework.
2. `Venworks Canvas Example` — optional example consumer; requires Venworks Canvas.
3. `Venworks Canvas Component Gallery` — optional creator reference; requires Venworks Canvas.

The base Creation description is in `description.md`. If the optional packages receive their own public pages, keep their descriptions focused on the package and link back to the base Canvas Creation.

## Media

- Box-art candidate: `MarketingSites/Images/Venworks-Logo.png`
- Header candidate: `MarketingSites/Images/Venworks-Header.png`
- Include at least one player-facing in-game Canvas screenshot.
- The focused images under `Documentation/Images/ComponentGallery/` can support the Component Gallery page.
- Bethesda requires box art, screenshots, and a description; confirm every final media asset is owned or licensed for this upload.

## Documentation links

- Player overview, installation, compatibility, and troubleshooting: `https://github.com/monster-cookie/venworks-canvas#readme`
- Create a Canvas plugin from scratch: `https://github.com/monster-cookie/venworks-canvas/blob/master/Documentation/CreatingACanvasPlugin.md`
- Canvas component gallery: `https://github.com/monster-cookie/venworks-canvas/blob/master/Documentation/CanvasComponentGallery.md`
- Canvas datagrams: `https://github.com/monster-cookie/venworks-canvas/blob/master/Documentation/CanvasDatagrams.md`
- Source repository: `https://github.com/monster-cookie/venworks-canvas`

## Publication checks

- Paste `description.md` into the live editor and verify its preview. The file intentionally uses plain headings, short paragraphs, bullets, and bare URLs because Bethesda Creations supports a restricted description format.
- Confirm the final version, requirements, platform packages, pricing, tags, credits, media, and external links in the live publishing form.
- Keep the listing unpublished or marked Work In Progress until the uploaded Creation is functional and the intended platform acceptance is complete.
