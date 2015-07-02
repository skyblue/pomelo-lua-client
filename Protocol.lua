local Protocol = {}

-- str = json string
Protocol.strencode = function(str)
    if not str then return  end
    do return {string.byte(str, 1, #str)} end

    local byteArray = {}
    local offset = 1
    for i=1,#str do
        local charCode = string.byte(str, i)
        local codes = nil
        if charCode <= 0x7f then
            codes = {charCode}
        elseif charCode <= 0x7ff then
            codes = {bit.bor(0xc0,bit.rshift(charCode,6)),bit.bor(0x80,bit.band(charCode,0x3f))}
            console.log(codes, "Protocol.strencode")
        else
            codes = {bit.bor(0xe0,bit.rshift(charCode,12)),bit.rshift(bit.band(charCode,0xfc0),6),bit.bor(0x80,bit.band(charCode,0x3f))}
        end
        for j=1,#codes do
            byteArray[offset] = codes[j]
            offset = offset +1
        end
    end
    return byteArray
        -- return clone(byteArray)
end


Protocol.strdecode2 = function(bytes)
    local array = {}
    local charCode = 0
    local offset = 1
    while offset<=#bytes do
        if bytes[offset] < 128 then
            charCode = bytes[offset]
            offset = offset + 1
        elseif bytes[offset] < 224 then
            charCode = bit.lshift(bit.band(bytes[offset],0x3f),6) + bit.band(bytes[offset+1],0x3f)
            offset = offset + 2
        else
            charCode = bit.lshift(bit.band(bytes[offset],0x0f),12) + bit.lshift(bit.band(bytes[offset+1],0x3f),6) + bit.band(bytes[offset+2],0x3f)
            offset = offset + 3
        end
        table.insert(array, charCode)
    end
    dump(array, #array)
    return string.char(unpack(array))

        -- local arr = {}
        -- local len = #array
        -- for i = 1, len do
        --     arr[i] = string.char(array[i])
        -- end
        -- return table.concat(arr)
end

Protocol.strdecode = function(bytes)
    local array = {}
    local len = #bytes
    for i = 1, len do
        -- table.insert(array, string.char(bytes[i]))
        array[i] = string.char(bytes[i]) -- 更快一些
    end
    return table.concat(array)


        -- return string.char(unpack(bytes)) //爆栈
end

return Protocol

