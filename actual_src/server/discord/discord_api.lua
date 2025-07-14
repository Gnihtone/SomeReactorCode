-- Discord API модуль для OpenComputers
local component = require("component")
local event = require("event")
local computer = require("computer")

local json = require("SomeReactorCode.actual_src.server.discord.json")

local discord = {}

-- Проверка наличия интернет-карты
if not component.isAvailable("internet") then
    error("Discord API требует интернет-карту")
end

local internet = component.internet

-- Конфигурация API
discord.config = {
    baseUrl = "https://discord.com/api/v10",
    headers = {},
    timeout = 10
}

-- Инициализация с токеном бота
function discord.init(token)
    if not token then
        error("Discord API требует токен бота")
    end
    discord.config.headers["Authorization"] = "Bot " .. token
    discord.config.headers["Content-Type"] = "application/json"
    discord.config.headers["User-Agent"] = "DiscordBot (OpenComputers, v1.0)"
end

-- Выполнение HTTP запроса
local function request(method, endpoint, data)
    local url = discord.config.baseUrl .. endpoint
    
    local body = nil
    if data then
        body = json.encode(data)
    end
    
    local request = internet.request(url, body, discord.config.headers, method)
    if not request then
        return nil, "Не удалось создать запрос"
    end
    
    local startTime = computer.uptime()
    while true do
        local status, err = request.finishConnect()
        if status then
            break
        elseif status == nil then
            return nil, err
        end
        
        if computer.uptime() - startTime > discord.config.timeout then
            return nil, "Таймаут соединения"
        end
        
        os.sleep(0.1)
    end
    
    local response = ""
    local chunk = request.read()
    while chunk do
        response = response .. chunk
        chunk = request.read()
    end
    
    local code = request.response()
    request.close()
    
    if code >= 200 and code < 300 then
        if response and #response > 0 then
            return json.decode(response)
        else
            return true
        end
    else
        return nil, "HTTP " .. code .. ": " .. (response or "")
    end
end

-- Отправка сообщения в канал
function discord.sendMessage(channelId, content, embed)
    local data = {}
    
    if type(content) == "string" then
        data.content = content
    elseif type(content) == "table" then
        data = content
    end
    
    if embed then
        data.embeds = {embed}
    end
    
    return request("POST", "/channels/" .. channelId .. "/messages", data)
end

-- Получение последних сообщений из канала
function discord.getMessages(channelId, limit)
    limit = limit or 10
    local endpoint = "/channels/" .. channelId .. "/messages?limit=" .. limit
    return request("GET", endpoint)
end

-- Отправка embed сообщения с информацией о реакторе
function discord.sendReactorStatus(channelId, reactorData)
    local color = 0x00ff00 -- Зеленый по умолчанию
    
    if reactorData.status == "STOPPED" then
        color = 0xff0000 -- Красный
    elseif reactorData.status == "PAUSED_ENERGY" then
        color = 0xffaa00 -- Оранжевый
    elseif reactorData.status == "EMERGENCY" then
        color = 0xff00ff -- Пурпурный
    elseif reactorData.status == "MAINTENANCE" then
        color = 0x0099ff -- Голубой
    elseif reactorData.status == "OFFLINE" then
        color = 0x666666 -- Серый
    end
    
    local embed = {
        title = "Статус реактора: " .. reactorData.name,
        color = color,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        fields = {
            {
                name = "Состояние",
                value = reactorData.status,
                inline = true
            },
            {
                name = "Температура",
                value = string.format("%.1f°C / %.1f°C", 
                    reactorData.temperature or 0, 
                    reactorData.maxTemperature or 0),
                inline = true
            },
            {
                name = "Выход EU/t",
                value = tostring(reactorData.euOutput or 0),
                inline = true
            }
        }
    }
    
    if reactorData.runtime then
        table.insert(embed.fields, {
            name = "Время работы",
            value = reactorData.runtime,
            inline = true
        })
    end
    
    if reactorData.maintenance then
        table.insert(embed.fields, {
            name = "Обслуживание",
            value = reactorData.maintenance,
            inline = true
        })
    end
    
    return discord.sendMessage(channelId, nil, embed)
end

-- Отправка сообщения о состоянии всех реакторов
function discord.sendSystemStatus(channelId, reactors, energyStorages)
    local totalReactors = 0
    local runningReactors = 0
    local totalOutput = 0
    
    for _, reactor in pairs(reactors) do
        totalReactors = totalReactors + 1
        if reactor.status == "RUNNING" then
            runningReactors = runningReactors + 1
            totalOutput = totalOutput + (reactor.euOutput or 0)
        end
    end
    
    local fields = {
        {
            name = "Всего реакторов",
            value = tostring(totalReactors),
            inline = true
        },
        {
            name = "Активных",
            value = tostring(runningReactors),
            inline = true
        },
        {
            name = "Общий выход",
            value = totalOutput .. " EU/t",
            inline = true
        }
    }
    
    -- Добавляем информацию об энергохранилищах
    if energyStorages and next(energyStorages) then
        local avgFill = 0
        local count = 0
        for _, storage in pairs(energyStorages) do
            avgFill = avgFill + storage.fillPercent
            count = count + 1
        end
        if count > 0 then
            avgFill = avgFill / count
            table.insert(fields, {
                name = "Заполнение хранилищ",
                value = string.format("%.1f%%", avgFill * 100),
                inline = true
            })
        end
    end
    
    local embed = {
        title = "Система управления реакторами",
        description = "Общий статус системы",
        color = runningReactors > 0 and 0x00ff00 or 0xff0000,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        fields = fields
    }
    
    return discord.sendMessage(channelId, nil, embed)
end

-- Парсинг команд из Discord сообщений
function discord.parseCommand(message, prefix)
    prefix = prefix or "!"
    
    if not message.content or not message.content:sub(1, #prefix) == prefix then
        return nil
    end
    
    local command = message.content:sub(#prefix + 1)
    local args = {}
    
    for word in command:gmatch("%S+") do
        table.insert(args, word)
    end
    
    if #args == 0 then
        return nil
    end
    
    return {
        command = args[1]:lower(),
        args = {table.unpack(args, 2)},
        author = message.author,
        channelId = message.channel_id
    }
end

-- Отправка сообщения об ошибке
function discord.sendError(channelId, errorMessage)
    local embed = {
        title = "Ошибка",
        description = errorMessage,
        color = 0xff0000,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    
    return discord.sendMessage(channelId, nil, embed)
end

-- Отправка лог-сообщения
function discord.sendLog(channelId, level, message, reactor)
    local colors = {
        DEBUG = 0x808080,
        INFO = 0x0099ff,
        WARNING = 0xffaa00,
        ERROR = 0xff0000,
        CRITICAL = 0xff00ff
    }
    
    local embed = {
        title = "Лог системы",
        color = colors[level] or 0xffffff,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        fields = {
            {
                name = "Уровень",
                value = level,
                inline = true
            },
            {
                name = "Сообщение",
                value = message,
                inline = false
            }
        }
    }
    
    if reactor then
        table.insert(embed.fields, 2, {
            name = "Реактор",
            value = reactor,
            inline = true
        })
    end
    
    return discord.sendMessage(channelId, nil, embed)
end

return discord 