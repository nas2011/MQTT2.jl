# MQTT2.jl

A high-performance, full-featured MQTT 5.0 client library for the Julia programming language.

## Design Goals

`MQTT2.jl` is designed to be robust, asynchronous, and easy to integrate into larger Julia applications. Key architectural features include:

- **Multi-Threaded Execution**: Uses `Threads.@spawn` to run background tasks (socket reader, message dispatcher, and keep-alive loop) in parallel across available CPU threads.
- **Asynchronous Message Dispatch**: Incoming `PUBLISH` packets are buffered into a `Channel`, decoupling the network reader from user-defined message handlers. This prevents a slow handler from blocking the reception of new packets.
- **Immediate Acknowledgements**: To prevent broker timeouts, QoS 1 and 2 acknowledgments (`PUBACK`/`PUBREC`) are sent immediately by the reader task before messages are queued for processing.
- **Topic Wildcard Support**: Implements full MQTT spec wildcard matching (`+` and `#`), allowing for flexible message routing to specific handlers.
- **World Age Safety**: Uses `Base.invokelatest` for calling user handlers, ensuring compatibility with functions defined dynamically (e.g., in a REPL session).

## Features

- **Full MQTT 5.0 Support**: Includes support for Properties, User Properties, Reason Codes, and Subscription Identifiers.
- **Automatic Reconnection**: Automatically re-establishes connection on unexpected disconnects with an exponential backoff strategy ($3^n$ seconds).
- **Session Resumption**: Automatically restores subscriptions and replays in-flight QoS 1/2 messages after a reconnection.
- **Last Will and Testament (LWT)**: Configure a message to be published by the broker if the client disconnects unexpectedly.
- **Reliable Messaging**: Full implementation of the MQTT 5.0 ACK state machine for QoS 1 and QoS 2.
- **Lifecycle Callbacks**: Register `onConnect` and `onDisconnect` hooks to manage application state.
- **Deduplicated Message Routing**: Uses MQTT 5.0 Subscription Identifiers to ensure messages are only delivered once to a client, even with overlapping topic filters.
- **Auto-Keep-Alive**: Automatically manages `PINGREQ`/`PINGRESP` exchanges in the background.
- **Topic-Specific Handlers**: Register unique callback functions for different topic filters.
- **Global Handler**: Optional catch-all handler for all incoming messages.
- **Thread-Safe**: Designed to handle concurrent publishing and subscription management.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/nas2011/MQTT2.jl")
```

## Example Usage

The following example demonstrates how to configure a client with a Last Will, handle lifecycle events, and use reliable messaging.

```julia
using MQTT2

# 1. Configure the client
# Includes Last Will and Testament (LWT) and Reconnection settings
config = ClientConfig(
    host = "broker.hivemq.com",
    port = 1883,
    clientId = "julia_client_123",
    reconnectAttempts = 5, # Max attempts with 3^n backoff (3s, 9s, 27s...)
    willTopic = "status/julia_client",
    willPayload = "offline",
    willQos = qos1,
    willRetain = true
)

client = MqttClient(config)

# 2. Register lifecycle callbacks
client.onConnect = (client, connack) -> begin
    println("Connected! Session present: $(connack.sessionPresent)")
end

client.onDisconnect = (client) -> begin
    println("Disconnected from broker.")
end

# 3. Define a handler for a specific topic
function sensor_handler(packet::PublishPacket)
    payload_str = String(packet.payload)
    println("Received sensor data on $(packet.topic): $payload_str")
end

# 4. Connect to the broker
# cleanStart=false allows session resumption if the broker supports it
connect!(client, cleanStart=false)

# 5. Subscribe to a topic filter with QoS 2 (Exactly Once)
subscribe!(client, "sensors/+", sensor_handler, qos=qos2)

# 6. Publish messages using convenience functions
# String payload (automatically converted to bytes)
publish!(client, "sensors/status", "active", qos=qos1)

# Numeric payload (automatically converted to string then bytes)
publish!(client, "sensors/temperature", 23.5, qos=qos1)

# JSON payload using NamedTuples (requires JSON3)
# Single item -> Serialized as JSON object: {"id":1, "value":23.5}
publish!(client, "sensors/json", [(id=1, value=23.5)], qos=qos1)

# Multiple items -> Serialized as JSON array: [{"id":1, "value":23.5}, {...}]
publish!(client, "sensors/json_batch", [(id=1, val=23.5), (id=2, val=24.1)], qos=qos1)

# 7. Unsubscribe from a topic
unsubscribe!(client, ["sensors/+"])

# 8. Disconnect gracefully
disconnect!(client)
```

## Packet Properties (MQTT 5.0)

You can pass `Properties` to most API calls to leverage MQTT 5.0 features:

```julia
props = Properties()
push!(props.userProperties, "AppVersion" => "1.0.0")
props.sessionExpiryInterval = 3600 # 1 hour

connect!(client, properties=props)
```

## Advanced Features

### Automatic Reconnection & Session Resumption
If the network connection is lost, `MQTT2.jl` will:
1. Trigger the `onDisconnect` callback.
2. Attempt to reconnect using the configured `reconnectAttempts`.
3. Wait $3^n$ seconds between attempts (3, 9, 27...).
4. Upon successful reconnection, it will:
    - Re-subscribe to all active topic filters if `sessionPresent` is `false`.
    - Re-send all in-flight QoS 1 and QoS 2 messages with the `dup` flag set.

### Reliable Delivery (QoS 1 & 2)
The client maintains an internal `inflightMessages` dictionary. For QoS 1 and 2, messages are tracked until the full handshake (`PUBACK` or `PUBCOMP`) is completed, ensuring no data loss during transient network failures.

## Bugs / TODO

1. Implement TLS/SSL support.
2. Implement Topic Alias management (MQTT 5.0).
3. Implement Flow Control / Quota management.

## License

MIT License

## AI Disclosure

Coauthored using AI
