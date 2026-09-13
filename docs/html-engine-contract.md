# Canvas HTML Engine 2.0 contract

Canvas HTML Engine 2.0 is a deterministic, bounded document contract for consumer-owned HUD resources. The normative machine-readable definition is [`Contracts/html-engine-v2.json`](../Contracts/html-engine-v2.json), identified by the exact contract string `VWCANVAS_HTML/2`. The HTML contract has its own version and does not reuse a consumer descriptor revision, `VWCANVAS_CONSUMER` protocol version, `VWC_EVT` wire version, or negotiated Canvas host API version.

This repository currently defines the contract and conformance corpus only. It does not yet contain the production HTML parser, style engine, layout engine, binding adapter, asset loader, or renderer. Corpus results describe the required behavior of that future implementation; they are not recorded runtime passes and do not establish PC or PS5 acceptance.

## Input acquisition and parser ownership

Every runtime `.html`, `.css`, and `.svg` resource is acquired as an ordered byte sequence. The source-file and aggregate byte limits are enforced on those bytes before a strict UTF-8 decoder rejects a byte-order mark or the first invalid sequence. Successful decoding produces plain `String` text only. Canvas then selects exactly one Canvas-owned custom document, CSS, or SVG parser and performs exactly one parse pass for that decoded runtime resource. The document parser identifies template and composition node ranges during its single pass; it does not reparse them. At compose stage, `vw-use` clones the already-parsed children of its referenced template. Standalone fragment resources and a separate fragment parser are unsupported.

The same route is mandatory on PS5 and every other target. Scaleform XML, E4X, `XMLList`, `XMLDocument`, `parseXML`, `TextField.htmlText`, `StyleSheet`, and `StyleSheet.parseCSS` are forbidden as primary parsers, secondary parsers, recovery paths, validators, or conversion paths. A load, decode, or selected-parser failure publishes its one deterministic terminal result without trying another backend. `VWCANVAS_HTML_INPUT/1` in the machine manifest fixes the ordered steps, parser routes, forbidden backend catalog, and typed corpus-observation fields.

## Deterministic document syntax

A document is UTF-8 without a byte-order mark and starts with the exact lower-case declaration `<!doctype html>`. Element and attribute names use exact lower-case ASCII spelling, every attribute value uses double quotes, every element has an explicit closing tag, and duplicate attributes are rejected. Comments, processing instructions, CDATA, error recovery, and a secondary parser are not part of the contract.

Character references are decoded exactly once. Only `&amp;`, `&apos;`, `&gt;`, `&lt;`, and `&quot;` are accepted. Numeric references, unknown named references, and raw ampersands are rejected. A conforming engine never sends rejected input to another parser.

The accepted standard elements are `html`, `head`, `title`, `meta`, `link`, `style`, `body`, `main`, `header`, `footer`, `section`, `div`, `span`, `h1` through `h6`, `p`, `br`, `hr`, `ul`, `ol`, `li`, `button`, `template`, `img`, `svg`, and `path`. The manifest gives each element its exact attributes, value grammars, and child model. Unknown elements or attributes, `style` attributes, and attributes beginning with `on` are rejected.

The initial generic composition elements are `vw-include`, `vw-use`, `vw-repeat`, `vw-state`, and `vw-meter`. Their behavior and complete attribute sets are fixed in the manifest. `vw-icon`, `vw-symbol`, `vw-provider-symbol`, and `vw-mask` remain reserved and unsupported until Canvas owns versioned catalog or masking semantics for them. Consumer-owned VWHUD elements such as `vw-contact-radar` and `vw-compass-tape` are explicitly outside the Canvas engine contract and are also rejected as unsupported.

## Styles and vector paths

Styles come only from `style` elements or linked local `.css` resources. The selector grammar admits a comma-separated group of type, class, or ID selectors joined only by descendant or child combinators. Compound, attribute, pseudo, and universal selectors are rejected. The property catalog and each property's value grammar are closed in the manifest; unknown properties, comments, at-rules, nesting, `!important`, and variable fallbacks are unsupported.

Custom properties use lower-case `--name` identifiers. A custom property value is exactly one terminal token sequence or one whole-value `var(--name)` reference; a normal property may use `var()` only as its entire value. No leading or trailing whitespace, internal `var()` whitespace, fallback argument, partial substitution, escape, comment, tab, or line break is accepted. List terminals use one ASCII space where their grammar calls for it. The terminal vocabulary is an exact property keyword, color, paint, finite number, length, nonnegative length, one-to-four length list, or embedded-font identifier. Resolution follows the current element and then nearest ancestors, validates the resolved terminal again against the destination property's grammar, reports a missing variable as `unresolved-reference`, a terminal type mismatch as `invalid-value`, and a cycle as `cycle`. The destination `var()` invocation and every followed reference count toward `variable-depth`, so 16 is accepted and 17 is rejected. The only initial embedded font catalog entry is `$MAIN_Font_Bold`, which supports the bundled Example Consumer's 18 px plain-text presentation without introducing a VWHUD-owned catalog.

The cascade is deterministic: entry-document head resources contribute rules in document order, a linked stylesheet is inserted at its link position, specificity compares ID count then class count then type count, and later rule or declaration order breaks a tie. Included documents contribute body content only and must have a title-only head. Only color, font family, font size, and text alignment inherit; the machine contract lists every other initial value.

Layout uses host logical pixels from a top-left origin and a content-box model. The initial engine supports vertical block flow, one unwrapped inline line separated by `br` or block boundaries, non-wrapping row or column flex flow without grow or shrink, and static, relative, or absolute positioning. It does not support borders, automatic wrapping, floats, grid, scrolling, transforms, or z-index. Text measurement and viewport dimensions come from bounded host adapters, and any adapter failure rejects the pending candidate.

Inline SVG admits only `svg` and `path`. The path grammar accepts the listed move, line, horizontal, vertical, cubic, smooth cubic, quadratic, smooth quadratic, and close commands with finite decimal numbers. Exponents, arc commands, unsupported paint syntax, and parser recovery are rejected.

A standalone local `.svg` resource is UTF-8 without a byte-order mark, has no doctype, and consists of exactly one lower-case `svg` root with `viewbox`; only nested `svg` and `path` elements use the same attribute and value catalogs as inline SVG. It is parsed only by the asset-stage SVG grammar and is never passed through the HTML tokenizer, so its elements count toward the per-resource SVG and path ceilings but not `html-tokens` or `expanded-dom-nodes`. Its IDs and classes are resource-local and are not HTML CSS selector targets. When omitted, `svg` attributes default to: no `id`, empty `class`, visible `data-vw-visible`, unset `width` and `height` with the documented inline-viewbox or external-`img` sizing rule, `x` and `y` of `0`, `fill` of `currentcolor`, `stroke` of `none`, `stroke-width` of `0`, `clip-rule` and `fill-rule` of `nonzero`, `preserveaspectratio` of `xmidymid meet`, `stroke-linecap` of `butt`, `stroke-linejoin` of `miter`, and `vector-effect` of `none`. A `path` defaults to no `id`, empty `class`, and inherited `fill`, `stroke`, `stroke-width`, and `fill-rule`.

## Local resources and bindings

Resources resolve beneath the registered consumer namespace. The engine does not fall back to `Interface/VenworksCUI` or another shared root. Initial loadable extensions are `.html`, `.css`, and `.svg`; the only non-file asset references are identifiers in an explicit embedded catalog. Absolute paths, protocols, remote URLs, backslashes, dot segments, empty segments, percent encoding, queries, fragments, and traversal are rejected before a resource is read.

Bindings use the exact schema ID `VWCANVAS_HTML_BINDINGS/1` and are registered as out-of-band host metadata associated with the consumer before document loading. They are not runtime assets, are never resolved or read by the HTML resource loader, and contribute zero bytes to `source-file-bytes` and `aggregate-loaded-bytes`; `.json` is not a runtime resource extension. JSON files in the conformance corpus are only a serialization of the host-supplied plain-data metadata for deterministic integrity checks. The metadata's only top-level fields are `schema`, `consumerNamespace`, `entryDocument`, and `bindings`; each binding entry has only `type` and `default`, and unknown fields at either level are rejected. The consumer namespace must equal the registered namespace and the entry document must equal the normalized entry resource. `bindings` is an object whose ordinal case-sensitive keys match `[a-z][a-z0-9-]*` and the `identifier-length` ceiling. Each declaration supplies one of `string`, `number`, `boolean`, or `array` plus a required matching default: numbers are finite, strings obey `string-code-units`, and arrays preserve order and duplicates while containing at most `repeat-items` plain-data scalars of `null`, boolean, finite number, or bounded string; nested arrays and objects are rejected. Validation follows the manifest's fixed field, association, ordinal-key, type, and default order and reports one bind-stage failure whose `resource` is the normalized entry document, never the out-of-band metadata name. A missing current snapshot uses the declared typed default. An unknown key, wrong type, non-finite number, expression, function call, direct provider acquisition, or provider property path is rejected. Canvas adapters may populate local keys from subscribed data, but the document cannot acquire or navigate a provider itself.

Initial binding resolution happens before the first render. After a successful commit, Canvas retains one immutable parsed node-and-resource representation containing active nodes, inactive state children, zero-repeat source children, and template children. A later host-ordered local snapshot follows the separate `VWCANVAS_HTML_UPDATE/1` pipeline: resolve and validate typed keys, clone the retained parsed representation into a pending candidate, then recompute affected composition, style, layout, asset, display binding/render, and lifecycle work before an atomic commit. Previously parsed resources are never reparsed during the update. A newly required resource uses the byte-first `VWCANVAS_HTML_INPUT/1` path exactly once, belongs to the pending transaction, and becomes retained and cacheable only if that transaction commits. Failure disposes all pending ownership and preserves the prior committed tree, snapshot, and parsed representation. Provider data and named events remain consumer-adapter inputs; they can update local keys but are not visible as document expressions.

The generic binding sites are `data-vw-text` for strings, `data-vw-visible` and `vw-state when` for booleans, `vw-repeat items` for arrays, and `vw-meter value` for finite numbers. `data-vw-text` requires empty source content and replaces that element's text node. `vw-repeat` repeats its children once per item without creating an implicit item variable, which keeps the initial binding model closed and exact.

## Limits

Every positive ceiling below is normative. The conformance corpus contains one declarative at-limit case and one over-limit case for every row. Every recipe uses exact schema ID `VWCANVAS_HTML_RECIPE/1` and has only `schema`, `stageInput`, `generator`, and `parameters`; `parameters` has only a bounded nonnegative integer `count`. The manifest fixes each named generator's stage-input kind, construction, target measurement, and companion measurements. Stage inputs are limited to `raw-resource-set`, `html-token-stream`, `composed-tree`, `styled-tree`, `asset-tree`, `layout-tree`, and `render-tree`. The integrity checker performs the specific bounded construction and independently derives every measurement rather than trusting reported measurements. An at-limit construction may exceed no ceiling and has the exact accepted lifecycle terminal object; an over-limit construction exceeds only its named ceiling by exactly one and has the exact rejected stage, `limit-exceeded` code, resource, null offset, limit ID, and uncommitted result. These typed future-stage inputs make large limits executable without claiming an HTML/CSS runtime parser.

| Limit ID | Ceiling | Unit | Evaluation stage |
| --- | ---: | --- | --- |
| `source-file-bytes` | 65536 | UTF-8 bytes per resource | load |
| `aggregate-loaded-bytes` | 262144 | UTF-8 bytes across unique resources | load |
| `expanded-text-bytes` | 524288 | UTF-8 bytes after composition | compose |
| `html-tokens` | 32768 | emitted markup tokens | parse |
| `expanded-dom-nodes` | 4096 | composed element and text nodes | compose |
| `dom-depth` | 32 | composed levels | compose |
| `attributes-per-element` | 16 | attributes on one element | parse |
| `string-code-units` | 4096 | UTF-16 code units in one string | parse |
| `identifier-length` | 64 | ASCII characters | parse |
| `include-count` | 64 | expanded includes | compose |
| `include-depth` | 8 | active include levels | compose |
| `stylesheet-count` | 16 | inline and unique linked stylesheets | style |
| `css-rules` | 512 | rules across stylesheets | style |
| `selectors-per-group` | 8 | selectors in one group | style |
| `selector-terms` | 16 | terms in one selector | style |
| `declarations-per-rule` | 64 | declarations in one rule | style |
| `variable-depth` | 16 | active variable references | style |
| `repeat-items` | 64 | items consumed by one repeat | compose |
| `state-alternatives` | 16 | sibling state alternatives | compose |
| `svg-nodes` | 256 | nodes in one SVG | asset |
| `svg-depth` | 16 | SVG levels | asset |
| `path-tokens` | 2048 | tokens in one path value | asset |
| `path-commands` | 512 | commands in one path value | asset |
| `generic-components` | 512 | accepted `vw-` elements | layout |
| `native-display-objects` | 4096 | pending display objects | render |

These values are compatibility and resource-control ceilings, not measured performance targets. They provide generalized headroom for the current consumers and the bundled Example Consumer, but only a future engine implementation plus native runtime evidence can establish responsiveness, rendering correctness, or safe target-platform performance.

## One failure and one transaction

Every load or update attempt returns exactly one object containing `contract`, `status`, `stage`, `code`, `resource`, `offset`, `limitId`, and `committed`. Competing errors use one complete total order: stage declaration order; lowest entry-first, depth-first resource-discovery index; non-null source offset before null; lowest nonnegative source offset; diagnostic code declaration order; for `limit-exceeded`, limit declaration order; then normalized resource ordinal. If all keys tie, the terminal objects are identical. No separate same-offset rule overrides or competes with this order.

The engine builds a pending tree isolated from the currently committed content. Only a candidate that completes render and its ready lifecycle successfully can commit, immediately before its terminal accepted result. A rejection, cancellation, or adapter failure disposes every pending binding, asset, and display object exactly once and publishes no partial content. A cleanup error is a secondary observation and cannot replace the selected primary error. If a replacement is rejected or cancelled, the previously committed content remains active; `committed` is `false` because the failed candidate did not replace it.

## Conformance corpus

[`Tests/HtmlEngine/corpus.json`](../Tests/HtmlEngine/corpus.json) indexes valid, boundary, malformed, hostile, cycle, traversal, unsupported-feature, and exhaustion cases. File-backed physical resources live below `Tests/HtmlEngine/fixtures/<category>/<case>/` and carry canonical-LF byte count, code-unit count, and SHA-256 facts. Modeled resources use an explicitly absent path or canonical base64 bytes plus a raw SHA-256, allowing resource-unavailable, byte-order-mark, and invalid-UTF-8 cases without corrupting the corpus. Binding metadata is separately indexed and digest-frozen as out-of-band data; the valid fixtures exercise all four binding types, and focused invalid fixtures cover a non-finite number, wrong typed default, nested array, nested object, unknown entry field, and wrong consumer association. Typed `VWCANVAS_HTML_INPUT/1` observations record byte acquisition, strict decoding, plain-String creation, the single selected Canvas parser per runtime resource, and zero forbidden-backend calls for representative document with compose-time template cloning, CSS, SVG, unavailable, BOM, and invalid-UTF-8 paths. Typed `VWCANVAS_HTML_SEMANTICS/1` observations fix expected CSS variable resolution values and omitted SVG defaults without treating them as recorded runtime output. Failure scenarios record competing primary errors, cleanup, single terminal publication, and committed-tree preservation; paired forward and reverse limit-error permutations prove declaration-order selection is input-order independent. Typed snapshot-update scenarios cover successful false-to-true-to-false-to-true state changes, zero-to-one-to-zero-to-one repeat changes, invariant parse counts for retained resources, and a newly activated asset failure that disposes pending ownership without caching the new resource or replacing the committed tree. The integrity check validates these declarations, observations, hashes, and concrete recipe measurements without implementing or executing an HTML parser, CSS parser, SVG parser, snapshot-update engine, or renderer.

Run the focused integrity check from the repository root:

```powershell
pwsh -NoProfile -File Tools/testHtmlEngineContract.ps1
```

The broader source-only repository verification invokes that check alongside the existing build, setup, and packaging tooling checks:

```powershell
pwsh -NoProfile -File Tools/verifyCanvas.ps1 -SourceOnly
```

The bundled Example Consumer fixture demonstrates the static contract surface it needs: local CSS, `$MAIN_Font_Bold`, `18px` text, a typed local string binding with a default, and lifecycle-owned replacement. Actual PlayerData/event adaptation and live rendering remain future implementation and runtime acceptance work.
