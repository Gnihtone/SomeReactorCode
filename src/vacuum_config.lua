-- Конфигурация распределенной системы управления вакуумными реакторами
local config = {}

-- Сетевые настройки
config.NETWORK = {
    PORT = 1337,  -- Порт для беспроводной связи
    PROTOCOL = "VACUUM_REACTOR_NET",  -- Идентификатор протокола
    TIMEOUT = 5,  -- Таймаут ожидания ответа (секунды)
    RELAY_STRENGTH = 400,  -- Сила сигнала для реле
    HEARTBEAT_INTERVAL = 2,  -- Интервал отправки данных (секунды)
    CONNECTION_TIMEOUT = 10  -- Таймаут потери связи (секунды)
}

-- Настройки реактора
config.REACTOR = {
    UPDATE_INTERVAL = 0.5,  -- Интервал обновления состояния (секунды)
    CRITICAL_TEMP_PERCENT = 0.85,  -- Критическая температура для аварийного охлаждения (85%)
    WARNING_TEMP_PERCENT = 0.7,  -- Предупреждение о температуре (70%)
    COOLANT_MIN_DAMAGE = 0.9,  -- Минимальный уровень повреждения coolant cell (90%)
    EMERGENCY_COOLDOWN_TIME = 60,  -- Время аварийного охлаждения (секунды)
    MAX_REACTOR_NAME_LENGTH = 20,  -- Максимальная длина имени реактора
    AUTO_MAINTENANCE = true,  -- Автоматическое обслуживание
    MAINTENANCE_CHECK_INTERVAL = 10  -- Интервал проверки необходимости обслуживания (секунды)
}

-- Предметы для управления реактором
config.ITEMS = {
    -- Охлаждающие элементы для аварийного режима
    EMERGENCY_COOLANTS = {
        "IC2:reactorVentGold",  -- Overclocked Heat Vent
        "IC2:reactorVentDiamond",  -- Advanced Heat Vent
        "IC2:reactorVentSpread"  -- Component Heat Vent
    },
    
    -- Стандартные охлаждающие элементы
    COOLANT_CELLS = {
        "IC2:reactorCoolantSimple",
        "IC2:reactorCoolantTriple", 
        "IC2:reactorCoolantSix",
        "gregtech:gt.360k_NaK_Coolantcell",
        "gregtech:gt.360k_Helium_Coolantcell",
        "gregtech:gt.180k_NaK_Coolantcell",
        "gregtech:gt.180k_Helium_Coolantcell",
        "gregtech:gt.60k_NaK_Coolantcell",
        "gregtech:gt.60k_Helium_Coolantcell"
    },
    
    -- Топливные стержни
    FUEL_RODS = {
        "IC2:reactorUraniumQuad",
        "IC2:reactorMOXQuad",
        "gregtech:gt.Thoriumcell",
        "gregtech:gt.ThoriumDoublecell", 
        "gregtech:gt.ThoriumQuadcell",
        "gregtech:gt.NaquadahDoublecell",
        "gregtech:gt.NaquadahQuadcell",
        "gregtech:gt.MNqDoublecell",
        "gregtech:gt.MNqQuadcell"
    }
}

-- Настройки интерфейса
config.UI = {
    UPDATE_INTERVAL = 0.5,  -- Интервал обновления интерфейса
    LOG_MAX_LINES = 15,  -- Максимальное количество строк в логе
    COLORS = {
        BACKGROUND = 0x0a0a0a,
        FOREGROUND = 0xffffff,
        HEADER = 0x00a0ff,
        BORDER = 0x333333,
        STATUS_OK = 0x00ff00,
        STATUS_WARNING = 0xffaa00,
        STATUS_ERROR = 0xff0000,
        STATUS_OFFLINE = 0x666666,
        EMERGENCY = 0xff00ff,
        HIGHLIGHT = 0x00ffff
    },
    SYMBOLS = {
        OK = "✓",
        WARNING = "⚠",
        ERROR = "✗",
        OFFLINE = "◌",
        EMERGENCY = "☢",
        TEMPERATURE = "🌡",
        ENERGY = "⚡"
    }
}

-- Типы сообщений протокола
config.MESSAGES = {
    -- От клиента к серверу
    REGISTER = "REGISTER",  -- Регистрация клиента
    UNREGISTER = "UNREGISTER",  -- Отключение клиента
    STATUS_UPDATE = "STATUS_UPDATE",  -- Обновление статуса реактора
    EMERGENCY = "EMERGENCY",  -- Аварийная ситуация
    LOG = "LOG",  -- Лог-сообщение
    
    -- От сервера к клиенту
    ACK = "ACK",  -- Подтверждение
    COMMAND = "COMMAND",  -- Команда управления
    CONFIG_UPDATE = "CONFIG_UPDATE"  -- Обновление конфигурации
}

-- Команды управления
config.COMMANDS = {
    START = "START",
    STOP = "STOP",
    EMERGENCY_STOP = "EMERGENCY_STOP",
    CLEAR_EMERGENCY = "CLEAR_EMERGENCY",
    UPDATE_CONFIG = "UPDATE_CONFIG"
}

-- Настройки сторон transposer
config.SIDES = {
    REACTOR = 3,  -- front
    ME_SYSTEM = 2,  -- back
    BACKUP_STORAGE = 0  -- bottom (для аварийного хранения)
}

-- Уровни логирования
config.LOG_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARNING = 3,
    ERROR = 4,
    CRITICAL = 5
}

-- Текущий уровень логирования
config.CURRENT_LOG_LEVEL = config.LOG_LEVELS.INFO

return config 