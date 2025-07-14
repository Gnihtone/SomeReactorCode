local component = require("component")

local MEInterface = {}
MEInterface.__index = MEInterface

function MEInterface:new(transposerAddress)
    local self = setmetatable({}, MEInterface)
    
    self.transposer = component.proxy(transposerAddress)
    self.meInterfaceAddress = nil

    self:findMEInterface()
    
    return self
end

function MEInterface:findMEInterface()
    for side = 0, 5 do
        local inventoryName = self.transposer.getInventoryName(side)
        if inventoryName and inventoryName:find("BlockInterface") then
            self.meSide = side
            self.meInterfaceAddress = inventoryName
            return true
        end
    end
    
    error("ME Interface not found")
end

function MEInterface:findItemInME(itemName, minDamage, maxDamage)
    for slot, stack in pairs(self.transposer.getAllStacks(self.meSide).getAll()) do
        if stack and stack.name == itemName then
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

function MEInterface:requestItem(itemName, amount, damage)
    local slot, stack = self:findItemInME(itemName, damage, damage)
    if slot and stack then
        return slot, math.min(stack.size, amount)
    end
    
    return nil, 0
end

function MEInterface:exportToME(fromSide, fromSlot, amount)
    local transferred = self.transposer.transferItem(
        fromSide,
        self.meSide,
        amount or 64,
        fromSlot
    )
    
    return transferred
end

function MEInterface:importFromME(itemName, amount, toSide, toSlot, damage)
    local meSlot, available = self:requestItem(itemName, amount, damage)
    
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

function MEInterface:getAvailableItems()
    local items = {}
    for slot, stack in pairs(self.transposer.getAllStacks(self.meSide).getAll()) do
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
