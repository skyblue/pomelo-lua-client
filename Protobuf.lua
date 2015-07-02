
local Constants = {}
Constants.TYPES = {
    uInt32  = 0,
    sInt32  = 0,
    int32   = 0,
    double  = 1,
    string  = 2,
    message = 2,
    float   = 5
}



local Util = {}
Util.isSimpleType = function(type_)
    return ( type_ == 'uInt32' or
        type_ == 'sInt32' or
        type_ == 'int32'  or
        type_ == 'uInt64' or
        type_ == 'sInt64' or
        type_ == 'float'  or
        type_ == 'double' or
        type_ == 'bool'   or
        type_ == 'boolean')
end



Protobuf = {}

-- local Constants,Util, MsgEncoder, MsgDecoder, Parser, Codec = {}, {}, {}, {}, {}, {}
Protobuf.constants = Constants
Protobuf.util      = Util
Protobuf.parser    = require("libs.pomelo.protobuf.Parser")
Protobuf.codec     = require("libs.pomelo.protobuf.Codec")
Protobuf.encoder   = require("libs.pomelo.protobuf.Encoder")
Protobuf.decoder   = require("libs.pomelo.protobuf.Decoder")



Protobuf.init = function(protos)
    local parser = Protobuf.parser
    -- dump(parser.parse(protos.decoderProtos), "decoderProtos")
    Protobuf.encoder.init(parser.parse(protos.encoderProtos))
    Protobuf.decoder.init(parser.parse(protos.decoderProtos))
end

Protobuf.encode = function(key, msg)
    return Protobuf.encoder.encode(key, msg)
end

Protobuf.decode = function(key, msg)
    return Protobuf.decoder.decode(key, msg)
end


return Protobuf






