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

-- pcall a function that may be missing on this client; nil if missing or failing.
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end
Data.Safe = safe

local function getItemInfo(link)
    return safe((C_Item and C_Item.GetItemInfo) or GetItemInfo, link)
end

-- Equipped items, slots 1-19 (head ... tabard). Name, quality, item level and icon are
-- saved with the link, so other characters can show them without the item being cached.
-- Items the client has not loaded yet are filled in when GET_ITEM_INFO_RECEIVED arrives.
local gearIncomplete = false

local function collectGear(c)
    if GetAverageItemLevel then
        local _, equipped = GetAverageItemLevel()
        c.ilvl = equipped
    end
    local gear, incomplete = {}, false
    for slot = 1, 19 do
        local link = safe(GetInventoryItemLink, "player", slot)
        if link then
            local name, _, quality, ilvl, _, _, _, _, _, icon = getItemInfo(link)
            local detailed = safe((C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo, link)
            if not name then incomplete = true end
            gear[slot] = {
                link = link, name = name, q = quality, ilvl = detailed or ilvl,
                icon = icon or safe(GetInventoryItemTexture, "player", slot),
            }
        end
    end
    c.gear = gear
    gearIncomplete = incomplete
end

-- ---------------------------------------------------------------------------
-- Bags and bank: counts per item, c.bags / c.bank = { [key] = count }. key is the item ID,
-- plus ":suffix" for random-suffix items ("of the Bear"). Name/quality/icon/link live once
-- per key in AltBoardDB.items, shared by all characters (search reads names from there).
-- ---------------------------------------------------------------------------

-- "item:ID:enchant:gem1:gem2:gem3:gem4:suffix:..." -> "ID" or "ID:suffix".
function Data.ItemKey(link)
    local itemString = link and link:match("item:([%-%d:]+)")
    if not itemString then return nil end
    local fields = { strsplit(":", itemString) }
    local id, suffix = fields[1], fields[7]
    if not id or id == "" then return nil end
    if suffix and suffix ~= "" and suffix ~= "0" then return id .. ":" .. suffix end
    return id
end

local itemsIncomplete = false

-- Remember what an item is (once per key). Returns the key.
local function rememberItem(link, icon, quality)
    local key = Data.ItemKey(link)
    if not key then return nil end
    local items = AB.db.items
    if not items[key] then
        local name, _, q, _, _, _, _, _, _, tex = getItemInfo(link)
        -- Not loaded yet: the name inside the link will do until GET_ITEM_INFO_RECEIVED.
        items[key] = { n = name or link:match("%[(.-)%]"), q = q or quality, i = tex or icon, l = link,
            pending = not name or nil }
        if not name then itemsIncomplete = true end
    end
    return key
end
Data.RememberItem = rememberItem

-- Container IDs by kind. Modern clients name them in Enum.BagIndex; older ones use numbers.
local containerCache
local function containers()
    if containerCache then return containerCache end
    local bags, bank = {}, {}
    local E = Enum and Enum.BagIndex
    if E then
        for name, id in pairs(E) do
            if name == "Backpack" or name:match("^Bag_%d") or name == "ReagentBag" then
                bags[#bags + 1] = id
            elseif name == "Bank" or name:match("^BankBag") or name:match("^CharacterBankTab") then
                bank[#bank + 1] = id
            end
        end
    end
    if #bags == 0 then
        for id = 0, NUM_BAG_SLOTS or 4 do bags[#bags + 1] = id end
    end
    if #bank == 0 then
        bank[1] = BANK_CONTAINER or -1
        local first = (NUM_BAG_SLOTS or 4) + 1
        for id = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do bank[#bank + 1] = id end
    end
    sort(bags)
    sort(bank)
    containerCache = { bags = bags, bank = bank }
    return containerCache
end

local CC = C_Container
local function numSlots(bag)
    return safe((CC and CC.GetContainerNumSlots) or GetContainerNumSlots, bag) or 0
end

-- link, count, icon, quality for one slot (nil if empty).
local function slotItem(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local info = safe(CC.GetContainerItemInfo, bag, slot)
        if info and info.hyperlink then return info.hyperlink, info.stackCount or 1, info.iconFileID, info.quality end
        return nil
    end
    local icon, count, _, quality, _, _, link = safe(GetContainerItemInfo, bag, slot)
    if link then return link, count or 1, icon, quality end
end

-- Read a list of containers into { [key] = count }. Returns counts, used, total slots.
local function readContainers(list)
    local counts, used, total = {}, 0, 0
    for _, bag in ipairs(list) do
        local n = numSlots(bag)
        total = total + n
        for slot = 1, n do
            local link, count, icon, quality = slotItem(bag, slot)
            if link then
                used = used + 1
                local key = rememberItem(link, icon, quality)
                if key then counts[key] = (counts[key] or 0) + count end
            end
        end
    end
    return counts, used, total
end

local function collectBags(c)
    local counts, used, total = readContainers(containers().bags)
    if total == 0 then return end -- not ready (login): keep what we had
    c.bags, c.bagSlots, c.bagsAt = counts, { used = used, total = total }, time()
end

local bankOpen, bankClosing = false, false

-- Only while the bank is open. An unreadable bank (no slots) never overwrites, and while
-- it is closing an all-empty read is not trusted either (the client may already have
-- dropped the contents).
local function collectBank(c)
    if not bankOpen then return end
    local counts, used, total = readContainers(containers().bank)
    if total == 0 or (bankClosing and used == 0) then return end
    c.bank, c.bankSlots, c.bankAt = counts, { used = used, total = total }, time()
end

-- Stats as the character sheet shows them at that moment (buffs included). Anything the
-- client does not offer is simply left out.
local function collectStats(c)
    -- Druid forms change stats a lot (bear armor): keep the caster-form values.
    if c.stats and select(2, UnitClass("player")) == "DRUID" and (safe(GetShapeshiftForm) or 0) > 0 then return end
    local s = {}
    for i, key in ipairs({ "str", "agi", "sta", "int", "spi" }) do
        local _, effective = safe(UnitStat, "player", i)
        s[key] = effective
    end
    local _, armor = safe(UnitArmor, "player")
    s.armor = armor
    s.health = safe(UnitHealthMax, "player")
    s.power = safe(UnitPowerMax, "player")
    local _, powerToken = safe(UnitPowerType, "player")
    s.powerType = powerToken
    local base, pos, neg = safe(UnitAttackPower, "player")
    if base then s.ap = base + (pos or 0) + (neg or 0) end
    base, pos, neg = safe(UnitRangedAttackPower, "player")
    if base then s.rap = base + (pos or 0) + (neg or 0) end
    s.crit = safe(GetCritChance)
    s.rcrit = safe(GetRangedCritChance)
    s.hit = safe(GetHitModifier)
    s.dodge = safe(GetDodgeChance)
    s.parry = safe(GetParryChance)
    s.block = safe(GetBlockChance)
    local def, defMod = safe(UnitDefense, "player")
    if def then s.defense = def + (defMod or 0) end
    -- Spell power and spell crit: the best school (holy .. arcane).
    for school = 2, 7 do
        local sp = safe(GetSpellBonusDamage, school)
        if sp and sp > (s.sp or -1) then s.sp = sp end
        local sc = safe(GetSpellCritChance, school)
        if sc and sc > (s.scrit or -1) then s.scrit = sc end
    end
    s.heal = safe(GetSpellBonusHealing)
    s.shit = safe(GetSpellHitModifier)
    s.res = {}
    for school = 2, 6 do -- fire, nature, frost, shadow, arcane
        local _, total = safe(UnitResistance, "player", school)
        s.res[school] = total
    end
    c.stats = s
    c.statsAt = time()
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
    stats = collectStats, bags = collectBags, bank = collectBank,
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
    if AB.CharSheet then AB.CharSheet.Refresh() end
end

function Data.Mark(...)
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        if part then dirty[part] = true end
    end
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
    Data.Mark("identity", "money", "gear", "zone", "profs", "currency", "reps", "stats", "bags")
    AB.Compat.After(5, function() Data.Mark("profs", "currency", "gear", "reps", "stats", "bags") end)
end)

-- Bags: once per burst of changes (BAG_UPDATE_DELAYED where it exists).
if not AB:RegisterEvent("BAG_UPDATE_DELAYED", function() Data.Mark("bags", bankOpen and "bank" or nil) end) then
    AB:RegisterEvent("BAG_UPDATE", function() Data.Mark("bags", bankOpen and "bank" or nil) end)
end

-- Bank: read when it opens and on every change while open; saved right away on close.
local function bankOpened()
    bankOpen = true
    Data.Mark("bank", "bags")
end
local function bankClosed()
    if not bankOpen then return end
    bankClosing = true
    Data.Flush() -- save changes made just before closing
    bankOpen, bankClosing = false, false
end
AB:RegisterEvent("BANKFRAME_OPENED", bankOpened)
AB:RegisterEvent("BANKFRAME_CLOSED", bankClosed)
-- Newer clients report the banker through the interaction manager.
local BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
if BANKER then
    AB:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind) if kind == BANKER then bankOpened() end end)
    AB:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind) if kind == BANKER then bankClosed() end end)
end
for _, event in ipairs({ "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED" }) do
    AB:RegisterEvent(event, function() if bankOpen then Data.Mark("bank") end end)
end

function Data.IsBankOpen() return bankOpen end

-- Stat events carry a unit: only the player's count.
for _, event in ipairs({ "UNIT_STATS", "UNIT_RESISTANCES", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER",
    "UNIT_MAXHEALTH", "UNIT_MAXPOWER", "UNIT_DEFENSE" }) do
    AB:RegisterEvent(event, function(_, unit) if unit == "player" then Data.Mark("stats") end end)
end
for _, event in ipairs({ "COMBAT_RATING_UPDATE", "SPELL_POWER_CHANGED", "PLAYER_DAMAGE_DONE_MODS" }) do
    AB:RegisterEvent(event, function() Data.Mark("stats") end)
end

-- Only while some equipped item was not loaded yet (this event fires for every item).
AB:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    if gearIncomplete then Data.Mark("gear") end
    if itemsIncomplete then Data.Mark("itemNames") end
end)

-- Fill in names of remembered items that were not loaded when they were first seen.
COLLECTORS.itemNames = function()
    itemsIncomplete = false
    for _, it in pairs(AB.db.items) do
        if it.pending then
            local name, _, q, _, _, _, _, _, _, tex = getItemInfo(it.l)
            if name then
                it.n, it.q, it.i, it.pending = name, q or it.q, tex or it.i, nil
            else
                itemsIncomplete = true
            end
        end
    end
end

local EVENTS = {
    PLAYER_MONEY = { "money" },
    PLAYER_LEVEL_UP = { "identity", "stats" },
    PLAYER_XP_UPDATE = { "identity" },
    UPDATE_EXHAUSTION = { "identity" },
    PLAYER_GUILD_UPDATE = { "identity" },
    PLAYER_EQUIPMENT_CHANGED = { "gear", "stats" },
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

-- Item search over every character's bags, bank and equipped items. query is matched
-- case-insensitively against item names. Returns a list sorted by name:
-- { key, name, q, icon, link, total, chars = { { guid, name, class, bags, bank, worn } } }
function Data.Search(query)
    query = strlower(strtrim(query or ""))
    if query == "" then return {} end
    local items = AB.db.items
    local byKey, list = {}, {}

    local function add(key, meta, guid, c, where, count)
        local name = meta and meta.n
        if not name or not strlower(name):find(query, 1, true) then return end
        local r = byKey[key]
        if not r then
            r = { key = key, name = name, q = meta.q, icon = meta.i, link = meta.l, total = 0, chars = {}, byGuid = {} }
            byKey[key] = r
            list[#list + 1] = r
        end
        local e = r.byGuid[guid]
        if not e then
            e = { guid = guid, name = c.name, class = c.class, bags = 0, bank = 0, worn = 0 }
            r.byGuid[guid] = e
            r.chars[#r.chars + 1] = e
        end
        e[where] = e[where] + count
        r.total = r.total + count
    end

    for guid, c in pairs(AB.db.chars) do
        if c.name then
            for key, count in pairs(c.bags or {}) do add(key, items[key], guid, c, "bags", count) end
            for key, count in pairs(c.bank or {}) do add(key, items[key], guid, c, "bank", count) end
            for _, it in pairs(c.gear or {}) do
                local key = Data.ItemKey(it.link)
                if key then
                    add(key, items[key] or { n = it.name, q = it.q, i = it.icon, l = it.link }, guid, c, "worn", 1)
                end
            end
        end
    end
    sort(list, function(a, b) return a.name < b.name end)
    for _, r in ipairs(list) do
        sort(r.chars, function(a, b) return (a.bags + a.bank + a.worn) > (b.bags + b.bank + b.worn) end)
        r.byGuid = nil
    end
    return list
end

function Data.TotalMoney(includeHidden)
    local total = 0
    for _, c in pairs(AB.db and AB.db.chars or {}) do
        if includeHidden or not c.hidden then total = total + (c.money or 0) end
    end
    return total
end
