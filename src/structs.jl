# MQTT 5.0 Data Structures

"""
    Properties represents the MQTT 5.0 property set.
    Fields are named after the property names in the spec.
"""
mutable struct Properties
    sessionExpiryInterval::Union{Nothing, UInt32}
    receiveMaximum::Union{Nothing, UInt16}
    maximumPacketSize::Union{Nothing, UInt32}
    topicAliasMaximum::Union{Nothing, UInt16}
    topicAlias::Union{Nothing, UInt16}
    requestResponseInformation::Union{Nothing, UInt8}
    requestProblemInformation::Union{Nothing, UInt8}
    userProperties::Vector{Pair{String, String}}
    authenticationMethod::Union{Nothing, String}
    authenticationData::Union{Nothing, Vector{UInt8}}
    messageExpiryInterval::Union{Nothing, UInt32}
    payloadFormatIndicator::Union{Nothing, UInt8}
    contentType::Union{Nothing, String}
    responseTopic::Union{Nothing, String}
    correlationData::Union{Nothing, Vector{UInt8}}
    subscriptionIdentifiers::Vector{Int} # Variable Byte Integer(s)
    assignedClientIdentifier::Union{Nothing, String}
    serverKeepAlive::Union{Nothing, UInt16}
    reasonString::Union{Nothing, String}
    willDelayInterval::Union{Nothing, UInt32}

    function Properties()
        new(nothing, nothing, nothing, nothing, nothing, nothing, nothing, 
            Pair{String, String}[], nothing, nothing, nothing, nothing, 
            nothing, nothing, nothing, Int[], nothing, nothing, nothing, nothing)
    end
end

"""
    QoS level for MQTT messages.
"""
@enum QoS::UInt8 begin
    qos0 = 0x00
    qos1 = 0x01
    qos2 = 0x02
end

abstract type AbstractMqttPacket end

"""
    CONNECT Packet
"""
struct ConnectPacket <: AbstractMqttPacket
    protocolName::String
    protocolVersion::UInt8
    cleanStart::Bool
    keepAlive::UInt16
    properties::Properties
    clientId::String
    willFlag::Bool
    willQos::QoS
    willRetain::Bool
    willProperties::Properties
    willTopic::Union{Nothing, String}
    willPayload::Union{Nothing, Vector{UInt8}}
    username::Union{Nothing, String}
    password::Union{Nothing, Vector{UInt8}}

    function ConnectPacket(;
        protocolName = "MQTT",
        protocolVersion = 5,
        cleanStart = true,
        keepAlive = 60,
        properties = Properties(),
        clientId = "",
        willFlag = false,
        willQos = qos0,
        willRetain = false,
        willProperties = Properties(),
        willTopic = nothing,
        willPayload = nothing,
        username = nothing,
        password = nothing
    )
        pwd_bytes = if password isa String
            Vector{UInt8}(password)
        else
            password
        end
        new(protocolName, UInt8(protocolVersion), cleanStart, UInt16(keepAlive), properties, 
            clientId, willFlag, willQos, willRetain, willProperties, 
            willTopic, willPayload, username, pwd_bytes)
    end
end

"""
    CONNACK Packet
"""
Base.@kwdef struct ConnackPacket <: AbstractMqttPacket
    sessionPresent::Bool
    reasonCode::UInt8
    properties::Properties = Properties()
end

"""
    PUBLISH Packet
"""
Base.@kwdef struct PublishPacket <: AbstractMqttPacket
    dup::Bool = false
    qos::QoS = qos0
    retain::Bool = false
    topic::String
    packetIdentifier::Union{Nothing, UInt16} = nothing # Mandatory for QoS > 0
    properties::Properties = Properties()
    payload::Vector{UInt8} = UInt8[]
end

"""
    PUBACK Packet
"""
Base.@kwdef struct PubackPacket <: AbstractMqttPacket
    packetIdentifier::UInt16
    reasonCode::UInt8 = 0x00
    properties::Properties = Properties()
end

"""
    PUBREC Packet
"""
Base.@kwdef struct PubrecPacket <: AbstractMqttPacket
    packetIdentifier::UInt16
    reasonCode::UInt8 = 0x00
    properties::Properties = Properties()
end

"""
    PUBREL Packet
"""
Base.@kwdef struct PubrelPacket <: AbstractMqttPacket
    packetIdentifier::UInt16
    reasonCode::UInt8 = 0x00
    properties::Properties = Properties()
end

"""
    PUBCOMP Packet
"""
Base.@kwdef struct PubcompPacket <: AbstractMqttPacket
    packetIdentifier::UInt16
    reasonCode::UInt8 = 0x00
    properties::Properties = Properties()
end

"""
    SUBSCRIBE Packet
"""
Base.@kwdef struct Subscription
    topicFilter::String
    qos::QoS = qos0
    noLocal::Bool = false
    retainAsPublished::Bool = false
    retainHandling::UInt8 = 0 # 0, 1, or 2
end

Base.@kwdef struct SubscribePacket <: AbstractMqttPacket
    packetIdentifier::UInt16
    properties::Properties = Properties()
    subscriptions::Vector{Subscription}
end

"""
    SUBACK Packet
"""
Base.@kwdef struct SubackPacket <: AbstractMqttPacket
    packetIdentifier::UInt16
    properties::Properties = Properties()
    reasonCodes::Vector{UInt8}
end

"""
    UNSUBSCRIBE Packet
"""
Base.@kwdef struct UnsubscribePacket <: AbstractMqttPacket
    packetIdentifier::UInt16
    properties::Properties = Properties()
    topicFilters::Vector{String}
end

"""
    UNSUBACK Packet
"""
Base.@kwdef struct UnsubackPacket <: AbstractMqttPacket
    packetIdentifier::UInt16
    properties::Properties = Properties()
    reasonCodes::Vector{UInt8}
end

"""
    PINGREQ Packet
"""
struct PingreqPacket <: AbstractMqttPacket end

"""
    PINGRESP Packet
"""
struct PingrespPacket <: AbstractMqttPacket end

"""
    DISCONNECT Packet
"""
Base.@kwdef struct DisconnectPacket <: AbstractMqttPacket
    reasonCode::UInt8 = 0x00
    properties::Properties = Properties()
end

"""
    AUTH Packet
"""
Base.@kwdef struct AuthPacket <: AbstractMqttPacket
    reasonCode::UInt8 = 0x00
    properties::Properties = Properties()
end

export QoS, Properties, ConnectPacket, ConnackPacket, PublishPacket, PubackPacket, 
       PubrecPacket, PubrelPacket, PubcompPacket, SubscribePacket, SubackPacket, 
       UnsubscribePacket, UnsubackPacket, PingreqPacket, PingrespPacket, 
       DisconnectPacket, AuthPacket, Subscription
