
local constant = Protobuf.constants
local codec = Protobuf.codec
local util = Protobuf.util


local function writeBytes(buffer, offset, bytes)
    for i, b in ipairs(bytes) do
        buffer[offset] = b
        offset = offset + 1
    end
    return offset
end



local MsgEncoder = {}

function MsgEncoder.init(protos)
    MsgEncoder.protos = protos
end

function MsgEncoder.encode(route, msg)
    local protos = MsgEncoder.protos[route]
    if not MsgEncoder.checkMsg(msg, protos) then
        return nil
    end

    local buffer = {}
    local offset = 1

    if protos then
        offset = MsgEncoder.encodeMsg(buffer, offset, protos, msg)
    end
    return buffer
end

function  MsgEncoder.encodeTag(type_, tag)
    local value = constant.TYPES[type_] or 2
    return codec.encodeUInt32( bit.bor(bit.lshift(tag, 3), value))
end

function MsgEncoder.checkMsg(msg, protos)
    if not protos then
        return false
    end

    for name, proto in pairs(protos) do
        local option = proto.option
        local val = msg[name]
        if option == "required" and val == nil then
            return false
        end

        if option == "required" or option == "optional" then
            if val ~= nil then
                if protos.__messages[proto.type] then
                    MsgEncoder.checkMsg(msg[name], protos.__messages[proto.type])
                end
            end
        elseif option == "repeated" then
            if type(val) == "table" and protos.__messages[proto.type] then
                local __messageProto = protos.__messages[proto.type]
                for i = 1, #val do
                    if not MsgEncoder.checkMsg(val[i], __messageProto) then
                        return false
                    end
                end
            end
        end

    end

    return true
end

function MsgEncoder.encodeMsg(buffer, offset, protos, msg)
    for i, name in ipairs(protos.__tags) do
        if msg[name] and protos[name] then
            local val = msg[name]
            local proto = protos[name]
            local option = proto.option
            if option == "optional" or option == "required" then
                offset = writeBytes(buffer, offset, MsgEncoder.encodeTag(proto.type, proto.tag))
                offset = MsgEncoder.encodeProp(val, proto.type, offset, buffer, protos)
            elseif option == "repeated" then
                if #val > 0 then
                    offset = MsgEncoder.encodeArray(val, proto, offset, buffer, protos)
                end
            end
        end
    end
    return offset
end

function MsgEncoder.encodeProp(value, type_, offset, buffer, protos)
    -- console.log(value, type_, offset, buffer, protos)
    if type_ == "uInt32" then
        offset = writeBytes(buffer, offset, codec.encodeUInt32(value))
    elseif type_ == "int32" or type_ == "sInt32" then
        offset = writeBytes(buffer, offset, codec.encodeSInt32(value))
    elseif type_ == "bool" then
        value = (value == true) and 1 or 0
        offset = writeBytes(buffer, offset, codec.encodeUInt32(value))
    elseif type_ == "float" then
        writeBytes(buffer, offset, codec.encodeFloat(value))
        offset = offset + 4
    elseif type_ == "double" then
        writeBytes(buffer, offset, codec.encodeDouble(value))
        offset = offset + 8
    elseif type_ == "string" then
        local length = #value
        offset = writeBytes(buffer, offset, codec.encodeUInt32(length))
        codec.encodeStr(buffer, offset, value)
        offset = offset + length
    else
        local __messageProtos = protos.__messages[type_] or MsgEncoder.protos['message '.. type_]
        if __messageProtos then
            local tmpBuffer = {}
            local tmpOffset = 1
            length = MsgEncoder.encodeMsg(tmpBuffer, tmpOffset, __messageProtos, value)
            offset = writeBytes(buffer, offset, codec.encodeUInt32(#tmpBuffer))
            offset = writeBytes(buffer, offset, tmpBuffer)
        end

    end
    -- dump(buffer, "=============>")
    return offset
end




function MsgEncoder.encodeArray(array, proto, offset, buffer, protos)
    local len = #array
    if util.isSimpleType(proto.type) then
        offset = writeBytes(buffer, offset, MsgEncoder.encodeTag(proto.type, proto.tag))
        offset = writeBytes(buffer, offset, codec.encodeUInt32(len))
        for i = 1, len do
            offset = MsgEncoder.encodeProp(array[i], proto.type, offset, buffer)
        end
    else
        for i = 1, len do
            offset = writeBytes(buffer, offset, MsgEncoder.encodeTag(proto.type, proto.tag))
            offset = MsgEncoder.encodeProp(array[i], proto.type, offset, buffer, protos)
        end
    end

    return offset
end






return MsgEncoder







