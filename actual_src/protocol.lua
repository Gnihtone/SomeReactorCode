local component = require("component")
local serialization = require("serialization")
local event = require("event")

local config = require("SomeReactorCode.actual_src.config")

local Protocol = {}
Protocol.__index = Protocol

function Protocol:new(isServer)
    local self = setmetatable({}, Protocol)
    
    self.isServer = isServer
    self.modem = nil
    self.callbacks = {}
    
    if component.isAvailable("modem") then
        self.modem = component.modem
        self.modem.open(config.NETWORK.PORT)
    else
        error("Модем не найден! Требуется беспроводная сетевая карта или модем.")
    end
    
    return self
end

local function createMessage(messageType, data)
    local message = {
        protocol = config.NETWORK.PROTOCOL,
        type = messageType,
        timestamp = os.time(),
        data = data or {}
    }
    
    return message
end

local function send(address, messageType, data, modem)
    if not modem then
        return false, "Модем не инициализирован"
    end
    
    local message = createMessage(messageType, data)
    local serialized = serialization.serialize(message)
    
    if address == "broadcast" then
        modem.broadcast(config.NETWORK.PORT, serialized)
    else
        modem.send(address, config.NETWORK.PORT, serialized)
    end
    
    return true
end

function Protocol:send(address, messageType, data)
    return send(address, messageType, data, self.modem)
end

function Protocol:broadcast(messageType, data)
    return send("broadcast", messageType, data, self.modem)
end

function Protocol:receive(timeout)
    if not self.modem then
        return nil, "Модем не инициализирован"
    end
    
    local modem_message_event = {event.pull(timeout or 0, "modem_message")}
    
    if modem_message_event[1] then
        local _, _, from, port, _, serialized = table.unpack(modem_message_event)
        
        if port == config.NETWORK.PORT then
            local success, message = pcall(serialization.unserialize, serialized)
            
            if success and message and message.protocol == config.NETWORK.PROTOCOL then
                return message, from
            end
        end
    end
    
    return nil
end

function Protocol:registerHandler(messageType, callback)
    self.callbacks[messageType] = callback
end

function Protocol:processMessages(timeout)
    local message, from = self:receive(timeout)
    
    if message then
        local handler = self.callbacks[message.type]
        if handler then
            handler(message.data, from, message.timestamp)
        end
        return true
    end
    
    return false
end

function Protocol:formatLogMessage(level, message, reactorName)
    return {
        level = level,
        message = message,
        reactorName = reactorName,
        timestamp = os.time()
    }
end

function Protocol:validateMessage(message)
    if not message then return false end
    if message.protocol ~= config.NETWORK.PROTOCOL then return false end
    if not message.type then return false end
    if not message.timestamp then return false end
    
    local age = os.time() - message.timestamp
    if age > config.NETWORK.TIMEOUT then
        return false
    end
    
    return true
end
    
function Protocol:sendAck(address, originalMessageType)
    return self:send(address, config.MESSAGES.ACK, {
        originalType = originalMessageType,
        status = "OK"
    })
end

function Protocol:sendCommand(address, command, parameters, reactorId)
    return self:send(address, config.MESSAGES.COMMAND, {
        command = command,
        parameters = parameters or {},
        reactorId = reactorId
    })
end

function Protocol:discoverClients()
    return self:send("broadcast", config.MESSAGES.COMMAND, {
        command = "DISCOVER"
    })
end

function Protocol:close()
    if self.modem then
        self.modem.close(config.NETWORK.PORT)
    end
end

return Protocol 