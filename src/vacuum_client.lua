-- Клиент для мониторинга вакуумных реакторов
local component = require("component")
local event = require("event")
local thread = require("thread")
local computer = require("computer")
local config = require("vacuum_config")
local Protocol = require("vacuum_protocol")
local MEInterface = require("me_interface")

-- Класс клиента реактора
local VacuumClient = {}
VacuumClient.__index = VacuumClient

function VacuumClient:new(reactorName)
    local self = setmetatable({}, VacuumClient)
    
    -- Основные параметры
    self.name = reactorName or "Reactor-" .. computer.address():sub(1, 8)
    self.running = false
    self.emergencyMode = false
    self.emergencyCooldown = 0
    self.serverAddress = nil
    self.lastHeartbeat = 0
    
    -- Компоненты
    self.reactor = nil
    self.transposer = nil
    self.meInterface = nil
    self.protocol = nil
    
    -- Состояние реактора
    self.reactorData = {
        name = self.name,
        status = "OFFLINE",
        temperature = 0,
        maxTemperature = 10000,
        tempPercent = 0,
        euOutput = 0,
        efficiency = 0,
        running = false,
        emergencyMode = false,
        emergencyCooldown = 0,
        lastError = nil,
        coolantStatus = {},
        fuelStatus = {},
        uptime = 0,
        totalEU = 0
    }
    
    -- Сохраненная схема реактора (до аварийного режима)
    self.savedLayout = {}
    self.startTime = computer.uptime()
    
    return self
end

-- Инициализация компонентов
function VacuumClient:init()
    print("Инициализация клиента реактора: " .. self.name)
    
    -- Поиск реактора
    if not component.isAvailable("reactor") then
        error("Реактор не найден!")
    end
    self.reactor = component.reactor
    
    -- Поиск transposer
    if not component.isAvailable("transposer") then
        error("Transposer не найден!")
    end
    self.transposer = component.transposer
    
    -- Инициализация ME Interface
    local transposerAddress = component.transposer.address
    self.meInterface = MEInterface:new(transposerAddress)
    
    -- Инициализация протокола
    self.protocol = Protocol:new(false)
    
    -- Регистрация обработчиков
    self:setupHandlers()
    
    -- Регистрация на сервере
    self:registerToServer()
    
    print("Инициализация завершена")
    return true
end

-- Настройка обработчиков сообщений
function VacuumClient:setupHandlers()
    -- Подтверждение регистрации
    self.protocol:registerHandler(config.MESSAGES.ACK, function(data, from)
        if data.originalType == config.MESSAGES.REGISTER then
            self.serverAddress = from
            self:log("INFO", "Зарегистрирован на сервере: " .. from)
        end
    end)
    
    -- Обработка команд
    self.protocol:registerHandler(config.MESSAGES.COMMAND, function(data, from)
        self:handleCommand(data.command, data.parameters)
    end)
    
    -- Обновление конфигурации
    self.protocol:registerHandler(config.MESSAGES.CONFIG_UPDATE, function(data, from)
        -- Здесь можно обновлять локальную конфигурацию
        self:log("INFO", "Получено обновление конфигурации")
    end)
end

-- Регистрация на сервере
function VacuumClient:registerToServer()
    self:log("INFO", "Поиск сервера...")
    
    -- Отправка широковещательного сообщения о регистрации
    self.protocol:send("broadcast", config.MESSAGES.REGISTER, {
        name = self.name,
        type = "vacuum_reactor",
        capabilities = {
            emergency_cooling = true,
            remote_control = true
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
function VacuumClient:handleCommand(command, parameters)
    if command == config.COMMANDS.START then
        self:startReactor()
    elseif command == config.COMMANDS.STOP then
        self:stopReactor()
    elseif command == config.COMMANDS.EMERGENCY_STOP then
        self:emergencyStop()
    elseif command == config.COMMANDS.CLEAR_EMERGENCY then
        self:clearEmergency()
    elseif command == "DISCOVER" then
        -- Ответ на обнаружение
        self:registerToServer()
    end
end

-- Запуск реактора
function VacuumClient:startReactor()
    if self.emergencyMode then
        self:log("ERROR", "Невозможно запустить реактор в аварийном режиме")
        return false
    end
    
    self.reactor.setActive(true)
    self.reactorData.running = true
    self:log("INFO", "Реактор запущен")
    return true
end

-- Остановка реактора
function VacuumClient:stopReactor()
    self.reactor.setActive(false)
    self.reactorData.running = false
    self:log("INFO", "Реактор остановлен")
    return true
end

-- Аварийная остановка с охлаждением
function VacuumClient:emergencyStop()
    self:log("CRITICAL", "АВАРИЙНАЯ ОСТАНОВКА!")
    
    -- Немедленная остановка реактора
    self:stopReactor()
    
    -- Сохранение текущей схемы
    self:saveCurrentLayout()
    
    -- Переход в аварийный режим
    self.emergencyMode = true
    self.emergencyCooldown = config.REACTOR.EMERGENCY_COOLDOWN_TIME
    self.reactorData.emergencyMode = true
    
    -- Очистка реактора и установка охлаждающих элементов
    self:installEmergencyCooling()
    
    -- Отправка уведомления на сервер
    if self.serverAddress then
        self.protocol:send(self.serverAddress, config.MESSAGES.EMERGENCY, {
            reason = "Критическая температура",
            temperature = self.reactorData.temperature,
            tempPercent = self.reactorData.tempPercent
        })
    end
end

-- Сохранение текущей схемы реактора
function VacuumClient:saveCurrentLayout()
    self.savedLayout = {}
    local inventorySize = self.transposer.getInventorySize(config.SIDES.REACTOR)
    
    for slot = 1, inventorySize do
        local stack = self.transposer.getStackInSlot(config.SIDES.REACTOR, slot)
        if stack then
            self.savedLayout[slot] = {
                name = stack.name,
                damage = stack.damage,
                size = stack.size,
                label = stack.label
            }
        end
    end
    
    self:log("INFO", "Схема реактора сохранена: " .. #self.savedLayout .. " предметов")
end

-- Установка аварийного охлаждения
function VacuumClient:installEmergencyCooling()
    self:log("INFO", "Установка аварийного охлаждения...")
    
    -- Перемещение всех предметов из реактора в ME систему
    local inventorySize = self.transposer.getInventorySize(config.SIDES.REACTOR)
    
    for slot = 1, inventorySize do
        local stack = self.transposer.getStackInSlot(config.SIDES.REACTOR, slot)
        if stack then
            self.meInterface:exportToME(config.SIDES.REACTOR, slot, stack.size)
        end
    end
    
    -- Установка охлаждающих элементов
    local coolantsInstalled = 0
    local targetSlots = {1, 3, 5, 7, 10, 12, 14, 16, 19, 21, 23, 25, 28, 30, 32, 34}  -- Оптимальные позиции для вентиляторов
    
    for _, coolantType in ipairs(config.ITEMS.EMERGENCY_COOLANTS) do
        for _, slot in ipairs(targetSlots) do
            if coolantsInstalled >= #targetSlots then break end
            
            local transferred = self.meInterface:importFromME(
                coolantType,
                1,
                config.SIDES.REACTOR,
                slot,
                0
            )
            
            if transferred > 0 then
                coolantsInstalled = coolantsInstalled + 1
            end
        end
    end
    
    self:log("INFO", "Установлено охлаждающих элементов: " .. coolantsInstalled)
    
    if coolantsInstalled == 0 then
        self:log("ERROR", "Не удалось установить охлаждающие элементы!")
    end
end

-- Восстановление нормальной схемы после охлаждения
function VacuumClient:restoreLayout()
    self:log("INFO", "Восстановление схемы реактора...")
    
    -- Очистка реактора
    local inventorySize = self.transposer.getInventorySize(config.SIDES.REACTOR)
    for slot = 1, inventorySize do
        local stack = self.transposer.getStackInSlot(config.SIDES.REACTOR, slot)
        if stack then
            self.meInterface:exportToME(config.SIDES.REACTOR, slot, stack.size)
        end
    end
    
    -- Восстановление сохраненной схемы
    local restored = 0
    for slot, item in pairs(self.savedLayout) do
        local transferred = self.meInterface:importFromME(
            item.name,
            item.size,
            config.SIDES.REACTOR,
            slot,
            item.damage
        )
        
        if transferred == item.size then
            restored = restored + 1
        else
            self:log("ERROR", "Не удалось восстановить " .. item.label .. " в слот " .. slot)
        end
    end
    
    self:log("INFO", "Восстановлено предметов: " .. restored .. "/" .. #self.savedLayout)
    
    return restored == #self.savedLayout
end

-- Очистка аварийного режима
function VacuumClient:clearEmergency()
    if not self.emergencyMode then
        return
    end
    
    -- Проверка температуры
    if self.reactorData.tempPercent > 0.3 then
        self:log("WARNING", "Температура все еще высока для выхода из аварийного режима")
        return
    end
    
    -- Восстановление схемы
    if self:restoreLayout() then
        self.emergencyMode = false
        self.reactorData.emergencyMode = false
        self.emergencyCooldown = 0
        self:log("INFO", "Аварийный режим отключен")
    else
        self:log("ERROR", "Не удалось полностью восстановить схему реактора")
    end
end

-- Обновление состояния реактора
function VacuumClient:updateReactorData()
    -- Базовые данные
    self.reactorData.temperature = self.reactor.getHeat()
    self.reactorData.maxTemperature = self.reactor.getMaxHeat()
    self.reactorData.tempPercent = self.reactorData.temperature / self.reactorData.maxTemperature
    self.reactorData.euOutput = self.reactor.getReactorEUOutput()
    self.reactorData.running = self.reactor.isActive()
    
    -- Статус
    if self.emergencyMode then
        self.reactorData.status = "EMERGENCY"
    elseif self.reactorData.running then
        if self.reactorData.tempPercent >= config.REACTOR.WARNING_TEMP_PERCENT then
            self.reactorData.status = "WARNING"
        else
            self.reactorData.status = "RUNNING"
        end
    else
        self.reactorData.status = "STOPPED"
    end
    
    -- Эффективность
    local maxOutput = self.reactor.getMaxEUOutput()
    if maxOutput > 0 then
        self.reactorData.efficiency = self.reactorData.euOutput / maxOutput
    else
        self.reactorData.efficiency = 0
    end
    
    -- Время работы и общая выработка
    if self.reactorData.running then
        local currentTime = computer.uptime()
        local deltaTime = currentTime - (self.lastUpdateTime or currentTime)
        self.reactorData.uptime = currentTime - self.startTime
        self.reactorData.totalEU = self.reactorData.totalEU + (self.reactorData.euOutput * deltaTime)
        self.lastUpdateTime = currentTime
    end
    
    -- Проверка критической температуры
    if self.reactorData.tempPercent >= config.REACTOR.CRITICAL_TEMP_PERCENT and not self.emergencyMode then
        self:emergencyStop()
    end
    
    -- Обновление таймера аварийного охлаждения
    if self.emergencyMode and self.emergencyCooldown > 0 then
        self.emergencyCooldown = self.emergencyCooldown - config.REACTOR.UPDATE_INTERVAL
        self.reactorData.emergencyCooldown = self.emergencyCooldown
        
        if self.emergencyCooldown <= 0 then
            self:clearEmergency()
        end
    end
    
    -- Анализ состояния компонентов
    self:analyzeComponents()
end

-- Анализ состояния компонентов реактора
function VacuumClient:analyzeComponents()
    local coolantCount = 0
    local damagedCoolants = 0
    local fuelCount = 0
    local depletedFuel = 0
    
    local inventorySize = self.transposer.getInventorySize(config.SIDES.REACTOR)
    
    for slot = 1, inventorySize do
        local stack = self.transposer.getStackInSlot(config.SIDES.REACTOR, slot)
        if stack then
            -- Проверка coolant cells
            for _, coolantType in ipairs(config.ITEMS.COOLANT_CELLS) do
                if stack.name == coolantType then
                    coolantCount = coolantCount + 1
                    if stack.damage / stack.maxDamage >= config.REACTOR.COOLANT_MIN_DAMAGE then
                        damagedCoolants = damagedCoolants + 1
                    end
                    break
                end
            end
            
            -- Проверка топливных стержней
            for _, fuelType in ipairs(config.ITEMS.FUEL_RODS) do
                if stack.name == fuelType then
                    fuelCount = fuelCount + 1
                    break
                elseif stack.name:find("depleted") then
                    depletedFuel = depletedFuel + 1
                    break
                end
            end
        end
    end
    
    self.reactorData.coolantStatus = {
        total = coolantCount,
        damaged = damagedCoolants
    }
    
    self.reactorData.fuelStatus = {
        total = fuelCount,
        depleted = depletedFuel
    }
end

-- Отправка данных на сервер
function VacuumClient:sendStatusUpdate()
    if not self.serverAddress then
        return
    end
    
    local data = self.protocol:formatReactorData(self.reactorData)
    self.protocol:send(self.serverAddress, config.MESSAGES.STATUS_UPDATE, data)
    self.lastHeartbeat = computer.uptime()
end

-- Логирование
function VacuumClient:log(level, message)
    local levelName = "INFO"
    for name, value in pairs(config.LOG_LEVELS) do
        if value == level or name == level then
            levelName = name
            break
        end
    end
    
    print(string.format("[%s][%s] %s", os.date("%H:%M:%S"), levelName, message))
    
    -- Отправка лога на сервер
    if self.serverAddress then
        local logData = self.protocol:formatLogMessage(level, message, self.name)
        self.protocol:send(self.serverAddress, config.MESSAGES.LOG, logData)
    end
end

-- Основной цикл работы
function VacuumClient:run()
    if not self:init() then
        return
    end
    
    self.running = true
    
    -- Поток для обработки сообщений
    local messageThread = thread.create(function()
        while self.running do
            self.protocol:processMessages(0.1)
        end
    end)
    
    -- Основной цикл обновления
    while self.running do
        local success, err = pcall(function()
            -- Обновление данных реактора
            self:updateReactorData()
            
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
    
    -- Отправка уведомления об отключении
    if self.serverAddress then
        self.protocol:send(self.serverAddress, config.MESSAGES.UNREGISTER, {
            name = self.name
        })
    end
    
    -- Завершение потока сообщений
    messageThread:kill()
    
    -- Закрытие протокола
    self.protocol:close()
end

-- Остановка клиента
function VacuumClient:stop()
    self.running = false
end

-- Точка входа
local args = {...}
local reactorName = args[1] or nil

local client = VacuumClient:new(reactorName)

-- Обработка сигнала прерывания
event.listen("interrupted", function()
    print("\nОстановка клиента...")
    client:stop()
end)

-- Запуск клиента
client:run() 