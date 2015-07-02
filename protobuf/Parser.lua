local Parser = {}

Parser.parse = function (protos)
    local maps = {};
    for key, obj in pairs(protos) do
        if type(obj) == "string" then
            if protos[obj] then
                obj = protos[obj]
            end
        end
        if obj then
            maps[key] = Parser.parseObject(obj)
        end
    end
    return maps
end

Parser.parseObject = function(obj)
    local proto = {};
    local nestProtos = {};
    local tags = {};
    for tag, name in ipairs(obj) do
        local params =  string.split(name, ' ')
        local option = params[1]
        if option == "required" or option == "optional" or option == "repeated" then
            if #params == 3 and  not tags[tag] then
                proto[params[3]] = {
                    option = params[1],
                    type = params[2],
                    tag    = tag,
                }
                tags[tag] = params[3]
            end
        else
           proto[params[2]] = {
                option = "optional",
                type   = params[1],
                tag    = tag
            }
            tags[tag] = params[2]
        end

    end
    proto.__messages = nestProtos
    proto.__tags = tags
    return proto
end


return Parser