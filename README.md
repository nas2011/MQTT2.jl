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

- **Full MQTT 5.0 Support**: Includes support for Properties, User Properties, and Reason Codes.
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

The following example demonstrates how to connect to a broker, subscribe to topics with wildcards, and publish messages.

```julia
using MQTT2

# 1. Configure the client
config = ClientConfig(
    host = "broker.hivemq.com",
    port = 1883,
    clientId = "julia_client_123",
    username = "my_user",
    password = "my_password"
)

client = MqttClient(config)

# 2. Define a handler for a specific topic with wildcards
function sensor_handler(packet::PublishPacket)
    payload_str = String(packet.payload)
    println("Received sensor data on $(packet.topic): $payload_str")
end

# 3. Connect to the broker
println("Connecting...")
connect!(client)

# 4. Subscribe to a topic filter
# This will match topics like "sensors/temperature" or "sensors/humidity"
subscribe!(client, "sensors/+", sensor_handler, qos=qos1)

# 5. Define a global handler (optional)
client.onMessage = (packet) -> begin
    println("Global log: Message on $(packet.topic)")
end

# 6. Publish a message
println("Publishing...")
payload = Vector{UInt8}("23.5°C")
publish!(client, "sensors/temperature", payload, qos=qos1)

# Wait a moment for the message to loop back
sleep(2)

# 7. Disconnect
println("Disconnecting...")
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

## Bugs / TODO

1. Single buffered channel causes first matching topic to posibly read messages from other topics. TODO- Implement channel per topic buffering or cooperative channel reading.

## License

MIT License

## AI Disclosure

Coauthored using AI


