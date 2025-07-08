-- Модуль работы с ME Interface Applied Energistics 2
local component = require("component")
local config = require("vacuum_config")

local MEInterface = {}
MEInterface.__index = MEInterface

-- Создание нового объекта ME Interface
function MEInterface:new(transposerAddress)
    local self = setmetatable({}, MEInterface)
    
    self.transposer = component.proxy(transposerAddress)
    self.meInterfaceAddress = nil
    self.meSide = config.SIDES.ME_SYSTEM
    
    -- Поиск ME Interface
    self:findMEInterface()
    
    return self
end

-- Поиск ME Interface подключенного к transposer
function MEInterface:findMEInterface()
    -- Проверяем все стороны transposer
    for side = 0, 5 do
        local inventoryName = self.transposer.getInventoryName(side)
        if inventoryName and (inventoryName:find("interface") or inventoryName:find("me_interface")) then
            self.meSide = side
            self.meInterfaceAddress = inventoryName
            return true
        end
    end
    
    -- Если не нашли, используем сторону из конфига
    return false
end

-- Поиск предмета в ME системе
function MEInterface:findItemInME(itemName, minDamage, maxDamage)
    local inventorySize = self.transposer.getInventorySize(self.meSide)
    
    if not inventorySize then
        return nil
    end
    
    for slot = 1, inventorySize do
        local stack = self.transposer.getStackInSlot(self.meSide, slot)
        if stack and stack.name == itemName then
            -- Проверка damage value если нужно
            if minDamage and maxDamage then
                if stack.damage >= minDamage and stack.damage <= maxDamage then
                    return slot, stack
                end
            else
                return slot, stack
            end
        end
    end
    
    return nil
end

-- Запрос предмета из ME системы
function MEInterface:requestItem(itemName, amount, damage)
    -- Для ME Interface нужно использовать специальный метод запроса
    -- В OpenComputers это обычно делается через database компонент
    if component.isAvailable("database") then
        local db = component.database
        -- Здесь должен быть код для работы с database компонентом
        -- но в базовой версии используем простой поиск
    end
    
    -- Альтернативный метод - поиск в экспортных слотах ME Interface
    local slot, stack = self:findItemInME(itemName, damage, damage)
    if slot and stack then
        return slot, math.min(stack.size, amount)
    end
    
    return nil, 0
end

-- Экспорт предмета в ME систему
function MEInterface:exportToME(fromSide, fromSlot, amount)
    local transferred = self.transposer.transferItem(
        fromSide,
        self.meSide,
        amount or 64,
        fromSlot
    )
    
    return transferred
end

-- Импорт предмета из ME системы
function MEInterface:importFromME(itemName, amount, toSide, toSlot, damage)
    local meSlot, available = self:requestItem(itemName, amount, damage)
    
    if not meSlot then
        return 0
    end
    
    local toTransfer = math.min(amount, available)
    local transferred = self.transposer.transferItem(
        self.meSide,
        toSide,
        toTransfer,
        meSlot,
        toSlot
    )
    
    return transferred
end

-- Получение списка доступных предметов в ME
function MEInterface:getAvailableItems()
    local items = {}
    local inventorySize = self.transposer.getInventorySize(self.meSide)
    
    if not inventorySize then
        return items
    end
    
    for slot = 1, inventorySize do
        local stack = self.transposer.getStackInSlot(self.meSide, slot)
        if stack then
            local key = stack.name .. ":" .. stack.damage
            if not items[key] then
                items[key] = {
                    name = stack.name,
                    label = stack.label,
                    damage = stack.damage,
                    size = 0,
                    slots = {}
                }
            end
            items[key].size = items[key].size + stack.size
            table.insert(items[key].slots, slot)
        end
    end
    
    return items
end

return MEInterface 