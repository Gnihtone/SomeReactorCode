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
        "gregtech:gt.glowstoneCell",
        "gregtech:gt.reactorUraniumQuad",
        "gregtech:gt.reactorMOXQuad",
        "gregtech:gt.Quad_Naquadahcell",
        "gregtech:gt.Quad_MNqCell",
        "bartworks:gt.Quad_Tiberiumcell",
        "bartworks:gt.Core_Reactor_Cell",
        "GoodGenerator:rodLiquidPlutonium4",
        "GoodGenerator:rodLiquidUranium4",
        "GoodGenerator:rodCompressedPlutonium4",
        "GoodGenerator:rodCompressedUranium4",
    },

    -- Истощенные топливные стержни
    DEPLETED_FUEL_RODS = {
        "gregtech:gt.sunnariumCell",
        "IC2:reactorUraniumQuaddepleted",
        "IC2:reactorMOXQuaddepleted",
        "gregtech:gt.Quad_NaquadahcellDep",
        "gregtech:gt.Quad_MNqCellDep",
        "bartworks:gt.Quad_TiberiumcellDep",
        "bartworks:gt.Core_Reactor_CellDep",
        "GoodGenerator:rodLiquidPlutoniumDepleted4",
        "GoodGenerator:rodLiquidUraniumDepleted4",
        "GoodGenerator:rodCompressedPlutoniumDepleted4",
        "GoodGenerator:rodCompressedUraniumDepleted4",
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
    ENERGY_STORAGE_UPDATE = "ENERGY_STORAGE_UPDATE",  -- Обновление состояния энергохранилищ
    
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
    UPDATE_CONFIG = "UPDATE_CONFIG",
    PAUSE_FOR_ENERGY_FULL = "PAUSE_FOR_ENERGY_FULL",  -- Пауза из-за переполнения энергохранилища
    RESUME_FROM_ENERGY_PAUSE = "RESUME_FROM_ENERGY_PAUSE"  -- Возобновление после освобождения энергохранилища
}

-- Настройки сторон transposer
config.SIDES = {
    REACTOR = 3,  -- front
    ME_SYSTEM = 2,  -- back
    BACKUP_STORAGE = 0  -- bottom (для аварийного хранения)
}

-- Настройки энергохранилищ
config.ENERGY_STORAGE = {
    UPDATE_INTERVAL = 2,  -- Интервал обновления состояния (секунды)
    FULL_THRESHOLD = 0.99,  -- Порог заполнения для остановки реакторов (99%)
    RESUME_THRESHOLD = 0.95,  -- Порог заполнения для возобновления работы (95%)
    SUPPORTED_TYPES = {  -- Поддерживаемые типы энергохранилищ Gregtech
        "gregtech_machine",
        "gt_batterybuffer",
        "gt_storage"
    }
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