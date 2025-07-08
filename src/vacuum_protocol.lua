-- Протокол обмена данными для распределенной системы управления вакуумными реакторами
local component = require("component")
local serialization = require("serialization")
local config = require("vacuum_config")

local Protocol = {}
Protocol.__index = Protocol

-- Создание нового экземпляра протокола
function Protocol:new(isServer)
    local self = setmetatable({}, Protocol)
    
    self.isServer = isServer
    self.modem = nil
    self.callbacks = {}
    
    -- Поиск модема
    if component.isAvailable("modem") then
        self.modem = component.modem
        self.modem.open(config.NETWORK.PORT)
        
        -- Установка силы сигнала для реле
        if self.modem.setStrength then
            self.modem.setStrength(config.NETWORK.RELAY_STRENGTH)
        end
    else
        error("Модем не найден! Требуется беспроводная сетевая карта или модем.")
    end
    
    return self
end

-- Создание сообщения
function Protocol:createMessage(messageType, data)
    local message = {
        protocol = config.NETWORK.PROTOCOL,
        type = messageType,
        timestamp = os.time(),
        data = data or {}
    }
    
    return message
end

-- Отправка сообщения
function Protocol:send(address, messageType, data)
    if not self.modem then
        return false, "Модем не инициализирован"
    end
    
    local message = self:createMessage(messageType, data)
    local serialized = serialization.serialize(message)
    
    if address == "broadcast" then
        self.modem.broadcast(config.NETWORK.PORT, serialized)
    else
        self.modem.send(address, config.NETWORK.PORT, serialized)
    end
    
    return true
end

-- Получение сообщения
function Protocol:receive(timeout)
    if not self.modem then
        return nil, "Модем не инициализирован"
    end
    
    local event = {component.modem.pull(timeout or 0, "modem_message")}
    
    if event[1] then
        local _, _, from, port, _, serialized = table.unpack(event)
        
        if port == config.NETWORK.PORT then
            local success, message = pcall(serialization.unserialize, serialized)
            
            if success and message and message.protocol == config.NETWORK.PROTOCOL then
                return message, from
            end
        end
    end
    
    return nil
end

-- Регистрация обработчика сообщений
function Protocol:registerHandler(messageType, callback)
    self.callbacks[messageType] = callback
end

-- Обработка входящих сообщений
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

-- Форматирование данных о реакторе для передачи
function Protocol:formatReactorData(reactor)
    return {
        name = reactor.name,
        status = reactor.status,
        temperature = reactor.temperature,
        maxTemperature = reactor.maxTemperature,
        tempPercent = reactor.tempPercent,
        euOutput = reactor.euOutput,
        efficiency = reactor.efficiency,
        running = reactor.running,
        emergencyMode = reactor.emergencyMode,
        emergencyCooldown = reactor.emergencyCooldown,
        maintenanceMode = reactor.maintenanceMode,
        lastError = reactor.lastError,
        coolantStatus = reactor.coolantStatus,
        fuelStatus = reactor.fuelStatus,
        uptime = reactor.uptime,
        totalEU = reactor.totalEU
    }
end

-- Форматирование лог-сообщения
function Protocol:formatLogMessage(level, message, reactorName)
    return {
        level = level,
        message = message,
        reactorName = reactorName,
        timestamp = os.time()
    }
end

-- Проверка валидности сообщения
function Protocol:validateMessage(message)
    if not message then return false end
    if message.protocol ~= config.NETWORK.PROTOCOL then return false end
    if not message.type then return false end
    if not message.timestamp then return false end
    
    -- Проверка актуальности сообщения (не старше таймаута)
    local age = os.time() - message.timestamp
    if age > config.NETWORK.TIMEOUT then
        return false
    end
    
    return true
end

-- Отправка подтверждения
function Protocol:sendAck(address, originalMessageType)
    return self:send(address, config.MESSAGES.ACK, {
        originalType = originalMessageType,
        status = "OK"
    })
end

-- Отправка команды реактору
function Protocol:sendCommand(address, command, parameters)
    return self:send(address, config.MESSAGES.COMMAND, {
        command = command,
        parameters = parameters or {}
    })
end

-- Широковещательный запрос для обнаружения клиентов
function Protocol:discoverClients()
    return self:send("broadcast", config.MESSAGES.COMMAND, {
        command = "DISCOVER"
    })
end

-- Закрытие протокола
function Protocol:close()
    if self.modem then
        self.modem.close(config.NETWORK.PORT)
    end
end

return Protocol 