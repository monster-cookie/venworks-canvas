# Canvas Product Boundary and Package Ownership

| Field | Value |
| --- | --- |
| Status | Canvas 1.0 planning baseline |
| Contract revision | 1 |
| Governing work item | VWCANVAS-7 |
| Last evidence review | 2026-09-01 |

This document defines ownership. It does not establish an API compatibility version or select mechanisms that belong to later contract and implementation work. A surface or package has one owner even when it depends on another owner's public contract.

## Ownership terms

- **Source ownership** identifies the project that designs, reviews, and maintains source for a surface or package.
- **Runtime-service ownership** identifies the runtime that creates, controls, tears down, and diagnoses a service.
- **Package ownership** identifies the project that builds, validates, versions, and distributes an installable artifact.
- **Integration responsibility** is an obligation to use another owner's public contract; it does not transfer ownership of that contract or service.

## Runtime and source ownership

| Surface | Owner | Owner responsibility | Integration boundary |
| --- | --- | --- | --- |
| Normal and large HUD host | Canvas | Own the authoritative host at the participating normal and large Starfield HUD paths, including startup, loading, lifecycle, isolation, teardown, and diagnostics. | Consumers provide only contract-approved namespaced resources and do not ship a competing host. |
| Bethesda UI-data provider hub | Canvas | Prime and subscribe once per distinct approved `BSUIDataManager` channel, defensively validate incoming shapes, and unsubscribe during teardown. | Consumers declare required channels; they do not create duplicate global subscriptions. |
| Read-only snapshot store and data fan-out | Canvas | Create bounded snapshots, retain only contract-approved state, and notify only consumers that declared the channel. | Consumers treat snapshots as read-only and own document-local state derived from them. |
| Consumer discovery and registration control plane | Canvas | Discover, validate, order, register, reject, reload, and unload independently packaged consumers with deterministic diagnostics and failure isolation. | Consumer packages provide a valid descriptor through the mechanism proven by VWCANVAS-9. Registration never uses the Watch Alert event transport. |
| Consumer descriptor and lifecycle contract | Canvas | Define namespaced identity, version negotiation, normal and large entry points, requested channels and topics, lifecycle callbacks, local resource roots, and budgets. | Consumers implement the published contract without gaining arbitrary access to the host or other consumers. |
| Papyrus publishing API and Canvas event ingress | Canvas | Define the bounded publishing API, parse Canvas envelopes received through `CustomAlertsData`, route namespaced topics, and isolate malformed or failing inputs. | Producers publish without knowing consumer identities. Consumers declare topics and receive only validated bodies. |
| Watch and Chronomark compatibility surface | Canvas | Own one authoritative alert presentation and demultiplex ordinary alerts, valid Canvas envelopes, and malformed Canvas-prefixed input before presentation. | Consumers do not create a second Chronomark animation state machine or display raw Canvas envelopes as player alerts. |
| HTML Engine 2.0 | Canvas | Own bounded text loading, tokenization, parsing, document and style models, layout, native Scaleform rendering, resource controls, diagnostics, and generic authoring semantics. | Consumers provide only supported local documents, styles, assets, bindings, and components. VWHUD-specific semantics remain in VWHUD. |
| Public consumer SDK and conformance material | Canvas | Publish authoring contracts, schemas, validation tools, fixtures, examples, compatibility policy, and generic integration guidance. | Consumer owners validate their packages against the supported Canvas contract and platform requirements. |
| Canvas Example Consumer source | Canvas | Maintain a minimal first-party consumer that exercises one data channel, one Canvas topic, lifecycle behavior, HTML/CSS, local assets, version negotiation, reload, and teardown. | The example demonstrates the public contract and does not define VWHUD behavior. |
| VWHUD consumer adapter | VWHUD | Declare VWHUD channels and topics, translate Canvas snapshots into VWHUD-local models, and implement VWHUD lifecycle behavior. | The adapter consumes Canvas services but does not own or duplicate their global acquisition and routing. |
| VWHUD components and domain behavior | VWHUD | Own tactical calculations, environmental interpretation, timers, derived presentation state, controls, animations, and other VWHUD-specific behavior. | Behavior moves into Canvas only through separately approved framework-wide contract work. |
| VWHUD themes, configuration, and consumer assets | VWHUD | Own VWHUD layouts, styles, palettes, SVG and path assets, theme selection, user configuration, migrations, and player documentation. | Assets remain under the VWHUD consumer namespace and conform to Canvas limits. |
| Reusable utility code | Venworks Core | Own general-purpose utilities that are useful independently of Canvas HUD delivery. | Core does not subscribe to HUD providers, register consumers, route Canvas events, own the host, or mediate Canvas-to-consumer delivery. |
| Third-party consumer source | Its consumer publisher | Own consumer-local behavior, documents, styles, assets, descriptors, releases, and support. | The publisher integrates through the Canvas SDK and must not depend on Canvas internals or another consumer. |

## Package ownership

| Installable or development output | Owner | Required separation |
| --- | --- | --- |
| Canvas base runtime package | Canvas | Contains the host and required runtime services. It contains no sample overlay, VWHUD theme, or fault-injection fixture. |
| Canvas consumer SDK | Canvas | Is a separate development output and is not required in a player's installed runtime unless a future contract explicitly identifies a runtime file. |
| Canvas Example Consumer package | Canvas | Is a separate optional download and is never included or enabled in the base runtime package. |
| VWHUD consumer package | VWHUD | Contains VWHUD-local resources and declares a compatible Canvas runtime dependency. It does not distribute a competing Canvas-owned host. |
| Venworks Core package | Venworks Core | Remains independently owned and versioned; it is not the Canvas data or event delivery layer. |
| Third-party consumer package | Its consumer publisher | Contains only that consumer's contract-approved resources and declares its Canvas compatibility requirements. |

Exact file inventories, archive names, dependency metadata, and build boundaries are specified by VWCANVAS-34. This contract fixes their ownership before that packaging work begins.

## Data-layer boundary and VWHUD migration evidence

The complete generic data layer lives in Canvas: acquisition, subscription deduplication, defensive shape validation, bounded read-only snapshots, lifecycle, fan-out, teardown, and provider diagnostics. A consumer owns the set of channels it requests and every consumer-specific interpretation or presentation derived from those snapshots.

The VWHUD baseline inspected for this contract was branch `codex/vwkshud-45-swf-components` at commit `74aff1c0df83e2c642750f942872e07033ed4a3a`. This is migration evidence, not a permanent Canvas public-channel list.

The full themed VWHUD value context currently contains 14 registration sites: `LocalEnvironmentData`, `LocalEnvData_Frequent`, `PlayerData`, `PlayerFrequentData`, `PlayerInventoryData`, `WeaponData`, `HudJetpackData`, `HUDStarbornPowersData`, `FavoritesData`, `ControlMapData`, `EnvironmentEffectsData`, `PersonalEffectsData`, `StarmapSystemBodyInfoProvider`, and `HudCompassData`.

Its condition context contains 10 registration sites: `HudCrosshairData`, `HUDStealthData`, `HudCompassData`, `HUDVehicleData`, `HUDOpacityData`, `WeaponData`, `HUDStarbornPowersData`, `FavoritesData`, `HudJetpackData`, and `PlayerInventoryData`.

Six channels occur in both contexts, so the full themed baseline has 24 registration sites across 18 distinct channels. Minimalist removes `WeaponData`, `HUDStarbornPowersData`, `FavoritesData`, and `ControlMapData`, leaving 17 registration sites across 14 distinct channels. Canvas must acquire each approved distinct channel once and fan it out to every declaring VWHUD context; it must not preserve the current duplicate-registration structure as public architecture.

The reviewed VWHUD source locations are `Scaleform/shared/actionscript/venworks/cui/CUIPlayerHudDataContext.as`, `Scaleform/shared/actionscript/venworks/cui/CUIConditionContext.as`, and `Scaleform/variants/MIN/patches/minimalist-live.xml` in the VWHUD repository.

## Papyrus event boundary

Canvas owns a low-frequency, bounded, fire-and-forget publishing path through `Game.ShowCustomWatchAlert()` and `CustomAlertsData`. Publication means submission to the demonstrated transport; it is not delivery acknowledgement. Canvas does not promise durability, reliable ordering, guaranteed delivery, or an unconstrained message body.

State that must survive a missed event belongs in an idempotent current-state model. A later contract may permit Canvas to retain and replay a bounded latest value for explicitly declared state topics, but that behavior does not make the underlying transport acknowledged or reliable.

Consumer discovery and registration are a separate control plane. An event payload cannot install, register, enumerate, select, or grant capabilities to a consumer.

## Watch and Chronomark boundary

Canvas owns one authoritative Watch and Chronomark surface. A valid Canvas envelope is bounded and routed without presenting the raw envelope. A normal Bethesda or non-Canvas alert reaches the authoritative alert animation. Malformed Canvas-prefixed input fails closed with bounded diagnostics and never becomes executable content.

Whether Canvas safely adopts the existing runtime Chronomark symbol or implements a compatible replacement remains an evidence-driven mechanism decision. Canvas owns the resulting surface either way; two active Chronomark animation controllers are outside this contract.

## HTML Engine boundary

HTML Engine 2.0 is a bounded local HUD document subsystem, not a browser. Canvas owns its generic parser, style, layout, rendering, resource, failure, and diagnostic contracts. VWHUD owns VWHUD-specific components, bindings, templates, presentation semantics, and migration content built on those contracts.

The engine does not provide JavaScript, inline event handlers, forms, frames, navigation, protocols, remote resources, arbitrary browser APIs, arbitrary ActionScript invocation, absolute paths, traversal, permissive error recovery, or fallback to Scaleform XML/E4X. VWHUD-46, formerly referenced as VWKSHUD-46, and its attached **HTML Engine 2.0 Architecture and Parser Contract** page are the source material to be re-homed and generalized by VWCANVAS-23.

## Integration requirements

- A participating consumer has a stable namespaced identity and declares compatible Canvas contract versions, normal and large entry points, requested data channels, requested event topics, lifecycle capabilities, local resource roots, and budgets through the published descriptor.
- A consumer package contains no replacement for a Canvas-owned host path and does not subscribe globally to a provider that Canvas owns.
- A consumer treats host data as read-only, confines mutable state to its own runtime, and tears down listeners, loaders, timers, callbacks, and display objects when directed by Canvas.
- A consumer cannot call arbitrary host methods, another consumer, or unrestricted filesystem paths.
- Missing, malformed, incompatible, oversized, or callback-failing consumers fail independently without disabling the host, the Watch surface, or healthy consumers.
- Normal and large assets are explicit and selected deterministically. A package cannot rely on silent browser fallback, directory enumeration, or merge behavior that has not been demonstrated on the target platform.
- Installation, update, rollback, dependency, and coexistence rules must be documented for both loose development and archive-only production shapes before release acceptance.

## Complete HUD replacement compatibility

Canvas cannot automatically coexist with an unrelated mod that replaces a complete Canvas-owned `HUDMenu` path. File-level winner selection cannot merge two authoritative hosts, subscription hubs, lifecycle managers, or Chronomark controllers.

Such a mod is incompatible by default until its owner explicitly integrates its behavior as a Canvas consumer or collaborates on an approved host integration. Canvas must not claim broad compatibility merely because a load order happens to leave one replacement active. Participating consumers must never instruct users to resolve the conflict by overwriting only part of the Canvas host set.

## Non-goals

- Canvas is not a browser, general application platform, or remote-content runtime.
- Canvas is not a reliable or durable inter-mod message bus.
- Canvas does not guarantee delivery, ordering, acknowledgement, or replay for the underlying Watch Alert transport.
- Canvas does not own VWHUD themes, VWHUD domain calculations, VWHUD user configuration, or VWHUD release support.
- VWHUD does not own the global provider hub, Canvas event router, consumer registry, generic HTML engine, or authoritative Watch surface.
- Venworks Core does not own or mediate Canvas data acquisition, event delivery, consumer registration, lifecycle, or presentation.
- The base Canvas runtime does not include the Example Consumer, VWHUD, a sample overlay, or fault-injection fixtures.
- Canvas does not claim automatic compatibility with unrelated complete HUD replacements.
- This contract does not select unproven console discovery, Chronomark adoption, event encoding, API version, resource limit, or package-layout mechanisms.

## Unresolved decisions and assigned work

There are no unresolved owner assignments for the surfaces and packages in this contract. The following mechanism and contract-detail decisions remain open and must not be implied by implementation:

| Decision | Governing work |
| --- | --- |
| Exact consumer descriptor fields, schema, paths, and namespace validation | VWCANVAS-8 |
| Console-safe discovery and registration for loose and archive-only consumers | VWCANVAS-9 |
| Lifecycle, data, event, callback, retention, and failure-isolation APIs | VWCANVAS-10 |
| Version negotiation, deprecation, rollback, diagnostics, and measurable resource limits | VWCANVAS-11 |
| Final Papyrus API, envelope encoding, length limits, sequence metadata, and latest-value rules | VWCANVAS-19 |
| Vanilla behavior baseline and Chronomark adoption versus compatible reimplementation | VWCANVAS-18 and VWCANVAS-21 |
| HTML Engine 2.0 syntax, rendering, security limits, and conformance corpus | VWCANVAS-23 |
| Runtime, SDK, Example Consumer, dependency, archive, and release package layouts | VWCANVAS-34 |

No implementation epic should claim production readiness while one of its blocking contract or evidence tasks remains unresolved. Compilation, decompilation, hashes, archive inventories, and PC-only execution are scoped evidence and do not replace exact packaged PC and PS5 runtime acceptance.
