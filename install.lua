-- Установщик системы управления реакторами GTNH
local component = require("component")
local fs = require("filesystem")
local shell = require("shell")
local term = require("term")

print("=== Установщик системы управления реакторами GTNH ===")
print()

-- Проверка необходимых компонентов
local function checkComponents()
    print("Проверка компонентов...")
    
    local required = {
        ["gpu"] = "Графическая карта",
        ["screen"] = "Экран",
        ["keyboard"] = "Клавиатура"
    }
    
    local missing = {}
    for comp, name in pairs(required) do
        if not component.isAvailable(comp) then
            table.insert(missing, name)
        end
    end
    
    if #missing > 0 then
        print("ОШИБКА: Отсутствуют необходимые компоненты:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        return false
    end
    
    print("✓ Все необходимые компоненты найдены")
    return true
end

-- Список файлов для установки
local files = {
    "reactor_manager.lua",
    "reactor.lua", 
    "ui.lua",
    "config.lua",
    "me_interface.lua",
    "README.md"
}

-- Создание резервных копий
local function backupExisting()
    print("\nСоздание резервных копий существующих файлов...")
    
    local backupDir = "/backup_" .. os.date("%Y%m%d_%H%M%S")
    fs.makeDirectory(backupDir)
    
    for _, file in ipairs(files) do
        if fs.exists(file) then
            fs.copy(file, backupDir .. "/" .. file)
            print("  Резервная копия: " .. file)
        end
    end
    
    print("✓ Резервные копии созданы в " .. backupDir)
end

-- Проверка наличия реакторов
local function checkReactors()
    print("\nПоиск реакторов...")
    
    local reactorCount = 0
    local transposerCount = 0
    
    for address, type in component.list("reactor") do
        reactorCount = reactorCount + 1
    end
    
    for address, type in component.list("transposer") do
        transposerCount = transposerCount + 1
    end
    
    print("  Найдено реакторов: " .. reactorCount)
    print("  Найдено transposer'ов: " .. transposerCount)
    
    if reactorCount == 0 then
        print("⚠ ВНИМАНИЕ: Реакторы не обнаружены!")
        print("  Убедитесь, что реакторы подключены к компьютеру")
    end
    
    if transposerCount < reactorCount then
        print("⚠ ВНИМАНИЕ: Недостаточно transposer'ов!")
        print("  Для каждого реактора нужен отдельный transposer")
    end
    
    return reactorCount > 0
end

-- Создание ярлыка для запуска
local function createShortcut()
    print("\nСоздание ярлыка для запуска...")
    
    local shortcut = [[#!/bin/lua
-- Запуск системы управления реакторами
local shell = require("shell")
shell.execute("reactor_manager.lua")
]]
    
    local file = io.open("/home/reactor.lua", "w")
    if file then
        file:write(shortcut)
        file:close()
        print("✓ Создан ярлык: /home/reactor.lua")
        print("  Для запуска используйте команду: reactor")
    end
end

-- Настройка автозапуска (опционально)
local function setupAutostart()
    print("\nНастроить автозапуск при старте компьютера? (y/n)")
    local answer = io.read()
    
    if answer:lower() == "y" then
        local autorun = [[-- Автозапуск системы управления реакторами
local shell = require("shell")
local computer = require("computer")

-- Задержка для инициализации компонентов
os.sleep(2)

print("Запуск системы управления реакторами...")
shell.execute("reactor_manager.lua")
]]
        
        local file = io.open("/autorun.lua", "w")
        if file then
            file:write(autorun)
            file:close()
            print("✓ Автозапуск настроен")
        else
            print("✗ Не удалось настроить автозапуск")
        end
    end
end

-- Основная функция установки
local function install()
    -- Проверка компонентов
    if not checkComponents() then
        print("\nУстановка прервана.")
        return false
    end
    
    -- Создание резервных копий
    local hasExisting = false
    for _, file in ipairs(files) do
        if fs.exists(file) then
            hasExisting = true
            break
        end
    end
    
    if hasExisting then
        print("\nОбнаружены существующие файлы. Создать резервные копии? (y/n)")
        local answer = io.read()
        if answer:lower() == "y" then
            backupExisting()
        end
    end
    
    -- Проверка файлов
    print("\nПроверка файлов системы...")
    local allFilesPresent = true
    for _, file in ipairs(files) do
        if not fs.exists(file) then
            print("✗ Отсутствует файл: " .. file)
            allFilesPresent = false
        else
            print("✓ " .. file)
        end
    end
    
    if not allFilesPresent then
        print("\nОШИБКА: Не все файлы системы присутствуют!")
        print("Убедитесь, что все файлы скопированы в текущую директорию")
        return false
    end
    
    -- Проверка реакторов
    checkReactors()
    
    -- Создание ярлыка
    createShortcut()
    
    -- Настройка автозапуска
    setupAutostart()
    
    print("\n=== Установка завершена! ===")
    print("\nДля запуска системы используйте одну из команд:")
    print("  reactor")
    print("  reactor_manager")
    print("\nДля получения справки смотрите README.md")
    
    return true
end

-- Запуск установки
install() 