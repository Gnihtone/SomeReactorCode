-- Система управления ядерными реакторами GTNH
local component = require("component")
local event = require("event")
local thread = require("thread")
local keyboard = require("keyboard")
local config = require("config")
local Reactor = require("reactor")
local UI = require("ui")

-- Проверка наличия необходимых компонентов
if not component.isAvailable("gpu") then
    error("Требуется графическая карта!")
end

-- Главный класс менеджера
local ReactorManager = {}
ReactorManager.__index = ReactorManager

function ReactorManager:new()
    local self = setmetatable({}, ReactorManager)
    
    self.reactors = {}
    self.ui = UI:new()
    self.running = false
    self.mainThread = nil
    self.inputThread = nil
    self.lscAddress = nil
    self.lscCharge = 0
    
    return self
end

-- Автоматическое обнаружение компонентов
function ReactorManager:autoDetectComponents()
    self.ui:addLog(os.date("%H:%M:%S"), "INFO", "Поиск компонентов системы...")
    
    -- Поиск LSC контроллера
    for address, type in component.list("gt_machine") do
        local proxy = component.proxy(address)
        -- Проверяем, является ли это LSC
        if proxy.getSensorInformation and tostring(proxy.getSensorInformation()):find("LSC") then
            self.lscAddress = address
            self.ui:addLog(os.date("%H:%M:%S"), "INFO", "Найден LSC контроллер")
            break
        end
    end
    
    -- Поиск реакторов и transposer'ов
    local transposers = {}
    local reactors = {}
    
    for address, type in component.list("transposer") do
        table.insert(transposers, address)
    end
    
    for address, type in component.list("reactor") do
        table.insert(reactors, address)
    end
    
    -- Сопоставление transposer'ов с реакторами
    for i, reactorAddress in ipairs(reactors) do
        if transposers[i] then
            local reactor = Reactor:new("Реактор #" .. i, transposers[i], reactorAddress)
            table.insert(self.reactors, reactor)
            self.ui:addLog(os.date("%H:%M:%S"), "INFO", "Найден " .. reactor.name)
        end
    end
    
    if #self.reactors == 0 then
        self.ui:addLog(os.date("%H:%M:%S"), "ERROR", "Реакторы не найдены!")
        return false
    end
    
    self.ui:addLog(os.date("%H:%M:%S"), "INFO", "Найдено реакторов: " .. #self.reactors)
    return true
end

-- Инициализация системы
function ReactorManager:init()
    self.ui:init()
    self.ui:showHelp()
    
    if not self:autoDetectComponents() then
        self.ui:showMessage("Ошибка инициализации! Проверьте подключения", true)
        return false
    end
    
    return true
end

-- Сохранение схем всех реакторов
function ReactorManager:saveAllLayouts()
    self.ui:addLog(os.date("%H:%M:%S"), "INFO", "Сохранение схем реакторов...")
    
    for _, reactor in ipairs(self.reactors) do
        reactor:saveLayout()
    end
    
    self.ui:addLog(os.date("%H:%M:%S"), "INFO", "Схемы всех реакторов сохранены")
end

-- Запуск всех реакторов
function ReactorManager:startAllReactors()
    self.ui:addLog(os.date("%H:%M:%S"), "INFO", "Запуск всех реакторов...")
    
    local started = 0
    for _, reactor in ipairs(self.reactors) do
        if reactor:start() then
            started = started + 1
        end
    end
    
    self.ui:addLog(os.date("%H:%M:%S"), "INFO", "Запущено реакторов: " .. started .. "/" .. #self.reactors)
end

-- Остановка всех реакторов
function ReactorManager:stopAllReactors()
    self.ui:addLog(os.date("%H:%M:%S"), "INFO", "Остановка всех реакторов...")
    
    for _, reactor in ipairs(self.reactors) do
        reactor:stop()
    end
    
    self.ui:addLog(os.date("%H:%M:%S"), "INFO", "Все реакторы остановлены")
end

-- Получение заряда LSC
function ReactorManager:getLSCCharge()
    if not self.lscAddress then
        return 0
    end
    
    local lsc = component.proxy(self.lscAddress)
    if lsc and lsc.getSensorInformation then
        local info = lsc.getSensorInformation()
        -- Парсинг информации LSC для получения процента заряда
        for _, line in ipairs(info) do
            local charge = tostring(line):match("(%d+%.?%d*)%%")
            if charge then
                return tonumber(charge) / 100
            end
        end
    end
    
    return 0
end

-- Основной цикл управления
function ReactorManager:mainLoop()
    while self.running do
        local success, err = pcall(function()
            -- Получение заряда LSC
            self.lscCharge = self:getLSCCharge()
            
            -- Проверка переполнения LSC
            local lscOverflow = self.lscCharge >= config.LSC_MAX_CHARGE_PERCENT
            
            -- Обработка каждого реактора
            for _, reactor in ipairs(self.reactors) do
                local reactorSuccess, reactorErr = pcall(function()
                    -- Сбор всех логов реактора
                    for _, log in ipairs(reactor:getLogs()) do
                        self.ui:addLog(log.time, log.level, log.message)
                    end
                    reactor.logs = {}  -- Очистка логов после отображения
                    
                    if lscOverflow and reactor.running then
                        reactor:stop()
                        reactor:log("WARNING", "Остановлен из-за переполнения LSC")
                    elseif not lscOverflow then
                        -- Проверка температуры
                        reactor:checkTemperature()
                        
                        if reactor.running then
                            -- Проверка coolant cells
                            local damagedCells = reactor:checkCoolantCells()
                            if #damagedCells > 0 then
                                reactor:replaceCoolantCells(damagedCells)
                            end
                            
                            -- Проверка истощенных стержней
                            local depletedRods = reactor:checkDepletedRods()
                            if #depletedRods > 0 then
                                reactor:replaceDepletedRods(depletedRods)
                            end
                            
                            -- Обновление статистики
                            reactor:updateStats()
                        end
                        
                        -- Попытка восстановления компонентов
                        reactor:retryMissingComponents()
                    end
                end)
                
                if not reactorSuccess then
                    self.ui:addLog(os.date("%H:%M:%S"), "ERROR", 
                        "Ошибка обработки " .. reactor.name .. ": " .. tostring(reactorErr))
                end
            end
            
            -- Обновление UI
            self.ui:updateReactorStatus(self.reactors, self.lscCharge)
        end)
        
        if not success then
            self.ui:addLog(os.date("%H:%M:%S"), "ERROR", "Ошибка главного цикла: " .. tostring(err))
        end
        
        -- Пауза
        os.sleep(config.UPDATE_INTERVAL)
    end
end

-- Обработка пользовательского ввода
function ReactorManager:handleInput()
    while self.running do
        local _, _, _, code = event.pull(0.1, "key_down")
        
        if code then
            local char = keyboard.keys[code]
            
            if char == "q" or char == "Q" then
                -- Выход
                self.running = false
                self.ui:showMessage("Завершение работы...", false)
            end
        end
    end
end

-- Обработка команд
function ReactorManager:processCommand(command)
    command = command:lower():gsub("^%s*(.-)%s*$", "%1")  -- trim
    
    if command == "start" or command == "restart" then
        self:saveAllLayouts()
        self:startAllReactors()
        return true
    elseif command == "stop" then
        self:stopAllReactors()
        return true
    elseif command == "exit" or command == "quit" then
        self.running = false
        return false
    else
        self.ui:showMessage("Неизвестная команда: " .. command, true)
        return true
    end
end

-- Запуск менеджера
function ReactorManager:run()
    if not self:init() then
        return
    end
    
    self.running = true
    
    -- Создание потока для основного цикла
    self.mainThread = thread.create(function()
        self:mainLoop()
    end)
    
    -- Основной цикл обработки команд
    while self.running do
        -- Ожидание ввода команды
        local command = io.read()
        if command then
            if not self:processCommand(command) then
                break
            end
        end
    end
    
    -- Остановка всех реакторов перед выходом
    self:stopAllReactors()
    
    -- Ожидание завершения потока
    if self.mainThread then
        self.mainThread:join()
    end
    
    -- Очистка UI
    self.ui:cleanup()
end

-- Точка входа
local manager = ReactorManager:new()
manager:run() 