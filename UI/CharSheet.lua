-- Character sheet: a saved character's equipped items and stats, opened by clicking a
-- name on the board. Built once; Refresh only fills in values.
local _, AB = ...

local Theme, W = AB.Theme, AB.Widgets

local Sheet = {}
AB.CharSheet = Sheet

local WIDTH, HEADER_H, SLOT_H, COL_W, PAD = 520, 70, 36, 246, 12
local STAT_H, TAB_H, CELL = 17, 30, 40

local TABS = { { id = "gear", label = "Gear" }, { id = "bags", label = "Bags" }, { id = "bank", label = "Bank" } }
Sheet.tab = "gear"

local frame, shownGuid
local gridOffset = 0 -- first visible grid row (Bags/Bank)

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
    W.Round(b.hl, Theme.radius.small)
    b.iconBox = CreateFrame("Frame", nil, b)
    b.iconBox:SetSize(30, 30)
    b.iconBox:SetPoint("LEFT", 0, 0)
    b.iconBg = W.Fill(b.iconBox, "field", 1)
    b.iconBg:SetAllPoints()
    W.Round(b.iconBg, Theme.radius.small)
    b.ring = W.RoundBorder(W.Border(b.iconBox, "line"), Theme.radius.small)
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
        b.ring:SetColor(r, g, bl, 1)
        return
    end
    b.icon:SetTexture(item.icon)
    b.name:SetText(item.name or (item.link and item.link:match("%[(.-)%]")) or "?")
    local r, g, bl = qualityColor(item.q)
    b.name:SetTextColor(r, g, bl)
    b.ring:SetColor(r, g, bl, item.q and item.q >= 2 and 1 or 0.35)
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

-- ---------------------------------------------------------------------------
-- Bags / Bank grid: one cell per item (counts added up), best quality first.
-- ---------------------------------------------------------------------------

local GRID_COLS = floor((WIDTH - 2 * PAD) / CELL)

local function cellTooltip(cell)
    if not GameTooltip or not cell.item then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    if not (cell.item.l and pcall(GameTooltip.SetHyperlink, GameTooltip, cell.item.l)) then
        GameTooltip:SetText(cell.item.n or "?")
    end
    GameTooltip:Show()
end

local function createCell(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(CELL - 4, CELL - 4)
    W.Round(W.Fill(b, "field", 1), Theme.radius.small):SetAllPoints()
    b.ring = W.RoundBorder(W.Border(b, "line"), Theme.radius.small)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b:SetScript("OnEnter", cellTooltip)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self)
        if self.item and self.item.l and HandleModifiedItemClick then HandleModifiedItemClick(self.item.l) end
    end)
    return b
end

local function buildGrid()
    local g = CreateFrame("Frame", nil, frame)
    g:SetPoint("TOPLEFT", 0, -(HEADER_H + TAB_H))
    g:SetPoint("BOTTOMRIGHT", 0, 0)
    g.info = W.Text(g, -1, "textFaint")
    g.info:SetPoint("TOPLEFT", PAD, -12)
    g.info:SetPoint("RIGHT", -PAD, 0)
    g.area = CreateFrame("Frame", nil, g)
    g.area:SetPoint("TOPLEFT", PAD, -36)
    g.area:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    g.area:SetClipsChildren(true)
    g.cells = {}
    g:EnableMouseWheel(true)
    g:SetScript("OnMouseWheel", function(_, delta)
        gridOffset = gridOffset - delta
        Sheet.Refresh()
    end)
    frame.gridView = g
end

local function refreshGrid(c)
    local g = frame.gridView
    local isBank = Sheet.tab == "bank"
    local counts = isBank and c.bank or c.bags
    local slots = isBank and c.bankSlots or c.bagSlots
    local at = isBank and c.bankAt or c.bagsAt

    if not counts then
        g.info:SetText(isBank and "Bank not seen yet: open the bank once on this character."
            or "Bags not read yet: log in on this character once.")
    else
        local when = (shownGuid == AB.guid and not isBank) and "now"
            or (shownGuid == AB.guid and isBank and AB.Data.IsBankOpen()) and "open now"
            or ago(at)
        g.info:SetText(("%s: %d / %d slots used   -   %s %s"):format(isBank and "Bank" or "Bags",
            slots and slots.used or 0, slots and slots.total or 0, isBank and "last visited" or "updated", when))
    end

    local list = {}
    for key, count in pairs(counts or {}) do
        list[#list + 1] = { key = key, count = count, item = AB.db.items[key] or { n = key } }
    end
    sort(list, function(a, b)
        local qa, qb = a.item.q or 0, b.item.q or 0
        if qa ~= qb then return qa > qb end
        return (a.item.n or "") < (b.item.n or "")
    end)

    local rowsVisible = floor(g.area:GetHeight() / CELL)
    local totalRows = ceil(#list / GRID_COLS)
    gridOffset = max(0, min(gridOffset, totalRows - rowsVisible))
    local first = gridOffset * GRID_COLS
    local n = min(#list - first, rowsVisible * GRID_COLS)
    for i = 1, max(n, #g.cells) do
        local cell = g.cells[i]
        local e = i <= n and list[first + i]
        if e then
            if not cell then
                cell = createCell(g.area)
                g.cells[i] = cell
            end
            local col, row = (i - 1) % GRID_COLS, floor((i - 1) / GRID_COLS)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", col * CELL, -row * CELL)
            cell.item = e.item
            cell.icon:SetTexture(e.item.i)
            local r, gg, b = qualityColor(e.item.q)
            cell.ring:SetColor(r, gg, b, e.item.q and e.item.q >= 2 and 1 or 0.35)
            cell.count:SetFont(Theme:FontPath(), 11, "OUTLINE")
            cell.count:SetText(e.count > 1 and num(e.count) or "")
            cell:Show()
        elseif cell then
            cell.item = nil
            cell:Hide()
        end
    end
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
    W.Panel(frame, frame.bg, W.Border(frame, "line"))

    -- Header: name, level/race/class, item level, freshness.
    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEADER_H)
    head.bg = W.Fill(head, "sidebar", 1)
    head.bg:SetAllPoints()
    head.bg:Hide() -- one surface with the rounded window
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

    -- Tabs: Gear / Bags / Bank.
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", 0, -HEADER_H)
    tabBar:SetPoint("TOPRIGHT", 0, -HEADER_H)
    tabBar:SetHeight(TAB_H)
    W.Line(tabBar, "bottom", "line")
    frame.tabs = {}
    for i, def in ipairs(TABS) do
        local tab = CreateFrame("Button", nil, tabBar)
        tab.id = def.id
        tab:SetSize(90, TAB_H)
        tab:SetPoint("TOPLEFT", PAD + (i - 1) * 90, 0)
        tab.text = W.Text(tab, 0, "textDim")
        tab.text:SetPoint("CENTER")
        tab.text:SetText(def.label)
        tab.underline = tab:CreateTexture(nil, "OVERLAY")
        tab.underline:SetPoint("BOTTOMLEFT", 8, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", -8, 0)
        W.PixelSize(tab.underline, tab, "h", 2)
        W.OnAccent(function(r, g, b) tab.underline:SetColorTexture(r, g, b, 1) end)
        tab:SetScript("OnClick", function(self)
            Sheet.tab = self.id
            gridOffset = 0
            Sheet.Refresh()
        end)
        tab:SetScript("OnEnter", function(self) self.text:SetTextColor(Theme:Color("text")) end)
        tab:SetScript("OnLeave", function(self)
            self.text:SetTextColor(Theme:Color(self.id == Sheet.tab and "text" or "textDim"))
        end)
        frame.tabs[i] = tab
    end

    -- Gear view: item slots in two columns, stats below.
    local view = CreateFrame("Frame", nil, frame)
    view:SetAllPoints()
    frame.gearView = view
    frame.slots = {}
    local y0 = HEADER_H + TAB_H + 10
    for i, slotId in ipairs(LEFT) do
        local b = createSlot(view, slotId)
        b:SetPoint("TOPLEFT", PAD, -(y0 + (i - 1) * SLOT_H))
        frame.slots[slotId] = b
    end
    for i, slotId in ipairs(RIGHT) do
        local b = createSlot(view, slotId)
        b:SetPoint("TOPLEFT", PAD + COL_W + 4, -(y0 + (i - 1) * SLOT_H))
        frame.slots[slotId] = b
    end
    local y = y0 + max(#LEFT, #RIGHT) * SLOT_H + 8

    -- Stats: heading, then three columns of label / value.
    local line = W.Fill(view, "line", 1, "BORDER")
    line:SetPoint("TOPLEFT", PAD, -y)
    line:SetPoint("TOPRIGHT", -PAD, -y)
    W.PixelSize(line, view, "h")
    y = y + 10
    local statsTitle = W.Text(view, -1, "text")
    statsTitle:SetPoint("TOPLEFT", PAD, -y)
    statsTitle:SetText("STATS")
    W.OnAccent(function(r, g, b) statsTitle:SetTextColor(r, g, b) end)
    frame.statsNote = W.Text(view, -2, "textFaint")
    frame.statsNote:SetPoint("LEFT", statsTitle, "RIGHT", 10, 0)
    y = y + 22

    frame.stats = {}
    local colW = (WIDTH - 2 * PAD) / #STAT_COLUMNS
    local tallest = 0
    for ci, col in ipairs(STAT_COLUMNS) do
        local x = PAD + (ci - 1) * colW
        local h = W.Text(view, -1, "textFaint")
        h:SetPoint("TOPLEFT", x, -y)
        h:SetText(col[1])
        for ri, def in ipairs(col[2]) do
            local ly = y + 4 + ri * STAT_H
            local label = W.Text(view, -1, "textDim")
            label:SetPoint("TOPLEFT", x, -ly)
            label:SetText(def[1])
            local value = W.Text(view, -1, "text")
            value:SetPoint("TOPRIGHT", view, "TOPLEFT", x + colW - 14, -ly)
            value:SetJustifyH("RIGHT")
            frame.stats[#frame.stats + 1] = { label = label, value = value, def = def }
        end
        tallest = max(tallest, #col[2])
    end
    y = y + 4 + (tallest + 1) * STAT_H + PAD

    buildGrid()
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

    for _, tab in ipairs(frame.tabs) do
        local active = tab.id == Sheet.tab
        tab.text:SetTextColor(Theme:Color(active and "text" or "textDim"))
        tab.underline:SetShown(active)
    end
    frame.gearView:SetShown(Sheet.tab == "gear")
    frame.gridView:SetShown(Sheet.tab ~= "gear")
    if Sheet.tab ~= "gear" then
        refreshGrid(c)
        return
    end

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
