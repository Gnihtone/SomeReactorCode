local component = require("component")
local event = require("event")
local thread = require("thread")
local keyboard = require("keyboard")
local computer = require("computer")

local config = require("SomeReactorCode.actual_src.server.config")
local VacuumUI = require("SomeReactorCode.actual_src.server.ui")
local discordIntegration = require("SomeReactorCode.actual_src.server.discord.discord_integration")

local common_config = require("SomeReactorCode.actual_src.config")
local Protocol = require("SomeReactorCode.actual_src.protocol")

local ReactorsServer = {}
ReactorsServer.__index = ReactorsServer

function ReactorsServer:new()
    local self = setmetatable({}, ReactorsServer)
    
    self.running = false
    self.protocol = nil
    self.ui = nil
    self.discord = nil
    
    self.clients = {}
    self.reactorList = {}
    self.energyStorages = {}
    self.pausedReactors = {}
    
    self.recentLogs = {}
    self.maxLogHistory = 50
    
    self.messageThread = nil
    self.uiThread = nil
    self.energyManagementThread = nil
    
    return self
end

function ReactorsServer:init()
    print("Инициализация сервера вакуумных реакторов...")

    local isServer = true
    self.protocol = Protocol:new(isServer)
    
    self.ui = VacuumUI:new()
    self.ui:init()
    
    if config.DISCORD.ENABLED then
        local success, err = discordIntegration.init(self)
        if success then
            self.discord = discordIntegration
            self:log("INFO", "Discord интеграция активирована")
        else
            self:log("WARNING", "Не удалось инициализировать Discord: " .. tostring(err))
        end
    end
    
    self:setupHandlers()
    self:discoverClients()

    self:log("INFO", "Сервер запущен")
    
    return true
end

function ReactorsServer:setupHandlers()
    self.protocol:registerHandler(common_config.MESSAGES.REGISTER, function(data, from)
        self:handleClientRegister(data, from)
    end)
    
    self.protocol:registerHandler(common_config.MESSAGES.UNREGISTER, function(data, from)
        self:handleClientUnregister(data, from)
    end)
    
    self.protocol:registerHandler(common_config.MESSAGES.STATUS_UPDATE, function(data, from)
        self:handleStatusUpdate(data, from)
    end)
    
    self.protocol:registerHandler(common_config.MESSAGES.ENERGY_STORAGE_UPDATE, function(data, from)
        self:handleEnergyStorageUpdate(data, from)
    end)
    
    self.protocol:registerHandler(common_config.MESSAGES.LOG, function(data, from)
        self:handleClientLog(data, from)
    end)
end

function ReactorsServer:handleClientRegister(data, address)
    self:log("INFO", "Регистрация клиента: " .. data.name .. " [" .. address:sub(1, 8) .. "]")
    
    if data.type == common_config.NETWORK.CLIENT_TYPES.REACTOR_CLIENT then
        self.clients[address] = {
            address = address,
            name = data.name,
            type = data.type,
            lastSeen = computer.uptime(),
            reactors = {}
        }
        
        if data.reactors then
            for _, reactor in ipairs(data.reactors) do
                self.clients[address].reactors[reactor.reactorId] = reactor
            end
        end
    elseif data.type == common_config.NETWORK.CLIENT_TYPES.ENERGY_STORAGE_CLIENT then
        self.clients[address] = {
            address = address,
            name = data.name,
            type = data.type,
            lastSeen = computer.uptime(),
            storages = {}
        }

        if data.storages then
            for _, storage in ipairs(data.storages) do
                self.clients[address].storages[storage.id] = storage
            end
        end
    else
        self:log("ERROR", "Unknown client type: " .. data.type)
    end
    
    self.protocol:sendAck(address, common_config.MESSAGES.REGISTER)
    
    self:updateReactorList()
end

function ReactorsServer:handleClientUnregister(data, address)
    if self.clients[address] then
        self:log("INFO", "Отключение клиента: " .. self.clients[address].name)
        
        if self.clients[address].type == common_config.NETWORK.CLIENT_TYPES.REACTOR_CLIENT then
            for _, reactor in pairs(self.clients[address].reactors) do
                reactor.status = common_config.REACTOR_STATUS.OFFLINE
            end
        elseif self.clients[address].reactorData then
            self.clients[address].reactorData.status = common_config.REACTOR_STATUS.OFFLINE
        end
        
        self:updateReactorList()
    end
end

function ReactorsServer:handleStatusUpdate(data, address)
    if self.clients[address] then
        self.clients[address].lastSeen = computer.uptime()
        
        if self.clients[address].type == common_config.NETWORK.CLIENT_TYPES.REACTOR_CLIENT then
            if data.reactors then
                for _, reactorData in ipairs(data.reactors) do
                    if self.clients[address].reactors[reactorData.reactorId] then
                        self.clients[address].reactors[reactorData.reactorId] = {
                            reactorId = reactorData.reactorId,
                            name = reactorData.name,
                            status = reactorData.status,
                            isBreeder = reactorData.isBreeder,
                            pausedForEnergy = self.pausedReactors[reactorData.reactorId] or false,
                            temperature = reactorData.temperature,
                            maxTemperature = reactorData.maxTemperature,
                            euOutput = reactorData.euOutput,
                            uptime = reactorData.uptime,
                            totalEU = reactorData.totalEU,
                            runningTime = reactorData.runningTime,
                            coolantStatus = reactorData.coolantStatus,
                            fuelStatus = reactorData.fuelStatus,
                        }
                    end
                end
            end
        end
        
        self:updateReactorList()
    end
end

function ReactorsServer:handleEnergyStorageUpdate(data, address)
    if self.clients[address] then
        self.clients[address].lastSeen = computer.uptime()
        
        self.energyStorages[address] = data.storages or {}
        
        local storedEU = 0
        local capacityEU = 0
        
        for _, storage in ipairs(data.storages) do
            storedEU = storedEU + storage.stored
            capacityEU = capacityEU + storage.capacity
        end
        
        local fillPercent = storedEU / capacityEU

        if fillPercent >= config.ENERGY_STORAGE.FULL_THRESHOLD then
            self:pauseReactorsForEnergy(string.format("Хранилище заполнено на %.1f%%", fillPercent * 100))
        elseif fillPercent < config.ENERGY_STORAGE.RESUME_THRESHOLD then
            self:resumeReactorsFromEnergyPause()
        end
    end
end

function ReactorsServer:pauseReactorsForEnergy(reason)
    self:log("INFO", "Приостановка реакторов: " .. reason)
    
    local totalStored = 0
    local totalCapacity = 0
    for _, storages in pairs(self.energyStorages) do
        for _, storage in ipairs(storages) do
            totalStored = totalStored + storage.stored
            totalCapacity = totalCapacity + storage.capacity
        end
    end
    local fillPercent = totalCapacity > 0 and (totalStored / totalCapacity) or 0
    
    if self.discord then
        self.discord.sendNotification("ENERGY_PAUSE", {fillPercent = fillPercent})
    end
    
    for address, client in pairs(self.clients) do
        if client.type == common_config.NETWORK.CLIENT_TYPES.REACTOR_CLIENT then
            for reactorId, reactor in pairs(client.reactors) do
                if reactor.status == common_config.REACTOR_STATUS.RUNNING and not reactor.isBreeder then
                    self.protocol:sendCommand(address, common_config.COMMANDS.STOP, {}, reactorId)
                    self.pausedReactors[reactorId] = true
                end
            end
        end
    end
end

function ReactorsServer:resumeReactorsFromEnergyPause()
    self:log("INFO", "Возобновление работы реакторов после освобождения энергохранилища")
    
    for address, client in pairs(self.clients) do
        if client.type == common_config.NETWORK.CLIENT_TYPES.REACTOR_CLIENT then
            for reactorId, reactor in pairs(client.reactors) do
                if self.pausedReactors[reactorId] then
                    self.protocol:sendCommand(address, common_config.COMMANDS.START, {}, reactorId)
                    self.pausedReactors[reactorId] = nil
                end
            end
        end
    end
end

function ReactorsServer:handleEmergency(data, address)
    if self.clients[address] then
        local clientName = self.clients[address].name
        local reactorId = data.reactorId or data.reactorName or "Unknown"
        self:log("CRITICAL", "АВАРИЙНАЯ СИТУАЦИЯ на " .. reactorId .. ": " .. data.reason)
        
        if data.temperature then
            self:log("CRITICAL", string.format("Температура: %d°C (%.1f%%)", 
                data.temperature, data.tempPercent * 100))
        end
        
        if self.discord then
            self.discord.sendNotification("EMERGENCY", {
                name = reactorId,
                id = reactorId,
                reason = data.reason
            })
        end
    end
end

function ReactorsServer:handleClientLog(data, address)
    if self.clients[address] then
        self.ui:addLog(data.timestamp or os.time(), data.level, data.message, data.reactorName)
    end
end

function ReactorsServer:discoverClients()
    self:log("INFO", "Поиск активных реакторов и энергохранилищ...")
    self.protocol:discoverClients()
end

function ReactorsServer:updateReactorList()
    self.reactorList = {}
    
    for address, client in pairs(self.clients) do
        if client.type == common_config.NETWORK.CLIENT_TYPES.REACTOR_CLIENT then
            for reactorId, reactor in pairs(client.reactors) do
                table.insert(self.reactorList, reactor)
            end
        elseif client.type == common_config.NETWORK.CLIENT_TYPES.REACTOR_CLIENT and client.reactorData then
            table.insert(self.reactorList, client.reactorData)
        end
    end
    
    table.sort(self.reactorList, function(a, b)
        return a.name < b.name
    end)
    
    self.ui:updateReactors(self.reactorList)
end

function ReactorsServer:checkConnectionTimeouts()
    local currentTime = computer.uptime()
    local hasChanges = false
    
    for address, client in pairs(self.clients) do
        local timeSinceLastSeen = currentTime - client.lastSeen
        
        if timeSinceLastSeen > common_config.NETWORK.CONNECTION_TIMEOUT then
            if client.type == common_config.NETWORK.CLIENT_TYPES.REACTOR_CLIENT then
                for _, reactor in pairs(client.reactors) do
                    if reactor.status ~= common_config.REACTOR_STATUS.OFFLINE then
                        reactor.status = common_config.REACTOR_STATUS.OFFLINE
                        hasChanges = true
                    end
                end
            end
            
            if hasChanges then
                self:log("WARNING", "Потеряна связь с " .. client.name)
            end
        end
    end
    
    if hasChanges then
        self:updateReactorList()
    end
end

function ReactorsServer:getReactors()
    local reactors = {}
    for _, reactor in ipairs(self.reactorList) do
        reactors[reactor.reactorId or reactor.name] = reactor
    end
    return reactors
end

function ReactorsServer:getEnergyStorages()
    local allStorages = {}
    for _, storages in pairs(self.energyStorages) do
        for _, storage in ipairs(storages) do
            table.insert(allStorages, storage)
        end
    end
    return allStorages
end

function ReactorsServer:getRecentLogs(count)
    count = count or 10
    local logs = {}
    local startIdx = math.max(1, #self.recentLogs - count + 1)
    for i = startIdx, #self.recentLogs do
        table.insert(logs, self.recentLogs[i])
    end
    return logs
end

function ReactorsServer:startReactor(reactorName)
    return self:sendReactorCommand(reactorName, common_config.COMMANDS.START)
end

function ReactorsServer:stopReactor(reactorName)
    return self:sendReactorCommand(reactorName, common_config.COMMANDS.STOP)
end

function ReactorsServer:startAllReactors()
    self:sendReactorCommandToAll(common_config.COMMANDS.START)
end

function ReactorsServer:stopAllReactors()
    self:sendReactorCommandToAll(common_config.COMMANDS.STOP)
end

function ReactorsServer:sendReactorCommand(reactorName, command)
    for address, client in pairs(self.clients) do
        if client.type == common_config.NETWORK.CLIENT_TYPES.REACTOR_CLIENT then
            for reactorId, reactor in pairs(client.reactors) do
                if reactor.name == reactorName then
                    self.protocol:sendCommand(address, command, {}, reactorId)
                    self:log("INFO", "Команда " .. command .. " отправлена на " .. reactorName)
                    
                    if self.discord then
                        if command == common_config.COMMANDS.START then
                            self.discord.sendNotification("REACTOR_START", {name = reactorName, id = reactorId})
                        elseif command == common_config.COMMANDS.STOP then
                            self.discord.sendNotification("REACTOR_STOP", {name = reactorName, id = reactorId})
                        end
                    end
                    
                    return true
                end
            end
        elseif client.reactorData and client.reactorData.name == reactorName then
            self.protocol:sendCommand(address, command)
            self:log("INFO", "Команда " .. command .. " отправлена на " .. reactorName)
            
            if self.discord then
                if command == common_config.COMMANDS.START then
                    self.discord.sendNotification("REACTOR_START", {name = reactorName})
                elseif command == common_config.COMMANDS.STOP then
                    self.discord.sendNotification("REACTOR_STOP", {name = reactorName})
                end
            end
            
            return true
        end
    end
    
    self:log("ERROR", "Реактор " .. reactorName .. " не найден")
    return false
end

function ReactorsServer:sendReactorCommandToAll(command)
    for address, client in pairs(self.clients) do
        if client.type == common_config.NETWORK.CLIENT_TYPES.REACTOR_CLIENT then
            self.protocol:sendCommand(address, command)
        end
    end
end

function ReactorsServer:exit()
    self:sendReactorCommandToAll(common_config.COMMANDS.STOP)
    self.running = false
end

function ReactorsServer:handleUserInput(key, code)
    if key == keyboard.keys.up then
        self.ui:scrollUp()
    elseif key == keyboard.keys.down then
        self.ui:scrollDown()
    elseif key == keyboard.keys.enter then
        local reactor = self.ui:getSelectedReactor()
        if reactor then
            self.ui:selectReactor(self.ui.selectedReactor)
        end
    elseif key == keyboard.keys.s then
        local reactor = self.ui:getSelectedReactor()
        if reactor then
            self:sendReactorCommand(reactor.name, common_config.COMMANDS.START)
        end
    elseif key == keyboard.keys.g then
        self:sendReactorCommandToAll(common_config.COMMANDS.STOP)
    elseif key == keyboard.keys.p then
        self:sendReactorCommandToAll(common_config.COMMANDS.START)
    elseif key == keyboard.keys.t then
        local reactor = self.ui:getSelectedReactor()
        if reactor then
            self:sendReactorCommand(reactor.name, common_config.COMMANDS.STOP)
        end
    elseif key == keyboard.keys.m then
        local reactor = self.ui:getSelectedReactor()
        if reactor then
            self:sendReactorCommand(reactor.name, common_config.COMMANDS.FORCE_MAINTENANCE)
        end
    elseif key == keyboard.keys.r then
        self:discoverClients()
    elseif key == keyboard.keys.q then
        self:exit()
    elseif key >= keyboard.keys["1"] and key <= keyboard.keys["9"] then
        local index = key - keyboard.keys["1"] + 1
        self.ui:selectReactor(index)
    end
end

function ReactorsServer:log(level, message, reactor)
    local timestamp = os.time()
    
    self.ui:addLog(timestamp, level, message, reactor)
    
    table.insert(self.recentLogs, {
        timestamp = os.date("%Y-%m-%d %H:%M:%S", timestamp),
        level = level,
        message = message,
        reactor = reactor
    })
    
    while #self.recentLogs > self.maxLogHistory do
        table.remove(self.recentLogs, 1)
    end
    
    if self.discord then
        self.discord.sendLog(level, message, reactor)
    end
    
end

function ReactorsServer:run()
    if not self:init() then
        return
    end
    
    self.running = true

    if self.discord then
        local success, err = self.discord.start()
        if not success then
            self:log("ERROR", "Не удалось запустить Discord интеграцию: " .. tostring(err))
        end
    end
    
    self.messageThread = thread.create(function()
        while self.running do
            self.protocol:processMessages(0.1)
        end
    end)
    
    self.uiThread = thread.create(function()
        while self.running do
            self:checkConnectionTimeouts()
            
            os.sleep(config.UI.UPDATE_INTERVAL)
        end
    end)
    
    while self.running do
        local eventData = {event.pull(0.1)}
        
        if eventData[1] == "key_down" then
            local _, _, _, code = table.unpack(eventData)
            self:handleUserInput(code, code)
        elseif eventData[1] == "interrupted" then
            self:exit()
        end
    end
    
    self:log("INFO", "Остановка сервера...")
    
    if self.discord then
        self.discord.stop()
    end
    
    if self.messageThread then
        self.messageThread:kill()
    end
    if self.uiThread then
        self.uiThread:kill()
    end
    
    self.protocol:close()
    
    self.ui:cleanup()
end

local server = ReactorsServer:new()

local function interruptEvent()
    print("\nОстановка сервера...")
    server:exit()
end

event.listen("interrupted", interruptEvent)
server:run()
event.ignore("interrupted", interruptEvent)
