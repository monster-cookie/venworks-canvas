# Linear team documentation

Use this procedure when technical project documentation, design decisions, research notes, validation evidence, or maintainer runbooks need a durable home.

## Documentation boundary

- Keep user and public documentation in the repository when it supports product discovery, installation, usage, security reporting, release history, or user-facing known issues.
- Store technical contracts, architecture, domain design, implementation guidance, research findings, validation evidence, and maintainer runbooks in documents verified to belong to the canonical Venworks Canvas team in the Venworks Linear workspace.
- Treat existing human-maintained repository documentation, including `README.md` and `CHANGELOG.md`, as approval-gated documentation. Moving or indexing that content does not authorize edits.
- Keep repository agent instructions, credential and tooling policies, and Linear lifecycle procedures local because they govern repository and tool execution.
- Do not create a second local technical copy after a document has been migrated to Linear. This procedure does not authorize Linear document creation, edits, comments, or attachments; verify the target and obtain explicit authorization before any mutation.

## Team identity, document access, and privacy

- Verify the consuming app user, workspace UUID, and canonical team UUID from `AGENT-REPO-CONTEXT.md` before dependent document operations. Use team scoping when available and verify the returned document's team identity after an unscoped retrieval.
- Resolve current document IDs and URLs from Linear readback. Do not invent or rely on remembered document names, URLs, or list positions. Re-read the selected document before a consequential write and after any authorized mutation.
- A team visibility value or an accessible document URL does not prove that a document is private, owner-only, or unpublished on the web. Treat web-publishing status as unverified when the consuming interface does not expose it; verify any required privacy property through a supported surface before a write that depends on it.
- Migrated documents may still say Plane owns current work or contain old Plane links. Treat their original-source notes as historical provenance and reconcile active requirements with current Linear issues and documents before decisions or edits.

## Current document index

Use current Linear readback and the verified Canvas team identity to select a destination. The following team-scoped documents are current known destinations; re-read the selected document before relying on its content or performing an authorized mutation.

| Linear destination | Scope indicated by the current document title |
| --- | --- |
| [Venworks HUD Framework Theoretical Design](https://linear.app/venworks/document/venworks-hud-framework-theoretical-design-2b622b6adbcd) | Theoretical HUD framework design. |
| [Venworks Canvas — Design Document](https://linear.app/venworks/document/venworks-canvas-design-document-4d59c05019ae) | Canvas design. |
| [VWCANVAS-13 — VWHUD provider subscription inventory](https://linear.app/venworks/document/vwcanvas-13-vwhud-provider-subscription-inventory-fa8243691cec) | VWHUD provider subscription inventory. |
| [VWCANVAS-24 — Local Resource Loader Implementation](https://linear.app/venworks/document/vwcanvas-24-local-resource-loader-implementation-e1e05ba6557b) | Local resource loader implementation. |
| [VWCANVAS-25 — HTML Tokenizer and Parser Implementation](https://linear.app/venworks/document/vwcanvas-25-html-tokenizer-and-parser-implementation-187631848030) | HTML tokenizer and parser implementation. |
| [VWCANVAS-10 — Consumer Lifecycle Contract and Runtime Test Handoff](https://linear.app/venworks/document/vwcanvas-10-consumer-lifecycle-contract-and-runtime-test-handoff-1367c0290a11) | Consumer lifecycle contract and runtime test handoff. |
| [VWCANVAS-34 — Repository Build and Packaging Operations](https://linear.app/venworks/document/vwcanvas-34-repository-build-and-packaging-operations-9c28e05c7f86) | Repository build and packaging operations. |

No repository public roadmap is currently declared by this procedure. If one is authorized later, it must remain a public summary rather than an independent current backlog. Preserve implemented behavior, proposed design, historical findings, and unverified acceptance as separate claims. Link to source files and tests where authoritative, but do not duplicate large implementation listings in Linear.

## Migration and handoff

Remove local links to intentionally deleted technical documents only within an authorized documentation scope and replace them with verified Linear links after readback. A documentation handoff should identify the destination, source, preserved sections, changed terminology, verified links, and remaining evidence or privacy gaps. A document created or updated without successful readback is not a completed migration.
