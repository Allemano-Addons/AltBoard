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

print(#errors == 0 and "ALL OK" or (#errors .. " error(s)"))
os.exit(#errors == 0 and 0 or 1)
