local component = require("component")

local DrawerInterface = {}
DrawerInterface.__index = DrawerInterface

function DrawerInterface:new(transposerAddress)
    local self = setmetatable({}, DrawerInterface)
    
    self.transposer = component.proxy(transposerAddress)
    self.cachedCells = {}  -- Store cells from initialization
    
    self:findDrawerInterface()
    self:cacheCells()  -- Cache the cells during initialization
    
    return self
end

function DrawerInterface:findDrawerInterface()
    for side = 0, 5 do
        local inventoryName = self.transposer.getInventoryName(side)
        if inventoryName and inventoryName:find("fullDrawer") then
            self.drawerSide = side
            return true
        end
    end
    
    error("Drawer Controller not found")
end

function DrawerInterface:cacheCells()
    self.cachedCells = {}
    local stacks = self.transposer.getAllStacks(self.drawerSide).getAll()
    
    for slot, stack in pairs(stacks) do
        slot = slot + 1
        if slot < 5 then
            goto continue
        end
        if stack and next(stack) then
            local key = stack.name
            if not self.cachedCells[key] then
                self.cachedCells[key] = {
                    name = stack.name,
                    label = stack.label,
                    size = stack.size,
                    slots = {}
                }
            end
            table.insert(self.cachedCells[key].slots, slot)
        end

        ::continue::
    end
end

function DrawerInterface:findItemInDrawer(itemName)
    for key, item in pairs(self.cachedCells) do
        if item.name == itemName then
            return item.slots[1], item
        end
    end
    
    return nil
end

function DrawerInterface:requestItem(itemName, amount)
    local slot, item = self:findItemInDrawer(itemName)
    if slot and item then
        return slot, math.min(item.size, amount)
    end
    
    return nil, 0
end

function DrawerInterface:exportToDrawer(fromSide, fromSlot, amount)
    local transferred = self.transposer.transferItem(
        fromSide,
        self.drawerSide,
        amount or 64,
        fromSlot
    )
    
    return transferred
end

function DrawerInterface:importFromDrawer(itemName, amount, toSide, toSlot)
    local drawerSlot, available = self:requestItem(itemName, amount)

    if drawerSlot == nil then
        return 0
    end
    
    local toTransfer = math.min(amount, available)
    local transferred = self.transposer.transferItem(
        self.drawerSide,
        toSide,
        toTransfer,
        drawerSlot,
        toSlot
    )
    
    return transferred
end

function DrawerInterface:refreshCache()
    self:cacheCells()
end

return DrawerInterface 