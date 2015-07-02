local func = require("libs.pomelo.functions")

local Package = {}

local PKG_HEAD_BYTES = 4

Package.TYPE_HANDSHAKE = 1
Package.TYPE_HANDSHAKE_ACK = 2
Package.TYPE_HEARTBEAT = 3
Package.TYPE_DATA = 4
Package.TYPE_KICK = 5

Package.encode = function(_type, body)
    local length = 0
    if body then
        length = #body
    end
    local buffer = {}
    local index = 1
    buffer[index] = bit.band(_type,0xff)
    index = index + 1
    buffer[index] = bit.band(bit.rshift(length,16),0xff)
    index = index + 1
    buffer[index] = bit.band(bit.rshift(length,8),0xff)
    index = index + 1
    buffer[index] = bit.band(length,0xff)
    index = index + 1
    if body then
        func.copyArray(buffer,index,body,1,length)
    end
    return buffer
end

local getLength_ = function(bytes, offset)
    offset = offset or 1
    local index = 1 + offset
    if not bytes[index] then
        dump(bytes)
    end
    -- console.log(index, bytes[index],bytes[1])
    local a = bit.lshift(bytes[index],16)
    index = index + 1
    local b = bit.lshift(bytes[index],8)
    index = index + 1
    local c = bytes[index]
    index = index + 1
    local d = bit.bor(bit.bor(a, b), c)
    local length = bit.arshift(d, 0) or 0
    return length
end


Package.decode = function(bytes)
    local bytesLength = #bytes
    if bytesLength == 0 then return nil end
    local rs = {}
    local offset = 1
    local length
    while (offset < bytesLength) do
        local type_, body = bytes[offset], {}
        local length = getLength_(bytes, offset)
        func.copyArray(body, 1, bytes, offset + PKG_HEAD_BYTES, length)
        offset = offset + PKG_HEAD_BYTES + length
        table.insert(rs, {type = type_, body = body})
    end

    return #rs == 1 and rs[0] or rs
end

Package.decode2 = function(bytes, pkgs)
    pkgs = pkgs or {}
    local bytesLength = #bytes
    -- if bytesLength == 0 then return pkgs end

    local length = getLength_(bytes)
    local _type, body = bytes[1], {}
    func.copyArray(body, 1, bytes, PKG_HEAD_BYTES + 1, length)
    local pkg = {type = _type, body = body}
    table.insert(pkgs, pkg)

    bytesLength = bytesLength - (length + PKG_HEAD_BYTES)
    if bytesLength > 0 then
        -- bytes = func.sliceTable(bytes, PKG_HEAD_BYTES + length + 1)
        func.copyArray(body, 1, bytes, offset + PKG_HEAD_BYTES, length)
        Package.decode(bytes, pkgs)
    end
    return pkgs

end

-- return type, body length
Package.decodeHead = function(bytes)
    if #bytes < 4 then return nil end
    -- local bytes = {string.byte(buffer, 1, 4)}
    local index =  1
    local type_, length = bytes[index], 0

    index = index + 1
    local a = bit.lshift(bytes[index],16)
    index = index + 1
    local b = bit.lshift(bytes[index],8)
    index = index + 1
    local c = bytes[index]
    index = index + 1
    local d = bit.bor(bit.bor(a, b), c)
    length = bit.arshift(d, 0)

    return type_, length
end



return Package

