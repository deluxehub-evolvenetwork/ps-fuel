Config = {}

Config.Debug = false

Config.Locale = 'en'

Config.DynamicPricing = {
    Enabled = true,
    UpdateMinutes = 30,
    MinMarketMultiplier = 0.80,
    MaxMarketMultiplier = 1.35,
    RandomStep = 0.08,
    LowStockThreshold = 2500.0,
    LowStockSurcharge = 0.20,
    HighStockThreshold = 8500.0,
    HighStockDiscount = 0.10,
}

Config.Deliveries = {
    Enabled = true,

    -- Only the owner of the selected station can start its delivery job.
    OwnerOnly = true,

    RequiredJob = false,
    TruckModel = 'phantom',
    TrailerModel = 'tanker',

    DeliveryAmount = 2500.0,
    RewardMin = 2500,
    RewardMax = 4500,
    CooldownMinutes = 15,

    -- Player is teleported here when starting the job.
    Pickup = vec4(1722.22, -1638.15, 112.47, 190.0),

    -- Delivery vehicle spawn positions.
    TruckSpawn = vec4(1712.50, -1642.10, 112.45, 190.0),
    TrailerSpawn = vec4(1699.90, -1648.50, 112.43, 190.0),

    -- The driver must take the tanker here and fill it before returning.
    LoadingTerminal = {
        Label = 'Fuel Loading Terminal',
        Coords = vec3(2777.53, 1487.82, 24.52),
        Radius = 18.0,
        FillDuration = 30000,
        BlipSprite = 478,
        BlipColour = 5,
        BlipScale = 0.85,
    },

    MaxDeliveryDistance = 35.0,
    AutoAttachTrailer = true,
    DeleteVehiclesOnComplete = true,
}

Config.AutoRestock = {
    Enabled = true,
    IntervalMinutes = 30,
    Amount = 750.0,

    -- Owned stations can also auto-restock.
    RestockOwnedStations = true,

    -- If false, stations at full capacity are ignored.
    RestockOnlyWhenBelowCapacity = true,
}

Config.Blips = {
    Enabled = true,
    Sprite = 361,
    Colour = 2,
    Scale = 0.75,
    ShortRange = true,
    Display = 4,
}

Config.Robberies = {
    Enabled = true,
    RequiredPolice = 2,
    CooldownMinutes = 45,
    Duration = 45000,
    MinReward = 4000,
    MaxReward = 12000,
    MaxStationBalancePercent = 35,
    DispatchEvent = 'police:server:policeAlert',
}

Config.Electric = {
    Enabled = true,
    ChargeSpeed = 1.25,
    PricePerFuel = 1.5,
    Models = {
        [`cyclone`] = true,
        [`dilettante`] = true,
        [`imorgon`] = true,
        [`iwagen`] = true,
        [`khamelion`] = true,
        [`neon`] = true,
        [`omnisegt`] = true,
        [`raiden`] = true,
        [`surge`] = true,
        [`tezeract`] = true,
        [`virtue`] = true,
        [`voltic`] = true,
        [`voltic2`] = true,
    },
    Chargers = {
        { id = 'pillbox_ev', label = 'Pillbox EV Charging', coords = vec3(307.45, -770.32, 29.31) },
        { id = 'vinewood_ev', label = 'Vinewood EV Charging', coords = vec3(621.13, 269.17, 103.09) },
        { id = 'sandy_ev', label = 'Sandy EV Charging', coords = vec3(1981.74, 3779.29, 32.18) },
    }
}

Config.Leaks = {
    Enabled = true,
    MinimumImpactDamage = 120.0,
    SevereImpactDamage = 350.0,
    ChancePercent = 55,
    SevereChancePercent = 90,
    NormalDrainPerTick = 0.8,
    SevereDrainPerTick = 2.0,
    RepairCommand = 'repairfuelleak',
}


Config.StationTablet = {
    -- The management tablet is available only after a station is purchased.
    OwnerOnly = true,
    AllowAdmin = true,
    OpenKey = 47, -- G
    PurchaseAccount = 'bank',
}

Config.FuelTypes = {
    Default = 'petrol',
    petrol = {
        label = 'Petrol',
        description = 'Regular unleaded for standard road vehicles.',
        priceMultiplier = 1.00,
        transactionType = 'fuel_petrol',
        accent = '#18d8e8',
    },
    premium = {
        label = 'Premium',
        description = 'High-octane unleaded for performance vehicles.',
        priceMultiplier = 1.35,
        transactionType = 'fuel_premium',
        accent = '#a78bfa',
    },
    diesel = {
        label = 'Diesel',
        description = 'Commercial diesel for configured heavy vehicles.',
        priceMultiplier = 1.12,
        transactionType = 'fuel_diesel',
        accent = '#f59e0b',

        -- GTA does not expose a universal fuel type. These classes and models
        -- are configurable so custom vehicles can be assigned correctly.
        AllowedClasses = {
            [10] = true, -- industrial
            [11] = true, -- utility
            [12] = true, -- vans
            [20] = true, -- commercial
        },
        Models = {
            [`benson`] = true, [`biff`] = true, [`hauler`] = true,
            [`hauler2`] = true, [`mule`] = true, [`mule2`] = true,
            [`mule3`] = true, [`mule4`] = true, [`packer`] = true,
            [`phantom`] = true, [`phantom3`] = true, [`pounder`] = true,
            [`pounder2`] = true, [`stockade`] = true,
        },
    },
}

Config.RefuelKey = 38
Config.RefuelDistance = 2.5
Config.VehicleDistance = 5.0
Config.MaxFuel = 100.0
Config.StartFuelMin = 35.0
Config.StartFuelMax = 85.0
Config.RefuelSpeed = 1.0
Config.RefuelTick = 1000
Config.PricePerFuel = 2
Config.PaymentAccount = 'bank' -- cash or bank
Config.PersistenceSaveInterval = 15000
Config.FuelDrainTick = 10000
Config.BaseDrain = 0.06
Config.RPMMultiplier = 0.12
Config.StationInteractionDistance = 18.0
Config.AdminAce = 'recoilfuel.admin'
Config.OwnerSharePercent = 70
Config.JerryCan = {
    Enabled = true,
    Item = 'weapon_petrolcan',
    Price = 350,
    FuelAmount = 25.0,
}

Config.ClassMultiplier = {
    [0] = 1.0, [1] = 1.0, [2] = 1.15, [3] = 1.05, [4] = 1.2,
    [5] = 1.15, [6] = 1.25, [7] = 1.45, [8] = 0.65, [9] = 1.25,
    [10] = 1.6, [11] = 1.35, [12] = 1.25, [13] = 0.0, [14] = 1.2,
    [15] = 1.8, [16] = 2.0, [17] = 1.1, [18] = 1.2, [19] = 1.4,
    [20] = 1.5, [21] = 1.0
}

Config.PumpModels = {
    `prop_gas_pump_1a`, `prop_gas_pump_1b`, `prop_gas_pump_1c`,
    `prop_gas_pump_1d`, `prop_gas_pump_old2`, `prop_gas_pump_old3`,
    `prop_vintage_pump`
}

-- Add or edit stations here. IDs must be unique and match the SQL station_id.
Config.Stations = {
    { id = 'strawberry', label = 'Strawberry Fuel', coords = vec3(265.64, -1261.30, 29.29), priceMultiplier = 1.00, purchasePrice = 250000, capacity = 10000.0 },
    { id = 'grove', label = 'Grove Street Fuel', coords = vec3(-70.21, -1761.79, 29.53), priceMultiplier = 1.05, purchasePrice = 225000, capacity = 10000.0 },
    { id = 'sandy', label = 'Sandy Shores Fuel', coords = vec3(2005.05, 3774.15, 32.18), priceMultiplier = 0.95, purchasePrice = 200000, capacity = 10000.0 },
    { id = 'paleto', label = 'Paleto Fuel', coords = vec3(179.84, 6602.84, 31.87), priceMultiplier = 1.10, purchasePrice = 175000, capacity = 10000.0 },
}
