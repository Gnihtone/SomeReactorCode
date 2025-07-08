-- Главный сервер управления вакуумными реакторами
local component = require("component")
local event = require("event")
local thread = require("thread")
local keyboard = require("keyboard")
local computer = require("computer")
local config = require("../vacuum_config")
local Protocol = require("../vacuum_protocol")
local VacuumUI = require("vacuum_ui")

-- Класс сервера
local VacuumServer = {}
VacuumServer.__index = VacuumServer

function VacuumServer:new()
    local self = setmetatable({}, VacuumServer)
    
    -- Основные параметры
    self.running = false
    self.protocol = nil
    self.ui = nil
    
    -- Подключенные клиенты (реакторы)
    self.clients = {}  -- address -> client data
    self.reactorList = {}  -- упорядоченный список для отображения
    
    -- Потоки
    self.messageThread = nil
    self.uiThread = nil
    
    return self
end

-- Инициализация сервера
function VacuumServer:init()
    print("Инициализация сервера вакуумных реакторов...")
    
    -- Инициализация протокола
    self.protocol = Protocol:new(true)
    
    -- Инициализация интерфейса
    self.ui = VacuumUI:new()
    self.ui:init()
    
    -- Регистрация обработчиков сообщений
    self:setupHandlers()
    
    -- Обнаружение существующих клиентов
    self:discoverClients()
    
    self:log("INFO", "Сервер запущен")
    
    return true
end

-- Настройка обработчиков сообщений
function VacuumServer:setupHandlers()
    -- Регистрация нового клиента
    self.protocol:registerHandler(config.MESSAGES.REGISTER, function(data, from)
        self:handleClientRegister(data, from)
    end)
    
    -- Отключение клиента
    self.protocol:registerHandler(config.MESSAGES.UNREGISTER, function(data, from)
        self:handleClientUnregister(data, from)
    end)
    
    -- Обновление статуса реактора
    self.protocol:registerHandler(config.MESSAGES.STATUS_UPDATE, function(data, from)
        self:handleStatusUpdate(data, from)
    end)
    
    -- Аварийная ситуация
    self.protocol:registerHandler(config.MESSAGES.EMERGENCY, function(data, from)
        self:handleEmergency(data, from)
    end)
    
    -- Лог от клиента
    self.protocol:registerHandler(config.MESSAGES.LOG, function(data, from)
        self:handleClientLog(data, from)
    end)
end

-- Обработка регистрации клиента
function VacuumServer:handleClientRegister(data, address)
    self:log("INFO", "Регистрация клиента: " .. data.name .. " [" .. address:sub(1, 8) .. "]")
    
    -- Сохранение данных клиента
    self.clients[address] = {
        address = address,
        name = data.name,
        type = data.type,
        capabilities = data.capabilities or {},
        lastSeen = computer.uptime(),
        reactorData = {
            name = data.name,
            status = "OFFLINE",
            temperature = 0,
            tempPercent = 0,
            euOutput = 0,
            efficiency = 0,
            running = false,
            emergencyMode = false,
            emergencyCooldown = 0,
            maintenanceMode = false,
            totalEU = 0
        }
    }
    
    -- Отправка подтверждения
    self.protocol:sendAck(address, config.MESSAGES.REGISTER)
    
    -- Обновление списка реакторов
    self:updateReactorList()
end

-- Обработка отключения клиента
function VacuumServer:handleClientUnregister(data, address)
    if self.clients[address] then
        self:log("INFO", "Отключение клиента: " .. self.clients[address].name)
        
        -- Установка статуса оффлайн
        if self.clients[address].reactorData then
            self.clients[address].reactorData.status = "OFFLINE"
        end
        
        -- Обновление интерфейса
        self:updateReactorList()
    end
end

-- Обработка обновления статуса
function VacuumServer:handleStatusUpdate(data, address)
    if self.clients[address] then
        -- Обновление времени последнего контакта
        self.clients[address].lastSeen = computer.uptime()
        
        -- Обновление данных реактора
        self.clients[address].reactorData = data
        
        -- Обновление интерфейса
        self:updateReactorList()
    end
end

-- Обработка аварийной ситуации
function VacuumServer:handleEmergency(data, address)
    if self.clients[address] then
        local clientName = self.clients[address].name
        self:log("CRITICAL", "АВАРИЙНАЯ СИТУАЦИЯ на " .. clientName .. ": " .. data.reason)
        
        -- Дополнительное логирование деталей
        if data.temperature then
            self:log("CRITICAL", string.format("Температура: %d°C (%.1f%%)", 
                data.temperature, data.tempPercent * 100))
        end
    end
end

-- Обработка лога от клиента
function VacuumServer:handleClientLog(data, address)
    if self.clients[address] then
        -- Добавление лога в интерфейс
        self.ui:addLog(data.timestamp or os.time(), data.level, data.message, data.reactorName)
    end
end

-- Обнаружение клиентов
function VacuumServer:discoverClients()
    self:log("INFO", "Поиск активных реакторов...")
    self.protocol:discoverClients()
end

-- Обновление списка реакторов для отображения
function VacuumServer:updateReactorList()
    self.reactorList = {}
    
    for address, client in pairs(self.clients) do
        table.insert(self.reactorList, client.reactorData)
    end
    
    -- Сортировка по имени
    table.sort(self.reactorList, function(a, b)
        return a.name < b.name
    end)
    
    -- Обновление интерфейса
    self.ui:updateReactors(self.reactorList)
end

-- Проверка таймаутов подключений
function VacuumServer:checkConnectionTimeouts()
    local currentTime = computer.uptime()
    local hasChanges = false
    
    for address, client in pairs(self.clients) do
        local timeSinceLastSeen = currentTime - client.lastSeen
        
        if timeSinceLastSeen > config.NETWORK.CONNECTION_TIMEOUT then
            if client.reactorData.status ~= "OFFLINE" then
                client.reactorData.status = "OFFLINE"
                hasChanges = true
                self:log("WARNING", "Потеряна связь с " .. client.name)
            end
        end
    end
    
    if hasChanges then
        self:updateReactorList()
    end
end

-- Отправка команды реактору
function VacuumServer:sendReactorCommand(reactorName, command)
    -- Поиск адреса реактора по имени
    local targetAddress = nil
    
    for address, client in pairs(self.clients) do
        if client.name == reactorName then
            targetAddress = address
            break
        end
    end
    
    if targetAddress then
        self.protocol:sendCommand(targetAddress, command)
        self:log("INFO", "Команда " .. command .. " отправлена на " .. reactorName)
        return true
    else
        self:log("ERROR", "Реактор " .. reactorName .. " не найден")
        return false
    end
end

-- Обработка команд пользователя
function VacuumServer:handleUserInput(key, code)
    if key == keyboard.keys.up then
        self.ui:scrollUp()
    elseif key == keyboard.keys.down then
        self.ui:scrollDown()
    elseif key == keyboard.keys.enter then
        -- Выбор текущего реактора
        local reactor = self.ui:getSelectedReactor()
        if reactor then
            self.ui:selectReactor(self.ui.selectedReactor)
        end
    elseif key == keyboard.keys.s then
        -- Запуск выбранного реактора
        local reactor = self.ui:getSelectedReactor()
        if reactor then
            self:sendReactorCommand(reactor.name, config.COMMANDS.START)
        end
    elseif key == keyboard.keys.t then
        -- Остановка выбранного реактора
        local reactor = self.ui:getSelectedReactor()
        if reactor then
            self:sendReactorCommand(reactor.name, config.COMMANDS.STOP)
        end
    elseif key == keyboard.keys.e then
        -- Сброс аварийного режима
        local reactor = self.ui:getSelectedReactor()
        if reactor and reactor.emergencyMode then
            self:sendReactorCommand(reactor.name, config.COMMANDS.CLEAR_EMERGENCY)
        end
    elseif key == keyboard.keys.m then
        -- Принудительное обслуживание
        local reactor = self.ui:getSelectedReactor()
        if reactor then
            self:sendReactorCommand(reactor.name, "FORCE_MAINTENANCE")
        end
    elseif key == keyboard.keys.r then
        -- Обновление (повторное обнаружение клиентов)
        self:discoverClients()
    elseif key == keyboard.keys.q then
        -- Выход
        self.running = false
    elseif key >= keyboard.keys["1"] and key <= keyboard.keys["9"] then
        -- Быстрый выбор реактора по номеру
        local index = key - keyboard.keys["1"] + 1
        self.ui:selectReactor(index)
    end
end

-- Логирование
function VacuumServer:log(level, message)
    -- Добавление в UI
    self.ui:addLog(os.time(), level, message, nil)
    
    -- Вывод в консоль для отладки
    print(string.format("[%s][%s] %s", os.date("%H:%M:%S"), level, message))
end

-- Основной цикл работы
function VacuumServer:run()
    if not self:init() then
        return
    end
    
    self.running = true
    
    -- Поток обработки сообщений
    self.messageThread = thread.create(function()
        while self.running do
            self.protocol:processMessages(0.1)
        end
    end)
    
    -- Поток обновления интерфейса
    self.uiThread = thread.create(function()
        while self.running do
            -- Проверка таймаутов подключений
            self:checkConnectionTimeouts()
            
            -- Небольшая задержка
            os.sleep(config.UI.UPDATE_INTERVAL)
        end
    end)
    
    -- Основной цикл обработки ввода
    while self.running do
        local eventData = {event.pull(0.1)}
        
        if eventData[1] == "key_down" then
            local _, _, _, code = table.unpack(eventData)
            self:handleUserInput(code, code)
        elseif eventData[1] == "interrupted" then
            self.running = false
        end
    end
    
    -- Завершение работы
    self:log("INFO", "Остановка сервера...")
    
    -- Остановка потоков
    if self.messageThread then
        self.messageThread:kill()
    end
    if self.uiThread then
        self.uiThread:kill()
    end
    
    -- Закрытие протокола
    self.protocol:close()
    
    -- Очистка интерфейса
    self.ui:cleanup()
end

-- Точка входа
local server = VacuumServer:new()

-- Обработка прерывания
event.listen("interrupted", function()
    print("\nОстановка сервера...")
    server.running = false
end)

-- Запуск сервера
server:run() 