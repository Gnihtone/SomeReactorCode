-- Конфигурация системы управления реакторами
local config = {}

-- Основные настройки
config.UPDATE_INTERVAL = 0.5  -- Интервал обновления (в секундах, 10 тиков = 0.5 секунды)
config.COOLANT_MIN_DAMAGE = 0.9  -- Минимальный уровень повреждения coolant cell для замены (90% повреждения = 10% прочности)
config.REACTOR_MAX_TEMP_PERCENT = 0.9  -- Максимальная температура реактора (90% от максимума)
config.LSC_MAX_CHARGE_PERCENT = 0.99  -- Максимальный заряд LSC для остановки реакторов (99%)
config.RETRY_DELAY = 30  -- Задержка повторной попытки заполнения реактора (в секундах)

-- Настройки интерфейса
config.UI_UPDATE_INTERVAL = 0.25  -- Интервал обновления интерфейса (в секундах)
config.LOG_MAX_LINES = 20  -- Максимальное количество строк в логе
config.COLORS = {
    BACKGROUND = 0x1a1a1a,
    FOREGROUND = 0xffffff,
    STATUS_OK = 0x00ff00,
    STATUS_WARNING = 0xffff00,
    STATUS_ERROR = 0xff0000,
    BORDER = 0x444444,
    HEADER = 0x0080ff
}

-- Настройки компонентов
config.TRANSPOSER_SIDES = {
    REACTOR = 0,  -- Сторона, где находится реактор
    ME_SYSTEM = 1  -- Сторона, где находится ME система
}

-- Типы предметов для реакторов
config.ITEM_TYPES = {
    URANIUM_ROD = "IC2:reactorUraniumQuad",
    MOX_ROD = "IC2:reactorMOXQuad",
    THORIUM_ROD = "gregtech:gt.Thoriumcell",
    DEPLETED_ROD = "IC2:reactorUraniumQuaddepleted",
    COOLANT_CELL = {
        "IC2:reactorCoolantSimple",
        "IC2:reactorCoolantTriple",
        "IC2:reactorCoolantSix"
    }
}

-- Настройки логирования
config.LOG_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARNING = 3,
    ERROR = 4,
    FATAL = 5
}
config.CURRENT_LOG_LEVEL = config.LOG_LEVELS.INFO

return config 