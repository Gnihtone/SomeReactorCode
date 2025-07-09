-- Модуль управления вакуумным реактором
package.path = package.path .. ";../?.lua"

local component = require("component")
local computer = require("computer")
local config = require("vacuum_config")
local MEInterface = require("me_interface")

-- Класс реактора
local VacuumReactor = {}
VacuumReactor.__index = VacuumReactor

function VacuumReactor:new(name)
    local self = setmetatable({}, VacuumReactor)
    
    -- Основные параметры
    self.name = name
    self.running = false
    self.emergencyMode = false
    self.emergencyCooldown = 0
    self.maintenanceMode = false
    
    -- Компоненты
    self.reactor = nil
    self.transposer = nil
    self.meInterface = nil

    self.currentLayout = {}
    
    -- Состояние реактора
    self.status = {
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
        maintenanceMode = false,
        lastError = nil,
        coolantStatus = {},
        fuelStatus = {},
        uptime = 0,
        totalEU = 0,
        emergencyTriggered = false,
        emergencyReason = nil,
        runningTime = 0,  -- Время работы в секундах (только когда реактор активен)
        pausedForEnergy = false  -- Приостановлен из-за переполнения энергохранилища
    }
    
    -- Сохраненная схема и логи
    self.savedLayout = {}
    self.logs = {}
    self.startTime = computer.uptime()
    self.lastUpdateTime = computer.uptime()
    
    return self
end

-- Инициализация реактора
function VacuumReactor:init()
    self:log("INFO", "Инициализация реактора: " .. self.name)
    
    -- Поиск реактора
    if not component.isAvailable("reactor_chamber") then
        self:log("ERROR", "Реактор не найден!")
        return false
    end
    self.reactor = component.reactor_chamber
    
    -- Поиск transposer
    if not component.isAvailable("transposer") then
        self:log("ERROR", "Transposer не найден!")
        return false
    end
    self.transposer = component.transposer
    
    -- Инициализация ME Interface
    local transposerAddress = component.transposer.address
    self.meInterface = MEInterface:new(transposerAddress)
    
    self:log("INFO", "Инициализация завершена")
    return true
end

-- Запуск реактора
function VacuumReactor:startReactor()
    if self.emergencyMode then
        self:log("ERROR", "Невозможно запустить реактор в аварийном режиме")
        return false
    end
    
    if self.status.pausedForEnergy then
        self:log("WARNING", "Реактор приостановлен из-за переполнения энергохранилища")
        return false
    end
    
    -- Сначала выполняем обслуживание
    if not self:performMaintenance() then
        self:log("WARNING", "Обслуживание не завершено, но реактор будет запущен")
    end
    
    self:saveCurrentLayout()
    self.reactor.setActive(true)
    self.running = true
    self.status.running = true
    self:log("INFO", "Реактор запущен")
    return true
end

-- Остановка реактора
function VacuumReactor:stopReactor()
    -- Сначала останавливаем реактор
    self.reactor.setActive(false)
    self.running = false
    self.status.running = false
    
    -- Затем выполняем обслуживание
    self:log("INFO", "Выполнение обслуживания перед полной остановкой...")
    self:performMaintenance()
    
    self:log("INFO", "Реактор остановлен")
    return true
end

function VacuumReactor:updateCurrentLayout()
    self.currentLayout = self.transposer.getAllStacks(config.SIDES.REACTOR)
    -- local inventorySize = self.transposer.getInventorySize(config.SIDES.REACTOR)
    -- for slot = 1, inventorySize do
    --     local stack = self.transposer.getStackInSlot(config.SIDES.REACTOR, slot)
    --     if stack then
    --         self.currentLayout[slot] = stack
    --     end
    -- end
end

-- Выполнение технического обслуживания
function VacuumReactor:performMaintenance()
    if self.maintenanceMode then
        self:log("DEBUG", "Обслуживание уже выполняется")
        return false
    end
    
    self.maintenanceMode = true
    self.status.maintenanceMode = true
    
    local wasRunning = self.running
    if wasRunning then
        self.reactor.setActive(false)
        self:log("INFO", "Реактор остановлен для обслуживания")
    end
    
    self:updateCurrentLayout()
    local success = true
    
    -- Проверка и замена поврежденных coolant cells
    local damagedCells = self:checkCoolantCells()
    if #damagedCells > 0 then
        self:log("INFO", "Найдено поврежденных coolant cells: " .. #damagedCells)
        if not self:replaceCoolantCells(damagedCells) then
            success = false
        end
    end
    
    -- Проверка и замена истощенных стержней
    local depletedRods = self:checkDepletedRods()
    if #depletedRods > 0 then
        self:log("INFO", "Найдено истощенных стержней: " .. #depletedRods)
        if not self:replaceDepletedRods(depletedRods) then
            success = false
        end
    end
    
    -- Если реактор был запущен и обслуживание прошло успешно, запускаем его снова
    if wasRunning and success then
        self.reactor.setActive(true)
        self.running = true
        self.status.running = true
        self:log("INFO", "Реактор перезапущен после обслуживания")
    elseif wasRunning and not success then
        self:log("WARNING", "Реактор не перезапущен из-за ошибок обслуживания")
    end
    
    self.maintenanceMode = false
    self.status.maintenanceMode = false
    
    return success
end

-- Проверка состояния coolant cells
function VacuumReactor:checkCoolantCells()
    local damagedCells = {}
    local inventorySize = #self.currentLayout
    
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
        if stack and self:isCoolantCell(stack.name) then
            local damagePercent = stack.damage / stack.maxDamage
            if damagePercent >= config.REACTOR.COOLANT_MIN_DAMAGE then
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
function VacuumReactor:isCoolantCell(itemName)
    for _, cellType in ipairs(config.ITEMS.COOLANT_CELLS) do
        if itemName == cellType then
            return true
        end
    end
    return false
end

-- Проверка, является ли предмет истощенным стержнем
function VacuumReactor:isDepletedRod(itemName)
    for _, rodType in ipairs(config.ITEMS.DEPLETED_FUEL_RODS) do
        if itemName == rodType then
            return true
        end
    end
    return false
end

-- Проверка на истощенные стержни
function VacuumReactor:checkDepletedRods()
    local depletedRods = {}
    local inventorySize = #self.currentLayout
    
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
        if stack and self:isDepletedRod(stack.name) then
            table.insert(depletedRods, {
                slot = slot,
                stack = stack
            })
        end
    end
    
    return depletedRods
end

-- Замена поврежденных coolant cells
function VacuumReactor:replaceCoolantCells(damagedCells)
    self:log("INFO", "Замена " .. #damagedCells .. " поврежденных coolant cells")
    
    local success = true
    for _, cell in ipairs(damagedCells) do
        -- Перемещение поврежденной cell в ME систему
        local transferred = self.meInterface:exportToME(
            config.SIDES.REACTOR,
            cell.slot,
            cell.stack.size
        )
        
        if transferred > 0 then
            -- Попытка получить новую cell из ME системы
            local originalCell = self.savedLayout[cell.slot]
            if originalCell and self:isCoolantCell(originalCell.name) then
                local pulled = self:pullFromME(originalCell.name, 1, cell.slot, 0)
                if pulled == 0 then
                    success = false
                    self:log("ERROR", "Не удалось получить coolant cell для слота " .. cell.slot)
                else
                    self:log("DEBUG", "Заменена coolant cell в слоте " .. cell.slot)
                end
            else
                self:log("ERROR", "Нет сохранённой схемы для реактора")
                success = false
            end
        else
            success = false
            self:log("ERROR", "Не удалось переместить поврежденную cell из слота " .. cell.slot)
        end
    end
    
    return success
end

-- Замена истощенных стержней
function VacuumReactor:replaceDepletedRods(depletedRods)
    self:log("INFO", "Замена " .. #depletedRods .. " истощенных стержней")
    
    local success = true
    for _, rod in ipairs(depletedRods) do
        -- Перемещение истощенного стержня в ME систему
        local transferred = self.meInterface:exportToME(
            config.SIDES.REACTOR,
            rod.slot,
            rod.stack.size
        )
        
        if transferred > 0 then
            -- Попытка получить новый стержень из ME системы
            local originalRod = self.savedLayout[rod.slot]
            if originalRod then
                local pulled = self:pullFromME(originalRod.name, originalRod.size, rod.slot, nil)
                if pulled < originalRod.size then
                    success = false
                    self:log("ERROR", "Не удалось получить стержень для слота " .. rod.slot)
                else
                    self:log("DEBUG", "Заменен стержень в слоте " .. rod.slot)
                end
            else
                self:log("ERROR", "Нет сохранённой схемы для реактора")
                success = false
            end
        else
            success = false
            self:log("ERROR", "Не удалось переместить истощенный стержень из слота " .. rod.slot)
        end
    end
    
    return success
end

-- Получение предмета из ME системы
function VacuumReactor:pullFromME(itemName, amount, targetSlot, damage)
    local transferred = self.meInterface:importFromME(
        itemName, 
        amount, 
        config.SIDES.REACTOR, 
        targetSlot,
        damage
    )
    
    return transferred
end

-- Аварийная остановка с охлаждением
function VacuumReactor:emergencyStop()
    self:log("CRITICAL", "АВАРИЙНАЯ ОСТАНОВКА!")
    
    -- Немедленная остановка реактора
    self.reactor.setActive(false)
    self.running = false
    self.status.running = false
    
    -- Сохранение текущей схемы
    self:saveCurrentLayout()
    
    -- Переход в аварийный режим
    self.emergencyMode = true
    self.emergencyCooldown = config.REACTOR.EMERGENCY_COOLDOWN_TIME
    self.status.emergencyMode = true
    self.status.emergencyTriggered = true
    self.status.emergencyReason = "Критическая температура"
    
    -- Очистка реактора и установка охлаждающих элементов
    self:installEmergencyCooling()
end

-- Сохранение текущей схемы реактора
function VacuumReactor:saveCurrentLayout()
    self.savedLayout = {}
    local inventorySize = #self.currentLayout
    
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
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
function VacuumReactor:installEmergencyCooling()
    self:log("INFO", "Установка аварийного охлаждения...")
    
    -- Перемещение всех предметов из реактора в ME систему
    local inventorySize = #self.currentLayout
    
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
        if stack then
            self.meInterface:exportToME(config.SIDES.REACTOR, slot, stack.size)
        end
    end
    
    -- Установка охлаждающих элементов
    local coolantsInstalled = 0
    local targetSlots = {1, 3, 5, 7, 10, 12, 14, 16, 19, 21, 23, 25, 28, 30, 32, 34}
    
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
function VacuumReactor:restoreLayout()
    self:log("INFO", "Восстановление схемы реактора...")
    
    -- Очистка реактора
    local inventorySize = #self.currentLayout
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
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
function VacuumReactor:clearEmergency()
    if not self.emergencyMode then
        return
    end
    
    -- Проверка температуры
    if self.status.tempPercent > 0.3 then
        self:log("WARNING", "Температура все еще высока для выхода из аварийного режима")
        return
    end
    
    -- Восстановление схемы
    if self:restoreLayout() then
        self.emergencyMode = false
        self.status.emergencyMode = false
        self.status.emergencyTriggered = false
        self.status.emergencyReason = nil
        self.emergencyCooldown = 0
        self:log("INFO", "Аварийный режим отключен")
    else
        self:log("ERROR", "Не удалось полностью восстановить схему реактора")
    end
end

-- Обновление состояния реактора
function VacuumReactor:update()
    -- Базовые данные
    self.status.temperature = self.reactor.getHeat()
    self.status.maxTemperature = self.reactor.getMaxHeat()
    self.status.tempPercent = self.status.temperature / self.status.maxTemperature
    self.status.euOutput = self.reactor.getReactorEUOutput()
    self.status.running = self.reactor.producesEnergy()
    
    -- Статус
    if self.emergencyMode then
        self.status.status = "EMERGENCY"
    elseif self.maintenanceMode then
        self.status.status = "MAINTENANCE"
    elseif self.status.pausedForEnergy then
        self.status.status = "PAUSED_ENERGY"
    elseif self.status.running then
        if self.status.tempPercent >= config.REACTOR.WARNING_TEMP_PERCENT then
            self.status.status = "WARNING"
        else
            self.status.status = "RUNNING"
        end
    else
        self.status.status = "STOPPED"
    end
    
    -- Эффективность
    self.status.efficiency = 0.5
    
    -- Время работы и общая выработка
    if self.status.running then
        local currentTime = computer.uptime()
        local deltaTime = currentTime - self.lastUpdateTime
        self.status.uptime = currentTime - self.startTime
        
        -- Обновляем время работы (только когда реактор действительно работает)
        -- Добавляем deltaTime к общему времени работы вместо пересчета всей сессии
        self.status.runningTime = self.status.runningTime + deltaTime
        
        self.status.totalEU = self.status.totalEU + (self.status.euOutput * deltaTime * 20)
        self.lastUpdateTime = currentTime
    else
        -- Обновляем только общее время работы системы
        self.status.uptime = computer.uptime() - self.startTime
        self.lastUpdateTime = computer.uptime()
    end
    
    -- Проверка критической температуры
    if self.status.tempPercent >= config.REACTOR.CRITICAL_TEMP_PERCENT and not self.emergencyMode then
        self:emergencyStop()
    end
    
    -- Обновление таймера аварийного охлаждения
    if self.emergencyMode and self.emergencyCooldown > 0 then
        self.emergencyCooldown = self.emergencyCooldown - config.REACTOR.UPDATE_INTERVAL
        self.status.emergencyCooldown = self.emergencyCooldown
        
        if self.emergencyCooldown <= 0 then
            self:clearEmergency()
        end
    end
    
    self:updateCurrentLayout()
    -- Анализ состояния компонентов
    self:analyzeComponents()
    
    -- Автоматическое обслуживание (если не в аварийном режиме)
    if not self.emergencyMode and not self.maintenanceMode then
        local needsMaintenance = false
        
        -- Проверка coolant cells
        local damagedCells = self:checkCoolantCells()
        if #damagedCells > 0 then
            needsMaintenance = true
        end
        
        -- Проверка топливных стержней
        local depletedRods = self:checkDepletedRods()
        if #depletedRods > 0 then
            needsMaintenance = true
        end
        
        if needsMaintenance then
            self:performMaintenance()
        end
    end
end

-- Анализ состояния компонентов реактора
function VacuumReactor:analyzeComponents()
    local coolantCount = 0
    local damagedCoolants = 0
    local fuelCount = 0
    local depletedFuel = 0
    
    local inventorySize = #self.currentLayout
    
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
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
                elseif self:isDepletedRod(stack.name) then
                    depletedFuel = depletedFuel + 1
                    break
                end
            end
        end
    end
    
    self.status.coolantStatus = {
        total = coolantCount,
        damaged = damagedCoolants
    }
    
    self.status.fuelStatus = {
        total = fuelCount,
        depleted = depletedFuel
    }
end

-- Получение данных о состоянии
function VacuumReactor:getStatusData()
    return self.status
end

-- Логирование
function VacuumReactor:log(level, message)
    print(level, message)
    table.insert(self.logs, {
        time = os.date("%H:%M:%S"),
        level = level,
        message = message
    })
    
    -- Ограничиваем количество логов
    while #self.logs > 100 do
        table.remove(self.logs, 1)
    end
end

-- Получение и очистка логов
function VacuumReactor:getAndClearLogs()
    local logs = self.logs
    self.logs = {}
    return logs
end

-- Приостановка реактора из-за переполнения энергохранилища
function VacuumReactor:pauseForEnergyFull()
    if not self.running then
        return
    end
    
    self.reactor.setActive(false)
    self.running = false
    self.status.running = false
    self.status.pausedForEnergy = true
    
    self:log("WARNING", "Реактор приостановлен из-за переполнения энергохранилища")
end

-- Возобновление работы после освобождения энергохранилища
function VacuumReactor:resumeFromEnergyPause()
    if not self.status.pausedForEnergy then
        return
    end
    
    self.status.pausedForEnergy = false
    
    -- Проверяем, можем ли запустить реактор
    if not self.emergencyMode and not self.maintenanceMode then
        self.reactor.setActive(true)
        self.running = true
        self.status.running = true
        self:log("INFO", "Реактор возобновил работу после освобождения энергохранилища")
    end
end

return VacuumReactor 