# Canvas datagrams

Canvas datagrams are bounded, atomic application messages carried through Canvas's named-event transport. Canvas owns framing, validation, routing, startup policy, and lifecycle. Publishers and consumers own message meaning.

The Custom Watch alert bridge is nonblocking, lossy, and unordered. A successful Papyrus submission acknowledges only that the native call was made. Canvas does not provide a HUD-to-Papyrus delivery acknowledgement.

## Addressing

Each datagram has two addressing levels:

- The event topic is a stream used for subscription routing, such as `author.navigation` or `author.combat`.
- The message type identifies one schema within that stream, such as `gps.position` or `hit.damage`.

Consumers subscribe to a small number of streams and dispatch any number of message types locally. Canvas does not maintain a global message-type registry or require a central enum.

## Wire envelope

The body of a Canvas datagram uses the following logical shape:

```text
VWDG/1|<message-type-frame><schema-version-frame><encoding-frame><payload-frame>
```

Each frame is a decimal character count, a colon, and that many unescaped characters:

```text
<length>:<value>
```

The envelope fields are:

| Field | Meaning |
| --- | --- |
| `VWDG/1` | Canvas datagram envelope version |
| Message type | Case-insensitive namespaced identifier for an application schema |
| Schema version | Integer in `1..9999` owned by that message type |
| Encoding | Payload encoding; the initial supported value is `ci-ascii` |
| Payload | Application-owned printable ASCII content |

`ci-ascii` means the application treats ASCII letters in the payload as case insensitive. The native alert transport can change ASCII casing. Numeric data and punctuation are unaffected. A future case-preserving encoding can be added as another encoding value without changing the datagram envelope.

The complete framed Canvas event is limited to 4,096 printable ASCII characters. Canvas rejects oversized datagrams and never fragments them automatically.

## Papyrus publishing

```papyrus
OperationResult result = Registry.TryPublishCanvasDatagram(
  "author.navigation",
  "gps.position",
  1,
  "ci-ascii",
  "12.5|-44.25|380.0"
)
```

`TryPublishCanvasDatagram` validates and frames the generic datagram, then performs one `TryPublishCanvasEvent` attempt. Its result has the same transport boundary: `EVENT_SUBMITTED` does not mean that a consumer received, decoded, or displayed the datagram.

`BuildCanvasDatagramBody` builds a body without publishing it. `TryPublishCanvasEvent` remains available for existing consumers and application-owned protocols.

## ActionScript decoding

```actionscript
var datagram:Object = CanvasDatagramCodec.decode(body);
if(datagram.messageType == "gps.position" && datagram.schemaVersion == 1)
{
   handleGpsPosition(String(datagram.payload));
}
```

Consumer contract 3 causes Canvas to validate the generic envelope before delivery. Application adapters validate their own payload schemas and commit state only after the complete payload passes.

Unknown envelope versions, encodings, message types, and application schema versions should be rejected without changing the last valid application state.

## Consumer contract 3

`VWCANVAS_CONSUMER/3` replaces the v2 topic list and global startup-queue Boolean with per-stream subscriptions:

```actionscript
{
   "protocol":"VWCANVAS_CONSUMER/3",
   "minimumContractVersion":3,
   "maximumContractVersion":3,
   "eventSubscriptions":[
      {"topic":"author.navigation","startup":"latest"},
      {"topic":"author.combat","startup":"fifo"},
      {"topic":"author.transient","startup":"drop"}
   ]
}
```

Each startup policy applies while that consumer is loading:

| Policy | Behavior before lifecycle `ready` | Typical use |
| --- | --- | --- |
| `drop` | Reject the datagram | Input or transient observations that should not replay |
| `latest` | Retain the newest received datagram for each message type, schema version, and encoding in that stream | Status, position, target state, clocks |
| `fifo` | Retain bounded datagrams in received order | Hits, alerts, notifications |

The queue remains bounded to 64 datagrams and 65,536 combined topic/body characters per consumer. A `latest` stream can multiplex many state schemas because coalescing uses the generic message type, schema version, and encoding as its key. Replacing an older datagram with the same identity is normal coalescing; other queue eviction is reported in Canvas diagnostics.

`VWCANVAS_CONSUMER/2` remains supported. Its existing settings map to the same internal policies:

- `queueEventsUntilReady: false` maps every registered topic to `drop`.
- `queueEventsUntilReady: true` maps every registered topic to `fifo`.

Current limits are 32 active consumers, 16 subscribed streams per consumer, 96 characters per stream topic, and 4,096 characters per complete event. Logical message types do not consume subscription slots.

## Version evolution

The envelope version, application schema version, and consumer contract version have separate compatibility rules:

- `VWDG/1` changes only when the generic framing itself becomes incompatible. Canvas can add another envelope decoder without changing application message types.
- The schema version is scoped to one application message type. A consumer may accept one version, several versions, or a bounded version range and should leave its last valid state unchanged when it receives an unsupported version.
- `VWCANVAS_CONSUMER/3` describes registration and startup behavior. It does not force every application message type to use the same schema version.

Canvas does not negotiate application schemas. During a compatibility transition, a publisher can emit the same state in both the old and new schema versions. A `latest` startup queue retains one datagram for each version because the coalescing identity includes message type, schema version, and encoding. Consumers that support both versions should define which version wins so receive order cannot downgrade their state. A publisher can use a new message type when the new payload represents a different concept rather than a new version of the same concept.

## Ordering and reliability

Canvas does not add or compare sequence numbers, revisions, timestamps, transaction IDs, or event IDs. The transport makes each datagram independently valid.

An application schema can carry its own metadata when needed. A position sample may include a source time, a combat event may include an event ID, and a replicated data set may include a revision. These fields remain application data and do not change Canvas routing.

For current-state messages, the usual behavior is arrival-order replacement followed by a periodic or lifecycle-triggered refresh. A dropped datagram leaves the previous valid state in place. A delayed older datagram can temporarily replace newer state when the application schema has no ordering field.

For occurrence messages, every received datagram is a separate occurrence. Consumers that need duplicate detection must define it in their message schema.

## Example schemas

| Stream | Message type | Example payload | Meaning |
| --- | --- | --- | --- |
| `venworks.canvas.example.status` | `effects.state` | `0|2|D:DEHYDRATED;D:MALNOURISHED;` | Complete current effect arrays |
| `author.navigation` | `gps.position` | `12.5|-44.25|380.0` | One independent position sample |
| `author.combat` | `hit.damage` | `player|47.5|physical` | One hit occurrence |
| `author.combat` | `target.state` | `target-42|320|500` | Complete current target state |

The Example publishes an empty effect state as `0|0|`. Apply, removal, HUD recreation, and periodic resynchronization each produce another complete `effects.state` datagram. Its Canvas adapter validates counts and entries, replaces both arrays atomically, and suppresses identical state before calling the HTML bridge.

## Large data

One datagram must fit the transport limit and be meaningful by itself. Applications can send a compact complete state, independent keyed records, or an application-specific large-data protocol. Canvas does not claim transaction completeness for application-level multipart data.
