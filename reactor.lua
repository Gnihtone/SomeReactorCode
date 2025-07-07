-- Модуль управления отдельным реактором
local component = require("component")
local sides = require("sides")
local config = require("config")
local MEInterface = require("me_interface")

local Reactor = {}
Reactor.__index = Reactor

-- Создание нового объекта реактора
function Reactor:new(name, transposerAddress, reactorAddress)
    local self = setmetatable({}, Reactor)
    
    self.name = name
    self.transposer = component.proxy(transposerAddress)
    self.reactor = component.proxy(reactorAddress)
    self.meInterface = MEInterface:new(transposerAddress)
    self.running = false
    self.initialLayout = {}
    self.lastError = nil
    self.retryTimer = 0
    self.logs = {}
    self.stats = {
        totalEUProduced = 0,
        runtime = 0,
        lastEUOutput = 0,
        efficiency = 0
    }
    
    return self
end

-- Сохранение текущей схемы реактора
function Reactor:saveLayout()
    self.initialLayout = {}
    local inventorySize = self.transposer.getInventorySize(config.TRANSPOSER_SIDES.REACTOR)
    
    for slot = 1, inventorySize do
        local stack = self.transposer.getStackInSlot(config.TRANSPOSER_SIDES.REACTOR, slot)
        if stack then
            self.initialLayout[slot] = {
                name = stack.name,
                damage = stack.damage,
                size = stack.size,
                label = stack.label
            }
        end
    end
    
    self:log("INFO", "Схема реактора сохранена: " .. #self.initialLayout .. " предметов")
end

-- Запуск реактора
function Reactor:start()
    if self.running then
        self:log("WARNING", "Реактор уже запущен")
        return false
    end
    
    self.reactor.setActive(true)
    self.running = true
    self:log("INFO", "Реактор запущен")
    return true
end

-- Остановка реактора
function Reactor:stop()
    if not self.running then
        return false
    end
    
    self.reactor.setActive(false)
    self.running = false
    self:log("INFO", "Реактор остановлен")
    return true
end

-- Проверка состояния coolant cells
function Reactor:checkCoolantCells()
    local damagedCells = {}
    local inventorySize = self.transposer.getInventorySize(config.TRANSPOSER_SIDES.REACTOR)
    
    for slot = 1, inventorySize do
        local stack = self.transposer.getStackInSlot(config.TRANSPOSER_SIDES.REACTOR, slot)
        if stack and self:isCoolantCell(stack.name) then
            local damagePercent = stack.damage / stack.maxDamage
            if damagePercent >= config.COOLANT_MIN_DAMAGE then
                table.insert(damagedCells, {
                    slot = slot,
                    stack = stack,
                    damagePercent = damagePercent
                })
            end
        end
    end
    
    return damagedCells
end

-- Проверка, является ли предмет coolant cell
function Reactor:isCoolantCell(itemName)
    for _, cellType in ipairs(config.ITEM_TYPES.COOLANT_CELL) do
        if itemName == cellType then
            return true
        end
    end
    return false
end

-- Проверка на истощенные стержни
function Reactor:checkDepletedRods()
    local depletedRods = {}
    local inventorySize = self.transposer.getInventorySize(config.TRANSPOSER_SIDES.REACTOR)
    
    for slot = 1, inventorySize do
        local stack = self.transposer.getStackInSlot(config.TRANSPOSER_SIDES.REACTOR, slot)
        if stack and stack.name:find("depleted") then
            table.insert(depletedRods, {
                slot = slot,
                stack = stack
            })
        end
    end
    
    return depletedRods
end

-- Замена поврежденных coolant cells
function Reactor:replaceCoolantCells(damagedCells)
    self:stop()
    self:log("INFO", "Замена " .. #damagedCells .. " поврежденных coolant cells")
    
    local success = true
    for _, cell in ipairs(damagedCells) do
        -- Перемещение поврежденной cell в ME систему через ME Interface
        local transferred = self.meInterface:exportToME(
            config.TRANSPOSER_SIDES.REACTOR,
            cell.slot,
            cell.stack.size
        )
        
        if transferred > 0 then
            -- Попытка получить новую cell из ME системы
            local originalCell = self.initialLayout[cell.slot]
            if originalCell and self:isCoolantCell(originalCell.name) then
                local pulled = self:pullFromME(originalCell.name, 1, cell.slot)
                if pulled == 0 then
                    success = false
                    self:log("ERROR", "Не удалось получить coolant cell для слота " .. cell.slot)
                end
            end
        else
            success = false
            self:log("ERROR", "Не удалось переместить поврежденную cell из слота " .. cell.slot)
        end
    end
    
    if success then
        self:start()
        self:log("INFO", "Все coolant cells успешно заменены")
    else
        self.retryTimer = config.RETRY_DELAY
        self:log("WARNING", "Некоторые coolant cells не удалось заменить, повтор через " .. config.RETRY_DELAY .. " секунд")
    end
    
    return success
end

-- Замена истощенных стержней
function Reactor:replaceDepletedRods(depletedRods)
    self:stop()
    self:log("INFO", "Замена " .. #depletedRods .. " истощенных стержней")
    
    local success = true
    for _, rod in ipairs(depletedRods) do
        -- Перемещение истощенного стержня в ME систему через ME Interface
        local transferred = self.meInterface:exportToME(
            config.TRANSPOSER_SIDES.REACTOR,
            rod.slot,
            rod.stack.size
        )
        
        if transferred > 0 then
            -- Попытка получить новый стержень из ME системы
            local originalRod = self.initialLayout[rod.slot]
            if originalRod then
                local pulled = self:pullFromME(originalRod.name, originalRod.size, rod.slot)
                if pulled < originalRod.size then
                    success = false
                    self:log("ERROR", "Не удалось получить стержень для слота " .. rod.slot)
                end
            end
        else
            success = false
            self:log("ERROR", "Не удалось переместить истощенный стержень из слота " .. rod.slot)
        end
    end
    
    if success then
        self:start()
        self:log("INFO", "Все стержни успешно заменены")
    else
        self.retryTimer = config.RETRY_DELAY
        self:log("WARNING", "Некоторые стержни не удалось заменить, повтор через " .. config.RETRY_DELAY .. " секунд")
    end
    
    return success
end

-- Получение предмета из ME системы
function Reactor:pullFromME(itemName, amount, targetSlot)
    -- Используем ME Interface для получения предмета
    local transferred = self.meInterface:importFromME(
        itemName, 
        amount, 
        config.TRANSPOSER_SIDES.REACTOR, 
        targetSlot,
        0  -- damage value для новых предметов
    )
    
    if transferred == 0 then
        self:log("DEBUG", "Не удалось получить " .. itemName .. " из ME системы")
    end
    
    return transferred
end

-- Проверка температуры реактора
function Reactor:checkTemperature()
    local heat = self.reactor.getHeat()
    local maxHeat = self.reactor.getMaxHeat()
    local heatPercent = heat / maxHeat
    
    if heatPercent >= config.REACTOR_MAX_TEMP_PERCENT then
        self:stop()
        self:log("FATAL", string.format("КРИТИЧЕСКАЯ ТЕМПЕРАТУРА! %.1f%% от максимума", heatPercent * 100))
        return false
    elseif heatPercent >= 0.7 then
        self:log("WARNING", string.format("Высокая температура: %.1f%%", heatPercent * 100))
    end
    
    return true
end

-- Обновление статистики
function Reactor:updateStats()
    if self.running then
        local euOutput = self.reactor.getReactorEUOutput()
        self.stats.lastEUOutput = euOutput
        self.stats.totalEUProduced = self.stats.totalEUProduced + euOutput * config.UPDATE_INTERVAL
        self.stats.runtime = self.stats.runtime + config.UPDATE_INTERVAL
        self.stats.efficiency = self.reactor.getReactorEUOutput() / self.reactor.getMaxEUOutput()
    end
end

-- Попытка восстановления недостающих компонентов
function Reactor:retryMissingComponents()
    if self.retryTimer <= 0 then
        return
    end
    
    self.retryTimer = self.retryTimer - config.UPDATE_INTERVAL
    
    if self.retryTimer <= 0 then
        self:log("INFO", "Повторная попытка заполнения реактора")
        
        -- Проверяем недостающие компоненты
        local inventorySize = self.transposer.getInventorySize(config.TRANSPOSER_SIDES.REACTOR)
        local missingFixed = true
        
        for slot = 1, inventorySize do
            local current = self.transposer.getStackInSlot(config.TRANSPOSER_SIDES.REACTOR, slot)
            local original = self.initialLayout[slot]
            
            if original and not current then
                local pulled = self:pullFromME(original.name, original.size, slot)
                if pulled < original.size then
                    missingFixed = false
                    self:log("ERROR", "Все еще не хватает: " .. original.label .. " для слота " .. slot)
                end
            end
        end
        
        if missingFixed then
            self:start()
            self:log("INFO", "Все компоненты восстановлены, реактор запущен")
        else
            self.retryTimer = config.RETRY_DELAY
            self:log("WARNING", "Не все компоненты восстановлены, следующая попытка через " .. config.RETRY_DELAY .. " секунд")
        end
    end
end

-- Получение состояния реактора
function Reactor:getStatus()
    local status = {
        name = self.name,
        running = self.running,
        heat = 0,
        maxHeat = 1,
        heatPercent = 0,
        euOutput = 0,
        efficiency = 0,
        totalEU = self.stats.totalEUProduced,
        runtime = self.stats.runtime,
        lastError = self.lastError,
        retryIn = self.retryTimer > 0 and math.ceil(self.retryTimer) or nil
    }
    
    if self.reactor then
        status.heat = self.reactor.getHeat()
        status.maxHeat = self.reactor.getMaxHeat()
        status.heatPercent = status.heat / status.maxHeat
        status.euOutput = self.stats.lastEUOutput
        status.efficiency = self.stats.efficiency
    end
    
    return status
end

-- Логирование
function Reactor:log(level, message)
    local logEntry = {
        time = os.date("%H:%M:%S"),
        level = level,
        message = "[" .. self.name .. "] " .. message
    }
    
    table.insert(self.logs, logEntry)
    
    -- Ограничиваем количество логов
    while #self.logs > config.LOG_MAX_LINES do
        table.remove(self.logs, 1)
    end
    
    if level == "ERROR" or level == "FATAL" then
        self.lastError = message
    end
end

-- Получение логов
function Reactor:getLogs()
    return self.logs
end

return Reactor 