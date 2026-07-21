local fuelCache, dirtyFuel, leakCache = {}, {}, {}
local isRefuelling, uiOpen, activeDelivery = false, false, nil
local activeFuelSession = nil
local lastBodyHealth = {}

local function forceCloseUi()
    uiOpen = false
    activeFuelSession = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'reset' })
end

CreateThread(function()
    -- The NUI browser exists as soon as the resource starts. Keep it closed
    -- throughout loading and Qbox character selection.
    for _ = 1, 30 do
        forceCloseUi()
        Wait(500)
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    forceCloseUi()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
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
    for _, station in ipairs(Config.Stations) do if station.id == id then return station end end
end

local function nearestStation()
    local coords = GetEntityCoords(cache.ped)
    local closest, distance
    for _, station in ipairs(Config.Stations) do
        local d = #(coords - station.coords)
        if not distance or d < distance then closest, distance = station, d end
    end
    return closest, distance
end

local function closestPump()
    local coords = GetEntityCoords(cache.ped)
    local found, best
    for _, model in ipairs(Config.PumpModels) do
        local pump = GetClosestObjectOfType(coords.x, coords.y, coords.z, Config.RefuelDistance, model, false, false, false)
        if pump ~= 0 then
            local d = #(coords - GetEntityCoords(pump))
            if not best or d < best then found, best = pump, d end
        end
    end
    return found
end

local function closestVehicle()
    local coords = GetEntityCoords(cache.ped)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, Config.VehicleDistance, 0, 71)
    return vehicle ~= 0 and vehicle or nil
end

local function getFuel(vehicle)
    if not DoesEntityExist(vehicle) then return 0.0 end
    local plate = trimPlate(vehicle)
    if plate == '' then return GetVehicleFuelLevel(vehicle) end

    if fuelCache[plate] == nil then
        local saved = lib.callback.await('ps-fuel:server:getVehicleFuel', false, plate)
        fuelCache[plate] = (type(saved) == 'table' and tonumber(saved.fuel) or tonumber(saved))
            or math.random(math.floor(Config.StartFuelMin), math.floor(Config.StartFuelMax)) + 0.0

        if type(saved) == 'table' then
            leakCache[plate] = tonumber(saved.leak_level) or 0
        end
    end
    SetVehicleFuelLevel(vehicle, fuelCache[plate])
    return fuelCache[plate]
end

local function setFuel(vehicle, amount)
    if not DoesEntityExist(vehicle) then return end
    local plate = trimPlate(vehicle)
    local fuel = math.max(0.0, math.min(Config.MaxFuel, tonumber(amount) or 0.0))
    fuelCache[plate] = fuel
    dirtyFuel[plate] = fuel
    SetVehicleFuelLevel(vehicle, fuel)
    Entity(vehicle).state:set('recoilFuel', fuel, true)
    SetVehicleUndriveable(vehicle, fuel <= 0.0)
    if fuel <= 0.0 then SetVehicleEngineOn(vehicle, false, true, true) end
end

local function vehicleUsesDiesel(vehicle)
    local diesel = Config.FuelTypes and Config.FuelTypes.diesel
    if not diesel or not DoesEntityExist(vehicle) then return false end
    local model = GetEntityModel(vehicle)
    local class = GetVehicleClass(vehicle)
    return (diesel.Models and diesel.Models[model] == true)
        or (diesel.AllowedClasses and diesel.AllowedClasses[class] == true)
end

local function fuelTypeAllowed(vehicle, fuelType)
    if not DoesEntityExist(vehicle) then return false end
    fuelType = tostring(fuelType or Config.FuelTypes.Default):lower()
    if Config.Electric.Enabled and Config.Electric.Models[GetEntityModel(vehicle)] == true then
        return false
    end
    local dieselVehicle = vehicleUsesDiesel(vehicle)
    if fuelType == 'diesel' then return dieselVehicle end
    return not dieselVehicle and (fuelType == 'petrol' or fuelType == 'premium')
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

    local allowedFuelTypes = {}
    for key, value in pairs(Config.FuelTypes or {}) do
        if type(value) == 'table' and fuelTypeAllowed(vehicle, key) then
            allowedFuelTypes[#allowedFuelTypes + 1] = key
        end
    end

    return {
        netId = netId,
        plate = trimPlate(vehicle),
        label = getVehicleLabel(vehicle),
        fuel = getFuel(vehicle),
        maxFuel = Config.MaxFuel,
        diesel = vehicleUsesDiesel(vehicle),
        allowedFuelTypes = allowedFuelTypes,
    }
end

local function showFuelUi(mode, data)
    uiOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'open', mode = mode, data = data })
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

local function openRefuelPanel(vehicle, station)
    if uiOpen or isRefuelling then return end
    if not vehicle or not DoesEntityExist(vehicle) then
        return notify('Move a vehicle closer to the pump.', 'error')
    end

    local data = lib.callback.await('ps-fuel:server:getRefuelPanel', false, station.id)
    local vehicleData = buildVehicleData(vehicle)
    if not data or not vehicleData then
        return notify('Unable to prepare the refuelling terminal.', 'error')
    end

    data.vehicle = vehicleData
    activeFuelSession = { vehicle = vehicle, stationId = station.id }
    showFuelUi('refuel', data)
end

local function openStationTablet(station)
    if not station then return notify('No fuel station is nearby.', 'error') end

    local access = lib.callback.await('ps-fuel:server:getStationAccess', false, station.id)
    if not access then return notify('Move closer to the fuel station.', 'error') end

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

local function refuelVehicle(vehicle, station)
    if isRefuelling then return end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 then NetworkRegisterEntityAsNetworked(vehicle); netId = NetworkGetNetworkIdFromEntity(vehicle) end
    if netId == 0 then return notify('Vehicle is not networked.', 'error') end

    isRefuelling = true
    FreezeEntityPosition(cache.ped, true)
    local purchased, paid = 0.0, 0

    while IsControlPressed(0, Config.RefuelKey) do
        Wait(Config.RefuelTick)
        if not closestPump() or not DoesEntityExist(vehicle) then break end
        local fuel = getFuel(vehicle)
        if fuel >= Config.MaxFuel then notify('The tank is full.', 'success'); break end
        local amount = math.min(Config.RefuelSpeed, Config.MaxFuel - fuel)
        local response = lib.callback.await('ps-fuel:server:purchaseFuel', false, station.id, netId, amount, Config.FuelTypes.Default)
        if not response or not response.success then notify(response and response.message or 'Payment failed.', 'error'); break end
        setFuel(vehicle, fuel + amount)
        purchased, paid = purchased + amount, paid + response.price
    end

    FreezeEntityPosition(cache.ped, false)
    isRefuelling = false
    if purchased > 0 then notify(('Purchased %.1f%% fuel for £%s.'):format(purchased, paid), 'success') end
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

RegisterNUICallback('close', function(_, cb)
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

RegisterNUICallback('purchaseFuelType', function(data, cb)
    safeNuiCallback('purchaseFuelType', function(payload)
        local session = activeFuelSession
        if not session or not DoesEntityExist(session.vehicle) then
            return { success = false, message = 'The vehicle is no longer available.' }
        end

        local station = stationById(session.stationId)
        local nearest, stationDistance = nearestStation()
        if not station or not nearest or nearest.id ~= station.id
            or stationDistance > Config.StationInteractionDistance or not closestPump()
        then
            return { success = false, message = 'Stay beside the pump while refuelling.' }
        end

        local fuelType = tostring(payload.fuelType or Config.FuelTypes.Default):lower()
        if not fuelTypeAllowed(session.vehicle, fuelType) then
            return { success = false, message = 'That fuel type is not compatible with this vehicle.' }
        end

        local currentFuel = getFuel(session.vehicle)
        local requested = math.max(0, tonumber(payload.amount) or 0)
        local amount = math.min(requested, Config.MaxFuel - currentFuel)
        if amount <= 0 then return { success = false, message = 'The tank is already full.' } end

        local netId = NetworkGetNetworkIdFromEntity(session.vehicle)
        if netId == 0 then return { success = false, message = 'Vehicle network ID was lost.' } end

        local purchased, paid, remaining = 0.0, 0, amount
        while remaining > 0.001 do
            local chunk = math.min(10.0, remaining)
            local response = lib.callback.await(
                'ps-fuel:server:purchaseFuel', false,
                session.stationId, netId, chunk, fuelType, GetVehicleClass(session.vehicle)
            )
            if not response or not response.success then
                if purchased <= 0 then return response or { success = false, message = 'Payment failed.' } end
                break
            end

            purchased = purchased + chunk
            paid = paid + (tonumber(response.price) or 0)
            remaining = remaining - chunk
            setFuel(session.vehicle, currentFuel + purchased)
            if remaining > 0.001 then Wait(400) end
        end

        local newFuel = getFuel(session.vehicle)
        notify(('Added %.1f%% %s for £%s.'):format(purchased, fuelType, paid), 'success')
        return {
            success = purchased > 0,
            amount = purchased,
            totalPrice = paid,
            newFuel = newFuel,
            fuelType = fuelType,
            message = purchased < amount and 'The purchase completed partially.' or 'Vehicle refuelled successfully.'
        }
    end, data, cb)
end)

RegisterNetEvent('ps-fuel:client:useJerryCan', function()
    if isRefuelling then return end
    local vehicle = closestVehicle()
    if not vehicle then return notify('Move closer to a vehicle.', 'error') end

    local fuel = getFuel(vehicle)
    if fuel >= Config.MaxFuel then return notify('The tank is already full.', 'error') end

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
    if not consumed then return notify('You do not have a usable jerry can.', 'error') end

    setFuel(vehicle, fuel + Config.JerryCan.FuelAmount)
    notify(('Added %.1f%% fuel from the jerry can.'):format(Config.JerryCan.FuelAmount), 'success')
end)

RegisterNetEvent('ps-fuel:client:openAdmin', function() openPanel('admin') end)

RegisterNetEvent('ps-fuel:client:openFromTablet', function()
    local station, distance = nearestStation()
    if not station or not distance or distance > Config.StationInteractionDistance then
        return notify('Move closer to a fuel station before opening its management app.', 'error')
    end
    openStationTablet(station)
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if not cache.vehicle and not isRefuelling and not uiOpen then
            local pump = closestPump()
            local station, stationDistance = nearestStation()
            if pump and station and stationDistance <= Config.StationInteractionDistance then
                sleep = 0
                local vehicle = closestVehicle()
                if vehicle then
                    lib.showTextUI(('[E] Refuel  |  [G] Station Tablet  |  Fuel %.1f%%'):format(getFuel(vehicle)), { position = 'left-center' })
                    if IsControlJustPressed(0, Config.RefuelKey) then openRefuelPanel(vehicle, station) end
                    if IsControlJustPressed(0, Config.StationTablet.OpenKey) then openStationTablet(station) end
                else
                    lib.showTextUI('[G] Purchase / Open Station Tablet', { position = 'left-center' })
                    if IsControlJustPressed(0, Config.StationTablet.OpenKey) then openStationTablet(station) end
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
        Wait(Config.FuelDrainTick)
        local vehicle = cache.vehicle
        if vehicle and GetPedInVehicleSeat(vehicle, -1) == cache.ped then
            local class = GetVehicleClass(vehicle)
            if class ~= 13 then
                local fuel = getFuel(vehicle)
                if GetIsVehicleEngineRunning(vehicle) and fuel > 0 then
                    local drain = (Config.BaseDrain + GetVehicleCurrentRpm(vehicle) * Config.RPMMultiplier) * (Config.ClassMultiplier[class] or 1.0)
                    setFuel(vehicle, fuel - drain)
                elseif fuel <= 0 then
                    SetVehicleEngineOn(vehicle, false, true, true)
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(Config.PersistenceSaveInterval)
        for plate, fuel in pairs(dirtyFuel) do
            TriggerServerEvent('ps-fuel:server:saveVehicleFuel', plate, fuel, leakCache[plate] or 0)
            dirtyFuel[plate] = nil
        end
    end
end)

AddStateBagChangeHandler('recoilFuel', nil, function(bagName, _, value)
    local entity = GetEntityFromStateBagName(bagName)
    if entity == 0 or GetEntityType(entity) ~= 2 then return end
    local plate = trimPlate(entity)
    fuelCache[plate] = tonumber(value) or fuelCache[plate]
    if fuelCache[plate] then SetVehicleFuelLevel(entity, fuelCache[plate]) end
end)

RegisterCommand('fuel', function()
    local vehicle = cache.vehicle or closestVehicle()
    if not vehicle then return notify('No vehicle found.', 'error') end
    notify(('Fuel: %.1f%%'):format(getFuel(vehicle)), 'inform')
end)

RegisterCommand('setfuel', function(_, args)
    local vehicle = cache.vehicle or closestVehicle()
    local amount = tonumber(args[1])
    if not vehicle or not amount then return notify('Usage: /setfuel 100 near a vehicle.', 'error') end
    setFuel(vehicle, amount)
    notify(('Fuel set to %.1f%%.'):format(getFuel(vehicle)), 'success')
end, true)

exports('GetFuel', getFuel)
exports('SetFuel', setFuel)


local function isElectricVehicle(vehicle)
    return Config.Electric.Enabled and Config.Electric.Models[GetEntityModel(vehicle)] == true
end

local function nearestCharger()
    local coords, closest, distance = GetEntityCoords(cache.ped)
    for _, charger in ipairs(Config.Electric.Chargers) do
        local d = #(coords - charger.coords)
        if not distance or d < distance then closest, distance = charger, d end
    end
    return closest, distance
end

local function setLeakLevel(vehicle, level)
    local plate = trimPlate(vehicle)
    leakCache[plate] = math.max(0, math.min(2, tonumber(level) or 0))
    dirtyFuel[plate] = fuelCache[plate] or getFuel(vehicle)
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

local function createStationBlip(station)
    local blip = AddBlipForCoord(
        station.coords.x,
        station.coords.y,
        station.coords.z
    )

    SetBlipSprite(blip, Config.Blips.Sprite)
    SetBlipColour(blip, Config.Blips.Colour)
    SetBlipScale(blip, Config.Blips.Scale)
    SetBlipAsShortRange(blip, Config.Blips.ShortRange)
    SetBlipDisplay(blip, Config.Blips.Display)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(station.label)
    EndTextCommandSetBlipName(blip)

    return blip
end

CreateThread(function()
    if not Config.Blips.Enabled then
        return
    end

    for _, station in ipairs(Config.Stations) do
        createStationBlip(station)
    end
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

        if Config.Deliveries.AutoAttachTrailer then
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
                    payload.stationId
                )

                notify(
                    finish and finish.message or 'Robbery failed.',
                    finish and finish.success and 'success' or 'error'
                )
            else
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
                local terminal = Config.Deliveries.LoadingTerminal
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
                        Config.RefuelKey
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
                    Config.Stations
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
                        <= Config.Deliveries.MaxDeliveryDistance
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
                                Config.RefuelKey
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
                                        if Config.Deliveries.DeleteVehiclesOnComplete
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
        if Config.Leaks.Enabled and cache.vehicle and GetPedInVehicleSeat(cache.vehicle, -1) == cache.ped then
            local vehicle = cache.vehicle
            local health = GetVehicleBodyHealth(vehicle)
            local previous = lastBodyHealth[vehicle] or health
            local damage = previous - health
            if damage >= Config.Leaks.MinimumImpactDamage then
                local severe = damage >= Config.Leaks.SevereImpactDamage
                local chance = severe and Config.Leaks.SevereChancePercent or Config.Leaks.ChancePercent
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
        Wait(Config.FuelDrainTick)
        local vehicle = cache.vehicle
        if vehicle and GetPedInVehicleSeat(vehicle, -1) == cache.ped then
            local leak = leakCache[trimPlate(vehicle)] or 0
            if leak > 0 then
                local drain = leak == 2 and Config.Leaks.SevereDrainPerTick or Config.Leaks.NormalDrainPerTick
                setFuel(vehicle, getFuel(vehicle) - drain)
            end
        end
    end
end)

RegisterCommand(Config.Leaks.RepairCommand, function()
    local vehicle = cache.vehicle or closestVehicle()
    if not vehicle then return notify('No vehicle found.', 'error') end
    setLeakLevel(vehicle, 0)
    notify('Fuel tank leak repaired.', 'success')
end, true)

exports('GetLeakLevel', function(vehicle)
    return leakCache[trimPlate(vehicle)] or 0
end)

exports('SetLeakLevel', setLeakLevel)
