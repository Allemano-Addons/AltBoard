-- Launcher: a small movable button (own, no LibDBIcon), same style as Hush's.
-- Left-click opens the board, right-click opens a menu, drag moves it.
local _, AB = ...

local Theme, W = AB.Theme, AB.Widgets

local Launcher = {}
AB.Launcher = Launcher

local SIZE = 30
local button

local function db() return AB.db.launcher end

local function savePosition()
    local d = db()
    d.left = Theme:Snap(button:GetLeft(), button)
    d.top = Theme:Snap(button:GetTop(), button)
end

local function restorePosition()
    local d = db()
    button:ClearAllPoints()
    if d.left and d.top then
        button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left, d.top)
    else
        -- Top center, a bit right of where Hush puts its button.
        button:SetPoint("TOP", UIParent, "TOP", 40, -8)
    end
end

function Launcher.ResetPosition()
    db().left, db().top = nil, nil
    if button then restorePosition() end
end

local function openMenu()
    local board = AB.Board.Frame()
    W.OpenMenu({
        { text = "AltBoard", title = true },
        { text = board and board:IsShown() and "Close board" or "Open board", onClick = function() AB.Board.Toggle() end },
        { text = "Search items", onClick = function() AB.Items.Toggle() end },
        { text = "Settings", onClick = function() AB.Settings.Toggle() end },
        { text = "Lock position", checked = db().locked == true, onClick = function() db().locked = not db().locked or nil end },
        { text = "Hide button", onClick = function()
            AB:SetSetting("launcher", false)
            AB:Print("Launcher hidden. Turn it back on in /ab settings")
        end },
    })
end

local function build()
    button = CreateFrame("Button", nil, UIParent)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("HIGH")
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    button.bg = W.Fill(button, "sidebar", 0.95)
    button.bg:SetAllPoints()
    local border = W.Border(button, "line")
    W.Panel(button, button.bg, border, Theme.radius.control)
    local function setBorder(r, g, b) border:SetColor(r, g, b, 1) end

    -- Icon: the AltBoard logo; if the texture does not load, three accent-colored columns.
    local logo = button:CreateTexture(nil, "ARTWORK")
    logo:SetPoint("TOPLEFT", 2, -2)
    logo:SetPoint("BOTTOMRIGHT", -2, 2)
    if logo:SetTexture(AB.LOGO) == false then
        logo:Hide()
        local bars = {}
        for i, h in ipairs({ 8, 13, 10 }) do
            local t = button:CreateTexture(nil, "ARTWORK")
            t:SetSize(4, h)
            t:SetPoint("BOTTOMLEFT", 7 + (i - 1) * 6, 8)
            bars[i] = t
        end
        W.OnAccent(function(r, g, b)
            for _, t in ipairs(bars) do t:SetColorTexture(r, g, b, 1) end
        end)
    end

    button:SetScript("OnEnter", function(self)
        setBorder(Theme:Accent())
        W.ShowTooltip(self, { "AltBoard", "|cff7c858fLeft-click: open  -  Right-click: menu  -  Drag: move|r" })
    end)
    button:SetScript("OnLeave", function()
        setBorder(Theme:Color("line"))
        W.HideTooltip()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        AB:Call("launcher", mouseButton == "RightButton" and openMenu or AB.Board.Toggle)
    end)
    button:SetScript("OnDragStart", function(self)
        if db().locked then return end
        W.HideTooltip()
        self:StartMoving()
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
        restorePosition()
    end)

    restorePosition()
end

function Launcher.Update()
    local on = AB.db.settings.launcher
    if on and not button then build() end
    if button then button:SetShown(on and true or false) end
end

AB:RegisterEvent("PLAYER_LOGIN", function() Launcher.Update() end)
AB:OnSettingChanged(function(key)
    if key == "launcher" then Launcher.Update() end
end)
