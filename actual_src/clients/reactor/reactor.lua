local component = require("component")
local computer = require("computer")

local config = require("SomeReactorCode.actual_src.clients.reactor.config")
local MEInterface = require("SomeReactorCode.actual_src.clients.reactor.me_interface")

local common_config = require("SomeReactorCode.actual_src.config")

local VacuumReactor = {}
VacuumReactor.__index = VacuumReactor

function VacuumReactor:new(name)
    local self = setmetatable({}, VacuumReactor)
    
    self.name = name
    self.emergencyCooldown = 0
    self.status = common_config.REACTOR_STATUS.IDLE
    
    self.reactor = nil
    self.transposer = nil
    self.meInterface = nil

    self.reactorSide = nil

    self.currentLayout = {}
    self.isCoolantCell = {}
    self.isDepletedRod = {}
    
    self.information = {
        name = self.name,
        status = self.status,
        isBreeder = false,
        temperature = 0,
        maxTemperature = config.REACTOR.MAX_TEMPERATURE,
        euOutput = 0,
        uptime = 0,
        totalEU = 0,
        runningTime = 0,
        coolantStatus = {
            total = 0,
            damaged = 0
        },
        fuelStatus = {
            total = 0,
            depleted = 0
        }
    }
    
    self.savedLayout = {}
    self.logs = {}
    self.startTime = computer.uptime()
    self.lastUpdateTime = computer.uptime()
    
    return self
end

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

function VacuumReactor:init(reactor, transposer)
    self:log("INFO", "Инициализация реактора: " .. self.name)

    self.reactor = reactor
    self.transposer = transposer

    for side = 0, 5 do
        if self.transposer.getInventoryName(side):find("Reactor") then
            self.reactorSide = side
            break
        end
    end

    local transposerAddress = transposer.address
    self.meInterface = MEInterface:new(transposerAddress)

    self.information.isBreeder = self:checkIsBreeder()
    
    self:log("INFO", "Инициализация завершена")
    return true
end

function VacuumReactor:startReactor()
    if self.status == common_config.REACTOR_STATUS.EMERGENCY then
        self:log("ERROR", "Невозможно запустить реактор в аварийном режиме")
        return false
    end

    self:updateCurrentLayout()
    self:saveCurrentLayout()

    if not self:performMaintenance() then
        self:log("WARNING", "Обслуживание не завершено, но реактор будет запущен")
    end

    self.reactor.setActive(true)
    self.status = common_config.REACTOR_STATUS.RUNNING
    self:log("INFO", "Реактор запущен")
    return true
end

function VacuumReactor:stopReactor()
    self.reactor.setActive(false)
    self.status = common_config.REACTOR_STATUS.IDLE

    self:log("INFO", "Выполнение обслуживания перед полной остановкой...")
    self:updateCurrentLayout()
    self:performMaintenance()
    
    self:log("INFO", "Реактор остановлен")
    return true
end

function VacuumReactor:checkIsBreeder()
    for slot = 1, #self.currentLayout do
        local stack = self.currentLayout[slot]
        if stack then
            for _, rodType in ipairs(config.ITEMS.BREEDER_RODS) do
                if stack.name == rodType then
                    return true
                end
            end
        end
    end
end

function VacuumReactor:checkIsCoolantCell(itemName)
    for _, cellType in ipairs(config.ITEMS.COOLANT_CELLS) do
        if itemName == cellType then
            return true
        end
    end
    return false
end

function VacuumReactor:checkIsDepletedRod(itemName)
    for _, rodType in ipairs(config.ITEMS.DEPLETED_FUEL_RODS) do
        if itemName == rodType then
            return true
        end
    end
    return false
end

function VacuumReactor:updateCurrentLayout()
    self.currentLayout = {}
    for slot, stack in pairs(self.transposer.getAllStacks(self.reactorSide).getAll()) do
        self.currentLayout[slot] = stack
        if self:checkIsCoolantCell(stack.name) then
            self.isCoolantCell[slot] = true
        else
            self.isCoolantCell[slot] = false
        end
        if self:checkIsDepletedRod(stack.name) then
            self.isDepletedRod[slot] = true
        else
            self.isDepletedRod[slot] = false
        end
    end
end

function VacuumReactor:checkCoolantCells()
    local damagedCells = {}
    local inventorySize = #self.currentLayout
    
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
        if stack and self.isCoolantCell[slot] then
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

function VacuumReactor:checkDepletedRods()
    local depletedRods = {}
    local inventorySize = #self.currentLayout
    
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
        if stack and self.isDepletedRod[slot] then
            table.insert(depletedRods, {
                slot = slot,
                stack = stack
            })
        end
    end
    
    return depletedRods
end

function VacuumReactor:replaceCoolantCells(damagedCells)
    self:log("INFO", "Замена " .. #damagedCells .. " поврежденных coolant cells")
    
    local success = true
    for _, cell in ipairs(damagedCells) do
        local transferred = self.meInterface:exportToME(
            self.reactorSide,
            cell.slot,
            cell.stack.size
        )
        
        if transferred > 0 then
            local originalCell = self.savedLayout[cell.slot]
            local pulled = self:pullFromME(originalCell.name, 1, cell.slot, 0)
            if pulled == 0 then
                success = false
                self:log("ERROR", "Не удалось получить coolant cell для слота " .. cell.slot)
            else
                self:log("DEBUG", "Заменена coolant cell в слоте " .. cell.slot)
            end
        else
            success = false
            self:log("ERROR", "Не удалось переместить поврежденную cell из слота " .. cell.slot)
        end
    end
    
    return success
end

function VacuumReactor:replaceDepletedRods(depletedRods)
    self:log("INFO", "Замена " .. #depletedRods .. " истощенных стержней")
    
    local success = true
    for _, rod in ipairs(depletedRods) do
        local transferred = self.meInterface:exportToME(
            self.reactorSide,
            rod.slot,
            rod.stack.size
        )
        
        if transferred > 0 then
            local originalRod = self.savedLayout[rod.slot]
            local pulled = self:pullFromME(originalRod.name, originalRod.size, rod.slot, nil)
            if pulled < originalRod.size then
                success = false
                self:log("ERROR", "Не удалось получить стержень для слота " .. rod.slot)
            else
                self:log("DEBUG", "Заменен стержень в слоте " .. rod.slot)
            end
        else
            success = false
            self:log("ERROR", "Не удалось переместить истощенный стержень из слота " .. rod.slot)
        end
    end
    
    return success
end

function VacuumReactor:performMaintenance(damagedCells, depletedRods)
    if self.status == common_config.REACTOR_STATUS.MAINTENANCE then
        self:log("DEBUG", "Обслуживание уже выполняется")
        return false
    end
    
    if damagedCells == nil and depletedRods == nil then
        damagedCells = self:checkCoolantCells()
        depletedRods = self:checkDepletedRods()
    end

    if #damagedCells == 0 and #depletedRods == 0 then
        return true
    end
    
    self.status = common_config.REACTOR_STATUS.MAINTENANCE
    
    self.reactor.setActive(false)
    self:log("INFO", "Реактор остановлен для обслуживания")
    
    local success = true

    if #damagedCells > 0 then
        self:log("INFO", "Найдено поврежденных coolant cells: " .. #damagedCells)
        if not self:replaceCoolantCells(damagedCells) then
            success = false
        end
    end

    if #depletedRods > 0 then
        self:log("INFO", "Найдено истощенных стержней: " .. #depletedRods)
        if not self:replaceDepletedRods(depletedRods) then
            success = false
        end
    end

    if success then
        self.reactor.setActive(true)
        self.status = common_config.REACTOR_STATUS.RUNNING
        self:log("INFO", "Реактор перезапущен после обслуживания")
    else
        self:log("WARNING", "Реактор не перезапущен из-за ошибок обслуживания")
    end
    
    return success
end

function VacuumReactor:pullFromME(itemName, amount, targetSlot, damage)
    local transferred = self.meInterface:importFromME(
        itemName, 
        amount, 
        self.reactorSide, 
        targetSlot,
        damage
    )
    
    return transferred
end

function VacuumReactor:emergencyStop()
    self:log("CRITICAL", "АВАРИЙНАЯ ОСТАНОВКА!")

    self.reactor.setActive(false)
    self.status = common_config.REACTOR_STATUS.EMERGENCY
    
    self:saveCurrentLayout()
    
    self.emergencyCooldown = config.REACTOR.EMERGENCY_COOLDOWN_TIME
    
    self:installEmergencyCooling()
end

function VacuumReactor:installEmergencyCooling()
    self:log("INFO", "Установка аварийного охлаждения...")

    local inventorySize = #self.currentLayout
    
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
        if stack then
            self.meInterface:exportToME(self.reactorSide, slot, stack.size)
        end
    end
    
    local coolantsInstalled = 0
    local targetSlots = {1, 3, 5, 7, 10, 12, 14, 16, 19, 21, 23, 25, 28, 30, 32, 34}
    
    for _, coolantType in ipairs(config.ITEMS.EMERGENCY_COOLANTS) do
        for _, slot in ipairs(targetSlots) do
            if coolantsInstalled >= #targetSlots then break end
            
            local transferred = self.meInterface:importFromME(
                coolantType,
                1,
                self.reactorSide,
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

function VacuumReactor:restoreLayout()
    self:log("INFO", "Восстановление схемы реактора...")
    
    local inventorySize = #self.currentLayout
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
        if stack then
            self.meInterface:exportToME(self.reactorSide, slot, stack.size)
        end
    end
    
    local restored = 0
    for slot, item in pairs(self.savedLayout) do
        local transferred = self.meInterface:importFromME(
            item.name,
            item.size,
            self.reactorSide,
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

function VacuumReactor:clearEmergency()
    if not self.emergencyMode then
        return
    end
    
    if self.status.tempPercent > 0.3 then
        self:log("WARNING", "Температура все еще высока для выхода из аварийного режима")
        return
    end
    
    if self:restoreLayout() then
        self.status = common_config.REACTOR_STATUS.IDLE
        self.emergencyCooldown = 0
        self:log("INFO", "Аварийный режим отключен")
    else
        self:log("ERROR", "Не удалось полностью восстановить схему реактора")
    end
end

function VacuumReactor:update()
    self.information.status = self.status

    self.information.temperature = self.reactor.getHeat()
    self.information.maxTemperature = self.reactor.getMaxHeat()
    self.information.tempPercent = self.information.temperature / self.information.maxTemperature
    self.information.euOutput = self.reactor.getReactorEUOutput()
    self.information.running = self.reactor.producesEnergy()
    
    local currentTime = computer.uptime()
    if self.status == common_config.REACTOR_STATUS.RUNNING then
        local deltaTime = currentTime - self.lastUpdateTime
        self.information.uptime = currentTime - self.startTime
        
        self.information.runningTime = self.information.runningTime + deltaTime
        
        self.information.totalEU = self.information.totalEU + (self.information.euOutput * deltaTime * 20)
        self.lastUpdateTime = currentTime
    else
        self.information.uptime = currentTime - self.startTime
        self.lastUpdateTime = currentTime
    end
    
    if self.information.tempPercent >= config.REACTOR.CRITICAL_TEMP_PERCENT and self.status ~= common_config.REACTOR_STATUS.EMERGENCY then
        self:emergencyStop()
    end
    
    if self.status == common_config.REACTOR_STATUS.EMERGENCY and self.emergencyCooldown > 0 then
        self.emergencyCooldown = self.emergencyCooldown - config.REACTOR.UPDATE_INTERVAL
        self.information.emergencyCooldown = self.emergencyCooldown
        
        if self.emergencyCooldown <= 0 then
            self:clearEmergency()
        end
    end
    
    self:updateCurrentLayout()
    self:analyzeComponents()
    
    if self.status ~= common_config.REACTOR_STATUS.EMERGENCY and self.status ~= common_config.REACTOR_STATUS.MAINTENANCE then
        local needsMaintenance = false
        
        local damagedCells = self:checkCoolantCells()
        if #damagedCells > 0 then
            needsMaintenance = true
        end

        local depletedRods = self:checkDepletedRods()
        if #depletedRods > 0 then
            needsMaintenance = true
        end
        
        if needsMaintenance then
            self:performMaintenance(damagedCells, depletedRods)
        end
    end
end

function VacuumReactor:analyzeComponents()
    local coolantCount = 0
    local damagedCoolants = 0
    local fuelCount = 0
    local depletedFuel = 0
    
    local inventorySize = #self.currentLayout
    
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
        if self.isCoolantCell[slot] then
            coolantCount = coolantCount + 1
            if stack.damage / stack.maxDamage >= config.REACTOR.COOLANT_MIN_DAMAGE then
                damagedCoolants = damagedCoolants + 1
            end
            goto continue
        end

        if self.isDepletedRod[slot] then
            fuelCount = fuelCount + 1
            depletedFuel = depletedFuel + 1
            goto continue
        end
        
        if stack then
            for _, fuelType in ipairs(config.ITEMS.FUEL_RODS) do
                if stack.name == fuelType then
                    fuelCount = fuelCount + 1
                end
                break
            end
        end

        ::continue::
    end
    
    self.information.coolantStatus = {
        total = coolantCount,
        damaged = damagedCoolants
    }
    
    self.information.fuelStatus = {
        total = fuelCount,
        depleted = depletedFuel
    }
end

function VacuumReactor:getInformation()
    return self.information
end

function VacuumReactor:log(level, message)
    print(level, message)
    table.insert(self.logs, {
        time = os.date("%H:%M:%S"),
        level = level,
        message = message
    })
    
    while #self.logs > 100 do
        table.remove(self.logs, 1)
    end
end

function VacuumReactor:getAndClearLogs()
    local logs = self.logs
    self.logs = {}
    return logs
end

return VacuumReactor 