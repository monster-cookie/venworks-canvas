# HTML/3 HUD authoring

Consumers opt in with `getCanvasHtmlRegistration()` returning `{contract:"VWCANVAS_HTML/3",entryDocument:"index.html"}`. The registration and lifecycle remain `VWCANVAS_CONSUMER/3`. Existing HTML/2 consumers retain synchronous `setData` behavior. HTML/3 is a bounded renderer contract, not a browser or a Vue/JavaScript runtime.

## SVG and meters

Inline SVG and local `.svg` assets use the same bounded geometry implementation. Supported elements are `svg`, `g`, `path`, `rect`, `circle`, `ellipse`, `polygon` and `polyline`. Paths support absolute and relative M/L/H/V/Z/Q/T/C/S commands. Cubic curves are flattened with bounded subdivisions; quadratic curves use native curve drawing. Arc commands are not implemented. Shapes support fill, stroke, stroke-width and fill/stroke opacity through attributes and approved CSS. Group transforms support bounded translate, scale, rotate and matrix operations. Parsing remains text-based without XML/E4X fallback.

```html
<svg viewBox="0 0 320 48" width="320" height="48">
  <path d="M 16 0 L 304 0 Q 320 0 320 16 L 320 32 Q 320 48 304 48 L 16 48 Q 0 48 0 32 L 0 16 Q 0 0 16 0 Z" fill="#061722" stroke="#2dcbff" stroke-width="1"></path>
</svg>
<vw-meter class="health" value="player.healthpercentage" min="0" max="100" direction="right" segments="16" gap="2" partial="true"></vw-meter>
```

Set meter dimensions and fill/track colors in CSS. Directions are right, left, up and down; segments are bounded to 1–256 and gaps to 0–256. `partial="false"` fills only complete segments. Explicit ranges avoid legacy automatic percentage interpretation. Transparent track colors preserve gaps. `object-fit: contain` fits SVG images without stretching; the legacy default remains fill.

## Placement and bindings

Use `position: absolute` with `data-vw-anchor` for top-left, top-center, top-right, center-left, center, center-right, bottom-left, bottom-center or bottom-right. Canvas supplies the host visible rectangle and safe-area insets, including ship HUD layout updates. Author offsets use the host's 1920×1080 design space. Host/game projection and actual ultrawide appearance still require runtime validation.

`data-vw-x`, `data-vw-y`, `data-vw-rotation`, `data-vw-opacity` and `data-vw-scale` name numeric snapshot fields. Values must be finite, with coordinates within ±8192, rotation within ±360 degrees, opacity 0–1 and scale 0.01–16. Static CSS transforms use bounded translate/scale/rotate/matrix syntax with pixels and degrees. Asset bindings use `data-vw-asset` and a static space-separated `data-vw-assets` allowlist on an image; they cannot open arbitrary resource paths.

## Native presentation controls

```html
<vw-hud-target target="player.crosshair" disabled="true"></vw-hud-target>
<vw-hud-target target="canvas.watch" disabled="true"></vw-hud-target>
<vw-hud-target target="player.crew-buffs" offset-x="12" offset-y="-8"></vw-hud-target>
```

Targets are semantic names, not author-supplied Bethesda paths. `disabled="true"`, CSS `display: none`, and CSS `visibility: hidden` suppress the requested surface. CSS has no `visibility: none`. Enabled means follow the engine's state; it never forces a hidden native surface to appear. Multiple consumers' suppression requests combine, so removing one request cannot clear another. Failure, replacement and unload release that consumer's requests.

Vanilla suppression uses a host-owned empty mask, preserving native `visible`, alpha, timelines and input callbacks. This distinction matters for vehicle exit: the native input handler checks visibility. The watch additionally suspends drawing and animation when disabled, while event ingress and shared providers continue. Re-enabling it rebuilds current presentation from cached provider state without replaying expired alerts.

Offsets are bounded to ±8192 and allowed only for a single native target. Group/dynamic/watch placement is rejected. Canvas tracks engine position changes while the offset is active and restores the current native position on release. If consumers request different placements of the same target, the lexically first consumer ID owns placement until it releases; suppression remains independent. Missing timeline instances produce a contained diagnostic and are retried when recreated. Unknown semantic targets are rejected.

`<vw-symbol name="vehicle-exit-prompt">`, `weapon-icon` and `compass-marker` expose only allowlisted native artwork in player HUD consumers. Weapon and vehicle glyph presentation uses a bounded host-owned capture (maximum 512×512), leaving the original native controls attached to their engine owners. Compass markers use the native marker class with validated descriptors. This does not enable bitmap file resources or arbitrary native class access. Native capture and marker frames require normal/large and controller acceptance in game.

## Data updates and diagnostics

HUD requests apply on the first successful render, even without a data snapshot, and on successful state and layout commits. HTML/2 documents cannot use HTML/3 HUD targets, native symbols, presentation bindings, anchors, or extended meter controls.

HTML/3 snapshots are validated before queuing and coalesced until the next frame. Unchanged objects remain attached; text and meter graphics update in place, and changed repeated/state subtrees reconcile. The bridge's `getUpdateState()` reports pending work, accepted revision and the most recent render diagnostic. A rejected update preserves the last valid display. Teardown removes queued frame work and releases HUD requests.

The Component Gallery demonstrates standard curves, primitive groups and an explicit segmented meter. The existing subscriptions diagnostic harness exercises production SVG/meter code, retained text/meter/static identities, coalescing, rejected data, unload, native mask restoration, multiple consumers and placement changes. Compiling the harness does not execute these tests; run it in the game before claiming runtime success.

The subscriptions probe also includes real-frame coalescing and disposal checks, first-paint and static-target session checks, body bindings, standard inline SVG dimensions, watch restoration, and transactional inventory boundary checks. A completed compile is not a passing probe result. Execute the probe and require all 17 cases to complete successfully; the asynchronous frame case remains pending until the player advances it.

Dynamic inventories publish only complete scans. A node or depth limit retains the last complete inventory for the same root, missing/replaced roots release obsolete objects, and diagnostics are emitted once per changed failure condition while frame retries continue.

For each target below, acceptance must cover enabled, hidden, disabled, group suppression, overlapping consumers, timeline replacement and unload in normal and large movies. Test game actions and status delivery while presentation is suppressed. Dynamic ship marker targets select the catalog's native marker classes through a bounded host inventory; they do not depend on transient instance names.

Standard `viewBox` and the existing lowercase `viewbox` alias share the same internal representation. SVG dimensions accept bounded numbers, pixel lengths, and root percentages; CSS dimensions override presentation attributes. External SVG dimensions supply intrinsic image sizing when CSS leaves that dimension automatic.

## HUD target catalog

`player.all` and `ship.all` combine their host's native targets. `canvas.watch` is a separate Canvas target. The implementation mapping is in [CanvasHudTargetCatalog.as](../Scaleform/canvas/actionscript/CanvasHudTargetCatalog.as); the table below identifies owning movies and mappings for review.

| Target | Owner (normal and large) | Host mapping |
| --- | --- | --- |
| `ship.target-components` | SpaceshipHudMenu | `@ship:TargetComponentIndicator` |
| `ship.activator-markers` | SpaceshipHudMenu | `@ship:ActivatorIcon` |
| `ship.star-markers` | SpaceshipHudMenu | `@ship:CelestialIcon` |
| `ship.hailing-markers` | SpaceshipHudMenu | `@ship:HailingIcon` |
| `ship.loot-markers` | SpaceshipHudMenu | `@ship:LootIcon` |
| `ship.poi-markers` | SpaceshipHudMenu | `@ship:POIIcon` |
| `ship.ship-markers` | SpaceshipHudMenu | `@ship:ShipTargetIcon` |
| `ship.station-markers` | SpaceshipHudMenu | `@ship:StationIcon` |
| `ship.planet-markers` | SpaceshipHudMenu | `@ship:PlanetIcon` |
| `ship.destructible-markers` | SpaceshipHudMenu | `@ship:DestructibleObjectIcon` |
| `ship.quest-markers` | SpaceshipHudMenu | `@ship:QuestIcon` |
| `ship.landing-markers` | SpaceshipHudMenu | `@ship:LandingMarkerIndicator` |
| `ship.off-screen-markers` | SpaceshipHudMenu | `@ship:OffScreenIcon` |
| `ship.reticle-buttons` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.ButtonBar_mc` |
| `player.health-label` | HUDMenu | `RightMeters_mc.Health_mc` |
| `player.health-track` | HUDMenu | `RightMeters_mc.HealthBarEmpty_mc` |
| `player.health-ghost` | HUDMenu | `RightMeters_mc.HealthBarGhost_mc` |
| `player.health-damage` | HUDMenu | `RightMeters_mc.HealthBarDamage_mc` |
| `player.health-fill` | HUDMenu | `RightMeters_mc.HealthBar_mc` |
| `player.health-increase` | HUDMenu | `RightMeters_mc.HealthBarIncrease_mc` |
| `player.power-fill` | HUDMenu | `RightMeters_mc.PowerBar_mc` |
| `player.power-increase` | HUDMenu | `RightMeters_mc.PowerBarIncrease_mc` |
| `player.meter-divider-primary` | HUDMenu | `RightMeters_mc.VerticalDivider_mc` |
| `player.meter-divider-secondary` | HUDMenu | `RightMeters_mc.VerticalDivider2_mc` |
| `player.vehicle-exit-button` | HUDMenu | `RightMeters_mc.HUDVehicle_mc.GetUpButton_mc` |
| `ship.throttle` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.ThrottleComponent_mc` |
| `ship.boost` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.BoostComponent_mc` |
| `ship.heading` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.HeadingIndicator_mc` |
| `ship.lock-on` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.LockOn_mc` |
| `ship.thrusters` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.ThrusterIcon_mc` |
| `ship.speed-label` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.SpeedName_mc` |
| `ship.roll` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.RollIndicator_mc` |
| `ship.lead-circle` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.LeadCircle_mc` |
| `ship.contraband` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.ContrabandWarning_mc` |
| `ship.turn-rate` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.MaxTurnRate_mc` |
| `ship.target-panel` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.TargetPanel_mc` |
| `ship.target-lock` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.TargetLockCircle_mc` |
| `ship.targeting-ap` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.APBar_mc` |
| `ship.engine-alert` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.AlertEng_mc` |
| `ship.grav-alert` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.AlertGrav_mc` |
| `ship.shield-alert` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.AlertShield_mc` |
| `ship.hull-alert` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.AlertHull_mc` |
| `ship.boost-button` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.BoostName_mc` |
| `ship.cruise-button` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.CruiseName_mc` |
| `ship.exit-cruise-button` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc.ExitCruiseHolder_mc` |
| `ship.power-dpad` | SpaceshipHudMenu | `PowerAllocationComponentWrapper_mc.PowerAllocationComponent_mc.DPadButton_mc` |
| `ship.power-increase` | SpaceshipHudMenu | `PowerAllocationComponentWrapper_mc.PowerAllocationComponent_mc.UpButton_mc` |
| `ship.power-decrease` | SpaceshipHudMenu | `PowerAllocationComponentWrapper_mc.PowerAllocationComponent_mc.DownButton_mc` |
| `ship.power-count` | SpaceshipHudMenu | `PowerAllocationComponentWrapper_mc.PowerAllocationComponent_mc.BarCount_mc` |
| `ship.power-free-status` | SpaceshipHudMenu | `PowerAllocationComponentWrapper_mc.PowerAllocationComponent_mc.FreeLaneStatus_mc` |
| `ship.power-free-title` | SpaceshipHudMenu | `PowerAllocationComponentWrapper_mc.PowerAllocationComponent_mc.FreeLaneTitle_mc` |
| `ship.hull-meter` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.INTMeter_mc` |
| `ship.shield-health` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.ShieldHealth_mc` |
| `ship.outline` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.ShipOutline_mc` |
| `ship.repair-button` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.ShipRepairButton_mc` |
| `ship.hull-label` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.HullLabel_mc` |
| `ship.repair-animation` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.ShipRepairAnim_mc` |
| `ship.grav-power-required` | SpaceshipHudMenu | `GravJumpComponent_mc.GravNeedsPower_mc` |
| `ship.grav-progress` | SpaceshipHudMenu | `GravJumpComponent_mc.GravJumpProgress_mc` |
| `ship.grav-cancel` | SpaceshipHudMenu | `GravJumpComponent_mc.CancelButton_mc` |
| `ship.starborn-grav-power-required` | SpaceshipHudMenu | `StarbornGravJumpComponent_mc.GravNeedsPower_mc` |
| `ship.starborn-grav-progress` | SpaceshipHudMenu | `StarbornGravJumpComponent_mc.GravJumpProgress_mc` |
| `ship.starborn-grav-cancel` | SpaceshipHudMenu | `StarbornGravJumpComponent_mc.CancelButton_mc` |
| `ship.hail-name` | SpaceshipHudMenu | `HailComponent_mc.Name_mc` |
| `ship.hail-buttons` | SpaceshipHudMenu | `HailComponent_mc.ButtonBar_mc` |
| `ship.container-list` | SpaceshipHudMenu | `ShipHudQuickContainer_mc.List_mc` |
| `ship.container-target-name` | SpaceshipHudMenu | `ShipHudQuickContainer_mc.TargetName_tf` |
| `ship.container-player-inventory` | SpaceshipHudMenu | `ShipHudQuickContainer_mc.PlayerInvData_mc` |
| `ship.container-buttons` | SpaceshipHudMenu | `ShipHudQuickContainer_mc.ButtonBar_mc` |
| `ship.container-header` | SpaceshipHudMenu | `ShipHudQuickContainer_mc.Header_mc` |
| `ship.component-status-1` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.ComponentStatus1_mc` |
| `ship.component-status-2` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.ComponentStatus2_mc` |
| `ship.component-status-3` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.ComponentStatus3_mc` |
| `ship.component-status-4` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.ComponentStatus4_mc` |
| `ship.component-status-5` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.ComponentStatus5_mc` |
| `ship.component-status-6` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.ComponentStatus6_mc` |
| `ship.component-status-7` | SpaceshipHudMenu | `ShieldComponentWrapper_mc.ShieldComponent_mc.ComponentStatus7_mc` |
| `canvas.watch` | CanvasHost | `@watch` |
| `player.center` | HUDMenu | `CenterGroup_mc` |
| `player.crosshair` | HUDMenu | `CenterGroup_mc.ReticleBase_mc` |
| `player.power-notification` | HUDMenu | `CenterGroup_mc.ArtifactPowersWidget_mc` |
| `player.explosive-indicators` | HUDMenu | `CenterGroup_mc.ExplosiveIndicatorBase_mc` |
| `player.directional-damage` | HUDMenu | `CenterGroup_mc.DirectionalHitIndicatorBase_mc` |
| `player.hit-damage` | HUDMenu | `HitDamageBase_mc` |
| `player.hit-and-kill` | HUDMenu | `HitAndKillIndicator_mc` |
| `player.hit-indicator` | HUDMenu | `HitAndKillIndicator_mc.HitIndicator_mc` |
| `player.kill-indicator` | HUDMenu | `HitAndKillIndicator_mc.KillIndicator_mc` |
| `player.top-center` | HUDMenu | `TopCenterGroup_mc` |
| `player.stealth` | HUDMenu | `TopCenterGroup_mc.StealthMeter_mc` |
| `player.enemy-health` | HUDMenu | `EnemyHealthHolder_mc` |
| `player.quest-markers` | HUDMenu | `FloatingQuestMarkerBase` |
| `player.rollover` | HUDMenu | `RolloverWidget_mc` |
| `player.rollover-activation` | HUDMenu | `RolloverWidget_mc.RolloverActivationHolder_mc` |
| `player.rollover-reticle` | HUDMenu | `RolloverWidget_mc.Reticle_mc` |
| `player.social-commands` | HUDMenu | `SocialCommandIcons_mc` |
| `player.crew-buffs` | HUDMenu | `CrewBuffWidget_mc` |
| `player.meters` | HUDMenu | `RightMeters_mc` |
| `player.health` | HUDMenu | `RightMeters_mc.Health_mc,RightMeters_mc.HealthBarEmpty_mc,RightMeters_mc.HealthBarGhost_mc,RightMeters_mc.HealthBarDamage_mc,RightMeters_mc.HealthBar_mc,RightMeters_mc.HealthBarIncrease_mc` |
| `player.power` | HUDMenu | `RightMeters_mc.PowerBar_mc,RightMeters_mc.PowerBarIncrease_mc` |
| `player.jetpack` | HUDMenu | `RightMeters_mc.JetpackMeterWrapper_mc` |
| `player.weapon-icon` | HUDMenu | `RightMeters_mc.EquippedWeaponIconHolder_mc` |
| `player.ammo` | HUDMenu | `RightMeters_mc.EquippedWeaponAmmo_mc` |
| `player.ammo-reserve` | HUDMenu | `RightMeters_mc.EquippedWeaponAmmoTotal_mc` |
| `player.grenade-icon` | HUDMenu | `RightMeters_mc.EquippedGrenadeIcon_mc` |
| `player.grenade-count` | HUDMenu | `RightMeters_mc.EquippedGrenadeCount_mc` |
| `player.meter-dividers` | HUDMenu | `RightMeters_mc.VerticalDivider_mc,RightMeters_mc.VerticalDivider2_mc` |
| `player.vehicle-exit` | HUDMenu | `RightMeters_mc.HUDVehicle_mc` |
| `ship.power` | SpaceshipHudMenu | `PowerAllocationComponentWrapper_mc` |
| `ship.shields` | SpaceshipHudMenu | `ShieldComponentWrapper_mc` |
| `ship.get-up` | SpaceshipHudMenu | `GetUpButton_mc` |
| `ship.reticle` | SpaceshipHudMenu | `Reticle_mc` |
| `ship.target-indicator` | SpaceshipHudMenu | `Reticle_mc.ShipReticle_mc` |
| `ship.body-marker` | SpaceshipHudMenu | `Reticle_mc.BodyViewMarker_mc` |
| `ship.indicator-buttons` | SpaceshipHudMenu | `Reticle_mc.IndicatorButtonBar_mc` |
| `ship.grav-jump` | SpaceshipHudMenu | `GravJumpComponent_mc` |
| `ship.starborn-grav-jump` | SpaceshipHudMenu | `StarbornGravJumpComponent_mc` |
| `ship.alerts` | SpaceshipHudMenu | `Alerts_mc` |
| `ship.quick-container` | SpaceshipHudMenu | `ShipHudQuickContainer_mc` |
| `ship.hail` | SpaceshipHudMenu | `HailComponent_mc` |
| `ship.buttons` | SpaceshipHudMenu | `ButtonBar_mc` |
| `ship.scan` | SpaceshipHudMenu | `ScanDetails_mc` |
| `ship.scan-ship` | SpaceshipHudMenu | `ScanDetails_mc.Internal_mc.ShipInfo_mc` |
| `ship.scan-planet` | SpaceshipHudMenu | `ScanDetails_mc.Internal_mc.PlanetInfo_mc` |
| `ship.debug-text` | SpaceshipHudMenu | `DebugText_tf` |
| `ship.debug-buttons` | SpaceshipHudMenu | `DebugButtonHints_tf` |
