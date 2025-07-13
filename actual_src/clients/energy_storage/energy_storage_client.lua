-- Клиент мониторинга энергохранилищ
local component = require("component")
local event = require("event")
local thread = require("thread")
local computer = require("computer")
local config = dofile("config.lua")

local common_config = dofile("../../config.lua")
local Protocol = dofile("../../protocol.lua")

local EnergyStorageClient = {}
EnergyStorageClient.__index = EnergyStorageClient

function EnergyStorageClient:new(clientName)
    local self = setmetatable({}, EnergyStorageClient)
    
    self.clientName = (clientName or "EnergyStorage-") .. computer.address():sub(1, 8)
    self.running = false
    self.serverAddress = nil
    self.lastUpdate = 0
    
    self.protocol = nil
    self.storages = {}
    
    self.messageThread = nil
    self.mainThread = nil
    
    return self
end

-- Инициализация клиента
function EnergyStorageClient:init()
    print("Инициализация клиента энергохранилищ: " .. self.clientName)
    
    local isServer = false
    self.protocol = Protocol:new(isServer)
    
    self:findAllStorages()
    
    if #self.storages == 0 then
        print("ВНИМАНИЕ: Не найдено ни одного поддерживаемого энергохранилища!")
    else
        print("Найдено энергохранилищ: " .. #self.storages)
    end
    
    self:setupHandlers()
    self:registerToServer()
    
    print("Инициализация завершена")
    return true
end

function EnergyStorageClient:findAllStorages()
    self.storages = {}
    
    for address, componentType in component.list("gt_") do
        local storage = self:analyzeGenericGTStorage(address, componentType)
        if storage ~= nil and self.storages[address] ~= nil then
            self.storages[address] = storage
        end
    end
end

function EnergyStorageClient:analyzeGenericGTStorage(address, componentType)
    local component_proxy = component.proxy(address)
    
    local stored, capacity
    
    if component_proxy.getStoredEU then
        stored = component_proxy.getStoredEU()
    elseif component_proxy.getEnergyStored then
        stored = component_proxy.getEnergyStored()
    elseif component_proxy.getStored then
        stored = component_proxy.getStored()
    end
    
    if component_proxy.getEUCapacity then
        capacity = component_proxy.getEUCapacity()
    elseif component_proxy.getMaxEnergyStored then
        capacity = component_proxy.getMaxEnergyStored()
    elseif component_proxy.getCapacity then
        capacity = component_proxy.getCapacity()
    end
    
    if stored and capacity and capacity > 0 then
        return {
            id = address:sub(1, 8),
            address = address,
            type = componentType,
            stored = stored,
            capacity = capacity,
            fillPercent = stored / capacity,
            inputRate = 0,
            outputRate = 0,
            location = string.format("%s %s", componentType, address:sub(1, 8))
        }
    end
    
    return nil
end

function EnergyStorageClient:setupHandlers()
    self.protocol:registerHandler(common_config.MESSAGES.ACK, function(data, from)
        if data.originalType == common_config.MESSAGES.REGISTER then
            self.serverAddress = from
            self:log("INFO", "Зарегистрирован на сервере: " .. from:sub(1, 8))
        end
    end)
    
    self.protocol:registerHandler(common_config.MESSAGES.COMMAND, function(data, from)
        if data.command == common_config.COMMANDS.DISCOVER then
            self:registerToServer()
        elseif data.command == common_config.COMMANDS.REFRESH_STORAGES then
            self:findAllStorages()
        end
    end)
end

local function formatEnergyStorageData(storage)
    return {
        id = storage.id,
        type = storage.type,
        stored = storage.stored,
        capacity = storage.capacity,
        fillPercent = storage.fillPercent,
        inputRate = storage.inputRate,
        outputRate = storage.outputRate,
        location = storage.location
    }
end

function EnergyStorageClient:registerToServer()
    self:log("INFO", "Поиск сервера...")
    
    local storagesData = self:updateStorages()

    local formattedStorages = {}
    for _, storage in ipairs(storagesData) do
        table.insert(formattedStorages, formatEnergyStorageData(storage))
    end

    self.protocol:send("broadcast", common_config.MESSAGES.REGISTER, {
        name = self.clientName,
        type = common_config.NETWORK.CLIENT_TYPES.ENERGY_STORAGE_CLIENT,
        storages = formattedStorages
    })
    
    local timeout = computer.uptime() + common_config.NETWORK.TIMEOUT
    while computer.uptime() < timeout and not self.serverAddress do
        os.sleep(0.5)
    end
    
    if not self.serverAddress then
        self:log("WARNING", "Сервер не найден, работа в автономном режиме")
    end
end

function EnergyStorageClient:updateStorages()
    local updatedStorages = {}
    
    for address, oldData in pairs(self.storages) do
        local newData = nil

        newData = self:analyzeGenericGTStorage(address, oldData.type)
        
        if newData then
            table.insert(updatedStorages, newData)
            self.storages[address] = newData
        else
            self:log("WARNING", "Потеряна связь с хранилищем: " .. oldData.location)
            self.storages[address] = nil
        end
    end
    
    return updatedStorages
end

function EnergyStorageClient:sendStorageUpdate()
    if not self.serverAddress then
        return
    end
    
    local storagesData = self:updateStorages()
    
    local formattedData = {}
    for _, storage in ipairs(storagesData) do
        table.insert(formattedData, formatEnergyStorageData(storage))
    end
    
    self.protocol:send(self.serverAddress, common_config.MESSAGES.ENERGY_STORAGE_UPDATE, {
        clientName = self.clientName,
        storages = formattedData,
        timestamp = os.time()
    })
    
    self.lastUpdate = computer.uptime()
end

function EnergyStorageClient:log(level, message)
    local timestamp = os.date("%H:%M:%S")
    print(string.format("[%s][%s] %s", timestamp, level, message))
    
    if self.serverAddress then
        local logData = self.protocol:formatLogMessage(level, message, self.clientName)
        self.protocol:send(self.serverAddress, common_config.MESSAGES.LOG, logData)
    end
end

function EnergyStorageClient:run()
    if not self:init() then
        return
    end
    
    self.running = true
    
    self.messageThread = thread.create(function()
        while self.running do
            self.protocol:processMessages(0.1)
        end
    end)
    
    self.mainThread = thread.create(function()
        while self.running do
            local success, err = pcall(function()
                if computer.uptime() - self.lastUpdate >= config.ENERGY_STORAGE.UPDATE_INTERVAL then
                    self:sendStorageUpdate()
                    
                    local filledCount = 0
                    for _, storage in pairs(self.storages) do
                        if storage.fillPercent >= config.ENERGY_STORAGE.FULL_THRESHOLD then
                            filledCount = filledCount + 1
                        end
                    end
                    
                    if filledCount > 0 then
                        self:log("INFO", string.format("%d хранилищ заполнены на %d%% и выше", 
                            filledCount, config.ENERGY_STORAGE.FULL_THRESHOLD * 100))
                    end
                end
            end)
            
            if not success then
                self:log("ERROR", "Ошибка в основном цикле: " .. tostring(err))
            end
            
            os.sleep(0.5)
        end
    end)
    
    while self.running do
        os.sleep(0.5)
    end
    
    if self.serverAddress then
        self.protocol:send(self.serverAddress, common_config.MESSAGES.UNREGISTER, {
            name = self.clientName
        })
    end
    
    if self.messageThread then
        self.messageThread:kill()
    end
    if self.mainThread then
        self.mainThread:kill()
    end
    
    self.protocol:close()
end

function EnergyStorageClient:stop()
    self.running = false
end

local args = {...}
local clientName = args[1] or nil

local client = EnergyStorageClient:new(clientName)

local function interruptEvent()
    print("\nОстановка клиента энергохранилищ...")
    client:stop()
end

event.listen("interrupted", interruptEvent)

client:run() 

event.ignore("interrupted", interruptEvent)
