local stations = {}
local paymentCooldown = {}
local marketMultiplier = 1.0
local deliveryCooldowns = {}
local activeDeliveries = {}
local robberyCooldowns = {}
local activeRobberies = {}
local nozzleSessions = {}
local vehicleProfiles = {}

local function getPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

local function getCitizenId(player)
    return player and player.PlayerData and player.PlayerData.citizenid
end

local function audit(action, src, player, details)
    if (PSFuelConfig.Logging or {}).Console == true then
        print(('[ps-fuel] %s | source=%s citizenid=%s details=%s'):format(
            tostring(action), tostring(src or 0), tostring(getCitizenId(player) or 'none'),
            type(details) == 'string' and details or json.encode(details or {})
        ))
    end
    if PSFuelDatabase and PSFuelDatabase.Audit then
        PSFuelDatabase.Audit(action, src, getCitizenId(player), details)
    end
end

local function rateLimited(src, key, windowMs, burst)
    local security = PSFuelConfig.Security or {}
    return PSFuelSecurity and PSFuelSecurity.RateLimit(src, key,
        windowMs or security.CallbackWindowMs or 1000,
        burst or security.CallbackBurst or 8)
end

local function normalisePlate(value)
    return PSFuelSecurity and PSFuelSecurity.NormalisePlate(value) or tostring(value or '')
end

local function serverVehicleClass(vehicle, reported)
    local ok, value = pcall(GetVehicleClass, vehicle)
    value = ok and tonumber(value) or tonumber(reported)
    if not value or value < 0 or value > 22 then return nil end
    return math.floor(value)
end

local function deliveryEntities(delivery)
    if not delivery then return 0, 0 end
    local truck = delivery.truckNetId and NetworkGetEntityFromNetworkId(delivery.truckNetId) or 0
    local trailer = delivery.trailerNetId and NetworkGetEntityFromNetworkId(delivery.trailerNetId) or 0
    if truck ~= 0 and (not DoesEntityExist(truck) or GetEntityType(truck) ~= 2) then truck = 0 end
    if trailer ~= 0 and (not DoesEntityExist(trailer) or GetEntityType(trailer) ~= 2) then trailer = 0 end
    return truck, trailer
end

local function deleteDeliveryEntities(delivery)
    local truck, trailer = deliveryEntities(delivery)
    if trailer ~= 0 then DeleteEntity(trailer) end
    if truck ~= 0 then DeleteEntity(truck) end
end


local function normaliseVehicleFuelType(value)
    value = tostring(value or ''):lower()
    if value == 'petrol' or value == 'diesel' or value == 'electric' then return value end
    return nil
end

local function vehicleProfileKey(model)
    return tostring(tonumber(model) or 0)
end

local function configuredVehicleProfile(model, reportedVehicleClass)
    model = tonumber(model) or 0
    local override = vehicleProfiles[vehicleProfileKey(model)]
    if override then
        return {
            modelHash = model,
            modelName = override.modelName,
            fuelType = override.fuelType,
            fastCharge = override.fastCharge == true,
            source = 'database',
        }
    end

    local electricConfig = PSFuelConfig.Electric or {}
    if electricConfig.Enabled ~= false and electricConfig.Models and electricConfig.Models[model] == true then
        return {
            modelHash = model,
            fuelType = 'electric',
            fastCharge = (PSFuelConfig.VehicleConfiguration or {}).ElectricFastChargeDefault == true,
            source = 'config',
        }
    end

    local class = tonumber(reportedVehicleClass)
    if class then
        class = math.floor(class)
        if class < 0 or class > 22 then class = nil end
    end

    local diesel = PSFuelConfig.FuelTypes and PSFuelConfig.FuelTypes.diesel or {}
    local dieselVehicle = (diesel.Models and diesel.Models[model] == true)
        or (class ~= nil and diesel.AllowedClasses and diesel.AllowedClasses[class] == true)

    return {
        modelHash = model,
        fuelType = dieselVehicle and 'diesel' or 'petrol',
        fastCharge = false,
        source = 'automatic',
    }
end

local function chargerSupportsFastCharge(charger)
    local fast = (PSFuelConfig.Electric or {}).FastCharge or {}
    if fast.Enabled == false then return false end
    if charger and charger.fastCharge ~= nil then return charger.fastCharge == true end
    return fast.ChargersEnabledByDefault ~= false
end

local function isElectricFuelType(fuelType)
    fuelType = tostring(fuelType or ''):lower()
    return fuelType == 'electric' or fuelType == 'electric_fast'
end

local function stationConfig(id)
    for i = 1, #PSFuelConfig.Stations do
        if PSFuelConfig.Stations[i].id == id then return PSFuelConfig.Stations[i] end
    end
end

local function stationOwnershipEnabled(cfg)
    if not cfg then return false end
    if cfg.ownershipEnabled ~= nil then return cfg.ownershipEnabled == true end
    local ownership = PSFuelConfig.Ownership or {}
    return ownership.DefaultEnabled ~= false
end

local function stationPurchasePrice(cfg)
    return math.max(0, math.floor(tonumber(cfg and cfg.purchasePrice)
        or tonumber((PSFuelConfig.Ownership or {}).DefaultPurchasePrice)
        or 0))
end

local function stationDeliveryEnabled(cfg)
    if not cfg then return false end
    if cfg.deliveryEnabled ~= nil then return cfg.deliveryEnabled == true end
    return stationOwnershipEnabled(cfg)
end

local function stationInteractionDistance(station)
    return math.max(5.0, tonumber(station and station.interactionDistance)
        or tonumber(PSFuelConfig.StationInteractionDistance)
        or 18.0)
end

local function isNearStation(src, station)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - station.coords) <= stationInteractionDistance(station)
end

local function notify(src, description, kind)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'PS Fuel',
        description = description,
        type = kind or 'inform'
    })
end

local function playerIdentifier(player)
    return getCitizenId(player) or (player and player.PlayerData and player.PlayerData.source)
end

local function getPlayerMoney(player, account)
    local identifier = playerIdentifier(player)
    if not identifier then return 0 end
    local ok, value = pcall(function()
        return exports.qbx_core:GetMoney(identifier, account)
    end)
    if ok and value ~= false then return tonumber(value) or 0 end
    return tonumber(player and player.PlayerData and player.PlayerData.money and player.PlayerData.money[account]) or 0
end

local function removePlayerMoney(player, account, amount, reason)
    local identifier = playerIdentifier(player)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if not identifier or getPlayerMoney(player, account) < amount then return false end
    local ok, result = pcall(function()
        return exports.qbx_core:RemoveMoney(identifier, account, amount, reason)
    end)
    return ok and result == true
end

local function addPlayerMoney(player, account, amount, reason)
    local identifier = playerIdentifier(player)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if not identifier then return false end
    local ok, result = pcall(function()
        return exports.qbx_core:AddMoney(identifier, account, amount, reason)
    end)
    return ok and result == true
end

local function paymentAccountAllowed(account)
    account = tostring(account or (PSFuelConfig.Payment or {}).DefaultAccount or PSFuelConfig.PaymentAccount or 'bank'):lower()
    local allowed = (PSFuelConfig.Payment or {}).AllowedAccounts or { bank = true }
    if allowed[account] ~= true then
        account = tostring((PSFuelConfig.Payment or {}).DefaultAccount or PSFuelConfig.PaymentAccount or 'bank'):lower()
    end
    return account
end

local function electricChargerByStation(stationId, chargerId)
    local fallback
    for _, charger in ipairs((PSFuelConfig.Electric or {}).Chargers or {}) do
        if charger.stationId == stationId then
            fallback = fallback or charger
            if chargerId and charger.id == chargerId then return charger end
        end
    end
    return fallback
end

local function isNearFuelSource(src, station, electric, chargerId)
    if not electric then return isNearStation(src, station) end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local charger = electricChargerByStation(station.id, chargerId)
    if not charger or not charger.coords then return false end
    local coords = charger.coords
    return #(GetEntityCoords(ped) - vec3(coords.x, coords.y, coords.z))
        <= math.max(5.0, tonumber((PSFuelConfig.Electric or {}).MaxCableDistance) or 7.5)
end

local function emergencyDiscount(player, vehicleClass)
    local cfg = PSFuelConfig.EmergencyDiscount or {}
    if cfg.Enabled ~= true or not player or not player.PlayerData then return 0 end

    local job = player.PlayerData.job or {}
    if not cfg.Jobs or cfg.Jobs[job.name] ~= true then return 0 end
    if cfg.OnDutyOnly == true and job.onduty ~= true then return 0 end

    local class = tonumber(vehicleClass)
    if cfg.EmergencyVehiclesOnly == true and class ~= 18 then return 0 end

    return math.max(0, math.min(100, tonumber(cfg.DiscountPercent) or 0))
end

local function applyDiscount(value, discount)
    value = tonumber(value) or 0
    discount = math.max(0, math.min(100, tonumber(discount) or 0))
    return value * (1.0 - (discount / 100.0))
end

local function applyTax(value)
    value = tonumber(value) or 0
    local percent = math.max(0, tonumber((PSFuelConfig.Pricing or {}).GlobalTaxPercent) or 0)
    return value * (1.0 + (percent / 100.0))
end

local function jerryCanPrice()
    return math.max(0, math.ceil(applyTax(tonumber((PSFuelConfig.JerryCan or {}).Price) or 0)))
end

local function nozzleSessionTimeout()
    return math.max(30, math.floor(tonumber((PSFuelConfig.Nozzles or {}).SessionTimeoutSeconds) or 300))
end

local function nozzleSessionRequired()
    local cfg = PSFuelConfig.Nozzles or {}
    return cfg.Enabled == true and cfg.RequireNozzle == true
end

local function createNozzleToken(src)
    return PSFuelSecurity and PSFuelSecurity.Token(src, 'nozzle') or ('%s:%s:%s'):format(src, GetGameTimer(), math.random(100000, 999999))
end

local function validateNozzleSession(src, stationId, electric, chargerId, token)
    if not nozzleSessionRequired() then return true, nil end

    local session = nozzleSessions[src]
    if not session or type(token) ~= 'string' or token == '' or session.token ~= token then
        return false, nil
    end
    if session.expiresAt <= os.time() or session.stationId ~= stationId then
        nozzleSessions[src] = nil
        return false, nil
    end

    local expectedKind = electric and 'electric' or 'fuel'
    if session.kind ~= expectedKind then return false, nil end
    if electric and session.chargerId ~= chargerId then return false, nil end

    local cfg = stationConfig(stationId)
    if not cfg or not isNearFuelSource(src, cfg, electric, chargerId) then
        return false, nil
    end

    session.expiresAt = os.time() + nozzleSessionTimeout()
    return true, session
end

local function fuelTypeConfig(fuelType)
    fuelType = tostring(fuelType or (PSFuelConfig.FuelTypes and PSFuelConfig.FuelTypes.Default) or 'petrol'):lower()
    local config = PSFuelConfig.FuelTypes and PSFuelConfig.FuelTypes[fuelType]
    if type(config) ~= 'table' then return nil, nil end
    return fuelType, config
end

local function fuelUnitPrice(station, electric, fuelType)
    if electric then
        local electricConfig = PSFuelConfig.Electric or {}
        local subtotal = tonumber(electricConfig.PricePerFuel) or 0
        if tostring(fuelType or ''):lower() == 'electric_fast' then
            local fast = electricConfig.FastCharge or {}
            subtotal = subtotal * math.max(0.0, tonumber(fast.PriceMultiplier) or 1.0)
        end

        if electricConfig.UseStationMultiplier == true then
            subtotal = subtotal * (tonumber(station and station.price_multiplier) or 1.0)
        end
        if electricConfig.UseMarketMultiplier == true then
            subtotal = subtotal * marketMultiplier
        end
        if electricConfig.UseGlobalTax == false then
            return subtotal
        end
        return applyTax(subtotal)
    end

    local stock = tonumber(station and station.stock) or 0
    local stockMult = 1.0

    local dynamic = PSFuelConfig.DynamicPricing or {}
    if dynamic.Enabled == true then
        local lowThreshold = tonumber(dynamic.LowStockThreshold) or 2500.0
        local highThreshold = tonumber(dynamic.HighStockThreshold) or 8500.0
        if highThreshold < lowThreshold then lowThreshold, highThreshold = highThreshold, lowThreshold end
        if stock <= lowThreshold then
            stockMult = 1.0 + math.max(0.0, tonumber(dynamic.LowStockSurcharge) or 0.20)
        elseif stock >= highThreshold then
            stockMult = math.max(0.05, 1.0 - math.max(0.0, tonumber(dynamic.HighStockDiscount) or 0.10))
        end
    end

    local _, typeConfig = fuelTypeConfig(fuelType)
    local typeMultiplier = typeConfig and tonumber(typeConfig.priceMultiplier) or 1.0
    local subtotal = (tonumber(PSFuelConfig.PricePerFuel) or 0)
        * (tonumber(station and station.price_multiplier) or 1.0)
        * marketMultiplier
        * stockMult
        * typeMultiplier

    return applyTax(subtotal)
end

local function canAccessStationTablet(src, player, station, cfg)
    if not player or not station or not cfg then return false, false, false end
    local isOwner = station.owner_citizenid == getCitizenId(player)
    local isAdmin = PSFuelConfig.StationTablet.AllowAdmin and IsPlayerAceAllowed(src, PSFuelConfig.AdminAce) or false

    if not stationOwnershipEnabled(cfg) then
        local allowAdmin = (PSFuelConfig.Ownership or {}).AllowAdminPanelAtPublicStations == true
        return isAdmin and allowAdmin, false, isAdmin
    end

    local allowed = isOwner or isAdmin or PSFuelConfig.StationTablet.OwnerOnly == false
    return allowed, isOwner, isAdmin
end

local function vehicleFuelTypeAllowed(vehicle, fuelType, reportedVehicleClass)
    if vehicle == 0 or GetEntityType(vehicle) ~= 2 then return false end
    fuelType = tostring(fuelType or ''):lower()
    local profile = configuredVehicleProfile(GetEntityModel(vehicle), reportedVehicleClass)

    if fuelType == 'electric' then return profile.fuelType == 'electric' end
    if fuelType == 'electric_fast' then
        return profile.fuelType == 'electric' and profile.fastCharge == true
    end
    if profile.fuelType == 'electric' then return false end
    if fuelType == 'diesel' then return profile.fuelType == 'diesel' end
    return profile.fuelType == 'petrol' and (fuelType == 'petrol' or fuelType == 'premium')
end

local function serialiseFuelTypes(station, player, vehicleClass, includeElectric, includeFastCharge)
    local result = {}
    local discount = emergencyDiscount(player, vehicleClass)

    for key, data in pairs(PSFuelConfig.FuelTypes or {}) do
        if type(data) == 'table' then
            result[#result + 1] = {
                id = key,
                label = data.label or key,
                description = data.description or '',
                accent = data.accent or '#18d8e8',
                priceMultiplier = tonumber(data.priceMultiplier) or 1.0,
                unitPrice = applyDiscount(fuelUnitPrice(station, false, key), discount),
                discountPercent = discount,
            }
        end
    end

    if includeElectric and (PSFuelConfig.Electric or {}).Enabled ~= false then
        result[#result + 1] = {
            id = 'electric',
            label = 'Standard charge',
            description = 'Standard-output charging for configured electric vehicles.',
            accent = '#22c55e',
            priceMultiplier = 1.0,
            unitPrice = applyDiscount(fuelUnitPrice(station, true, 'electric'), discount),
            discountPercent = discount,
        }

        local fast = (PSFuelConfig.Electric or {}).FastCharge or {}
        if includeFastCharge and fast.Enabled ~= false then
            result[#result + 1] = {
                id = 'electric_fast',
                label = fast.Label or 'Fast charge',
                description = fast.Description or 'Higher-output charging for compatible electric vehicles.',
                accent = fast.Accent or '#38bdf8',
                priceMultiplier = tonumber(fast.PriceMultiplier) or 1.0,
                unitPrice = applyDiscount(fuelUnitPrice(station, true, 'electric_fast'), discount),
                discountPercent = discount,
            }
        end
    end

    table.sort(result, function(a, b)
        local order = { petrol = 1, premium = 2, diesel = 3, electric = 4, electric_fast = 5 }
        return (order[a.id] or 99) < (order[b.id] or 99)
    end)
    return result
end

local function loadVehicleProfiles()
    vehicleProfiles = {}
    local rows = MySQL.query.await([[SELECT model_hash, model_name, fuel_type, fast_charge_enabled
        FROM ps_fuel_vehicle_profiles]]) or {}
    for _, row in ipairs(rows) do
        local fuelType = normaliseVehicleFuelType(row.fuel_type)
        local modelHash = tonumber(row.model_hash)
        if fuelType and modelHash then
            vehicleProfiles[vehicleProfileKey(modelHash)] = {
                modelHash = modelHash,
                modelName = tostring(row.model_name or modelHash),
                fuelType = fuelType,
                fastCharge = fuelType == 'electric' and tonumber(row.fast_charge_enabled) == 1 or false,
            }
        end
    end
end

local function serialiseVehicleProfiles()
    local result = {}
    for _, profile in pairs(vehicleProfiles) do
        result[#result + 1] = {
            modelHash = profile.modelHash,
            modelName = profile.modelName,
            fuelType = profile.fuelType,
            fastCharge = profile.fastCharge == true,
        }
    end
    table.sort(result, function(a, b) return tostring(a.modelName) < tostring(b.modelName) end)
    return result
end

local function loadStations()
    local rows = MySQL.query.await('SELECT * FROM ps_fuel_stations') or {}
    local byId = {}
    for _, row in ipairs(rows) do byId[row.station_id] = row end

    for _, cfg in ipairs(PSFuelConfig.Stations) do
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
        local configuredCapacity = math.max(1.0, tonumber(cfg.capacity) or tonumber(row.capacity) or 10000.0)
        row.stock = math.min(configuredCapacity, tonumber(row.stock) or configuredCapacity)
        row.capacity = configuredCapacity
        row.label = tostring(cfg.label or row.label or cfg.id):sub(1, 100)
        MySQL.update.await([[UPDATE ps_fuel_stations
            SET label = ?, capacity = ?, stock = LEAST(stock, ?)
            WHERE station_id = ?]], { row.label, configuredCapacity, configuredCapacity, cfg.id })
        stations[cfg.id] = row
    end
end

local function validateConfiguration()
    local errors, warnings = {}, {}
    local seenStations = {}
    for index, cfg in ipairs(PSFuelConfig.Stations or {}) do
        if type(cfg.id) ~= 'string' or cfg.id == '' then
            errors[#errors + 1] = ('Station #%s has no valid id.'):format(index)
        elseif seenStations[cfg.id] then
            errors[#errors + 1] = ('Duplicate station id: %s'):format(cfg.id)
        else
            seenStations[cfg.id] = true
        end
        if not cfg.coords then errors[#errors + 1] = ('Station %s has no coords.'):format(tostring(cfg.id or index)) end
    end

    local seenChargers = {}
    for index, charger in ipairs(((PSFuelConfig.Electric or {}).Chargers or {})) do
        if type(charger.id) ~= 'string' or charger.id == '' then
            errors[#errors + 1] = ('Electric charger #%s has no valid id.'):format(index)
        elseif seenChargers[charger.id] then
            errors[#errors + 1] = ('Duplicate electric charger id: %s'):format(charger.id)
        else
            seenChargers[charger.id] = true
        end
        if not seenStations[charger.stationId] then
            errors[#errors + 1] = ('Electric charger %s references unknown station %s.'):format(
                tostring(charger.id or index), tostring(charger.stationId)
            )
        end
        if not charger.coords then warnings[#warnings + 1] = ('Electric charger %s has no coords.'):format(tostring(charger.id or index)) end
    end

    for _, warning in ipairs(warnings) do print(('[ps-fuel] CONFIG WARNING: %s'):format(warning)) end
    for _, err in ipairs(errors) do print(('[ps-fuel] CONFIG ERROR: %s'):format(err)) end
    return #errors == 0
end

CreateThread(function()
    Wait(500)
    if not validateConfiguration() then
        print('[ps-fuel] Startup aborted because the configuration contains fatal errors.')
        return
    end
    if not PSFuelDatabase or not PSFuelDatabase.Ensure or not PSFuelDatabase.Ensure() then
        return
    end

    marketMultiplier = tonumber(MySQL.scalar.await(
        "SELECT setting_value FROM ps_fuel_settings WHERE setting_key = 'market_multiplier'"
    )) or 1.0

    loadVehicleProfiles()
    loadStations()
end)

-- Fuel stock is handled by the built-in delivery job and optional automatic restocking.

lib.callback.register('ps-fuel:server:beginNozzleSession', function(src, stationId, kind, chargerId, paymentAccount)
    kind = tostring(kind or ''):lower()
    local electric = kind == 'electric'
    if kind ~= 'fuel' and not electric then
        return { success = false, message = 'Invalid nozzle type.' }
    end

    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    if not cfg or not station or not isNearFuelSource(src, cfg, electric, chargerId) then
        return { success = false, message = 'Move closer to the correct pump or charger.' }
    end
    if electric and not electricChargerByStation(stationId, chargerId) then
        return { success = false, message = 'This electric charger is not configured.' }
    end

    local player = getPlayer(src)
    if not player then return { success = false, message = 'Player not found.' } end

    local account = paymentAccountAllowed(paymentAccount)
    local token = createNozzleToken(src)
    nozzleSessions[src] = {
        token = token,
        stationId = stationId,
        kind = kind,
        chargerId = electric and chargerId or nil,
        paymentAccount = account,
        billingRemainder = 0.0,
        expiresAt = os.time() + nozzleSessionTimeout(),
    }

    return {
        success = true,
        token = token,
        paymentAccount = account,
    }
end)

RegisterNetEvent('ps-fuel:server:endNozzleSession', function(token)
    local src = source
    local session = nozzleSessions[src]
    if session and session.token == tostring(token or '') then
        nozzleSessions[src] = nil
    end
end)

lib.callback.register('ps-fuel:server:getVehicleProfiles', function()
    return serialiseVehicleProfiles()
end)

lib.callback.register('ps-fuel:server:canConfigureVehicles', function(src)
    local cfg = PSFuelConfig.VehicleConfiguration or {}
    return cfg.Enabled ~= false and IsPlayerAceAllowed(src, cfg.AdminAce or PSFuelConfig.AdminAce)
end)

lib.callback.register('ps-fuel:server:saveVehicleProfile', function(src, netId, requestedType, fastCharge, modelName)
    local cfg = PSFuelConfig.VehicleConfiguration or {}
    if cfg.Enabled == false or not IsPlayerAceAllowed(src, cfg.AdminAce or PSFuelConfig.AdminAce) then
        return { success = false, message = 'You do not have permission to configure vehicle fuel types.' }
    end

    netId = tonumber(netId)
    local vehicle = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if vehicle == 0 or GetEntityType(vehicle) ~= 2 then
        return { success = false, message = 'The vehicle is no longer available.' }
    end

    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 8.0 then
        return { success = false, message = 'Move closer to the vehicle.' }
    end

    local modelHash = GetEntityModel(vehicle)
    requestedType = tostring(requestedType or ''):lower()
    if requestedType == 'automatic' then
        MySQL.update.await('DELETE FROM ps_fuel_vehicle_profiles WHERE model_hash = ?', { modelHash })
        vehicleProfiles[vehicleProfileKey(modelHash)] = nil
        TriggerClientEvent('ps-fuel:client:vehicleProfileUpdated', -1, {
            modelHash = modelHash,
            removed = true,
        })
        return { success = true, message = 'Vehicle model returned to automatic fuel detection.' }
    end

    local fuelType = normaliseVehicleFuelType(requestedType)
    if not fuelType then return { success = false, message = 'Invalid vehicle fuel type.' } end
    fastCharge = fuelType == 'electric' and fastCharge == true or false
    modelName = tostring(modelName or modelHash):gsub('[^%w_%- ]', ''):sub(1, 80)
    if modelName == '' then modelName = tostring(modelHash) end

    local player = getPlayer(src)
    local updatedBy = getCitizenId(player) or ('source:%s'):format(src)
    MySQL.prepare.await([[INSERT INTO ps_fuel_vehicle_profiles
        (model_hash, model_name, fuel_type, fast_charge_enabled, updated_by)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE model_name = VALUES(model_name), fuel_type = VALUES(fuel_type),
        fast_charge_enabled = VALUES(fast_charge_enabled), updated_by = VALUES(updated_by)]], {
        modelHash, modelName, fuelType, fastCharge and 1 or 0, updatedBy
    })

    local profile = {
        modelHash = modelHash,
        modelName = modelName,
        fuelType = fuelType,
        fastCharge = fastCharge,
    }
    vehicleProfiles[vehicleProfileKey(modelHash)] = profile
    TriggerClientEvent('ps-fuel:client:vehicleProfileUpdated', -1, profile)
    return {
        success = true,
        message = ('%s configured as %s%s.'):format(
            modelName,
            fuelType,
            fastCharge and ' with fast charging' or ''
        ),
        profile = profile,
    }
end)

lib.callback.register('ps-fuel:server:getVehicleFuel', function(src, plate)
    if rateLimited(src, 'getVehicleFuel', 1000, 12) then return nil end
    plate = normalisePlate(plate)
    if not plate then return nil end
    return MySQL.single.await('SELECT fuel, leak_level FROM ps_fuel_vehicles WHERE plate = ?', { plate })
end)

RegisterNetEvent('ps-fuel:server:saveVehicleFuel', function(netId, plate, fuel, leakLevel)
    local src = source
    local security = PSFuelConfig.Security or {}
    if rateLimited(src, 'saveVehicleFuel', security.PersistenceWindowMs or 1000, 4) then return end

    local vehicle = PSFuelSecurity and PSFuelSecurity.VehicleFromNetId(netId) or 0
    if vehicle == 0 or not PSFuelSecurity.PlayerNearEntity(src, vehicle, 20.0) then return end

    local actualPlate
    local ok, value = pcall(GetVehicleNumberPlateText, vehicle)
    if ok then actualPlate = normalisePlate(value) end
    plate = normalisePlate(plate)
    if not plate or (actualPlate and actualPlate ~= plate) then return end

    fuel = tonumber(fuel)
    leakLevel = math.max(0, math.min(2, tonumber(leakLevel) or 0))
    if not fuel then return end
    fuel = math.max(0, math.min(PSFuelConfig.MaxFuel, fuel))
    MySQL.prepare.await([[INSERT INTO ps_fuel_vehicles (plate, fuel, leak_level, updated_at)
        VALUES (?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE
        fuel = VALUES(fuel), leak_level = VALUES(leak_level), updated_at = NOW()]],
        { plate, fuel, leakLevel })
end)

lib.callback.register('ps-fuel:server:purchaseFuel', function(
    src, stationId, netId, fuelAmount, fuelType, vehicleClass, paymentAccount, chargerId, sessionToken
)
    if rateLimited(src, 'purchaseFuel', 1000, 8) then
        return { success = false, message = 'Please slow down.' }
    end

    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    fuelAmount = tonumber(fuelAmount)
    netId = tonumber(netId)
    fuelType = tostring(fuelType or PSFuelConfig.FuelTypes.Default):lower()
    local electric = isElectricFuelType(fuelType)
    local selectedFuelType, selectedFuelConfig

    if electric then
        selectedFuelType = fuelType == 'electric_fast' and 'electric_fast' or 'electric'
        local electricConfig = PSFuelConfig.Electric or {}
        local fast = electricConfig.FastCharge or {}
        selectedFuelConfig = {
            transactionType = selectedFuelType == 'electric_fast'
                and (fast.TransactionType or 'electric_fast_charge')
                or (electricConfig.TransactionType or 'electric_charge')
        }
    else
        selectedFuelType, selectedFuelConfig = fuelTypeConfig(fuelType)
    end

    if not player or not cfg or not station or not selectedFuelType or not selectedFuelConfig
        or not fuelAmount or fuelAmount <= 0 or fuelAmount > 10
    then
        return { success = false, message = 'Invalid fuel purchase.' }
    end
    local validSession, nozzleSession = validateNozzleSession(
        src,
        stationId,
        electric,
        chargerId,
        sessionToken
    )
    if not validSession then
        return { success = false, message = 'The physical nozzle session is no longer authorised.' }
    end

    if not isNearFuelSource(src, cfg, electric, chargerId) then
        return {
            success = false,
            message = electric
                and 'You are too far away from the electric charger.'
                or 'You are too far away from the fuel station.'
        }
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
    local actualVehicleClass = serverVehicleClass(vehicle, vehicleClass)
    if not vehicleFuelTypeAllowed(vehicle, selectedFuelType, actualVehicleClass) then
        return { success = false, message = 'That energy type is not compatible with this vehicle.' }
    end
    if selectedFuelType == 'electric_fast' then
        local charger = electricChargerByStation(stationId, chargerId)
        if not chargerSupportsFastCharge(charger) then
            return { success = false, message = 'This charger does not support fast charging.' }
        end
    end

    local playerPed = GetPlayerPed(src)
    if playerPed == 0 or #(GetEntityCoords(playerPed) - GetEntityCoords(vehicle)) > (PSFuelConfig.VehicleDistance + 3.0) then
        return { success = false, message = 'The vehicle is too far away from the pump or charger.' }
    end

    local stock = tonumber(station.stock) or 0
    if not electric and stock < fuelAmount then
        return { success = false, message = 'This station is out of fuel.' }
    end

    local discount = emergencyDiscount(player, actualVehicleClass)
    local unitPrice = applyDiscount(fuelUnitPrice(station, electric, selectedFuelType), discount)
    local rawPrice = fuelAmount * unitPrice
    local nextRemainder = 0.0
    local price

    if nozzleSession then
        rawPrice = rawPrice + (tonumber(nozzleSession.billingRemainder) or 0.0)
        price = math.max(0, math.floor(rawPrice + 0.000001))
        nextRemainder = math.max(0.0, rawPrice - price)
    else
        price = math.max(unitPrice <= 0 and 0 or 1, math.ceil(rawPrice))
    end

    local account = nozzleSession and nozzleSession.paymentAccount or paymentAccountAllowed(paymentAccount)
    local balance = getPlayerMoney(player, account)
    if balance < price then
        return { success = false, message = ('You need £%s more in %s.'):format(price - balance, account) }
    end

    if price > 0 and not removePlayerMoney(player, account, price, 'ps-fuel-purchase') then
        return { success = false, message = ('Payment failed from %s account.'):format(account) }
    end

    local ownershipEnabled = stationOwnershipEnabled(cfg)
    local hasOwner = station.owner_citizenid ~= nil and station.owner_citizenid ~= ''
    local keepPublicShare = (PSFuelConfig.Ownership or {}).PublicStationsKeepOwnerShare == true
    local ownerCut = (not electric and ((hasOwner and ownershipEnabled) or keepPublicShare))
        and math.floor(price * (PSFuelConfig.OwnerSharePercent / 100))
        or 0
    local stockRemoval = electric and 0 or fuelAmount

    local affected
    if electric then
        affected = MySQL.update.await([[UPDATE ps_fuel_stations
            SET balance = balance + ?, total_sales = total_sales + ?, total_litres = total_litres + ?
            WHERE station_id = ?]], { ownerCut, price, fuelAmount, stationId })
    else
        affected = MySQL.update.await([[UPDATE ps_fuel_stations
            SET balance = balance + ?, total_sales = total_sales + ?, total_litres = total_litres + ?,
                stock = stock - ?
            WHERE station_id = ? AND stock >= ?]], {
                ownerCut, price, fuelAmount, stockRemoval, stationId, stockRemoval
            })
    end

    if not affected or affected < 1 then
        if price > 0 then addPlayerMoney(player, account, price, 'ps-fuel-purchase-refund') end
        return { success = false, message = electric and 'The charging transaction failed.' or 'The station ran out of fuel.' }
    end
    if nozzleSession then nozzleSession.billingRemainder = nextRemainder end

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
    if not electric then
        station.stock = math.max(0, (tonumber(station.stock) or 0) - fuelAmount)
    end

    return {
        success = true,
        price = price,
        station = stationId,
        fuelType = selectedFuelType,
        unitPrice = unitPrice,
        discountPercent = discount,
        paymentAccount = account,
    }
end)

lib.callback.register('ps-fuel:server:buyJerryCan', function(src, stationId, paymentAccount)
    local canConfig = PSFuelConfig.JerryCan or {}
    if canConfig.Enabled ~= true then
        return { success = false, message = 'Jerry cans are disabled.' }
    end

    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    if not player or not cfg or not station or not isNearStation(src, cfg) then
        return { success = false, message = 'You are too far away from this station.' }
    end

    local fuelAmount = math.max(0, tonumber(canConfig.FuelAmount) or 0)
    if (tonumber(station.stock) or 0) < fuelAmount then
        return { success = false, message = 'This station does not have enough fuel to fill a can.' }
    end

    local account = paymentAccountAllowed(paymentAccount)
    local price = jerryCanPrice()
    local balance = getPlayerMoney(player, account)
    if balance < price then
        return { success = false, message = ('You cannot afford the fuel can using %s.'):format(account) }
    end
    if price > 0 and not removePlayerMoney(player, account, price, 'ps-fuel-jerrycan') then
        return { success = false, message = 'Payment failed.' }
    end

    local ownershipEnabled = stationOwnershipEnabled(cfg)
    local hasOwner = station.owner_citizenid ~= nil and station.owner_citizenid ~= ''
    local keepPublicShare = (PSFuelConfig.Ownership or {}).PublicStationsKeepOwnerShare == true
    local ownerCut = ((hasOwner and ownershipEnabled) or keepPublicShare)
        and math.floor(price * (PSFuelConfig.OwnerSharePercent / 100))
        or 0

    local affected = MySQL.update.await([[UPDATE ps_fuel_stations
        SET balance = balance + ?, total_sales = total_sales + ?, total_litres = total_litres + ?,
            stock = stock - ?
        WHERE station_id = ? AND stock >= ?]], {
            ownerCut, price, fuelAmount, fuelAmount, stationId, fuelAmount
        })
    if not affected or affected < 1 then
        if price > 0 then addPlayerMoney(player, account, price, 'ps-fuel-jerrycan-refund') end
        return { success = false, message = 'This station ran out of fuel.' }
    end

    local metadata = {}
    for key, value in pairs(canConfig.Metadata or {}) do metadata[key] = value end
    metadata.fuel = fuelAmount
    metadata.ammo = math.floor(fuelAmount)

    local added = PSFuelInventory and PSFuelInventory.AddItem(src, player, canConfig.Item, 1, metadata)
    if added ~= true then
        if price > 0 then addPlayerMoney(player, account, price, 'ps-fuel-jerrycan-refund') end
        MySQL.update.await([[UPDATE ps_fuel_stations
            SET balance = GREATEST(0, balance - ?), total_sales = GREATEST(0, total_sales - ?),
                total_litres = GREATEST(0, total_litres - ?), stock = LEAST(capacity, stock + ?)
            WHERE station_id = ?]], { ownerCut, price, fuelAmount, fuelAmount, stationId })
        return { success = false, message = 'You cannot carry the emergency fuel can.' }
    end

    station.balance = (tonumber(station.balance) or 0) + ownerCut
    station.total_sales = (tonumber(station.total_sales) or 0) + price
    station.total_litres = (tonumber(station.total_litres) or 0) + fuelAmount
    station.stock = math.max(0, (tonumber(station.stock) or 0) - fuelAmount)

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
        canConfig.TransactionType or 'jerrycan'
    })

    return {
        success = true,
        price = price,
        paymentAccount = account,
        fuelAmount = fuelAmount,
    }
end)

lib.callback.register('ps-fuel:server:getStationPanel', function(src, stationId)
    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    if not player or not cfg or not station or not isNearStation(src, cfg) then return nil end

    local allowed, isOwner, isAdmin = canAccessStationTablet(src, player, station, cfg)
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
        purchasePrice = stationPurchasePrice(cfg),
        ownershipEnabled = stationOwnershipEnabled(cfg),
        publicStation = not stationOwnershipEnabled(cfg),
        jerryCanPrice = jerryCanPrice(),
        stock = tonumber(station.stock) or 0,
        capacity = tonumber(station.capacity) or cfg.capacity or 10000,
        marketMultiplier = marketMultiplier,
        unitPrice = fuelUnitPrice(station, false, PSFuelConfig.FuelTypes.Default),
        fuelTypes = serialiseFuelTypes(station, player, nil, true, ((PSFuelConfig.Electric or {}).FastCharge or {}).Enabled ~= false),
        deliveriesEnabled = PSFuelConfig.Deliveries.Enabled and stationDeliveryEnabled(cfg),
        robberiesEnabled = PSFuelConfig.Robberies.Enabled,
        transactions = recent
    }
end)

lib.callback.register('ps-fuel:server:getStationAccess', function(src, stationId)
    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    if not player or not cfg or not station or not isNearStation(src, cfg) then return nil end

    local allowed, isOwner, isAdmin = canAccessStationTablet(src, player, station, cfg)
    return {
        id = stationId,
        label = station.label or cfg.label,
        owner = station.owner_name,
        owned = station.owner_citizenid ~= nil,
        isOwner = isOwner,
        isAdmin = isAdmin,
        allowed = allowed,
        purchasePrice = stationPurchasePrice(cfg),
        ownershipEnabled = stationOwnershipEnabled(cfg),
        publicStation = not stationOwnershipEnabled(cfg),
    }
end)

lib.callback.register('ps-fuel:server:getRefuelPanel', function(
    src, stationId, netId, vehicleClass, nozzleKind, chargerId, sessionToken
)
    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    if not player or not cfg or not station then return nil end

    local vehicle
    if tonumber(netId) then
        vehicle = NetworkGetEntityFromNetworkId(tonumber(netId))
        if vehicle == 0 or GetEntityType(vehicle) ~= 2 then vehicle = nil end
    end

    local profile = vehicle and configuredVehicleProfile(GetEntityModel(vehicle), vehicleClass) or nil
    local electricVehicle = profile and profile.fuelType == 'electric' or false
    local charger = electricChargerByStation(stationId, chargerId)
    local fastCharge = electricVehicle and profile.fastCharge == true and chargerSupportsFastCharge(charger)
    local electricSource = tostring(nozzleKind or '') == 'electric'

    if electricSource ~= electricVehicle and vehicle then
        return nil
    end

    local validSession, nozzleSession = validateNozzleSession(
        src,
        stationId,
        electricSource,
        chargerId,
        sessionToken
    )
    if not validSession then return nil end
    if not isNearFuelSource(src, cfg, electricSource, chargerId) then return nil end

    local account = nozzleSession and nozzleSession.paymentAccount or paymentAccountAllowed(nil)
    return {
        id = stationId,
        label = station.label or cfg.label,
        owner = station.owner_name,
        stock = tonumber(station.stock) or 0,
        capacity = tonumber(station.capacity) or cfg.capacity or 10000,
        marketMultiplier = marketMultiplier,
        fuelTypes = serialiseFuelTypes(station, player, vehicleClass, electricVehicle, fastCharge),
        paymentAccount = account,
        paymentAccounts = (PSFuelConfig.Payment or {}).AllowedAccounts or { bank = true },
        discountPercent = emergencyDiscount(player, vehicleClass),
        electric = electricVehicle,
        fastCharge = fastCharge,
    }
end)

lib.callback.register('ps-fuel:server:buyStation', function(src, stationId)
    local player = getPlayer(src)
    local cfg = stationConfig(stationId)
    local station = stations[stationId]
    if not player or not cfg or not station or not isNearStation(src, cfg) then return { success = false, message = 'Invalid station.' } end
    if not stationOwnershipEnabled(cfg) then
        return { success = false, message = 'This is a public fuel station and cannot be purchased.' }
    end
    if station.owner_citizenid then return { success = false, message = 'This station is already owned.' } end

    local price = stationPurchasePrice(cfg)
    if price <= 0 then return { success = false, message = 'This station has no valid purchase price.' } end
    local purchaseAccount = PSFuelConfig.StationTablet.PurchaseAccount or 'bank'
    if (getPlayerMoney(player, purchaseAccount)) < price then return { success = false, message = ('Insufficient %s funds.'):format(purchaseAccount) } end
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
        addPlayerMoney(player, purchaseAccount, price, 'ps-fuel-station-purchase-refund')
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

    if rateLimited(src, 'withdrawStation', 3000, 1) then
        return { success = false, message = 'Please wait before withdrawing again.' }
    end

    local row = MySQL.single.await('SELECT balance FROM ps_fuel_stations WHERE station_id = ?', { stationId })
    local amount = math.floor(tonumber(row and row.balance) or 0)
    if amount <= 0 then return { success = false, message = 'There are no funds to withdraw.' } end

    local affected = MySQL.update.await(
        'UPDATE ps_fuel_stations SET balance = 0 WHERE station_id = ? AND balance = ?',
        { stationId, amount }
    )
    if not affected or affected < 1 then
        loadStations()
        return { success = false, message = 'The station balance changed. Try again.' }
    end

    local paid = addPlayerMoney(player, 'bank', amount, 'ps-fuel-station-withdrawal')
    if paid == false then
        MySQL.update.await('UPDATE ps_fuel_stations SET balance = balance + ? WHERE station_id = ?', { amount, stationId })
        station.balance = amount
        return { success = false, message = 'The bank deposit failed and the station balance was restored.' }
    end

    station.balance = 0
    audit('station_withdrawal', src, player, { stationId = stationId, amount = amount })
    return { success = true, amount = amount }
end)

lib.callback.register('ps-fuel:server:setStationMultiplier', function(src, stationId, multiplier)
    local player = getPlayer(src)
    local station = stations[stationId]
    multiplier = tonumber(multiplier)
    if not player or not station or not multiplier or multiplier < 0.5 or multiplier > 2.0 then
        return { success = false, message = 'Multiplier must be between 0.5 and 2.0.' }
    end
    if station.owner_citizenid ~= getCitizenId(player) and not IsPlayerAceAllowed(src, PSFuelConfig.AdminAce) then
        return { success = false, message = 'You cannot edit this station.' }
    end

    MySQL.update.await('UPDATE ps_fuel_stations SET price_multiplier = ? WHERE station_id = ?', { multiplier, stationId })
    station.price_multiplier = multiplier
    return { success = true }
end)

lib.callback.register('ps-fuel:server:getAdminData', function(src)
    if not IsPlayerAceAllowed(src, PSFuelConfig.AdminAce) then return nil end
    local totals = MySQL.single.await([[SELECT COUNT(*) AS transactions,
        COALESCE(SUM(amount_paid),0) AS revenue, COALESCE(SUM(fuel_amount),0) AS fuel
        FROM ps_fuel_transactions]]) or {}
    local list = {}
    for _, cfg in ipairs(PSFuelConfig.Stations) do
        local row = stations[cfg.id]
        list[#list + 1] = {
            id = cfg.id, label = cfg.label, owner = row and row.owner_name,
            ownershipEnabled = stationOwnershipEnabled(cfg),
            publicStation = not stationOwnershipEnabled(cfg),
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
    local canConfig = PSFuelConfig.JerryCan or {}
    if canConfig.Enabled ~= true then
        return { success = false, message = 'Jerry cans are disabled.' }
    end

    local player = getPlayer(src)
    if not player then return { success = false, message = 'Player not found.' } end

    local removed, metadata = PSFuelInventory and PSFuelInventory.ConsumeOne(src, player, canConfig.Item)
    if removed ~= true then
        return { success = false, message = 'You do not have a usable emergency fuel can.' }
    end
    metadata = type(metadata) == 'table' and metadata or {}
    local fuelAmount = tonumber(metadata.fuel) or tonumber(metadata.ammo)
        or tonumber(canConfig.FuelAmount) or 25.0

    return { success = true, fuelAmount = math.max(0, fuelAmount) }
end)

do
    local canConfig = PSFuelConfig.JerryCan or {}
    if canConfig.Enabled == true and type(canConfig.Item) == 'string' and canConfig.Item ~= '' then
        local ok, err = pcall(function()
            exports.qbx_core:CreateUseableItem(canConfig.Item, function(src)
                TriggerClientEvent('ps-fuel:client:useJerryCan', src)
            end)
        end)
        if not ok then
            print(('[ps-fuel] Failed to register usable item %s: %s'):format(canConfig.Item, tostring(err)))
        end
    end
end

lib.callback.register('ps-fuel:server:authoriseLeakRepair', function(src, netId)
    if rateLimited(src, 'authoriseLeakRepair', 2000, 1) then
        return { success = false, message = 'Please wait before trying again.' }
    end

    local player = getPlayer(src)
    if not player then return { success = false, message = 'Player not found.' } end
    local leaks = PSFuelConfig.Leaks or {}
    local permitted = IsPlayerAceAllowed(src, leaks.RepairAce or 'ps-fuel.repair')
        or IsPlayerAceAllowed(src, PSFuelConfig.AdminAce or 'ps-fuel.admin')

    if not permitted then
        local job = player.PlayerData and player.PlayerData.job or {}
        local required = leaks.RepairJobs and leaks.RepairJobs[job.name]
        local grade = tonumber(job.grade and (job.grade.level or job.grade.grade) or job.grade) or 0
        permitted = required ~= nil and grade >= (tonumber(required) or 0)
    end

    if not permitted then
        return { success = false, message = 'Your job or permissions do not allow fuel-tank repairs.' }
    end

    local vehicle = PSFuelSecurity and PSFuelSecurity.VehicleFromNetId(netId) or 0
    if vehicle == 0 or not PSFuelSecurity.PlayerNearEntity(src, vehicle, 8.0) then
        return { success = false, message = 'Move closer to the vehicle.' }
    end

    audit('fuel_leak_repaired', src, player, { netId = tonumber(netId) })
    return { success = true }
end)

RegisterCommand('fueladmin', function(src)
    if src == 0 then return end
    if not IsPlayerAceAllowed(src, PSFuelConfig.AdminAce) then return notify(src, 'You do not have permission.', 'error') end
    TriggerClientEvent('ps-fuel:client:openAdmin', src)
end, false)

RegisterCommand('setfuel', function(src, args)
    if src == 0 then return end
    if not IsPlayerAceAllowed(src, PSFuelConfig.AdminAce) then
        return notify(src, 'You do not have permission.', 'error')
    end
    local amount = tonumber(args[1])
    if not amount then return notify(src, 'Usage: /setfuel 100 near or inside a vehicle.', 'error') end
    TriggerClientEvent('ps-fuel:client:adminSetFuel', src, math.max(0.0, math.min(PSFuelConfig.MaxFuel, amount)))
end, false)


CreateThread(function()
    while true do
        local restock = PSFuelConfig.AutoRestock or {}
        local intervalMinutes = math.max(1, tonumber(restock.IntervalMinutes) or 30)
        Wait(math.floor(intervalMinutes * 60000))

        if restock.Enabled == true then
            for _, cfg in ipairs(PSFuelConfig.Stations or {}) do
                local station = stations[cfg.id]

                if station then
                    local capacity = math.max(1.0, tonumber(station.capacity) or tonumber(cfg.capacity) or 10000.0)
                    local stock = math.max(0.0, tonumber(station.stock) or 0.0)
                    local isOwned = station.owner_citizenid ~= nil

                    local canRestock =
                        (not isOwned or restock.RestockOwnedStations == true)
                        and (
                            restock.RestockOnlyWhenBelowCapacity == false
                            or stock < capacity
                        )

                    if canRestock then
                        local newStock = math.min(capacity, stock + math.max(0.0, tonumber(restock.Amount) or 750.0))
                        local added = newStock - stock

                        if added > 0 then
                            local affected = MySQL.update.await(
                                'UPDATE ps_fuel_stations SET stock = LEAST(capacity, stock + ?) WHERE station_id = ?',
                                { added, cfg.id }
                            )
                            if affected and affected > 0 then
                                local current = MySQL.scalar.await(
                                    'SELECT stock FROM ps_fuel_stations WHERE station_id = ?', { cfg.id }
                                )
                                station.stock = tonumber(current) or newStock
                                MySQL.insert.await([[
                                    INSERT INTO ps_fuel_transactions
                                    (station_id, citizenid, player_name, amount_paid, fuel_amount, transaction_type)
                                    VALUES (?, NULL, 'Automatic Restock', 0, ?, 'auto_restock')
                                ]], { cfg.id, added })
                            end
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    paymentCooldown[source] = nil
    nozzleSessions[source] = nil
    activeRobberies[source] = nil
end)


-- Recoil Fuel 3.0 premium systems
local function premiumPlayerName(player)
    local c = player and player.PlayerData and player.PlayerData.charinfo or {}
    return (((c.firstname or '') .. ' ' .. (c.lastname or '')):gsub('^%s*(.-)%s*$', '%1'))
end

local function premiumUnitPrice(station, electric, fuelType)
    return fuelUnitPrice(station, electric, fuelType)
end

CreateThread(function()
    while true do
        local dynamic = PSFuelConfig.DynamicPricing or {}
        local updateMinutes = math.max(1, tonumber(dynamic.UpdateMinutes) or 30)
        Wait(math.floor(updateMinutes * 60000))
        if dynamic.Enabled == true then
            local minimum = math.max(0.01, tonumber(dynamic.MinMarketMultiplier) or 0.80)
            local maximum = math.max(minimum, tonumber(dynamic.MaxMarketMultiplier) or 1.35)
            local step = math.max(0.0, tonumber(dynamic.RandomStep) or 0.08)
            local direction = math.random() < 0.5 and -1 or 1
            marketMultiplier = math.max(minimum, math.min(maximum, marketMultiplier + direction * step))
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
    if not PSFuelConfig.Deliveries.Enabled then
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

    if not stationDeliveryEnabled(cfg) then
        return {
            success = false,
            message = 'Fuel deliveries are disabled for this public station.'
        }
    end

    local citizenid = getCitizenId(player)

    if PSFuelConfig.Deliveries.OwnerOnly
        and station.owner_citizenid ~= citizenid
    then
        return {
            success = false,
            message = 'Only the owner of this fuel station can start its delivery job.'
        }
    end

    if PSFuelConfig.Deliveries.RequiredJob
        and player.PlayerData.job.name ~= PSFuelConfig.Deliveries.RequiredJob
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
        pickup = PSFuelConfig.Deliveries.Pickup,
        truck = PSFuelConfig.Deliveries.TruckModel,
        trailer = PSFuelConfig.Deliveries.TrailerModel,
        loadingTerminal = PSFuelConfig.Deliveries.LoadingTerminal,
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
    if delivery.stage ~= 'collect_vehicle' or delivery.truckNetId or delivery.trailerNetId then
        return { success = false, message = 'The delivery vehicles have already been issued.' }
    end

    local truckModel = joaat(PSFuelConfig.Deliveries.TruckModel)
    local trailerModel = joaat(PSFuelConfig.Deliveries.TrailerModel)

    local truckCoords = PSFuelConfig.Deliveries.TruckSpawn
    local trailerCoords = PSFuelConfig.Deliveries.TrailerSpawn

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
    local terminal = PSFuelConfig.Deliveries.LoadingTerminal

    if #(coords - terminal.Coords) > terminal.Radius + 10.0 then
        return {
            success = false,
            message = 'You are not at the fuel loading terminal.'
        }
    end

    local truck, trailer = deliveryEntities(delivery)
    local maxVehicleDistance = math.max(10.0, tonumber((PSFuelConfig.Security or {}).DeliveryVehicleDistance) or 25.0)
    if truck == 0 or trailer == 0
        or #(GetEntityCoords(truck) - terminal.Coords) > maxVehicleDistance
        or #(GetEntityCoords(trailer) - terminal.Coords) > maxVehicleDistance
    then
        return { success = false, message = 'Bring the assigned truck and tanker into the loading area.' }
    end
    if (PSFuelConfig.Security or {}).RequireDeliveryDriverSeat ~= false
        and GetPedInVehicleSeat(truck, -1) ~= ped
    then
        return { success = false, message = 'You must be driving the assigned delivery truck.' }
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
    if ped == 0 or #(GetEntityCoords(ped) - cfg.coords) > PSFuelConfig.Deliveries.MaxDeliveryDistance then
        return {
            success = false,
            message = ('Move the tanker within %.0f metres of the station.'):format(PSFuelConfig.Deliveries.MaxDeliveryDistance)
        }
    end

    local truck, trailer = deliveryEntities(delivery)
    local maxVehicleDistance = math.max(10.0, tonumber((PSFuelConfig.Security or {}).DeliveryVehicleDistance) or 25.0)
    if truck == 0 or trailer == 0
        or #(GetEntityCoords(truck) - cfg.coords) > maxVehicleDistance
        or #(GetEntityCoords(trailer) - cfg.coords) > maxVehicleDistance
    then
        return { success = false, message = 'Bring the assigned truck and loaded tanker into the station delivery area.' }
    end
    if (PSFuelConfig.Security or {}).RequireDeliveryDriverSeat ~= false
        and GetPedInVehicleSeat(truck, -1) ~= ped
    then
        return { success = false, message = 'You must be driving the assigned delivery truck.' }
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
    local deliveryAmount = tonumber(PSFuelConfig.Deliveries.DeliveryAmount) or 2500
    local amount = math.min(deliveryAmount, math.max(0, capacity - stock))

    if amount <= 0 then
        return {
            success = false,
            message = 'This fuel station is already at full capacity. Use some fuel or lower automatic restocking first.'
        }
    end

    local rewardMin = math.max(0, math.floor(tonumber(PSFuelConfig.Deliveries.RewardMin) or 2500))
    local rewardMax = math.max(0, math.floor(tonumber(PSFuelConfig.Deliveries.RewardMax) or 4500))

    if rewardMax < rewardMin then
        rewardMin, rewardMax = rewardMax, rewardMin
    end

    local reward = math.random(rewardMin, rewardMax)

    local paid = addPlayerMoney(player, 'bank', reward, 'ps-fuel-delivery')

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
        removePlayerMoney(player, 'bank', reward, 'ps-fuel-delivery-refund-reversal')
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

    deliveryCooldowns[citizenid] = os.time() + ((tonumber(PSFuelConfig.Deliveries.CooldownMinutes) or 15) * 60)
    if PSFuelConfig.Deliveries.DeleteVehiclesOnComplete == true then deleteDeliveryEntities(delivery) end
    activeDeliveries[src] = nil
    audit('delivery_completed', src, player, { stationId = stationId, reward = reward, amount = amount })
    return { success = true, reward = reward, amount = amount, message = ('Delivered %.1f fuel and earned £%s.'):format(amount, reward) }
end)

lib.callback.register('ps-fuel:server:startRobbery', function(src, stationId)
    if not PSFuelConfig.Robberies.Enabled then return { success = false, message = 'Robberies are disabled.' } end
    if rateLimited(src, 'startRobbery', 5000, 1) then return { success = false, message = 'Please wait.' } end

    local player, cfg, station = getPlayer(src), stationConfig(stationId), stations[stationId]
    if not player or not cfg or not station or not isNearStation(src, cfg) then
        return { success = false, message = 'Invalid station.' }
    end
    if station.owner_citizenid == getCitizenId(player) then
        return { success = false, message = 'You cannot rob your own fuel station.' }
    end
    if activeRobberies[src] then return { success = false, message = 'You already have an active robbery.' } end

    local policeCount = 0
    local ok, count = pcall(function() return exports.qbx_core:GetDutyCountType('leo') end)
    if ok then policeCount = tonumber(count) or 0 end
    if policeCount < (tonumber(PSFuelConfig.Robberies.RequiredPolice) or 0) then
        return { success = false, message = 'There are not enough police on duty.' }
    end
    if (robberyCooldowns[stationId] or 0) > os.time() then
        return { success = false, message = 'This station was robbed recently.' }
    end

    local duration = math.max(5000, math.floor(tonumber(PSFuelConfig.Robberies.Duration) or 45000))
    local token = PSFuelSecurity.Token(src, 'robbery')
    activeRobberies[src] = {
        token = token,
        stationId = stationId,
        startedAt = GetGameTimer(),
        completeAt = GetGameTimer() + duration,
    }
    robberyCooldowns[stationId] = os.time() + ((tonumber(PSFuelConfig.Robberies.CooldownMinutes) or 45) * 60)
    local dispatchEvent = tostring((PSFuelConfig.Robberies or {}).DispatchEvent or '')
    if dispatchEvent ~= '' then
        TriggerEvent(dispatchEvent, ('Fuel station robbery at %s'):format(cfg.label), 1, src)
    end
    audit('robbery_started', src, player, { stationId = stationId })
    return { success = true, duration = duration, token = token }
end)

RegisterNetEvent('ps-fuel:server:cancelRobbery', function(token)
    local src = source
    local robbery = activeRobberies[src]
    if robbery and robbery.token == tostring(token or '') then
        activeRobberies[src] = nil
    end
end)

lib.callback.register('ps-fuel:server:completeRobbery', function(src, stationId, token)
    if rateLimited(src, 'completeRobbery', 3000, 1) then return { success = false, message = 'Please wait.' } end
    local robbery = activeRobberies[src]
    if not robbery or robbery.stationId ~= stationId or robbery.token ~= tostring(token or '') then
        return { success = false, message = 'No authorised robbery session was found.' }
    end

    local grace = math.max(0, tonumber((PSFuelConfig.Security or {}).RobberyGraceMs) or 1500)
    if GetGameTimer() + grace < robbery.completeAt then
        return { success = false, message = 'The station safe has not been opened yet.' }
    end

    local player, cfg, station = getPlayer(src), stationConfig(stationId), stations[stationId]
    if not player or not cfg or not station or not isNearStation(src, cfg) then
        activeRobberies[src] = nil
        return { success = false, message = 'You moved too far away from the station.' }
    end

    local row = MySQL.single.await('SELECT balance FROM ps_fuel_stations WHERE station_id = ?', { stationId })
    local balance = math.floor(tonumber(row and row.balance) or 0)
    local minimumReward = math.max(0, math.floor(tonumber((PSFuelConfig.Robberies or {}).MinReward) or 4000))
    local maximumReward = math.max(0, math.floor(tonumber((PSFuelConfig.Robberies or {}).MaxReward) or 12000))
    if maximumReward < minimumReward then minimumReward, maximumReward = maximumReward, minimumReward end
    local maximumPercent = math.max(0, math.min(100, tonumber((PSFuelConfig.Robberies or {}).MaxStationBalancePercent) or 35))
    local reward = math.min(
        math.random(minimumReward, maximumReward),
        math.floor(balance * (maximumPercent / 100))
    )
    if reward <= 0 then
        activeRobberies[src] = nil
        return { success = false, message = 'The station safe is empty.' }
    end

    local affected = MySQL.update.await(
        'UPDATE ps_fuel_stations SET balance = balance - ? WHERE station_id = ? AND balance >= ?',
        { reward, stationId, reward }
    )
    if not affected or affected < 1 then
        activeRobberies[src] = nil
        loadStations()
        return { success = false, message = 'The station balance changed. The robbery was cancelled.' }
    end

    local paid = addPlayerMoney(player, 'cash', reward, 'ps-fuel-robbery')
    if paid == false then
        MySQL.update.await('UPDATE ps_fuel_stations SET balance = balance + ? WHERE station_id = ?', { reward, stationId })
        activeRobberies[src] = nil
        return { success = false, message = 'The cash payout failed and the station balance was restored.' }
    end

    station.balance = math.max(0, balance - reward)
    MySQL.insert.await([[INSERT INTO ps_fuel_transactions
        (station_id, citizenid, player_name, amount_paid, fuel_amount, transaction_type)
        VALUES (?, ?, ?, ?, 0, 'robbery')]],
        { stationId, getCitizenId(player), premiumPlayerName(player), -reward })
    activeRobberies[src] = nil
    audit('robbery_completed', src, player, { stationId = stationId, reward = reward })
    return { success = true, reward = reward, message = ('You stole £%s.'):format(reward) }
end)

CreateThread(function()
    local cfg = PSFuelConfig.DatabaseMaintenance or {}
    if cfg.Enabled == false then return end
    local interval = math.max(1, tonumber(cfg.CleanupIntervalHours) or 12) * 3600000
    while true do
        Wait(interval)
        local transactionDays = math.max(1, math.floor(tonumber(cfg.TransactionRetentionDays) or 120))
        local auditDays = math.max(1, math.floor(tonumber(cfg.AuditRetentionDays) or 180))
        MySQL.update.await(('DELETE FROM ps_fuel_transactions WHERE created_at < NOW() - INTERVAL %d DAY'):format(transactionDays))
        MySQL.update.await(('DELETE FROM ps_fuel_audit_logs WHERE created_at < NOW() - INTERVAL %d DAY'):format(auditDays))
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for src, delivery in pairs(activeDeliveries) do
        deleteDeliveryEntities(delivery)
        activeDeliveries[src] = nil
    end
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

    activeRobberies[source] = nil
    activeDeliveries[source] = nil
end)
