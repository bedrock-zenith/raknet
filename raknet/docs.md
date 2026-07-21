### naming conventions

- `orderIndex` -> `epoch_id`
- `sequenceIndex` -> `snapshot_id`
- `reliabilityIndex` -> `reliable_id`
- `frameSet` -> `datagram`
- `frameSet.sequenceId` -> `datagram_id`
- `capsule/frame` -> `segment`
- `orderChannel` -> `channel`
- `fragment/split` -> `fragment`
- `fragment.{.id, .count, .index}` -> `fragment.{.id, .count, .index}`
- `reliability` -> `delivery_policy`

- `rx/tx` ref: `receiver/transmitter`

### WARNING AI SHI.

```
               ┌─────────────────────────┐
               │       Connection        │  <-- Base Reliability Engine
               └─────────────────────────┘      (Shared rx/tx, channels, ACK queues)
                            │
            ┌───────────────┴───────────────┐
            │                               │
┌─────────────────────────┐     ┌─────────────────────────┐
│      ClientSession      │     │      ServerSession      │
│  (Server's view of a    │     │   (Client's view of     │
│     remote client)      │     │     the server host)    │
└─────────────────────────┘     └─────────────────────────┘
             │                               │
┌────────────┴────────────┐     ┌────────────┴────────────┐
│        Listener         │     │        Connector        │
│    (UDP Server Node)    │     │    (UDP Client Node)    │
└─────────────────────────┘     └─────────────────────────┘
```
