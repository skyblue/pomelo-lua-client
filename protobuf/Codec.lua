local func = require("libs.pomelo.functions")



--[[
local function encode2UTF8(charCode)
    if charCode <= 0x7f then
        return {charCode}
    elseif charCode <= 0x7ff then
      -- local a = bit.rshift(charCode, 6)
      -- local b = bit.b

      return
       -- return {0xc0|(charCode>>6), 0x80|(charCode & 0x3f)}
    else
       -- return {0xe0|(charCode>>12), 0x80|((charCode & 0xfc0)>>6), 0x80|(charCode & 0x3f)}
    end
end

local function codeLength(code)
 if code <= 0x7f then
     return 1
     elseif code <= 0x7ff then
         return 2byteLength
     else
         return 3
     end
 end
]]


local Codec = {}


local buffer = {}
-- local float32Array = buffer
-- local float64Array = buffer
local uInt8Array = buffer


Codec.encodeUInt32 = function(n)
    if type(n) ~= "number" or n < 0 then
        return nil
    end
    n = checkint(n)

    local result = {}
    repeat
        local tmp = n % 128
        local next_ = math.floor(n/128)
        if next_ ~= 0 then
            tmp = tmp + 128
        end
        table.insert(result, tmp)
        n = next_
    until (n == 0)

    return result
end

Codec.encodeSInt32 = function(n)
    if type(n) ~= "number" then return nil end
    local n = checkint(n)
    n = (n < 0) and (math.abs(n)*2-1) or (n*2)

    return Codec.encodeUInt32(n)
end

Codec.decodeUInt32 = function(bytes)
    local n = 0

    for i = 1,  #bytes do
        local m = bytes[i]
        n = n + ( bit.band(m , 0x7f) * math.pow(2,(7*(i-1))))
        if m < 128 then
            return n
        end
    end

    return n
end


Codec.decodeSInt32 = function(bytes)
    local n = Codec.decodeUInt32(bytes)
    local flag = ((n%2) == 1) and -1 or 1

    n = ((n%2 + n)/2)*flag

    return n
end

Codec.decodeUInt64 = function(bytes)
    local b1, b2, v1,v2, val
    b1 = func.sliceTable(bytes, 1, 4)
    b1 = func.sliceTable(bytes, 5, 8)
    v1 = Codec.decodeUInt32(b1);
    v2 = Codec.decodeUInt32(b2);
    val = (v2 * math.pow(2, 32)) + v1;
    return val
end


local function grab_byte(v)
    return math.ceil(v / 256), string.char(math.floor(v) % 256)
end
Codec.encodeFloat = function(n)
    local sign = 0
    if n < 0 then
        sign = 1
        n = -n
    end

    local mantissa, exponent = math.frexp(n)
    if x == 0 then -- zero
        mantissa = 0
        exponent = 0
    else
        mantissa = (mantissa * 2 - 1) * math.ldexp(0.5, 24) + 1
        exponent = exponent + 126
    end
    local v, byte = ""
    n, byte = grab_byte(mantissa); v = v..byte
    n, byte = grab_byte(n); v = v..byte
    n, byte = grab_byte(exponent * 128 + n); v = v..byte
    n, byte = grab_byte(sign * 128 + n); v = v..byte
    return v
end

Codec.decodeFloat = function(bytes, offset)
    if not bytes or (#bytes < (4 + offset-1)) then
        return 0
    end

    for i = 1, 4 do
        uInt8Array[i] = bytes[offset + i - 1]
        -- uInt8Array[i] = bytes[offset + 4 - i  ]
    end

    -- dump(uInt8Array, "decodeFloat")

    local b = uInt8Array

    local sign = b[4] > 127 and -1 or 1
    local mantissa = b[3] % 128
    for i = 2, 1, -1 do
        mantissa = mantissa * 256 + b[i]
    end

    local exponent = (b[4] % 128) * 2 + math.floor(b[3] / 128)
    if exponent == 0 then return 0 end
    mantissa = (math.ldexp(mantissa, -23) + 1) * sign
    return math.ldexp(mantissa, exponent - 127)


        -- local sign = b[1] > 0x7F and -1 or 1
        -- local exponent = bit.bor(bit.band(bit.lshift(b[1], 1), 0xff) , bit.rshift(b[2], 7) - 127)
        -- local m1 = bit.lshift(bit.band(b[2] , 0x7f) , 16)
        -- local m2 = bit.lshift(b[3], 8)
        -- local m3 = b[4]
        -- local mantissa = bit.bor(bit.bor(m1,m2),m3)

        -- if (mantissa == 0 and exponent == -127) then
        --     return 0.0
        -- end

        -- if (exponent == -127) then
        --     return sign * mantissa * math.pow(2, -126 - 23)
        -- end

        -- return sign * (1 + mantissa * math.pow(2, -23)) * math.pow(2, exponent)

end

-- TODO  改使用位运算  and 大小端问题?
Codec.encodeDouble = function(n)
    local sign = 0
    if n < 0 then
        sign = 0x80
        n = -n
    end
    local mant, expo = math.frexp(n)
    if mant ~= mant then
        return string.char(0xFF, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)  -- nan
    elseif mant == math.huge then
        if sign == 0 then
            return string.char(0x7F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)-- inf
        else
            return string.char(0xFF, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)-- -inf
        end
    elseif mant == 0.0 and expo == 0 then
        return string.char(sign, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)-- zero
    else
        expo = expo + 0x3FE
        mant = (mant * 2.0 - 1.0) * math.ldexp(0.5, 53)
        local bytes = {}
        bytes[1] = mant % 0x100
        bytes[2] = math.floor(mant / 0x100) % 0x100
        bytes[3] = math.floor(mant / 0x10000) % 0x100
        bytes[4] = math.floor(mant / 0x1000000) % 0x100
        bytes[5] = math.floor(mant / 4294967296) % 0x100                     -- pow(2, 32)
        bytes[6] = math.floor(mant / 1099511627776) % 0x100                  -- pow(2, 40)
        bytes[7] = (expo % 0x10) * 0x10 + math.floor(mant / 281474976710656) -- pow(2, 48)
        bytes[8] = sign + math.floor(expo / 0x10)

        -- bytes[1] = mant % 2^8
        -- bytes[2] = math.floor(mant / 2^8)  % 2^8
        -- bytes[3] = math.floor(mant / 2^16) % 2^8
        -- bytes[4] = math.floor(mant / 2^24) % 2^8
        -- bytes[5] = math.floor(mant / 2^32) % 2^8                 -- pow(2, 32)
        -- bytes[6] = math.floor(mant / 2^40) % 2^8                 -- pow(2, 40)
        -- bytes[7] = (expo % 2^4) * 0x10 + math.floor(mant / 2^48) -- pow(2, 48)
        -- bytes[8] = sign + math.floor(expo / 0x10)

        return string.char(unpack(bytes))


            -- return string.char( sign + math.floor(expo / 0x10),
            --                      (expo % 0x10) * 0x10 + math.floor(mant / 281474976710656), -- pow(2, 48)
            --                      math.floor(mant / 1099511627776) % 0x100,                  -- pow(2, 40)
            --                      math.floor(mant / 4294967296) % 0x100,                     -- pow(2, 32)
            --                      math.floor(mant / 0x1000000) % 0x100,
            --                      math.floor(mant / 0x10000) % 0x100,
            --                      math.floor(mant / 0x100) % 0x100,
            --                      mant % 0x100)
    end


end

Codec.decodeDouble = function(bytes, offset, littleEndian)
    if not bytes or (#bytes < (8 + offset-1)) then
        return nil
    end


    for i = 1, 8 do
        uInt8Array[i] = bytes[offset + 8 - i  ]
        -- if littleEndian then
        --   uInt8Array[i] = bytes[offset + i - i  ]
        -- end
    end

    local b = uInt8Array
    local sign = b[1] > 0x7F and -1 or 1
    local expo = (b[1] % 0x80) * 0x10 + math.floor(b[2] / 0x10)
    local mant = ((((((b[2] % 0x10) * 0x100 + b[3]) * 0x100 + b[4]) * 0x100 + b[5]) * 0x100 + b[6]) * 0x100 + b[7]) * 0x100 + b[8]

    local n
    if mant == 0 and expo == 0 then
        n = 0.0
    elseif expo == 0x7FF then
        if mant == 0 then
            n = sign * math.huge
        else
            n = 0.0
        end
    else
        n = sign * math.ldexp(1.0 + mant / 4503599627370496.0, expo - 0x3FF)
    end

    return n
end

Codec.encodeStr = function(bytes, offset, str)
    local tmp = {string.byte(str, 1, #str)}
    for i, v in ipairs(tmp) do
        table.insert(bytes, v)
    end
    offset = offset + #tmp
    return offset
end

Codec.decodeStr = function(bytes, offset, length)
    local last = offset + length -1
    local arr = func.sliceTable(bytes, offset, offset+length-1)
    local str = string.char(unpack(arr))
    offset = last
    return str
end

Codec.byteLength = function(str)
    if type(str) ~= 'string' then
        return -1
    end

    local length = #str
    return length
end


-- local int32 = Codec.encodeUInt32(123123123)
-- dump(int32, Codec.decodeUInt32(int32))

-- local uInt32 = Codec.encodeSInt32(-123123123)
-- dump(uInt32, Codec.decodeSInt32(uInt32))

-- local float = Codec.encodeFloat(123.123)
-- dump(float, Codec.decodeFloat(float, 1))


-- local float = Codec.encodeFloat(123.12)
-- dump({string.byte(float, 1, #float)})
-- dump(Codec.decodeFloat({string.byte(float, 1, #float)},1))
-- local doub = Codec.encodeDouble(0.05)
-- dump({string.byte(doub,1, #doub)})
-- dump(Codec.decodeDouble({string.byte(doub,1, #doub)},1))
-- error()
return Codec

