-- Модуль интерфейса для сервера управления вакуумными реакторами
local component = require("component")
local term = require("term")

local config = require("SomeReactorCode.actual_src.server.config")
local gpu = component.gpu

local common_config = require("SomeReactorCode.actual_src.config")

local VacuumUI = {}
VacuumUI.__index = VacuumUI

function VacuumUI:new()
    local self = setmetatable({}, VacuumUI)
    
    self.width, self.height = gpu.getResolution()
    
    self.headerHeight = 3
    self.footerHeight = 2
    self.reactorPanelY = self.headerHeight + 1
    self.reactorPanelHeight = 5
    self.logPanelY = self.height - config.UI.LOG_MAX_LINES - self.footerHeight
    self.maxReactorsDisplay = math.floor((self.logPanelY - self.reactorPanelY - 1) / self.reactorPanelHeight)
    
    self.reactors = {}
    self.logs = {}
    self.scrollOffset = 0
    self.selectedReactor = 0
    self.totalEnergyProduced = 0
    self.activeReactors = 0
    
    return self
end

function VacuumUI:init()
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

function VacuumUI:recalculateLayout()
    self.logPanelY = self.height - config.UI.LOG_MAX_LINES - self.footerHeight
    self.maxReactorsDisplay = math.floor((self.logPanelY - self.reactorPanelY - 1) / self.reactorPanelHeight)
end

function VacuumUI:drawStaticElements()
    gpu.setBackground(config.UI.COLORS.HEADER)
    gpu.setForeground(config.UI.COLORS.BACKGROUND)
    gpu.fill(1, 1, self.width, self.headerHeight, " ")
    
    local title = "СИСТЕМА УПРАВЛЕНИЯ ВАКУУМНЫМИ РЕАКТОРАМИ GTNH"
    local titleX = math.floor((self.width - #title) / 2)
    gpu.set(titleX, 2, title)
    
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    gpu.setForeground(config.UI.COLORS.BORDER)
    gpu.fill(1, self.logPanelY - 1, self.width, 1, "═")
    gpu.fill(1, self.height - self.footerHeight + 1, self.width, 1, "═")
    
    gpu.setForeground(config.UI.COLORS.HEADER)
    gpu.set(3, self.logPanelY - 1, "╡ Системные логи ╞")
    
    self:drawFooter()
end

function VacuumUI:drawFooter()
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    gpu.setForeground(config.UI.COLORS.BORDER)
    
    local helpText = "[↑↓] Прокрутка | [S] Старт | [T] Стоп | [M] Обслуживание | [V] Очистить | [R] Обновить | [G] Остановка всех | [P] Запуск всех | [Q] Выход"
    local helpX = math.floor((self.width - #helpText) / 2)
    gpu.set(helpX, self.height, helpText)
end

function VacuumUI:updateReactors(reactorList)
    self.reactors = reactorList
    
    self.totalEnergyProduced = 0
    self.activeReactors = 0
    
    for _, reactor in ipairs(self.reactors) do
        self.totalEnergyProduced = self.totalEnergyProduced + (reactor.totalEU or 0)
        if reactor.status == common_config.REACTOR_STATUS.RUNNING then
            self.activeReactors = self.activeReactors + 1
        end
    end
    
    self:drawStaticElements()
    self:drawReactors()
    self:drawStats()
end

function VacuumUI:drawStats()
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    gpu.setForeground(config.UI.COLORS.FOREGROUND)
    
    local statsY = self.headerHeight + 1
    
    gpu.fill(1, statsY, self.width, 2, " ")
    
    gpu.setForeground(config.UI.COLORS.HIGHLIGHT)
    gpu.set(3, statsY, string.format("Активных реакторов: %d/%d", self.activeReactors, #self.reactors))
    gpu.set(30, statsY, string.format("Общая выработка: %s", self:formatEnergy(self.totalEnergyProduced)))
    
    gpu.setForeground(config.UI.COLORS.BORDER)
    gpu.fill(1, statsY + 1, self.width, 1, "─")
end

function VacuumUI:drawReactors()
    local startY = self.reactorPanelY + 2
    
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    gpu.fill(1, startY, self.width, self.logPanelY - startY - 1, " ")
    
    local displayCount = math.min(#self.reactors - self.scrollOffset, self.maxReactorsDisplay)
    
    for i = 1, displayCount do
        local reactorIndex = i + self.scrollOffset
        local reactor = self.reactors[reactorIndex]
        
        if reactor then
            self:drawReactorPanel(reactor, startY + (i - 1) * self.reactorPanelHeight, reactorIndex == self.selectedReactor)
        end
    end
    
    if #self.reactors > self.maxReactorsDisplay then
        self:drawScrollBar()
    end
end

function VacuumUI:drawReactorPanel(reactor, y, isSelected)
    if isSelected then
        gpu.setBackground(config.UI.COLORS.BORDER)
    else
        gpu.setBackground(config.UI.COLORS.BACKGROUND)
    end
    
    gpu.setForeground(config.UI.COLORS.BORDER)
    gpu.fill(2, y, self.width - 4, self.reactorPanelHeight - 1, " ")
    
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
    local tempPercent = reactor.tempPercent or 0
    if tempPercent >= 0.85 then
        tempColor = config.UI.COLORS.STATUS_ERROR
    elseif tempPercent >= 0.7 then
        tempColor = config.UI.COLORS.STATUS_WARNING
    end
    
    gpu.setForeground(tempColor)
    gpu.set(tempX + 6, y + 1, string.format("%d°C (%.1f%%)", reactor.temperature or 0, (reactor.tempPercent or 0) * 100))
    
    -- Вторая строка - энергия и эффективность
    gpu.setForeground(config.UI.COLORS.FOREGROUND)
    gpu.set(4, y + 2, string.format("Выход: %s EU/t", self:formatNumber(reactor.euOutput or 0)))
    gpu.set(30, y + 2, string.format("Эфф: %.1f%%", (reactor.efficiency or 0) * 100))
    gpu.set(tempX, y + 2, string.format("Всего: %s", self:formatEnergy(reactor.totalEU or 0)))
    
    -- Третья строка - компоненты и время работы
    if reactor.coolantStatus then
        local coolantDamaged = reactor.coolantStatus.damaged or 0
        local coolantTotal = reactor.coolantStatus.total or 0
        local coolantText = string.format("Охлаждение: %d/%d", 
            coolantTotal - coolantDamaged,
            coolantTotal)
        if coolantDamaged > 0 then
            gpu.setForeground(config.UI.COLORS.STATUS_WARNING)
        else
            gpu.setForeground(config.UI.COLORS.FOREGROUND)
        end
        gpu.set(4, y + 3, coolantText)
    end
    
    if reactor.fuelStatus then
        local fuelDepleted = reactor.fuelStatus.depleted or 0
        local fuelTotal = reactor.fuelStatus.total or 0
        local fuelText = string.format("Топливо: %d/%d", 
            fuelTotal - fuelDepleted,
            fuelTotal)
        if fuelDepleted > 0 then
            gpu.setForeground(config.UI.COLORS.STATUS_WARNING)
        else
            gpu.setForeground(config.UI.COLORS.FOREGROUND)
        end
        gpu.set(30, y + 3, fuelText)
    end

    if reactor.runningTime then
        gpu.setForeground(config.UI.COLORS.FOREGROUND)
        gpu.set(tempX, y + 3, string.format("Время работы: %s", self:formatTime(reactor.runningTime)))
    end
    
    if reactor.status == common_config.REACTOR_STATUS.EMERGENCY then
        gpu.setForeground(config.UI.COLORS.EMERGENCY)
        gpu.set(4, y + 4, string.format("АВАРИЙНОЕ ОХЛАЖДЕНИЕ: %ds", reactor.emergencyCooldown or 0))
    elseif reactor.status == common_config.REACTOR_STATUS.MAINTENANCE then
        gpu.setForeground(config.UI.COLORS.STATUS_WARNING)
        gpu.set(4, y + 4, "ТЕХНИЧЕСКОЕ ОБСЛУЖИВАНИЕ")
    elseif reactor.pausedForEnergy then
        gpu.setForeground(config.UI.COLORS.STATUS_WARNING)
        gpu.set(4, y + 4, "ПРИОСТАНОВЛЕН: Энергохранилище переполнено")
    end
    
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
end

function VacuumUI:getStatusStyle(status)
    local styles = {
        RUNNING = {config.UI.COLORS.STATUS_OK, config.UI.SYMBOLS.OK},
        IDLE = {config.UI.COLORS.STATUS_ERROR, config.UI.SYMBOLS.ERROR},
        WARNING = {config.UI.COLORS.STATUS_WARNING, config.UI.SYMBOLS.WARNING},
        EMERGENCY = {config.UI.COLORS.EMERGENCY, config.UI.SYMBOLS.EMERGENCY},
        MAINTENANCE = {config.UI.COLORS.STATUS_WARNING, "⚙"},
        OFFLINE = {config.UI.COLORS.STATUS_OFFLINE, config.UI.SYMBOLS.OFFLINE},
    }
    
    local style = styles[status] or styles.OFFLINE
    return style[1], style[2]
end

function VacuumUI:drawScrollBar()
    local barX = self.width - 2
    local barHeight = self.logPanelY - self.reactorPanelY - 3
    local barY = self.reactorPanelY + 2
    
    gpu.setForeground(config.UI.COLORS.BORDER)
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    
    for y = barY, barY + barHeight - 1 do
        gpu.set(barX, y, "│")
    end
    
    local scrollRatio = self.scrollOffset / (#self.reactors - self.maxReactorsDisplay)
    local thumbY = barY + math.floor(scrollRatio * (barHeight - 1))
    
    gpu.setForeground(config.UI.COLORS.HIGHLIGHT)
    gpu.set(barX, thumbY, "█")
end

function VacuumUI:addLog(timestamp, level, message, reactorName)
    table.insert(self.logs, {
        time = os.date("%H:%M:%S", timestamp),
        level = level,
        message = message,
        reactor = reactorName
    })
    
    while #self.logs > config.UI.LOG_MAX_LINES * 2 do
        table.remove(self.logs, 1)
    end
    
    self:drawLogs()
end

function VacuumUI:drawLogs()
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    
    gpu.fill(2, self.logPanelY, self.width - 2, config.UI.LOG_MAX_LINES, " ")
    
    local startIndex = math.max(1, #self.logs - config.UI.LOG_MAX_LINES + 1)
    local y = self.logPanelY
    
    for i = startIndex, #self.logs do
        local log = self.logs[i]
        if log and y < self.logPanelY + config.UI.LOG_MAX_LINES then
            gpu.setForeground(config.UI.COLORS.BORDER)
            gpu.set(3, y, log.time)
            
            local levelColor = self:getLogLevelColor(log.level)
            gpu.setForeground(levelColor)
            gpu.set(13, y, "[" .. log.level .. "]")
            
            if log.reactor then
                gpu.setForeground(config.UI.COLORS.HIGHLIGHT)
                gpu.set(23, y, "[" .. log.reactor .. "]")
            end
            
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

function VacuumUI:formatTime(seconds)
    if not seconds then return "0s" end
    
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    
    if hours > 0 then
        return string.format("%dч %dм %dс", hours, minutes, secs)
    elseif minutes > 0 then
        return string.format("%dм %dс", minutes, secs)
    else
        return string.format("%dс", secs)
    end
end

function VacuumUI:scrollUp()
    self:selectReactor(self.selectedReactor - 1)
end

function VacuumUI:scrollDown()
    self:selectReactor(self.selectedReactor + 1)
end

function VacuumUI:selectReactor(index)
    if index >= 1 and index <= #self.reactors then
        self.selectedReactor = index
        
        if index - self.scrollOffset < 1 then
            self.scrollOffset = index - 1
        elseif index - self.scrollOffset > self.maxReactorsDisplay then
            self.scrollOffset = index - self.maxReactorsDisplay
        end
        
        self:drawReactors()
    end
end

function VacuumUI:getSelectedReactor()
    if self.selectedReactor > 0 and self.selectedReactor <= #self.reactors then
        return self.reactors[self.selectedReactor]
    end
    return nil
end

function VacuumUI:showMessage(message, isError)
    local messageY = math.floor(self.height / 2)
    local messageX = math.floor((self.width - #message - 4) / 2)
    
    gpu.setBackground(isError and config.UI.COLORS.STATUS_ERROR or config.UI.COLORS.HEADER)
    gpu.setForeground(isError and config.UI.COLORS.FOREGROUND or config.UI.COLORS.BACKGROUND)
    
    gpu.fill(messageX - 2, messageY - 1, #message + 8, 3, " ")
    gpu.set(messageX, messageY, "  " .. message .. "  ")
    
    os.sleep(2)
    gpu.setBackground(config.UI.COLORS.BACKGROUND)
    self:drawReactors()
end

function VacuumUI:cleanup()
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    term.clear()
end

return VacuumUI
