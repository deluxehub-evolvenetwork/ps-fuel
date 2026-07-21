local stations = {}
local paymentCooldown = {}
local marketMultiplier = 1.0
local deliveryCooldowns = {}
local activeDeliveries = {}
local robberyCooldowns = {}

local function getPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

local function getCitizenId(player)
    return player and player.PlayerData and player.PlayerData.citizenid
end

local function stationConfig(id)
    for i = 1, #Config.Stations do
        if Config.Stations[i].id == id then return Config.Stations[i] end
    end
end

local function isNearStation(src, station)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - station.coords) <= Config.StationInteractionDistance
end

local function notify(src, description, kind)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'PS Fuel',
        description = description,
        type = kind or 'inform'
    })
end

local function removePlayerMoney(player, account, amount, reason)
    if not player or not player.PlayerData or not player.PlayerData.money then
        return false
    end

    local before = tonumber(player.PlayerData.money[account]) or 0
    if before < amount then
        return false
    end

    local result = player.Functions.RemoveMoney(account, amount, reason)

    -- Some Qbox versions return nil on success; only an explicit false is failure.
    if result == false then
        return false
    end

    return true
end

local function fuelTypeConfig(fuelType)
    fuelType = tostring(fuelType or (Config.FuelTypes and Config.FuelTypes.Default) or 'petrol'):lower()
    local config = Config.FuelTypes and Config.FuelTypes[fuelType]
    if type(config) ~= 'table' then return nil, nil end
    return fuelType, config
end

local function fuelUnitPrice(station, electric, fuelType)
    local stock = tonumber(station and station.stock) or 0
    local stockMult = 1.0

    if Config.DynamicPricing and Config.DynamicPricing.Enabled then
        if stock <= Config.DynamicPricing.LowStockThreshold then
            stockMult = 1.0 + Config.DynamicPricing.LowStockSurcharge
        elseif stock >= Config.DynamicPricing.HighStockThreshold then
            stockMult = 1.0 - Config.DynamicPricing.HighStockDiscount
        end
    end

    local base = electric and Config.Electric.PricePerFuel or Config.PricePerFuel
    local typeMultiplier = 1.0

    if not electric then
        local _, typeConfig = fuelTypeConfig(fuelType)
        if typeConfig then typeMultiplier = tonumber(typeConfig.priceMultiplier) or 1.0 end
    end

    return base
        * (tonumber(station and station.price_multiplier) or 1.0)
        * marketMultiplier
        * stockMult
        * typeMultiplier
end

local function canAccessStationTablet(src, player, station)
    if not player or not station then return false, false, false end
    local isOwner = station.owner_citizenid == getCitizenId(player)
    local isAdmin = Config.StationTablet.AllowAdmin and IsPlayerAceAllowed(src, Config.AdminAce) or false
    local allowed = isOwner or isAdmin or Config.StationTablet.OwnerOnly == false
    return allowed, isOwner, isAdmin
end

local function vehicleFuelTypeAllowed(vehicle, fuelType, reportedVehicleClass)
    if vehicle == 0 or GetEntityType(vehicle) ~= 2 then return false end
    local model = GetEntityModel(vehicle)
    if Config.Electric and Config.Electric.Models and Config.Electric.Models[model] == true then
        return false
    end

    -- GetVehicleClass is a client native and is not available in the server
    -- runtime. The client sends the class with the purchase request while the
    -- server still resolves and validates the actual networked vehicle/model.
    local class = tonumber(reportedVehicleClass)
    if class then
        class = math.floor(class)
        if class < 0 or class > 22 then class = nil end
    end

    local diesel = Config.FuelTypes and Config.FuelTypes.diesel or {}
    local dieselVehicle = (diesel.Models and diesel.Models[model] == true)
        or (class ~= nil and diesel.AllowedClasses and diesel.AllowedClasses[class] == true)

    if fuelType == 'diesel' then return dieselVehicle end
    return not dieselVehicle and (fuelType == 'petrol' or fuelType == 'premium')
end

local function serialiseFuelTypes(station)
    local result = {}
    for key, data in pairs(Config.FuelTypes or {}) do
        if type(data) == 'table' then
            result[#result + 1] = {
                id = key,
                label = data.label or key,
                description = data.description or '',
                accent = data.accent or '#18d8e8',
                priceMultiplier = tonumber(data.priceMultiplier) or 1.0,
                unitPrice = fuelUnitPrice(station, false, key),
            }
        end
    end
    table.sort(result, function(a, b)
        local order = { petrol = 1, premium = 2, diesel = 3 }
        return (order[a.id] or 99) < (order[b.id] or 99)
    end)
    return result
end

local function loadStations()
    local rows = MySQL.query.await('SELECT * FROM ps_fuel_stations') or {}
    local byId = {}
    for _, row in ipairs(rows) do byId[row.station_id] = row end

    for _, cfg in ipairs(Config.Stations) do
        local row = byId[cfg.id]
        if not row then
            MySQL.insert.await([[INSERT INTO ps_fuel_stations
                (station_id, label, owner_citizenid, owner_name, balance, price_multiplier, total_sales, total_litres, stock, capacity)
                VALUES (?, ?, NULL, NULL, 0, ?, 0, 0, ?, ?)]], {
                    cfg.id,
                    cfg.label,
                    cfg.priceMultiplier or 1.0,
                    cfg.capacity or 10000.0,
                    cfg.capacity or 10000.0
                })
            row = {
                station_id = cfg.id, label = cfg.label, owner_citizenid = nil,
                owner_name = nil, balance = 0, price_multiplier = cfg.priceMultiplier or 1.0,
                total_sales = 0,
                total_litres = 0,
                stock = cfg.capacity or 10000.0,
                capacity = cfg.capacity or 10000.0
            }
        end
        row.stock = tonumber(row.stock) or tonumber(cfg.capacity) or 10000.0
        row.capacity = tonumber(row.capacity) or tonumber(cfg.capacity) or 10000.0
        stations[cfg.id] = row
    end
end

CreateThread(function()
    Wait(1000)
    loadStations()
end)

lib.callback.register('ps-fuel:server:getVehicleFuel', function(_, plate)
    if type(plate) ~= 'string' or plate == '' then return nil end
    return MySQL.single.await('SELECT fuel, leak_level FROM ps_fuel_vehicles WHERE plate = ?', { plate })
end)

RegisterNetEvent('ps-fuel:server:saveVehicleFuel', function(plate, fuel, leakLevel)
    if type(plate) ~= 'string' then return end
    fuel = tonumber(fuel)
    leakLevel = math.max(0, math.min(2, tonumber(leakLevel) or 0))
    if not fuel then return end
    fuel = math.max(0, math.min(Config.MaxFuel, fuel))
    MySQL.prepare.await([[INSERT INTO ps_fuel_vehicles (plate, fuel, leak_level, updated_at)
        VALUES (?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE
        fuel = VALUES(fuel), leak_level = VALUES(leak_level), updated_at = NOW()]],
        { plate, fuel, leakLevel })
end)

lib.callback.register('ps-fuel:server:purchaseFuel', function(src, stationId, netId, fuelAmount, fuelType, vehicleClass)
    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    fuelAmount = tonumber(fuelAmount)
    netId = tonumber(netId)
    local selectedFuelType, selectedFuelConfig = fuelTypeConfig(fuelType)

    if not player or not cfg or not station or not selectedFuelType or not selectedFuelConfig
        or not fuelAmount or fuelAmount <= 0 or fuelAmount > 10
    then
        return { success = false, message = 'Invalid fuel purchase.' }
    end
    if not isNearStation(src, cfg) then
        return { success = false, message = 'You are too far away from the fuel station.' }
    end

    local now = GetGameTimer()
    if now - (paymentCooldown[src] or 0) < 350 then
        return { success = false, message = 'Please slow down.' }
    end
    paymentCooldown[src] = now

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or GetEntityType(vehicle) ~= 2 then
        return { success = false, message = 'Vehicle not found.' }
    end
    if not vehicleFuelTypeAllowed(vehicle, selectedFuelType, vehicleClass) then
        return { success = false, message = 'That fuel type is not compatible with this vehicle.' }
    end

    local playerPed = GetPlayerPed(src)
    if playerPed == 0 or #(GetEntityCoords(playerPed) - GetEntityCoords(vehicle)) > (Config.VehicleDistance + 3.0) then
        return { success = false, message = 'The vehicle is too far away from the pump.' }
    end

    local stock = tonumber(station.stock) or 0
    if stock < fuelAmount then
        return { success = false, message = 'This station is out of fuel.' }
    end

    local price = math.max(1, math.ceil(fuelAmount * fuelUnitPrice(station, false, selectedFuelType)))
    local balance = tonumber(player.PlayerData.money[Config.PaymentAccount]) or 0
    if balance < price then
        return { success = false, message = ('You need £%s more.'):format(price - balance) }
    end

    if not removePlayerMoney(player, Config.PaymentAccount, price, 'ps-fuel-purchase') then
        return {
            success = false,
            message = ('Payment failed from %s account.'):format(Config.PaymentAccount)
        }
    end

    local ownerCut = math.floor(price * (Config.OwnerSharePercent / 100))
    MySQL.update.await([[UPDATE ps_fuel_stations
        SET balance = balance + ?, total_sales = total_sales + ?, total_litres = total_litres + ?,
            stock = GREATEST(0, stock - ?)
        WHERE station_id = ?]], { ownerCut, price, fuelAmount, fuelAmount, stationId })

    local charinfo = player.PlayerData.charinfo or {}
    local playerName = (((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s*(.-)%s*$', '%1'))
    if playerName == '' then playerName = player.PlayerData.name or 'Unknown' end

    MySQL.insert.await([[INSERT INTO ps_fuel_transactions
        (station_id, citizenid, player_name, amount_paid, fuel_amount, transaction_type)
        VALUES (?, ?, ?, ?, ?, ?)]], {
        stationId,
        getCitizenId(player),
        playerName,
        price,
        fuelAmount,
        selectedFuelConfig.transactionType or ('fuel_' .. selectedFuelType)
    })

    station.balance = (tonumber(station.balance) or 0) + ownerCut
    station.total_sales = (tonumber(station.total_sales) or 0) + price
    station.total_litres = (tonumber(station.total_litres) or 0) + fuelAmount
    station.stock = math.max(0, (tonumber(station.stock) or 0) - fuelAmount)

    return { success = true, price = price, station = stationId, fuelType = selectedFuelType, unitPrice = fuelUnitPrice(station, false, selectedFuelType) }
end)

lib.callback.register('ps-fuel:server:buyJerryCan', function(src, stationId)
    if not Config.JerryCan.Enabled then return { success = false, message = 'Jerry cans are disabled.' } end
    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    if not player or not cfg or not isNearStation(src, cfg) then
        return { success = false, message = 'You are too far away.' }
    end

    local price = Config.JerryCan.Price
    if (tonumber(player.PlayerData.money[Config.PaymentAccount]) or 0) < price then
        return { success = false, message = 'You cannot afford a jerry can.' }
    end
    if not removePlayerMoney(player, Config.PaymentAccount, price, 'ps-fuel-jerrycan') then
        return { success = false, message = 'Payment failed.' }
    end

    local added = player.Functions.AddItem(Config.JerryCan.Item, 1, false, {
        durability = Config.JerryCan.FuelAmount,
        ammo = Config.JerryCan.FuelAmount
    })
    if not added then
        player.Functions.AddMoney(Config.PaymentAccount, price, 'ps-fuel-jerrycan-refund')
        return { success = false, message = 'You cannot carry the jerry can.' }
    end

    MySQL.insert.await([[INSERT INTO ps_fuel_transactions
        (station_id, citizenid, player_name, amount_paid, fuel_amount, transaction_type)
        VALUES (?, ?, ?, ?, 0, 'jerrycan')]], {
        stationId, getCitizenId(player), player.PlayerData.name or 'Unknown', price
    })
    return { success = true, price = price }
end)

lib.callback.register('ps-fuel:server:getStationPanel', function(src, stationId)
    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    if not player or not cfg or not station or not isNearStation(src, cfg) then return nil end

    local allowed, isOwner, isAdmin = canAccessStationTablet(src, player, station)
    if not allowed then return nil end
    local recent = MySQL.query.await([[SELECT transaction_type, amount_paid, fuel_amount, player_name, created_at
        FROM ps_fuel_transactions WHERE station_id = ? ORDER BY id DESC LIMIT 20]], { stationId }) or {}

    return {
        id = stationId,
        label = station.label or cfg.label,
        owner = station.owner_name,
        owned = station.owner_citizenid ~= nil,
        isOwner = isOwner,
        isAdmin = isAdmin,
        balance = tonumber(station.balance) or 0,
        totalSales = tonumber(station.total_sales) or 0,
        totalFuel = tonumber(station.total_litres) or 0,
        priceMultiplier = tonumber(station.price_multiplier) or 1.0,
        purchasePrice = cfg.purchasePrice,
        jerryCanPrice = Config.JerryCan.Price,
        stock = tonumber(station.stock) or 0,
        capacity = tonumber(station.capacity) or cfg.capacity or 10000,
        marketMultiplier = marketMultiplier,
        unitPrice = fuelUnitPrice(station, false, Config.FuelTypes.Default),
        fuelTypes = serialiseFuelTypes(station),
        deliveriesEnabled = Config.Deliveries.Enabled,
        robberiesEnabled = Config.Robberies.Enabled,
        transactions = recent
    }
end)

lib.callback.register('ps-fuel:server:getStationAccess', function(src, stationId)
    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    if not player or not cfg or not station or not isNearStation(src, cfg) then return nil end

    local allowed, isOwner, isAdmin = canAccessStationTablet(src, player, station)
    return {
        id = stationId,
        label = station.label or cfg.label,
        owner = station.owner_name,
        owned = station.owner_citizenid ~= nil,
        isOwner = isOwner,
        isAdmin = isAdmin,
        allowed = allowed,
        purchasePrice = cfg.purchasePrice,
    }
end)

lib.callback.register('ps-fuel:server:getRefuelPanel', function(src, stationId)
    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    if not player or not cfg or not station or not isNearStation(src, cfg) then return nil end

    return {
        id = stationId,
        label = station.label or cfg.label,
        owner = station.owner_name,
        stock = tonumber(station.stock) or 0,
        capacity = tonumber(station.capacity) or cfg.capacity or 10000,
        marketMultiplier = marketMultiplier,
        fuelTypes = serialiseFuelTypes(station),
        paymentAccount = Config.PaymentAccount,
    }
end)

lib.callback.register('ps-fuel:server:buyStation', function(src, stationId)
    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    if not player or not cfg or not station or not isNearStation(src, cfg) then return { success = false, message = 'Invalid station.' } end
    if station.owner_citizenid then return { success = false, message = 'This station is already owned.' } end

    local price = cfg.purchasePrice
    local purchaseAccount = Config.StationTablet.PurchaseAccount or 'bank'
    if (tonumber(player.PlayerData.money[purchaseAccount]) or 0) < price then return { success = false, message = ('Insufficient %s funds.'):format(purchaseAccount) } end
    if not removePlayerMoney(player, purchaseAccount, price, 'ps-fuel-station-purchase') then return { success = false, message = 'Purchase failed.' } end

    local charinfo = player.PlayerData.charinfo or {}
    local ownerName = (((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s*(.-)%s*$', '%1'))
    if ownerName == '' then ownerName = player.PlayerData.name or getCitizenId(player) end
    local affected = MySQL.update.await([[UPDATE ps_fuel_stations
        SET owner_citizenid = ?, owner_name = ?
        WHERE station_id = ? AND owner_citizenid IS NULL]], {
        getCitizenId(player), ownerName, stationId
    })

    if not affected or affected < 1 then
        player.Functions.AddMoney(purchaseAccount, price, 'ps-fuel-station-purchase-refund')
        loadStations()
        return { success = false, message = 'Another player purchased this station first. Your payment was refunded.' }
    end

    station.owner_citizenid, station.owner_name = getCitizenId(player), ownerName
    return { success = true, message = 'Fuel station purchased.' }
end)

lib.callback.register('ps-fuel:server:withdrawStation', function(src, stationId)
    local player = getPlayer(src)
    local station = stations[stationId]
    if not player or not station or station.owner_citizenid ~= getCitizenId(player) then
        return { success = false, message = 'You do not own this station.' }
    end

    local amount = math.floor(tonumber(station.balance) or 0)
    if amount <= 0 then return { success = false, message = 'There are no funds to withdraw.' } end

    MySQL.update.await('UPDATE ps_fuel_stations SET balance = 0 WHERE station_id = ?', { stationId })
    station.balance = 0
    player.Functions.AddMoney('bank', amount, 'ps-fuel-station-withdrawal')
    return { success = true, amount = amount }
end)

lib.callback.register('ps-fuel:server:setStationMultiplier', function(src, stationId, multiplier)
    local player = getPlayer(src)
    local station = stations[stationId]
    multiplier = tonumber(multiplier)
    if not player or not station or not multiplier or multiplier < 0.5 or multiplier > 2.0 then
        return { success = false, message = 'Multiplier must be between 0.5 and 2.0.' }
    end
    if station.owner_citizenid ~= getCitizenId(player) and not IsPlayerAceAllowed(src, Config.AdminAce) then
        return { success = false, message = 'You cannot edit this station.' }
    end

    MySQL.update.await('UPDATE ps_fuel_stations SET price_multiplier = ? WHERE station_id = ?', { multiplier, stationId })
    station.price_multiplier = multiplier
    return { success = true }
end)

lib.callback.register('ps-fuel:server:getAdminData', function(src)
    if not IsPlayerAceAllowed(src, Config.AdminAce) then return nil end
    local totals = MySQL.single.await([[SELECT COUNT(*) AS transactions,
        COALESCE(SUM(amount_paid),0) AS revenue, COALESCE(SUM(fuel_amount),0) AS fuel
        FROM ps_fuel_transactions]]) or {}
    local list = {}
    for _, cfg in ipairs(Config.Stations) do
        local row = stations[cfg.id]
        list[#list + 1] = {
            id = cfg.id, label = cfg.label, owner = row and row.owner_name,
            balance = row and tonumber(row.balance) or 0,
            totalSales = row and tonumber(row.total_sales) or 0,
            priceMultiplier = row and tonumber(row.price_multiplier) or cfg.priceMultiplier,
            stock = row and tonumber(row.stock) or 0,
            capacity = row and tonumber(row.capacity) or cfg.capacity or 10000
        }
    end
    return { totals = totals, stations = list }
end)


lib.callback.register('ps-fuel:server:consumeJerryCan', function(src)
    if not Config.JerryCan.Enabled then return false end
    local player = getPlayer(src)
    if not player then return false end

    local item = player.Functions.GetItemByName(Config.JerryCan.Item)
        or player.Functions.GetItemByName(Config.JerryCan.Item:upper())
    if not item then return false end

    return player.Functions.RemoveItem(item.name, 1, item.slot) == true
end)

exports.qbx_core:CreateUseableItem(Config.JerryCan.Item, function(src)
    TriggerClientEvent('ps-fuel:client:useJerryCan', src)
end)

RegisterCommand('fueladmin', function(src)
    if src == 0 then return end
    if not IsPlayerAceAllowed(src, Config.AdminAce) then return notify(src, 'You do not have permission.', 'error') end
    TriggerClientEvent('ps-fuel:client:openAdmin', src)
end, false)


CreateThread(function()
    while true do
        Wait((Config.AutoRestock.IntervalMinutes or 30) * 60000)

        if Config.AutoRestock.Enabled then
            for _, cfg in ipairs(Config.Stations) do
                local station = stations[cfg.id]

                if station then
                    local capacity = tonumber(station.capacity) or cfg.capacity or 10000.0
                    local stock = tonumber(station.stock) or 0.0
                    local isOwned = station.owner_citizenid ~= nil

                    local canRestock =
                        (not isOwned or Config.AutoRestock.RestockOwnedStations)
                        and (
                            not Config.AutoRestock.RestockOnlyWhenBelowCapacity
                            or stock < capacity
                        )

                    if canRestock then
                        local newStock = math.min(
                            capacity,
                            stock + (Config.AutoRestock.Amount or 750.0)
                        )

                        local added = newStock - stock

                        if added > 0 then
                            station.stock = newStock

                            MySQL.update.await(
                                'UPDATE ps_fuel_stations SET stock = ? WHERE station_id = ?',
                                { newStock, cfg.id }
                            )

                            MySQL.insert.await([[
                                INSERT INTO ps_fuel_transactions
                                (station_id, citizenid, player_name, amount_paid, fuel_amount, transaction_type)
                                VALUES (?, NULL, 'Automatic Restock', 0, ?, 'auto_restock')
                            ]], {
                                cfg.id,
                                added
                            })
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function() paymentCooldown[source] = nil end)


-- Recoil Fuel 3.0 premium systems
marketMultiplier = tonumber(MySQL.scalar.await(
    "SELECT setting_value FROM ps_fuel_settings WHERE setting_key = 'market_multiplier'"
)) or 1.0

local function premiumPlayerName(player)
    local c = player and player.PlayerData and player.PlayerData.charinfo or {}
    return (((c.firstname or '') .. ' ' .. (c.lastname or '')):gsub('^%s*(.-)%s*$', '%1'))
end

local function premiumUnitPrice(station, electric, fuelType)
    return fuelUnitPrice(station, electric, fuelType)
end

CreateThread(function()
    while true do
        Wait(Config.DynamicPricing.UpdateMinutes * 60000)
        if Config.DynamicPricing.Enabled then
            local direction = math.random() < 0.5 and -1 or 1
            marketMultiplier = math.max(
                Config.DynamicPricing.MinMarketMultiplier,
                math.min(Config.DynamicPricing.MaxMarketMultiplier,
                    marketMultiplier + direction * Config.DynamicPricing.RandomStep)
            )
            MySQL.prepare.await([[INSERT INTO ps_fuel_settings (setting_key, setting_value)
                VALUES ('market_multiplier', ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)]],
                { marketMultiplier })
            TriggerClientEvent('ps-fuel:client:marketUpdate', -1, marketMultiplier)
        end
    end
end)

lib.callback.register('ps-fuel:server:getPremiumPrice', function(_, stationId, electric, fuelType)
    local station = stations[stationId]
    if not station then return nil end
    return {
        unitPrice = premiumUnitPrice(station, electric == true, fuelType),
        marketMultiplier = marketMultiplier,
        stock = tonumber(station.stock) or 0,
        capacity = tonumber(station.capacity) or 10000
    }
end)

lib.callback.register('ps-fuel:server:startDelivery', function(src, stationId)
    if not Config.Deliveries.Enabled then
        return {
            success = false,
            message = 'Fuel deliveries are disabled.'
        }
    end

    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]

    if not player or not cfg or not station or not isNearStation(src, cfg) then
        return {
            success = false,
            message = 'Invalid fuel station.'
        }
    end

    local citizenid = getCitizenId(player)

    if Config.Deliveries.OwnerOnly
        and station.owner_citizenid ~= citizenid
    then
        return {
            success = false,
            message = 'Only the owner of this fuel station can start its delivery job.'
        }
    end

    if Config.Deliveries.RequiredJob
        and player.PlayerData.job.name ~= Config.Deliveries.RequiredJob
    then
        return {
            success = false,
            message = 'You do not have the required delivery job.'
        }
    end

    if (deliveryCooldowns[citizenid] or 0) > os.time() then
        return {
            success = false,
            message = 'You must wait before starting another delivery.'
        }
    end

    if activeDeliveries[src] then
        return {
            success = false,
            message = 'You already have an active fuel delivery.'
        }
    end

    activeDeliveries[src] = {
        stationId = stationId,
        stage = 'collect_vehicle',
        tankerLoaded = false,
        startedAt = os.time()
    }

    return {
        success = true,
        stationId = stationId,
        pickup = Config.Deliveries.Pickup,
        truck = Config.Deliveries.TruckModel,
        trailer = Config.Deliveries.TrailerModel,
        loadingTerminal = Config.Deliveries.LoadingTerminal,
        destination = cfg.coords,
        stationLabel = cfg.label
    }
end)



lib.callback.register('ps-fuel:server:spawnDeliveryVehicles', function(src, stationId)
    local delivery = activeDeliveries[src]

    if not delivery or delivery.stationId ~= stationId then
        return {
            success = false,
            message = 'No matching delivery job is active.'
        }
    end

    local truckModel = joaat(Config.Deliveries.TruckModel)
    local trailerModel = joaat(Config.Deliveries.TrailerModel)

    local truckCoords = Config.Deliveries.TruckSpawn
    local trailerCoords = Config.Deliveries.TrailerSpawn

    local truck = CreateVehicleServerSetter(
        truckModel,
        'automobile',
        truckCoords.x,
        truckCoords.y,
        truckCoords.z,
        truckCoords.w
    )

    if not truck or truck == 0 then
        return {
            success = false,
            message = 'Failed to create the delivery truck.'
        }
    end

    local trailer = CreateVehicleServerSetter(
        trailerModel,
        'trailer',
        trailerCoords.x,
        trailerCoords.y,
        trailerCoords.z,
        trailerCoords.w
    )

    if not trailer or trailer == 0 then
        DeleteEntity(truck)

        return {
            success = false,
            message = 'Failed to create the fuel tanker.'
        }
    end

    local timeout = GetGameTimer() + 10000

    while (
        not DoesEntityExist(truck)
        or not DoesEntityExist(trailer)
    ) and GetGameTimer() < timeout do
        Wait(100)
    end

    if not DoesEntityExist(truck)
        or not DoesEntityExist(trailer)
    then
        if DoesEntityExist(truck) then
            DeleteEntity(truck)
        end

        if DoesEntityExist(trailer) then
            DeleteEntity(trailer)
        end

        return {
            success = false,
            message = 'The delivery vehicles failed to network.'
        }
    end

    local truckNetId = NetworkGetNetworkIdFromEntity(truck)
    local trailerNetId = NetworkGetNetworkIdFromEntity(trailer)

    if truckNetId == 0 or trailerNetId == 0 then
        DeleteEntity(truck)
        DeleteEntity(trailer)

        return {
            success = false,
            message = 'The delivery vehicles failed to obtain network IDs.'
        }
    end

    SetEntityOrphanMode(truck, 2)
    SetEntityOrphanMode(trailer, 2)

    delivery.truckNetId = truckNetId
    delivery.trailerNetId = trailerNetId
    delivery.stage = 'drive_to_terminal'

    return {
        success = true,
        truckNetId = truckNetId,
        trailerNetId = trailerNetId
    }
end)

lib.callback.register('ps-fuel:server:markTankerLoaded', function(src, stationId)
    local delivery = activeDeliveries[src]
    local cfg = stationConfig(stationId)

    if not delivery
        or delivery.stationId ~= stationId
        or not cfg
    then
        return {
            success = false,
            message = 'No matching fuel delivery is active.'
        }
    end

    local ped = GetPlayerPed(src)

    if ped == 0 then
        return {
            success = false,
            message = 'Player could not be found.'
        }
    end

    local coords = GetEntityCoords(ped)
    local terminal = Config.Deliveries.LoadingTerminal

    if #(coords - terminal.Coords) > terminal.Radius + 10.0 then
        return {
            success = false,
            message = 'You are not at the fuel loading terminal.'
        }
    end

    delivery.stage = 'return_to_station'
    delivery.tankerLoaded = true

    return {
        success = true,
        destination = cfg.coords,
        stationLabel = cfg.label,
        message = ('Tanker filled. Return to %s.'):format(cfg.label)
    }
end)

lib.callback.register('ps-fuel:server:completeDelivery', function(src, stationId)
    local player, cfg, station = getPlayer(src), stationConfig(stationId), stations[stationId]
    local delivery = activeDeliveries[src]
    if not player or not cfg or not station or not delivery or delivery.stationId ~= stationId then
        return { success = false, message = 'No active delivery found.' }
    end

    if not delivery.tankerLoaded or delivery.stage ~= 'return_to_station' then
        return {
            success = false,
            message = 'The tanker must be filled at the loading terminal first.'
        }
    end
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - cfg.coords) > Config.Deliveries.MaxDeliveryDistance then
        return {
            success = false,
            message = ('Move the tanker within %.0f metres of the station.'):format(Config.Deliveries.MaxDeliveryDistance)
        }
    end

    local citizenid = getCitizenId(player)

    if not citizenid then
        return {
            success = false,
            message = 'Your Qbox character identifier could not be found.'
        }
    end

    local capacity = tonumber(station.capacity) or tonumber(cfg.capacity) or 10000
    local stock = tonumber(station.stock) or 0
    local deliveryAmount = tonumber(Config.Deliveries.DeliveryAmount) or 2500
    local amount = math.min(deliveryAmount, math.max(0, capacity - stock))

    if amount <= 0 then
        return {
            success = false,
            message = 'This fuel station is already at full capacity. Use some fuel or lower automatic restocking first.'
        }
    end

    local rewardMin = tonumber(Config.Deliveries.RewardMin) or 2500
    local rewardMax = tonumber(Config.Deliveries.RewardMax) or 4500

    if rewardMax < rewardMin then
        rewardMin, rewardMax = rewardMax, rewardMin
    end

    local reward = math.random(rewardMin, rewardMax)

    local paid = player.Functions.AddMoney(
        'bank',
        reward,
        'recoil-fuel-delivery'
    )

    if paid == false then
        return {
            success = false,
            message = 'The Qbox bank payment failed.'
        }
    end
    local newStock = math.min(capacity, stock + amount)
    local affected = MySQL.update.await(
        'UPDATE ps_fuel_stations SET stock = ? WHERE station_id = ?',
        { newStock, stationId }
    )

    if not affected or affected < 1 then
        -- Refund the job payout if database persistence failed.
        player.Functions.RemoveMoney('bank', reward, 'recoil-fuel-delivery-refund-reversal')
        return {
            success = false,
            message = 'The station stock could not be saved to the database.'
        }
    end

    station.stock = newStock
    MySQL.insert.await([[INSERT INTO ps_fuel_transactions
        (station_id, citizenid, player_name, amount_paid, fuel_amount, transaction_type)
        VALUES (?, ?, ?, ?, ?, 'delivery')]],
        { stationId, citizenid, premiumPlayerName(player), -reward, amount })

    deliveryCooldowns[citizenid] = os.time() + ((tonumber(Config.Deliveries.CooldownMinutes) or 15) * 60)
    activeDeliveries[src] = nil
    return { success = true, reward = reward, amount = amount, message = ('Delivered %.1f fuel and earned £%s.'):format(amount, reward) }
end)

lib.callback.register('ps-fuel:server:startRobbery', function(src, stationId)
    if not Config.Robberies.Enabled then return { success = false, message = 'Robberies are disabled.' } end
    local cfg, station = stationConfig(stationId), stations[stationId]
    if not cfg or not station or not isNearStation(src, cfg) then return { success = false, message = 'Invalid station.' } end
    if exports.qbx_core:GetDutyCountType('leo') < Config.Robberies.RequiredPolice then
        return { success = false, message = 'There are not enough police on duty.' }
    end
    if (robberyCooldowns[stationId] or 0) > os.time() then
        return { success = false, message = 'This station was robbed recently.' }
    end
    robberyCooldowns[stationId] = os.time() + Config.Robberies.CooldownMinutes * 60
    TriggerEvent(Config.Robberies.DispatchEvent, ('Fuel station robbery at %s'):format(cfg.label), 1, src)
    return { success = true, duration = Config.Robberies.Duration }
end)

lib.callback.register('ps-fuel:server:completeRobbery', function(src, stationId)
    local player, cfg, station = getPlayer(src), stationConfig(stationId), stations[stationId]
    if not player or not cfg or not station or not isNearStation(src, cfg) then
        return { success = false, message = 'Invalid station.' }
    end
    local balance = math.floor(tonumber(station.balance) or 0)
    local reward = math.min(
        math.random(Config.Robberies.MinReward, Config.Robberies.MaxReward),
        math.floor(balance * (Config.Robberies.MaxStationBalancePercent / 100))
    )
    if reward <= 0 then return { success = false, message = 'The station safe is empty.' } end

    station.balance = balance - reward
    MySQL.update.await('UPDATE ps_fuel_stations SET balance = GREATEST(0, balance - ?) WHERE station_id = ?',
        { reward, stationId })
    player.Functions.AddMoney('cash', reward, 'recoil-fuel-robbery')
    MySQL.insert.await([[INSERT INTO ps_fuel_transactions
        (station_id, citizenid, player_name, amount_paid, fuel_amount, transaction_type)
        VALUES (?, ?, ?, ?, 0, 'robbery')]],
        { stationId, getCitizenId(player), premiumPlayerName(player), -reward })
    return { success = true, reward = reward, message = ('You stole £%s.'):format(reward) }
end)

AddEventHandler('playerDropped', function()
    local delivery = activeDeliveries[source]

    if delivery then
        if delivery.truckNetId then
            local truck = NetworkGetEntityFromNetworkId(delivery.truckNetId)

            if truck and truck ~= 0 and DoesEntityExist(truck) then
                DeleteEntity(truck)
            end
        end

        if delivery.trailerNetId then
            local trailer = NetworkGetEntityFromNetworkId(delivery.trailerNetId)

            if trailer and trailer ~= 0 and DoesEntityExist(trailer) then
                DeleteEntity(trailer)
            end
        end
    end

    activeDeliveries[source] = nil
end)
