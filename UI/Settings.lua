-- Settings window: a label on the left, a control on the right, grouped in sections.
-- Every change is applied at once (AB:SetSetting); nothing needs a /reload.
local _, AB = ...

local Theme, W = AB.Theme, AB.Widgets
local S = Theme.size

local Settings = {}
AB.Settings = Settings

local WIDTH, ROW, LABEL_X, CONTROL_X = 440, 34, 16, 170
local frame
local controls = {} -- key -> control, for refreshing values when opened

local function set(key, value) AB:SetSetting(key, value) end

-- Layout helpers: y grows downward while building.
local y
local function heading(parent, text)
    y = y + 10
    local fs = W.Text(parent, -1, "text")
    fs:SetPoint("TOPLEFT", LABEL_X, -y)
    fs:SetText(strupper(text))
    W.OnAccent(function(r, g, b) fs:SetTextColor(r, g, b) end)
    y = y + 24
end

local function row(parent, label, control, offsetY)
    local fs = W.Text(parent, 0, "textDim")
    fs:SetPoint("TOPLEFT", LABEL_X, -(y + 7))
    fs:SetText(label)
    control:SetPoint("TOPLEFT", CONTROL_X, -(y + (offsetY or 3)))
    y = y + ROW
    return fs
end

local function toggleRow(parent, label, get, onChange)
    local t = W.Toggle(parent, onChange)
    row(parent, label, t, 7)
    t.refresh = function() t:Set(get()) end
    controls[#controls + 1] = t
    return t
end

local function textButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(24)
    b.bg = W.Fill(b, "field", 1)
    b.bg:SetAllPoints()
    W.Border(b, "line")
    b.text = W.Text(b, -1, "text")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetWidth(b.text:GetStringWidth() + 24)
    b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(Theme:Color("selected")) end)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(Theme:Color("field")) end)
    b:SetScript("OnClick", onClick)
    return b
end

local place

local function build()
    local s = AB.db.settings
    frame = CreateFrame("Frame", "AltBoardSettingsFrame", UIParent)
    tinsert(UISpecialFrames, "AltBoardSettingsFrame") -- ESC closes it
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetWidth(WIDTH)
    frame.bg = W.Fill(frame, "window", 0.98)
    frame.bg:SetAllPoints()
    W.Border(frame, "line")

    -- Title bar (drag to move).
    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(S.titleH)
    W.Line(title, "bottom", "line")
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() frame:StartMoving() end)
    title:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local name = W.Text(title, 3, "text")
    name:SetPoint("LEFT", S.padding, 0)
    name:SetText("AltBoard Settings")
    local close = W.CloseButton(title, function() frame:Hide() end)
    close:SetPoint("RIGHT", -8, 0)

    local body = frame
    y = S.titleH + 4

    -- Appearance -------------------------------------------------------------
    heading(body, "Appearance")

    local font = W.Dropdown(body, 220, function()
        local opts = {}
        for _, f in ipairs(Theme:AvailableFonts()) do opts[#opts + 1] = { value = f.name, label = f.name, font = f.path } end
        return opts
    end, function(v) set("font", v) end)
    row(body, "Font", font)
    font.refresh = function() font:Set(s.font) end
    controls[#controls + 1] = font

    local size = W.Segment(body, {
        { value = "S", label = "Small" }, { value = "M", label = "Medium" }, { value = "L", label = "Large" },
    }, function(v) set("textSize", v) end)
    row(body, "Text size", size, 5)
    size.refresh = function() size:Set(s.textSize) end
    controls[#controls + 1] = size

    local swatches = CreateFrame("Frame", nil, body)
    local accent = W.Segment(body, {
        { value = "hush", label = Theme.HasHush() and "Follow Hush" or "Default" },
        { value = "class", label = "Class" },
        { value = "custom", label = "Custom" },
    }, function(v)
        set("accentMode", v)
        swatches.refresh()
    end)
    row(body, "Accent color", accent, 5)
    accent.refresh = function() accent:Set(s.accentMode) end
    controls[#controls + 1] = accent

    -- Custom accent presets (only active with "Custom").
    swatches:SetSize(8 * 26, 22)
    swatches:SetPoint("TOPLEFT", CONTROL_X, -(y - 2))
    swatches.list = {}
    for i, hex in ipairs(Theme.ACCENTS) do
        local sw = W.Swatch(swatches, hex, function()
            s.accentMode = "custom"
            accent:Set("custom")
            set("accent", hex)
            swatches.refresh()
        end)
        sw:SetPoint("LEFT", (i - 1) * 26, 0)
        sw.hex = hex
        swatches.list[i] = sw
    end
    swatches.refresh = function()
        for _, sw in ipairs(swatches.list) do
            sw:SetSelected(s.accentMode == "custom" and s.accent == sw.hex)
            sw:SetAlpha(s.accentMode == "custom" and 1 or 0.4)
        end
    end
    controls[#controls + 1] = swatches
    y = y + ROW - 6

    local alpha = W.Slider(body, 50, 100, 5, 170, function(v) return v .. "%" end,
        function(v) set("bgAlpha", v / 100) end)
    row(body, "Background", alpha, 9)
    alpha.refresh = function() alpha:Set(floor((s.bgAlpha or 0.96) * 100 + 0.5)) end
    controls[#controls + 1] = alpha

    local scale = W.Slider(body, 70, 130, 5, 170, function(v) return v .. "%" end,
        function(v) set("scale", v / 100) end)
    row(body, "Window scale", scale, 9)
    scale.refresh = function() scale:Set(floor((s.scale or 1) * 100 + 0.5)) end
    controls[#controls + 1] = scale

    local cols = W.Segment(body, {
        { value = "narrow", label = "Narrow" }, { value = "normal", label = "Normal" }, { value = "wide", label = "Wide" },
    }, function(v) set("colWidth", v) end)
    row(body, "Column width", cols, 5)
    cols.refresh = function() cols:Set(s.colWidth) end
    controls[#controls + 1] = cols

    -- Board --------------------------------------------------------------------
    heading(body, "Board")
    for _, key in ipairs({ "Overview", "Professions", "Currency", "Reputation" }) do
        toggleRow(body, "Show " .. key, function() return s.sections[key] end, function(on)
            s.sections[key] = on
            set("sections", s.sections)
        end)
    end
    toggleRow(body, "Hidden chars in total", function() return s.totalIncludesHidden end,
        function(on) set("totalIncludesHidden", on) end)

    -- Launcher -----------------------------------------------------------------
    heading(body, "Launcher button")
    toggleRow(body, "Show button", function() return s.launcher end, function(on) set("launcher", on) end)
    toggleRow(body, "Lock position", function() return AB.db.launcher.locked == true end,
        function(on) AB.db.launcher.locked = on or nil end)

    local reset = textButton(body, "Reset window positions", function()
        AB.Board.ResetPosition()
        AB.Launcher.ResetPosition()
        place()
        AB:Print("Window and launcher positions reset.")
    end)
    reset:SetPoint("TOPLEFT", LABEL_X, -(y + 8))
    y = y + 44

    frame:SetHeight(y)
    frame:SetScript("OnHide", function()
        W.HideTooltip()
        W.CloseMenus()
    end)
    frame:Hide()
end

function place()
    frame:ClearAllPoints()
    local board = AB.Board.Frame()
    if board and board:IsShown() and board:GetRight() and
        (board:GetRight() * board:GetEffectiveScale() + WIDTH * frame:GetEffectiveScale()) < UIParent:GetRight() * UIParent:GetEffectiveScale() then
        frame:SetPoint("TOPLEFT", board, "TOPRIGHT", 8, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

function Settings.Toggle()
    if not AB.db then return end
    if not frame then
        -- A failed build must not leave a half-made (invisible) window behind.
        local ok, err = pcall(build)
        if not ok then
            if frame then frame:Hide() end
            frame = nil
            wipe(controls)
            AB:RecordError("settings build", err)
            return
        end
    end
    if frame:IsShown() then frame:Hide() return end
    for _, c in ipairs(controls) do c.refresh() end
    place()
    frame:Show()
end

AB:AddSlashCommand("settings", function() Settings.Toggle() end, "open the settings")
