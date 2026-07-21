PSFuelRuntime = PSFuelRuntime or {}

local fuelCache, dirtyFuel, leakCache = {}, {}, {}
local isRefuelling, uiOpen, activeDelivery = false, false, nil
local activeFuelSession = nil
local selectedPumpFuel = nil
local lastBodyHealth = {}
local lastFuelMessage = nil
local openFuelApp
local vehicleProfiles = {}
local canConfigureVehicleProfiles = false
local vehicleConfigTargetRegistered = false
local activeWorldFuelDisplay = nil
local fuelDecor = tostring((PSFuelConfig.Compatibility or {}).FuelDecor or '_FUEL_LEVEL')

local function fuelDecorEnabled()
    return (PSFuelConfig.Compatibility or {}).UseFuelDecor == true and fuelDecor ~= ''
end

CreateThread(function()
    if fuelDecorEnabled() and not DecorIsRegisteredAsType(fuelDecor, 1) then
        DecorRegister(fuelDecor, 1)
    end
end)

local function sendFuelNui(payload)
    payload = payload or {}
    SendNUIMessage(payload)
end

local function forceCloseUi(keepPumpSelection, silent, closeTablet)
    local wasOpen = uiOpen or lastFuelMessage ~= nil
    uiOpen = false
    activeFuelSession = nil
    lastFuelMessage = nil
    if keepPumpSelection ~= true then
        selectedPumpFuel = nil
        if PSFuelNozzle and PSFuelNozzle.CancelVehicleAttachment then
            PSFuelNozzle.CancelVehicleAttachment()
        end
    end
    if wasOpen then sendFuelNui({ action = 'reset' }) end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

CreateThread(function()
    -- Ensure the standalone NUI starts hidden without repeatedly closing it
    -- after the player has already begun using a pump.
    Wait(750)
    forceCloseUi(false, true, false)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    forceCloseUi()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for plate, entry in pairs(dirtyFuel) do
        if type(entry) == 'table' and tonumber(entry.netId) and tonumber(entry.netId) > 0 then
            TriggerServerEvent('ps-fuel:server:saveVehicleFuel', entry.netId, plate, entry.fuel, entry.leak or leakCache[plate] or 0)
        end
    end
    sendFuelNui({ action = 'psFuelSound', command = 'stopAll' })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    forceCloseUi()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    forceCloseUi()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    forceCloseUi()
end)

local function notify(description, kind)
    lib.notify({ title = 'PS Fuel', description = description, type = kind or 'inform', position = 'top-right' })
end

local function trimPlate(vehicle)
    return (GetVehicleNumberPlateText(vehicle) or ''):gsub('^%s*(.-)%s*$', '%1')
end

local function stationById(id)
    for _, station in ipairs(PSFuelConfig.Stations) do if station.id == id then return station end end
end

local function stationOwnershipEnabled(station)
    if not station then return false end
    if station.ownershipEnabled ~= nil then return station.ownershipEnabled == true end
    return (PSFuelConfig.Ownership or {}).DefaultEnabled ~= false
end

local function stationInteractionDistance(station)
    return math.max(5.0, tonumber(station and station.interactionDistance)
        or tonumber(PSFuelConfig.StationInteractionDistance)
        or 18.0)
end

local function stationManagementEnabled(station)
    return stationOwnershipEnabled(station)
end

local function nearestStation()
    local coords = GetEntityCoords(cache.ped)
    local closest, distance
    for _, station in ipairs(PSFuelConfig.Stations) do
        local d = #(coords - station.coords)
        if not distance or d < distance then closest, distance = station, d end
    end
    return closest, distance
end

local function closestPump()
    local coords = GetEntityCoords(cache.ped)
    local found, best
    for _, model in ipairs(PSFuelConfig.PumpModels) do
        local pump = GetClosestObjectOfType(coords.x, coords.y, coords.z, PSFuelConfig.RefuelDistance, model, false, false, false)
        if pump ~= 0 then
            local d = #(coords - GetEntityCoords(pump))
            if not best or d < best then found, best = pump, d end
        end
    end
    return found
end

local function closestVehicle()
    local coords = GetEntityCoords(cache.ped)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, PSFuelConfig.VehicleDistance, 0, 71)
    return vehicle ~= 0 and vehicle or nil
end


local function vehicleProfileKey(model)
    return tostring(tonumber(model) or 0)
end

local function applyVehicleProfiles(rows)
    vehicleProfiles = {}
    for _, profile in ipairs(type(rows) == 'table' and rows or {}) do
        local modelHash = tonumber(profile.modelHash)
        local fuelType = tostring(profile.fuelType or ''):lower()
        if modelHash and (fuelType == 'petrol' or fuelType == 'diesel' or fuelType == 'electric') then
            vehicleProfiles[vehicleProfileKey(modelHash)] = {
                modelHash = modelHash,
                modelName = tostring(profile.modelName or modelHash),
                fuelType = fuelType,
                fastCharge = fuelType == 'electric' and profile.fastCharge == true or false,
            }
        end
    end
end

local function configuredVehicleProfile(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then
        return { fuelType = 'petrol', fastCharge = false, source = 'automatic' }
    end

    local model = GetEntityModel(vehicle)
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

    local electric = PSFuelConfig.Electric or {}
    if electric.Enabled ~= false and electric.Models and electric.Models[model] == true then
        return {
            modelHash = model,
            fuelType = 'electric',
            fastCharge = (PSFuelConfig.VehicleConfiguration or {}).ElectricFastChargeDefault == true,
            source = 'config',
        }
    end

    local diesel = PSFuelConfig.FuelTypes and PSFuelConfig.FuelTypes.diesel or {}
    local class = GetVehicleClass(vehicle)
    local dieselVehicle = (diesel.Models and diesel.Models[model] == true)
        or (diesel.AllowedClasses and diesel.AllowedClasses[class] == true)

    return {
        modelHash = model,
        fuelType = dieselVehicle and 'diesel' or 'petrol',
        fastCharge = false,
        source = 'automatic',
    }
end

local function isElectricFuelType(fuelType)
    fuelType = tostring(fuelType or ''):lower()
    return fuelType == 'electric' or fuelType == 'electric_fast'
end

local function getFuel(vehicle)
    if not DoesEntityExist(vehicle) then return 0.0 end
    local plate = trimPlate(vehicle)
    if plate == '' then return GetVehicleFuelLevel(vehicle) end

    if fuelCache[plate] == nil then
        local saved = lib.callback.await('ps-fuel:server:getVehicleFuel', false, plate)
        local startMinimum = math.floor(tonumber(PSFuelConfig.StartFuelMin) or 35)
        local startMaximum = math.floor(tonumber(PSFuelConfig.StartFuelMax) or 80)
        if startMaximum < startMinimum then startMinimum, startMaximum = startMaximum, startMinimum end
        startMinimum = math.max(0, math.min(math.floor(tonumber(PSFuelConfig.MaxFuel) or 100), startMinimum))
        startMaximum = math.max(startMinimum, math.min(math.floor(tonumber(PSFuelConfig.MaxFuel) or 100), startMaximum))
        fuelCache[plate] = (type(saved) == 'table' and tonumber(saved.fuel) or tonumber(saved))
            or (math.random(startMinimum, startMaximum) + 0.0)

        if type(saved) == 'table' then
            leakCache[plate] = tonumber(saved.leak_level) or 0
        end
    end
    SetVehicleFuelLevel(vehicle, fuelCache[plate])
    if fuelDecorEnabled() then DecorSetFloat(vehicle, fuelDecor, fuelCache[plate] + 0.0) end
    return fuelCache[plate]
end

local function setFuel(vehicle, amount)
    if not DoesEntityExist(vehicle) then return end
    local plate = trimPlate(vehicle)
    local fuel = math.max(0.0, math.min(PSFuelConfig.MaxFuel, tonumber(amount) or 0.0))
    fuelCache[plate] = fuel
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    dirtyFuel[plate] = { fuel = fuel, netId = netId, leak = leakCache[plate] or 0 }
    SetVehicleFuelLevel(vehicle, fuel)
    if fuelDecorEnabled() then DecorSetFloat(vehicle, fuelDecor, fuel + 0.0) end
    Entity(vehicle).state:set('recoilFuel', fuel, true)

    local shutOffLevel = math.max(0.0, tonumber((PSFuelConfig.Safety or {}).ShutOffAtFuel) or 0.0)
    local empty = fuel <= shutOffLevel
    SetVehicleUndriveable(vehicle, empty)
    if empty then SetVehicleEngineOn(vehicle, false, true, true) end
end

local function vehicleUsesDiesel(vehicle)
    return configuredVehicleProfile(vehicle).fuelType == 'diesel'
end

local function isElectricVehicle(vehicle)
    return configuredVehicleProfile(vehicle).fuelType == 'electric'
end

local function vehicleSupportsFastCharge(vehicle)
    local profile = configuredVehicleProfile(vehicle)
    return profile.fuelType == 'electric' and profile.fastCharge == true
end

local function fuelTypeAllowed(vehicle, fuelType)
    if not DoesEntityExist(vehicle) then return false end
    fuelType = tostring(fuelType or PSFuelConfig.FuelTypes.Default):lower()
    local profile = configuredVehicleProfile(vehicle)

    if fuelType == 'electric' then return profile.fuelType == 'electric' end
    if fuelType == 'electric_fast' then
        return profile.fuelType == 'electric' and profile.fastCharge == true
    end
    if profile.fuelType == 'electric' then return false end
    if fuelType == 'diesel' then return profile.fuelType == 'diesel' end
    return profile.fuelType == 'petrol' and (fuelType == 'petrol' or fuelType == 'premium')
end

local function getVehicleLabel(vehicle)
    local display = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local label = GetLabelText(display)
    if not label or label == 'NULL' then label = display end
    return label or 'Vehicle'
end

local function buildVehicleData(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return nil end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 then
        NetworkRegisterEntityAsNetworked(vehicle)
        netId = NetworkGetNetworkIdFromEntity(vehicle)
    end
    if netId == 0 then return nil end

    local profile = configuredVehicleProfile(vehicle)
    local electric = profile.fuelType == 'electric'
    local allowedFuelTypes = {}

    if electric then
        allowedFuelTypes[1] = 'electric'
        if profile.fastCharge == true and ((PSFuelConfig.Electric or {}).FastCharge or {}).Enabled ~= false then
            allowedFuelTypes[#allowedFuelTypes + 1] = 'electric_fast'
        end
    else
        for key, value in pairs(PSFuelConfig.FuelTypes or {}) do
            if type(value) == 'table' and fuelTypeAllowed(vehicle, key) then
                allowedFuelTypes[#allowedFuelTypes + 1] = key
            end
        end
    end

    return {
        netId = netId,
        plate = trimPlate(vehicle),
        label = getVehicleLabel(vehicle),
        fuel = getFuel(vehicle),
        maxFuel = PSFuelConfig.MaxFuel,
        diesel = vehicleUsesDiesel(vehicle),
        electric = electric,
        fastCharge = profile.fastCharge == true,
        fuelProfileSource = profile.source,
        allowedFuelTypes = allowedFuelTypes,
    }
end

local function showFuelUi(mode, data)
    uiOpen = true
    lastFuelMessage = { action = 'open', mode = mode, data = data }
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    sendFuelNui(lastFuelMessage)
end

local function openPanel(mode, stationId)
    local data
    if mode == 'admin' then
        data = lib.callback.await('ps-fuel:server:getAdminData', false)
    else
        data = lib.callback.await('ps-fuel:server:getStationPanel', false, stationId)
    end
    if not data then return notify('You must own this station before accessing its management tablet.', 'error') end

    if mode == 'station' then
        local vehicle = closestVehicle()
        if vehicle and closestPump() then
            local vehicleData = buildVehicleData(vehicle)
            if vehicleData then
                data.vehicle = vehicleData
                activeFuelSession = { vehicle = vehicle, stationId = stationId }
            end
        end
    end

    showFuelUi(mode, data)
end

local function openRefuelPanel(vehicle, station, context)
    if uiOpen or isRefuelling then return end
    context = type(context) == 'table' and context or {}
    if not vehicle or not DoesEntityExist(vehicle) then
        return notify('Move a vehicle closer to the pump.', 'error')
    end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 then
        NetworkRegisterEntityAsNetworked(vehicle)
        netId = NetworkGetNetworkIdFromEntity(vehicle)
    end

    local data = lib.callback.await(
        'ps-fuel:server:getRefuelPanel',
        false,
        station.id,
        netId,
        GetVehicleClass(vehicle),
        context.nozzleKind,
        context.chargerId,
        context.sessionToken
    )
    local vehicleData = buildVehicleData(vehicle)
    if not data or not vehicleData then
        return notify('Unable to prepare the refuelling terminal.', 'error')
    end

    data.vehicle = vehicleData
    data.paymentAccount = context.paymentAccount
        or data.paymentAccount
        or (PSFuelConfig.Payment or {}).DefaultAccount
        or PSFuelConfig.PaymentAccount
    data.nozzleKind = context.nozzleKind
    data.physicalNozzle = context.physicalNozzle == true
    data.sessionToken = context.sessionToken

    activeFuelSession = {
        vehicle = vehicle,
        stationId = station.id,
        paymentAccount = data.paymentAccount,
        nozzleKind = context.nozzleKind,
        chargerId = context.chargerId,
        physicalNozzle = context.physicalNozzle == true,
        sessionToken = context.sessionToken,
    }
    showFuelUi('refuel', data)
end

local function openStationTablet(station)
    if not station then return notify('No fuel station is nearby.', 'error') end

    local access = lib.callback.await('ps-fuel:server:getStationAccess', false, station.id)
    if not access then return notify('Move closer to the fuel station.', 'error') end

    if access.ownershipEnabled == false then
        if access.isAdmin and access.allowed then
            return openPanel('station', station.id)
        end
        return notify('This is a public fuel station. Anyone can refuel here, but players cannot purchase or manage it.', 'inform')
    end

    if not access.owned then
        local decision = lib.alertDialog({
            header = ('Purchase %s'):format(access.label),
            content = ('This station must be purchased before its management tablet can be used. Purchase price: **£%s**.'):format(access.purchasePrice),
            centered = true,
            cancel = true,
            labels = { confirm = 'Purchase station', cancel = 'Not now' }
        })
        if decision ~= 'confirm' then return end

        local purchase = lib.callback.await('ps-fuel:server:buyStation', false, station.id)
        if not purchase or not purchase.success then
            return notify(purchase and purchase.message or 'Station purchase failed.', 'error')
        end
        notify(purchase.message or 'Fuel station purchased.', 'success')
        Wait(150)
        return openPanel('station', station.id)
    end

    if not access.allowed then
        return notify(('This station belongs to %s. Only its owner can use the management tablet.'):format(access.owner or 'another player'), 'error')
    end

    openPanel('station', station.id)
end

local function getFuelTypeLabel(fuelType)
    if fuelType == 'electric_fast' then return 'Fast charge' end
    if fuelType == 'electric' then return 'Standard charge' end
    local fuelConfig = PSFuelConfig.FuelTypes and PSFuelConfig.FuelTypes[fuelType]
    return (type(fuelConfig) == 'table' and fuelConfig.label) or tostring(fuelType or 'Fuel')
end

local function selectedFuelForVehicle(vehicle, station)
    local selection = selectedPumpFuel
    if not selection then return nil end

    if (selection.expiresAt or 0) <= GetGameTimer() then
        selectedPumpFuel = nil
        return nil
    end

    if not vehicle or not DoesEntityExist(vehicle) or not station
        or selection.stationId ~= station.id
        or selection.netId ~= NetworkGetNetworkIdFromEntity(vehicle)
        or selection.plate ~= trimPlate(vehicle)
        or not fuelTypeAllowed(vehicle, selection.fuelType)
    then
        selectedPumpFuel = nil
        return nil
    end

    return selection
end

local function refuelVehicle(vehicle, station, fuelType, options)
    if isRefuelling then return end
    options = type(options) == 'table' and options or {}
    fuelType = tostring(fuelType or PSFuelConfig.FuelTypes.Default):lower()

    if not fuelTypeAllowed(vehicle, fuelType) then
        selectedPumpFuel = nil
        return notify('That fuel type is not compatible with this vehicle.', 'error')
    end

    local physicalNozzle = options.physicalNozzle == true
        or (PSFuelNozzle and PSFuelNozzle.IsReadyFor and PSFuelNozzle.IsReadyFor(vehicle, options.nozzleKind))

    if (PSFuelConfig.Nozzles or {}).RequireNozzle == true and not physicalNozzle then
        selectedPumpFuel = nil
        return notify('Take a nozzle and insert it into the vehicle first.', 'error')
    end

    if not isElectricFuelType(fuelType)
        and (PSFuelConfig.Safety or {}).RequireEngineOff ~= false
        and GetIsVehicleEngineRunning(vehicle)
    then
        return notify('Turn the engine off before refuelling.', 'error')
    end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 then
        NetworkRegisterEntityAsNetworked(vehicle)
        netId = NetworkGetNetworkIdFromEntity(vehicle)
    end
    if netId == 0 then return notify('Vehicle is not networked.', 'error') end

    local fuelLabel = getFuelTypeLabel(fuelType)
    local electric = isElectricFuelType(fuelType)
    local fastCharging = fuelType == 'electric_fast'
    local fastConfig = (PSFuelConfig.Electric or {}).FastCharge or {}
    local refuelSpeed = electric
        and (fastCharging
            and (tonumber(fastConfig.ChargeSpeed) or tonumber(PSFuelConfig.Electric.ChargeSpeed) or 1.0)
            or (tonumber(PSFuelConfig.Electric.ChargeSpeed) or 1.0))
        or (tonumber(PSFuelConfig.RefuelSpeed) or 1.0)
    local paymentAccount = options.paymentAccount
        or (PSFuelNozzle and PSFuelNozzle.GetPaymentAccount and PSFuelNozzle.GetPaymentAccount())
        or (PSFuelConfig.Payment or {}).DefaultAccount
        or PSFuelConfig.PaymentAccount

    if physicalNozzle and PSFuelNozzle and PSFuelNozzle.OnRefuelStart then
        if not PSFuelNozzle.OnRefuelStart(vehicle, fuelType) then
            return notify('The physical nozzle is no longer connected.', 'error')
        end
    end

    local safety = PSFuelConfig.Safety or {}
    if not electric and safety.VehicleBlowUp == true and GetIsVehicleEngineRunning(vehicle) then
        if math.random(100) <= math.max(0, math.min(100, tonumber(safety.BlowUpChance) or 5)) then
            local explosionCoords = GetEntityCoords(vehicle)
            AddExplosion(explosionCoords.x, explosionCoords.y, explosionCoords.z, 5, 50.0, true, false, true)
            if physicalNozzle and PSFuelNozzle and PSFuelNozzle.OnRefuelStop then
                PSFuelNozzle.OnRefuelStop(fuelType)
            end
            return
        end
    end

    isRefuelling = true

    local purchased, paid = 0.0, 0
    activeWorldFuelDisplay = {
        vehicle = vehicle,
        electric = electric,
        fastCharging = fastCharging,
        label = fuelLabel,
        purchased = 0.0,
        paid = 0,
    }
    local cancelled = false
    local stopReason

    while isRefuelling do
        local tickEnds = GetGameTimer() + PSFuelConfig.RefuelTick
        while GetGameTimer() < tickEnds do
            Wait(0)
            if IsControlJustPressed(0, PSFuelConfig.CancelRefuelKey or 73) then
                cancelled = true
                break
            end
        end
        if cancelled then break end

        local validSource
        if physicalNozzle and PSFuelNozzle and PSFuelNozzle.IsSessionValid then
            validSource = PSFuelNozzle.IsSessionValid(vehicle, station)
        else
            local nearest, stationDistance = nearestStation()
            validSource = closestPump()
                and nearest
                and nearest.id == station.id
                and stationDistance
                and stationDistance <= stationInteractionDistance(station)
        end

        if not validSource
            or not DoesEntityExist(vehicle)
            or #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > (PSFuelConfig.VehicleDistance + 1.5)
        then
            stopReason = ('%s stopped because you moved away from the %s or vehicle.'):format(
                electric and 'Charging' or 'Refuelling',
                electric and 'charger' or 'pump'
            )
            break
        end

        local fuel = getFuel(vehicle)
        if fuel >= PSFuelConfig.MaxFuel then
            stopReason = electric and 'The battery is fully charged.' or 'The tank is full.'
            break
        end

        local amount = math.min(refuelSpeed, PSFuelConfig.MaxFuel - fuel)
        local response = lib.callback.await(
            'ps-fuel:server:purchaseFuel', false,
            station.id, netId, amount, fuelType, GetVehicleClass(vehicle),
            paymentAccount, options.chargerId, options.sessionToken
        )

        if not response or not response.success then
            stopReason = response and response.message or 'Payment failed.'
            break
        end

        setFuel(vehicle, fuel + amount)
        purchased = purchased + amount
        paid = paid + (tonumber(response.price) or 0)
        if activeWorldFuelDisplay then
            activeWorldFuelDisplay.purchased = purchased
            activeWorldFuelDisplay.paid = paid
        end
    end

    activeWorldFuelDisplay = nil
    isRefuelling = false
    selectedPumpFuel = nil

    if physicalNozzle and PSFuelNozzle and PSFuelNozzle.OnRefuelStop then
        PSFuelNozzle.OnRefuelStop(fuelType)
    end

    if purchased > 0 then
        notify(('%s %.1f%% for £%s.'):format(electric and 'Charged' or 'Purchased', purchased, paid), 'success')
    elseif cancelled then
        notify(electric and 'Charging cancelled.' or 'Refuelling cancelled.', 'warning')
    elseif stopReason then
        local successfulStop = stopReason == 'The tank is full.' or stopReason == 'The battery is fully charged.'
        notify(stopReason, successfulStop and 'success' or 'error')
    end
end

local function safeNuiCallback(callbackName, callback, data, cb)
    local ok, response = pcall(callback, data or {})

    if not ok then
        lib.print.error(('[ps-fuel] NUI callback %s failed: %s'):format(callbackName, response))
        cb({
            success = false,
            message = ('%s failed. Check the F8/server console.'):format(callbackName)
        })
        return
    end

    if response == nil then
        response = {
            success = false,
            message = ('%s returned no response.'):format(callbackName)
        }
    end

    cb(response)
end

RegisterNUICallback('fuelClose', function(_, cb)
    forceCloseUi()
    cb({ success = true })
end)

RegisterNUICallback('nuiNotify', function(data, cb)
    notify(data.message or 'Fuel action completed.', data.type or 'inform')
    cb({ success = true })
end)

RegisterNUICallback('refreshStation', function(data, cb)
    safeNuiCallback('refreshStation', function(payload)
        local stationData = lib.callback.await(
            'ps-fuel:server:getStationPanel',
            false,
            payload.stationId
        )

        return {
            success = stationData ~= nil,
            data = stationData,
            message = stationData and nil or 'Unable to refresh station data.'
        }
    end, data, cb)
end)

RegisterNUICallback('buyStation', function(data, cb)
    safeNuiCallback('buyStation', function(payload)
        return lib.callback.await(
            'ps-fuel:server:buyStation',
            false,
            payload.stationId
        )
    end, data, cb)
end)

RegisterNUICallback('withdraw', function(data, cb)
    safeNuiCallback('withdraw', function(payload)
        return lib.callback.await(
            'ps-fuel:server:withdrawStation',
            false,
            payload.stationId
        )
    end, data, cb)
end)

RegisterNUICallback('setMultiplier', function(data, cb)
    safeNuiCallback('setMultiplier', function(payload)
        return lib.callback.await(
            'ps-fuel:server:setStationMultiplier',
            false,
            payload.stationId,
            tonumber(payload.multiplier)
        )
    end, data, cb)
end)

RegisterNUICallback('buyJerryCan', function(data, cb)
    safeNuiCallback('buyJerryCan', function(payload)
        return lib.callback.await(
            'ps-fuel:server:buyJerryCan',
            false,
            payload.stationId
        )
    end, data, cb)
end)

RegisterNUICallback('selectFuelType', function(data, cb)
    safeNuiCallback('selectFuelType', function(payload)
        local session = activeFuelSession
        if not session or not DoesEntityExist(session.vehicle) then
            return { success = false, message = 'The vehicle is no longer available.' }
        end

        local station = stationById(session.stationId)
        local nearest, stationDistance = nearestStation()
        local physicalReady = session.physicalNozzle
            and PSFuelNozzle
            and PSFuelNozzle.IsReadyFor
            and PSFuelNozzle.IsReadyFor(session.vehicle, session.nozzleKind)

        if not station then
            return { success = false, message = 'The station configuration is no longer available.' }
        end

        if not physicalReady and (not nearest or nearest.id ~= station.id
            or stationDistance > stationInteractionDistance(station) or not closestPump())
        then
            return { success = false, message = 'Stay beside the pump while selecting fuel.' }
        end

        local fuelType = tostring(payload.fuelType or PSFuelConfig.FuelTypes.Default):lower()
        if not fuelTypeAllowed(session.vehicle, fuelType) then
            return { success = false, message = 'That fuel type is not compatible with this vehicle.' }
        end

        if getFuel(session.vehicle) >= PSFuelConfig.MaxFuel then
            return { success = false, message = isElectricVehicle(session.vehicle) and 'The battery is already fully charged.' or 'The tank is already full.' }
        end

        local netId = NetworkGetNetworkIdFromEntity(session.vehicle)
        if netId == 0 then
            NetworkRegisterEntityAsNetworked(session.vehicle)
            netId = NetworkGetNetworkIdFromEntity(session.vehicle)
        end
        if netId == 0 then return { success = false, message = 'Vehicle network ID was lost.' } end

        selectedPumpFuel = {
            vehicle = session.vehicle,
            netId = netId,
            plate = trimPlate(session.vehicle),
            stationId = session.stationId,
            fuelType = fuelType,
            paymentAccount = session.paymentAccount,
            nozzleKind = session.nozzleKind,
            chargerId = session.chargerId,
            physicalNozzle = session.physicalNozzle == true,
            sessionToken = session.sessionToken,
            expiresAt = GetGameTimer() + (PSFuelConfig.FuelSelectionTimeout or 120000)
        }

        SetTimeout(100, function()
            forceCloseUi(true, false, true)
            if physicalReady then
                refuelVehicle(session.vehicle, station, fuelType, {
                    paymentAccount = session.paymentAccount,
                    nozzleKind = session.nozzleKind,
                    chargerId = session.chargerId,
                    physicalNozzle = true,
                    sessionToken = session.sessionToken,
                })
            else
                notify(('%s selected. Press E beside the pump to start refuelling.'):format(
                    getFuelTypeLabel(fuelType)
                ), 'success')
            end
        end)

        return {
            success = true,
            fuelType = fuelType,
            fuelLabel = getFuelTypeLabel(fuelType),
            message = physicalReady
                and ((isElectricFuelType(fuelType) and 'Charging started.') or 'Refuelling started.')
                or 'Fuel type selected. Press E at the pump to refuel.'
        }
    end, data, cb)
end)

RegisterNetEvent('ps-fuel:client:useJerryCan', function()
    if isRefuelling then return end
    local vehicle = closestVehicle()
    if not vehicle then return notify('Move closer to a vehicle.', 'error') end

    local electricVehicle = isElectricVehicle(vehicle)
    if electricVehicle then
        return notify('A petrol can cannot charge an electric vehicle.', 'error')
    end

    local fuel = getFuel(vehicle)
    if fuel >= PSFuelConfig.MaxFuel then return notify('The tank is already full.', 'error') end

    if (PSFuelConfig.Safety or {}).RequireEngineOff ~= false and GetIsVehicleEngineRunning(vehicle) then
        return notify('Turn the engine off before using the fuel can.', 'error')
    end

    local completed = lib.progressCircle({
        duration = 6500,
        label = 'Pouring fuel...',
        position = 'bottom',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'weapon@w_sp_jerrycan', clip = 'fire' }
    })

    if not completed then
        notify('Jerry can use was cancelled.', 'warning')
        return
    end

    local consumed = lib.callback.await('ps-fuel:server:consumeJerryCan', false)
    if not consumed or consumed.success ~= true then
        return notify(consumed and consumed.message or 'You do not have a usable jerry can.', 'error')
    end

    local amount = math.min(
        tonumber(consumed.fuelAmount) or tonumber(PSFuelConfig.JerryCan.FuelAmount) or 25.0,
        PSFuelConfig.MaxFuel - fuel
    )
    setFuel(vehicle, fuel + amount)
    notify(('Added %.1f%% fuel from the emergency fuel can.'):format(amount), 'success')
end)

RegisterNetEvent('ps-fuel:client:openAdmin', function()
    openPanel('admin')
end)

RegisterNetEvent('ps-fuel:client:openFromTablet', function(context)
    if openFuelApp then openFuelApp(type(context) == 'table' and context or {}) end
end)

CreateThread(function()
    if (PSFuelConfig.Nozzles or {}).Enabled == true and (PSFuelConfig.Nozzles or {}).RequireNozzle == true then
        return
    end

    while true do
        local sleep = 1000
        if not cache.vehicle and not isRefuelling and not uiOpen then
            local pump = closestPump()
            local station, stationDistance = nearestStation()
            if pump and station and stationDistance <= stationInteractionDistance(station) then
                sleep = 0
                local vehicle = closestVehicle()
                if vehicle then
                    local selection = selectedFuelForVehicle(vehicle, station)
                    local managementEnabled = stationManagementEnabled(station)
                    if selection then
                        local fuelLabel = getFuelTypeLabel(selection.fuelType)
                        local prompt = managementEnabled
                            and ('[E] Refuel with %s  |  [H] Change fuel  |  [G] Station Tablet  |  Fuel %.1f%%'):format(fuelLabel, getFuel(vehicle))
                            or ('[E] Refuel with %s  |  [H] Change fuel  |  Public Station  |  Fuel %.1f%%'):format(fuelLabel, getFuel(vehicle))
                        lib.showTextUI(prompt, { position = 'left-center' })

                        if IsControlJustPressed(0, PSFuelConfig.RefuelKey) then
                            refuelVehicle(vehicle, station, selection.fuelType, {
                                paymentAccount = selection.paymentAccount,
                                nozzleKind = selection.nozzleKind,
                                chargerId = selection.chargerId,
                                physicalNozzle = selection.physicalNozzle,
                                sessionToken = selection.sessionToken,
                            })
                        elseif IsControlJustPressed(0, PSFuelConfig.ChangeFuelTypeKey or 74) then
                            selectedPumpFuel = nil
                            openRefuelPanel(vehicle, station)
                        elseif managementEnabled and IsControlJustPressed(0, PSFuelConfig.StationTablet.OpenKey) then
                            openStationTablet(station)
                        end
                    else
                        local prompt = managementEnabled
                            and ('[E] Select Fuel Type  |  [G] Station Tablet  |  Fuel %.1f%%'):format(getFuel(vehicle))
                            or ('[E] Select Fuel Type  |  Public Station  |  Fuel %.1f%%'):format(getFuel(vehicle))
                        lib.showTextUI(prompt, { position = 'left-center' })

                        if IsControlJustPressed(0, PSFuelConfig.RefuelKey) then
                            openRefuelPanel(vehicle, station)
                        elseif managementEnabled and IsControlJustPressed(0, PSFuelConfig.StationTablet.OpenKey) then
                            openStationTablet(station)
                        end
                    end
                else
                    if stationManagementEnabled(station) then
                        lib.showTextUI('[G] Purchase / Open Station Tablet', { position = 'left-center' })
                        if IsControlJustPressed(0, PSFuelConfig.StationTablet.OpenKey) then openStationTablet(station) end
                    else
                        lib.showTextUI('Public Fuel Station · Bring a vehicle beside a pump', { position = 'left-center' })
                    end
                end
            else
                lib.hideTextUI()
            end
        else
            lib.hideTextUI()
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        Wait(PSFuelConfig.FuelDrainTick)
        local vehicle = cache.vehicle
        if vehicle and GetPedInVehicleSeat(vehicle, -1) == cache.ped then
            local class = GetVehicleClass(vehicle)
            if class ~= 13 then
                local fuel = getFuel(vehicle)
                if GetIsVehicleEngineRunning(vehicle) and fuel > 0 then
                    local drain = (PSFuelConfig.BaseDrain + GetVehicleCurrentRpm(vehicle) * PSFuelConfig.RPMMultiplier) * (PSFuelConfig.ClassMultiplier[class] or 1.0)
                    setFuel(vehicle, fuel - drain)
                elseif fuel <= math.max(0.0, tonumber((PSFuelConfig.Safety or {}).ShutOffAtFuel) or 0.0) then
                    SetVehicleEngineOn(vehicle, false, true, true)
                    SetVehicleUndriveable(vehicle, true)
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(PSFuelConfig.PersistenceSaveInterval)
        for plate, entry in pairs(dirtyFuel) do
            if type(entry) == 'table' and tonumber(entry.netId) and tonumber(entry.netId) > 0 then
                TriggerServerEvent('ps-fuel:server:saveVehicleFuel', entry.netId, plate, entry.fuel, entry.leak or leakCache[plate] or 0)
            end
            dirtyFuel[plate] = nil
        end
    end
end)

AddStateBagChangeHandler('recoilFuel', nil, function(bagName, _, value)
    local entity = GetEntityFromStateBagName(bagName)
    if entity == 0 or GetEntityType(entity) ~= 2 then return end
    local plate = trimPlate(entity)
    fuelCache[plate] = tonumber(value) or fuelCache[plate]
    if fuelCache[plate] then
        SetVehicleFuelLevel(entity, fuelCache[plate])
        if fuelDecorEnabled() then DecorSetFloat(entity, fuelDecor, fuelCache[plate] + 0.0) end
    end
end)

local function drawFuelWorldText(coords, text, scale)
    local visible, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not visible then return end
    SetTextScale(0.0, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 235)
    SetTextCentre(true)
    SetTextDropshadow(1, 0, 0, 0, 180)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(screenX, screenY)
end

CreateThread(function()
    while true do
        local display = activeWorldFuelDisplay
        local cfg = PSFuelConfig.WorldDisplay or {}
        if cfg.Enabled ~= false and display and display.vehicle and DoesEntityExist(display.vehicle) then
            local vehicle = display.vehicle
            local pedCoords = GetEntityCoords(cache.ped or PlayerPedId())
            local vehicleCoords = GetEntityCoords(vehicle)
            if #(pedCoords - vehicleCoords) <= (tonumber(cfg.MaxDistance) or 25.0) then
                local _, maxDim = GetModelDimensions(GetEntityModel(vehicle))
                local height = (maxDim and maxDim.z or 1.0) + (tonumber(cfg.HeightOffset) or 1.35)
                local coords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, height)
                local mode = display.electric
                    and (display.fastCharging and 'FAST CHARGING' or 'CHARGING')
                    or 'REFUELLING'
                local line = ('~b~%s~s~  %.1f%%'):format(mode, getFuel(vehicle))
                if cfg.ShowFuelType ~= false and display.label then
                    line = ('%s  ~c~%s~s~'):format(line, display.label)
                end
                if cfg.ShowAmountPaid ~= false then
                    line = ('%s  ~g~£%s~s~'):format(line, math.floor(tonumber(display.paid) or 0))
                end
                drawFuelWorldText(coords, line, tonumber(cfg.Scale) or 0.34)
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

RegisterNetEvent('ps-fuel:client:vehicleProfileUpdated', function(profile)
    if type(profile) ~= 'table' then return end
    local modelHash = tonumber(profile.modelHash)
    if not modelHash then return end
    local key = vehicleProfileKey(modelHash)
    if profile.removed == true then
        vehicleProfiles[key] = nil
        return
    end
    local fuelType = tostring(profile.fuelType or ''):lower()
    if fuelType ~= 'petrol' and fuelType ~= 'diesel' and fuelType ~= 'electric' then return end
    vehicleProfiles[key] = {
        modelHash = modelHash,
        modelName = tostring(profile.modelName or modelHash),
        fuelType = fuelType,
        fastCharge = fuelType == 'electric' and profile.fastCharge == true or false,
    }
end)

local function openVehicleFuelConfiguration(vehicle)
    if (PSFuelConfig.VehicleConfiguration or {}).Enabled == false then return end
    if not canConfigureVehicleProfiles then
        return notify('You do not have permission to configure vehicle fuel types.', 'error')
    end
    vehicle = vehicle or closestVehicle()
    if not vehicle or not DoesEntityExist(vehicle) then
        return notify('Move closer to the vehicle you want to configure.', 'error')
    end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 then
        NetworkRegisterEntityAsNetworked(vehicle)
        netId = NetworkGetNetworkIdFromEntity(vehicle)
    end
    if netId == 0 then return notify('The vehicle is not networked.', 'error') end

    local modelHash = GetEntityModel(vehicle)
    local modelName = GetDisplayNameFromVehicleModel(modelHash)
    if not modelName or modelName == '' or modelName == 'CARNOTFOUND' then
        modelName = tostring(modelHash)
    end
    local current = configuredVehicleProfile(vehicle)
    local result = lib.inputDialog(('Configure %s'):format(getVehicleLabel(vehicle)), {
        {
            type = 'select',
            label = 'Vehicle energy type',
            description = 'This applies to every vehicle using this model.',
            required = true,
            default = current.source == 'database' and current.fuelType or 'automatic',
            options = {
                { value = 'automatic', label = 'Automatic detection / remove override' },
                { value = 'petrol', label = 'Petrol and premium' },
                { value = 'diesel', label = 'Diesel' },
                { value = 'electric', label = 'Electric' },
            },
        },
        {
            type = 'checkbox',
            label = 'Supports fast charging',
            description = 'Only used when the vehicle is configured as electric.',
            checked = current.fastCharge == true,
        },
    })
    if not result then return end

    local response = lib.callback.await(
        'ps-fuel:server:saveVehicleProfile',
        false,
        netId,
        result[1],
        result[2] == true,
        modelName
    )
    notify(response and response.message or 'Vehicle configuration failed.', response and response.success and 'success' or 'error')
end

local function initialiseVehicleConfiguration()
    local rows = lib.callback.await('ps-fuel:server:getVehicleProfiles', false)
    if type(rows) == 'table' then applyVehicleProfiles(rows) end
    canConfigureVehicleProfiles = lib.callback.await('ps-fuel:server:canConfigureVehicles', false) == true

    local cfg = PSFuelConfig.VehicleConfiguration or {}
    if canConfigureVehicleProfiles and cfg.AddOxTargetOption ~= false and not vehicleConfigTargetRegistered then
        exports.ox_target:addGlobalVehicle({
            {
                name = 'ps-fuel:configure-vehicle-profile',
                icon = 'fa-solid fa-car-battery',
                label = 'Configure vehicle fuel type',
                distance = tonumber(cfg.TargetDistance) or 3.0,
                canInteract = function(entity)
                    return canConfigureVehicleProfiles
                        and not isRefuelling
                        and entity ~= 0
                        and DoesEntityExist(entity)
                end,
                onSelect = function(data) openVehicleFuelConfiguration(data.entity) end,
            }
        })
        vehicleConfigTargetRegistered = true
    end
end

CreateThread(function()
    Wait(1500)
    for _ = 1, 3 do
        initialiseVehicleConfiguration()
        if next(vehicleProfiles) ~= nil or canConfigureVehicleProfiles then break end
        Wait(1500)
    end
end)

RegisterCommand((PSFuelConfig.VehicleConfiguration or {}).Command or 'fuelvehicleconfig', function()
    openVehicleFuelConfiguration(closestVehicle())
end, false)

RegisterCommand('fuel', function()
    local vehicle = cache.vehicle or closestVehicle()
    if not vehicle then return notify('No vehicle found.', 'error') end
    notify(('Fuel: %.1f%%'):format(getFuel(vehicle)), 'inform')
end)

RegisterNetEvent('ps-fuel:client:adminSetFuel', function(amount)
    local vehicle = cache.vehicle or closestVehicle()
    if not vehicle then return notify('Move closer to a vehicle.', 'error') end
    setFuel(vehicle, amount)
    notify(('Fuel set to %.1f%%.'):format(getFuel(vehicle)), 'success')
end)

exports('GetFuel', getFuel)
exports('SetFuel', setFuel)


local function nearestCharger()
    local coords, closest, distance = GetEntityCoords(cache.ped)
    for _, charger in ipairs(PSFuelConfig.Electric.Chargers) do
        local d = #(coords - charger.coords)
        if not distance or d < distance then closest, distance = charger, d end
    end
    return closest, distance
end

PSFuelRuntime.Notify = notify
PSFuelRuntime.StationById = stationById
PSFuelRuntime.NearestStation = nearestStation
PSFuelRuntime.ClosestPump = closestPump
PSFuelRuntime.ClosestVehicle = closestVehicle
PSFuelRuntime.GetFuel = getFuel
PSFuelRuntime.SetFuel = setFuel
PSFuelRuntime.IsElectricVehicle = isElectricVehicle
PSFuelRuntime.SupportsFastCharge = vehicleSupportsFastCharge
PSFuelRuntime.GetVehicleProfile = configuredVehicleProfile
PSFuelRuntime.FuelTypeAllowed = fuelTypeAllowed
PSFuelRuntime.OpenRefuelPanel = openRefuelPanel
PSFuelRuntime.RefuelVehicle = refuelVehicle
PSFuelRuntime.IsRefuelling = function() return isRefuelling end
PSFuelRuntime.CloseFuelUi = function(silent) forceCloseUi(false, silent == true, false) end
PSFuelRuntime.PlaySound = function(name, volume, looped)
    sendFuelNui({
        action = 'psFuelSound',
        command = 'play',
        name = name,
        volume = volume,
        loop = looped == true,
    })
end
PSFuelRuntime.StopSound = function(name)
    sendFuelNui({
        action = 'psFuelSound',
        command = 'stop',
        name = name,
    })
end
PSFuelRuntime.StopAllSounds = function()
    sendFuelNui({ action = 'psFuelSound', command = 'stopAll' })
end

local function setLeakLevel(vehicle, level)
    local plate = trimPlate(vehicle)
    leakCache[plate] = math.max(0, math.min(2, tonumber(level) or 0))
    dirtyFuel[plate] = {
        fuel = fuelCache[plate] or getFuel(vehicle),
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        leak = leakCache[plate] or 0,
    }
    Entity(vehicle).state:set('recoilFuelLeak', leakCache[plate], true)
end


local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)

    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return nil
    end

    RequestModel(hash)

    local timeout = GetGameTimer() + 15000

    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            return nil
        end

        Wait(50)
    end

    return hash
end

local function spawnDeliveryVehicle(model, coords)
    local hash = loadModel(model)

    if not hash then
        return nil
    end

    local vehicle = CreateVehicle(
        hash,
        coords.x,
        coords.y,
        coords.z,
        coords.w,
        true,
        true
    )

    SetModelAsNoLongerNeeded(hash)

    if vehicle == 0 then
        return nil
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleFuelLevel(vehicle, 100.0)

    local netId = NetworkGetNetworkIdFromEntity(vehicle)

    if netId ~= 0 then
        SetNetworkIdCanMigrate(netId, true)
    end

    return vehicle
end

local function teleportPlayer(coords)
    DoScreenFadeOut(500)

    while not IsScreenFadedOut() do
        Wait(50)
    end

    SetEntityCoordsNoOffset(
        cache.ped,
        coords.x,
        coords.y,
        coords.z,
        false,
        false,
        false
    )

    SetEntityHeading(cache.ped, coords.w)

    Wait(500)
    DoScreenFadeIn(500)
end

local fuelStationBlips = {}

local function removeFuelStationBlips()
    for _, blip in ipairs(fuelStationBlips) do
        if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    fuelStationBlips = {}
end

local function createStationBlip(station)
    if station.blip == false then return end

    local defaults = PSFuelConfig.Blips or {}
    local override = type(station.blip) == 'table' and station.blip or {}
    local publicStation = not stationOwnershipEnabled(station)
    local colour = override.Colour or override.colour
        or (publicStation and defaults.PublicColour)
        or defaults.PlayerOwnedColour
        or defaults.Colour
        or 2

    local blip = AddBlipForCoord(station.coords.x, station.coords.y, station.coords.z)
    SetBlipSprite(blip, tonumber(override.Sprite or override.sprite or defaults.Sprite) or 361)
    SetBlipColour(blip, tonumber(colour) or 2)
    SetBlipScale(blip, tonumber(override.Scale or override.scale or defaults.Scale) or 0.75)
    SetBlipAsShortRange(blip, override.ShortRange ~= false and defaults.ShortRange ~= false)
    SetBlipDisplay(blip, tonumber(override.Display or override.display or defaults.Display) or 4)
    if defaults.Category or override.Category then
        SetBlipCategory(blip, tonumber(override.Category or defaults.Category) or 1)
    end

    local label = tostring(override.Label or override.label or station.label or 'Fuel Station')
    if publicStation and defaults.ShowPublicSuffix ~= false then
        label = label .. tostring(defaults.PublicSuffix or ' · Public')
    end

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)

    fuelStationBlips[#fuelStationBlips + 1] = blip
end

local function refreshFuelStationBlips()
    removeFuelStationBlips()
    if (PSFuelConfig.Blips or {}).Enabled == false then return end
    for _, station in ipairs(PSFuelConfig.Stations or {}) do createStationBlip(station) end
end

CreateThread(function()
    Wait(500)
    refreshFuelStationBlips()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    removeFuelStationBlips()
end)

RegisterNUICallback('startDelivery', function(data, cb)
    safeNuiCallback('startDelivery', function(payload)
        local response = lib.callback.await(
            'ps-fuel:server:startDelivery',
            false,
            payload.stationId
        )

        if not response or not response.success then
            return response
        end

        local pickup = vector4(
            response.pickup.x,
            response.pickup.y,
            response.pickup.z,
            response.pickup.w
        )

        teleportPlayer(pickup)

        local spawnResponse = lib.callback.await(
            'ps-fuel:server:spawnDeliveryVehicles',
            false,
            response.stationId
        )

        if not spawnResponse or not spawnResponse.success then
            return {
                success = false,
                message = spawnResponse
                    and spawnResponse.message
                    or 'Failed to spawn delivery vehicles.'
            }
        end

        local timeout = GetGameTimer() + 15000
        local truck
        local trailer

        while GetGameTimer() < timeout do
            truck = NetworkGetEntityFromNetworkId(
                spawnResponse.truckNetId
            )

            trailer = NetworkGetEntityFromNetworkId(
                spawnResponse.trailerNetId
            )

            if truck
                and truck ~= 0
                and DoesEntityExist(truck)
                and trailer
                and trailer ~= 0
                and DoesEntityExist(trailer)
            then
                break
            end

            Wait(100)
        end

        if not truck
            or truck == 0
            or not DoesEntityExist(truck)
        then
            return {
                success = false,
                message = 'The delivery truck did not stream in.'
            }
        end

        if not trailer
            or trailer == 0
            or not DoesEntityExist(trailer)
        then
            return {
                success = false,
                message = 'The fuel tanker did not stream in.'
            }
        end

        SetEntityAsMissionEntity(
            truck,
            true,
            true
        )

        SetEntityAsMissionEntity(
            trailer,
            true,
            true
        )

        SetVehicleOnGroundProperly(
            truck
        )

        SetVehicleOnGroundProperly(
            trailer
        )

        if PSFuelConfig.Deliveries.AutoAttachTrailer then
            local attachTimeout =
                GetGameTimer() + 5000

            while not IsVehicleAttachedToTrailer(
                truck
            ) and GetGameTimer() < attachTimeout do
                AttachVehicleToTrailer(
                    truck,
                    trailer,
                    1.1
                )

                Wait(250)
            end
        end

        SetPedIntoVehicle(
            cache.ped,
            truck,
            -1
        )

        if GetVehiclePedIsIn(
            cache.ped,
            false
        ) ~= truck then
            TaskWarpPedIntoVehicle(
                cache.ped,
                truck,
                -1
            )
        end

        SetVehicleEngineOn(
            truck,
            true,
            true,
            false
        )

        activeDelivery = response
        activeDelivery.truck = truck
        activeDelivery.trailer = trailer
        activeDelivery.stage = 'drive_to_terminal'
        activeDelivery.tankerLoaded = false

        local terminal = response.loadingTerminal

        SetNewWaypoint(
            terminal.Coords.x,
            terminal.Coords.y
        )

        notify(
            'Drive the tanker to the fuel loading terminal and fill it.',
            'success'
        )

        return {
            success = true,
            message = 'Delivery started. Drive to the loading terminal.'
        }
    end, data, cb)
end)

RegisterNUICallback('startRobbery', function(data, cb)
    safeNuiCallback('startRobbery', function(payload)
        local response = lib.callback.await(
            'ps-fuel:server:startRobbery',
            false,
            payload.stationId
        )

        if not response or not response.success then
            return response
        end

        CreateThread(function()
            forceCloseUi()

            local completed = lib.progressCircle({
                duration = response.duration,
                label = 'Emptying station safe...',
                position = 'bottom',
                canCancel = true,
                disable = {
                    move = true,
                    car = true,
                    combat = true
                },
                anim = {
                    dict = 'anim@heists@ornate_bank@grab_cash',
                    clip = 'grab'
                }
            })

            if completed then
                local finish = lib.callback.await(
                    'ps-fuel:server:completeRobbery',
                    false,
                    payload.stationId,
                    response.token
                )

                notify(
                    finish and finish.message or 'Robbery failed.',
                    finish and finish.success and 'success' or 'error'
                )
            else
                TriggerServerEvent('ps-fuel:server:cancelRobbery', response.token)
                notify('Robbery cancelled.', 'warning')
            end
        end)

        return {
            success = true,
            message = 'Robbery started.'
        }
    end, data, cb)
end)

RegisterNetEvent('ps-fuel:client:marketUpdate', function(multiplier)
    notify(('Fuel market changed to x%.2f.'):format(multiplier), 'inform')
end)

CreateThread(function()
    local terminalBlip

    while true do
        local sleep = 1000

        if activeDelivery then
            sleep = 0

            if activeDelivery.stage == 'drive_to_terminal' then
                local terminal = PSFuelConfig.Deliveries.LoadingTerminal
                local distance = #(
                    GetEntityCoords(cache.ped)
                    - terminal.Coords
                )

                if not terminalBlip then
                    terminalBlip = AddBlipForCoord(
                        terminal.Coords.x,
                        terminal.Coords.y,
                        terminal.Coords.z
                    )

                    SetBlipSprite(
                        terminalBlip,
                        terminal.BlipSprite
                    )

                    SetBlipColour(
                        terminalBlip,
                        terminal.BlipColour
                    )

                    SetBlipScale(
                        terminalBlip,
                        terminal.BlipScale
                    )

                    SetBlipRoute(
                        terminalBlip,
                        true
                    )

                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString(
                        terminal.Label
                    )
                    EndTextCommandSetBlipName(
                        terminalBlip
                    )
                end

                if distance <= terminal.Radius then
                    lib.showTextUI(
                        '[E] Fill fuel tanker',
                        {
                            position = 'right-center'
                        }
                    )

                    if IsControlJustPressed(
                        0,
                        PSFuelConfig.RefuelKey
                    ) then
                        local truckExists =
                            activeDelivery.truck
                            and DoesEntityExist(
                                activeDelivery.truck
                            )

                        local trailerExists =
                            activeDelivery.trailer
                            and DoesEntityExist(
                                activeDelivery.trailer
                            )

                        if not truckExists
                            or not trailerExists
                        then
                            notify(
                                'The delivery truck or tanker is missing.',
                                'error'
                            )

                            activeDelivery = nil
                            lib.hideTextUI()

                            if terminalBlip then
                                RemoveBlip(
                                    terminalBlip
                                )

                                terminalBlip = nil
                            end
                        else
                            local completed =
                                lib.progressCircle({
                                    duration =
                                        terminal.FillDuration,

                                    label =
                                        'Filling tanker with fuel...',

                                    position = 'bottom',

                                    canCancel = true,

                                    disable = {
                                        move = true,
                                        car = true,
                                        combat = true
                                    }
                                })

                            if completed then
                                local response =
                                    lib.callback.await(
                                        'ps-fuel:server:markTankerLoaded',
                                        false,
                                        activeDelivery.stationId
                                    )

                                if response
                                    and response.success
                                then
                                    activeDelivery.stage =
                                        'return_to_station'

                                    activeDelivery.tankerLoaded =
                                        true

                                    if terminalBlip then
                                        RemoveBlip(
                                            terminalBlip
                                        )

                                        terminalBlip = nil
                                    end

                                    SetNewWaypoint(
                                        response.destination.x,
                                        response.destination.y
                                    )

                                    notify(
                                        response.message,
                                        'success'
                                    )
                                else
                                    notify(
                                        response
                                            and response.message
                                            or 'Failed to load the tanker.',

                                        'error'
                                    )
                                end
                            end
                        end
                    end
                else
                    lib.hideTextUI()
                end

            elseif activeDelivery.stage == 'return_to_station' then
                local station

                for _, value in ipairs(
                    PSFuelConfig.Stations
                ) do
                    if value.id
                        == activeDelivery.stationId
                    then
                        station = value
                        break
                    end
                end

                if station then
                    local distance = #(
                        GetEntityCoords(cache.ped)
                        - station.coords
                    )

                    if distance
                        <= PSFuelConfig.Deliveries.MaxDeliveryDistance
                    then
                        local truckExists =
                            activeDelivery.truck
                            and DoesEntityExist(
                                activeDelivery.truck
                            )

                        local trailerExists =
                            activeDelivery.trailer
                            and DoesEntityExist(
                                activeDelivery.trailer
                            )

                        if truckExists
                            and trailerExists
                        then
                            lib.showTextUI(
                                '[E] Unload fuel into station',
                                {
                                    position =
                                        'right-center'
                                }
                            )

                            if IsControlJustPressed(
                                0,
                                PSFuelConfig.RefuelKey
                            ) then
                                local unloading =
                                    lib.progressCircle({
                                        duration = 20000,
                                        label =
                                            'Unloading fuel into station...',

                                        position = 'bottom',
                                        canCancel = true,

                                        disable = {
                                            move = true,
                                            car = true,
                                            combat = true
                                        }
                                    })

                                if unloading then
                                    local response =
                                        lib.callback.await(
                                            'ps-fuel:server:completeDelivery',
                                            false,
                                            activeDelivery.stationId
                                        )

                                    notify(
                                        response
                                            and response.message
                                            or 'Delivery failed.',

                                        response
                                            and response.success
                                            and 'success'
                                            or 'error'
                                    )

                                    if response
                                        and response.success
                                    then
                                        if PSFuelConfig.Deliveries.DeleteVehiclesOnComplete
                                        then
                                            if DoesEntityExist(
                                                activeDelivery.trailer
                                            ) then
                                                SetEntityAsMissionEntity(
                                                    activeDelivery.trailer,
                                                    true,
                                                    true
                                                )

                                                DeleteVehicle(
                                                    activeDelivery.trailer
                                                )
                                            end

                                            if DoesEntityExist(
                                                activeDelivery.truck
                                            ) then
                                                SetEntityAsMissionEntity(
                                                    activeDelivery.truck,
                                                    true,
                                                    true
                                                )

                                                DeleteVehicle(
                                                    activeDelivery.truck
                                                )
                                            end
                                        end

                                        activeDelivery = nil
                                        lib.hideTextUI()
                                    end
                                end
                            end
                        else
                            notify(
                                'The delivery truck or tanker is missing.',
                                'error'
                            )

                            activeDelivery = nil
                            lib.hideTextUI()
                        end
                    else
                        lib.hideTextUI()
                    end
                end
            end
        else
            if terminalBlip then
                RemoveBlip(
                    terminalBlip
                )

                terminalBlip = nil
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        Wait(750)
        if PSFuelConfig.Leaks.Enabled and cache.vehicle and GetPedInVehicleSeat(cache.vehicle, -1) == cache.ped then
            local vehicle = cache.vehicle
            local health = GetVehicleBodyHealth(vehicle)
            local previous = lastBodyHealth[vehicle] or health
            local damage = previous - health
            if damage >= PSFuelConfig.Leaks.MinimumImpactDamage then
                local severe = damage >= PSFuelConfig.Leaks.SevereImpactDamage
                local chance = severe and PSFuelConfig.Leaks.SevereChancePercent or PSFuelConfig.Leaks.ChancePercent
                if math.random(100) <= chance then
                    local level = severe and 2 or 1
                    if (leakCache[trimPlate(vehicle)] or 0) < level then
                        setLeakLevel(vehicle, level)
                        notify(severe and 'Severe fuel tank rupture detected.' or 'Fuel tank damaged. Fuel is leaking.', 'error')
                    end
                end
            end
            lastBodyHealth[vehicle] = health
        end
    end
end)

CreateThread(function()
    while true do
        Wait(PSFuelConfig.FuelDrainTick)
        local vehicle = cache.vehicle
        if vehicle and GetPedInVehicleSeat(vehicle, -1) == cache.ped then
            local leak = leakCache[trimPlate(vehicle)] or 0
            if leak > 0 then
                local drain = leak == 2 and PSFuelConfig.Leaks.SevereDrainPerTick or PSFuelConfig.Leaks.NormalDrainPerTick
                setFuel(vehicle, getFuel(vehicle) - drain)
            end
        end
    end
end)

RegisterCommand((PSFuelConfig.Leaks or {}).RepairCommand or 'repairfuelleak', function()
    local vehicle = cache.vehicle or closestVehicle()
    if not vehicle then return notify('No vehicle found.', 'error') end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local response = lib.callback.await('ps-fuel:server:authoriseLeakRepair', false, netId)
    if not response or response.success ~= true then
        return notify(response and response.message or 'You are not authorised to repair fuel leaks.', 'error')
    end
    setLeakLevel(vehicle, 0)
    notify('Fuel tank leak repaired.', 'success')
end, false)

exports('GetLeakLevel', function(vehicle)
    return leakCache[trimPlate(vehicle)] or 0
end)

exports('SetLeakLevel', setLeakLevel)



openFuelApp = function(context)
    context = type(context) == 'table' and context or {}

    if context.admin == true then
        openPanel('admin')
        return uiOpen, uiOpen and nil or 'Unable to open fuel administration.'
    end

    local station, distance = nearestStation()
    if not station or not distance or distance > stationInteractionDistance(station) then
        return false, 'Move closer to a fuel station before opening the fuel terminal.'
    end

    if not stationManagementEnabled(station) then
        local vehicle = closestVehicle()
        if vehicle and closestPump() then
            openRefuelPanel(vehicle, station)
            return uiOpen, uiOpen and nil or 'Unable to open the public refuelling terminal.'
        end
        return false, 'This is a public fuel station. Move a vehicle beside a pump to refuel.'
    end

    openStationTablet(station)
    return uiOpen, uiOpen and nil or 'Station access was not opened.'
end

RegisterCommand('fuelstation', function()
    local ok, message = openFuelApp({})
    if ok == false and message then notify(message, 'error') end
end, false)

RegisterCommand('closefuel', function()
    forceCloseUi(false, true, false)
end, false)

exports('OpenFuelApp', function(context)
    return openFuelApp(context)
end)
