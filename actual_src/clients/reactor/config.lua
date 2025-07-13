local config = {}

config.REACTOR = {
    MAX_TEMPERATURE = 10000,
    COOLANT_MIN_DAMAGE = 0.1,
    UPDATE_INTERVAL = 0.1
}

config.ITEMS = {
    EMERGENCY_COOLANTS = {
        "IC2:reactorVentGold",
        "IC2:reactorVentDiamond",
        "IC2:reactorVentSpread"
    },

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

    BREEDER_RODS = {
        "gregtech:gt.glowstoneCell",
    },
    
    DEPLETED_BREEDER_RODS = {
        "gregtech:gt.sunnariumCell",
    },
    
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

return config
