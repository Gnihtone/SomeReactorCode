-- Менеджер клиента для вакуумных реакторов
local component = require("component")
local event = require("event")
local thread = require("thread")
local computer = require("computer")

local config = dofile("../vacuum_config.lua")
local Protocol = dofile("../vacuum_protocol.lua")
local VacuumReactor = dofile("vacuum_reactor.lua")

-- Класс менеджера клиента
local VacuumClientManager = {}
VacuumClientManager.__index = VacuumClientManager

function VacuumClientManager:new(clientName)
    local self = setmetatable({}, VacuumClientManager)
    
    -- Основные параметры
    self.clientName = clientName or "Client-" .. computer.address():sub(1, 8)
    self.running = false
    self.serverAddress = nil
    self.lastHeartbeat = 0
    
    -- Компоненты
    self.protocol = nil
    self.reactors = {}  -- Таблица реакторов: reactorId -> VacuumReactor
    self.reactorAddresses = {}  -- Адреса reactor_chamber компонентов
    
    -- Потоки
    self.messageThread = nil
    self.mainThread = nil
    
    return self
end

-- Инициализация менеджера
function VacuumClientManager:init()
    print("Инициализация клиента: " .. self.clientName)
    
    -- Инициализация протокола
    self.protocol = Protocol:new(false)
    
    -- Поиск всех реакторов
    self:findAllReactors()
    
    if #self.reactorAddresses == 0 then
        error("Не найдено ни одного реактора!")
    end
    
    print("Найдено реакторов: " .. #self.reactorAddresses)
    
    -- Инициализация каждого реактора
    for i, reactorAddress in ipairs(self.reactorAddresses) do
        local reactorId = self.clientName .. "-R" .. i
        local reactor = VacuumReactor:new(reactorId)
        
        -- Переопределяем компоненты для конкретного реактора
        reactor.reactor = component.proxy(reactorAddress)
        
        -- Находим ближайший transposer к реактору
        local transposerAddress = self:findNearestTransposer(reactorAddress)
        if transposerAddress then
            reactor.transposer = component.proxy(transposerAddress)
            
            -- Инициализируем ME Interface
            local MEInterface = require("me_interface")
            reactor.meInterface = MEInterface:new(transposerAddress)
            
            self.reactors[reactorId] = reactor
            print("Инициализирован реактор: " .. reactorId)
        else
            print("ВНИМАНИЕ: Не найден transposer для реактора " .. reactorId)
        end
    end
    
    -- Настройка обработчиков сообщений
    self:setupHandlers()
    
    -- Регистрация на сервере
    self:registerToServer()
    
    print("Инициализация завершена")
    return true
end

-- Поиск всех реакторов в системе
function VacuumClientManager:findAllReactors()
    self.reactorAddresses = {}
    
    for address, componentType in component.list("reactor_chamber") do
        table.insert(self.reactorAddresses, address)
    end
end

-- Поиск ближайшего transposer к реактору
function VacuumClientManager:findNearestTransposer(reactorAddress)
    -- В простейшем случае берем первый найденный transposer
    -- В реальной системе может потребоваться более сложная логика
    for address, componentType in component.list("transposer") do
        -- Проверяем, есть ли reactor_chamber среди соседних блоков
        local transposer = component.proxy(address)
        for side = 0, 5 do
            local inventoryName = transposer.getInventoryName(side)
            if inventoryName and inventoryName:find("reactor") then
                return address
            end
        end
    end
    
    -- Если не нашли по соседству, возвращаем первый доступный
    local firstTransposer = component.list("transposer")()
    return firstTransposer
end

-- Настройка обработчиков сообщений
function VacuumClientManager:setupHandlers()
    -- Подтверждение регистрации
    self.protocol:registerHandler(config.MESSAGES.ACK, function(data, from)
        if data.originalType == config.MESSAGES.REGISTER then
            self.serverAddress = from
            self:log("INFO", "Зарегистрирован на сервере: " .. from:sub(1, 8))
        end
    end)
    
    -- Обработка команд от сервера
    self.protocol:registerHandler(config.MESSAGES.COMMAND, function(data, from)
        self:handleServerCommand(data.command, data.parameters, data.reactorId)
    end)
    
    -- Обновление конфигурации
    self.protocol:registerHandler(config.MESSAGES.CONFIG_UPDATE, function(data, from)
        self:log("INFO", "Получено обновление конфигурации")
    end)
end

-- Регистрация на сервере
function VacuumClientManager:registerToServer()
    self:log("INFO", "Поиск сервера...")
    
    -- Подготовка списка реакторов
    local reactorList = {}
    for reactorId, reactor in pairs(self.reactors) do
        table.insert(reactorList, {
            id = reactorId,
            name = reactor.name
        })
    end
    
    -- Отправка широковещательного сообщения о регистрации
    self.protocol:send("broadcast", config.MESSAGES.REGISTER, {
        name = self.clientName,
        type = "multi_reactor_client",
        reactors = reactorList,
        capabilities = {
            emergency_cooling = true,
            remote_control = true,
            auto_maintenance = true,
            multi_reactor = true
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

-- Обработка команд от сервера
function VacuumClientManager:handleServerCommand(command, parameters, reactorId)
    -- Если указан конкретный реактор
    if reactorId and self.reactors[reactorId] then
        local reactor = self.reactors[reactorId]
        
        if command == config.COMMANDS.START then
            reactor:startReactor()
        elseif command == config.COMMANDS.STOP then
            reactor:stopReactor()
        elseif command == config.COMMANDS.EMERGENCY_STOP then
            reactor:emergencyStop()
        elseif command == config.COMMANDS.CLEAR_EMERGENCY then
            reactor:clearEmergency()
        elseif command == config.COMMANDS.PAUSE_FOR_ENERGY_FULL then
            reactor:pauseForEnergyFull()
        elseif command == config.COMMANDS.RESUME_FROM_ENERGY_PAUSE then
            reactor:resumeFromEnergyPause()
        elseif command == "FORCE_MAINTENANCE" then
            reactor:performMaintenance()
        end
    elseif not reactorId then
        -- Команда для всех реакторов
        for id, reactor in pairs(self.reactors) do
            self:handleServerCommand(command, parameters, id)
        end
    end
    
    -- Общие команды
    if command == "DISCOVER" then
        self:registerToServer()
    end
end

-- Отправка данных на сервер
function VacuumClientManager:sendStatusUpdate()
    if not self.serverAddress then
        return
    end
    
    -- Собираем данные всех реакторов
    local reactorsData = {}
    for reactorId, reactor in pairs(self.reactors) do
        local reactorData = reactor:getStatusData()
        reactorData.reactorId = reactorId  -- Добавляем ID реактора
        table.insert(reactorsData, self.protocol:formatReactorData(reactorData))
    end
    
    self.protocol:send(self.serverAddress, config.MESSAGES.STATUS_UPDATE, {
        clientName = self.clientName,
        reactors = reactorsData
    })
    
    self.lastHeartbeat = computer.uptime()
end

-- Отправка лога на сервер
function VacuumClientManager:sendLog(level, message, reactorId)
    if self.serverAddress then
        local logData = self.protocol:formatLogMessage(level, message, reactorId or self.clientName)
        self.protocol:send(self.serverAddress, config.MESSAGES.LOG, logData)
    end
end

-- Отправка аварийного уведомления
function VacuumClientManager:sendEmergencyAlert(reactorId, reason, data)
    if self.serverAddress then
        self.protocol:send(self.serverAddress, config.MESSAGES.EMERGENCY, {
            reactorId = reactorId,
            clientName = self.clientName,
            reason = reason,
            temperature = data.temperature,
            tempPercent = data.tempPercent,
            additionalData = data
        })
    end
end

-- Логирование
function VacuumClientManager:log(level, message, reactorId)
    local timestamp = os.date("%H:%M:%S")
    local prefix = reactorId and string.format("[%s][%s][%s]", timestamp, level, reactorId) or string.format("[%s][%s]", timestamp, level)
    print(prefix .. " " .. message)
    
    -- Отправка на сервер
    self:sendLog(level, message, reactorId)
end

-- Основной цикл работы
function VacuumClientManager:run()
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
    
    -- Основной поток управления реакторами
    self.mainThread = thread.create(function()
        while self.running do
            local success, err = pcall(function()
                -- Обновление состояния каждого реактора
                for reactorId, reactor in pairs(self.reactors) do
                    reactor:update()
                    
                    -- Проверка на аварийные ситуации
                    local status = reactor:getStatusData()
                    if status.emergencyTriggered then
                        self:sendEmergencyAlert(reactorId, status.emergencyReason, status)
                    end
                    
                    -- Сбор логов от реактора
                    local logs = reactor:getAndClearLogs()
                    for _, logEntry in ipairs(logs) do
                        self:log(logEntry.level, logEntry.message, reactorId)
                    end
                end
                
                -- Отправка данных на сервер
                if computer.uptime() - self.lastHeartbeat >= config.NETWORK.HEARTBEAT_INTERVAL then
                    self:sendStatusUpdate()
                end
            end)
            
            if not success then
                self:log("ERROR", "Ошибка в основном цикле: " .. tostring(err))
            end
            
            -- Пауза
            os.sleep(config.REACTOR.UPDATE_INTERVAL)
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
    
    -- Закрытие протокола и остановка реакторов
    self.protocol:close()
    for _, reactor in pairs(self.reactors) do
        reactor:stopReactor()
    end
end

-- Остановка менеджера
function VacuumClientManager:stop()
    self.running = false
end

-- Точка входа
local args = {...}
local clientName = args[1] or nil

local manager = VacuumClientManager:new(clientName)

-- Обработка сигнала прерывания
event.listen("interrupted", function()
    print("\nОстановка клиента...")
    manager:stop()
end)

-- Запуск менеджера
manager:run() 