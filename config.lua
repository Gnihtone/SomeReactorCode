local config = {}

config.REACTOR_STATUS = {
    OFFLINE = "OFFLINE",
    IDLE = "IDLE",
    RUNNING = "RUNNING",
    EMERGENCY = "EMERGENCY",
    MAINTENANCE = "MAINTENANCE",
}

config.NETWORK = {
    PORT = 1337,
    PROTOCOL = "VACUUM_REACTOR_NET",
    TIMEOUT = 5,
    RELAY_STRENGTH = 400,
    HEARTBEAT_INTERVAL = 2,
    CONNECTION_TIMEOUT = 10,

    CLIENT_TYPES = {
        REACTOR_CLIENT = "reactor_client",
        ENERGY_STORAGE_CLIENT = "energy_storage_client"
    }
}

config.MESSAGES = {
    REGISTER = "REGISTER",
    UNREGISTER = "UNREGISTER",
    STATUS_UPDATE = "STATUS_UPDATE",
    LOG = "LOG",
    ENERGY_STORAGE_UPDATE = "ENERGY_STORAGE_UPDATE",
    ACK = "ACK",
    COMMAND = "COMMAND",
    CONFIG_UPDATE = "CONFIG_UPDATE"
}

config.COMMANDS = {
    -- COMMON
    DISCOVER = "DISCOVER",

    -- REACTOR
    START = "START",
    STOP = "STOP",
    FORCE_MAINTENANCE = "FORCE_MAINTENANCE",
    CLEAR_REACTOR = "CLEAR_REACTOR",
    
    -- ENERGY STORAGE
    REFRESH_STORAGES = "REFRESH_STORAGES"
}

return config
