PSFuelSecurity = PSFuelSecurity or {}

local limits = {}

local function nowMs()
    return GetGameTimer()
end

function PSFuelSecurity.NormalisePlate(value)
    if type(value) ~= 'string' then return nil end
    local plate = value:gsub('[%c]', ''):gsub('^%s*(.-)%s*$', '%1'):upper():sub(1, 16)
    if plate == '' then return nil end
    return plate
end

function PSFuelSecurity.RateLimit(source, key, windowMs, burst)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    key = tostring(key or 'default')
    windowMs = math.max(100, math.floor(tonumber(windowMs) or 1000))
    burst = math.max(1, math.floor(tonumber(burst) or 5))

    local current = nowMs()
    local playerLimits = limits[source]
    if not playerLimits then
        playerLimits = {}
        limits[source] = playerLimits
    end

    local entry = playerLimits[key]
    if not entry or current - entry.startedAt >= windowMs then
        playerLimits[key] = { startedAt = current, count = 1 }
        return false
    end

    entry.count = entry.count + 1
    return entry.count > burst
end

function PSFuelSecurity.Token(source, purpose)
    return ('%s:%s:%s:%08x%08x'):format(
        tostring(purpose or 'ps-fuel'),
        tostring(source or 0),
        tostring(os.time()),
        math.random(0, 0x7fffffff),
        math.random(0, 0x7fffffff)
    )
end

function PSFuelSecurity.VehicleFromNetId(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return 0 end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return 0 end
    return entity
end

function PSFuelSecurity.PlayerNearEntity(source, entity, distance)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= math.max(1.0, tonumber(distance) or 10.0)
end

function PSFuelSecurity.Clear(source)
    limits[tonumber(source)] = nil
end

AddEventHandler('playerDropped', function()
    PSFuelSecurity.Clear(source)
end)
