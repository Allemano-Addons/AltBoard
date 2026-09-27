-- Smoke test outside the game: loads every TOC file against a fake WoW API, fires the
-- login events, opens the board and the settings and clicks around. Catches Lua errors
-- that WoW Forever would swallow silently. Run from the addon folder: lua Tests/smoke_test.lua
local unpack = table.unpack or unpack
_G.unpack = unpack

-- Generic fake widget: known getters return sensible values, everything else is a no-op.
local GETTERS = {
    GetStringWidth = 50, GetStringHeight = 12, GetEffectiveScale = 1, GetWidth = 1920, GetHeight = 1080,
    GetLeft = 100, GetTop = 800, GetRight = 400, GetBottom = 100, GetFrameLevel = 1, IsShown = false,
    IsEnabled = true, IsVisible = true, GetText = "",
}
local scripts = setmetatable({}, { __mode = "k" })
local function mock(kind)
    local o = { _kind = kind, _shown = kind ~= "Frame" and true or true }
    return setmetatable(o, { __index = function(t, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end -- fields: nil, like real frames
        if k == "SetScript" then return function(self, name, fn) scripts[self] = scripts[self] or {}; scripts[self][name] = fn end end
        if k == "HookScript" then return function() end end
        if k == "GetScript" then return function(self, name) return scripts[self] and scripts[self][name] end end
        if k == "Show" then return function(self) self._shown = true; local f = scripts[self] and scripts[self].OnShow; if f then f(self) end end end
        if k == "Hide" then return function(self) local was = self._shown; self._shown = false; local f = was and scripts[self] and scripts[self].OnHide; if f then f(self) end end end
        if k == "SetShown" then return function(self, v) if v then self:Show() else self:Hide() end end end
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "SetColorTexture" or k == "SetTextColor" or k == "SetVertexColor" then
            return function(_, r, g, b, a)
                for i, v in ipairs({ r, g, b }) do assert(type(v) == "number", k .. ": component " .. i .. " is " .. type(v)) end
                assert(a == nil or type(a) == "number", k .. ": alpha is " .. type(a))
            end
        end
        if k == "SetFont" then return function() return true end end
        if k == "GetFont" then return function() return "Fonts\\FRIZQT__.TTF", 12 end end
        if k == "CreateTexture" or k == "CreateFontString" or k == "CreateLine" then return function() return mock(k) end end
        if GETTERS[k] ~= nil then local v = GETTERS[k]; return function() return v end end
        return function() end
    end })
end

-- WoW globals used by AltBoard.
CreateFrame = function(kind, name) local f = mock(kind); f._shown = true; if name then _G[name] = f end; return f end
UIParent = mock("Frame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("[chat] " .. m) end }
UISpecialFrames = {}
SlashCmdList = {}
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
tostringall = function(...) local t = { ... } for i = 1, select("#", ...) do t[i] = tostring(t[i]) end return unpack(t, 1, select("#", ...)) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, strupper, tinsert, tremove, sort, floor, ceil, min, max, format = string.lower, string.upper, table.insert, table.remove, table.sort, math.floor, math.ceil, math.min, math.max, string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
date, time = os.date, os.time
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
local errors = {}
geterrorhandler = function() return function(e) errors[#errors + 1] = e; print("ERROR: " .. tostring(e)) end end
C_Timer = { After = function(_, fn) fn() end }
C_AddOns = { GetAddOnMetadata = function() return "test" end }
GetBuildInfo = function() return "1.60.1", "70009", "Sep 23 2026", 16001 end
GetPhysicalScreenSize = function() return 2560, 1440 end
GetCursorPosition = function() return 500, 500 end
IsShiftKeyDown = function() return false end
UnitGUID = function() return "Player-1-A" end
UnitName = function() return "Allemano", "Moo" end
UnitClass = function() return "Druid", "DRUID", 11 end
UnitRace = function() return "Tauren" end
UnitFactionGroup = function() return "Horde" end
UnitLevel = function() return 20 end
UnitXP, UnitXPMax = function() return 100 end, function() return 1000 end
GetXPExhaustion = function() return 500 end
GetMoney = function() return 51234 end
GetAverageItemLevel = function() return 16.7, 16.7 end
GetRealZoneText = function() return "The Barrens" end
GetNormalizedRealmName = function() return "ClassicBetaPvP2" end
GetRealmName = GetNormalizedRealmName
IsInGuild = function() return true end
GetGuildInfo = function() return "Slakthuset" end
GetProfessions = function() return 6, 8, nil, 7, nil end
GetProfessionInfo = function(i) return "Prof" .. i, 136246, 50, 75, 0, 0, i end
C_CurrencyInfo = { GetCurrencyListSize = function() return 2 end, GetCurrencyListInfo = function(i)
    if i == 1 then return { isHeader = true, name = "PvP" } end
    return { name = "Honor Points", quantity = 12, maxQuantity = 15000, iconFileID = 1 } end }
C_Reputation = { GetNumFactions = function() return 2 end, GetFactionDataByIndex = function(i)
    if i == 1 then return { name = "Horde", isHeader = true, isChild = false, factionID = 67 } end
    return { name = "Orgrimmar", factionID = 76, reaction = 5, currentStanding = 4320, currentReactionThreshold = 3000, nextReactionThreshold = 9000 } end,
    GetFactionDataByID = function() return nil end }
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 } }
LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druid" }
FACTION_BAR_COLORS = { [5] = { r = 0, g = 0.6, b = 0.1 } }
BreakUpLargeNumbers = function(n) return tostring(n) end
HushDB = { settings = { accent = "C8332E" } }
-- Gear and stats. Slot 5 (chest) is "not loaded yet" the first time, like a fresh login.
local chestLoaded = false
GetInventoryItemLink = function(_, slot)
    if slot == 1 or slot == 5 or slot == 16 then return "|cff1eff00|Hitem:" .. (100 + slot) .. "::::|h[Item " .. slot .. "]|h|r" end
end
GetInventoryItemTexture = function() return 134400 end
C_Item = {
    GetItemInfo = function(link)
        local id = tonumber(link:match("item:(%d+)"))
        if id == 105 and not chestLoaded then return nil end
        return "Item " .. (id - 100), link, 2, 20, 18, "Armor", "Cloth", 1, "INVTYPE_CHEST", 134400
    end,
    GetDetailedItemLevelInfo = function() return 21 end,
}
ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 } }
UnitStat = function(_, i) return 20, 20 + i, 0, 0 end
UnitArmor = function() return 300, 350 end
UnitHealthMax, UnitPowerMax = function() return 400 end, function() return 500 end
UnitPowerType = function() return 0, "MANA" end
UnitAttackPower = function() return 60, 10, 0 end
GetCritChance = function() return 5.123 end
GetSpellBonusDamage = function(school) return school == 3 and 12 or 0 end
UnitResistance = function(_, school) return 0, school * 5 end
GetShapeshiftForm = function() return 0 end
local tooltipLink
GameTooltip = setmetatable({ SetHyperlink = function(_, link) tooltipLink = link end }, { __index = function() return function() end end })
local modifiedClick
HandleModifiedItemClick = function(link) modifiedClick = link end

-- Load the TOC files in order with the shared addon table.
local AB = {}
for line in io.lines("AltBoard.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") then
        local chunk = assert(loadfile((line:gsub("\\", "/"))))
        chunk("AltBoard", AB)
    end
end

-- Fire events through the addon's own dispatcher frame: find it via RegisterEvent's frame.
local function fire(event, ...)
    -- Core registers on a frame whose OnEvent we can reach through scripts.
    for f, s in pairs(scripts) do if s.OnEvent then s.OnEvent(f, event, ...) end end
end

local function step(name, fn)
    local ok, err = pcall(fn)
    print((ok and "ok   " or "FAIL ") .. name .. (ok and "" or (": " .. tostring(err))))
    if not ok then errors[#errors + 1] = err end
end

step("ADDON_LOADED", function() fire("ADDON_LOADED", "AltBoard") end)
step("PLAYER_LOGIN", function() fire("PLAYER_LOGIN") end)
step("open board", function() SlashCmdList.ALTBOARD("") end)
step("open settings", function() SlashCmdList.ALTBOARD("settings") end)
local settingsFrame = _G.AltBoardSettingsFrame
step("settings visible", function() assert(settingsFrame and settingsFrame._shown, "settings frame not shown") end)
for _, kv in ipairs({ { "font", "Arial Narrow" }, { "textSize", "L" }, { "accentMode", "custom" }, { "accent", "3FC77F" },
    { "bgAlpha", 0.7 }, { "scale", 1.2 }, { "colWidth", "wide" }, { "totalIncludesHidden", false }, { "launcher", false } }) do
    step("set " .. kv[1], function() AB:SetSetting(kv[1], kv[2]) end)
end
step("hide section", function() AB.db.settings.sections.Currency = false; AB:SetSetting("sections", AB.db.settings.sections) end)
step("character menu", function() AB.Board.CharacterMenu({ guid = "Player-1-A" }) end)
step("close settings", function() AB.Settings.Toggle() end)
step("reopen settings", function() AB.Settings.Toggle() end)
step("slash errors", function() SlashCmdList.ALTBOARD("errors") end)

-- Hidden rows: right-click rows through their real OnMouseUp and pick menu items.
local function visibleRows(pred)
    local out = {}
    for f, s in pairs(scripts) do
        if s.OnMouseUp and f._shown and pred(f) then out[#out + 1] = f end
    end
    return out
end
local function rightClickAndPick(row, pick)
    local realOpen = AB.Widgets.OpenMenu
    local picked
    AB.Widgets.OpenMenu = function(items) picked = items[pick] end
    scripts[row].OnMouseUp(row, "RightButton")
    AB.Widgets.OpenMenu = realOpen
    assert(picked and picked.onClick, "menu item " .. pick .. " missing")
    picked.onClick()
end
step("hide a reputation row", function()
    AB.Board.Refresh()
    local rows = visibleRows(function(f) return f.section == "Reputation" and f.rowId == 76 end)
    assert(#rows == 1, "Orgrimmar row not found (" .. #rows .. ")")
    rightClickAndPick(rows[1], 2)
    assert(AB.db.settings.hiddenRows.Reputation[76] == "Orgrimmar", "not hidden")
    assert(#visibleRows(function(f) return f.section == "Reputation" and f.rowId == 76 end) == 0, "still shown")
    assert(#visibleRows(function(f) return f.section == "Reputation" and f.groupIds end) == 0, "empty group heading still shown")
end)
step("section menu: show all", function()
    local heads = visibleRows(function(f) return f.toggle == "Reputation" end)
    assert(#heads == 1, "heading not found")
    rightClickAndPick(heads[1], 2)
    assert(next(AB.db.settings.hiddenRows.Reputation) == nil, "not unhidden")
end)
step("hide a whole group", function()
    local groups = visibleRows(function(f) return f.section == "Reputation" and f.groupIds end)
    assert(#groups == 1, "group heading not found (" .. #groups .. ")")
    rightClickAndPick(groups[1], 2)
    assert(AB.db.settings.hiddenRows.Reputation[76], "group not hidden")
end)
step("hide an overview row", function()
    local rows = visibleRows(function(f) return f.section == "Overview" and f.rowId == "Location" end)
    assert(#rows == 1, "Location row not found")
    rightClickAndPick(rows[1], 2)
    assert(AB.db.settings.hiddenRows.Overview.Location, "not hidden")
end)

-- Character sheet.
step("gear and stats saved", function()
    local c = AB.db.chars["Player-1-A"]
    assert(c.gear and c.gear[1] and c.gear[1].name == "Item 1" and c.gear[1].ilvl == 21, "gear slot 1 wrong")
    assert(c.gear[5] and c.gear[5].name == nil, "chest should wait for item info")
    chestLoaded = true
    fire("GET_ITEM_INFO_RECEIVED", 105)
    assert(c.gear[5].name == "Item 5", "chest not filled in after GET_ITEM_INFO_RECEIVED")
    assert(c.stats and c.stats.str == 21 and c.stats.armor == 350 and c.stats.ap == 70, "stats wrong")
    assert(c.stats.sp == 12 and c.stats.res[6] == 30 and c.stats.powerType == "MANA", "spell/res stats wrong")
end)
step("druid in bear form keeps caster stats", function()
    local c = AB.db.chars["Player-1-A"]
    GetShapeshiftForm = function() return 1 end
    UnitArmor = function() return 300, 2000 end
    fire("UNIT_STATS", "player")
    assert(c.stats.armor == 350, "bear armor was saved")
    GetShapeshiftForm = function() return 0 end
    UnitArmor = function() return 300, 350 end
end)
step("click name opens the sheet", function()
    local heads = {}
    for f, s in pairs(scripts) do
        if s.OnClick and f._shown and rawget(f, "guid") == "Player-1-A" and rawget(f, "onLeftClick") then heads[#heads + 1] = f end
    end
    assert(#heads == 1, "name cell not found (" .. #heads .. ")")
    scripts[heads[1]].OnClick(heads[1], "LeftButton")
    local sheet = _G.AltBoardCharFrame
    assert(sheet and sheet._shown, "sheet not shown")
    assert(AB.CharSheet.ShownGuid() == "Player-1-A", "wrong character")
    -- Hover and shift-click an item.
    local slot
    for f, s in pairs(scripts) do if rawget(f, "slotId") == 1 then slot = f end end
    assert(slot and slot.link, "head slot has no link")
    scripts[slot].OnEnter(slot)
    assert(tooltipLink == slot.link, "tooltip not shown")
    scripts[slot].OnClick(slot, "LeftButton")
    assert(modifiedClick == slot.link, "modified click not passed on")
    -- Same name again closes it.
    scripts[heads[1]].OnClick(heads[1], "LeftButton")
    assert(not sheet._shown, "sheet did not close")
end)
step("closing the board closes the sheet", function()
    AB.CharSheet.Toggle("Player-1-A")
    assert(_G.AltBoardCharFrame._shown, "sheet not reopened")
    _G.AltBoardFrame:Hide()
    assert(not _G.AltBoardCharFrame._shown, "sheet still open")
end)

print(#errors == 0 and "ALL OK" or (#errors .. " error(s)"))
os.exit(#errors == 0 and 0 or 1)
