-- Data: snapshot of the logged-in character, saved in AltBoardDB.chars[guid].
-- Event driven: each event marks what changed and one short timer saves it all.
local _, AB = ...

local Data = {}
AB.Data = Data

local function char()
    local guid = AB.guid or UnitGUID("player")
    if not guid or not AB.db then return nil end
    local c = AB.db.chars[guid]
    if not c then
        c = {}
        AB.db.chars[guid] = c
    end
    return c
end

-- ---------------------------------------------------------------------------
-- Collectors
-- ---------------------------------------------------------------------------

local function collectIdentity(c)
    c.name = AB.Compat.PlayerName()
    c.realm = AB.Compat.PlayerRealm()
    local _, classFile = UnitClass("player")
    c.class = classFile
    c.race = UnitRace("player")
    c.faction = UnitFactionGroup("player")
    c.level = UnitLevel("player")
    c.guild = IsInGuild() and GetGuildInfo("player") or nil
    c.rested = GetXPExhaustion and GetXPExhaustion() or nil
    c.xp, c.xpMax = UnitXP("player"), UnitXPMax("player")
end

local function collectMoney(c)
    c.money = GetMoney()
end

local function collectGear(c)
    if not GetAverageItemLevel then return end
    local _, equipped = GetAverageItemLevel()
    c.ilvl = equipped
end

local function collectZone(c)
    c.zone = GetRealZoneText and GetRealZoneText() or nil
end

-- GetProfessions returns spellbook indexes (nil = empty slot). Slots 1-2 are the main
-- professions, the rest secondary; each index goes to GetProfessionInfo.
local function collectProfessions(c)
    if not (GetProfessions and GetProfessionInfo) then return end
    local slots = { GetProfessions() }
    local list = {}
    for slot = 1, select("#", GetProfessions()) do
        local index = slots[slot]
        if index then
            local ok, name, icon, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, index)
            if ok and name then
                list[#list + 1] = {
                    name = name, icon = icon, rank = rank, max = maxRank,
                    skillLine = skillLine, primary = slot <= 2,
                }
            end
        end
    end
    c.profs = list
end

-- Only currencies the character has (quantity > 0) are kept, keyed by name (the list
-- does not always carry an id).
local function collectCurrency(c)
    local CI = C_CurrencyInfo
    if not (CI and CI.GetCurrencyListSize and CI.GetCurrencyListInfo) then return end
    local out = {}
    for i = 1, CI.GetCurrencyListSize() do
        local info = CI.GetCurrencyListInfo(i)
        if info and not info.isHeader and info.name and (info.quantity or 0) > 0 then
            out[info.name] = { qty = info.quantity, max = info.maxQuantity, icon = info.iconFileID }
        end
    end
    c.currency = out
end

-- Reputation: { [factionID] = { name, group, reaction, cur, min, max } }.
-- Blizzard's list hides factions under collapsed headers, so factions seen before are
-- kept and refreshed by ID instead (never expanding the player's headers).
local function repEntry(d, group)
    return {
        name = d.name, group = group, reaction = d.reaction,
        cur = d.currentStanding, min = d.currentReactionThreshold, max = d.nextReactionThreshold,
    }
end

local function collectReputation(c)
    local R = C_Reputation
    if not (R and R.GetNumFactions and R.GetFactionDataByIndex) then return end
    local out, group = {}, nil
    for i = 1, R.GetNumFactions() do
        local d = R.GetFactionDataByIndex(i)
        if d and d.name then
            if d.isHeader and not d.isChild then group = d.name end
            if d.factionID and d.factionID > 0 and (not d.isHeader or d.isHeaderWithRep) then
                out[d.factionID] = repEntry(d, group)
            end
        end
    end
    if R.GetFactionDataByID then
        for id, old in pairs(c.reps or {}) do
            if not out[id] then
                local ok, d = pcall(R.GetFactionDataByID, id)
                if ok and d and d.name then out[id] = repEntry(d, old.group) end
            end
        end
    end
    c.reps = out
end

local COLLECTORS = {
    identity = collectIdentity, money = collectMoney, gear = collectGear, zone = collectZone,
    profs = collectProfessions, currency = collectCurrency, reps = collectReputation,
}

-- ---------------------------------------------------------------------------
-- Dirty flags + one timer
-- ---------------------------------------------------------------------------

local dirty, pending = {}, false

local function flush()
    pending = false
    local c = char()
    if not c then return end
    for part in pairs(dirty) do
        local ok, err = pcall(COLLECTORS[part], c)
        if not ok then AB:RecordError("collect " .. part, err) end
    end
    wipe(dirty)
    c.lastSeen = time()
    if AB.Board then AB.Board.Refresh() end
end

function Data.Mark(...)
    for i = 1, select("#", ...) do dirty[select(i, ...)] = true end
    if not pending then
        pending = true
        AB.Compat.After(1, flush)
    end
end

-- Right now, without waiting (opening the board, logout).
function Data.Flush()
    if next(dirty) then flush() end
end

AB:RegisterEvent("PLAYER_LOGIN", function()
    -- Professions and currencies are not always ready at login: again a bit later.
    Data.Mark("identity", "money", "gear", "zone", "profs", "currency", "reps")
    AB.Compat.After(5, function() Data.Mark("profs", "currency", "gear", "reps") end)
end)

local EVENTS = {
    PLAYER_MONEY = { "money" },
    PLAYER_LEVEL_UP = { "identity" },
    PLAYER_XP_UPDATE = { "identity" },
    UPDATE_EXHAUSTION = { "identity" },
    PLAYER_GUILD_UPDATE = { "identity" },
    PLAYER_EQUIPMENT_CHANGED = { "gear" },
    ZONE_CHANGED_NEW_AREA = { "zone" },
    SKILL_LINES_CHANGED = { "profs" },
    TRADE_SKILL_LIST_UPDATE = { "profs" },
    CURRENCY_DISPLAY_UPDATE = { "currency" },
    UPDATE_FACTION = { "reps" },
}
for event, parts in pairs(EVENTS) do
    AB:RegisterEvent(event, function() Data.Mark(unpack(parts)) end)
end

-- Logout: only the zone and "last seen". GetMoney() already returns 0 here on WoW Forever,
-- and money is kept current by PLAYER_MONEY anyway.
AB:RegisterEvent("PLAYER_LOGOUT", function()
    dirty.money = nil
    Data.Mark("zone")
    flush()
end)

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

-- Characters as a list { guid = ..., data = ... }. Default order: current first, then
-- level, then name. Once the player moved a character, AltBoardDB.order decides and
-- characters not in it yet come last (in the default order).
function Data.Characters(includeHidden)
    local list = {}
    for guid, c in pairs(AB.db and AB.db.chars or {}) do
        if c.name and (includeHidden or not c.hidden) then list[#list + 1] = { guid = guid, data = c } end
    end
    local me = AB.guid
    local pos = {}
    for i, guid in ipairs(AB.db and AB.db.order or {}) do pos[guid] = i end
    sort(list, function(a, b)
        local pa, pb = pos[a.guid] or math.huge, pos[b.guid] or math.huge
        if pa ~= pb then return pa < pb end
        if (a.guid == me) ~= (b.guid == me) then return a.guid == me end
        local la, lb = a.data.level or 0, b.data.level or 0
        if la ~= lb then return la > lb end
        return (a.data.name or "") < (b.data.name or "")
    end)
    return list
end

function Data.HiddenCount()
    local n = 0
    for _, c in pairs(AB.db and AB.db.chars or {}) do
        if c.name and c.hidden then n = n + 1 end
    end
    return n
end

-- Move a character one step (-1 left, +1 right) among the visible ones (hidden characters
-- are skipped over). Saves the full order from then on.
function Data.Move(guid, dir, includeHidden)
    local shown = Data.Characters(includeHidden)
    local i
    for n, e in ipairs(shown) do if e.guid == guid then i = n end end
    local j = i and i + dir
    if not j or j < 1 or j > #shown then return end
    shown[i], shown[j] = shown[j], shown[i]
    -- Rebuild the order: the visible ones as now shown, hidden ones kept in their slots.
    local all, order, k = Data.Characters(true), {}, 0
    for _, e in ipairs(all) do
        if includeHidden or not e.data.hidden then
            k = k + 1
            order[#order + 1] = shown[k].guid
        else
            order[#order + 1] = e.guid
        end
    end
    AB.db.order = order
end

function Data.SetHidden(guid, hidden)
    local c = AB.db.chars[guid]
    if c then c.hidden = hidden or nil end
end

-- Forget a character completely (never the logged-in one: it would come straight back).
function Data.Delete(guid)
    if guid == AB.guid then return end
    AB.db.chars[guid] = nil
    local order = AB.db.order
    if order then
        for i = #order, 1, -1 do if order[i] == guid then tremove(order, i) end end
    end
end

function Data.TotalMoney(includeHidden)
    local total = 0
    for _, c in pairs(AB.db and AB.db.chars or {}) do
        if includeHidden or not c.hidden then total = total + (c.money or 0) end
    end
    return total
end
