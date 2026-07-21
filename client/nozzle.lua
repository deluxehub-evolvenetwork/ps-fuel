PSFuelNozzle = PSFuelNozzle or {}

local config = PSFuelConfig.Nozzles or {}
local electricConfig = PSFuelConfig.Electric or {}
local state = {
    kind = nil,
    prop = nil,
    rope = nil,
    sourceEntity = nil,
    sourceCoords = nil,
    station = nil,
    charger = nil,
    vehicle = nil,
    paymentAccount = nil,
    sessionToken = nil,
    refuelling = false,
}

local spawnedChargers = {}
local chargerByEntity = {}
local electricBlips = {}
local targetNames = {
    fuelTake = 'ps-fuel:take-fuel-nozzle',
    fuelReturn = 'ps-fuel:return-fuel-nozzle',
    electricTake = 'ps-fuel:take-electric-nozzle',
    electricReturn = 'ps-fuel:return-electric-nozzle',
    vehicleInsert = 'ps-fuel:insert-nozzle',
    jerryCanBuy = 'ps-fuel:buy-jerry-can',
}

local function notify(message, kind)
    if PSFuelRuntime and PSFuelRuntime.Notify then
        PSFuelRuntime.Notify(message, kind)
        return
    end
    lib.notify({ title = 'PS Fuel', description = message, type = kind or 'inform' })
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end

    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then return nil end
        Wait(25)
    end
    return hash
end

local function loadAnim(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(25)
    end
    return true
end

local function playSound(name, looped)
    if (config.Sounds or {}).Enabled == false or not name or name == '' then return end
    if PSFuelRuntime and PSFuelRuntime.PlaySound then
        PSFuelRuntime.PlaySound(name, (config.Sounds or {}).Volume or 0.45, looped == true)
    end
end

local function stopSound(name)
    if (config.Sounds or {}).Enabled == false then return end
    if PSFuelRuntime and PSFuelRuntime.StopSound then PSFuelRuntime.StopSound(name) end
end

local function removeRope()
    if state.rope then
        DeleteRope(state.rope)
        state.rope = nil
    end
    RopeUnloadTextures()
end

local function deleteProp()
    if state.prop and DoesEntityExist(state.prop) then
        DetachEntity(state.prop, true, true)
        DeleteEntity(state.prop)
    end
    state.prop = nil
end

local function attachToHand()
    if not state.prop or not DoesEntityExist(state.prop) then return false end
    local ped = cache.ped or PlayerPedId()
    local hand = (config.HandAttachment or {})
    local attachment = hand[state.kind] or hand.fuel or {}
    local bone = GetPedBoneIndex(ped, tonumber(hand.bone) or 18905)

    DetachEntity(state.prop, true, true)
    AttachEntityToEntity(
        state.prop, ped, bone,
        attachment.x or 0.13, attachment.y or 0.04, attachment.z or 0.01,
        attachment.rx or -42.0, attachment.ry or -115.0, attachment.rz or -63.42,
        false, true, false, true, 0, true
    )
    state.vehicle = nil
    return true
end

local function findVehicleBone(vehicle)
    for _, name in ipairs(config.VehicleBones or {}) do
        local bone = GetEntityBoneIndexByName(vehicle, name)
        if bone and bone ~= -1 then return bone, name end
    end
    return 0, 'chassis'
end

local function attachToVehicle(vehicle)
    if not state.prop or not DoesEntityExist(state.prop) or not DoesEntityExist(vehicle) then return false end
    local attachment = (config.VehicleAttachment or {})[state.kind] or {}
    local bone = findVehicleBone(vehicle)

    DetachEntity(state.prop, true, true)
    AttachEntityToEntity(
        state.prop, vehicle, bone,
        attachment.x or 0.0, attachment.y or 0.0, attachment.z or 0.0,
        attachment.rx or 0.0, attachment.ry or 90.0, attachment.rz or 0.0,
        false, true, false, true, 0, true
    )
    state.vehicle = vehicle
    return true
end

local function choosePaymentAccount()
    local payment = PSFuelConfig.Payment or {}
    local allowed = payment.AllowedAccounts or { bank = true }
    if payment.AskWhenTakingNozzle == false then
        return payment.DefaultAccount or PSFuelConfig.PaymentAccount or 'bank'
    end

    local options = {}
    if allowed.bank then options[#options + 1] = { value = 'bank', label = 'Bank card' } end
    if allowed.cash then options[#options + 1] = { value = 'cash', label = 'Cash' } end
    if #options == 0 then return nil end

    local result = lib.inputDialog('Fuel payment', {
        {
            type = 'select',
            label = 'Payment method',
            required = true,
            default = payment.DefaultAccount or 'bank',
            options = options,
        }
    })
    return result and result[1] or nil
end

local function createHose(anchor, kind)
    if config.PumpHose == false then return end
    if not anchor or not DoesEntityExist(anchor) or not state.prop or not DoesEntityExist(state.prop) then return end

    RopeLoadTextures()
    local timeout = GetGameTimer() + 3000
    while not RopeAreTexturesLoaded() and GetGameTimer() < timeout do
        Wait(0)
        RopeLoadTextures()
    end

    local anchorCoords = GetEntityCoords(anchor)
    local hoseLength = kind == 'electric'
        and (tonumber(electricConfig.HoseLength) or 5.0)
        or (tonumber(config.HoseLength) or 8.0)
    local ropeType = kind == 'electric'
        and (tonumber(electricConfig.RopeType) or tonumber(config.RopeType) or 1)
        or (tonumber(config.RopeType) or 1)

    state.rope = AddRope(
        anchorCoords.x, anchorCoords.y, anchorCoords.z,
        0.0, 0.0, 0.0,
        3.0, ropeType, math.max(1.0, hoseLength), 0.0, 1.0,
        false, false, false, 1.0, true
    )
    if not state.rope or state.rope == 0 then
        state.rope = nil
        RopeUnloadTextures()
        return
    end

    ActivatePhysics(state.rope)
    Wait(50)
    local nozzleCoords = GetEntityCoords(state.prop)
    local pumpHeight = kind == 'electric' and 1.76 or 2.1
    AttachEntitiesToRope(
        state.rope, anchor, state.prop,
        anchorCoords.x, anchorCoords.y, anchorCoords.z + pumpHeight,
        nozzleCoords.x, nozzleCoords.y, nozzleCoords.z,
        hoseLength, false, false, nil, nil
    )
end

local function resetState()
    state.kind = nil
    state.sourceEntity = nil
    state.sourceCoords = nil
    state.station = nil
    state.charger = nil
    state.vehicle = nil
    state.paymentAccount = nil
    state.sessionToken = nil
    state.refuelling = false
end

local function returnNozzle(silent, force)
    if state.refuelling and force ~= true then
        if not silent then notify('Stop refuelling before returning the nozzle.', 'error') end
        return false
    end

    local sessionToken = state.sessionToken

    if state.kind == 'electric' then
        playSound((config.Sounds or {}).ReturnElectric or 'putbackcharger')
    elseif state.kind == 'fuel' then
        playSound((config.Sounds or {}).ReturnFuel or 'putbacknozzle')
    end

    removeRope()
    deleteProp()
    resetState()

    if sessionToken then
        TriggerServerEvent('ps-fuel:server:endNozzleSession', sessionToken)
    end
    if PSFuelRuntime and PSFuelRuntime.CloseFuelUi then
        PSFuelRuntime.CloseFuelUi(true)
    end
    return true
end

local function hoseBreak()
    local sourceCoords = state.sourceCoords
    local kind = state.kind
    returnNozzle(true, true)
    notify('The nozzle hose could not reach that far and was disconnected.', 'error')

    local breakConfig = config.BreakHose or {}
    if kind == 'fuel' and breakConfig.Enabled ~= false and breakConfig.ExplodePump == true and sourceCoords then
        if math.random(100) <= math.max(0, math.min(100, tonumber(breakConfig.ExplosionChance) or 100)) then
            AddExplosion(sourceCoords.x, sourceCoords.y, sourceCoords.z, tonumber(breakConfig.ExplosionType) or 5, 1.0, true, false, 1.0)
        end
    end
end

local function takeNozzle(entity, kind, charger)
    if config.Enabled == false or state.kind then return end
    if IsPedInAnyVehicle(cache.ped or PlayerPedId(), false) then
        return notify('Exit the vehicle before taking a nozzle.', 'error')
    end

    local station
    if kind == 'electric' and charger and charger.stationId then
        station = PSFuelRuntime and PSFuelRuntime.StationById and PSFuelRuntime.StationById(charger.stationId)
    elseif PSFuelRuntime and PSFuelRuntime.NearestStation then
        station = select(1, PSFuelRuntime.NearestStation())
    end
    if not station then return notify('This pump is not linked to a configured station.', 'error') end

    local account = choosePaymentAccount()
    if not account then return end

    local session = lib.callback.await(
        'ps-fuel:server:beginNozzleSession',
        false,
        station.id,
        kind,
        charger and charger.id or nil,
        account
    )
    if not session or not session.success or not session.token then
        return notify(session and session.message or 'The pump could not authorise this nozzle.', 'error')
    end

    local model = kind == 'electric' and electricConfig.NozzleModel or config.FuelModel
    local hash = loadModel(model)
    if not hash then
        TriggerServerEvent('ps-fuel:server:endNozzleSession', session.token)
        return notify('The nozzle model could not be loaded.', 'error')
    end

    local anim = config.Animation or {}
    if anim.Enabled == true and loadAnim(anim.PickupDict or 'anim@am_hold_up@male') then
        TaskPlayAnim(cache.ped, anim.PickupDict or 'anim@am_hold_up@male', anim.PickupClip or 'shoplift_high', 2.0, 8.0, 600, 50, 0.0, false, false, false)
    end
    playSound((config.Sounds or {}).Pickup or 'pickupnozzle')
    Wait(anim.Enabled == true and 250 or 50)

    state.prop = CreateObject(hash, 1.0, 1.0, 1.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not state.prop or state.prop == 0 then
        state.prop = nil
        TriggerServerEvent('ps-fuel:server:endNozzleSession', session.token)
        return notify('The nozzle could not be created.', 'error')
    end

    SetEntityAsMissionEntity(state.prop, true, true)
    SetEntityCollision(state.prop, false, false)

    state.kind = kind
    state.sourceEntity = entity
    state.sourceCoords = GetEntityCoords(entity)
    state.station = station
    state.charger = charger
    state.paymentAccount = session.paymentAccount or account
    state.sessionToken = session.token
    attachToHand()
    createHose(entity, kind)

    CreateThread(function()
        while state.kind and state.prop and DoesEntityExist(state.prop) do
            local maxDistance = state.kind == 'electric'
                and (tonumber(electricConfig.MaxCableDistance) or tonumber(config.MaxDistance) or 7.5)
                or (tonumber(config.MaxDistance) or 7.5)
            local source = state.sourceEntity
            if not source or not DoesEntityExist(source) then
                hoseBreak()
                break
            end

            local coords = GetEntityCoords(source)
            if #(GetEntityCoords(cache.ped or PlayerPedId()) - coords) > maxDistance then
                hoseBreak()
                break
            end
            Wait(250)
        end
    end)
end

local function canUseVehicle(vehicle)
    if not state.kind or state.refuelling or not DoesEntityExist(vehicle) then return false end
    if cache.vehicle then return false end
    if state.kind == 'electric' then
        return PSFuelRuntime and PSFuelRuntime.IsElectricVehicle and PSFuelRuntime.IsElectricVehicle(vehicle)
    end
    return not (PSFuelRuntime and PSFuelRuntime.IsElectricVehicle and PSFuelRuntime.IsElectricVehicle(vehicle))
end

local function insertNozzle(vehicle)
    if not canUseVehicle(vehicle) then return end
    if state.kind == 'fuel' and (PSFuelConfig.Safety or {}).RequireEngineOff ~= false and GetIsVehicleEngineRunning(vehicle) then
        return notify('Turn the engine off before inserting the fuel nozzle.', 'error')
    end

    if not attachToVehicle(vehicle) then return notify('Unable to attach the nozzle to this vehicle.', 'error') end
    if not PSFuelRuntime or not PSFuelRuntime.OpenRefuelPanel then
        attachToHand()
        return notify('The refuelling terminal is unavailable.', 'error')
    end

    PSFuelRuntime.OpenRefuelPanel(vehicle, state.station, {
        paymentAccount = state.paymentAccount,
        nozzleKind = state.kind,
        chargerId = state.charger and state.charger.id or nil,
        physicalNozzle = true,
        sessionToken = state.sessionToken,
    })
end

local function buyJerryCanAtPump()
    if (PSFuelConfig.JerryCan or {}).Enabled ~= true then
        return notify('Jerry cans are disabled.', 'error')
    end

    local station = PSFuelRuntime and PSFuelRuntime.NearestStation and select(1, PSFuelRuntime.NearestStation())
    if not station then return notify('This pump is not linked to a configured station.', 'error') end

    local account = choosePaymentAccount()
    if not account then return end

    local response = lib.callback.await('ps-fuel:server:buyJerryCan', false, station.id, account)
    if not response or not response.success then
        return notify(response and response.message or 'The jerry can purchase failed.', 'error')
    end

    notify(('Purchased an emergency fuel can for £%s from %s.'):format(response.price or 0, response.paymentAccount or account), 'success')
end

local function spawnChargers()
    if electricConfig.Enabled == false or electricConfig.SpawnChargers == false then return end
    local hash = loadModel(electricConfig.ChargerModel)
    if not hash then
        notify('Electric charger model failed to load. Charging targets are disabled.', 'error')
        return
    end

    for _, charger in ipairs(electricConfig.Chargers or {}) do
        local coords = charger.coords
        local object = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
        if object and object ~= 0 then
            SetEntityHeading(object, (coords.w or 0.0) - 180.0)
            SetEntityAsMissionEntity(object, true, true)
            FreezeEntityPosition(object, true)
            SetEntityInvincible(object, true)
            spawnedChargers[#spawnedChargers + 1] = object
            chargerByEntity[object] = charger
        end

        local blipConfig = electricConfig.Blips or {}
        if blipConfig.Enabled then
            local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
            SetBlipSprite(blip, tonumber(blipConfig.Sprite) or 620)
            SetBlipColour(blip, tonumber(blipConfig.Colour) or 3)
            SetBlipScale(blip, tonumber(blipConfig.Scale) or 0.65)
            SetBlipAsShortRange(blip, blipConfig.ShortRange ~= false)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(charger.label or 'EV Charger')
            EndTextCommandSetBlipName(blip)
            electricBlips[#electricBlips + 1] = blip
        end
    end
    SetModelAsNoLongerNeeded(hash)
end

local function registerTargets()
    if config.Enabled == false or config.UseOxTarget == false then return end

    exports.ox_target:addModel(PSFuelConfig.PumpModels or {}, {
        {
            name = targetNames.fuelTake,
            icon = 'fa-solid fa-gas-pump',
            label = 'Take fuel nozzle',
            distance = tonumber(config.InteractionDistance) or 2.0,
            canInteract = function()
                return state.kind == nil and not IsPedInAnyVehicle(cache.ped or PlayerPedId(), false)
            end,
            onSelect = function(data) takeNozzle(data.entity, 'fuel') end,
        },
        {
            name = targetNames.fuelReturn,
            icon = 'fa-solid fa-hand',
            label = 'Return fuel nozzle',
            distance = tonumber(config.InteractionDistance) or 2.0,
            canInteract = function(entity)
                return state.kind == 'fuel' and not state.refuelling and state.sourceEntity == entity
            end,
            onSelect = function() returnNozzle(false) end,
        },
        {
            name = targetNames.jerryCanBuy,
            icon = 'fa-solid fa-jug-detergent',
            label = 'Buy emergency fuel can',
            distance = tonumber(config.InteractionDistance) or 2.0,
            canInteract = function()
                return config.BuyJerryCanAtPump == true
                    and (PSFuelConfig.JerryCan or {}).Enabled == true
                    and state.kind == nil
                    and not IsPedInAnyVehicle(cache.ped or PlayerPedId(), false)
            end,
            onSelect = buyJerryCanAtPump,
        },
    })

    exports.ox_target:addModel(electricConfig.ChargerModel, {
        {
            name = targetNames.electricTake,
            icon = 'fa-solid fa-bolt',
            label = 'Take charging connector',
            distance = tonumber(config.InteractionDistance) or 2.0,
            canInteract = function()
                return electricConfig.Enabled ~= false and state.kind == nil and not IsPedInAnyVehicle(cache.ped or PlayerPedId(), false)
            end,
            onSelect = function(data) takeNozzle(data.entity, 'electric', chargerByEntity[data.entity]) end,
        },
        {
            name = targetNames.electricReturn,
            icon = 'fa-solid fa-plug-circle-check',
            label = 'Return charging connector',
            distance = tonumber(config.InteractionDistance) or 2.0,
            canInteract = function(entity)
                return state.kind == 'electric' and not state.refuelling and state.sourceEntity == entity
            end,
            onSelect = function() returnNozzle(false) end,
        },
    })

    exports.ox_target:addGlobalVehicle({
        {
            name = targetNames.vehicleInsert,
            icon = 'fa-solid fa-gas-pump',
            label = 'Insert nozzle',
            distance = tonumber(config.VehicleTargetDistance) or 3.0,
            bones = config.VehicleBones,
            canInteract = function(entity) return canUseVehicle(entity) end,
            onSelect = function(data) insertNozzle(data.entity) end,
        }
    })
end

function PSFuelNozzle.IsHolding(kind)
    return state.kind ~= nil and (kind == nil or state.kind == kind)
end

function PSFuelNozzle.GetKind()
    return state.kind
end

function PSFuelNozzle.GetPaymentAccount()
    return state.paymentAccount
end

function PSFuelNozzle.GetSessionToken()
    return state.sessionToken
end

function PSFuelNozzle.IsReadyFor(vehicle, kind)
    return state.kind ~= nil
        and state.vehicle == vehicle
        and (kind == nil or state.kind == kind)
        and state.prop ~= nil
        and DoesEntityExist(state.prop)
end

function PSFuelNozzle.IsSessionValid(vehicle, station)
    if not PSFuelNozzle.IsReadyFor(vehicle) then return false end
    if not station or not state.station or station.id ~= state.station.id then return false end
    if not state.sourceEntity or not DoesEntityExist(state.sourceEntity) then return false end
    local maxDistance = state.kind == 'electric'
        and (tonumber(electricConfig.MaxCableDistance) or tonumber(config.MaxDistance) or 7.5)
        or (tonumber(config.MaxDistance) or 7.5)
    return #(GetEntityCoords(cache.ped or PlayerPedId()) - GetEntityCoords(state.sourceEntity)) <= maxDistance
end

function PSFuelNozzle.OnRefuelStart(vehicle, fuelType)
    if not PSFuelNozzle.IsReadyFor(vehicle) then return false end
    state.refuelling = true
    local anim = config.Animation or {}
    if anim.Enabled == true and loadAnim(anim.RefuelDict or 'timetable@gardener@filling_can') then
        TaskTurnPedToFaceEntity(cache.ped or PlayerPedId(), vehicle, 250)
        Wait(250)
        TaskPlayAnim(cache.ped or PlayerPedId(), anim.RefuelDict or 'timetable@gardener@filling_can', anim.RefuelClip or 'gar_ig_5_filling_can', 8.0, 1.0, -1, 1, 0.0, false, false, false)
    end

    if fuelType == 'electric' or fuelType == 'electric_fast' then
        playSound((config.Sounds or {}).ChargeLoop or 'charging', true)
    else
        playSound((config.Sounds or {}).FuelLoop or 'refuel', true)
    end
    return true
end

function PSFuelNozzle.OnRefuelStop(fuelType)
    state.refuelling = false
    local anim = config.Animation or {}
    if anim.Enabled == true then
        StopAnimTask(cache.ped or PlayerPedId(), anim.RefuelDict or 'timetable@gardener@filling_can', anim.RefuelClip or 'gar_ig_5_filling_can', 2.0)
    end
    if fuelType == 'electric' or fuelType == 'electric_fast' then
        stopSound((config.Sounds or {}).ChargeLoop or 'charging')
        playSound((config.Sounds or {}).ChargeStop or 'chargestop')
    else
        stopSound((config.Sounds or {}).FuelLoop or 'refuel')
        playSound((config.Sounds or {}).FuelStop or 'fuelstop')
    end
    attachToHand()
end

function PSFuelNozzle.CancelVehicleAttachment()
    if state.kind and state.vehicle and not state.refuelling then attachToHand() end
end

function PSFuelNozzle.Return()
    return returnNozzle(false)
end

local function nearestSpawnedCharger()
    local pedCoords = GetEntityCoords(cache.ped or PlayerPedId())
    local closestEntity, closestCharger, closestDistance

    for entity, charger in pairs(chargerByEntity) do
        if DoesEntityExist(entity) then
            local distance = #(pedCoords - GetEntityCoords(entity))
            if not closestDistance or distance < closestDistance then
                closestEntity = entity
                closestCharger = charger
                closestDistance = distance
            end
        end
    end

    local maxDistance = math.max(2.0, tonumber(config.InteractionDistance) or 2.0) + 1.5
    if closestDistance and closestDistance <= maxDistance then
        return closestEntity, closestCharger
    end
end

-- Compatibility with scripts that previously depended on cdn-fuel's public
-- electric-nozzle helpers. The authoritative session and payment checks still
-- run through this resource before a connector can be used.
exports('IsHoldingElectricNozzle', function()
    return state.kind == 'electric'
end)

exports('SetElectricNozzle', function(action)
    action = tostring(action or ''):lower()

    if action == 'putback' then
        if state.kind ~= 'electric' then return false end
        return returnNozzle(false)
    end

    if action == 'pickup' then
        if state.kind then return state.kind == 'electric' end
        local entity, charger = nearestSpawnedCharger()
        if not entity or not charger then
            notify('Move closer to an electric charger.', 'error')
            return false
        end
        takeNozzle(entity, 'electric', charger)
        return true
    end

    return false
end)

CreateThread(function()
    Wait(500)
    spawnChargers()
    registerTargets()
end)

if (PSFuelConfig.Safety or {}).LeaveEngineRunning then
    CreateThread(function()
        while true do
            Wait(100)
            local ped = cache.ped or PlayerPedId()
            if IsPedInAnyVehicle(ped, false) and IsControlPressed(0, 75) and not IsEntityDead(ped) and not IsPauseMenuActive() then
                local vehicle = GetVehiclePedIsIn(ped, false)
                local running = GetIsVehicleEngineRunning(vehicle)
                Wait(900)
                if running and not IsPedInAnyVehicle(ped, false) and DoesEntityExist(vehicle) then
                    SetVehicleEngineOn(vehicle, true, true, true)
                end
            end
        end
    end)
end

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    returnNozzle(true, true)
end)

CreateThread(function()
    while true do
        if state.kind then
            local ped = cache.ped or PlayerPedId()
            if IsEntityDead(ped) then returnNozzle(true, true) end
            Wait(500)
        else
            Wait(1500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    returnNozzle(true, true)
    if config.UseOxTarget ~= false then
        pcall(function() exports.ox_target:removeModel(PSFuelConfig.PumpModels or {}, {
            targetNames.fuelTake, targetNames.fuelReturn, targetNames.jerryCanBuy
        }) end)
        pcall(function() exports.ox_target:removeModel(electricConfig.ChargerModel, {
            targetNames.electricTake, targetNames.electricReturn
        }) end)
        pcall(function() exports.ox_target:removeGlobalVehicle(targetNames.vehicleInsert) end)
    end
    if PSFuelRuntime and PSFuelRuntime.StopAllSounds then PSFuelRuntime.StopAllSounds() end
    for _, object in ipairs(spawnedChargers) do
        if DoesEntityExist(object) then DeleteEntity(object) end
    end
    for _, blip in ipairs(electricBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
end)
