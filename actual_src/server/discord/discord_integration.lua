-- Discord интеграция для системы управления реакторами
local event = require("event")
local thread = require("thread")

local discord = dofile("discord_api.lua")
local config = dofile("../../config.lua")

local integration = {}

-- Локальные переменные
local running = false
local pollThread = nil
local updateThread = nil
local lastStatusUpdate = 0
local commandHandlers = {}
local server = nil  -- Ссылка на сервер реакторов

-- Инициализация интеграции
function integration.init(serverInstance)
    if not config.DISCORD.ENABLED then
        return false, "Discord интеграция отключена в конфигурации"
    end
    
    if not config.DISCORD.BOT_TOKEN or config.DISCORD.BOT_TOKEN == "" then
        return false, "Не указан токен Discord бота"
    end
    
    if not config.DISCORD.CHANNEL_ID or config.DISCORD.CHANNEL_ID == "" then
        return false, "Не указан ID канала Discord"
    end
    
    server = serverInstance
    discord.init(config.DISCORD.BOT_TOKEN)
    
    -- Регистрация обработчиков команд
    integration.registerCommands()
    
    return true
end

-- Регистрация обработчиков команд Discord
function integration.registerCommands()
    -- Команда статуса
    commandHandlers["status"] = function(cmd)
        local reactors = server.getReactors()
        local energyStorages = server.getEnergyStorages()
        discord.sendSystemStatus(cmd.channelId, reactors, energyStorages)
    end
    
    -- Команда списка реакторов
    commandHandlers["reactors"] = function(cmd)
        local reactors = server.getReactors()
        local embed = {
            title = "Список реакторов",
            color = 0x0099ff,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            fields = {}
        }
        
        for id, reactor in pairs(reactors) do
            table.insert(embed.fields, {
                name = reactor.name or id,
                value = string.format("Статус: %s | EU/t: %d | Темп: %.1f°C",
                    reactor.status,
                    reactor.euOutput or 0,
                    reactor.temperature or 0),
                inline = false
            })
        end
        
        if #embed.fields == 0 then
            embed.description = "Нет подключенных реакторов"
        end
        
        discord.sendMessage(cmd.channelId, nil, embed)
    end
    
    -- Команда запуска реактора
    commandHandlers["start"] = function(cmd)
        if #cmd.args < 1 then
            discord.sendError(cmd.channelId, "Использование: !start <имя_реактора|all>")
            return
        end
        
        local target = cmd.args[1]
        if target == "all" then
            server.startAllReactors()
            discord.sendMessage(cmd.channelId, "✅ Запущены все реакторы")
        else
            local success = server.startReactor(target)
            if success then
                discord.sendMessage(cmd.channelId, "✅ Реактор " .. target .. " запущен")
            else
                discord.sendError(cmd.channelId, "Не удалось запустить реактор " .. target)
            end
        end
    end
    
    -- Команда остановки реактора
    commandHandlers["stop"] = function(cmd)
        if #cmd.args < 1 then
            discord.sendError(cmd.channelId, "Использование: !stop <имя_реактора|all>")
            return
        end
        
        local target = cmd.args[1]
        if target == "all" then
            server.stopAllReactors()
            discord.sendMessage(cmd.channelId, "⛔ Остановлены все реакторы")
        else
            local success = server.stopReactor(target)
            if success then
                discord.sendMessage(cmd.channelId, "⛔ Реактор " .. target .. " остановлен")
            else
                discord.sendError(cmd.channelId, "Не удалось остановить реактор " .. target)
            end
        end
    end
    
    -- Команда помощи
    commandHandlers["help"] = function(cmd)
        local embed = {
            title = "Команды управления реакторами",
            color = 0x00ff00,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            fields = {
                {
                    name = config.DISCORD.COMMAND_PREFIX .. "status",
                    value = "Показать общий статус системы",
                    inline = false
                },
                {
                    name = config.DISCORD.COMMAND_PREFIX .. "reactors",
                    value = "Список всех реакторов",
                    inline = false
                },
                {
                    name = config.DISCORD.COMMAND_PREFIX .. "start <имя|all>",
                    value = "Запустить реактор или все реакторы",
                    inline = false
                },
                {
                    name = config.DISCORD.COMMAND_PREFIX .. "stop <имя|all>",
                    value = "Остановить реактор или все реакторы",
                    inline = false
                },
                {
                    name = config.DISCORD.COMMAND_PREFIX .. "energy",
                    value = "Показать состояние энергохранилищ",
                    inline = false
                },
                {
                    name = config.DISCORD.COMMAND_PREFIX .. "logs",
                    value = "Показать последние логи системы",
                    inline = false
                }
            }
        }
        
        discord.sendMessage(cmd.channelId, nil, embed)
    end
    
    -- Команда энергохранилищ
    commandHandlers["energy"] = function(cmd)
        local storages = server.getEnergyStorages()
        local embed = {
            title = "Состояние энергохранилищ",
            color = 0xffaa00,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            fields = {}
        }
        
        for id, storage in pairs(storages) do
            table.insert(embed.fields, {
                name = storage.name or id,
                value = string.format("Заполнение: %.1f%% | %d / %d EU",
                    storage.fillPercent * 100,
                    storage.stored,
                    storage.capacity),
                inline = false
            })
        end
        
        if #embed.fields == 0 then
            embed.description = "Нет подключенных энергохранилищ"
        end
        
        discord.sendMessage(cmd.channelId, nil, embed)
    end
    
    -- Команда логов
    commandHandlers["logs"] = function(cmd)
        local logs = server.getRecentLogs(10)
        local embed = {
            title = "Последние логи системы",
            color = 0x808080,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            description = ""
        }
        
        if logs and #logs > 0 then
            for _, log in ipairs(logs) do
                embed.description = embed.description .. 
                    string.format("[%s] %s: %s\n", 
                        log.timestamp or "N/A",
                        log.level or "INFO",
                        log.message or "")
            end
        else
            embed.description = "Нет доступных логов"
        end
        
        discord.sendMessage(cmd.channelId, nil, embed)
    end
end

-- Обработка команды из Discord
function integration.handleCommand(message)
    local cmd = discord.parseCommand(message, config.DISCORD.COMMAND_PREFIX)
    if not cmd then
        return
    end
    
    local handler = commandHandlers[cmd.command]
    if handler then
        local success, err = pcall(handler, cmd)
        if not success then
            discord.sendError(cmd.channelId, "Ошибка выполнения команды: " .. tostring(err))
        end
    else
        discord.sendError(cmd.channelId, "Неизвестная команда. Используйте " .. 
            config.DISCORD.COMMAND_PREFIX .. "help для списка команд")
    end
end

-- Поток проверки новых сообщений
local function pollMessages()
    while running do
        local success, messages = pcall(discord.getMessages, config.DISCORD.CHANNEL_ID, 10)
        if success and messages then
            for _, message in ipairs(messages) do
                -- Пропускаем сообщения от ботов
                if not message.author.bot then
                    integration.handleCommand(message)
                end
            end
        end
        
        os.sleep(config.DISCORD.POLL_INTERVAL)
    end
end

-- Поток периодических обновлений статуса
local function sendStatusUpdates()
    while running do
        if config.DISCORD.NOTIFICATIONS.SYSTEM_STATUS and 
           os.time() - lastStatusUpdate >= config.DISCORD.UPDATE_INTERVAL then
            
            local reactors = server.getReactors()
            local energyStorages = server.getEnergyStorages()
            
            pcall(discord.sendSystemStatus, config.DISCORD.CHANNEL_ID, reactors, energyStorages)
            lastStatusUpdate = os.time()
        end
        
        os.sleep(1)
    end
end

-- Запуск интеграции
function integration.start()
    if not server then
        return false, "Интеграция не инициализирована"
    end
    
    running = true
    
    -- Запуск потоков
    pollThread = thread.create(pollMessages)
    updateThread = thread.create(sendStatusUpdates)
    
    -- Отправка сообщения о запуске
    pcall(discord.sendMessage, config.DISCORD.CHANNEL_ID, 
        "🚀 Система управления реакторами запущена и подключена к Discord!")
    
    return true
end

-- Остановка интеграции
function integration.stop()
    running = false
    
    -- Отправка сообщения об остановке
    pcall(discord.sendMessage, config.DISCORD.CHANNEL_ID, 
        "🛑 Система управления реакторами отключается от Discord")
    
    -- Ожидание завершения потоков
    if pollThread then
        thread.waitForAny({pollThread})
    end
    if updateThread then
        thread.waitForAny({updateThread})
    end
end

-- Отправка уведомления о событии
function integration.sendNotification(eventType, data)
    if not config.DISCORD.ENABLED or not running then
        return
    end
    
    local notifications = config.DISCORD.NOTIFICATIONS
    
    if eventType == "REACTOR_START" and notifications.REACTOR_START then
        local embed = {
            title = "🟢 Реактор запущен",
            description = "Реактор **" .. (data.name or data.id) .. "** начал работу",
            color = 0x00ff00,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }
        pcall(discord.sendMessage, config.DISCORD.CHANNEL_ID, nil, embed)
        
    elseif eventType == "REACTOR_STOP" and notifications.REACTOR_STOP then
        local embed = {
            title = "🔴 Реактор остановлен",
            description = "Реактор **" .. (data.name or data.id) .. "** прекратил работу",
            color = 0xff0000,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }
        pcall(discord.sendMessage, config.DISCORD.CHANNEL_ID, nil, embed)
        
    elseif eventType == "EMERGENCY" and notifications.EMERGENCY then
        local embed = {
            title = "⚠️ АВАРИЙНАЯ СИТУАЦИЯ",
            description = "Реактор **" .. (data.name or data.id) .. "** в аварийном режиме!",
            color = 0xff00ff,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            fields = {
                {
                    name = "Причина",
                    value = data.reason or "Неизвестно",
                    inline = false
                }
            }
        }
        pcall(discord.sendMessage, config.DISCORD.CHANNEL_ID, nil, embed)
        
    elseif eventType == "MAINTENANCE" and notifications.MAINTENANCE then
        local embed = {
            title = "🔧 Требуется обслуживание",
            description = "Реактор **" .. (data.name or data.id) .. "** требует обслуживания",
            color = 0x0099ff,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            fields = {
                {
                    name = "Детали",
                    value = data.details or "Проверьте состояние компонентов",
                    inline = false
                }
            }
        }
        pcall(discord.sendMessage, config.DISCORD.CHANNEL_ID, nil, embed)
        
    elseif eventType == "ENERGY_PAUSE" and notifications.ENERGY_PAUSE then
        local embed = {
            title = "⏸️ Реакторы приостановлены",
            description = "Все реакторы приостановлены из-за переполнения энергохранилищ",
            color = 0xffaa00,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            fields = {
                {
                    name = "Заполнение",
                    value = string.format("%.1f%%", (data.fillPercent or 0) * 100),
                    inline = true
                }
            }
        }
        pcall(discord.sendMessage, config.DISCORD.CHANNEL_ID, nil, embed)
    end
end

-- Отправка лога в Discord
function integration.sendLog(level, message, reactor)
    if not config.DISCORD.ENABLED or not running then
        return
    end
    
    -- Проверяем, нужно ли отправлять этот уровень лога
    if config.DISCORD.LOG_LEVELS[level] then
        local channelId = config.DISCORD.LOG_CHANNEL_ID ~= "" and 
                         config.DISCORD.LOG_CHANNEL_ID or 
                         config.DISCORD.CHANNEL_ID
        
        pcall(discord.sendLog, channelId, level, message, reactor)
    end
end

return integration 