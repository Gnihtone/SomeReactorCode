-- Менеджер клиента для вакуумных реакторов
local component = require("component")
local event = require("event")
local thread = require("thread")
local computer = require("computer")
local config = require("../vacuum_config")
local Protocol = require("../vacuum_protocol")
local VacuumReactor = require("vacuum_reactor")

-- Класс менеджера клиента
local VacuumClientManager = {}
VacuumClientManager.__index = VacuumClientManager

function VacuumClientManager:new(reactorName)
    local self = setmetatable({}, VacuumClientManager)
    
    -- Основные параметры
    self.name = reactorName or "Reactor-" .. computer.address():sub(1, 8)
    self.running = false
    self.serverAddress = nil
    self.lastHeartbeat = 0
    
    -- Компоненты
    self.protocol = nil
    self.reactor = nil
    
    -- Потоки
    self.messageThread = nil
    self.mainThread = nil
    
    return self
end

-- Инициализация менеджера
function VacuumClientManager:init()
    print("Инициализация клиента реактора: " .. self.name)
    
    -- Инициализация протокола
    self.protocol = Protocol:new(false)
    
    -- Инициализация реактора
    self.reactor = VacuumReactor:new(self.name)
    if not self.reactor:init() then
        error("Не удалось инициализировать реактор!")
    end
    
    -- Настройка обработчиков сообщений
    self:setupHandlers()
    
    -- Регистрация на сервере
    self:registerToServer()
    
    print("Инициализация завершена")
    return true
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
        self:handleServerCommand(data.command, data.parameters)
    end)
    
    -- Обновление конфигурации
    self.protocol:registerHandler(config.MESSAGES.CONFIG_UPDATE, function(data, from)
        self:log("INFO", "Получено обновление конфигурации")
    end)
end

-- Регистрация на сервере
function VacuumClientManager:registerToServer()
    self:log("INFO", "Поиск сервера...")
    
    -- Отправка широковещательного сообщения о регистрации
    self.protocol:send("broadcast", config.MESSAGES.REGISTER, {
        name = self.name,
        type = "vacuum_reactor",
        capabilities = {
            emergency_cooling = true,
            remote_control = true,
            auto_maintenance = true
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
function VacuumClientManager:handleServerCommand(command, parameters)
    if command == config.COMMANDS.START then
        self.reactor:startReactor()
    elseif command == config.COMMANDS.STOP then
        self.reactor:stopReactor()
    elseif command == config.COMMANDS.EMERGENCY_STOP then
        self.reactor:emergencyStop()
    elseif command == config.COMMANDS.CLEAR_EMERGENCY then
        self.reactor:clearEmergency()
    elseif command == "DISCOVER" then
        -- Ответ на обнаружение
        self:registerToServer()
    elseif command == "FORCE_MAINTENANCE" then
        -- Принудительное обслуживание
        self.reactor:performMaintenance()
    end
end

-- Отправка данных на сервер
function VacuumClientManager:sendStatusUpdate()
    if not self.serverAddress then
        return
    end
    
    local reactorData = self.reactor:getStatusData()
    local data = self.protocol:formatReactorData(reactorData)
    self.protocol:send(self.serverAddress, config.MESSAGES.STATUS_UPDATE, data)
    self.lastHeartbeat = computer.uptime()
end

-- Отправка лога на сервер
function VacuumClientManager:sendLog(level, message)
    if self.serverAddress then
        local logData = self.protocol:formatLogMessage(level, message, self.name)
        self.protocol:send(self.serverAddress, config.MESSAGES.LOG, logData)
    end
end

-- Отправка аварийного уведомления
function VacuumClientManager:sendEmergencyAlert(reason, data)
    if self.serverAddress then
        self.protocol:send(self.serverAddress, config.MESSAGES.EMERGENCY, {
            reason = reason,
            temperature = data.temperature,
            tempPercent = data.tempPercent,
            additionalData = data
        })
    end
end

-- Логирование
function VacuumClientManager:log(level, message)
    local timestamp = os.date("%H:%M:%S")
    print(string.format("[%s][%s] %s", timestamp, level, message))
    
    -- Отправка на сервер
    self:sendLog(level, message)
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
    
    -- Основной поток управления реактором
    self.mainThread = thread.create(function()
        while self.running do
            local success, err = pcall(function()
                -- Обновление состояния реактора
                self.reactor:update()
                
                -- Проверка на аварийные ситуации
                local status = self.reactor:getStatusData()
                if status.emergencyTriggered then
                    self:sendEmergencyAlert(status.emergencyReason, status)
                end
                
                -- Отправка данных на сервер
                if computer.uptime() - self.lastHeartbeat >= config.NETWORK.HEARTBEAT_INTERVAL then
                    self:sendStatusUpdate()
                end
                
                -- Сбор логов от реактора
                local logs = self.reactor:getAndClearLogs()
                for _, logEntry in ipairs(logs) do
                    self:log(logEntry.level, logEntry.message)
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
            name = self.name
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

-- Остановка менеджера
function VacuumClientManager:stop()
    self.running = false
end

-- Точка входа
local args = {...}
local reactorName = args[1] or nil

local manager = VacuumClientManager:new(reactorName)

-- Обработка сигнала прерывания
event.listen("interrupted", function()
    print("\nОстановка клиента...")
    manager:stop()
end)

-- Запуск менеджера
manager:run() 