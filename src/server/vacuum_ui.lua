-- Модуль интерфейса для сервера управления вакуумными реакторами
local component = require("component")
local term = require("term")
local config = require("../vacuum_config")
local gpu = component.gpu

local VacuumUI = {}
VacuumUI.__index = VacuumUI

function VacuumUI:new()
    local self = setmetatable({}, VacuumUI)
    
    -- Размеры экрана
    self.width, self.height = gpu.getResolution()
    
    -- Параметры интерфейса
    self.headerHeight = 3
    self.footerHeight = 2
    self.reactorPanelY = self.headerHeight + 1
    self.reactorPanelHeight = 5  -- Высота панели для одного реактора
    self.logPanelY = self.height - config.UI.LOG_MAX_LINES - self.footerHeight
    self.maxReactorsDisplay = math.floor((self.logPanelY - self.reactorPanelY - 1) / self.reactorPanelHeight)
    
    -- Данные для отображения
    self.reactors = {}
    self.logs = {}
    self.scrollOffset = 0
    self.selectedReactor = 0
    self.totalEnergyProduced = 0
    self.activeReactors = 0
    
    return self
end

-- Инициализация интерфейса
function VacuumUI:init()
    -- Установка разрешения экрана на максимум
    local maxW, maxH = gpu.maxResolution()
    if self.width ~= maxW or self.height ~= maxH then
        gpu.setResolution(maxW, maxH)
        self.width, self.height = maxW, maxH
        self:recalculateLayout()
    end
    
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    gpu.fill(1, 1, self.width, self.height, " ")
    
    self:drawStaticElements()
end

-- Пересчет компоновки при изменении разрешения
function VacuumUI:recalculateLayout()
    self.logPanelY = self.height - config.UI.LOG_MAX_LINES - self.footerHeight
    self.maxReactorsDisplay = math.floor((self.logPanelY - self.reactorPanelY - 1) / self.reactorPanelHeight)
end

-- Отрисовка статических элементов
function VacuumUI:drawStaticElements()
    -- Заголовок
    gpu.setBackground(config.UI.COLORS.HEADER)
    gpu.setForeground(config.UI.COLORS.BACKGROUND)
    gpu.fill(1, 1, self.width, self.headerHeight, " ")
    
    local title = "СИСТЕМА УПРАВЛЕНИЯ ВАКУУМНЫМИ РЕАКТОРАМИ GTNH"
    local titleX = math.floor((self.width - #title) / 2)
    gpu.set(titleX, 2, title)
    
    -- Разделители
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    gpu.setForeground(config.UI.COLORS.BORDER)
    gpu.fill(1, self.logPanelY - 1, self.width, 1, "═")
    gpu.fill(1, self.height - self.footerHeight + 1, self.width, 1, "═")
    
    -- Заголовок логов
    gpu.setForeground(config.UI.COLORS.HEADER)
    gpu.set(3, self.logPanelY - 1, "╡ Системные логи ╞")
    
    -- Подсказки в футере
    self:drawFooter()
end

-- Отрисовка футера с подсказками
function VacuumUI:drawFooter()
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    gpu.setForeground(config.UI.COLORS.BORDER)
    
    local helpText = "[↑↓] Прокрутка | [S] Старт | [T] Стоп | [E] Сброс аварии | [M] Обслуживание | [R] Обновить | [Q] Выход"
    local helpX = math.floor((self.width - #helpText) / 2)
    gpu.set(helpX, self.height, helpText)
end

-- Обновление списка реакторов
function VacuumUI:updateReactors(reactorList)
    self.reactors = reactorList
    
    -- Подсчет статистики
    self.totalEnergyProduced = 0
    self.activeReactors = 0
    
    for _, reactor in ipairs(self.reactors) do
        self.totalEnergyProduced = self.totalEnergyProduced + (reactor.totalEU or 0)
        if reactor.status == "RUNNING" then
            self.activeReactors = self.activeReactors + 1
        end
    end
    
    self:drawReactors()
    self:drawStats()
end

-- Отрисовка статистики
function VacuumUI:drawStats()
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    gpu.setForeground(config.UI.COLORS.FOREGROUND)
    
    local statsY = self.headerHeight + 1
    
    -- Очистка области статистики
    gpu.fill(1, statsY, self.width, 2, " ")
    
    -- Общая статистика
    gpu.setForeground(config.UI.COLORS.HIGHLIGHT)
    gpu.set(3, statsY, string.format("Активных реакторов: %d/%d", self.activeReactors, #self.reactors))
    gpu.set(30, statsY, string.format("Общая выработка: %s", self:formatEnergy(self.totalEnergyProduced)))
    
    -- Линия разделителя
    gpu.setForeground(config.UI.COLORS.BORDER)
    gpu.fill(1, statsY + 1, self.width, 1, "─")
end

-- Отрисовка списка реакторов
function VacuumUI:drawReactors()
    local startY = self.reactorPanelY + 2
    
    -- Очистка области реакторов
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    gpu.fill(1, startY, self.width, self.logPanelY - startY - 1, " ")
    
    -- Отображение реакторов с учетом прокрутки
    local displayCount = math.min(#self.reactors - self.scrollOffset, self.maxReactorsDisplay)
    
    for i = 1, displayCount do
        local reactorIndex = i + self.scrollOffset
        local reactor = self.reactors[reactorIndex]
        
        if reactor then
            self:drawReactorPanel(reactor, startY + (i - 1) * self.reactorPanelHeight, reactorIndex == self.selectedReactor)
        end
    end
    
    -- Индикатор прокрутки
    if #self.reactors > self.maxReactorsDisplay then
        self:drawScrollBar()
    end
end

-- Отрисовка панели отдельного реактора
function VacuumUI:drawReactorPanel(reactor, y, isSelected)
    -- Фон для выбранного реактора
    if isSelected then
        gpu.setBackground(config.UI.COLORS.BORDER)
    else
        gpu.setBackground(config.UI.COLORS.BACKGROUND)
    end
    
    -- Рамка реактора
    gpu.setForeground(config.UI.COLORS.BORDER)
    gpu.fill(2, y, self.width - 4, self.reactorPanelHeight - 1, " ")
    
    -- Статус и имя реактора
    local statusColor, statusSymbol = self:getStatusStyle(reactor.status)
    gpu.setForeground(statusColor)
    gpu.set(4, y + 1, statusSymbol .. " " .. reactor.name)
    
    -- Статус
    gpu.setForeground(config.UI.COLORS.FOREGROUND)
    gpu.set(30, y + 1, "Статус: ")
    gpu.setForeground(statusColor)
    gpu.set(38, y + 1, reactor.status)
    
    -- Температура
    local tempX = 55
    gpu.setForeground(config.UI.COLORS.FOREGROUND)
    gpu.set(tempX, y + 1, "Темп: ")
    
    local tempColor = config.UI.COLORS.STATUS_OK
    if reactor.tempPercent >= 0.85 then
        tempColor = config.UI.COLORS.STATUS_ERROR
    elseif reactor.tempPercent >= 0.7 then
        tempColor = config.UI.COLORS.STATUS_WARNING
    end
    
    gpu.setForeground(tempColor)
    gpu.set(tempX + 6, y + 1, string.format("%d°C (%.1f%%)", reactor.temperature or 0, (reactor.tempPercent or 0) * 100))
    
    -- Вторая строка - энергия и эффективность
    gpu.setForeground(config.UI.COLORS.FOREGROUND)
    gpu.set(4, y + 2, string.format("Выход: %s EU/t", self:formatNumber(reactor.euOutput or 0)))
    gpu.set(30, y + 2, string.format("Эфф: %.1f%%", (reactor.efficiency or 0) * 100))
    gpu.set(tempX, y + 2, string.format("Всего: %s", self:formatEnergy(reactor.totalEU or 0)))
    
    -- Третья строка - компоненты
    if reactor.coolantStatus then
        local coolantText = string.format("Охлаждение: %d/%d", 
            reactor.coolantStatus.total - reactor.coolantStatus.damaged,
            reactor.coolantStatus.total)
        if reactor.coolantStatus.damaged > 0 then
            gpu.setForeground(config.UI.COLORS.STATUS_WARNING)
        else
            gpu.setForeground(config.UI.COLORS.FOREGROUND)
        end
        gpu.set(4, y + 3, coolantText)
    end
    
    if reactor.fuelStatus then
        local fuelText = string.format("Топливо: %d/%d", 
            reactor.fuelStatus.total - reactor.fuelStatus.depleted,
            reactor.fuelStatus.total)
        if reactor.fuelStatus.depleted > 0 then
            gpu.setForeground(config.UI.COLORS.STATUS_WARNING)
        else
            gpu.setForeground(config.UI.COLORS.FOREGROUND)
        end
        gpu.set(30, y + 3, fuelText)
    end
    
    -- Специальные режимы
    if reactor.emergencyMode then
        gpu.setForeground(config.UI.COLORS.EMERGENCY)
        gpu.set(tempX, y + 3, string.format("АВАРИЙНОЕ ОХЛАЖДЕНИЕ: %ds", reactor.emergencyCooldown or 0))
    elseif reactor.maintenanceMode then
        gpu.setForeground(config.UI.COLORS.STATUS_WARNING)
        gpu.set(tempX, y + 3, "ТЕХНИЧЕСКОЕ ОБСЛУЖИВАНИЕ")
    end
    
    -- Восстановление фона
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
end

-- Получение стиля для статуса
function VacuumUI:getStatusStyle(status)
    local styles = {
        RUNNING = {config.UI.COLORS.STATUS_OK, config.UI.SYMBOLS.OK},
        STOPPED = {config.UI.COLORS.STATUS_ERROR, config.UI.SYMBOLS.ERROR},
        WARNING = {config.UI.COLORS.STATUS_WARNING, config.UI.SYMBOLS.WARNING},
        EMERGENCY = {config.UI.COLORS.EMERGENCY, config.UI.SYMBOLS.EMERGENCY},
        MAINTENANCE = {config.UI.COLORS.STATUS_WARNING, "⚙"},
        OFFLINE = {config.UI.COLORS.STATUS_OFFLINE, config.UI.SYMBOLS.OFFLINE}
    }
    
    local style = styles[status] or styles.OFFLINE
    return style[1], style[2]
end

-- Отрисовка полосы прокрутки
function VacuumUI:drawScrollBar()
    local barX = self.width - 2
    local barHeight = self.logPanelY - self.reactorPanelY - 3
    local barY = self.reactorPanelY + 2
    
    gpu.setForeground(config.UI.COLORS.BORDER)
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    
    -- Полоса прокрутки
    for y = barY, barY + barHeight - 1 do
        gpu.set(barX, y, "│")
    end
    
    -- Позиция ползунка
    local scrollRatio = self.scrollOffset / (#self.reactors - self.maxReactorsDisplay)
    local thumbY = barY + math.floor(scrollRatio * (barHeight - 1))
    
    gpu.setForeground(config.UI.COLORS.HIGHLIGHT)
    gpu.set(barX, thumbY, "█")
end

-- Добавление лога
function VacuumUI:addLog(timestamp, level, message, reactorName)
    table.insert(self.logs, {
        time = os.date("%H:%M:%S", timestamp),
        level = level,
        message = message,
        reactor = reactorName
    })
    
    -- Ограничение количества логов
    while #self.logs > config.UI.LOG_MAX_LINES * 2 do
        table.remove(self.logs, 1)
    end
    
    self:drawLogs()
end

-- Отрисовка логов
function VacuumUI:drawLogs()
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    
    -- Очистка области логов
    gpu.fill(2, self.logPanelY, self.width - 2, config.UI.LOG_MAX_LINES, " ")
    
    -- Отображение последних логов
    local startIndex = math.max(1, #self.logs - config.UI.LOG_MAX_LINES + 1)
    local y = self.logPanelY
    
    for i = startIndex, #self.logs do
        local log = self.logs[i]
        if log and y < self.logPanelY + config.UI.LOG_MAX_LINES then
            -- Время
            gpu.setForeground(config.UI.COLORS.BORDER)
            gpu.set(3, y, log.time)
            
            -- Уровень
            local levelColor = self:getLogLevelColor(log.level)
            gpu.setForeground(levelColor)
            gpu.set(13, y, "[" .. log.level .. "]")
            
            -- Реактор
            if log.reactor then
                gpu.setForeground(config.UI.COLORS.HIGHLIGHT)
                gpu.set(23, y, "[" .. log.reactor .. "]")
            end
            
            -- Сообщение
            gpu.setForeground(config.UI.COLORS.FOREGROUND)
            local messageX = log.reactor and 40 or 23
            local maxLength = self.width - messageX - 2
            local message = log.message
            
            if #message > maxLength then
                message = message:sub(1, maxLength - 3) .. "..."
            end
            
            gpu.set(messageX, y, message)
            
            y = y + 1
        end
    end
end

-- Получение цвета для уровня лога
function VacuumUI:getLogLevelColor(level)
    local colors = {
        DEBUG = config.UI.COLORS.BORDER,
        INFO = config.UI.COLORS.STATUS_OK,
        WARNING = config.UI.COLORS.STATUS_WARNING,
        ERROR = config.UI.COLORS.STATUS_ERROR,
        CRITICAL = config.UI.COLORS.EMERGENCY
    }
    
    return colors[level] or config.UI.COLORS.FOREGROUND
end

-- Форматирование чисел
function VacuumUI:formatNumber(num)
    if num >= 1e9 then
        return string.format("%.2fG", num / 1e9)
    elseif num >= 1e6 then
        return string.format("%.2fM", num / 1e6)
    elseif num >= 1e3 then
        return string.format("%.2fK", num / 1e3)
    else
        return string.format("%.0f", num)
    end
end

-- Форматирование энергии
function VacuumUI:formatEnergy(eu)
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

-- Прокрутка вверх
function VacuumUI:scrollUp()
    if self.scrollOffset > 0 then
        self.scrollOffset = self.scrollOffset - 1
        self:drawReactors()
    end
end

-- Прокрутка вниз
function VacuumUI:scrollDown()
    local maxOffset = math.max(0, #self.reactors - self.maxReactorsDisplay)
    if self.scrollOffset < maxOffset then
        self.scrollOffset = self.scrollOffset + 1
        self:drawReactors()
    end
end

-- Выбор реактора
function VacuumUI:selectReactor(index)
    if index >= 1 and index <= #self.reactors then
        self.selectedReactor = index
        
        -- Автопрокрутка к выбранному реактору
        if index - self.scrollOffset < 1 then
            self.scrollOffset = index - 1
        elseif index - self.scrollOffset > self.maxReactorsDisplay then
            self.scrollOffset = index - self.maxReactorsDisplay
        end
        
        self:drawReactors()
    end
end

-- Получение выбранного реактора
function VacuumUI:getSelectedReactor()
    if self.selectedReactor > 0 and self.selectedReactor <= #self.reactors then
        return self.reactors[self.selectedReactor]
    end
    return nil
end

-- Отображение сообщения
function VacuumUI:showMessage(message, isError)
    local messageY = math.floor(self.height / 2)
    local messageX = math.floor((self.width - #message - 4) / 2)
    
    gpu.setBackground(isError and config.UI.COLORS.STATUS_ERROR or config.UI.COLORS.HEADER)
    gpu.setForeground(isError and config.UI.COLORS.FOREGROUND or config.UI.COLORS.BACKGROUND)
    
    -- Рамка сообщения
    gpu.fill(messageX - 2, messageY - 1, #message + 8, 3, " ")
    gpu.set(messageX, messageY, "  " .. message .. "  ")
    
    -- Автоматическое скрытие через 2 секунды
    os.sleep(2)
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    self:drawReactors()
end

-- Очистка интерфейса
function VacuumUI:cleanup()
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    term.clear()
end

return VacuumUI 