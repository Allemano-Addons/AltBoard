-- Probe (step 0): records what the WoW Forever client really returns for the APIs
-- AltBoard will depend on. Saved to AltBoardDB.probe[guid] so it can be read from the
-- SavedVariables file after /reload. Remove once v0.1 is built on the results.
local _, AB = ...

-- Every return value as a string (keeps nils visible, never saves odd types).
local function pack(...)
    local t = { n = select("#", ...) }
    for i = 1, t.n do t[i] = tostring((select(i, ...))) end
    return t
end

-- pcall that records either the packed returns or the error.
local function try(fn, ...)
    if type(fn) ~= "function" then return { missing = true } end
    local res = pack(pcall(fn, ...))
    if res[1] ~= "true" then return { err = res[2] } end
    tremove(res, 1)
    res.n = res.n - 1
    return res
end

local API_NAMES = {
    -- identity / basics
    "UnitGUID", "UnitName", "UnitFullName", "UnitClass", "UnitRace", "UnitLevel", "UnitFactionGroup",
    "GetMoney", "GetAverageItemLevel", "RequestTimePlayed", "GetGuildInfo", "GetRealZoneText",
    "GetXPExhaustion", "UnitXP", "UnitXPMax", "GetRestState",
    -- lockouts
    "RequestRaidInfo", "GetNumSavedInstances", "GetSavedInstanceInfo", "GetSavedInstanceEncounterInfo",
    "GetSavedInstanceChatLink", "GetNumSavedWorldBosses", "GetSavedWorldBossInfo", "GetDifficultyInfo",
    "GetQuestResetTime", "GetServerTime", "C_DateAndTime", "GetGameTime",
    -- professions
    "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo",
    "GetSpellCooldown", "C_Spell", "GetItemCooldown", "C_Container", "GetSpellInfo", "IsSpellKnown",
    -- reputation
    "GetNumFactions", "GetFactionInfo", "GetFactionInfoByID", "C_Reputation", "ExpandFactionHeader",
    -- misc
    "C_CurrencyInfo", "GetNumTitles", "C_Map", "C_Item", "C_MountJournal", "GetInventoryItemLink",
}

local function probeApis()
    local out = {}
    for _, name in ipairs(API_NAMES) do out[name] = type(_G[name]) end
    local ns = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:match("^C_") and type(v) == "table" then ns[#ns + 1] = k end
    end
    sort(ns)
    out._namespaces = table.concat(ns, " ")
    local function fns(tbl)
        local list = {}
        if type(tbl) == "table" then
            for k, v in pairs(tbl) do if type(v) == "function" then list[#list + 1] = k end end
        end
        sort(list)
        return table.concat(list, " ")
    end
    out._C_Reputation = fns(C_Reputation)
    out._C_Spell = fns(C_Spell)
    out._C_DateAndTime = fns(C_DateAndTime)
    out._C_TradeSkillUI = fns(C_TradeSkillUI)
    return out
end

local function probeIdentity()
    return {
        guid = try(UnitGUID, "player"),
        name = try(UnitName, "player"),
        fullName = try(UnitFullName, "player"),
        playerName = AB.Compat.PlayerName(),
        realm = AB.Compat.PlayerRealm(),
        class = try(UnitClass, "player"),
        race = try(UnitRace, "player"),
        level = try(UnitLevel, "player"),
        faction = try(UnitFactionGroup, "player"),
        money = try(GetMoney),
        ilvl = try(GetAverageItemLevel),
        guild = try(GetGuildInfo, "player"),
        zone = try(GetRealZoneText),
        rested = try(GetXPExhaustion),
        serverTime = try(GetServerTime),
        localTime = time(),
        questReset = try(GetQuestResetTime),
        weeklyReset = C_DateAndTime and try(C_DateAndTime.GetSecondsUntilWeeklyReset) or { missing = true },
        build = pack(GetBuildInfo()),
    }
end

local function probeLockouts()
    local out = { count = try(GetNumSavedInstances), instances = {}, worldBosses = {} }
    local n = tonumber(out.count[1]) or 0
    for i = 1, n do
        local inst = { info = try(GetSavedInstanceInfo, i), link = try(GetSavedInstanceChatLink, i), bosses = {} }
        local numBosses = tonumber(inst.info[9]) or 0 -- 9th return = numEncounters on retail-style API
        for j = 1, math.max(numBosses, 1) + 2 do    -- a few extra to see what past the end returns
            inst.bosses[j] = try(GetSavedInstanceEncounterInfo, i, j)
        end
        out.instances[i] = inst
    end
    local wb = try(GetNumSavedWorldBosses)
    out.worldBossCount = wb
    for i = 1, tonumber(wb[1]) or 0 do out.worldBosses[i] = try(GetSavedWorldBossInfo, i) end
    return out
end

local function probeSkills()
    local out = { profs = try(GetProfessions), lines = {} }
    local n = tonumber(try(GetNumSkillLines)[1]) or 0
    for i = 1, n do out.lines[i] = try(GetSkillLineInfo, i) end
    -- Classic profession cooldown spells (transmute, mooncloth, salt shaker...), to see
    -- whether GetSpellCooldown reports them.
    out.cooldowns = {}
    for _, id in ipairs({ 11479, 17187, 18560, 19566, 15846, 17559 }) do
        out.cooldowns[id] = {
            known = try(IsSpellKnown, id),
            info = try(GetSpellInfo, id),
            cd = try(GetSpellCooldown, id),
        }
    end
    return out
end

local function probeReputation()
    local out = { count = try(GetNumFactions), list = {} }
    local n = tonumber(out.count[1]) or 0
    for i = 1, n do out.list[i] = try(GetFactionInfo, i) end
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        out.cCount = try(C_Reputation.GetNumFactions)
        out.cFirst = {}
        for i = 1, math.min(tonumber(out.cCount[1]) or 0, 5) do
            local ok, data = pcall(C_Reputation.GetFactionDataByIndex, i)
            if ok and type(data) == "table" then
                local flat = {}
                for k, v in pairs(data) do flat[k] = tostring(v) end
                out.cFirst[i] = flat
            end
        end
    end
    return out
end

-- /altboard probe: raid info and played time arrive by events, so ask, wait, then save.
local running = false
local function runProbe()
    if running then return end
    running = true
    AB:Print("Probing... (a few seconds)")
    local result = { v = AB.version, at = date("%Y-%m-%d %H:%M:%S") }
    local waiting = { UPDATE_INSTANCE_INFO = true, TIME_PLAYED_MSG = true }

    local function finish()
        if not running then return end
        running = false
        local ok, err = pcall(function()
            result.apis = probeApis()
            result.identity = probeIdentity()
            result.lockouts = probeLockouts()
            result.skills = probeSkills()
            result.reputation = probeReputation()
        end)
        if not ok then result.error = tostring(err) end
        AB.db.probe = AB.db.probe or {}
        AB.db.probe[UnitGUID("player") or AB.Compat.PlayerName()] = result
        AB:Print(ok and "Probe saved." or ("Probe saved with an error: " .. tostring(err)),
            "Now type /reload so the file is written.")
    end

    local function onEvent(event, ...)
        if event == "TIME_PLAYED_MSG" then result.played = pack(...) end
        waiting[event] = nil
        AB:UnregisterEvent(event, onEvent)
        if not next(waiting) then finish() end
    end
    for event in pairs(CopyTable(waiting)) do
        if not AB:RegisterEvent(event, onEvent) then waiting[event] = nil end
    end
    if RequestRaidInfo then RequestRaidInfo() else waiting.UPDATE_INSTANCE_INFO = nil end
    if RequestTimePlayed then RequestTimePlayed() else waiting.TIME_PLAYED_MSG = nil end
    if not next(waiting) then finish() end
    -- Never wait forever for an event the server does not send.
    AB.Compat.After(5, function()
        if running then
            result.timedOut = CopyTable(waiting)
            for event in pairs(waiting) do AB:UnregisterEvent(event, onEvent) end
            finish()
        end
    end)
end

AB:AddSlashCommand("probe", runProbe, "record API results for development (then /reload)")
