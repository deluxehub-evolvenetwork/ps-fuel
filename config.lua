PSFuelConfig = {}

PSFuelConfig.Debug = false

PSFuelConfig.Locale = 'en'

-- Public-release security and maintenance defaults.
PSFuelConfig.Security = {
    CallbackWindowMs = 1000,
    CallbackBurst = 8,
    PersistenceWindowMs = 1000,
    RobberyGraceMs = 1500,
    DeliveryVehicleDistance = 25.0,
    RequireDeliveryDriverSeat = true,
}

PSFuelConfig.DatabaseMaintenance = {
    Enabled = true,
    TransactionRetentionDays = 120,
    AuditRetentionDays = 180,
    CleanupIntervalHours = 12,
}

PSFuelConfig.Logging = {
    Console = true,
    DatabaseAudit = true,
}

PSFuelConfig.DynamicPricing = {
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

PSFuelConfig.Pricing = {
    -- Matches the configurable global tax behaviour used by ps-fuel. The tax
    -- is included in the displayed unit price so the UI and server charge agree.
    GlobalTaxPercent = 15.0,
}

PSFuelConfig.Deliveries = {
    -- Native PS Fuel delivery job. No external haulage resource is required.
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

PSFuelConfig.AutoRestock = {
    -- Safety fallback so stations cannot remain empty when no owner runs deliveries.
    Enabled = true,
    IntervalMinutes = 30,
    Amount = 750.0,

    -- Owned stations can also auto-restock.
    RestockOwnedStations = true,

    -- If false, stations at full capacity are ignored.
    RestockOnlyWhenBelowCapacity = true,
}


PSFuelConfig.Blips = {
    Enabled = true,
    Sprite = 361,
    Colour = 2,
    PublicColour = 2,
    PlayerOwnedColour = 5,
    Scale = 0.75,
    ShortRange = true,
    Display = 4,
    Category = 1,
    ShowPublicSuffix = true,
    PublicSuffix = ' · Public',
}

PSFuelConfig.Robberies = {
    Enabled = true,
    RequiredPolice = 2,
    CooldownMinutes = 45,
    Duration = 45000,
    MinReward = 4000,
    MaxReward = 12000,
    MaxStationBalancePercent = 35,
    -- Leave blank to disable the generic dispatch event.
    DispatchEvent = 'police:server:policeAlert',
}

PSFuelConfig.Electric = {
    Enabled = true,

    -- Standard charging remains the default. Fast charging is a second,
    -- separately priced option that is only shown for vehicles configured to
    -- support it and chargers that allow it.
    ChargeSpeed = 1.25,
    PricePerFuel = 1.5,
    TransactionType = 'electric_charge',
    FastCharge = {
        Enabled = true,
        Label = 'Fast charge',
        Description = 'Higher-output charging for compatible electric vehicles.',
        ChargeSpeed = 4.0,
        PriceMultiplier = 1.65,
        TransactionType = 'electric_fast_charge',
        Accent = '#38bdf8',
        ChargersEnabledByDefault = true,
    },
    UseStationMultiplier = false,
    UseMarketMultiplier = false,
    UseGlobalTax = true,

    -- Custom charger and nozzle models supplied by cdn-fuel. They are streamed
    -- directly by ps-fuel; do not start cdn-fuel as a second resource.
    ChargerModel = `electric_charger`,
    NozzleModel = `electric_nozzle`,
    SpawnChargers = true,
    MaxCableDistance = 7.5,
    HoseLength = 5.0,
    RopeType = 1,

    Blips = {
        Enabled = false,
        Sprite = 620,
        Colour = 3,
        Scale = 0.65,
        ShortRange = true,
    },

    Models = {
        [`airtug`] = true,
        [`caddy`] = true,
        [`caddy2`] = true,
        [`caddy3`] = true,
        [`cyclone`] = true,
        [`dilettante`] = true,
        [`imorgon`] = true,
        [`iwagen`] = true,
        [`khamelion`] = true,
        [`neon`] = true,
        [`omnisegt`] = true,
        [`raiden`] = true,
        [`rcbandito`] = true,
        [`surge`] = true,
        [`tezeract`] = true,
        [`virtue`] = true,
        [`voltic`] = true,
        [`voltic2`] = true,
    },

    Chargers = {
        { id = 'strawberry_ev', stationId = 'strawberry', label = 'Strawberry Fuel EV Charger', coords = vec4(279.79, -1237.35, 28.35, 181.07) },
        { id = 'grove_ev', stationId = 'grove', label = 'Grove Street Fuel EV Charger', coords = vec4(-51.09, -1767.02, 28.26, 47.16) },
        { id = 'sandy_ev', stationId = 'sandy', label = 'Sandy Shores Fuel EV Charger', coords = vec4(1994.54, 3778.44, 31.18, 215.25) },
        { id = 'paleto_ev', stationId = 'paleto', label = 'Paleto Fuel EV Charger', coords = vec4(181.14, 6636.17, 30.61, 179.96) },
        { id = 'senora_west_ev', stationId = 'senora_west', label = 'Grand Senora Fuel EV Charger', coords = vec4(50.21, 2787.38, 56.88, 147.20) },
        { id = 'harmony_ev', stationId = 'harmony', label = 'Harmony Fuel EV Charger', coords = vec4(267.96, 2599.47, 43.69, 5.80) },
        { id = 'route68_west_ev', stationId = 'route68_west', label = 'Route 68 Fuel West EV Charger', coords = vec4(1033.32, 2662.91, 38.55, 95.38) },
        { id = 'route68_east_ev', stationId = 'route68_east', label = 'Route 68 Fuel East EV Charger', coords = vec4(1208.26, 2649.46, 36.85, 222.32) },
        { id = 'senora_east_ev', stationId = 'senora_east', label = 'Grand Senora Fuel East EV Charger', coords = vec4(2545.81, 2586.18, 36.94, 83.74) },
        { id = 'senora_freeway_ev', stationId = 'senora_freeway', label = 'Senora Freeway Fuel EV Charger', coords = vec4(2690.25, 3265.62, 54.24, 58.98) },
        { id = 'grapeseed_ev', stationId = 'grapeseed', label = 'Grapeseed Fuel EV Charger', coords = vec4(1703.57, 4937.23, 41.08, 55.74) },
        { id = 'paleto_east_ev', stationId = 'paleto_east', label = 'Paleto Bay Fuel East EV Charger', coords = vec4(1714.14, 6425.44, 31.79, 155.94) },
        { id = 'paleto_west_ev', stationId = 'paleto_west', label = 'Paleto Bay Fuel West EV Charger', coords = vec4(-98.12, 6403.39, 30.64, 141.49) },
        { id = 'chumash_ev', stationId = 'chumash', label = 'Chumash Fuel EV Charger', coords = vec4(-2570.04, 2317.10, 32.22, 21.29) },
        { id = 'richman_ev', stationId = 'richman', label = 'Richman Fuel EV Charger', coords = vec4(-1819.22, 798.51, 137.16, 315.13) },
        { id = 'morningwood_ev', stationId = 'morningwood', label = 'Morningwood Fuel EV Charger', coords = vec4(-1420.51, -278.76, 45.26, 137.35) },
        { id = 'del_perro_ev', stationId = 'del_perro', label = 'Del Perro Fuel EV Charger', coords = vec4(-2080.61, -338.52, 12.26, 352.21) },
        { id = 'little_seoul_ev', stationId = 'little_seoul', label = 'Little Seoul Fuel EV Charger', coords = vec4(-704.64, -935.71, 18.21, 90.02) },
        { id = 'la_puerta_ev', stationId = 'la_puerta', label = 'La Puerta Fuel EV Charger', coords = vec4(-514.06, -1216.25, 17.46, 66.29) },
        { id = 'cypress_flats_ev', stationId = 'cypress_flats', label = 'Cypress Flats Fuel EV Charger', coords = vec4(834.27, -1028.70, 26.16, 88.39) },
        { id = 'el_burro_ev', stationId = 'el_burro', label = 'El Burro Heights Fuel EV Charger', coords = vec4(1194.41, -1394.44, 34.37, 270.30) },
        { id = 'mirror_park_ev', stationId = 'mirror_park', label = 'Mirror Park Fuel EV Charger', coords = vec4(1168.38, -323.56, 68.30, 280.22) },
        { id = 'vinewood_ev', stationId = 'vinewood', label = 'Vinewood Fuel EV Charger', coords = vec4(633.64, 247.22, 102.30, 60.29) },
        { id = 'east_vinewood_ev', stationId = 'east_vinewood', label = 'East Vinewood Fuel EV Charger', coords = vec4(2561.24, 357.30, 107.62, 266.65) },
        { id = 'davis_ev', stationId = 'davis', label = 'Davis Fuel EV Charger', coords = vec4(175.90, -1546.65, 28.26, 224.29) },
        { id = 'sandy_airfield_ev', stationId = 'sandy_airfield', label = 'Sandy Airfield Fuel EV Charger', coords = vec4(1770.86, 3337.97, 40.43, 301.10) },
        { id = 'strawberry_south_ev', stationId = 'strawberry_south', label = 'Strawberry South Fuel EV Charger', coords = vec4(-341.63, -1459.39, 29.76, 271.73) },
    }
}


PSFuelConfig.Payment = {
    DefaultAccount = 'bank',
    AllowedAccounts = {
        bank = true,
        cash = true,
    },
    AskWhenTakingNozzle = true,
}

PSFuelConfig.Nozzles = {
    Enabled = true,
    RequireNozzle = true,
    UseOxTarget = true,
    FuelModel = `prop_cs_fuel_nozle`,
    PumpHose = true,
    RopeType = 1,
    HoseLength = 8.0,
    MaxDistance = 7.5,
    InteractionDistance = 2.0,
    VehicleTargetDistance = 3.0,
    SessionTimeoutSeconds = 300,
    BuyJerryCanAtPump = true,

    HandAttachment = {
        bone = 18905,
        fuel = { x = 0.13, y = 0.04, z = 0.01, rx = -42.0, ry = -115.0, rz = -63.42 },
        electric = { x = 0.24, y = 0.10, z = -0.052, rx = -45.0, ry = 120.0, rz = 75.0 },
    },

    VehicleBones = {
        'petrolcap',
        'petroltank',
        'petroltank_l',
        'petroltank_r',
        'wheel_lr',
        'wheel_rr',
        'boot',
    },

    VehicleAttachment = {
        fuel = { x = 0.0, y = 0.0, z = 0.0, rx = 0.0, ry = 90.0, rz = 0.0 },
        electric = { x = 0.0, y = 0.0, z = 0.0, rx = 0.0, ry = 90.0, rz = 0.0 },
    },

    Sounds = {
        Enabled = true,
        Pickup = 'pickupnozzle',
        ReturnFuel = 'putbacknozzle',
        ReturnElectric = 'putbackcharger',
        FuelLoop = 'refuel',
        FuelStop = 'fuelstop',
        ChargeLoop = 'charging',
        ChargeStop = 'chargestop',
        Volume = 0.45,
    },

    Animation = {
        -- Disabled by default: the player only takes the nozzle and inserts it
        -- into the vehicle. No pickup or refuelling animation is played.
        Enabled = false,
        PickupDict = 'anim@am_hold_up@male',
        PickupClip = 'shoplift_high',
        RefuelDict = 'timetable@gardener@filling_can',
        RefuelClip = 'gar_ig_5_filling_can',
    },

    BreakHose = {
        Enabled = true,
        ExplodePump = false,
        ExplosionChance = 100,
        ExplosionType = 5,
    },
}


PSFuelConfig.VehicleConfiguration = {
    Enabled = true,
    Command = 'fuelvehicleconfig',
    AdminAce = 'ps-fuel.admin',
    AddOxTargetOption = true,
    TargetDistance = 3.0,

    -- Runtime entries saved in the database override the static model lists in
    -- this config. Removing an override returns the model to automatic rules.
    AllowedTypes = {
        petrol = 'Petrol / Premium',
        diesel = 'Diesel',
        electric = 'Electric',
    },
    ElectricFastChargeDefault = true,
}

PSFuelConfig.WorldDisplay = {
    Enabled = true,
    HeightOffset = 1.35,
    MaxDistance = 25.0,
    Scale = 0.34,
    ShowAmountPaid = true,
    ShowFuelType = true,
}

PSFuelConfig.Safety = {
    RequireEngineOff = true,
    VehicleBlowUp = false,
    BlowUpChance = 5,
    LeaveEngineRunning = false,
    ShutOffAtFuel = 0.0,
}

PSFuelConfig.EmergencyDiscount = {
    Enabled = true,
    DiscountPercent = 25,
    OnDutyOnly = true,
    EmergencyVehiclesOnly = true,
    Jobs = {
        police = true,
        sasp = true,
        trooper = true,
        sheriff = true,
        ambulance = true,
        fire = true,
    },
}

PSFuelConfig.Leaks = {
    Enabled = true,
    MinimumImpactDamage = 120.0,
    SevereImpactDamage = 350.0,
    ChancePercent = 55,
    SevereChancePercent = 90,
    NormalDrainPerTick = 0.8,
    SevereDrainPerTick = 2.0,
    RepairCommand = 'repairfuelleak',
    -- ACE permission for the repair command. AdminAce is also accepted.
    RepairAce = 'ps-fuel.repair',
    -- Optional framework jobs and minimum grades allowed to repair leaks.
    RepairJobs = { mechanic = 0 },
}



PSFuelConfig.Ownership = {
    -- Stations inherit this when ownershipEnabled is omitted.
    DefaultEnabled = true,
    DefaultPurchasePrice = 200000,

    -- Public stations remain usable by everyone for refuelling but cannot be
    -- purchased or managed by players. Admins can still view them in the global
    -- fuel administration screen.
    AllowAdminPanelAtPublicStations = false,

    -- Only pay the owner share when a station currently has an owner.
    PublicStationsKeepOwnerShare = false,
}

PSFuelConfig.StationTablet = {
    -- The management tablet is available only after a station is purchased.
    OwnerOnly = true,
    AllowAdmin = true,
    OpenKey = 47, -- G
    PurchaseAccount = 'bank',
}

PSFuelConfig.FuelTypes = {
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


PSFuelConfig.Compatibility = {
    -- Keeps compatibility with scripts that read the original ps-fuel/LegacyFuel
    -- decorator directly instead of using the exported GetFuel function.
    UseFuelDecor = true,
    FuelDecor = '_FUEL_LEVEL',
}

PSFuelConfig.RefuelKey = 38
PSFuelConfig.CancelRefuelKey = 73 -- X stops an active refuel
PSFuelConfig.ChangeFuelTypeKey = 74 -- H reopens the selector after a fuel type is chosen
PSFuelConfig.FuelSelectionTimeout = 120000 -- selection remains valid for two minutes
PSFuelConfig.RefuelDistance = 2.5
PSFuelConfig.VehicleDistance = 5.0
PSFuelConfig.MaxFuel = 100.0
PSFuelConfig.StartFuelMin = 35.0
PSFuelConfig.StartFuelMax = 85.0
PSFuelConfig.RefuelSpeed = 1.0
PSFuelConfig.RefuelTick = 1000
PSFuelConfig.PricePerFuel = 2
PSFuelConfig.PaymentAccount = PSFuelConfig.Payment.DefaultAccount -- legacy compatibility
PSFuelConfig.PersistenceSaveInterval = 15000
PSFuelConfig.FuelDrainTick = 10000
PSFuelConfig.BaseDrain = 0.06
PSFuelConfig.RPMMultiplier = 0.12
PSFuelConfig.StationInteractionDistance = 18.0
PSFuelConfig.AdminAce = 'ps-fuel.admin'
PSFuelConfig.OwnerSharePercent = 70
PSFuelConfig.JerryCan = {
    Enabled = true,
    Item = 'weapon_petrolcan',
    Price = 350,
    FuelAmount = 25.0,
    TransactionType = 'jerrycan',
    Metadata = {
        fuel = 25.0,
        ammo = 25,
        durability = 100,
    },
}

PSFuelConfig.ClassMultiplier = {
    [0] = 1.0, [1] = 1.0, [2] = 1.15, [3] = 1.05, [4] = 1.2,
    [5] = 1.15, [6] = 1.25, [7] = 1.45, [8] = 0.65, [9] = 1.25,
    [10] = 1.6, [11] = 1.35, [12] = 1.25, [13] = 0.0, [14] = 1.2,
    [15] = 1.8, [16] = 2.0, [17] = 1.1, [18] = 1.2, [19] = 1.4,
    [20] = 1.5, [21] = 1.0
}

PSFuelConfig.PumpModels = {
    `prop_gas_pump_1a`, `prop_gas_pump_1b`, `prop_gas_pump_1c`,
    `prop_gas_pump_1d`, `prop_gas_pump_old2`, `prop_gas_pump_old3`,
    `prop_vintage_pump`
}

-- Add or edit stations here. IDs must be unique and match the SQL station_id.
-- ownershipEnabled = false creates a public station: everyone may refuel, but
-- players cannot purchase it. Change it to true and set purchasePrice when you
-- want to turn an individual public station into a player-owned business.
PSFuelConfig.Stations = {
    -- Existing player-owned stations.
    {
        id = 'strawberry', label = 'Strawberry Fuel', coords = vec3(265.64, -1261.30, 29.29),
        priceMultiplier = 1.00, purchasePrice = 250000, capacity = 10000.0,
        ownershipEnabled = true, interactionDistance = 26.0, deliveryEnabled = true,
        delivery = { coords = vec3(277.00, -1244.50, 29.20), heading = 0.0, length = 26.0, width = 9.0, requireDirection = false },
    },
    {
        id = 'grove', label = 'Grove Street Fuel', coords = vec3(-70.21, -1761.79, 29.53),
        priceMultiplier = 1.05, purchasePrice = 225000, capacity = 10000.0,
        ownershipEnabled = true, interactionDistance = 28.0, deliveryEnabled = true,
        delivery = { coords = vec3(-69.50, -1745.00, 29.30), heading = 50.0, length = 26.0, width = 9.0, requireDirection = false },
    },
    {
        id = 'sandy', label = 'Sandy Shores Fuel', coords = vec3(2005.05, 3774.15, 32.18),
        priceMultiplier = 0.95, purchasePrice = 200000, capacity = 10000.0,
        ownershipEnabled = true, interactionDistance = 30.0, deliveryEnabled = true,
        delivery = { coords = vec3(1988.50, 3787.00, 32.20), heading = 30.0, length = 26.0, width = 9.0, requireDirection = false },
    },
    {
        id = 'paleto', label = 'Paleto Fuel', coords = vec3(179.84, 6602.84, 31.87),
        priceMultiplier = 1.10, purchasePrice = 175000, capacity = 10000.0,
        ownershipEnabled = true, interactionDistance = 32.0, deliveryEnabled = true,
        delivery = { coords = vec3(155.50, 6597.50, 31.80), heading = 0.0, length = 26.0, width = 9.0, requireDirection = false },
    },

    -- Standard public GTA fuel stations. These automatically enter the fuel
    -- database on resource start and require no SQL import.
    { id = 'senora_west', label = 'Grand Senora Fuel', coords = vec3(49.4187, 2778.793, 58.043), priceMultiplier = 1.00, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 32.0 },
    { id = 'harmony', label = 'Harmony Fuel', coords = vec3(263.894, 2606.463, 44.983), priceMultiplier = 1.00, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 32.0 },
    { id = 'route68_west', label = 'Route 68 Fuel West', coords = vec3(1039.958, 2671.134, 39.550), priceMultiplier = 1.00, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 32.0 },
    { id = 'route68_east', label = 'Route 68 Fuel East', coords = vec3(1207.260, 2660.175, 37.899), priceMultiplier = 1.00, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 32.0 },
    { id = 'senora_east', label = 'Grand Senora Fuel East', coords = vec3(2539.685, 2594.192, 37.944), priceMultiplier = 1.00, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 32.0 },
    { id = 'senora_freeway', label = 'Senora Freeway Fuel', coords = vec3(2679.858, 3263.946, 55.240), priceMultiplier = 1.00, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 32.0 },
    { id = 'grapeseed', label = 'Grapeseed Fuel', coords = vec3(1687.156, 4929.392, 42.078), priceMultiplier = 0.98, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'paleto_east', label = 'Paleto Bay Fuel East', coords = vec3(1701.314, 6416.028, 32.763), priceMultiplier = 1.05, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'paleto_west', label = 'Paleto Bay Fuel West', coords = vec3(-94.4619, 6419.594, 31.489), priceMultiplier = 1.05, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'chumash', label = 'Chumash Fuel', coords = vec3(-2554.996, 2334.400, 33.078), priceMultiplier = 1.08, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 36.0 },
    { id = 'richman', label = 'Richman Fuel', coords = vec3(-1800.375, 803.661, 138.651), priceMultiplier = 1.12, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'morningwood', label = 'Morningwood Fuel', coords = vec3(-1437.622, -276.747, 46.207), priceMultiplier = 1.08, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 32.0 },
    { id = 'del_perro', label = 'Del Perro Fuel', coords = vec3(-2096.243, -320.286, 13.168), priceMultiplier = 1.08, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'little_seoul', label = 'Little Seoul Fuel', coords = vec3(-724.619, -935.163, 19.213), priceMultiplier = 1.05, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'la_puerta', label = 'La Puerta Fuel', coords = vec3(-526.019, -1211.003, 18.184), priceMultiplier = 1.02, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'cypress_flats', label = 'Cypress Flats Fuel', coords = vec3(819.653, -1028.846, 26.403), priceMultiplier = 1.00, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'el_burro', label = 'El Burro Heights Fuel', coords = vec3(1208.951, -1402.567, 35.224), priceMultiplier = 1.00, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'mirror_park', label = 'Mirror Park Fuel', coords = vec3(1181.381, -330.847, 69.316), priceMultiplier = 1.05, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'vinewood', label = 'Vinewood Fuel', coords = vec3(620.843, 269.100, 103.089), priceMultiplier = 1.10, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'east_vinewood', label = 'East Vinewood Fuel', coords = vec3(2581.321, 362.039, 108.468), priceMultiplier = 1.05, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'davis', label = 'Davis Fuel', coords = vec3(176.631, -1562.025, 29.263), priceMultiplier = 1.00, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 32.0 },
    { id = 'sandy_airfield', label = 'Sandy Airfield Fuel', coords = vec3(1784.324, 3330.550, 41.253), priceMultiplier = 0.98, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
    { id = 'strawberry_south', label = 'Strawberry South Fuel', coords = vec3(-319.292, -1471.715, 30.549), priceMultiplier = 1.00, capacity = 15000.0, ownershipEnabled = false, deliveryEnabled = false, interactionDistance = 34.0 },
}

