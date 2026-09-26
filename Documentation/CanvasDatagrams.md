# Send data with Canvas datagrams

Canvas datagrams let a Papyrus script send a small, self-contained message to one or more Canvas panels. Canvas handles the packaging and routing; your mod decides what the message means.

Use a datagram when your panel needs mod-owned data that is not already available through a Canvas UI channel. Good examples include a current quest state, a selected target, a GPS sample, or a combat notification.

## The three names you choose

Every datagram needs:

| Part | Example | Purpose |
| --- | --- | --- |
| Topic | `author.navigation` | Groups related messages and gives consumers something to subscribe to. |
| Message type | `gps.position` | Identifies the kind of message inside that topic. |
| Schema version | `1` | Lets you change the payload format later without silently misreading old data. |

Use namespaced lowercase names so they do not collide with another mod. Canvas treats topic names as ASCII case insensitive and delivers them to consumers in lowercase.

A topic is also the unit that receives one startup behavior. Put current state and one-time occurrences on different topics when they should behave differently while a panel is loading. For example, use `author.combat.state` for the current target and `author.combat.events` for individual hits.

## Publish from Papyrus

Call `TryPublishCanvasDatagram` with the topic, message type, schema version, encoding, and payload:

```papyrus
OperationResult result = Registry.TryPublishCanvasDatagram(
  "author.navigation",
  "gps.position",
  1,
  "ci-ascii",
  "12.5|-44.25|380.0"
)
Registry.LogOperation(result)
```

The current encoding is `ci-ascii`, which means payload letters must be treated as case insensitive. The underlying Starfield alert transport can change letter casing. Numbers and punctuation are unaffected, so compact numeric or token-based payloads work well.

`EVENT_SUBMITTED` means the native send call accepted this attempt. It does not mean a panel received, decoded, or displayed the message. Do not clear important state merely because the publish call returned that status.

## Subscribe in the consumer SWF

Declare each topic and what Canvas should do with messages received while the consumer is loading:

```actionscript
public function getCanvasRegistration() : Object
{
   return {
      "protocol":"VWCANVAS_CONSUMER/3",
      "consumerId":"your-generated-uuid",
      "assetNamespace":"author.navigation-panel",
      "version":1,
      "minimumContractVersion":3,
      "maximumContractVersion":3,
      "hostKinds":["player"],
      "uiChannels":[],
      "eventSubscriptions":[
         {"topic":"author.navigation","startup":"latest"}
      ]
   };
}
```

Choose the startup behavior that matches the meaning of the topic:

| Startup behavior | Use it for | What happens before the panel is ready |
| --- | --- | --- |
| `latest` | Current state such as status, position, target, or clock | Canvas keeps the newest message for each message type and version, then gives that state to the panel when it is ready. |
| `fifo` | Separate occurrences such as hits, alerts, or notifications | Canvas keeps a bounded first-in, first-out list after the consumer has joined the topic. |
| `drop` | Input or temporary observations that should never replay | Canvas rejects messages that arrive before the panel is ready. |

`latest` can also retain valid state published before this consumer finished joining the topic. `fifo` does not replay messages sent before membership existed.

## Receive and validate in ActionScript

Canvas validates the general datagram before it reaches a version 3 consumer. Your adapter still needs to validate its own message type, schema version, and payload.

```actionscript
public function handleCanvasEvent(topic:String, body:String) : void
{
   if(topic != "author.navigation")
   {
      return;
   }

   var datagram:Object = CanvasDatagramCodec.decode(body);
   if(datagram.messageType != "gps.position" ||
      datagram.schemaVersion != 1 ||
      datagram.encoding != "ci-ascii")
   {
      return;
   }

   var fields:Array = String(datagram.payload).split("|");
   if(fields.length != 3)
   {
      return;
   }

   var x:Number = Number(fields[0]);
   var y:Number = Number(fields[1]);
   var z:Number = Number(fields[2]);
   if(!isFinite(x) || !isFinite(y) || !isFinite(z))
   {
      return;
   }

   this.position = {"x":x,"y":y,"z":z};
   this.publishCompleteViewModel();
}
```

Adapt the final assignment and publish call to your consumer's saved view model. Validate the complete payload before changing visible state. An unknown message type, schema version, encoding, missing field, invalid number, or out-of-range value should leave the last valid state in place.

## Design a useful payload

Keep each datagram meaningful on its own. Canvas does not join several datagrams into one transaction for you.

For current state, send a complete compact snapshot whenever the state changes and refresh it periodically or after relevant lifecycle events. If one update is lost, a later complete snapshot can repair the display.

For occurrences, make every datagram one occurrence. Add an application-owned event ID only when your consumer needs duplicate detection.

Canvas does not add sequence numbers, timestamps, revisions, or transaction IDs. Put one of those fields in your payload only when your message actually needs it, then validate it in the consumer.

## Example: the shipped effect panel

The shipped Example uses:

| Part | Value |
| --- | --- |
| Topic | `venworks.canvas.example.status` |
| Message type | `effects.state` |
| Schema version | `1` |
| Startup behavior | `latest` |
| Empty state payload | `0|0|` |

Its Papyrus registrar sends one complete list of active buff and debuff rows. The consumer validates the counts and every entry, replaces both arrays together, and ignores an identical state before updating the HTML document. Effect changes, removals, HUD recreation, and periodic recovery each create another complete snapshot.

This pattern is a good default for a status panel: publish complete state, use `latest`, validate before committing, and refresh after lifecycle events.

## Delivery rules to plan for

- Delivery is temporary, nonblocking, and not guaranteed.
- Messages can be lost or arrive out of order.
- `EVENT_SUBMITTED` is a send receipt, not a display receipt.
- A delayed old message can replace newer state unless your payload includes and checks an ordering field.
- Current-state panels should periodically republish or refresh after lifecycle changes.
- Consumers that need duplicate detection must define an event ID in their own schema.
- Payload letters may change case when using `ci-ascii`.

## Practical limits

| Limit | Current value |
| --- | --- |
| Complete Canvas event | 4,096 printable ASCII characters |
| Subscribed topics per consumer | 16 |
| Topic length | 96 characters |
| Active consumers | 32 |
| Retained state cache and each loading consumer's startup queue | 64 datagrams and 65,536 combined topic/body characters per queue |

Canvas rejects an oversized message instead of splitting it. For larger data, send a smaller complete summary, send independent keyed records that are useful by themselves, or define and verify your own multipart protocol. Canvas does not promise that every part of an application-level multipart transfer will arrive.

## Updating a schema

Increase the schema version when the same message type needs an incompatible payload format. During a transition, a publisher can send both versions and consumers can accept the versions they understand.

If the new payload represents a different concept rather than a new format for the same concept, give it a new message type instead.

Canvas does not negotiate application schemas. When a consumer accepts more than one version, define which version wins so that a delayed older message cannot downgrade the displayed state.

## Compatibility with older consumers

`VWCANVAS_CONSUMER/2` remains supported for existing add-ons. Its one queue setting maps to the newer startup behaviors:

- `queueEventsUntilReady: false` maps registered topics to `drop`.
- `queueEventsUntilReady: true` maps registered topics to `fifo`.

Use `VWCANVAS_CONSUMER/3` for new work because it lets each topic choose `drop`, `latest`, or `fifo` and gives Canvas enough information to validate the datagram envelope before delivery.

For a complete panel walkthrough, see [Create a Canvas plugin from scratch](CreatingACanvasPlugin.md). For visible HTML, CSS, and binding examples, see the [Canvas component gallery](CanvasComponentGallery.md).
