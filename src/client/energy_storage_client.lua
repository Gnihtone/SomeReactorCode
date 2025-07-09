-- Клиент мониторинга энергохранилищ
package.path = package.path .. ";../?.lua"

local component = require("component")
local event = require("event")
local thread = require("thread")
local computer = require("computer")
local config = require("vacuum_config")
local Protocol = require("vacuum_protocol")

-- Класс клиента энергохранилищ
local EnergyStorageClient = {}
EnergyStorageClient.__index = EnergyStorageClient

function EnergyStorageClient:new(clientName)
    local self = setmetatable({}, EnergyStorageClient)
    
    -- Основные параметры
    self.clientName = clientName or "EnergyStorage-" .. computer.address():sub(1, 8)
    self.running = false
    self.serverAddress = nil
    self.lastUpdate = 0
    
    -- Компоненты
    self.protocol = nil
    self.storages = {}  -- Таблица энергохранилищ: address -> storage data
    
    -- Потоки
    self.messageThread = nil
    self.mainThread = nil
    
    return self
end

-- Инициализация клиента
function EnergyStorageClient:init()
    print("Инициализация клиента энергохранилищ: " .. self.clientName)
    
    -- Инициализация протокола
    self.protocol = Protocol:new(false)
    
    -- Поиск всех энергохранилищ
    self:findAllStorages()
    
    if #self.storages == 0 then
        print("ВНИМАНИЕ: Не найдено ни одного поддерживаемого энергохранилища!")
    else
        print("Найдено энергохранилищ: " .. #self.storages)
    end
    
    -- Настройка обработчиков сообщений
    self:setupHandlers()
    
    -- Регистрация на сервере
    self:registerToServer()
    
    print("Инициализация завершена")
    return true
end

-- Поиск всех энергохранилищ в системе
function EnergyStorageClient:findAllStorages()
    self.storages = {}
    
    -- Поиск GT батарейных буферов
    for address, componentType in component.list("gt_batterybuffer") do
        local storage = self:analyzeGTBatteryBuffer(address)
        if storage then
            table.insert(self.storages, storage)
        end
    end
    
    -- Поиск GT машин с энергохранилищем
    for address, componentType in component.list("gt_machine") do
        local storage = self:analyzeGTMachine(address)
        if storage then
            table.insert(self.storages, storage)
        end
    end
    
    -- Поиск других GT хранилищ
    for address, componentType in component.list() do
        if componentType:find("gregtech") or componentType:find("gt_") then
            local storage = self:analyzeGenericGTStorage(address, componentType)
            if storage and not self.storages[address] then
                table.insert(self.storages, storage)
            end
        end
    end
end

-- Анализ GT батарейного буфера
function EnergyStorageClient:analyzeGTBatteryBuffer(address)
    local component_proxy = component.proxy(address)
    
    -- Проверяем наличие необходимых методов
    if not component_proxy.getStoredEU or not component_proxy.getEUCapacity then
        return nil
    end
    
    local stored = component_proxy.getStoredEU()
    local capacity = component_proxy.getEUCapacity()
    
    if capacity and capacity > 0 then
        return {
            id = address:sub(1, 8),
            address = address,
            type = "gt_batterybuffer",
            stored = stored or 0,
            capacity = capacity,
            fillPercent = stored / capacity,
            inputRate = component_proxy.getInputVoltage and component_proxy.getInputVoltage() or 0,
            outputRate = component_proxy.getOutputVoltage and component_proxy.getOutputVoltage() or 0,
            location = string.format("Battery Buffer %s", address:sub(1, 8))
        }
    end
    
    return nil
end

-- Анализ GT машины
function EnergyStorageClient:analyzeGTMachine(address)
    local component_proxy = component.proxy(address)
    
    -- Проверяем наличие методов для работы с энергией
    if not component_proxy.getStoredEU or not component_proxy.getEUCapacity then
        return nil
    end
    
    local stored = component_proxy.getStoredEU()
    local capacity = component_proxy.getEUCapacity()
    
    -- Игнорируем машины с малой ёмкостью (обычные машины, а не хранилища)
    if capacity and capacity > 10000 then  -- Минимум 10k EU для считывания как хранилище
        return {
            id = address:sub(1, 8),
            address = address,
            type = "gt_machine",
            stored = stored or 0,
            capacity = capacity,
            fillPercent = stored / capacity,
            inputRate = component_proxy.getAverageElectricInput and component_proxy.getAverageElectricInput() or 0,
            outputRate = component_proxy.getAverageElectricOutput and component_proxy.getAverageElectricOutput() or 0,
            location = string.format("GT Machine %s", address:sub(1, 8))
        }
    end
    
    return nil
end

-- Анализ общего GT хранилища
function EnergyStorageClient:analyzeGenericGTStorage(address, componentType)
    local component_proxy = component.proxy(address)
    
    -- Пытаемся найти методы для работы с энергией
    local stored, capacity
    
    -- Различные варианты методов в GT
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

-- Настройка обработчиков сообщений
function EnergyStorageClient:setupHandlers()
    -- Подтверждение регистрации
    self.protocol:registerHandler(config.MESSAGES.ACK, function(data, from)
        if data.originalType == config.MESSAGES.REGISTER then
            self.serverAddress = from
            self:log("INFO", "Зарегистрирован на сервере: " .. from:sub(1, 8))
        end
    end)
    
    -- Обработка команд от сервера
    self.protocol:registerHandler(config.MESSAGES.COMMAND, function(data, from)
        if data.command == "DISCOVER" then
            self:registerToServer()
        elseif data.command == "REFRESH_STORAGES" then
            self:findAllStorages()
        end
    end)
end

-- Регистрация на сервере
function EnergyStorageClient:registerToServer()
    self:log("INFO", "Поиск сервера...")
    
    -- Отправка широковещательного сообщения о регистрации
    self.protocol:send("broadcast", config.MESSAGES.REGISTER, {
        name = self.clientName,
        type = "energy_storage_monitor",
        capabilities = {
            gregtech_support = true,
            auto_scan = true
        }
    })
    
    -- Ожидание ответа
    local timeout = computer.uptime() + config.NETWORK.TIMEOUT
    while computer.uptime() < timeout and not self.serverAddress do
        self.protocol:processMessages(0.1)
    end
    
    if not self.serverAddress then
        self:log("WARNING", "Сервер не найден, работа в автономном режиме")
    end
end

-- Обновление состояния хранилищ
function EnergyStorageClient:updateStorages()
    local updatedStorages = {}
    
    for address, oldData in pairs(self.storages) do
        local newData = nil
        
        -- Обновляем данные в зависимости от типа
        if oldData.type == "gt_batterybuffer" then
            newData = self:analyzeGTBatteryBuffer(address)
        elseif oldData.type == "gt_machine" then
            newData = self:analyzeGTMachine(address)
        else
            newData = self:analyzeGenericGTStorage(address, oldData.type)
        end
        
        if newData then
            table.insert(updatedStorages, newData)
            self.storages[address] = newData
        else
            -- Хранилище больше не доступно
            self:log("WARNING", "Потеряна связь с хранилищем: " .. oldData.location)
            self.storages[address] = nil
        end
    end
    
    return updatedStorages
end

-- Отправка данных на сервер
function EnergyStorageClient:sendStorageUpdate()
    if not self.serverAddress then
        return
    end
    
    local storagesData = self:updateStorages()
    
    -- Форматируем данные
    local formattedData = {}
    for _, storage in ipairs(storagesData) do
        table.insert(formattedData, self.protocol:formatEnergyStorageData(storage))
    end
    
    self.protocol:send(self.serverAddress, config.MESSAGES.ENERGY_STORAGE_UPDATE, {
        clientName = self.clientName,
        storages = formattedData,
        timestamp = os.time()
    })
    
    self.lastUpdate = computer.uptime()
end

-- Логирование
function EnergyStorageClient:log(level, message)
    local timestamp = os.date("%H:%M:%S")
    print(string.format("[%s][%s] %s", timestamp, level, message))
    
    -- Отправка на сервер
    if self.serverAddress then
        local logData = self.protocol:formatLogMessage(level, message, self.clientName)
        self.protocol:send(self.serverAddress, config.MESSAGES.LOG, logData)
    end
end

-- Основной цикл работы
function EnergyStorageClient:run()
    if not self:init() then
        return
    end
    
    self.running = true
    
    -- Поток для обработки сообщений
    self.messageThread = thread.create(function()
        while self.running do
            self.protocol:processMessages(0.1)
        end
    end)
    
    -- Основной поток мониторинга
    self.mainThread = thread.create(function()
        while self.running do
            local success, err = pcall(function()
                -- Отправка данных на сервер
                if computer.uptime() - self.lastUpdate >= config.ENERGY_STORAGE.UPDATE_INTERVAL then
                    self:sendStorageUpdate()
                    
                    -- Выводим текущее состояние
                    local criticalCount = 0
                    for _, storage in pairs(self.storages) do
                        if storage.fillPercent >= config.ENERGY_STORAGE.FULL_THRESHOLD then
                            criticalCount = criticalCount + 1
                        end
                    end
                    
                    if criticalCount > 0 then
                        self:log("WARNING", string.format("%d хранилищ заполнены на %d%% и выше", 
                            criticalCount, config.ENERGY_STORAGE.FULL_THRESHOLD * 100))
                    end
                end
            end)
            
            if not success then
                self:log("ERROR", "Ошибка в основном цикле: " .. tostring(err))
            end
            
            -- Пауза
            os.sleep(0.5)
        end
    end)
    
    -- Ожидание завершения
    while self.running do
        os.sleep(0.5)
    end
    
    -- Отправка уведомления об отключении
    if self.serverAddress then
        self.protocol:send(self.serverAddress, config.MESSAGES.UNREGISTER, {
            name = self.clientName
        })
    end
    
    -- Завершение потоков
    if self.messageThread then
        self.messageThread:kill()
    end
    if self.mainThread then
        self.mainThread:kill()
    end
    
    -- Закрытие протокола
    self.protocol:close()
end

-- Остановка клиента
function EnergyStorageClient:stop()
    self.running = false
end

-- Точка входа
local args = {...}
local clientName = args[1] or nil

local client = EnergyStorageClient:new(clientName)

-- Обработка сигнала прерывания
event.listen("interrupted", function()
    print("\nОстановка клиента энергохранилищ...")
    client:stop()
end)

-- Запуск клиента
client:run() 