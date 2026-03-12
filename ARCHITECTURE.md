# MQTT2.jl Architecture

This document describes the internal architecture of the MQTT2.jl client, focusing on the asynchronous message distribution and handling system.

## Core Components

### `MqttClient`
The central coordinator. It manages the TCP connection, keeps track of active subscriptions, and coordinates the background tasks.
- **`subscriptions`**: A vector of `TopicSubscription` objects.
- **`onMessage`**: An optional global handler executed for *every* incoming `PUBLISH` packet.
- **`subscriptionIdCounter`**: A monotonically increasing counter used to assign unique IDs to each new subscription.

### `TopicSubscription`
Encapsulates the processing logic for a specific topic filter.
- **`channel`**: A buffered `Channel{PublishPacket}`. This acts as a per-subscription mailbox, isolating it from other handlers.
- **`task`**: A dedicated `Threads.@spawn` loop that pulls messages from the channel and executes the user-provided handler.
- **`subscriptionIdentifier`**: An optional MQTT 5.0 integer ID used for deduplicated routing.

## Message Flow (Incoming `PUBLISH`)

When a `PUBLISH` packet arrives from the broker, it follows this path:

1.  **Network Reader (`clientReader`)**:
    - Runs in a background thread.
    - Reads raw bytes from the socket and decodes them into an `AbstractMqttPacket`.
    - Calls `handleIncoming(client, packet)`.

2.  **Dispatch Logic (`handleIncoming`)**:
    - **Global Handler**: If `client.onMessage` is defined, it is executed in a new `Threads.@spawn` task.
    - **Routing Strategy**:
        - **MQTT 5.0 Identifiers**: If the packet contains `subscriptionIdentifiers`, the client routes the message *only* to subscriptions whose internal `subscriptionIdentifier` matches one of the IDs in the packet. This prevents duplicate delivery when a client has multiple overlapping filters (e.g., `test/#` and `test/topic`).
        - **Topic Matching (Fallback)**: If no identifiers are present (e.g., MQTT 3.1.1 broker or no IDs assigned), the client iterates through all active subscriptions and uses `topicMatches(packet.topic, filter)` to find recipients.
    - **Asynchronous Fan-out**: For every matching subscription, a `Threads.@spawn` task is created to `put!` a `deepcopy` of the message into that subscription's private `channel`.
        - *Benefit*: This ensures the `clientReader` never blocks, even if a subscription's buffer is full or its handler is slow.

3.  **Subscription Processing (`startSubscriptionTask!`)**:
    - Each subscription has its own persistent worker task.
    - It waits on `take!(sub.channel)`.
    - When a message arrives, it executes the handler using `Base.invokelatest` (to ensure compatibility with new code loaded into the Julia session).

## Function Call Diagram

```text
[ Broker ]
    |
    | (TCP Stream)
    v
[ clientReader ] ----------------------> [ handleIncoming(::PublishPacket) ]
    |                                        |
    |                                        +-- [ Threads.@spawn ] --> [ onMessage(p) ]
    |                                        |
    |                                        +-- [ Has Subscription IDs? ]
    |                                                |
    |                                                +-- YES: Match by ID
    |                                                |
    |                                                +-- NO: Match by topic string
    |                                                |
    |                                                v
    |                                          [ for each matching sub ]
    |                                                |
    |                                                v
    |                                          [ Threads.@spawn ]
    |                                                |
    |                                                v
    |                                          [ put!(sub.channel, deepcopy(p)) ]
    |                                                |
    |                                                v
    |                                          [ sub.task (loop) ]
    |                                                |
    |                                                v
    |                                          [ Base.invokelatest(sub.handler, p) ]
```

## Resource Management

- **Isolation**: A slow or crashed handler for one topic filter does not affect the delivery of messages to other filters.
- **Buffer Control**: The `channelSize` (default: 1024) can be configured per subscription in `subscribe!`.
- **Cleanup**: When `unsubscribe!` is called or the client disconnects, the respective channels are `close()`-ed, which naturally terminates the associated processing tasks.
