# MQTT 5.0 Encoding and Decoding Logic

"""
    encodeProperties(props::Properties) -> Vector{UInt8}

Encodes the Properties struct into a sequence of bytes, preceded by the Property Length (VBI).
"""
function encodeProperties(props::Properties)
    buf = IOBuffer()
    
    if !isnothing(props.sessionExpiryInterval)
        write(buf, SESSION_EXPIRY_INTERVAL)
        writeUint32(buf, props.sessionExpiryInterval)
    end
    if !isnothing(props.receiveMaximum)
        write(buf, RECEIVE_MAXIMUM)
        writeUint16(buf, props.receiveMaximum)
    end
    if !isnothing(props.maximumPacketSize)
        write(buf, MAXIMUM_PACKET_SIZE)
        writeUint32(buf, props.maximumPacketSize)
    end
    if !isnothing(props.topicAliasMaximum)
        write(buf, TOPIC_ALIAS_MAXIMUM)
        writeUint16(buf, props.topicAliasMaximum)
    end
    if !isnothing(props.topicAlias)
        write(buf, TOPIC_ALIAS)
        writeUint16(buf, props.topicAlias)
    end
    if !isnothing(props.requestResponseInformation)
        write(buf, REQUEST_RESPONSE_INFORMATION)
        write(buf, props.requestResponseInformation)
    end
    if !isnothing(props.requestProblemInformation)
        write(buf, REQUEST_PROBLEM_INFORMATION)
        write(buf, props.requestProblemInformation)
    end
    for pair in props.userProperties
        write(buf, USER_PROPERTY)
        write(buf, encodeString(pair.first))
        write(buf, encodeString(pair.second))
    end
    if !isnothing(props.authenticationMethod)
        write(buf, AUTHENTICATION_METHOD)
        write(buf, encodeString(props.authenticationMethod))
    end
    if !isnothing(props.authenticationData)
        write(buf, AUTHENTICATION_DATA)
        writeUint16(buf, UInt16(length(props.authenticationData)))
        write(buf, props.authenticationData)
    end
    if !isnothing(props.messageExpiryInterval)
        write(buf, MESSAGE_EXPIRY_INTERVAL)
        writeUint32(buf, props.messageExpiryInterval)
    end
    if !isnothing(props.payloadFormatIndicator)
        write(buf, PAYLOAD_FORMAT_INDICATOR)
        write(buf, props.payloadFormatIndicator)
    end
    if !isnothing(props.contentType)
        write(buf, CONTENT_TYPE)
        write(buf, encodeString(props.contentType))
    end
    if !isnothing(props.responseTopic)
        write(buf, RESPONSE_TOPIC)
        write(buf, encodeString(props.responseTopic))
    end
    if !isnothing(props.correlationData)
        write(buf, CORRELATION_DATA)
        writeUint16(buf, UInt16(length(props.correlationData)))
        write(buf, props.correlationData)
    end
    if !isnothing(props.subscriptionIdentifier)
        write(buf, SUBSCRIPTION_IDENTIFIER)
        write(buf, encodeVbi(props.subscriptionIdentifier))
    end
    if !isnothing(props.assignedClientIdentifier)
        write(buf, ASSIGNED_CLIENT_IDENTIFIER)
        write(buf, encodeString(props.assignedClientIdentifier))
    end
    if !isnothing(props.serverKeepAlive)
        write(buf, SERVER_KEEP_ALIVE)
        writeUint16(buf, props.serverKeepAlive)
    end
    if !isnothing(props.reasonString)
        write(buf, REASON_STRING)
        write(buf, encodeString(props.reasonString))
    end
    if !isnothing(props.willDelayInterval)
        write(buf, WILL_DELAY_INTERVAL)
        writeUint32(buf, props.willDelayInterval)
    end

    propsBytes = take!(buf)
    vbiLen = encodeVbi(length(propsBytes))
    return vcat(vbiLen, propsBytes)
end

"""
    decodeProperties(stream::IO) -> Properties

Decodes the Properties block from a sequence of bytes.
"""
function decodeProperties(stream::IO)
    len = decodeVbi(stream)
    props = Properties()
    if len == 0
        return props
    end
    
    propBytes = read(stream, len)
    buf = IOBuffer(propBytes)
    
    while !eof(buf)
        id = read(buf, UInt8)
        if id == SESSION_EXPIRY_INTERVAL
            props.sessionExpiryInterval = readUint32(buf)
        elseif id == RECEIVE_MAXIMUM
            props.receiveMaximum = readUint16(buf)
        elseif id == MAXIMUM_PACKET_SIZE
            props.maximumPacketSize = readUint32(buf)
        elseif id == TOPIC_ALIAS_MAXIMUM
            props.topicAliasMaximum = readUint16(buf)
        elseif id == TOPIC_ALIAS
            props.topicAlias = readUint16(buf)
        elseif id == REQUEST_RESPONSE_INFORMATION
            props.requestResponseInformation = read(buf, UInt8)
        elseif id == REQUEST_PROBLEM_INFORMATION
            props.requestProblemInformation = read(buf, UInt8)
        elseif id == USER_PROPERTY
            key = decodeString(buf)
            val = decodeString(buf)
            push!(props.userProperties, key => val)
        elseif id == AUTHENTICATION_METHOD
            props.authenticationMethod = decodeString(buf)
        elseif id == AUTHENTICATION_DATA
            vlen = readUint16(buf)
            props.authenticationData = read(buf, vlen)
        elseif id == MESSAGE_EXPIRY_INTERVAL
            props.messageExpiryInterval = readUint32(buf)
        elseif id == PAYLOAD_FORMAT_INDICATOR
            props.payloadFormatIndicator = read(buf, UInt8)
        elseif id == CONTENT_TYPE
            props.contentType = decodeString(buf)
        elseif id == RESPONSE_TOPIC
            props.responseTopic = decodeString(buf)
        elseif id == CORRELATION_DATA
            vlen = readUint16(buf)
            props.correlationData = read(buf, vlen)
        elseif id == SUBSCRIPTION_IDENTIFIER
            props.subscriptionIdentifier = decodeVbi(buf)
        elseif id == ASSIGNED_CLIENT_IDENTIFIER
            props.assignedClientIdentifier = decodeString(buf)
        elseif id == SERVER_KEEP_ALIVE
            props.serverKeepAlive = readUint16(buf)
        elseif id == REASON_STRING
            props.reasonString = decodeString(buf)
        elseif id == WILL_DELAY_INTERVAL
            props.willDelayInterval = readUint32(buf)
        else
            error("Unknown Property Identifier: $id")
        end
    end
    return props
end

"""
    encodePacket(packet::AbstractMqttPacket) -> Vector{UInt8}

Generic entry point to encode any MQTT Control Packet.
"""
function encodePacket(packet::AbstractMqttPacket)
    typeByte, variableHeader, payload = encodeParts(packet)
    
    remainingLength = length(variableHeader) + length(payload)
    vbiLen = encodeVbi(remainingLength)
    
    return vcat(typeByte, vbiLen, variableHeader, payload)
end

"""
    decodePacket(stream::IO) -> AbstractMqttPacket

Generic entry point to decode any MQTT Control Packet from a stream.
"""
function decodePacket(stream::IO)
    firstByte = read(stream, UInt8)
    type = firstByte >> 4
    flags = firstByte & 0x0F
    
    remainingLength = decodeVbi(stream)
    
    # Read the rest of the packet into a buffer
    packetData = read(stream, remainingLength)
    buf = IOBuffer(packetData)
    
    if type == CONNECT
        return decodeConnect(buf)
    elseif type == CONNACK
        return decodeConnack(buf)
    elseif type == PUBLISH
        return decodePublish(flags, buf)
    elseif type == PUBACK
        return decodeAck(PubackPacket, buf)
    elseif type == PUBREC
        return decodeAck(PubrecPacket, buf)
    elseif type == PUBREL
        return decodeAck(PubrelPacket, buf)
    elseif type == PUBCOMP
        return decodeAck(PubcompPacket, buf)
    elseif type == SUBSCRIBE
        return decodeSubscribe(buf)
    elseif type == SUBACK
        return decodeSuback(buf)
    elseif type == UNSUBSCRIBE
        return decodeUnsubscribe(buf)
    elseif type == UNSUBACK
        return decodeUnsuback(buf)
    elseif type == PINGREQ
        return PingreqPacket()
    elseif type == PINGRESP
        return PingrespPacket()
    elseif type == DISCONNECT
        return decodeDisconnect(buf)
    elseif type == AUTH
        return decodeAuth(buf)
    else
        error("Unknown Packet Type: $type")
    end
end

# --- Specific Packet Part Encoders ---

function encodeParts(p::ConnectPacket)
    typeByte = (CONNECT << 4)
    
    vh = IOBuffer()
    write(vh, encodeString(p.protocolName))
    write(vh, p.protocolVersion)
    
    connectFlags = UInt8(0)
    if !isnothing(p.username) connectFlags |= 0x80 end
    if !isnothing(p.password) connectFlags |= 0x40 end
    if p.willRetain          connectFlags |= 0x20 end
    connectFlags |= (UInt8(p.willQos) << 3)
    if p.willFlag            connectFlags |= 0x04 end
    if p.cleanStart         connectFlags |= 0x02 end
    
    write(vh, connectFlags)
    writeUint16(vh, p.keepAlive)
    write(vh, encodeProperties(p.properties))
    
    pl = IOBuffer()
    write(pl, encodeString(p.clientId))
    if p.willFlag
        write(pl, encodeProperties(p.willProperties))
        write(pl, encodeString(p.willTopic))
        # Will Payload is Binary Data (2-byte length + bytes)
        writeUint16(pl, UInt16(length(p.willPayload)))
        write(pl, p.willPayload)
    end
    if !isnothing(p.username)
        write(pl, encodeString(p.username))
    end
    if !isnothing(p.password)
        writeUint16(pl, UInt16(length(p.password)))
        write(pl, p.password)
    end
    
    return typeByte, take!(vh), take!(pl)
end

function encodeParts(p::ConnackPacket)
    typeByte = (CONNACK << 4)
    vh = IOBuffer()
    write(vh, p.sessionPresent ? 0x01 : 0x00)
    write(vh, p.reasonCode)
    write(vh, encodeProperties(p.properties))
    return typeByte, take!(vh), UInt8[]
end

function encodeParts(p::PublishPacket)
    typeByte = (PUBLISH << 4)
    if p.dup    typeByte |= 0x08 end
    typeByte |= (UInt8(p.qos) << 1)
    if p.retain typeByte |= 0x01 end
    
    vh = IOBuffer()
    write(vh, encodeString(p.topic))
    if p.qos > qos0
        writeUint16(vh, p.packetIdentifier)
    end
    write(vh, encodeProperties(p.properties))
    
    return typeByte, take!(vh), p.payload
end

# Generic encoder for PUBACK, PUBREC, PUBREL, PUBCOMP
for (T, code) in [(PubackPacket, PUBACK), (PubrecPacket, PUBREC), (PubrelPacket, PUBREL), (PubcompPacket, PUBCOMP)]
    @eval function encodeParts(p::$T)
        typeByte = ($code << 4)
        if $code == PUBREL
            typeByte |= 0x02 # Bit 1 is 1 for PUBREL
        end
        vh = IOBuffer()
        writeUint16(vh, p.packetIdentifier)
        write(vh, p.reasonCode)
        write(vh, encodeProperties(p.properties))
        return typeByte, take!(vh), UInt8[]
    end
end

function encodeParts(p::SubscribePacket)
    typeByte = (SUBSCRIBE << 4) | 0x02
    vh = IOBuffer()
    writeUint16(vh, p.packetIdentifier)
    write(vh, encodeProperties(p.properties))
    
    pl = IOBuffer()
    for s in p.subscriptions
        write(pl, encodeString(s.topicFilter))
        opts = UInt8(s.qos)
        if s.noLocal           opts |= 0x04 end
        if s.retainAsPublished opts |= 0x08 end
        opts |= (s.retainHandling << 4)
        write(pl, opts)
    end
    return typeByte, take!(vh), take!(pl)
end

function encodeParts(p::SubackPacket)
    typeByte = (SUBACK << 4)
    vh = IOBuffer()
    writeUint16(vh, p.packetIdentifier)
    write(vh, encodeProperties(p.properties))
    return typeByte, take!(vh), p.reasonCodes
end

function encodeParts(p::UnsubscribePacket)
    typeByte = (UNSUBSCRIBE << 4) | 0x02
    vh = IOBuffer()
    writeUint16(vh, p.packetIdentifier)
    write(vh, encodeProperties(p.properties))
    
    pl = IOBuffer()
    for tf in p.topicFilters
        write(pl, encodeString(tf))
    end
    return typeByte, take!(vh), take!(pl)
end

function encodeParts(p::UnsubackPacket)
    typeByte = (UNSUBACK << 4)
    vh = IOBuffer()
    writeUint16(vh, p.packetIdentifier)
    write(vh, encodeProperties(p.properties))
    return typeByte, take!(vh), p.reasonCodes
end

function encodeParts(p::PingreqPacket)
    return (PINGREQ << 4), UInt8[], UInt8[]
end

function encodeParts(p::PingrespPacket)
    return (PINGRESP << 4), UInt8[], UInt8[]
end

function encodeParts(p::DisconnectPacket)
    typeByte = (DISCONNECT << 4)
    vh = IOBuffer()
    write(vh, p.reasonCode)
    write(vh, encodeProperties(p.properties))
    return typeByte, take!(vh), UInt8[]
end

function encodeParts(p::AuthPacket)
    typeByte = (AUTH << 4)
    vh = IOBuffer()
    write(vh, p.reasonCode)
    write(vh, encodeProperties(p.properties))
    return typeByte, take!(vh), UInt8[]
end

# --- Specific Packet Part Decoders ---

function decodeConnect(buf::IO)
    protocolName = decodeString(buf)
    protocolVersion = read(buf, UInt8)
    connectFlags = read(buf, UInt8)
    keepAlive = readUint16(buf)
    properties = decodeProperties(buf)
    
    clientId = decodeString(buf)
    
    willFlag = (connectFlags & 0x04) != 0
    willQos = QoS((connectFlags >> 3) & 0x03)
    willRetain = (connectFlags & 0x20) != 0
    cleanStart = (connectFlags & 0x02) != 0
    
    willProperties = Properties()
    willTopic = nothing
    willPayload = nothing
    if willFlag
        willProperties = decodeProperties(buf)
        willTopic = decodeString(buf)
        plen = readUint16(buf)
        willPayload = read(buf, plen)
    end
    
    username = nothing
    if (connectFlags & 0x80) != 0
        username = decodeString(buf)
    end
    
    password = nothing
    if (connectFlags & 0x40) != 0
        plen = readUint16(buf)
        password = read(buf, plen)
    end
    
    return ConnectPacket(
        protocolName = protocolName,
        protocolVersion = protocolVersion,
        cleanStart = cleanStart,
        keepAlive = keepAlive,
        properties = properties,
        clientId = clientId,
        willFlag = willFlag,
        willQos = willQos,
        willRetain = willRetain,
        willProperties = willProperties,
        willTopic = willTopic,
        willPayload = willPayload,
        username = username,
        password = password
    )
end

function decodeConnack(buf::IO)
    sessionPresent = (read(buf, UInt8) & 0x01) != 0
    reasonCode = read(buf, UInt8)
    properties = decodeProperties(buf)
    return ConnackPacket(sessionPresent, reasonCode, properties)
end

function decodePublish(flags::UInt8, buf::IO)
    dup = (flags & 0x08) != 0
    qos = QoS((flags >> 1) & 0x03)
    retain = (flags & 0x01) != 0
    
    topic = decodeString(buf)
    packetIdentifier = nothing
    if qos > qos0
        packetIdentifier = readUint16(buf)
    end
    
    properties = decodeProperties(buf)
    
    # Rest of the buffer is payload
    payload = read(buf)
    
    return PublishPacket(
        dup = dup,
        qos = qos,
        retain = retain,
        topic = topic,
        packetIdentifier = packetIdentifier,
        properties = properties,
        payload = payload
    )
end

function decodeAck(T::Type{<:AbstractMqttPacket}, buf::IO)
    packetIdentifier = readUint16(buf)
    reasonCode = 0x00
    properties = Properties()
    
    # Reason Code and Properties are optional if they are default
    if !eof(buf)
        reasonCode = read(buf, UInt8)
    end
    if !eof(buf)
        properties = decodeProperties(buf)
    end
    
    return T(packetIdentifier, reasonCode, properties)
end

function decodeSubscribe(buf::IO)
    packetIdentifier = readUint16(buf)
    properties = decodeProperties(buf)
    
    subscriptions = Subscription[]
    while !eof(buf)
        topicFilter = decodeString(buf)
        opts = read(buf, UInt8)
        qos = QoS(opts & 0x03)
        noLocal = (opts & 0x04) != 0
        retainAsPublished = (opts & 0x08) != 0
        retainHandling = (opts >> 4) & 0x03
        push!(subscriptions, Subscription(topicFilter, qos, noLocal, retainAsPublished, retainHandling))
    end
    
    return SubscribePacket(packetIdentifier, properties, subscriptions)
end

function decodeSuback(buf::IO)
    packetIdentifier = readUint16(buf)
    properties = decodeProperties(buf)
    reasonCodes = read(buf)
    return SubackPacket(packetIdentifier, properties, reasonCodes)
end

function decodeUnsubscribe(buf::IO)
    packetIdentifier = readUint16(buf)
    properties = decodeProperties(buf)
    topicFilters = String[]
    while !eof(buf)
        push!(topicFilters, decodeString(buf))
    end
    return UnsubscribePacket(packetIdentifier, properties, topicFilters)
end

function decodeUnsuback(buf::IO)
    packetIdentifier = readUint16(buf)
    properties = decodeProperties(buf)
    reasonCodes = read(buf)
    return UnsubackPacket(packetIdentifier, properties, reasonCodes)
end

function decodeDisconnect(buf::IO)
    reasonCode = 0x00
    properties = Properties()
    if !eof(buf)
        reasonCode = read(buf, UInt8)
    end
    if !eof(buf)
        properties = decodeProperties(buf)
    end
    return DisconnectPacket(reasonCode, properties)
end

function decodeAuth(buf::IO)
    reasonCode = 0x00
    properties = Properties()
    if !eof(buf)
        reasonCode = read(buf, UInt8)
    end
    if !eof(buf)
        properties = decodeProperties(buf)
    end
    return AuthPacket(reasonCode, properties)
end
