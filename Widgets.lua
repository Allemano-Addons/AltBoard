-- Widgets: a trimmed copy of Hush's flat building blocks (no Blizzard textures).
local _, AB = ...

local Theme = AB.Theme

local W = {}
AB.Widgets = W

-- Pixel-sized textures, re-sized when the UI scale changes.
local pixelItems = {}

local function applyPixel(item)
    local px = Theme:Pixel(item.frame)
    if item.axis == "h" then item.tex:SetHeight(px * item.n) else item.tex:SetWidth(px * item.n) end
end

function W.PixelSize(tex, frame, axis, n)
    local item = { tex = tex, frame = frame, axis = axis, n = n or 1 }
    pixelItems[#pixelItems + 1] = item
    applyPixel(item)
end

local function refreshPixels()
    for i = 1, #pixelItems do applyPixel(pixelItems[i]) end
end
AB:RegisterEvent("UI_SCALE_CHANGED", refreshPixels)
AB:RegisterEvent("DISPLAY_SIZE_CHANGED", refreshPixels)

function W.Fill(frame, colorKey, alpha, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    local r, g, b = Theme:Color(colorKey)
    t:SetColorTexture(r, g, b, alpha or 1)
    return t
end

-- A 1 px line along one side of frame.
function W.Line(frame, side, colorKey, layer)
    local t = W.Fill(frame, colorKey or "line", 1, layer or "BORDER")
    if side == "top" or side == "bottom" then
        local p = side == "top" and "TOP" or "BOTTOM"
        t:SetPoint(p .. "LEFT")
        t:SetPoint(p .. "RIGHT")
        W.PixelSize(t, frame, "h")
    else
        local p = side == "left" and "LEFT" or "RIGHT"
        t:SetPoint("TOP" .. p)
        t:SetPoint("BOTTOM" .. p)
        W.PixelSize(t, frame, "w")
    end
    return t
end

function W.Border(frame, colorKey)
    local b = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do b[side] = W.Line(frame, side, colorKey) end
    return b
end

function W.Text(parent, delta, colorKey, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    Theme:SetFont(fs, delta)
    fs:SetTextColor(Theme:Color(colorKey or "text"))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Own flat tooltip. lines = string or { "line", "line", ... }.
local tip
function W.ShowTooltip(owner, lines)
    if not tip then
        tip = CreateFrame("Frame", nil, UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetClampedToScreen(true)
        tip.bg = W.Fill(tip, "field", 0.98)
        tip.bg:SetAllPoints()
        W.Border(tip, "line")
        tip.text = W.Text(tip, -1, "text")
        tip.text:SetWordWrap(true)
        tip.text:SetSpacing(3)
        tip.text:SetPoint("TOPLEFT", 8, -6)
    end
    tip.text:SetText(type(lines) == "table" and table.concat(lines, "\n") or lines)
    tip.text:SetWidth(0)
    local w = min(tip.text:GetStringWidth() + 2, 320)
    tip.text:SetWidth(w)
    tip:SetSize(w + 16, tip.text:GetStringHeight() + 12)
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    tip:Show()
end

function W.HideTooltip()
    if tip then tip:Hide() end
end

-- Small square button with an "x" (text glyph: Friz Quadrata lacks fancy symbols).
function W.CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b.bg = W.Fill(b, "selected", 1)
    b.bg:SetAllPoints()
    b.bg:Hide()
    b.text = W.Text(b, 1, "textDim")
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText("x")
    b:SetScript("OnEnter", function(self)
        self.bg:Show()
        self.text:SetTextColor(Theme:Color("text"))
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:Hide()
        self.text:SetTextColor(Theme:Color("textDim"))
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- ---------------------------------------------------------------------------
-- Context menu and confirm dialog. A full-screen invisible catcher closes them on any
-- click outside.
-- ---------------------------------------------------------------------------

local catcher, menu, dialog

local function closeAll()
    if menu then menu:Hide() end
    if dialog then dialog:Hide() end
    if catcher then catcher:Hide() end
end
W.CloseMenus = closeAll

local function getCatcher()
    if not catcher then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", closeAll)
    end
    catcher:Show()
    return catcher
end

local function panel()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(getCatcher():GetFrameLevel() + 10)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f.bg = W.Fill(f, "field", 0.98)
    f.bg:SetAllPoints()
    W.Border(f, "line")
    return f
end

local function menuButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.bg = W.Fill(b, "selected", 1)
    b.bg:SetAllPoints()
    b.bg:Hide()
    b.text = W.Text(b, 0, "text")
    b.text:SetPoint("LEFT", 10, 0)
    b:SetScript("OnEnter", function(self) if self:IsEnabled() then self.bg:Show() end end)
    b:SetScript("OnLeave", function(self) self.bg:Hide() end)
    return b
end

-- items = { { text, onClick, disabled, danger, title } }. Title items are faint headings.
function W.OpenMenu(items, anchor)
    closeAll()
    getCatcher()
    if not menu then
        menu = panel()
        menu.buttons = {}
    end
    menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
    local width = 120
    for i, item in ipairs(items) do
        local b = menu.buttons[i] or menuButton(menu)
        menu.buttons[i] = b
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 1, -4 - (i - 1) * 22)
        b:SetPoint("RIGHT", -1, 0)
        b.text:SetText(item.text)
        local key = item.title and "textFaint" or item.disabled and "textFaint" or item.danger and "warn" or "text"
        b.text:SetTextColor(Theme:Color(key))
        b:SetEnabled(not item.disabled and not item.title)
        b:SetScript("OnClick", function()
            closeAll()
            if item.onClick then item.onClick() end
        end)
        b:Show()
        width = max(width, b.text:GetStringWidth() + 30)
    end
    for i = #items + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:SetSize(width, #items * 22 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

-- Yes/No box in the middle of the screen.
function W.Confirm(text, yesLabel, onYes)
    closeAll()
    getCatcher()
    if not dialog then
        dialog = panel()
        dialog:SetSize(300, 110)
        dialog.text = W.Text(dialog, 0, "text")
        dialog.text:SetWordWrap(true)
        dialog.text:SetJustifyH("CENTER")
        dialog.text:SetPoint("TOPLEFT", 16, -18)
        dialog.text:SetPoint("TOPRIGHT", -16, -18)
        local function button(label, colorKey)
            local b = CreateFrame("Button", nil, dialog)
            b:SetSize(110, 26)
            b.bg = W.Fill(b, colorKey, 1)
            b.bg:SetAllPoints()
            W.Border(b, "line")
            b.text = W.Text(b, 0, "text")
            b.text:SetPoint("CENTER")
            b.text:SetText(label)
            b:SetScript("OnEnter", function(self) self.bg:SetAlpha(0.8) end)
            b:SetScript("OnLeave", function(self) self.bg:SetAlpha(1) end)
            return b
        end
        dialog.yes = button("", "selected")
        dialog.yes:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -4, 14)
        dialog.yes.text:SetTextColor(Theme:Color("warn"))
        dialog.no = button("Cancel", "field")
        dialog.no:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 4, 14)
        dialog.no:SetScript("OnClick", closeAll)
    end
    dialog:SetFrameLevel(catcher:GetFrameLevel() + 10)
    dialog.text:SetText(text)
    dialog.yes.text:SetText(yesLabel or "Yes")
    dialog.yes:SetScript("OnClick", function()
        closeAll()
        onYes()
    end)
    dialog:ClearAllPoints()
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    dialog:Show()
end

-- Reused frames.
function W.Pool(create, reset)
    local pool = { free = {}, active = {} }
    function pool:Acquire()
        local obj = tremove(self.free) or create()
        self.active[#self.active + 1] = obj
        obj:Show()
        return obj
    end
    function pool:ReleaseAll()
        for i = #self.active, 1, -1 do
            local obj = self.active[i]
            obj:Hide()
            obj:ClearAllPoints()
            if reset then reset(obj) end
            self.free[#self.free + 1] = obj
            self.active[i] = nil
        end
    end
    return pool
end
