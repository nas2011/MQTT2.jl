using Random

"""
    ClientConfig

Configuration options for the MqttClient.
"""
Base.@kwdef struct ClientConfig
    host::String = "localhost"
    port::Int = 1883
    username::Union{Nothing, String} = nothing
    password::Union{Nothing, String} = nothing
    keepAlive::Int = 60
    clientId::String = "julia_$(randstring(8))"
    reconnectAttempts::Int = 5
end

"""
    TopicSubscription

Internal representation of a subscription with its own buffering channel and task.
"""
mutable struct TopicSubscription
    topicFilter::String
    handler::Function
    channel::Channel{PublishPacket}
    task::Union{Nothing, Task}
    subscriptionIdentifier::Union{Nothing, Int}
    qos::QoS
    properties::Properties

    function TopicSubscription(filter::String, handler::Function, channelSize::Int, qos::QoS, properties::Properties; subscriptionIdentifier=nothing)
        new(filter, handler, Channel{PublishPacket}(channelSize), nothing, subscriptionIdentifier, qos, properties)
    end
end

"""
    MqttClient

An MQTT 5.0 client instance.
"""
mutable struct MqttClient
    config::ClientConfig
    socket::Union{Nothing, TCPSocket}
    connected::Bool
    packetIdCounter::UInt16
    subscriptionIdCounter::Int
    
    # Tasks
    readTask::Union{Nothing, Task}
    keepAliveTask::Union{Nothing, Task}
    
    # Global handler for all messages
    onMessage::Union{Nothing, Function}
    # Lifecycle callbacks
    onConnect::Union{Nothing, Function}
    onDisconnect::Union{Nothing, Function}
    # Topic-specific handlers
    subscriptions::Vector{TopicSubscription}
    # In-flight QoS 1/2 messages
    inflightMessages::Dict{UInt16, PublishPacket}

    function MqttClient(config::ClientConfig)
        new(config, nothing, false, 1, 1, nothing, nothing, nothing, nothing, nothing, TopicSubscription[], Dict{UInt16, PublishPacket}())
    end
end

"""
    connect!(client::MqttClient; cleanStart=true, properties=Properties(), username=client.config.username, password=client.config.password)

Establishes a connection to the MQTT broker and sends a CONNECT packet.
"""
function connect!(client::MqttClient; cleanStart=true, properties=Properties(), username=client.config.username, password=client.config.password)
    client.socket = Sockets.connect(client.config.host, client.config.port)
    
    cp = ConnectPacket(
        clientId = client.config.clientId,
        cleanStart = cleanStart,
        keepAlive = client.config.keepAlive,
        properties = properties,
        username = username,
        password = password
    )
    
    write(client.socket, encodePacket(cp))
    
    # Wait for CONNACK
    ack = decodePacket(client.socket)
    if ack isa ConnackPacket
        if ack.reasonCode == 0x00
            client.connected = true
            # Start background tasks
            client.readTask = Threads.@spawn clientReader(client)
            if client.config.keepAlive > 0
                client.keepAliveTask = Threads.@spawn pingLoop(client)
            end
            
            # Trigger onConnect callback
            if !isnothing(client.onConnect)
                Threads.@spawn try
                    Base.invokelatest(client.onConnect, client, ack)
                catch e
                    @error "Error in onConnect handler" exception=(e, catch_backtrace())
                end
            end
            
            return ack
        else
            close(client.socket)
            client.socket = nothing
            error("Connection failed with reason code: $(ack.reasonCode)")
        end
    else
        close(client.socket)
        client.socket = nothing
        error("Expected CONNACK, got $(typeof(ack))")
    end
end

"""
    reconnect!(client::MqttClient)

Internal helper to reconnect the client after a connection loss.
"""
function reconnect!(client::MqttClient)
    attempts = 0
    maxAttempts = client.config.reconnectAttempts
    
    while attempts < maxAttempts
        attempts += 1
        backoff = 3^attempts # Exponential backoff: 3, 9, 27, 81, 243... seconds
        @info "Attempting to reconnect (attempt $attempts/$maxAttempts) in $backoff seconds..."
        sleep(backoff)
        
        try
            # Re-use the existing connect! logic but without starting new tasks yet
            # We need to be careful not to leak tasks.
            # Actually, it's simpler to just perform the low-level connection here.
            client.socket = Sockets.connect(client.config.host, client.config.port)
            
            cp = ConnectPacket(
                clientId = client.config.clientId,
                cleanStart = false, # Resume session if possible
                keepAlive = client.config.keepAlive,
                username = client.config.username,
                password = client.config.password
            )
            write(client.socket, encodePacket(cp))
            
            ack = decodePacket(client.socket)
            if ack isa ConnackPacket && ack.reasonCode == 0x00
                @info "Reconnected successfully."
                client.connected = true
                # Restart ping loop if needed
                if client.config.keepAlive > 0
                    client.keepAliveTask = Threads.@spawn pingLoop(client)
                end
                
                # Re-subscribe to existing filters if it was a clean start or session expired
                if !ack.sessionPresent
                    for sub in client.subscriptions
                        @info "Re-subscribing to $(sub.topicFilter)"
                        # Note: This might need a new packet ID, but we'll use the current counter
                        pid = client.packetIdCounter
                        client.packetIdCounter += 1
                        if client.packetIdCounter == 0 client.packetIdCounter = 1 end
                        
                        subs = [Subscription(topicFilter=sub.topicFilter, qos=sub.qos)]
                        p = SubscribePacket(packetIdentifier=pid, properties=sub.properties, subscriptions=subs)
                        write(client.socket, encodePacket(p))
                    end
                end

                # Replay inflight messages
                for (pid, p) in client.inflightMessages
                    @info "Replaying inflight message $(p.packetIdentifier) to $(p.topic)"
                    # Create a copy with DUP=true
                    dup_p = PublishPacket(
                        dup = true,
                        qos = p.qos,
                        retain = p.retain,
                        topic = p.topic,
                        packetIdentifier = p.packetIdentifier,
                        properties = p.properties,
                        payload = p.payload
                    )
                    write(client.socket, encodePacket(dup_p))
                end

                # Trigger onConnect callback
                if !isnothing(client.onConnect)
                    Threads.@spawn try
                        Base.invokelatest(client.onConnect, client, ack)
                    catch e
                        @error "Error in onConnect handler" exception=(e, catch_backtrace())
                    end
                end

                return true
            end
        catch e
            @warn "Reconnection attempt $attempts failed" exception=(e, catch_backtrace())
        end
    end
    
    @error "Failed to reconnect after $maxAttempts attempts."
    return false
end

"""
    clientReader(client::MqttClient)

Internal loop to read incoming packets from the socket.
"""
function clientReader(client::MqttClient)
    try
        while true
            try
                while client.connected && !eof(client.socket)
                    packet = decodePacket(client.socket)
                    handleIncoming(client, packet)
                end
            catch e
                if client.connected
                    @error "MqttClient reader error" exception=(e, catch_backtrace())
                end
            end
            
            # If we reach here, the connection is lost
            client.connected = false
            
            # Trigger onDisconnect callback
            if !isnothing(client.onDisconnect)
                Threads.@spawn try
                    Base.invokelatest(client.onDisconnect, client)
                catch e
                    @error "Error in onDisconnect handler" exception=(e, catch_backtrace())
                end
            end

            if !isnothing(client.socket)
                try close(client.socket) catch end
                client.socket = nothing
            end
            
            # Try to reconnect
            if !reconnect!(client)
                break # Give up after max attempts
            end
            # If reconnect! succeeded, client.connected is true again and we continue the outer loop
        end
    finally
        client.connected = false
        # Stop all subscription dispatchers
        for sub in client.subscriptions
            close(sub.channel)
        end
        if !isnothing(client.socket)
            try close(client.socket) catch end
        end
    end
end

"""
    pingLoop(client::MqttClient)

Internal loop to send PINGREQ at regular intervals based on keepAlive.
"""
function pingLoop(client::MqttClient)
    # Ping slightly more frequently than keepAlive to be safe
    interval = client.config.keepAlive * 0.75
    @debug "Starting pingLoop with interval $(interval)s"
    try
        while client.connected
            sleep(interval)
            if client.connected
                @debug "Sending PINGREQ"
                write(client.socket, encodePacket(PingreqPacket()))
            end
        end
    catch e
        if client.connected
            @error "MqttClient pingLoop error" exception=(e, catch_backtrace())
        end
    end
end

packetCount = 0

"""
    handleIncoming(client::MqttClient, packet::AbstractMqttPacket)

Dispatches incoming packets to handlers.
"""
function handleIncoming(client::MqttClient, p::PublishPacket)
    @debug "global packet count: $(packetCount)"
    global packetCount +=1
    # Global handler
    if !isnothing(client.onMessage)
        p_global = deepcopy(p)
        Threads.@spawn try
            Base.invokelatest(client.onMessage, p_global)
        catch e
            @error "Error in global onMessage handler" exception=(e, catch_backtrace())
        end
    end
    
    # Topic-specific handlers: Distribute to each matching subscription's channel
    if !isempty(p.properties.subscriptionIdentifiers)
        # MQTT 5.0 routing via subscription identifiers (prevents duplicate delivery from broker)
        for id in p.properties.subscriptionIdentifiers
            for sub in client.subscriptions
                if sub.subscriptionIdentifier == id
                    if isopen(sub.channel)
                        p_sub = deepcopy(p)
                        Threads.@spawn try
                            put!(sub.channel, p_sub)
                        catch e
                            if isopen(sub.channel)
                                @error "Error putting message into sub-channel for '$(sub.topicFilter)'" exception=(e, catch_backtrace())
                            end
                        end
                    end
                    # Found the matching sub, break inner loop for this ID
                    break
                end
            end
        end
    else
        # Fallback to topic matching (for brokers not supporting identifiers or if not assigned)
        for sub in client.subscriptions
            if topicMatches(p.topic, sub.topicFilter)
                @debug ("packet topic ", p.topic, " matches sub topic: ", sub.topicFilter)
                if isopen(sub.channel)
                    # Use Threads.@spawn to avoid blocking the network reader if a sub-channel is full
                    p_sub = deepcopy(p)
                    Threads.@spawn try
                        @debug ("Putting to ", sub.topicFilter, " " , sub.channel, " with length " , sub.channel.n_avail_items)
                        put!(sub.channel, p_sub)
                    catch e
                        if isopen(sub.channel)
                            @error "Error putting message into sub-channel for '$(sub.topicFilter)'" exception=(e, catch_backtrace())
                        end
                    end
                end
            end
        end
    end
    
    # Auto-ack if QoS > 0 (done immediately to free up the broker)
    if p.qos == qos1
        ack = PubackPacket(packetIdentifier = p.packetIdentifier)
        write(client.socket, encodePacket(ack))
    elseif p.qos == qos2
        # For incoming QoS 2, we send PUBREC, then wait for PUBREL, then send PUBCOMP.
        # This implementation currently does a simplified version: send PUBREC.
        # The broker will send PUBREL when it receives our PUBREC.
        rec = PubrecPacket(packetIdentifier = p.packetIdentifier)
        write(client.socket, encodePacket(rec))
    end
end

function handleIncoming(client::MqttClient, p::PubackPacket)
    delete!(client.inflightMessages, p.packetIdentifier)
end

function handleIncoming(client::MqttClient, p::PubrecPacket)
    # Received PUBREC in response to our PUBLISH (QoS 2)
    # We must send PUBREL
    rel = PubrelPacket(packetIdentifier = p.packetIdentifier)
    write(client.socket, encodePacket(rel))
end

function handleIncoming(client::MqttClient, p::PubrelPacket)
    # Received PUBREL from broker (either response to our PUBREC for incoming, 
    # or broker initiated for outgoing if we were the receiver)
    # We must send PUBCOMP
    comp = PubcompPacket(packetIdentifier = p.packetIdentifier)
    write(client.socket, encodePacket(comp))
end

function handleIncoming(client::MqttClient, p::PubcompPacket)
    # Received PUBCOMP in response to our PUBREL (QoS 2)
    # Transaction complete, remove from inflight
    delete!(client.inflightMessages, p.packetIdentifier)
end

function handleIncoming(client::MqttClient, p::PingrespPacket)
    @debug "Received PINGRESP"
end

function handleIncoming(client::MqttClient, p::AbstractMqttPacket)
    # Default handler for other packet types
end

"""
    publish!(client::MqttClient, topic::String, payload::Vector{UInt8}; qos=qos0, retain=false, properties=Properties())

Sends a PUBLISH packet.
"""
function publish!(client::MqttClient, topic::String, payload::Vector{UInt8}; qos=qos0, retain=false, properties=Properties())
    if !client.connected
        error("Client not connected")
    end
    
    pid = nothing
    if qos > qos0
        pid = client.packetIdCounter
        client.packetIdCounter += 1
        if client.packetIdCounter == 0 client.packetIdCounter = 1 end
    end
    
    p = PublishPacket(
        topic = topic,
        payload = payload,
        qos = qos,
        retain = retain,
        packetIdentifier = pid,
        properties = properties
    )
    
    if qos > qos0
        client.inflightMessages[pid] = p
    end
    
    write(client.socket, encodePacket(p))
    return pid
end

"""
    publish!(client::MqttClient, topic::String, payload::String; kwargs...)

Convenience function to publish a string payload. Converts the string to `Vector{UInt8}`.
"""
function publish!(client::MqttClient, topic::String, payload::String; kwargs...)
    return publish!(client, topic, Vector{UInt8}(payload); kwargs...)
end

function startSubscriptionTask!(sub::TopicSubscription)
    sub.task = Threads.@spawn begin
        try
            for p in sub.channel
                try
                    Base.invokelatest(sub.handler, p)
                catch e
                    @error "Error in subscription handler for filter '$(sub.topicFilter)'" exception=(e, catch_backtrace())
                end
            end
        catch e
            @error "Error in subscription task for filter '$(sub.topicFilter)'" exception=(e, catch_backtrace())
        end
    end
end

"""
    subscribe!(client::MqttClient, topicFilter::String, handler::Function; qos=qos0, properties=Properties(), channelSize=1024)

Subscribes to a topic filter with a specific handler function.
"""
function subscribe!(client::MqttClient, topicFilter::String, handler::Function; qos=qos0, properties=Properties(), channelSize=1024)
    if !client.connected
        error("Client not connected")
    end
    
    pid = client.packetIdCounter
    client.packetIdCounter += 1
    if client.packetIdCounter == 0 client.packetIdCounter = 1 end
    
    subId = client.subscriptionIdCounter
    client.subscriptionIdCounter += 1
    
    # Add subscription identifier to properties for the SUBSCRIBE packet
    push!(properties.subscriptionIdentifiers, subId)
    
    # Create and start new subscription
    sub = TopicSubscription(topicFilter, handler, channelSize, qos, deepcopy(properties); subscriptionIdentifier=subId)
    push!(client.subscriptions, sub)
    startSubscriptionTask!(sub)
    
    subs = [Subscription(topicFilter=topicFilter, qos=qos)]
    p = SubscribePacket(packetIdentifier=pid, properties=properties, subscriptions=subs)
    
    write(client.socket, encodePacket(p))
    return pid
end


"""
    unsubscribe!(client::MqttClient, topicFilters::Vector{String}; properties=Properties())

Sends an UNSUBSCRIBE packet and removes handlers for these topics.
"""
function unsubscribe!(client::MqttClient, topicFilters::Vector{String}; properties=Properties())
    if !client.connected
        error("Client not connected")
    end
    
    pid = client.packetIdCounter
    client.packetIdCounter += 1
    if client.packetIdCounter == 0 client.packetIdCounter = 1 end
    
    # Remove handlers and stop tasks
    for tf in topicFilters
        filter!(client.subscriptions) do sub
            if sub.topicFilter == tf
                close(sub.channel)
                return false
            end
            return true
        end
    end
    
    p = UnsubscribePacket(packetIdentifier=pid, properties=properties, topicFilters=topicFilters)
    
    write(client.socket, encodePacket(p))
    return pid
end

"""
    disconnect!(client::MqttClient; reasonCode=0x00, properties=Properties())

Sends a DISCONNECT packet and closes the socket.
"""
function disconnect!(client::MqttClient; reasonCode=0x00, properties=Properties())
    if client.connected
        p = DisconnectPacket(reasonCode=reasonCode, properties=properties)
        write(client.socket, encodePacket(p))
        client.connected = false
        close(client.socket)
    end
end
