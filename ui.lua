-- Модуль пользовательского интерфейса
local component = require("component")
local term = require("term")
local config = require("config")
local gpu = component.gpu

local UI = {}
UI.__index = UI

-- Создание нового объекта UI
function UI:new()
    local self = setmetatable({}, UI)
    
    self.width, self.height = gpu.getResolution()
    self.reactorPanelHeight = 8
    self.logPanelY = self.height - config.LOG_MAX_LINES - 2
    self.statusPanelY = 2
    self.logs = {}
    
    return self
end

-- Инициализация интерфейса
function UI:init()
    gpu.setBackground(config.COLORS.BACKGROUND)
    gpu.fill(1, 1, self.width, self.height, " ")
    self:drawBorders()
    self:drawTitle()
end

-- Отрисовка границ
function UI:drawBorders()
    gpu.setForeground(config.COLORS.BORDER)
    
    -- Верхняя и нижняя границы
    gpu.fill(1, 1, self.width, 1, "═")
    gpu.fill(1, self.height, self.width, 1, "═")
    gpu.fill(1, self.logPanelY - 1, self.width, 1, "═")
    
    -- Боковые границы
    for y = 2, self.height - 1 do
        gpu.set(1, y, "║")
        gpu.set(self.width, y, "║")
    end
    
    -- Углы
    gpu.set(1, 1, "╔")
    gpu.set(self.width, 1, "╗")
    gpu.set(1, self.height, "╚")
    gpu.set(self.width, self.height, "╝")
    gpu.set(1, self.logPanelY - 1, "╠")
    gpu.set(self.width, self.logPanelY - 1, "╣")
end

-- Отрисовка заголовка
function UI:drawTitle()
    gpu.setForeground(config.COLORS.HEADER)
    gpu.setBackground(config.COLORS.BACKGROUND)
    local title = "╡ Система управления реакторами GTNH ╞"
    local x = math.floor((self.width - #title) / 2)
    gpu.set(x, 1, title)
end

-- Обновление статуса реакторов
function UI:updateReactorStatus(reactors, lscCharge)
    -- Очистка области статуса
    gpu.setBackground(config.COLORS.BACKGROUND)
    gpu.fill(2, self.statusPanelY, self.width - 2, self.logPanelY - self.statusPanelY - 2, " ")
    
    -- Отображение статуса LSC
    gpu.setForeground(config.COLORS.FOREGROUND)
    gpu.set(3, self.statusPanelY, "LSC заряд: ")
    
    local lscColor = config.COLORS.STATUS_OK
    if lscCharge >= config.LSC_MAX_CHARGE_PERCENT then
        lscColor = config.COLORS.STATUS_WARNING
    end
    gpu.setForeground(lscColor)
    gpu.set(14, self.statusPanelY, string.format("%.1f%%", lscCharge * 100))
    
    -- Отображение статуса каждого реактора
    local y = self.statusPanelY + 2
    for i, reactor in ipairs(reactors) do
        local status = reactor:getStatus()
        
        -- Название реактора
        gpu.setForeground(config.COLORS.FOREGROUND)
        gpu.set(3, y, status.name .. ":")
        
        -- Статус работы
        local statusText, statusColor
        if status.running then
            statusText = "РАБОТАЕТ"
            statusColor = config.COLORS.STATUS_OK
        elseif status.retryIn then
            statusText = "ОЖИДАНИЕ (" .. status.retryIn .. "с)"
            statusColor = config.COLORS.STATUS_WARNING
        else
            statusText = "ОСТАНОВЛЕН"
            statusColor = config.COLORS.STATUS_ERROR
        end
        
        gpu.setForeground(statusColor)
        gpu.set(20, y, statusText)
        
        -- Температура
        gpu.setForeground(config.COLORS.FOREGROUND)
        gpu.set(35, y, "Темп:")
        
        local tempColor = config.COLORS.STATUS_OK
        if status.heatPercent >= 0.9 then
            tempColor = config.COLORS.STATUS_ERROR
        elseif status.heatPercent >= 0.7 then
            tempColor = config.COLORS.STATUS_WARNING
        end
        
        gpu.setForeground(tempColor)
        gpu.set(41, y, string.format("%d°C (%.1f%%)", status.heat, status.heatPercent * 100))
        
        -- Выход EU
        gpu.setForeground(config.COLORS.FOREGROUND)
        gpu.set(3, y + 1, "  Выход: ")
        gpu.setForeground(config.COLORS.STATUS_OK)
        gpu.set(12, y + 1, string.format("%.0f EU/t", status.euOutput))
        
        -- Эффективность
        gpu.setForeground(config.COLORS.FOREGROUND)
        gpu.set(25, y + 1, "Эфф:")
        gpu.setForeground(config.COLORS.STATUS_OK)
        gpu.set(30, y + 1, string.format("%.1f%%", status.efficiency * 100))
        
        -- Всего произведено
        gpu.setForeground(config.COLORS.FOREGROUND)
        gpu.set(40, y + 1, "Всего:")
        gpu.setForeground(config.COLORS.HEADER)
        gpu.set(47, y + 1, self:formatEU(status.totalEU))
        
        -- Последняя ошибка
        if status.lastError then
            gpu.setForeground(config.COLORS.STATUS_ERROR)
            gpu.set(3, y + 2, "  ! " .. status.lastError)
        end
        
        y = y + 4
    end
end

-- Форматирование EU
function UI:formatEU(eu)
    if eu >= 1e12 then
        return string.format("%.2f TEU", eu / 1e12)
    elseif eu >= 1e9 then
        return string.format("%.2f GEU", eu / 1e9)
    elseif eu >= 1e6 then
        return string.format("%.2f MEU", eu / 1e6)
    elseif eu >= 1e3 then
        return string.format("%.2f KEU", eu / 1e3)
    else
        return string.format("%.0f EU", eu)
    end
end

-- Добавление записи в лог
function UI:addLog(time, level, message)
    table.insert(self.logs, {
        time = time,
        level = level,
        message = message
    })
    
    -- Ограничиваем количество логов
    while #self.logs > config.LOG_MAX_LINES do
        table.remove(self.logs, 1)
    end
    
    self:updateLogs()
end

-- Обновление области логов
function UI:updateLogs()
    -- Заголовок логов
    gpu.setForeground(config.COLORS.HEADER)
    gpu.setBackground(config.COLORS.BACKGROUND)
    gpu.set(3, self.logPanelY - 1, "╡ Системные логи ╞")
    
    -- Очистка области логов
    gpu.fill(2, self.logPanelY, self.width - 2, config.LOG_MAX_LINES, " ")
    
    -- Отображение логов
    for i, log in ipairs(self.logs) do
        local y = self.logPanelY + i - 1
        
        -- Время
        gpu.setForeground(config.COLORS.BORDER)
        gpu.set(3, y, log.time)
        
        -- Уровень лога
        local levelColor = config.COLORS.FOREGROUND
        if log.level == "ERROR" then
            levelColor = config.COLORS.STATUS_ERROR
        elseif log.level == "WARNING" then
            levelColor = config.COLORS.STATUS_WARNING
        elseif log.level == "FATAL" then
            levelColor = config.COLORS.STATUS_ERROR
        elseif log.level == "INFO" then
            levelColor = config.COLORS.STATUS_OK
        end
        
        gpu.setForeground(levelColor)
        gpu.set(13, y, "[" .. log.level .. "]")
        
        -- Сообщение
        gpu.setForeground(config.COLORS.FOREGROUND)
        local maxMessageLength = self.width - 25
        local message = log.message
        if #message > maxMessageLength then
            message = message:sub(1, maxMessageLength - 3) .. "..."
        end
        gpu.set(23, y, message)
    end
end

-- Отображение справки по командам
function UI:showHelp()
    local helpY = self.height - 1
    gpu.setForeground(config.COLORS.BORDER)
    gpu.setBackground(config.COLORS.BACKGROUND)
    local helpText = " [start/restart] - Запуск | [stop] - Остановка | [exit] - Выход "
    gpu.set(3, helpY, helpText)
end

-- Отображение сообщения
function UI:showMessage(message, isError)
    local messageY = math.floor(self.height / 2)
    local messageX = math.floor((self.width - #message - 4) / 2)
    
    gpu.setBackground(isError and config.COLORS.STATUS_ERROR or config.COLORS.HEADER)
    gpu.setForeground(config.COLORS.FOREGROUND)
    
    -- Рамка сообщения
    gpu.fill(messageX - 1, messageY - 1, #message + 6, 3, " ")
    gpu.set(messageX, messageY, "  " .. message .. "  ")
    
    -- Восстановление фона через 2 секунды
    os.sleep(2)
    gpu.setBackground(config.COLORS.BACKGROUND)
    self:init()
end

-- Очистка экрана при выходе
function UI:cleanup()
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    term.clear()
end

return UI 