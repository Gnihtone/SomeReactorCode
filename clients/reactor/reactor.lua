local component = require("component")
local computer = require("computer")
local thread = require("thread")

local config = require("SomeReactorCode.clients.reactor.config")
local MEInterface = require("SomeReactorCode.clients.reactor.me_interface")

local common_config = require("SomeReactorCode.config")

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
    self.storageSide = nil
    
    self.currentLayout = {}
    self.isCoolantCell = {}
    self.isDepletedRod = {}
    
    self.information = {
        name = self.name,
        status = self.status,
        isBreeder = false,
        temperature = 0,
        maxTemperature = config.REACTOR.MAX_TEMPERATURE,
        tempPercent = 0,
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
        local inventoryName = self.transposer.getInventoryName(side)
        if inventoryName then
            if inventoryName:find("Reactor") then
                self.reactorSide = side
            elseif not inventoryName:find("BlockInterface") then
                self.storageSide = side
            end
        end
    end

    if not self.storageSide then
        self:log("ERROR", "Не найдено дополнительное хранилище")
        error("Требуется дополнительное хранилище (сундук/ящик) подключенное к transposer")
    end
    
    self:updateCurrentLayout()
    self:saveCurrentLayout()
    self:analyzeComponents()

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

    self.information.isBreeder = self:checkIsBreeder()

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
        slot = slot + 1
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
    
    -- Step 1: First fetch all needed coolant cells from ME to storage for faster access
    local cellsToFetch = {}
    for _, cell in ipairs(damagedCells) do
        local originalCell = self.savedLayout[cell.slot]
        table.insert(cellsToFetch, {
            name = originalCell.name,
            size = 1,
            targetSlot = cell.slot
        })
    end
    
    -- Pre-fetch all required coolant cells to storage
    self:log("INFO", "Предзагрузка охлаждающих элементов из ME в буферное хранилище")
    for i, cellInfo in ipairs(cellsToFetch) do
        local storageSlot = i
        local pulled = self.meInterface:importFromME(
            cellInfo.name,
            cellInfo.size,
            self.storageSide,
            storageSlot,
            0
        )
        
        if pulled < cellInfo.size then
            self:log("WARNING", "Не удалось предварительно загрузить " .. cellInfo.name .. " из ME")
        end
    end
    
    -- Step 2: Create parallel threads to handle cell replacement
    local threads = {}
    for i, cell in ipairs(damagedCells) do
        local storageSlot = i
        
        local thread_func = function()
            local transferred = self.meInterface:exportToME(
                self.reactorSide,
                cell.slot,
                cell.stack.size
            )
            
            if transferred > 0 then
                local movedToReactor = self.transposer.transferItem(
                    self.storageSide,
                    self.reactorSide,
                    1,
                    storageSlot,
                    cell.slot
                )
                
                if movedToReactor == 0 then
                    self:log("ERROR", "Не удалось переместить новую охлаждающую ячейку из хранилища в слот " .. cell.slot)
                    success = false
                else
                    self:log("DEBUG", "Заменена coolant cell в слоте " .. cell.slot)
                end
            else
                self:log("ERROR", "Не удалось переместить поврежденную cell из слота " .. cell.slot)
                success = false
            end
            
            os.sleep(0.05)
        end
        
        table.insert(threads, thread.create(thread_func))
    end
    
    for _, t in ipairs(threads) do
        t:join()
    end
    
    return success
end

function VacuumReactor:replaceDepletedRods(depletedRods)
    self:log("INFO", "Замена " .. #depletedRods .. " истощенных стержней")
    
    local success = true
    
    -- Step 1: First fetch all needed rods from ME to storage for faster access
    local rodsToFetch = {}
    for _, rod in ipairs(depletedRods) do
        local originalRod = self.savedLayout[rod.slot]
        table.insert(rodsToFetch, {
            name = originalRod.name,
            size = originalRod.size,
            targetSlot = rod.slot
        })
    end
    
    -- Pre-fetch all required rods to storage
    local slotOffset = 30
    self:log("INFO", "Предзагрузка топливных стержней из ME в буферное хранилище")
    for i, rodInfo in ipairs(rodsToFetch) do
        local storageSlot = i + slotOffset
        local pulled = self.meInterface:importFromME(
            rodInfo.name,
            rodInfo.size,
            self.storageSide,
            storageSlot,
            0
        )
        
        if pulled < rodInfo.size then
            self:log("WARNING", "Не удалось предварительно загрузить " .. rodInfo.name .. " из ME")
            success = false
        end
    end
    
    -- Step 2: Create parallel threads to handle rod replacement
    local threads = {}
    for i, rod in ipairs(depletedRods) do
        local storageSlot = i + slotOffset
        local originalRod = self.savedLayout[rod.slot]
        
        local thread_func = function()
            -- Move depleted rod from reactor to ME
            local transferred = self.meInterface:exportToME(
                self.reactorSide,
                rod.slot,
                rod.stack.size
            )
            
            if transferred > 0 then
                -- Move new rod from storage to reactor
                local movedToReactor = self.transposer.transferItem(
                    self.storageSide,
                    self.reactorSide,
                    originalRod.size,
                    storageSlot,
                    rod.slot
                )
                
                if movedToReactor < originalRod.size then
                    self:log("ERROR", "Не удалось переместить новый стержень из хранилища в слот " .. rod.slot)
                    success = false
                else
                    self:log("DEBUG", "Заменен стержень в слоте " .. rod.slot)
                end
            else
                self:log("ERROR", "Не удалось переместить истощенный стержень из слота " .. rod.slot)
                success = false
            end
            
            os.sleep(0.05)
        end
        
        table.insert(threads, thread.create(thread_func))
    end
    
    for _, t in ipairs(threads) do
        t:join()
    end
    
    return success
end

function VacuumReactor:performMaintenance(damagedCells, depletedRods)
    if self.status == common_config.REACTOR_STATUS.MAINTENANCE then
        self:log("DEBUG", "Обслуживание уже выполняется")
        return false
    end

    local wasRunning = self.status == common_config.REACTOR_STATUS.RUNNING
    
    if damagedCells == nil or depletedRods == nil then
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

    if success and wasRunning then
        self.reactor.setActive(true)
        self.status = common_config.REACTOR_STATUS.RUNNING
        self:log("INFO", "Реактор перезапущен после обслуживания")
    elseif not success then
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
    
    local clearThreads = {}
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
        if stack then
            local thread_func = function()
                self.meInterface:exportToME(self.reactorSide, slot, stack.size)
                os.sleep(0.05) -- Small sleep to prevent potential race conditions
            end
            table.insert(clearThreads, thread.create(thread_func))
            
            -- Limit number of parallel threads to avoid overloading
            if #clearThreads >= 10 then
                for _, t in ipairs(clearThreads) do
                    t:join()
                end
                clearThreads = {}
            end
        end
    end
    
    -- Wait for any remaining clear threads
    for _, t in ipairs(clearThreads) do
        t:join()
    end
    
    local coolantsInstalled = 0
    local targetSlots = {1, 3, 5, 7, 10, 12, 14, 16, 19, 21, 23, 25, 28, 30, 32, 34}
    
    -- Pre-fetch emergency coolants to storage
    self:log("INFO", "Предзагрузка аварийных охладителей из ME в буферное хранилище")
    local coolantsFetched = {}
    local slotIndex = 1
    
    for _, coolantType in ipairs(config.ITEMS.EMERGENCY_COOLANTS) do
        for i = 1, #targetSlots do
            local storageSlot = 200 + slotIndex
            local pulled = self.meInterface:importFromME(
                coolantType,
                1,
                self.storageSide,
                storageSlot,
                0
            )
            
            if pulled > 0 then
                table.insert(coolantsFetched, {
                    storageSlot = storageSlot,
                    targetSlot = targetSlots[i]
                })
                slotIndex = slotIndex + 1
                
                if #coolantsFetched >= #targetSlots then
                    break
                end
            end
        end
        
        if #coolantsFetched >= #targetSlots then
            break
        end
    end
    
    -- Install coolants in parallel
    local installThreads = {}
    for _, coolant in ipairs(coolantsFetched) do
        local thread_func = function()
            local transferred = self.transposer.transferItem(
                self.storageSide,
                self.reactorSide,
                1,
                coolant.storageSlot,
                coolant.targetSlot
            )
            
            if transferred > 0 then
                coolantsInstalled = coolantsInstalled + 1
            end
            
            os.sleep(0.05) -- Small sleep to prevent potential race conditions
        end
        
        table.insert(installThreads, thread.create(thread_func))
    end
    
    -- Wait for all install threads to complete
    for _, t in ipairs(installThreads) do
        t:join()
    end
    
    self:log("INFO", "Установлено охлаждающих элементов: " .. coolantsInstalled)
    
    if coolantsInstalled == 0 then
        self:log("ERROR", "Не удалось установить охлаждающие элементы!")
    end
end

function VacuumReactor:restoreLayout()
    self:log("INFO", "Восстановление схемы реактора...")
    
    -- First clear the reactor
    local inventorySize = #self.currentLayout
    local clearThreads = {}
    
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
        if stack then
            local thread_func = function()
                self.meInterface:exportToME(self.reactorSide, slot, stack.size)
                os.sleep(0.05) -- Small sleep to prevent potential race conditions
            end
            
            table.insert(clearThreads, thread.create(thread_func))
            
            -- Limit number of parallel threads to avoid overloading
            if #clearThreads >= 10 then
                for _, t in ipairs(clearThreads) do
                    t:join()
                end
                clearThreads = {}
            end
        end
    end
    
    -- Wait for any remaining clear threads
    for _, t in ipairs(clearThreads) do
        t:join()
    end
    
    -- Pre-fetch all items to the storage
    self:log("INFO", "Предзагрузка компонентов из ME в буферное хранилище")
    local itemsToRestore = {}
    
    for slot, item in pairs(self.savedLayout) do
        local storageSlot = slot + 300 -- Use slots starting at 301 to avoid conflict with other operations
        local pulled = self.meInterface:importFromME(
            item.name,
            item.size,
            self.storageSide,
            storageSlot,
            item.damage
        )
        
        if pulled == item.size then
            table.insert(itemsToRestore, {
                slot = slot,
                storageSlot = storageSlot,
                size = item.size,
                label = item.label
            })
        else
            self:log("WARNING", "Не удалось предварительно загрузить " .. item.label .. " из ME")
        end
    end
    
    -- Restore items in parallel
    local restoreThreads = {}
    local restored = 0
    
    for _, item in ipairs(itemsToRestore) do
        local thread_func = function()
            local transferred = self.transposer.transferItem(
                self.storageSide,
                self.reactorSide,
                item.size,
                item.storageSlot,
                item.slot
            )
            
            if transferred == item.size then
                restored = restored + 1
            else
                self:log("ERROR", "Не удалось восстановить " .. item.label .. " в слот " .. item.slot)
            end
            
            os.sleep(0.05) -- Small sleep to prevent potential race conditions
        end
        
        table.insert(restoreThreads, thread.create(thread_func))
    end
    
    -- Wait for all restore threads to complete
    for _, t in ipairs(restoreThreads) do
        t:join()
    end
    
    self:log("INFO", "Восстановлено предметов: " .. restored .. "/" .. #self.savedLayout)
    
    return restored == #self.savedLayout
end

function VacuumReactor:clearEmergency()
    if not self.emergencyMode then
        return
    end
    
    local tempPercent = self.information.tempPercent or 0
    if tempPercent > 0.3 then
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
                    break
                end
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

function VacuumReactor:clearReactor()
    self:log("INFO", "Очистка реактора...")

    self.reactor.setActive(false)
    self.status = common_config.REACTOR_STATUS.MAINTENANCE

    local cleared = 0
    local inventorySize = #self.currentLayout
    
    -- Create threads to clear reactor in parallel
    local clearThreads = {}
    local itemsCleared = 0
    
    for slot = 1, inventorySize do
        local stack = self.currentLayout[slot]
        if stack and next(stack) ~= nil then
            local thread_func = function()
                local transferred = self.meInterface:exportToME(self.reactorSide, slot, stack.size)
                if transferred > 0 then
                    itemsCleared = itemsCleared + 1
                    self:log("DEBUG", "Предмет из слота " .. slot .. " перемещен в ME")
                else
                    self:log("WARNING", "Не удалось переместить предмет из слота " .. slot)
                end
                os.sleep(0.05) -- Small sleep to prevent potential race conditions
            end
            
            table.insert(clearThreads, thread.create(thread_func))
            
            -- Limit number of parallel threads to avoid overloading
            if #clearThreads >= 10 then
                for _, t in ipairs(clearThreads) do
                    t:join()
                end
                clearThreads = {}
            end
        end
    end
    
    -- Wait for any remaining clear threads
    for _, t in ipairs(clearThreads) do
        t:join()
    end

    self:updateCurrentLayout()
    self.status = common_config.REACTOR_STATUS.IDLE
    self:log("INFO", "Реактор очищен. Перемещено предметов: " .. itemsCleared)
    
    return itemsCleared
end

return VacuumReactor 