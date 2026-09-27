-- Character sheet: a saved character's equipped items and stats, opened by clicking a
-- name on the board. Built once; Refresh only fills in values.
local _, AB = ...

local Theme, W = AB.Theme, AB.Widgets

local Sheet = {}
AB.CharSheet = Sheet

local WIDTH, HEADER_H, SLOT_H, COL_W, PAD = 520, 70, 36, 246, 12
local STAT_H = 17

local frame, shownGuid

local SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist",
    [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Finger",
    [13] = "Trinket", [14] = "Trinket", [15] = "Back", [16] = "Main Hand", [17] = "Off Hand",
    [18] = "Ranged", [19] = "Tabard",
}
-- Same order as Blizzard's character sheet: left column, right column, weapons.
local LEFT = { 1, 2, 3, 15, 5, 4, 19, 9, 16, 18 }
local RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14, 17 }

local POWER_NAMES = { MANA = "Mana", RAGE = "Rage", ENERGY = "Energy", FOCUS = "Focus" }

local function num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end
local function pct(v) return v and ("%.2f%%"):format(v) or nil end
local function int(v) return v and num(floor(v + 0.5)) or nil end

-- Stat columns: { heading, { { label, get(stats) }, ... } }.
local STAT_COLUMNS = {
    { "Attributes", {
        { "Health", function(s) return int(s.health) end },
        { "Power", function(s) return int(s.power) end, function(s) return POWER_NAMES[s.powerType or ""] end },
        { "Strength", function(s) return int(s.str) end },
        { "Agility", function(s) return int(s.agi) end },
        { "Stamina", function(s) return int(s.sta) end },
        { "Intellect", function(s) return int(s.int) end },
        { "Spirit", function(s) return int(s.spi) end },
        { "Armor", function(s) return int(s.armor) end },
    } },
    { "Melee & ranged", {
        { "Attack power", function(s) return int(s.ap) end },
        { "Ranged AP", function(s) return int(s.rap) end },
        { "Crit", function(s) return pct(s.crit) end },
        { "Ranged crit", function(s) return pct(s.rcrit) end },
        { "Hit", function(s) return s.hit and (s.hit .. "%") end },
        { "Dodge", function(s) return pct(s.dodge) end },
        { "Parry", function(s) return pct(s.parry) end },
        { "Block", function(s) return pct(s.block) end },
        { "Defense", function(s) return int(s.defense) end },
    } },
    { "Spell", {
        { "Spell power", function(s) return int(s.sp) end },
        { "Healing", function(s) return int(s.heal) end },
        { "Spell crit", function(s) return pct(s.scrit) end },
        { "Spell hit", function(s) return s.shit and (s.shit .. "%") end },
        { "Fire res.", function(s) return s.res and int(s.res[2]) end },
        { "Nature res.", function(s) return s.res and int(s.res[3]) end },
        { "Frost res.", function(s) return s.res and int(s.res[4]) end },
        { "Shadow res.", function(s) return s.res and int(s.res[5]) end },
        { "Arcane res.", function(s) return s.res and int(s.res[6]) end },
    } },
}

local function qualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return Theme:Color("text")
end

local function ago(t)
    if not t then return "unknown" end
    local d = time() - t
    if d < 3600 then return max(1, floor(d / 60)) .. " min ago" end
    if d < 86400 then return floor(d / 3600) .. " h ago" end
    return floor(d / 86400) .. " d ago"
end

-- ---------------------------------------------------------------------------
-- Item slot
-- ---------------------------------------------------------------------------

local function createSlot(parent, slotId)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(COL_W, SLOT_H - 4)
    b.slotId = slotId
    b.hl = W.Fill(b, "selected", 1)
    b.hl:SetAllPoints()
    b.hl:Hide()
    b.iconBox = CreateFrame("Frame", nil, b)
    b.iconBox:SetSize(30, 30)
    b.iconBox:SetPoint("LEFT", 0, 0)
    b.iconBg = W.Fill(b.iconBox, "field", 1)
    b.iconBg:SetAllPoints()
    b.ring = W.Border(b.iconBox, "line")
    b.icon = b.iconBox:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.name = W.Text(b, 0, "text")
    b.name:SetPoint("TOPLEFT", b.iconBox, "TOPRIGHT", 8, -2)
    b.name:SetPoint("RIGHT", -4, 0)
    b.sub = W.Text(b, -2, "textFaint")
    b.sub:SetPoint("BOTTOMLEFT", b.iconBox, "BOTTOMRIGHT", 8, 2)
    b.sub:SetPoint("RIGHT", -4, 0)

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        self.hl:Show()
        if self.link and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
            if ok then GameTooltip:Show() else GameTooltip:Hide() end
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hl:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)
    -- Shift-click links it in chat, ctrl-click previews it (the game's own handling).
    b:SetScript("OnClick", function(self)
        if not self.link then return end
        if HandleModifiedItemClick then
            HandleModifiedItemClick(self.link)
        elseif IsShiftKeyDown() and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.link)
        end
    end)
    return b
end

local function fillSlot(b, item)
    b.link = item and item.link
    local slotName = SLOT_NAMES[b.slotId]
    if not item then
        b.icon:SetTexture(nil)
        b.name:SetText(slotName)
        b.name:SetTextColor(Theme:Color("textFaint"))
        b.sub:SetText("Empty")
        local r, g, bl = Theme:Color("line")
        for _, side in pairs(b.ring) do side:SetColorTexture(r, g, bl, 1) end
        return
    end
    b.icon:SetTexture(item.icon)
    b.name:SetText(item.name or (item.link and item.link:match("%[(.-)%]")) or "?")
    local r, g, bl = qualityColor(item.q)
    b.name:SetTextColor(r, g, bl)
    for _, side in pairs(b.ring) do side:SetColorTexture(r, g, bl, item.q and item.q >= 2 and 1 or 0.35) end
    b.sub:SetText(item.ilvl and ("%s  -  item level %d"):format(slotName, item.ilvl) or slotName)
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

-- Same scale and opacity as the board.
local function applyLook()
    if not frame then return end
    frame:SetScale(AB.db.settings.scale or 1)
    frame.bg:SetAlpha(AB.db.settings.bgAlpha or 0.96)
end

local function build()
    frame = CreateFrame("Frame", "AltBoardCharFrame", UIParent)
    tinsert(UISpecialFrames, "AltBoardCharFrame") -- ESC closes it
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetWidth(WIDTH)
    frame.bg = W.Fill(frame, "window", 0.96)
    frame.bg:SetAllPoints()
    W.Border(frame, "line")

    -- Header: name, level/race/class, item level, freshness.
    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEADER_H)
    head.bg = W.Fill(head, "sidebar", 1)
    head.bg:SetAllPoints()
    W.Line(head, "bottom", "line")
    frame.name = W.Text(head, 4, "text")
    frame.name:SetPoint("TOPLEFT", PAD, -14)
    frame.info = W.Text(head, -1, "textDim")
    frame.info:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -6)
    frame.ilvl = W.Text(head, 2, "text")
    frame.ilvl:SetPoint("TOPRIGHT", -44, -14)
    frame.ilvl:SetJustifyH("RIGHT")
    frame.updated = W.Text(head, -2, "textFaint")
    frame.updated:SetPoint("TOPRIGHT", frame.ilvl, "BOTTOMRIGHT", 0, -6)
    frame.updated:SetJustifyH("RIGHT")
    local accent = head:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetSize(WIDTH, 2)
    W.OnAccent(function(r, g, b) accent:SetColorTexture(r, g, b, 1) end)
    local close = W.CloseButton(head, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    -- Item slots in two columns.
    frame.slots = {}
    local y0 = HEADER_H + 10
    for i, slotId in ipairs(LEFT) do
        local b = createSlot(frame, slotId)
        b:SetPoint("TOPLEFT", PAD, -(y0 + (i - 1) * SLOT_H))
        frame.slots[slotId] = b
    end
    for i, slotId in ipairs(RIGHT) do
        local b = createSlot(frame, slotId)
        b:SetPoint("TOPLEFT", PAD + COL_W + 4, -(y0 + (i - 1) * SLOT_H))
        frame.slots[slotId] = b
    end
    local y = y0 + max(#LEFT, #RIGHT) * SLOT_H + 8

    -- Stats: heading, then three columns of label / value.
    local line = W.Fill(frame, "line", 1, "BORDER")
    line:SetPoint("TOPLEFT", PAD, -y)
    line:SetPoint("TOPRIGHT", -PAD, -y)
    W.PixelSize(line, frame, "h")
    y = y + 10
    local statsTitle = W.Text(frame, -1, "text")
    statsTitle:SetPoint("TOPLEFT", PAD, -y)
    statsTitle:SetText("STATS")
    W.OnAccent(function(r, g, b) statsTitle:SetTextColor(r, g, b) end)
    frame.statsNote = W.Text(frame, -2, "textFaint")
    frame.statsNote:SetPoint("LEFT", statsTitle, "RIGHT", 10, 0)
    y = y + 22

    frame.stats = {}
    local colW = (WIDTH - 2 * PAD) / #STAT_COLUMNS
    local tallest = 0
    for ci, col in ipairs(STAT_COLUMNS) do
        local x = PAD + (ci - 1) * colW
        local h = W.Text(frame, -1, "textFaint")
        h:SetPoint("TOPLEFT", x, -y)
        h:SetText(col[1])
        for ri, def in ipairs(col[2]) do
            local ly = y + 4 + ri * STAT_H
            local label = W.Text(frame, -1, "textDim")
            label:SetPoint("TOPLEFT", x, -ly)
            label:SetText(def[1])
            local value = W.Text(frame, -1, "text")
            value:SetPoint("TOPRIGHT", frame, "TOPLEFT", x + colW - 14, -ly)
            value:SetJustifyH("RIGHT")
            frame.stats[#frame.stats + 1] = { label = label, value = value, def = def }
        end
        tallest = max(tallest, #col[2])
    end
    y = y + 4 + (tallest + 1) * STAT_H + PAD

    frame:SetHeight(y)
    frame:SetScript("OnHide", function()
        shownGuid = nil
        if GameTooltip then GameTooltip:Hide() end
        AB.Board.Refresh() -- drop the "open" mark on the name
    end)
    frame:Hide()
    applyLook()
end

-- Next to the board: right side if there is room, else left.
local function place()
    frame:ClearAllPoints()
    local board = AB.Board.Frame()
    if board and board:IsShown() then
        local right = (board:GetRight() or 0) * board:GetEffectiveScale()
        if right + WIDTH * frame:GetEffectiveScale() + 8 < UIParent:GetRight() * UIParent:GetEffectiveScale() then
            frame:SetPoint("TOPLEFT", board, "TOPRIGHT", 8, 0)
        else
            frame:SetPoint("TOPRIGHT", board, "TOPLEFT", -8, 0)
        end
    else
        frame:SetPoint("CENTER")
    end
end

function Sheet.Refresh()
    if not frame or not frame:IsShown() or not shownGuid then return end
    local c = AB.db.chars[shownGuid]
    if not c then frame:Hide() return end
    local isMe = shownGuid == AB.guid

    frame.name:SetText(c.name or "?")
    local r, g, b = Theme.ClassColor(c.class)
    if r then frame.name:SetTextColor(r, g, b) else frame.name:SetTextColor(Theme:Color("text")) end
    local className = c.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.class] or ""
    frame.info:SetText(("Level %s %s %s%s"):format(c.level or "?", c.race or "", className,
        c.guild and ("   <" .. c.guild .. ">") or ""))
    frame.ilvl:SetText(c.ilvl and ("Item level %.1f"):format(c.ilvl) or "")
    frame.updated:SetText(isMe and "online" or ("updated " .. ago(c.lastSeen)))
    frame.updated:SetTextColor(Theme:Color(isMe and "good" or "textFaint"))

    local gear = c.gear or {}
    for slotId, slot in pairs(frame.slots) do fillSlot(slot, gear[slotId]) end

    local s = c.stats
    frame.statsNote:SetText(s and "as shown in game at the last update (buffs included)"
        or "no stats yet: log in on this character once")
    for _, st in ipairs(frame.stats) do
        local ok, text = pcall(st.def[2], s or {})
        st.value:SetText(ok and text or "-")
        st.value:SetTextColor(Theme:Color(ok and text and "text" or "textFaint"))
        if st.def[3] then
            local okL, label = pcall(st.def[3], s or {})
            st.label:SetText(okL and label or st.def[1])
        end
    end
end

-- Open the sheet for a character; the same character again closes it.
function Sheet.Toggle(guid)
    if not AB.db or not AB.db.chars[guid] then return end
    if not frame then build() end
    if frame:IsShown() and shownGuid == guid then
        frame:Hide()
        return
    end
    if guid == AB.guid then AB.Data.Flush() end
    shownGuid = guid
    place()
    frame:Show()
    Sheet.Refresh()
    AB.Board.Refresh()
end

function Sheet.Hide()
    if frame then frame:Hide() end
end

function Sheet.ShownGuid() return shownGuid end

AB:OnSettingChanged(function(key)
    if not frame then return end
    if key == "scale" or key == "bgAlpha" then applyLook() end
    Sheet.Refresh()
end)
