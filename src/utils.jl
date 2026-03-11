# MQTT 5.0 Constants and Utilities

# Control Packet Types
const CONNECT     = UInt8(0x01)
const CONNACK     = UInt8(0x02)
const PUBLISH     = UInt8(0x03)
const PUBACK      = UInt8(0x04)
const PUBREC      = UInt8(0x05)
const PUBREL      = UInt8(0x06)
const PUBCOMP     = UInt8(0x07)
const SUBSCRIBE   = UInt8(0x08)
const SUBACK      = UInt8(0x09)
const UNSUBSCRIBE = UInt8(0x0A)
const UNSUBACK    = UInt8(0x0B)
const PINGREQ     = UInt8(0x0C)
const PINGRESP    = UInt8(0x0D)
const DISCONNECT  = UInt8(0x0E)
const AUTH        = UInt8(0x0F)

# Property Identifiers
const PAYLOAD_FORMAT_INDICATOR          = UInt8(0x01)
const MESSAGE_EXPIRY_INTERVAL           = UInt8(0x02)
const CONTENT_TYPE                      = UInt8(0x03)
const RESPONSE_TOPIC                    = UInt8(0x08)
const CORRELATION_DATA                  = UInt8(0x09)
const SUBSCRIPTION_IDENTIFIER           = UInt8(0x0B)
const SESSION_EXPIRY_INTERVAL           = UInt8(0x11)
const ASSIGNED_CLIENT_IDENTIFIER        = UInt8(0x12)
const SERVER_KEEP_ALIVE                 = UInt8(0x13)
const AUTHENTICATION_METHOD             = UInt8(0x15)
const AUTHENTICATION_DATA               = UInt8(0x16)
const REQUEST_PROBLEM_INFORMATION       = UInt8(0x17)
const WILL_DELAY_INTERVAL               = UInt8(0x18)
const REQUEST_RESPONSE_INFORMATION      = UInt8(0x19)
const RESPONSE_INFORMATION              = UInt8(0x1A)
const SERVER_REFERENCE                  = UInt8(0x1C)
const REASON_STRING                     = UInt8(0x1F)
const RECEIVE_MAXIMUM                   = UInt8(0x21)
const TOPIC_ALIAS_MAXIMUM               = UInt8(0x22)
const TOPIC_ALIAS                       = UInt8(0x23)
const MAXIMUM_QOS                       = UInt8(0x24)
const RETAIN_AVAILABLE                  = UInt8(0x25)
const USER_PROPERTY                     = UInt8(0x26)
const MAXIMUM_PACKET_SIZE               = UInt8(0x27)
const WILDCARD_SUBSCRIPTION_AVAILABLE   = UInt8(0x28)
const SUBSCRIPTION_IDENTIFIER_AVAILABLE = UInt8(0x29)
const SHARED_SUBSCRIPTION_AVAILABLE     = UInt8(0x2A)

# Reason Codes (Subset of common codes)
const SUCCESS                           = UInt8(0x00)
const NORMAL_DISCONNECTION              = UInt8(0x00)
const DISCONNECT_WITH_WILL_MESSAGE      = UInt8(0x04)
const UNSPECIFIED_ERROR                 = UInt8(0x80)
const MALFORMED_PACKET                  = UInt8(0x81)
const PROTOCOL_ERROR                    = UInt8(0x82)
const IMPLEMENTATION_SPECIFIC_ERROR     = UInt8(0x83)

# Variable Byte Integer Utilities
"""
    encodeVbi(value::Integer) -> Vector{UInt8}

Encodes an integer into a Variable Byte Integer according to the MQTT 5.0 spec.
Max value is 268,435,455.
"""
function encodeVbi(value::Integer)
    res = UInt8[]
    x = value
    while true
        encodedByte = UInt8(x % 128)
        x = x ÷ 128
        if x > 0
            push!(res, encodedByte | 0x80)
        else
            push!(res, encodedByte)
            break
        end
    end
    return res
end

"""
    decodeVbi(stream::IO) -> Int

Decodes a Variable Byte Integer from an IO stream.
"""
function decodeVbi(stream::IO)
    multiplier = 1
    value = 0
    while true
        encodedByte = read(stream, UInt8)
        value += (encodedByte & 0x7F) * multiplier
        if multiplier > 128 * 128 * 128
            error("Malformed Variable Byte Integer")
        end
        multiplier *= 128
        if (encodedByte & 0x80) == 0
            break
        end
    end
    return value
end

# String Utilities
"""
    encodeString(str::String) -> Vector{UInt8}

Encodes a UTF-8 string with a 2-byte length prefix (big-endian).
"""
function encodeString(str::String)
    bytes = Vector{UInt8}(str)
    len = length(bytes)
    if len > 65535
        error("String too long for MQTT 2-byte length prefix")
    end
    return vcat(UInt8(len >> 8), UInt8(len & 0xFF), bytes)
end

"""
    decodeString(stream::IO) -> String

Decodes a UTF-8 string prefixed with a 2-byte length from an IO stream.
"""
function decodeString(stream::IO)
    msb = read(stream, UInt8)
    lsb = read(stream, UInt8)
    len = (UInt16(msb) << 8) | UInt16(lsb)
    bytes = read(stream, len)
    return String(bytes)
end

# Big-Endian Integer Utilities
"""
    writeUint16(stream::IO, value::UInt16)

Writes a 16-bit unsigned integer to the stream in big-endian format.
"""
function writeUint16(stream::IO, value::UInt16)
    write(stream, hton(value))
end

"""
    readUint16(stream::IO) -> UInt16

Reads a 16-bit unsigned integer from the stream in big-endian format.
"""
function readUint16(stream::IO)
    return ntoh(read(stream, UInt16))
end

"""
    writeUint32(stream::IO, value::UInt32)

Writes a 32-bit unsigned integer to the stream in big-endian format.
"""
function writeUint32(stream::IO, value::UInt32)
    write(stream, hton(value))
end

"""
    readUint32(stream::IO) -> UInt32

Reads a 32-bit unsigned integer from the stream in big-endian format.
"""
function readUint32(stream::IO)
    return ntoh(read(stream, UInt32))
end

"""
    topicMatches(topic::String, topicFilter::String) -> Bool

Matches an MQTT topic name against a topic filter with wildcards (+, #).
"""
function topicMatches(topic::String, topicFilter::String)
    # Fast path for exact match
    if topic == topicFilter
        return true
    end
    
    # Split both into levels
    nameLevels = split(topic, '/')
    filterLevels = split(topicFilter, '/')
    
    for i in 1:length(filterLevels)
        fl = filterLevels[i]
        
        # Multi-level wildcard '#' must be at the end
        if fl == "#"
            return true
        end
        
        # Single-level wildcard '+'
        if fl == "+"
            if i > length(nameLevels)
                return false
            end
            continue
        end
        
        # Exact level match
        if i > length(nameLevels) || fl != nameLevels[i]
            return false
        end
    end
    
    # If we reached here, filterLevels must match nameLevels length
    return length(nameLevels) == length(filterLevels)
end
