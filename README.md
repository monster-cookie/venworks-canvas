# Venworks Canvas

Venworks Canvas is a shared Starfield HUD framework and installed UI runtime. It owns the authoritative normal and large HUD host, centralized Bethesda UI-data acquisition and fan-out, the bounded Papyrus-to-HUD event bridge, Watch and Chronomark compatibility, the bounded HTML Engine 2.0 renderer, consumer lifecycle services, diagnostics, and public authoring contracts.

Venworks Customizable HUD (VWHUD) is the flagship Canvas consumer and owns its themes, components, domain-specific behavior, configuration, and distribution. Venworks Core may provide reusable utilities, but it does not participate in Canvas data acquisition, consumer registration, or event delivery.

See [Canvas Product Boundary and Package Ownership](docs/PRODUCT_BOUNDARY.md) for the normative ownership, integration, compatibility, and non-goal contract.
