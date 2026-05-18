Config = {}

-- General Settings
Config.DispatchDelay = 5000          -- Delay in ms before police spawn after crime
Config.ChaseRadius = 200.0           -- How far police will chase before giving up
Config.SearchDuration = 30000        -- How long police search after losing sight (ms)
Config.WantedCooldown = 60000        -- Time in ms before wanted level decays after escaping
Config.MaxPoliceWaves = 1           -- Maximum number of police waves that can be active
Config.TimeBetweenWaves = 15000      -- Time between additional police waves (ms)
Config.PoliceAccuracy = 45.0         -- Police shooting accuracy (0-100)
Config.PoliceRunSpeed = 3.0          -- Police movement speed (1.0 = walk, 3.0 = sprint)
Config.DetectionCooldown = 2000      -- Cooldown between crime detections (ms)

-- New Crime Settings
Config.CrimeAimDuration = 3000       -- ms aiming at NPC before it's a crime

Config.LEOJobType = 'leo'  -- The job type to check for
Config.LEOCheckInterval = 30000 -- 30 seconds
Config.LEOOnlineMessage = "Law enforcement officers are on duty."
-- Wanted Levels
Config.WantedLevels = {
    [1] = { name = "Disturbing the Peace", minCrimes = 1,  extraPeds = 0 },
    [2] = { name = "Wanted Criminal",      minCrimes = 3,  extraPeds = 2 },
    [3] = { name = "Dangerous Outlaw",      minCrimes = 6,  extraPeds = 4 },
    [4] = { name = "Public Enemy",          minCrimes = 10, extraPeds = 6 },
}

-- Notification Settings
Config.NotifyType = 'bln-notify' -- Using bln-notify

-- Police Zone Configuration
Config.Police = {
    [1]  = {
        centerzonecoords = vector3(-290.94305419921875, 734.415771484375, 117.43962097167969),
        radius = 200.0,
        pedmodel = "a_m_m_valdeputyresident_01",
        policespawncoords = vector3(-268.73, 809.68, 119.2),
        numberofpedstocreate = 2,
        weapon1 = "weapon_revolver_cattleman",
        weapon2 = "weapon_rifle_bolt_action",
        health = 100,
        policecooldown = 1,
        policeinvicible = false,
        zoneName = "Valentine"
    },
    [2]  = {
        centerzonecoords = vector3(-799.2973022460938, -1316.4456787109375, 43.60391235351562),
        radius = 120.0,
        pedmodel = "s_m_m_ambientblwpolice_01",
        policespawncoords = vector3(-747.77, -1268.14, 43.19),
        numberofpedstocreate = 2,
        weapon1 = "weapon_revolver_cattleman",
        weapon2 = "weapon_rifle_bolt_action",
        health = 100,
        policecooldown = 1,
        policeinvicible = false,
        zoneName = "Blackwater"
    },
    [3]  = {
        centerzonecoords = vector3(-1804.5823974609375, -404.25775146484375, 154.07200622558594),
        radius = 120.0,
        pedmodel = "a_m_m_strdeputyresident_01",
        policespawncoords = vector3(-1801.24, -352.63, 164.07),
        numberofpedstocreate = 2,
        weapon1 = "weapon_revolver_cattleman",
        weapon2 = "weapon_rifle_bolt_action",
        health = 100,
        policecooldown = 1,
        policeinvicible = false,
        zoneName = "Strawberry"
    },
    [4]  = {
        centerzonecoords = vector3(-5512.77685546875, -2940.746826171875, -2.10357570648193),
        radius = 120.0,
        pedmodel = "a_m_m_armdeputyresident_01",
        policespawncoords = vector3(-5517.98, -2931.45, -2.08),
        numberofpedstocreate = 2,
        weapon1 = "weapon_revolver_cattleman",
        weapon2 = "weapon_rifle_bolt_action",
        health = 100,
        policecooldown = 1,
        policeinvicible = false,
        zoneName = "Tumbleweed"
    },
    [5]  = {
        centerzonecoords = vector3(-3707.22216796875, -2612.533935546875, -13.75928592681884),
        radius = 120.0,
        pedmodel = "a_m_m_armdeputyresident_01",
        policespawncoords = vector3(-3676.96, -2611.96, -14.08),
        numberofpedstocreate = 2,
        weapon1 = "weapon_revolver_cattleman",
        weapon2 = "weapon_rifle_bolt_action",
        health = 100,
        policecooldown = 1,
        policeinvicible = false,
        zoneName = "Armadillo"
    },
    [6]  = {
        centerzonecoords = vector3(1307.4217529296875, -1292.3609619140625, 75.79313659667969),
        radius = 120.0,
        pedmodel = "a_m_m_rhddeputyresident_01",
        policespawncoords = vector3(1358.38, -1312.48, 76.91),
        numberofpedstocreate = 2,
        weapon1 = "weapon_revolver_cattleman",
        weapon2 = "weapon_rifle_bolt_action",
        health = 100,
        policecooldown = 1,
        policeinvicible = false,
        zoneName = "Rhodes"
    },
    [7]  = {
        centerzonecoords = vector3(2523.26, -1279.84, 49.04),
        radius = 600.0,
        pedmodel = "s_m_m_ambientsdpolice_01",
        policespawncoords = vector3(2523.26, -1279.84, 49.04),
        numberofpedstocreate = 2,
        weapon1 = "weapon_revolver_cattleman",
        weapon2 = "weapon_rifle_bolt_action",
        health = 100,
        policecooldown = 1,
        policeinvicible = false,
        zoneName = "Saint Denis"
    },
    [8]  = {
        centerzonecoords = vector3(2959.2890625, 531.40625, 44.44278335571289),
        radius = 100.0,
        pedmodel = "a_m_m_asbdeputyresident_01",
        policespawncoords = vector3(2956.04, 496.64, 46.01),
        numberofpedstocreate = 2,
        weapon1 = "weapon_revolver_cattleman",
        weapon2 = "weapon_rifle_bolt_action",
        health = 100,
        policecooldown = 1,
        policeinvicible = false,
        zoneName = "Van Horn"
    },
    [9]  = {
        centerzonecoords = vector3(2929.720947265625, 1332.70849609375, 44.07649612426758),
        radius = 170.0,
        pedmodel = "a_m_m_asbdeputyresident_01",
        policespawncoords = vector3(2914.61, 1309.58, 44.39),
        numberofpedstocreate = 2,
        weapon1 = "weapon_revolver_cattleman",
        weapon2 = "weapon_rifle_bolt_action",
        health = 100,
        policecooldown = 1,
        policeinvicible = false,
        zoneName = "Annesburg"
    },
}