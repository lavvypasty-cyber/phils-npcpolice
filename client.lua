local RSGCore = exports['rsg-core']:GetCoreObject()

-- ============================================================
-- STATE VARIABLES
-- ============================================================

local playerWantedLevel    = 0
local crimeCount           = 0
local isWanted             = false
local activePolice         = {}
local lastCrimeTime        = 0
local isOnCooldown         = {}
local policeWaveCount      = 0
local isSearching          = false
local chaseActive          = false

-- ANTI-SPAM: Track already processed entities
local processedDeadPeds    = {}       -- NPCs already counted as killed
local lastShootNotify      = 0        -- Last time we notified about shooting
local lastWantedNotify     = 0        -- Last time we showed wanted level change
local lastSearchNotify     = 0        -- Last time we showed search countdown
local lastReinfNotify      = 0        -- Last time we showed reinforcement notification
local lastDispatchNotify   = 0        -- Last time we showed dispatch notification
local initialDispatchSent  = false    -- Whether first dispatch has been triggered

-- Aim/robbery tracking
local aimStartTime = 0
local lastAimTarget = nil
local lastAimCrimeTime = 0

-- Vandalism tracking
local processedVandalism = {}
local lastVandalismCrimeTime = 0

-- Relationship groups
local REL_POLICE           = nil
local REL_PLAYER           = nil
local REL_ARREST = nil
-- ============================================================
-- DEBUG
-- ============================================================

local function DebugPrint(msg)
    if Config.Debug then
        print('[phils-police] ' .. tostring(msg))
    end
end

-- ============================================================
-- BLN-NOTIFY (with anti-spam)
-- ============================================================

local notifyCooldowns = {}

local function SendNotify(message, type, duration, cooldownKey, cooldownMs)
    duration   = duration or 5000
    cooldownMs = cooldownMs or 0

    -- If cooldown key provided, check if we should skip
    if cooldownKey then
        local now = GetGameTimer()
        if notifyCooldowns[cooldownKey] and (now - notifyCooldowns[cooldownKey]) < cooldownMs then
            return -- Skip, too soon
        end
        notifyCooldowns[cooldownKey] = now
    end

    local notifyConfig = {
        ['success'] = { template = "SUCCESS" },
        ['error']   = { template = "ERROR"   },
        ['warning'] = {
            template = nil,
            title    = "~#f39c12~Warning~e~",
            icon     = "warning"
        },
        ['info']    = { template = "INFO" },
    }

    local cfg = notifyConfig[type] or notifyConfig['info']

    if cfg.template then
        TriggerEvent("bln_notify:send", {
            description = message,
            duration    = duration,
            placement   = "top-right",
        }, cfg.template)
    else
        TriggerEvent("bln_notify:send", {
            title       = cfg.title,
            description = message,
            icon        = cfg.icon,
            duration    = duration,
            placement   = "top-right",
        })
    end
end

-- ============================================================
-- RELATIONSHIP GROUPS
-- ============================================================

CreateThread(function()
    Wait(1000)

    local result, hash = AddRelationshipGroup("REL_POLICE_CHASE")
    REL_POLICE = hash
    REL_PLAYER = GetHashKey("PLAYER")

    SetRelationshipBetweenGroups(5, REL_POLICE, REL_PLAYER)
    SetRelationshipBetweenGroups(5, REL_PLAYER, REL_POLICE)
    SetRelationshipBetweenGroups(0, REL_POLICE, REL_POLICE)

    -- ✅ Arrest group (neutral)
    local result2, arrestHash = AddRelationshipGroup("REL_POLICE_ARREST")
    REL_ARREST = arrestHash

    SetRelationshipBetweenGroups(0, REL_ARREST, REL_PLAYER)
    SetRelationshipBetweenGroups(0, REL_PLAYER, REL_ARREST)
    SetRelationshipBetweenGroups(0, REL_ARREST, REL_ARREST)

    DebugPrint("Relationship groups initialized")
end)

-- ============================================================
-- UTILITY
-- ============================================================
local function EnsureNetworkControl(ped)
    if not NetworkHasControlOfEntity(ped) then
        NetworkRequestControlOfEntity(ped)
        local timeout = 1000
        while not NetworkHasControlOfEntity(ped) and timeout > 0 do
            Wait(0)
            timeout = timeout - 1
        end
        return timeout > 0
    end
    return true
end

local function LoadModel(model)
    if not IsModelValid(model) then
        DebugPrint('Invalid model: ' .. tostring(model))
        return false
    end

    RequestModel(model)
    local timeout = 5000
    while not HasModelLoaded(model) and timeout > 0 do
        Wait(100)
        timeout = timeout - 100
    end

    return HasModelLoaded(model)
end

local function SpawnArrestOfficer(playerPed)
    local playerCoords = GetEntityCoords(playerPed)
    local forward = GetEntityForwardVector(playerPed)
    local spawnCoords = playerCoords + (forward * -3.0)

    local model = Config.ArrestModel or "s_m_m_valdeputy_01"
    local modelHash = GetHashKey(model)

    if not IsModelValid(modelHash) then
        DebugPrint("Invalid arrest model")
        return nil
    end

    RequestModel(modelHash)

    local timeout = 5000
    while not HasModelLoaded(modelHash) and timeout > 0 do
        Wait(100)
        timeout = timeout - 100
    end

    if not HasModelLoaded(modelHash) then
        DebugPrint("Failed to load arrest model")
        return nil
    end

    local ped = CreatePed(
        modelHash,
        spawnCoords.x, spawnCoords.y, spawnCoords.z,
        GetEntityHeading(playerPed),
        true, true, false, false
    )

    if not DoesEntityExist(ped) then return nil end

    EnsureNetworkControl(ped)

    if REL_ARREST then
        SetPedRelationshipGroupHash(ped, REL_ARREST)
    end

    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)

    RemoveAllPedWeapons(ped, true, true)

    SetModelAsNoLongerNeeded(modelHash)

    return ped
end




local function GetPlayerCurrentZone()
    local playerCoords = GetEntityCoords(PlayerPedId())

    for i, zone in ipairs(Config.Police) do
        local dist = #(playerCoords - zone.centerzonecoords)
        if dist <= zone.radius then
            return i, zone
        end
    end
    return nil, nil
end

local function IsPlayerInAnyZone()
    local zoneIndex, zoneData = GetPlayerCurrentZone()
    return zoneIndex ~= nil, zoneIndex, zoneData
end

local function IsPlayerLEO()
    local Player = RSGCore.Functions.GetPlayerData()
    if not Player or not Player.job or not Player.job.type then return false end
    if not Player.job.onduty then return false end
    return string.lower(Player.job.type) == string.lower(Config.LEOJobType or 'leo')
end

local function GetWantedLevelFromCrimes()
    local level = 0
    for i, data in ipairs(Config.WantedLevels) do
        if crimeCount >= data.minCrimes then
            level = i
        end
    end
    return level
end

local function GenerateSpawnPoints(baseCoords, count, spread)
    local points = {}
    for i = 1, count do
        local angle  = (i / count) * 360.0
        local rad    = math.rad(angle)
        local offset = spread + math.random(-3, 3)
        local x      = baseCoords.x + math.cos(rad) * offset
        local y      = baseCoords.y + math.sin(rad) * offset
        local z      = baseCoords.z

        local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 10.0, false)
        if found then z = groundZ end

        table.insert(points, vector3(x, y, z))
    end
    return points
end

-- ============================================================
-- PED COMBAT SETUP
-- ============================================================

local function SetupPoliceCombat(ped, zoneData)
    if not DoesEntityExist(ped) then return end

    EnsureNetworkControl(ped)

    if REL_POLICE then
        SetPedRelationshipGroupHash(ped, REL_POLICE)
    end

    if zoneData.health then
        Citizen.InvokeNative(0xC6258F41D86676E0, ped, 0, zoneData.health)
        SetEntityHealth(ped, zoneData.health, 0)
    end

    SetEntityInvincible(ped, zoneData.policeinvicible or false)
    SetPedCanRagdoll(ped, true)
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)

    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5,  true)
    SetPedCombatAttributes(ped, 4,  true)
    SetPedCombatAttributes(ped, 0,  true)
    SetPedCombatAttributes(ped, 1,  true)
    SetPedCombatAttributes(ped, 2,  false)
    SetPedCombatAttributes(ped, 52, true)

    SetPedCombatAbility(ped, 2)
    SetPedCombatMovement(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedAccuracy(ped, math.floor(Config.PoliceAccuracy or 45))
end

local function ArmPolicePed(ped, zoneData)
    if not DoesEntityExist(ped) then return end

    local w1 = GetHashKey(zoneData.weapon1)
    local w2 = GetHashKey(zoneData.weapon2)

    GiveWeaponToPed_2(ped, w1, 999, true, true,  0, false, 0.5, 1.0, 0, false, 0, false)
    GiveWeaponToPed_2(ped, w2, 999, true, false, 0, false, 0.5, 1.0, 0, false, 0, false)
    SetCurrentPedWeapon(ped, w1, true, 0, false, false)
end

local function ForceArmedCombat(ped, target)
    if not DoesEntityExist(ped) or not DoesEntityExist(target) then return end
    if IsPedDeadOrDying(ped) or IsPedDeadOrDying(target) then return end
    if not EnsureNetworkControl(ped) then return end

    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)

    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5,  true)
    SetPedCombatAttributes(ped, 0,  true)
    SetPedCombatAttributes(ped, 1,  true)
    SetPedCombatAttributes(ped, 52, true)
    SetPedCombatAbility(ped, 2)
    SetPedCombatMovement(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedKeepTask(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    TaskCombatPed(ped, target, 0, 0)
end

-- ============================================================
-- SPAWN POLICE PED
-- ============================================================

local function SpawnPolicePed(spawnCoords, heading, zoneData)
    local model = zoneData.pedmodel

    if not LoadModel(model) then
        DebugPrint('Failed to load police model: ' .. tostring(model))
        return nil
    end

    local modelHash = GetHashKey(model)

    local ped = CreatePed(
        modelHash,
        spawnCoords.x, spawnCoords.y, spawnCoords.z,
        heading or 0.0,
        true, true, false, false
    )

    if not DoesEntityExist(ped) then
        DebugPrint('Failed to create police ped')
        return nil
    end

    Wait(100)
    NetworkRequestControlOfEntity(ped)

    local timeout = 1000
    while not NetworkHasControlOfEntity(ped) and timeout > 0 do
        Wait(0)
        timeout = timeout - 1
    end

    SetupPoliceCombat(ped, zoneData)
    ArmPolicePed(ped, zoneData)

    SetModelAsNoLongerNeeded(modelHash)

    DebugPrint('Police ped spawned: ' .. tostring(ped))
    return ped
end

-- ============================================================
-- SPAWN POLICE WAVE
-- ============================================================

local function SpawnPoliceWave(zoneIndex, zoneData, extraPeds)
    if isOnCooldown[zoneIndex] then
        DebugPrint('Zone ' .. zoneIndex .. ' on cooldown')
        return
    end

    local playerPed    = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local totalPeds    = zoneData.numberofpedstocreate + (extraPeds or 0)

    DebugPrint('Spawning wave: ' .. totalPeds .. ' peds')

    local mainCount   = math.ceil(totalPeds * 0.6)
    local flankCount  = totalPeds - mainCount

    local mainPoints  = GenerateSpawnPoints(zoneData.policespawncoords, mainCount, 3.0)
    local flankPoints = GenerateSpawnPoints(playerCoords, flankCount, 45.0)

    local allPoints = {}
    for _, p in ipairs(mainPoints)  do table.insert(allPoints, p) end
    for _, p in ipairs(flankPoints) do table.insert(allPoints, p) end

    for i = 1, totalPeds do
        local spawnCoord = allPoints[i] or zoneData.policespawncoords
        local dir        = playerCoords - spawnCoord
        local heading    = math.deg(math.atan(dir.y, dir.x)) - 90.0

        local ped = SpawnPolicePed(spawnCoord, heading, zoneData)

        if ped then
            table.insert(activePolice, {
                ped       = ped,
                zoneIndex = zoneIndex,
                spawnTime = GetGameTimer(),
            })

            Wait(300)
            ForceArmedCombat(ped, playerPed)
        end
    end

    isOnCooldown[zoneIndex] = true
    CreateThread(function()
        Wait((zoneData.policecooldown or 1) * 60000)
        isOnCooldown[zoneIndex] = false
    end)

    policeWaveCount = policeWaveCount + 1
end

-- ============================================================
-- POLICE AI LOOP
-- ============================================================

local function StartPoliceAILoop()
    CreateThread(function()
        DebugPrint('AI loop started')

        while chaseActive do
            Wait(3000) -- Check every 3 seconds, not too fast

            local playerPed    = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local aliveCops    = 0

            for i = #activePolice, 1, -1 do
                local data = activePolice[i]
                local ped  = data.ped

                if not DoesEntityExist(ped) then
                    table.remove(activePolice, i)

                elseif IsPedDeadOrDying(ped) then
                    local age = GetGameTimer() - data.spawnTime
                    if age > 60000 then
                        DeletePed(ped)
                        table.remove(activePolice, i)
                    end

                else
                    aliveCops = aliveCops + 1

                    local pedCoords  = GetEntityCoords(ped)
                    local distPlayer = #(pedCoords - playerCoords)
                    local zoneData   = Config.Police[data.zoneIndex]
                    local distZone   = #(pedCoords - zoneData.centerzonecoords)

                    if distPlayer > Config.ChaseRadius and distZone > zoneData.radius * 2.0 then
                        DeletePed(ped)
                        table.remove(activePolice, i)
                    else
                        -- Re-engage only if not already fighting
                        if not IsPedInCombat(ped) then
                            ForceArmedCombat(ped, playerPed)
                        end

                        -- Chase if too far
                        if distPlayer > 40.0 and distPlayer < Config.ChaseRadius then
                            if not IsPedRunning(ped) and not IsPedSprinting(ped) and not IsPedInCombat(ped) then
                                TaskGoToEntity(ped, playerPed, -1, 5.0, Config.PoliceRunSpeed or 3.0, 1073741824, 0)
                                Wait(3000)
                                if DoesEntityExist(ped) and not IsPedDeadOrDying(ped) then
                                    ForceArmedCombat(ped, playerPed)
                                end
                            end
                        end
                    end
                end
            end

            -- All dead, search
            if aliveCops == 0 and chaseActive and isWanted and not isSearching then
                StartSearchPhase()
            end
        end
    end)
end

-- ============================================================
-- WAVE TIMER
-- ============================================================

local function StartWaveTimer()
    CreateThread(function()
        while chaseActive and isWanted do
            Wait(Config.TimeBetweenWaves or 30000)

            if not chaseActive or not isWanted then break end
            if policeWaveCount >= (Config.MaxPoliceWaves or 3) then break end

            local inZone, zIdx, zData = IsPlayerInAnyZone()
            if not inZone then goto skipWave end

            local aliveCops = 0
            for _, data in ipairs(activePolice) do
                if DoesEntityExist(data.ped) and not IsPedDeadOrDying(data.ped) then
                    aliveCops = aliveCops + 1
                end
            end

            if aliveCops < 2 then
                local wantedData = Config.WantedLevels[playerWantedLevel] or Config.WantedLevels[1]
                SendNotify("~#e74c3c~Reinforcements~e~ arriving!", "info", 5000, "reinforcements", 15000)
                SpawnPoliceWave(zIdx, zData, wantedData.extraPeds)
            end

            ::skipWave::
        end
    end)
end

-- ============================================================
-- SEARCH PHASE
-- ============================================================

function StartSearchPhase()
    if isSearching then return end
    isSearching = true

    SendNotify("The law is ~#f39c12~searching~e~ for you... Get out of Town!", "tick", 5000, "search_start", 10000)

    CreateThread(function()
        local startTime = GetGameTimer()

        while isSearching and isWanted do
            Wait(2000) -- Slower check

            local elapsed = GetGameTimer() - startTime
            local inZone, zIdx, zData = IsPlayerInAnyZone()

            -- Escaped
            if elapsed >= (Config.SearchDuration or 30000) then
                ClearWantedLevel()
                SendNotify("You have ~#2ecc71~escaped~e~ the law!", "success", 5000, "escaped", 5000)
                break
            end

            -- Returned to zone
            if inZone then
                local aliveCops = 0
                for _, data in ipairs(activePolice) do
                    if DoesEntityExist(data.ped) and not IsPedDeadOrDying(data.ped) then
                        aliveCops = aliveCops + 1
                    end
                end

                if aliveCops == 0 then
                    isSearching = false
                    local wantedData = Config.WantedLevels[playerWantedLevel] or Config.WantedLevels[1]
                    SpawnPoliceWave(zIdx, zData, wantedData.extraPeds)
                    SendNotify("The law has ~#e74c3c~found you~e~ again!", "warning", 5000, "found_again", 10000)
                    break
                end
            end

            -- Countdown - only show at 20s and 10s remaining
            local remaining = math.ceil(((Config.SearchDuration or 30000) - elapsed) / 1000)
            if remaining == 20 or remaining == 10 then
                SendNotify("Escaping in ~#f39c12~" .. remaining .. "s~e~...", "warning", 3000, "escape_countdown", 8000)
            end
        end

        isSearching = false
    end)
end

-- ============================================================
-- CLEANUP
-- ============================================================

function CleanupAllPolice()
    for _, data in ipairs(activePolice) do
        if DoesEntityExist(data.ped) then
            DeletePed(data.ped)
        end
    end
    activePolice = {}

    chaseActive     = false
    policeWaveCount = 0
end

function ClearWantedLevel()
    isWanted          = false
    isSearching       = false
    playerWantedLevel = 0
    crimeCount        = 0
    chaseActive       = false
    initialDispatchSent = false

    -- Reset new crime tracking
    aimStartTime = 0
    lastAimTarget = nil
    lastAimCrimeTime = 0
    lastVandalismCrimeTime = 0

    -- Re-scan and re-mark all dead peds the player killed so they never trigger again
    processedDeadPeds = {}
    processedVandalism = {}
    local allPeds = GetGamePool('CPed')
    local playerPed = PlayerPedId()
    for _, nearPed in ipairs(allPeds) do
        if nearPed ~= playerPed
        and DoesEntityExist(nearPed)
        and not IsPedAPlayer(nearPed)
        and IsEntityDead(nearPed) then
            local killer = Citizen.InvokeNative(0x93C8B64DEB84728C, nearPed)
            if killer == playerPed then
                processedDeadPeds[nearPed] = true
            end
        end
    end

    CleanupAllPolice()
    TriggerServerEvent('police-chase:server:clearWanted')
    TriggerServerEvent('police-chase:server:clearCrimeData')
end

-- ============================================================
-- CRIME REGISTRATION (with anti-spam)
-- ============================================================

local function RegisterCrime(zoneIndex, zoneData, isKill, description)
    if IsPlayerLEO() then return end
    crimeCount = crimeCount + 1

    DebugPrint('Crime #' .. crimeCount .. ' registered (kill=' .. tostring(isKill) .. ')')

    -- Persist crime data
    TriggerServerEvent('police-chase:server:saveCrimeData', crimeCount, playerWantedLevel)

    -- First two crimes: warnings only (no police)
    if crimeCount <= 2 then
        local strikesLeft = 3 - crimeCount
        local msg = description or (isKill and "You killed someone!" or "Shots fired!")
        SendNotify(
            "~#f39c12~Warning~e~: " .. msg .. " Strike ~#e74c3c~" .. crimeCount .. "/3~e~. ~#f39c12~" .. strikesLeft .. "~e~ more and the law comes!",
            "warning", 6000, "crime_warning_" .. crimeCount, 5000
        )
        return
    end

    -- Update wanted level (3rd+ crime)
    local newLevel = GetWantedLevelFromCrimes()
    if newLevel > playerWantedLevel then
        playerWantedLevel = newLevel
        local wantedData  = Config.WantedLevels[playerWantedLevel]
        SendNotify(
            "~#e74c3c~Wanted Level " .. playerWantedLevel .. ":~e~ " .. wantedData.name,
            "info", 7000, "wanted_level", 5000
        )
    end

    -- First time becoming wanted (crime #3)
    if not isWanted then
        isWanted    = true
        chaseActive = true
        initialDispatchSent = false

        if isKill then
            SendNotify("~#e74c3c~You killed a civilian!~e~ The law has been alerted!", "warning", 5000, "crime_alert", 5000)
        else
            local alertMsg = description or "Shots fired!"
            SendNotify("~#f39c12~" .. alertMsg .. "~e~ The law has been alerted!", "warning", 5000, "crime_alert", 5000)
        end

        -- Single dispatch - only runs once
        CreateThread(function()
            Wait(Config.DispatchDelay or 5000)

            if not isWanted or initialDispatchSent then return end
            initialDispatchSent = true

            local inZone, zIdx, zData = IsPlayerInAnyZone()
            if not inZone then return end

            local wantedData = Config.WantedLevels[playerWantedLevel] or Config.WantedLevels[1]

            SendNotify(
                "~#e74c3c~Law enforcement~e~ responding to ~#f39c12~" ..
                (zData.zoneName or "your location") .. "~e~!",
                "warning", 5000, "dispatch", 10000
            )

            SpawnPoliceWave(zIdx, zData, wantedData.extraPeds)
            StartPoliceAILoop()
            StartWaveTimer()

            TriggerServerEvent('police-chase:server:playerWanted', playerWantedLevel, zData.zoneName or "Unknown")
        end)

    else
        -- Already wanted - escalate with heavy cooldown
        if policeWaveCount < (Config.MaxPoliceWaves or 3) then
            local wantedData = Config.WantedLevels[playerWantedLevel] or Config.WantedLevels[1]
            if crimeCount >= wantedData.minCrimes and policeWaveCount < playerWantedLevel then
                local now = GetGameTimer()
                if now - (lastReinfNotify or 0) > 15000 then
                    lastReinfNotify = now
                    CreateThread(function()
                        Wait(5000)
                        local inZone, zIdx, zData = IsPlayerInAnyZone()
                        if inZone and isWanted then
                            SendNotify("~#e74c3c~More law enforcement~e~ is coming!", "tick", 5000, "reinforcements", 15000)
                            SpawnPoliceWave(zIdx, zData, wantedData.extraPeds)
                        end
                    end)
                end
            end
        end
    end
end

-- ============================================================
-- CRIME DETECTION (CLEAN + REDM SAFE)
-- ============================================================

local function DetectCrimes()

    -- ===============================
    -- MAIN CRIME LOOP
    -- ===============================
    CreateThread(function()
        DebugPrint('Crime detection started (clean version)')

        while true do
            Wait(1000) -- 1 second polling (safe + low CPU)

            local playerPed = PlayerPedId()

            if not DoesEntityExist(playerPed) then goto continue end

            -- Player dead check
            if IsEntityDead(playerPed) then
                if isWanted then
                    SendNotify("You were ~#e74c3c~killed~e~ by the law...", "tick", 5000)
                    Wait(3000)
                    ClearWantedLevel()
                end
                Wait(3000)
                goto continue
            end

            local inZone, zoneIndex, zoneData = IsPlayerInAnyZone()
            if not inZone then
                if isWanted and not isSearching then
                    StartSearchPhase()
                end
                goto continue
            end

            local now = GetGameTimer()

            -- ==========================================
            -- 1️⃣ GUNSHOT DETECTION (simple + reliable)
            -- ==========================================
            if IsPedShooting(playerPed) then
                if now - lastCrimeTime > 5000 then
                    lastCrimeTime = now
                    RegisterCrime(zoneIndex, zoneData, false, "Shots fired!")
                end
            end

            -- ==========================================
            -- 2️⃣ DEAD PED DETECTION (COUNT EACH ONCE)
            -- ==========================================
            local allPeds = GetGamePool('CPed')

            for _, ped in ipairs(allPeds) do
                if ped ~= playerPed
                and DoesEntityExist(ped)
                and not IsPedAPlayer(ped)
                and IsEntityDead(ped)
                and not processedDeadPeds[ped] then

                    local killer = Citizen.InvokeNative(0x93C8B64DEB84728C, ped)

                    processedDeadPeds[ped] = true -- mark immediately

                    if killer == playerPed then
                        if now - lastCrimeTime > 2000 then
                            lastCrimeTime = now
                            RegisterCrime(zoneIndex, zoneData, true, "You killed someone!")
                        end
                    end
                end
            end

            -- ==========================================
            -- 3️⃣ AIMING AT CIVILIANS
            -- ==========================================
            local _, weapon = GetCurrentPedWeapon(playerPed, true, 0, true)

            if weapon ~= 0 and weapon ~= GetHashKey('WEAPON_UNARMED') and not IsPedShooting(playerPed) then

                local camPos = GetGameplayCamCoord()
                local camRot = GetGameplayCamRot(2)

                local dir = {
                    x = -math.sin(math.rad(camRot.z)) * math.abs(math.cos(math.rad(camRot.x))),
                    y =  math.cos(math.rad(camRot.z)) * math.abs(math.cos(math.rad(camRot.x))),
                    z =  math.sin(math.rad(camRot.x))
                }

                local endPos = vector3(
                    camPos.x + dir.x * 60.0,
                    camPos.y + dir.y * 60.0,
                    camPos.z + dir.z * 60.0
                )

                local ray = StartShapeTestRay(
                    camPos.x, camPos.y, camPos.z,
                    endPos.x, endPos.y, endPos.z,
                    -1, playerPed, 0
                )

                local _, hit, _, _, entity = GetShapeTestResult(ray)

                if hit == 1
                and entity ~= 0
                and DoesEntityExist(entity)
                and IsEntityAPed(entity)
                and not IsPedAPlayer(entity)
                and not IsEntityDead(entity) then

                    if entity ~= lastAimTarget then
                        lastAimTarget = entity
                        aimStartTime = now
                    end

                    if now - aimStartTime >= (Config.CrimeAimDuration or 3000)
                    and now - lastAimCrimeTime > (Config.DetectionCooldown or 5000) then

                        lastAimCrimeTime = now
                        aimStartTime = now
                        RegisterCrime(zoneIndex, zoneData, false, "Aiming at civilians!")
                    end
                else
                    lastAimTarget = nil
                end
            else
                lastAimTarget = nil
            end

            ::continue::
        end
    end)

    -- ==========================================
    -- 4️⃣ VANDALISM (HEALTH MONITOR - RELIABLE)
    -- ==========================================
    CreateThread(function()

        local trackedHealth = {}

        while true do
            Wait(2000)

            local playerPed = PlayerPedId()
            if not DoesEntityExist(playerPed) or IsEntityDead(playerPed) then goto skip end

            local inZone, zoneIndex, zoneData = IsPlayerInAnyZone()
            if not inZone then goto skip end

            local playerCoords = GetEntityCoords(playerPed)
            local now = GetGameTimer()

            -- Objects
            local objects = GetGamePool('CObject')
            for _, obj in ipairs(objects) do
                if DoesEntityExist(obj)
                and not processedVandalism[obj]
                and #(GetEntityCoords(obj) - playerCoords) < 30.0 then

                    local health = GetEntityHealth(obj)
                    local prev = trackedHealth[obj]

                    if prev ~= nil and prev > 0 and health <= 0 then
                        processedVandalism[obj] = true
                        trackedHealth[obj] = nil

                        if now - lastVandalismCrimeTime > (Config.DetectionCooldown or 5000) then
                            lastVandalismCrimeTime = now
                            RegisterCrime(zoneIndex, zoneData, false, "Destroying property!")
                        end
                    else
                        trackedHealth[obj] = health
                    end
                end
            end

            -- Vehicles (wagons etc)
            local vehicles = GetGamePool('CVehicle')
            for _, veh in ipairs(vehicles) do
                if DoesEntityExist(veh)
                and not processedVandalism[veh]
                and #(GetEntityCoords(veh) - playerCoords) < 40.0 then

                    local health = GetEntityHealth(veh)
                    local prev = trackedHealth[veh]

                    if prev ~= nil and prev > 0 and health <= 0 then
                        processedVandalism[veh] = true
                        trackedHealth[veh] = nil

                        if now - lastVandalismCrimeTime > (Config.DetectionCooldown or 5000) then
                            lastVandalismCrimeTime = now
                            RegisterCrime(zoneIndex, zoneData, false, "Destroying property!")
                        end
                    else
                        trackedHealth[veh] = health
                    end
                end
            end

            ::skip::
        end
    end)

end

-- ============================================================
-- COMMANDS
-- ============================================================

RegisterCommand('wantedstatus', function()
    if isWanted then
        local wantedData = Config.WantedLevels[playerWantedLevel] or { name = "Unknown" }
        local aliveCops  = 0

        for _, data in ipairs(activePolice) do
            if DoesEntityExist(data.ped) and not IsPedDeadOrDying(data.ped) then
                aliveCops = aliveCops + 1
            end
        end

        SendNotify(
            "Level: ~#e74c3c~" .. wantedData.name ..
            "~e~ | Crimes: ~#f39c12~" .. crimeCount ..
            "~e~ | Lawmen: ~#e74c3c~" .. aliveCops ..
            "~e~ | Waves: ~#f39c12~" .. policeWaveCount ..
            "/" .. (Config.MaxPoliceWaves or 3) .. "~e~",
            "info", 8000
        )
    else
        SendNotify("You are ~#2ecc71~not wanted~e~ by the law.", "tick", 3000)
    end
end, false)
local function ConvertCopToArrestMode(ped)
    if not DoesEntityExist(ped) then return end

    EnsureNetworkControl(ped)

    -- Stop ALL combat immediately
    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)
    ClearPedTasks(ped)

    -- Remove weapons
    RemoveAllPedWeapons(ped, true, true)
    SetCurrentPedWeapon(ped, GetHashKey("WEAPON_UNARMED"), true, 0, false, false)

    -- Move to arrest relationship group
    if REL_ARREST then
        SetPedRelationshipGroupHash(ped, REL_ARREST)
    end

    -- Disable combat attributes
    for i = 0, 52 do
        SetPedCombatAttributes(ped, i, false)
    end

    SetPedCombatMovement(ped, 0)
    SetPedCombatRange(ped, 0)
    SetPedCombatAbility(ped, 0)
    SetPedFleeAttributes(ped, 0, false)

    TaskClearDefensiveArea(ped)

    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
end
local function PlayHandsUpAnim(ped)
    local dict = "mech_loco_f@generic@reaction@handsup@unarmed@normal"
    local anim = "loop"

    RequestAnimDict(dict)

    local timeout = 5000
    while not HasAnimDictLoaded(dict) and timeout > 0 do
        Wait(100)
        timeout = timeout - 100
    end

    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, anim, 2.0, 2.0, -1, 31, 0.0, false, false, false)
    end
end
RegisterCommand('surrender', function()

    if not isWanted then
        SendNotify("~#2ecc71~You are not wanted.~e~", "tick", 3000)
        return
    end

    SendNotify("~#f39c12~You surrender to the law...~e~", "tick", 3000)

    local playerPed = PlayerPedId()

    -- ✅ Stop police system
    chaseActive = false
    isSearching = false
    isWanted = false

    -- ✅ Neutralize hostility
    if REL_POLICE and REL_PLAYER then
        SetRelationshipBetweenGroups(0, REL_POLICE, REL_PLAYER)
        SetRelationshipBetweenGroups(0, REL_PLAYER, REL_POLICE)
    end

    -- ✅ Play hands-up animation
    PlayHandsUpAnim(playerPed)

    -- ✅ Convert police to neutral and walk up
    for _, data in ipairs(activePolice) do
        local ped = data.ped
        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped) then

            EnsureNetworkControl(ped)

            if REL_ARREST then
                SetPedRelationshipGroupHash(ped, REL_ARREST)
            end

            ClearPedTasksImmediately(ped)
            RemoveAllPedWeapons(ped, true, true)

            for i = 0, 52 do
                SetPedCombatAttributes(ped, i, false)
            end

            SetBlockingOfNonTemporaryEvents(ped, true)

            TaskGoToEntity(ped, playerPed, -1, 2.0, 2.0, 0, 0)
        end
    end

    -- ✅ Let them reach player
    Wait(6000)

    -- ✅ Jail for 2 minutes
    TriggerServerEvent('phils-police:server:JailPlayer', 2)

    -- ✅ Delete police after jailing
    for _, data in ipairs(activePolice) do
        if DoesEntityExist(data.ped) then
            DeletePed(data.ped)
        end
    end

    activePolice = {}

    ClearPedTasks(playerPed)

    -- ✅ Restore hostility for future crimes
    if REL_POLICE and REL_PLAYER then
        SetRelationshipBetweenGroups(5, REL_POLICE, REL_PLAYER)
        SetRelationshipBetweenGroups(5, REL_PLAYER, REL_POLICE)
    end

    ClearWantedLevel()

end, false)


RegisterCommand('policedebug', function()
    Config.Debug = not Config.Debug
    SendNotify(
        "Police debug: " .. (Config.Debug and "~#2ecc71~ON~e~" or "~#e74c3c~OFF~e~"),
        "info", 3000
    )
end, false)

-- ============================================================
-- NET EVENTS
-- ============================================================

RegisterNetEvent('police-chase:client:clearWanted', function()
    ClearWantedLevel()
    TriggerServerEvent('police-chase:server:clearCrimeData')
    SendNotify("Your ~#f39c12~wanted level~e~ cleared by admin.", "success", 5000)
end)

RegisterNetEvent('police-chase:client:restoreCrimeData', function(savedCount, savedLevel)
    if savedCount and savedCount > 0 then
        crimeCount = savedCount
        playerWantedLevel = savedLevel or 0
        DebugPrint('Restored persisted crime data: count=' .. crimeCount .. ', level=' .. tostring(playerWantedLevel))
    end
end)

RegisterNetEvent('RSGCore:Client:OnPlayerUnload', function()
    if isWanted then ClearWantedLevel() end
end)

RegisterNetEvent('police-chase:client:forceDisable', function()
    if isWanted then ClearWantedLevel() end
end)

-- Clear wanted when going on duty
RegisterNetEvent('RSGCore:Client:OnJobUpdate', function(job)
    if not job or not job.type then return end
    if string.lower(job.type) == string.lower(Config.LEOJobType or 'leo') and job.onduty then
        if isWanted then
            ClearWantedLevel()
            SendNotify("You went on duty — wanted level cleared.", "info", 5000)
        end
    end
end)

-- ============================================================
-- RESOURCE CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    CleanupAllPolice()
end)

-- ============================================================
-- INIT
-- ============================================================

CreateThread(function()
    Wait(2000)

    DebugPrint('Initializing...')
    DebugPrint('Loaded ' .. #Config.Police .. ' zones')

    -- Pre-scan dead peds the player killed so they aren't re-counted after restart
    local allDead = GetGamePool('CPed')
    local myPed = PlayerPedId()
    local marked = 0
    for _, nearPed in ipairs(allDead) do
        if nearPed ~= myPed
        and DoesEntityExist(nearPed)
        and not IsPedAPlayer(nearPed)
        and IsEntityDead(nearPed) then
            local killer = Citizen.InvokeNative(0x93C8B64DEB84728C, nearPed)
            if killer == myPed then
                processedDeadPeds[nearPed] = true
                marked = marked + 1
            end
        end
    end
    DebugPrint('Marked ' .. marked .. ' existing kills to prevent re-count')

    -- Request persisted crime data from server
    TriggerServerEvent('police-chase:server:loadCrimeData')

    CreateThread(function()
        while true do
            Wait(0)
            if isWanted then
                ClearPlayerWantedLevel(PlayerId())
            end
        end
    end)

    DetectCrimes()

    --SendNotify("~#2ecc71~Police system~e~ loaded!", "success", 3000, "system_loaded", 30000)
end)

