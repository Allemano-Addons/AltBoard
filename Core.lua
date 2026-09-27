-- AltBoard: core namespace, event dispatcher, SavedVariables and slash command.
-- Standalone: never requires Hush.
local addonName, AB = ...

AB.name = addonName
AB.SCHEMA = 1

function AB:Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7ebAltBoard|r " .. msg)
end

-- ---------------------------------------------------------------------------
-- Errors: WoW Forever does not show Lua errors, so they are kept (last 10, also in
-- AltBoardDB.errors), announced once per session and listed by /ab errors.
-- ---------------------------------------------------------------------------

AB.errors = {}
local announced = false

function AB:RecordError(where, err)
    local list = self.errors
    list[#list + 1] = { t = time(), where = tostring(where), msg = tostring(err):sub(1, 400), v = self.version }
    while #list > 10 do tremove(list, 1) end
    if not announced then
        announced = true
        self:Print("|cffe8a33dhit an error|r (" .. tostring(where) .. "). /ab errors shows it.")
    end
    geterrorhandler()(err)
end

-- Run fn protected; errors are recorded instead of lost.
function AB:Call(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then self:RecordError(where, err) end
    return ok
end

-- ---------------------------------------------------------------------------
-- Game events: several handlers per event, one shared frame. Each handler runs
-- protected so one failing part never stops the others.
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- Returns false if the client does not know the event.
function AB:RegisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        list = {}
        eventHandlers[event] = list
    end
    list[#list + 1] = handler
    return true
end

function AB:UnregisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then tremove(list, i) end
    end
    if #list == 0 then
        eventHandlers[event] = nil
        eventFrame:UnregisterEvent(event)
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    -- In registration order, over a copy: a handler may unregister itself.
    local n = #list
    if n == 1 then
        local ok, err = pcall(list[1], event, ...)
        if not ok then AB:RecordError(event, err) end
        return
    end
    local snapshot = { unpack(list, 1, n) }
    for i = 1, n do
        local ok, err = pcall(snapshot[i], event, ...)
        if not ok then AB:RecordError(event, err) end
    end
end)

-- ---------------------------------------------------------------------------
-- SavedVariables: read at ADDON_LOADED, never at file load (WoW Forever quirk).
-- ---------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    font = "Friz Quadrata",
    textSize = "M",            -- S / M / L
    accentMode = "hush",       -- hush (follow Hush if installed) / class / custom
    accent = "3FC7EB",         -- used by "custom"
    bgAlpha = 0.96,
    scale = 1,
    colWidth = "normal",       -- narrow / normal / wide
    sections = { Overview = true, Professions = true, Currency = true, Reputation = true },
    totalIncludesHidden = true,
    launcher = true,
    collapsed = {},            -- board sections folded closed
    hiddenRows = {},           -- [section][rowId] = label
}

local function fillDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(dst[k]) == "table" and k ~= "collapsed" and k ~= "hiddenRows" then
            fillDefaults(dst[k], v)
        end
    end
end

-- Settings changes: listeners get (key, value). A failing listener never stops the others.
local settingListeners = {}
function AB:OnSettingChanged(fn) settingListeners[#settingListeners + 1] = fn end

function AB:SetSetting(key, value)
    self.db.settings[key] = value
    for _, fn in ipairs(settingListeners) do
        local ok, err = pcall(fn, key, value)
        if not ok then AB:RecordError("setting " .. tostring(key), err) end
    end
end

local function initDB()
    if type(AltBoardDB) ~= "table" then AltBoardDB = {} end
    local db = AltBoardDB
    db.schema = db.schema or AB.SCHEMA
    db.settings = db.settings or {}
    fillDefaults(db.settings, DEFAULT_SETTINGS)
    db.launcher = db.launcher or {}
    db.chars = db.chars or {} -- keyed by player GUID
    db.items = db.items or {} -- [itemKey] = { n = name, q = quality, i = icon, l = link }, see Data.ItemKey
    db.window = db.window or {}
    db.itemsWindow = db.itemsWindow or {}
    -- Errors from before the saved data was loaded are kept too.
    db.errors = db.errors or {}
    for _, e in ipairs(AB.errors) do tinsert(db.errors, e) end
    while #db.errors > 10 do tremove(db.errors, 1) end
    AB.errors = db.errors
    AB.db = db
end

AB:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= addonName then return end
    initDB()
    AB.version = AB.Compat.GetAddOnMetadata(addonName, "Version") or "?"
end)

AB:RegisterEvent("PLAYER_LOGIN", function()
    AB.guid = UnitGUID("player")
    AB.ready = true
end)

-- ---------------------------------------------------------------------------
-- Slash command: other files add subcommands with AB:AddSlashCommand.
-- ---------------------------------------------------------------------------

local slashCommands, slashOrder = {}, {}

function AB:AddSlashCommand(name, fn, help)
    if not slashCommands[name] then slashOrder[#slashOrder + 1] = name end
    slashCommands[name] = { fn = fn, help = help }
end

function AB:Toggle()
    -- Replaced once the board window exists.
    self:Print("The board is not ready yet.")
end

AB:AddSlashCommand("version", function() AB:Print("v" .. tostring(AB.version)) end, "show version")

AB:AddSlashCommand("errors", function(arg)
    if strlower(arg or "") == "clear" then
        wipe(AB.errors)
        AB:Print("Error list cleared.")
        return
    end
    if #AB.errors == 0 then AB:Print("No errors recorded.") return end
    for _, e in ipairs(AB.errors) do
        AB:Print(("[%s] %s (v%s): %s"):format(date("%d/%m %H:%M", e.t), e.where, tostring(e.v), e.msg))
    end
end, "show recent errors (/ab errors clear empties the list)")

SLASH_ALTBOARD1 = "/altboard"
SLASH_ALTBOARD2 = "/ab"
SlashCmdList.ALTBOARD = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")
    local c = slashCommands[cmd]
    if cmd == "" then
        AB:Toggle()
    elseif c then
        local ok, err = pcall(c.fn, rest)
        if not ok then AB:RecordError("/ab " .. cmd, err) end
    else
        AB:Print("/altboard - open/close")
        for _, name in ipairs(slashOrder) do
            AB:Print(("/altboard %s - %s"):format(name, slashCommands[name].help or ""))
        end
    end
end
