local config = {}

config.DISCORD = {
    ENABLED = false,
    BOT_TOKEN = "",
    CHANNEL_ID = "1393349403204522065",
    LOG_CHANNEL_ID = "1393349373630349383",
    COMMAND_PREFIX = "!",
    UPDATE_INTERVAL = 30,
    POLL_INTERVAL = 2,
    LOG_LEVELS = {
        WARNING = true,
        ERROR = true,
        CRITICAL = true
    },
    NOTIFICATIONS = {
        REACTOR_START = true,
        REACTOR_STOP = true,
        EMERGENCY = true,
        MAINTENANCE = true,
        ENERGY_PAUSE = true,
        SYSTEM_STATUS = true
    }
}

config.ENERGY_STORAGE = {
    FULL_THRESHOLD = 0.99,
    RESUME_THRESHOLD = 0.95
}

config.UI = {
    UPDATE_INTERVAL = 0.5,
    LOG_MAX_LINES = 15,
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

return config
