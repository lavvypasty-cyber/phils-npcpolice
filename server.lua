local RSGCore = exports['rsg-core']:GetCoreObject()

-- Track wanted players
local wantedPlayers = {}

-- ============================================================
-- PERSISTENT CRIME DATA (JSON)
-- ============================================================

local persistFile = 'wanted_persist.json'
local resourceName = GetCurrentResourceName()

local function LoadPersistData()
    local content = LoadResourceFile(resourceName, persistFile)
    if content and content ~= '' then
        local ok, result = pcall(json.decode, content)
        if ok and type(result) == 'table' then
            return result
        end
    end
    return {}
end
local RSGCore = exports['rsg-core']:GetCoreObject()

RegisterNetEvent('phils-police:server:JailPlayer', function(time)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    -- ✅ Set jail metadata
    Player.Functions.SetMetaData('injail', time)

    -- ✅ Trigger prison enter properly
    TriggerClientEvent('rsg-prison:client:Enter', src, time)
end)
local function SavePersistData(data)
    SaveResourceFile(resourceName, persistFile, json.encode(data), -1)
end

-- Create file on start if it doesn't exist
SavePersistData(LoadPersistData())

local persistData = LoadPersistData()

CreateThread(function()
    Wait(500)
    persistData = LoadPersistData()
    local count = 0
    for _ in pairs(persistData) do count = count + 1 end
    print('[Police-Chase] Loaded ' .. count .. ' persisted crime records')
end)

RegisterNetEvent('police-chase:server:saveCrimeData', function(crimeCount, wantedLevel)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid
    if not cid then return end
    persistData[cid] = { crimeCount = crimeCount, wantedLevel = wantedLevel, time = os.time() }
    SavePersistData(persistData)
end)

RegisterNetEvent('police-chase:server:loadCrimeData', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid
    if not cid then return end
    local data = persistData[cid]
    if data then
        TriggerClientEvent('police-chase:client:restoreCrimeData', src, data.crimeCount, data.wantedLevel)
    end
end)

RegisterNetEvent('police-chase:server:clearCrimeData', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid
    if not cid then return end
    persistData[cid] = nil
    SavePersistData(persistData)
end)

-- Track LEO online status
local leoOnline = false
local leoCount = 0

-- ============================================================
-- LEO ONLINE CHECK (BY JOB TYPE)
-- ============================================================

local function IsLEOJobType(player)
    if not player then return false end
    if not player.PlayerData then return false end
    if not player.PlayerData.job then return false end

    local jobType = player.PlayerData.job.type

    if not jobType then return false end

    -- Compare job type (case insensitive)
    return string.lower(jobType) == string.lower(Config.LEOJobType or 'leo')
end

local function CheckLEOOnline()
    local players = RSGCore.Functions.GetRSGPlayers()
    local count = 0

    for _, player in pairs(players) do
        if IsLEOJobType(player) then
            count = count + 1
        end
    end

    local wasOnline = leoOnline
    leoCount = count
    leoOnline = count > 0

    -- Status changed - notify all clients
    if wasOnline ~= leoOnline then
        TriggerClientEvent('police-chase:client:leoStatusChanged', -1, leoOnline, leoCount)

        if leoOnline then
            print('[Police-Chase] LEO is now ONLINE (' .. leoCount .. ' officers). NPC police DISABLED.')
        else
            print('[Police-Chase] No LEO online. NPC police ENABLED.')
        end
    end

    return leoOnline
end

-- Periodic LEO check
CreateThread(function()
    Wait(5000) -- Initial delay for players to load

    while true do
        CheckLEOOnline()
        Wait(Config.LEOCheckInterval or 30000)
    end
end)

-- ============================================================
-- LEO STATUS EVENTS
-- ============================================================

-- Player requests current LEO status (on join / resource start)
RegisterNetEvent('police-chase:server:requestLEOStatus', function()
    local src = source
    CheckLEOOnline()
    TriggerClientEvent('police-chase:client:leoStatusChanged', src, leoOnline, leoCount)
end)

-- Re-check when a player changes job
RegisterNetEvent('RSGCore:Server:OnJobUpdate', function(source, job)
    Wait(500)
    CheckLEOOnline()
end)

-- Also listen for SetJob event (some versions use this)
RegisterNetEvent('RSGCore:Server:SetJob', function(source, job)
    Wait(500)
    CheckLEOOnline()
end)

-- Re-check when player joins
RegisterNetEvent('RSGCore:Server:PlayerLoaded', function(player)
    Wait(2000)
    CheckLEOOnline()
end)

-- Re-check when player drops
AddEventHandler('playerDropped', function(reason)
    local src = source

    -- Clear wanted data
    if wantedPlayers[src] then
        print('[Police-Chase] Wanted player ' .. wantedPlayers[src].name .. ' (ID: ' .. src .. ') disconnected: ' .. reason)
        wantedPlayers[src] = nil
    end

    -- Re-check LEO status after player drops
    Wait(1000)
    CheckLEOOnline()
end)

-- ============================================================
-- SERVER SIDE BLN-NOTIFY HELPER
-- ============================================================

local function SendNotifyToClient(source, message, type, duration)
    duration = duration or 5000

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

    local config = notifyConfig[type] or notifyConfig['info']

    if config.template then
        TriggerClientEvent("bln_notify:send", source, {
            description = message,
            duration    = duration,
            placement   = "top-right",
        }, config.template)
    else
        TriggerClientEvent("bln_notify:send", source, {
            title       = config.title,
            description = message,
            icon        = config.icon,
            duration    = duration,
            placement   = "top-right",
        })
    end
end

-- ============================================================
-- SERVER EVENTS
-- ============================================================

RegisterNetEvent('police-chase:server:playerWanted', function(wantedLevel, zoneName)
    local src = source

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Block if the player themselves are LEO
    if IsLEOJobType(Player) then
        SendNotifyToClient(src, "You are law enforcement — no NPC police response.", "info", 3000)
        TriggerClientEvent('police-chase:client:forceDisable', src)
        return
    end

    local playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname

    wantedPlayers[src] = {
        name  = playerName,
        level = wantedLevel,
        zone  = zoneName,
        time  = os.time()
    }

    print('[Police-Chase] Player ' .. playerName .. ' (ID: ' .. src .. ') is now wanted (Level ' .. wantedLevel .. ') in ' .. zoneName)
end)

RegisterNetEvent('police-chase:server:clearWanted', function()
    local src = source

    if wantedPlayers[src] then
        print('[Police-Chase] Player ' .. wantedPlayers[src].name .. ' (ID: ' .. src .. ') is no longer wanted')
        wantedPlayers[src] = nil
    end
end)

RegisterNetEvent('police-chase:server:payBounty', function(crimeCount)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)

    if not Player then return end

    local bountyAmount = crimeCount * 5
    local currentCash  = Player.PlayerData.money['cash'] or 0

    if currentCash >= bountyAmount then
        Player.Functions.RemoveMoney('cash', bountyAmount, 'police-bounty')
        SendNotifyToClient(src, "You paid ~#e74c3c~$" .. bountyAmount .. "~e~ in bounty fees.", "error", 5000)
    else
        if currentCash > 0 then
            Player.Functions.RemoveMoney('cash', currentCash, 'police-bounty-partial')
        end
        SendNotifyToClient(src, "You could not pay the full bounty of ~#e74c3c~$" .. bountyAmount .. "~e~.", "error", 5000)
    end

    if wantedPlayers[src] then
        wantedPlayers[src] = nil
    end
end)

-- ============================================================
-- ADMIN COMMANDS
-- ============================================================

RSGCore.Commands.Add('clearwanted', 'Clear a player wanted level (Admin)', {
    { name = 'id', help = 'Player ID' }
}, true, function(source, args)
    local targetId = tonumber(args[1])

    if not targetId then
        SendNotifyToClient(source, "Invalid player ID.", "error", 3000)
        return
    end

    local targetPlayer = RSGCore.Functions.GetPlayer(targetId)
    if not targetPlayer then
        SendNotifyToClient(source, "Player not found.", "error", 3000)
        return
    end

    TriggerClientEvent('police-chase:client:clearWanted', targetId)
    SendNotifyToClient(source, "Cleared wanted level for player ~#2ecc71~" .. targetId .. "~e~.", "success", 3000)

    if wantedPlayers[targetId] then
        wantedPlayers[targetId] = nil
    end

    print('[Police-Chase] Admin (ID: ' .. source .. ') cleared wanted level for player ID: ' .. targetId)
end, 'admin')

RSGCore.Commands.Add('wantedlist', 'Show all wanted players (Admin)', {}, false, function(source, args)
    local count = 0

    for playerId, data in pairs(wantedPlayers) do
        count = count + 1
        local message = "ID: ~#e74c3c~" .. playerId .. "~e~ | " .. data.name .. " | Level: ~#f39c12~" .. data.level .. "~e~ | Zone: " .. data.zone
        SendNotifyToClient(source, message, "info", 8000)
        Wait(500)
    end

    if count == 0 then
        SendNotifyToClient(source, "No players are currently wanted.", "info", 5000)
    else
        SendNotifyToClient(source, "Total wanted: ~#e74c3c~" .. count .. "~e~", "info", 5000)
    end
end, 'admin')

RSGCore.Commands.Add('leostatus', 'Check LEO online status (Admin)', {}, false, function(source, args)
    CheckLEOOnline()

    if leoOnline then
        SendNotifyToClient(source, "~#2ecc71~" .. leoCount .. "~e~ LEO (type: " .. (Config.LEOJobType or 'leo') .. ") online. NPC police ~#e74c3c~DISABLED~e~.", "info", 5000)
    else
        SendNotifyToClient(source, "~#e74c3c~No~e~ LEO (type: " .. (Config.LEOJobType or 'leo') .. ") online. NPC police ~#2ecc71~ENABLED~e~.", "info", 5000)
    end
end, 'admin')

-- Debug command to see all players' job info
RSGCore.Commands.Add('debugjobs', 'Show all players job info (Admin)', {}, false, function(source, args)
    local players = RSGCore.Functions.GetRSGPlayers()

    print('=== DEBUG: All Player Jobs ===')
    for _, player in pairs(players) do
        if player and player.PlayerData and player.PlayerData.job then
            local job = player.PlayerData.job
            local msg = string.format(
                'ID: %d | Name: %s | Type: %s | Grade: %d',
                player.PlayerData.source or 0,
                job.name or 'none',
                job.type or 'none',
                job.grade or 0
            )
            print(msg)
            SendNotifyToClient(source, msg, "info", 8000)
            Wait(500)
        end
    end
    print('==============================')
end, 'admin')

-- ============================================================
-- RESOURCE CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    wantedPlayers = {}
    print('[Police-Chase] Resource stopped, cleared all wanted players.')
end)

print('[Police-Chase] Server-side loaded successfully!')
print('[Police-Chase] Checking for job TYPE: ' .. (Config.LEOJobType or 'leo'))