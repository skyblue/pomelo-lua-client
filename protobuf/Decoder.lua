
local codec = Protobuf.codec
local util = Protobuf.util



local buffer, offset


local MsgDecoder = {}

local function getBytes(flag)
    local bytes = {}
    local pos = offset
    flag = flag or false

    local b
    repeat
        b = buffer[pos]
        table.insert(bytes, b)
        pos = pos + 1
    until b < 128

    -- while true do
    --     b = buffer[pos]
    --     if b  and b >= 128 then
    --         table.insert(bytes, b)
    --         pos = pos + 1
    --     else
    --         break
    --     end
    --     break
    -- end

    if not flag then
        offset = pos
    end
    return bytes
end

local function peekBytes()
    return getBytes(true)
end


local function getHead()
    local tag = codec.decodeUInt32(getBytes())
    return {
        type_ = bit.band(tag, 0x7),
        tag = bit.rshift(tag, 3)
    }
end

local function peekHead()
    local tag = codec.decodeUInt32(peekBytes())

    return {
        type_ = bit.band(tag, 0x7),
        tag = bit.rshift(tag, 3)
    }
end

local function isFinish(msg, protos)
    return (not protos.__tags{peekHead().tag})
end


local decodeProp, decodeProp, decodeArray

decodeMsg = function(msg, protos, length)
    while offset < length do
        local head = getHead()
        local type_ = head.type_
        local tag = head.tag
        local name = protos.__tags[tag]
        -- console.error(protos, "==============",name, head.type_, head.tag)
        local option = protos[name].option
        if option == "optional" or option == "required" then
            msg[name] = decodeProp(protos[name].type, protos);
        elseif option == "repeated" then
            if not msg[name]  then
                msg[name] = {}
            end
            decodeArray(msg[name], protos[name].type, protos);
        end

    end

    return msg
end

decodeProp = function(type_, protos)
    if type_ == "uInt32" then
        return codec.decodeUInt32(getBytes())
    elseif type_ == "int32" or type_ == "sInt32" then
        return codec.decodeSInt32(getBytes())
    elseif type_ == "bool" then
        local v = codec.decodeUInt32(getBytes())
        return (v ~= 0)
    elseif type_ == "float" then
        local float = codec.decodeFloat(buffer, offset)
        offset = offset + 4
        return float
    elseif type_ == "double" then
        local double = codec.decodeDouble(buffer, offset)
        offset = offset + 8
        return double
    elseif type_ == "string" then
        local length = codec.decodeUInt32(getBytes())
        local str  =  codec.decodeStr(buffer, offset, length)
        offset = offset + length
        return str
    else
        local __messageProtos = protos.__messages[type_] or MsgDecoder.protos['message ' .. type_]
        if __messageProtos then
            local length = codec.decodeUInt32(getBytes())
            local msg = decodeMsg({}, __messageProtos, offset + length )
            return msg
        end
    end
end

decodeArray = function(array, type_, protos)
    if util.isSimpleType(type_) then
        local length = codec.decodeUInt32(getBytes())
        for i = 1, length do
            table.insert(array, decodeProp(type_))
        end
    else
        table.insert(array, decodeProp(type_, protos))
    end
end











MsgDecoder.init = function(protos)
    MsgDecoder.protos = protos or {}
end

MsgDecoder.setProtos = function(protos)
    if protos then
        MsgDecoder.protos = protos
    end
end

MsgDecoder.decode = function(route, buf)
    local protos = MsgDecoder.protos[route]

    buffer = buf
    offset = 1

    if protos then
        return decodeMsg({}, protos, #buffer)
    end

    return nil
end





return MsgDecoder


