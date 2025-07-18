local component = require("component")
local event = require("event")
local thread = require("thread")
local computer = require("computer")

local config = require("SomeReactorCode.clients.reactor.config")
local VacuumReactor = require("SomeReactorCode.clients.reactor.reactor")
local MEInterface = require("SomeReactorCode.clients.reactor.me_interface")

local common_config = require("SomeReactorCode.config")
local Protocol = require("SomeReactorCode.protocol")

local VacuumClientManager = {}
VacuumClientManager.__index = VacuumClientManager

function VacuumClientManager:new(clientName)
    local self = setmetatable({}, VacuumClientManager)

    self.clientName = (clientName or "Client-") .. computer.address():sub(1, 8)
    self.running = false
    self.serverAddress = nil
    self.lastHeartbeat = 0
    
    self.protocol = nil
    self.reactors = {}
    self.reactorAddresses = {}
    self.transposerAddresses = {}
    
    self.messageThread = nil
    self.mainThread = nil
    
    return self
end

function VacuumClientManager:init()
    print("Инициализация клиента: " .. self.clientName)
    
    local isServer = false
    self.protocol = Protocol:new(isServer)
    
    self:findAllReactors()
    self:findAllTransposers()

    if #self.reactorAddresses == 0 then
        error("Не найдено ни одного реактора!")
    end
    
    print("Найдено реакторов: " .. #self.reactorAddresses)

    for i, reactorAddress in ipairs(self.reactorAddresses) do
        local reactorId = self.clientName .. "-R" .. i
        local vacuum_reactor = VacuumReactor:new(reactorId)

        local reactor = component.proxy(reactorAddress)

        local transposerAddress = self:findNearestTransposer(reactor)
        if transposerAddress then
            local transposer = component.proxy(transposerAddress)

            vacuum_reactor:init(reactor, transposer)
            self.reactors[reactorId] = vacuum_reactor
            print("Инициализирован реактор: " .. reactorId)
        else
            error("Не найден transposer для реактора " .. reactorId)
        end
    end

    self:setupHandlers()

    self:registerToServer()
    
    print("Инициализация завершена")
    return true
end

function VacuumClientManager:findAllReactors()
    self.reactorAddresses = {}
    
    for address, componentType in component.list("reactor_chamber") do
        table.insert(self.reactorAddresses, address)
    end
end

function VacuumClientManager:findAllTransposers()
    self.transposerAddresses = {}

    for address, componentType in component.list("transposer") do
        table.insert(self.transposerAddresses, address)
    end
end

local function checkSlotsAreSame(slot, stack, reactor)
    slot = slot - 1
    local x = slot % 9
    local y = math.floor(slot / 9)
    local slotInfo = reactor.getSlotInfo(x, y)

    if (stack == nil or next(stack) == nil) and (slotInfo == nil or next(slotInfo) == nil) then
        return true
    end

    if stack == nil or next(stack) == nil or slotInfo == nil or next(slotInfo) == nil then
        return false
    end

    if stack.name ~= slotInfo.item.name then
        return false
    end

    return true
end

function VacuumClientManager:findNearestTransposer(reactor)
    local minInventorySize = 60
    for _, transposerAddress in ipairs(self.transposerAddresses) do
        local transposer = component.proxy(transposerAddress)
        local currentReactorSide = nil
        local currentMeInterfaceSide = nil
        local anotherStorageSide = nil
        local currentDrawerSide = nil
        for side = 0, 5 do
            local inventoryName = transposer.getInventoryName(side)
            if not inventoryName then
                goto continue
            end

            if inventoryName:find("Reactor") then
                currentReactorSide = side
            elseif inventoryName:find("BlockInterface") then
                currentMeInterfaceSide = side
            elseif inventoryName:find("fullDrawer") then
                currentDrawerSide = side
            elseif transposer.getInventorySize(side) >= minInventorySize then
                anotherStorageSide = side
            end

            ::continue::
        end

        if not currentReactorSide then
            error("Не найден реактор для transposer " .. transposerAddress)
        end
        if not currentMeInterfaceSide then
            error("Не найден ME Interface для transposer " .. transposerAddress)
        end
        if not anotherStorageSide then
            error("Не найден другой инвентарь для transposer " .. transposerAddress)
        end
        if not currentDrawerSide then
            error("Не найден drawer для transposer " .. transposerAddress)
        end

        local reactorInventory = transposer.getAllStacks(currentReactorSide).getAll()

        local transferredSlot = nil
        for slot, stack in pairs(reactorInventory) do
            slot = slot + 1
            if stack and next(stack) ~= nil then
                transferredSlot = slot
                break
            end
        end
        if transferredSlot == nil then
            error("Какой-то из реакторов пуст")
        end

        local notTransferredStack = transposer.getStackInSlot(currentReactorSide, transferredSlot)
        if not checkSlotsAreSame(transferredSlot, notTransferredStack, reactor) then
            goto next_transposer
        end

        local transferred = transposer.transferItem(currentReactorSide, anotherStorageSide, 1, transferredSlot, 1)
        if transferred == 0 then
            goto next_transposer
        end

        local found = false
        local transferredStack = transposer.getStackInSlot(currentReactorSide, transferredSlot)
        if checkSlotsAreSame(transferredSlot, transferredStack, reactor) then
            found = true
        end

        transposer.transferItem(anotherStorageSide, currentReactorSide, 1, 1, transferredSlot)
        if found then
            return transposerAddress
        end

        ::next_transposer::
    end
    
    return nil
end

function VacuumClientManager:setupHandlers()
    self.protocol:registerHandler(common_config.MESSAGES.ACK, function(data, from)
        if data.originalType == common_config.MESSAGES.REGISTER then
            self.serverAddress = from
            self:log("INFO", "Зарегистрирован на сервере: " .. from:sub(1, 8))
        end
    end)

    self.protocol:registerHandler(common_config.MESSAGES.COMMAND, function(data, from)
        self:handleServerCommand(data.command, data.parameters, data.reactorId)
    end)
end

function VacuumClientManager:registerToServer()
    self:log("INFO", "Поиск сервера...")
    
    local reactorList = {}
    for reactorId, reactor in pairs(self.reactors) do
        local reactorData = reactor:getInformation()
        reactorData.reactorId = reactorId
        table.insert(reactorList, reactorData)
    end
    
    self.protocol:send("broadcast", common_config.MESSAGES.REGISTER, {
        name = self.clientName,
        type = common_config.NETWORK.CLIENT_TYPES.REACTOR_CLIENT,
        reactors = reactorList
    })
    
    local timeout = computer.uptime() + common_config.NETWORK.TIMEOUT
    while computer.uptime() < timeout and not self.serverAddress do
        self.protocol:processMessages(0.1)
    end
    
    if not self.serverAddress then
        self:log("WARNING", "Сервер не найден, работа в автономном режиме")
    end
end

function VacuumClientManager:handleServerCommand(command, parameters, reactorId)
    if reactorId and self.reactors[reactorId] then
        local reactor = self.reactors[reactorId]
        
        if command == common_config.COMMANDS.START then
            reactor:startReactor()
        elseif command == common_config.COMMANDS.STOP then
            reactor:stopReactor()
        elseif command == common_config.COMMANDS.FORCE_MAINTENANCE then
            reactor:performMaintenance()
        elseif command == common_config.COMMANDS.CLEAR_REACTOR then
            reactor:clearReactor()
        end
    elseif not reactorId then
        for id, reactor in pairs(self.reactors) do
            self:handleServerCommand(command, parameters, id)
        end
    end
    
    if command == common_config.COMMANDS.DISCOVER then
        self:registerToServer()
    end
end

function VacuumClientManager:sendStatusUpdate()
    if not self.serverAddress then
        return
    end
    
    local reactorsData = {}
    for reactorId, reactor in pairs(self.reactors) do
        local reactorData = reactor:getInformation()
        reactorData.reactorId = reactorId
        table.insert(reactorsData, reactorData)
    end
    
    self.protocol:send(self.serverAddress, common_config.MESSAGES.STATUS_UPDATE, {
        clientName = self.clientName,
        reactors = reactorsData
    })

    self.lastHeartbeat = computer.uptime()
end

function VacuumClientManager:sendLog(level, message, reactorId)
    if self.serverAddress then
        local logData = self.protocol:formatLogMessage(level, message, reactorId or self.clientName)
        self.protocol:send(self.serverAddress, common_config.MESSAGES.LOG, logData)
    end
end

function VacuumClientManager:log(level, message, reactorId)
    local timestamp = os.date("%H:%M:%S")
    local prefix = reactorId and string.format("[%s][%s][%s]", timestamp, level, reactorId) or string.format("[%s][%s]", timestamp, level)
    
    self:sendLog(level, message, reactorId)
end

function VacuumClientManager:run()
    if not self:init() then
        return
    end
    
    self.running = true
    
    self.messageThread = thread.create(function()
        while self.running do
            self.protocol:processMessages(0.1)
        end
    end)
    
    self.mainThread = thread.create(function()
        while self.running do
            local success, err = pcall(function()
                for reactorId, reactor in pairs(self.reactors) do
                    reactor:update()

                    local logs = reactor:getAndClearLogs()
                    for _, logEntry in ipairs(logs) do
                        self:log(logEntry.level, logEntry.message, reactorId)
                    end
                end
                
                if computer.uptime() - self.lastHeartbeat >= common_config.NETWORK.HEARTBEAT_INTERVAL then
                    self:sendStatusUpdate()
                end
            end)
            
            if not success then
                self:log("ERROR", "Ошибка в основном цикле: " .. tostring(err))
            end

            os.sleep(config.REACTOR.UPDATE_INTERVAL)
        end
    end)
    
    while self.running do
        os.sleep(0.5)
    end
    
    if self.serverAddress then
        self.protocol:send(self.serverAddress, common_config.MESSAGES.UNREGISTER, {
            name = self.clientName
        })
    end
    
    if self.messageThread then
        self.messageThread:kill()
    end
    if self.mainThread then
        self.mainThread:kill()
    end
    
    self.protocol:close()
    for _, reactor in pairs(self.reactors) do
        reactor:stopReactor()
    end
end

function VacuumClientManager:stop()
    self.running = false
end

local args = {...}
local clientName = args[1] or nil

local manager = VacuumClientManager:new(clientName)

local function interruptEvent()
    print("\nОстановка клиента...")
    manager:stop()
end

event.listen("interrupted", interruptEvent)

manager:run()

event.ignore("interrupted", interruptEvent)
