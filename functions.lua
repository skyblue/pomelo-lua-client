local func = {}

function func.copyArray(dest,doffset,src,soffset,length)
    if("table" ~= type(dest) or "table" ~= type(src) or length<=0 ) then
        return dest
    end
    for index=1,length do
        dest[doffset] = src[soffset]
        doffset = doffset + 1
        soffset = soffset + 1
    end
end

function func.printTable(t)
    for k,v in pairs(t) do
        printInfo("k=%s,v=%s",k,v)
    end
end

function func.sliceTable(t,i1,i2)
    local res = {}
    local n = #t
    -- default t for range
    i1 = i1 or 1
    i2 = i2 or n
    if i2 < 0 then
        i2 = n + i2 + 1
    elseif i2 > n then
        i2 = n
    end
    if i1 < 1 or i1 > n then
        return res
    end
    local k = 1
    for i = i1,i2 do
        res[k] = t[i]
        k = k + 1
    end
    return res
end

return func


