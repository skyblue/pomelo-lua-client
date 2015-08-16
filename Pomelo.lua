-- 需要有一个消息pool 定时取消息处理,否则容易卡UI
-- 再封装一层connector, 切换使用tcp, udp websocket
local scheduler = require("framework.scheduler")
local Protobuf = require("libs.pomelo.Protobuf")
local Protocol = require("libs.pomelo.Protocol")
local Package = require("libs.pomelo.Package")
local Message = require("libs.pomelo.Message")
local Emitter = require("libs.pomelo.Emitter")

local RES_OK = 200
local RES_FAIL = 500
local RES_OLD_CLIENT = 501

local LUA_CLIENT_TYPE = 'lua-client'
local LUA_CLIENT_VERSION = '0.0.1'

-- 继承Emitter
local Pomelo = class("Pomelo",function()
    return Emitter.new()
end)

Pomelo.CONNECT_TYPE = {
    TCP = "tcp",
    WEBSOCKET = "websocket"
}

function Pomelo:ctor()
    self.socket = nil
    self.reqId = 1
    --Map from request id to route
    self.routeMap = {}

    self.heartbeatInterval = 0
    self.heartbeatTimeout = 0
    self.nextHeartbeatTimeout = 0
    self.gapThreshold = 1       -- heartbeat gap threashold
    self.heartbeatId = nil
    self.heartbeatTimeoutId = nil

    self.handshakeBuffer = {
        sys = {
            type = LUA_CLIENT_TYPE,
            version = LUA_CLIENT_VERSION,
        -- TODO 添加RSA加密选项,生成加密的key在本地
        },
        user = {}
    }

    self.handlers = {}
    self.handlers[Package.TYPE_HANDSHAKE] = handler(self,self._handshake)
    self.handlers[Package.TYPE_HEARTBEAT] = handler(self,self.heartbeat)
    self.handlers[Package.TYPE_DATA] = handler(self,self._onData)
    self.handlers[Package.TYPE_KICK] = handler(self,self._onKick)

    -- self._callbacks = {}
    self._messagePool = {}
end

function Pomelo:init(params, cb)
    printf("Pomelo:init()")
    self.params = params

    local host = params.host
    local port = params.port
    local connectType = params.connect or Pomelo.CONNECT_TYPE.WEBSOCKET

    self.connectType = connectType
    self.initCallback = cb
    self.handshakeBuffer.user = params.user
    self.handshakeCallback = params.handshakeCallback


    if connectType == Pomelo.CONNECT_TYPE.WEBSOCKET then
        self:_initWebSocket(host, port, cb)
    else
        self:_initTcpSocket(host, port, cb)
    end

end

function Pomelo:request(route, msg, cb)
    --printf("Pomelo:request()")

    if not route then
        return false
    end

    if not self:_isReady() then
        printError("Pomelo:request() - socket not ready")
        return false
    end

    self.reqId = self.reqId + 2
    -- if math.fmod(self.reqId, 128) == 0  then
    --     self.reqId = self.reqId + 1
    -- end
    -- self.reqId = self.reqId+1
    -- if self.reqId > 127 then
    --     self.reqId = 1
    -- end

    self:_sendMessage(self.reqId, route, msg)

    self._callbacks[self.reqId] = cb
    self.routeMap[self.reqId] = route
    return true
end

function Pomelo:notify(route,msg)
    if not self:_isReady() then
        printError("Pomelo:notify() - socket not ready")
        return
    end

    local msg = msg or {}
    self:_sendMessage(0, route, msg)
end


function Pomelo:disconnect()
    printf("Pomelo:disconnect()")
    if self:_isReady() then
        self.socket:close()
        self.socket = nil
    end

    if self.heartbeatId then
        self:_clearTimeout(self.heartbeatId)
        self.heartbeatId = nil
    end

    if self.heartbeatTimeoutId then
        self:_clearTimeout(self.heartbeatTimeoutId)
        self.heartbeatTimeoutId = nil
    end

    self:removeAllListener()
end

function Pomelo:reconnect()
    local params = self.params
    params.reconnect = true
    self:init(params)
    params.reconnect = nil
end

-- 用于外部文件缓存dict/protos, 减少数据流量
function Pomelo:getData()
    return self.data
end

function Pomelo.setData(data)
    self.data = data
end


function Pomelo:_initWebSocket(host, port)

    local _bin2hex = function(binary)
        local t = {}
        for i = 1, string.len(binary) do
            t[i] = string.byte(binary,i)
        end
        return t
    end

    local onopen = function(event)
        self:emit('open')

        if self.data then
            if self.data.dict and self.data.dictVersion then
                self.handshakeBuffer.sys.dictVersion = self.data.dictVersion
            end

            if self.data.protos and self.data.protos.version then
                self.handshakeBuffer.sys.protoVersion = self.data.protos.version
            end
        end

        local obj = Package.encode(Package.TYPE_HANDSHAKE, Protocol.strencode(json.encode(self.handshakeBuffer)))
        self:_send(obj)
    end

    local onmessage = function(message)
        -- if type(message) == "string" then
        --     message = _bin2hex(message)
        -- end
        self:_processPackage(Package.decode(message))
        -- new package arrived,update the heartbeat timeout
        if self.heartbeatTimeout ~= 0 then
            self.nextHeartbeatTimeout = os.time() + self.heartbeatTimeout
        end
    end

    local onerror = function(event)
        self:emit('io-error',event)
        self:disconnect()
    end

    local onclose = function(event)
        self:emit('close',event)
        self:disconnect()
    end

    local url = 'ws://' .. host
    if port then
        url = url .. ':' .. port
    end

    self.socket = cc.WebSocket:create(url)

    self.socket:registerScriptHandler(onopen, cc.WEBSOCKET_OPEN)
    self.socket:registerScriptHandler(onmessage,cc.WEBSOCKET_MESSAGE)
    self.socket:registerScriptHandler(onclose,cc.WEBSOCKET_CLOSE)
    self.socket:registerScriptHandler(onerror,cc.WEBSOCKET_ERROR)

    self.socket.send = self.socket.sendString

end

function Pomelo:_initTcpSocket(host, port)
    local Socket = require("framework.cc.net.SocketTCP")
    local socket = Socket.new(host, port, false)

    self.socket = socket
    self.buffer = ""

    socket:addEventListener(Socket.EVENT_CONNECTED, function()
        self:emit("open")
        -- 握手
        dump(self.handshakeBuffer)
        local obj = Package.encode(Package.TYPE_HANDSHAKE, Protocol.strencode(json.encode(self.handshakeBuffer)))
        self:_send(obj)


    end)

    socket:addEventListener(Socket.EVENT_CLOSED, function(event)
        self:emit('close', event)
        -- self:disconnect()
    end)

    socket:addEventListener(Socket.EVENT_CONNECT_FAILURE, function(event)
        self:emit('io-error')
        -- self:disconnect()
    end)

    socket:addEventListener(Socket.EVENT_DATA, function(event)
        self.buffer = self.buffer .. event.data
        -- self:emit("data")
        -- console.log(#self.buffer, string.byte(event.data, 1,10))

        local bufferLength = #self.buffer

        while bufferLength >= 4 do
            local type_, packLen = Package.decodeHead({string.byte(self.buffer, 1, 4)})

            -- console.log("#type_, packlen", type_, packLen )
            packLen = packLen + 4

            if bufferLength < packLen then
                break
            end

            local buff = string.sub(self.buffer, 1, packLen)
            local bytes = {}
            for i = 1, packLen do
                bytes[i] = string.byte(buff, i, i+1)
            end


            self:_processPackage(Package.decode(bytes))
            if self.heartbeatTimeout ~= 0 then
                self.nextHeartbeatTimeout = os.time() + self.heartbeatTimeout
            end

            self.buffer = string.sub(self.buffer, packLen + 1)
            -- console.log("#self.buffer len", #self.buffer)
            bufferLength = #self.buffer
        end

    end)



    socket:connect()

end


function Pomelo:_processPackage(msg)
    if not msg then return end
    if #msg > 0 then
        for i, msg_ in ipairs(msg) do
            self.handlers[msg_.type](msg_.body)
        end
    else
        self.handlers[msg.type](msg.body)
    end
end


function Pomelo:_processMessage(msg)
    --    printf("Pomelo:_processMessage()")
    --    printf("msg.id=%s,msg.route=%s,msg.body=%s",msg.id,msg.route,msg.body)
    --    printf("json.encode(msg.body)=%s",json.encode(msg.body))
    if msg.id==0 then
        -- server push message
        self:emit(msg.route, msg.body)
    end

    --if have a id then find the callback function with the request
    local cb = self._callbacks[msg.id]
    --    printf("msg.id=%s,type(cb)=%s",msg.id,type(cb))
    self._callbacks[msg.id] = nil
    if type(cb) ~= 'function' then
        return
    end

    --    --printf("type(msg.body)=%s",type(msg.body))
    cb(msg.body)

    --    return self
end

function Pomelo:_processMessageBatch(msgs)
    for i=1,#msgs do
        self:_processMessage(msgs[i])
    end
end

function Pomelo:_isReady()
    if not self.socket then return false end

    if self.connectType == Pomelo.CONNECT_TYPE.WEBSOCKET then
        return  (self.socket:getReadyState() == cc.WEBSOCKET_STATE_OPEN)
    else
        return self.socket.isConnected
    end
end

function Pomelo:_sendMessage(reqId,route,msg)
    local _type = Message.TYPE_REQUEST
    if reqId == 0 then
        _type = Message.TYPE_NOTIFY
    end

    --compress message by Protobuf
    -- TODO 暂时不支持 Protobuf
    local protos = {}
    if self.data.protos then
        protos = self.data.protos.client
    end

    if protos[route] then
        msg = Protobuf.encode(route, msg)
    else
        msg = Protocol.strencode(json.encode(msg))
    end

    local compressRoute = 0
    if self.data.dict and self.data.dict[route] then
        route = self.data.dict[route]
        compressRoute = 1
    end

    msg = Message.encode(reqId,_type,compressRoute,route,msg)
    local packet = Package.encode(Package.TYPE_DATA, msg)

    self:_send(packet)
end

function Pomelo:_send(packet)
    if self:_isReady() then

        -- local arr, len = {}, #packet
        -- for i = 1, len do
        --     arr[i] = string.char(packet[i])
        -- end
        -- local str = table.concat(arr)
        local str = Protocol.strdecode(packet)

        self.socket:send(str)
        -- dump(msg)

        -- dump(packet)
        if(#str ==11) then
        -- dump(packet)
        -- local msg = Package.decode(Protocol.strencode(str))
        -- dump(msg)
        -- dump(Message.decode(msg.body))
        end
    end
end

function Pomelo:heartbeat(data)
    --    printf("Pomelo:heartbeat(data)")

    if self.heartbeatInterval == 0 then
        -- no heartbeat
        return
    end

    if self.heartbeatId ~= nil then
        -- already in a heartbeat interval
        return
    end

    if self.heartbeatTimeoutId ~= nil then
        self:_clearTimeout(self.heartbeatTimeoutId)
        self.heartbeatTimeoutId = nil
    end

    local obj = Package.encode(Package.TYPE_HEARTBEAT)

    self.heartbeatId = self:_setTimeout(
        function()
            self:_send(obj)

            self.nextHeartbeatTimeout = os.time() + self.heartbeatTimeout
            self.heartbeatTimeoutId = self:_setTimeout(handler(self, self.heartbeatTimeoutCb), self.heartbeatTimeout)

            self:_clearTimeout(self.heartbeatId)
            self.heartbeatId = nil
        end,
        self.heartbeatInterval)
end

function Pomelo:heartbeatTimeoutCb()
    local gap = self.nextHeartbeatTimeout - os.time()
    -- printf("Pomelo:heartbeatTimeoutCb() os.time()=%s",os.time())
    -- printf("gap=%s,self.gapThreshold=%s",gap,self.gapThreshold)
    if gap > self.gapThreshold then
        self.heartbeatTimeoutId = self:_setTimeout(handler(self,self.heartbeatTimeoutCb),gap)
    else
        printf('heartbeat timeout')
        self:emit('heartbeat timeout')
        self:disconnect()
    end
end

function Pomelo:_handshake(data)
    -- printf("Pomelo:_handshake Protocol.strdecode(data)=%s",#data, Protocol.strdecode(data))
    -- dump(Protocol.strdecode(data), #data)

    data = json.decode(Protocol.strdecode(data))

    if data.code == RES_OLD_CLIENT then
        self:emit('error','client version not fullfill')
        return
    end

    if data.code ~= RES_OK then
        self:emit('error','_handshake fail')
        return
    end

    self:_handshakeInit(data)

    local obj = Package.encode(Package.TYPE_HANDSHAKE_ACK)
    self:_send(obj)

    if self.initCallback then
        self:initCallback(self.socket)
        self.initCallback = nil
    end

end


function Pomelo:_onData(data)
    local msg = Message.decode(data)
    if msg.id > 0 then
        msg.route = self.routeMap[msg.id]
        self.routeMap[msg.id] = nil
        if not msg.route then
            return
        end
    end
    msg.body = self:_deCompose(msg)
    self:_processMessage(msg)
end

function Pomelo:_onKick(data)
    local msg = json.decode(Protocol.strdecode(data))
    self:emit('onKick', msg)
end

-- msg 为packect.decode后的, body需要message.decode , body可以为pbc编码, msgpack等
function Pomelo:_deCompose(msg)
    local protos = {}
    if self.data.protos then
        protos = self.data.protos.server
    end
    local abbrs = self.data.abbrs
    local route = msg.route

    --Decompose route from dict
    if msg.compressRoute ~= 0 then
        if not abbrs[route] then
            return {}
        end
        msg.route = abbrs[route]
        route = msg.route
    end

    if Protobuf and protos[route] then
        return Protobuf.decode(route,msg.body)
    else
        return json.decode(Protocol.strdecode(msg.body))
    end

    return msg
end

function Pomelo:_handshakeInit(data)
    --    printf("Pomelo:_handshakeInit(data=%s)",json.encode(data))
    if data.sys and data.sys.heartbeat then
        self.heartbeatInterval = data.sys.heartbeat         -- heartbeat interval
        self.heartbeatTimeout = self.heartbeatInterval * 2  -- max heartbeat timeout
    end

    if data.user and data.user.heartbeat then
        self.heartbeatInterval = data.user.heartbeat         -- heartbeat interval
        self.heartbeatTimeout = self.heartbeatInterval * 5   -- max heartbeat timeout
    end

    self:_initData(data)

    if type(self.handshakeCallback) == 'function' then
        self:handshakeCallback(data.user)
    end

end

--Initilize data used in pomelo client
function Pomelo:_initData(data)
    if not data or not data.sys then
        return
    end

    self.data = self.data or {}

    local dict = data.sys.dict
    local protos = data.sys.protos

    --Init compress dict
    if data.sys.useDict and dict then
        self.data.dict = dict
        self.data.abbrs = {}
        for k,v in pairs(dict) do
            self.data.abbrs[dict[k]] = k
        end
    end

    self.data.dictVersion = data.sys.dictVersion


    -- Init Protobuf protos
    if  data.sys.useProto and protos then
        self.data.protos = data.sys.protos
        Protobuf.init({
            encoderProtos = self.data.protos.client,
            decoderProtos = self.data.protos.server
        })

    end


end

function Pomelo:_setTimeout(fn,delay)
    return scheduler.performWithDelayGlobal(fn,delay)
end

function Pomelo:_clearTimeout(fn)
    if fn and fn ~= 0 then
        scheduler.unscheduleGlobal(fn)
    end
end

return Pomelo


