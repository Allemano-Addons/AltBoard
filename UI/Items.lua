-- Items: search every character's bags, bank and equipped items. Results update while
-- typing; rows show the total and who has it, hover = item tooltip + per-character counts.
local _, AB = ...

local Theme, W, Data = AB.Theme, AB.Widgets, AB.Data
local S = Theme.size

local Items = {}
AB.Items = Items

local WIDTH, HEIGHT, ROW_H, PAD = 480, 560, 40, 12
local MAX_RESULTS = 300

local frame
local results, offset = {}, 0

local function classCode(classFile)
    local r, g, b = Theme.ClassColor(classFile)
    if not r then return "|cffe6e8eb" end
    return ("|cff%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local function qualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return Theme:Color("text")
end

local function num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

-- "bags 10, bank 30, worn"
local function where(e)
    local parts = {}
    if e.bags > 0 then parts[#parts + 1] = "bags " .. num(e.bags) end
    if e.bank > 0 then parts[#parts + 1] = "bank " .. num(e.bank) end
    if e.worn > 0 then parts[#parts + 1] = "equipped" end
    return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

local function showTooltip(row)
    local r = row.result
    if not r or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if not (r.link and pcall(GameTooltip.SetHyperlink, GameTooltip, r.link)) then
        GameTooltip:SetText(r.name or "?")
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("AltBoard", Theme:Accent())
    for _, e in ipairs(r.chars) do
        local cr, cg, cb = Theme.ClassColor(e.class)
        GameTooltip:AddDoubleLine(e.name or "?", where(e), cr or 1, cg or 1, cb or 1, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Total", num(r.total), 0.6, 0.64, 0.68, 1, 1, 1)
    GameTooltip:Show()
end

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.hl = W.Fill(row, "selected", 1)
    row.hl:SetAllPoints()
    row.hl:Hide()
    row.iconBox = CreateFrame("Frame", nil, row)
    row.iconBox:SetSize(30, 30)
    row.iconBox:SetPoint("LEFT", PAD, 0)
    W.Fill(row.iconBox, "field", 1):SetAllPoints()
    row.ring = W.Border(row.iconBox, "line")
    row.icon = row.iconBox:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 2, -2)
    row.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.total = W.Text(row, 1, "text")
    row.total:SetPoint("TOPRIGHT", -PAD, -6)
    row.total:SetJustifyH("RIGHT")
    row.name = W.Text(row, 0, "text")
    row.name:SetPoint("TOPLEFT", row.iconBox, "TOPRIGHT", 8, -2)
    row.name:SetPoint("RIGHT", row.total, "LEFT", -8, 0)
    row.who = W.Text(row, -2, "textDim")
    row.who:SetPoint("BOTTOMLEFT", row.iconBox, "BOTTOMRIGHT", 8, 2)
    row.who:SetPoint("RIGHT", -PAD, 0)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        showTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self)
        local link = self.result and self.result.link
        if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    end)
    return row
end

local function fillRow(row, r)
    row.result = r
    row.icon:SetTexture(r.icon)
    row.name:SetText(r.name)
    local cr, cg, cb = qualityColor(r.q)
    row.name:SetTextColor(cr, cg, cb)
    for _, side in pairs(row.ring) do side:SetColorTexture(cr, cg, cb, r.q and r.q >= 2 and 1 or 0.35) end
    row.total:SetText(num(r.total))
    local parts = {}
    for i, e in ipairs(r.chars) do
        if i > 4 then
            parts[#parts + 1] = "+" .. (#r.chars - 4)
            break
        end
        parts[#parts + 1] = classCode(e.class) .. (e.name or "?") .. "|r " .. num(e.bags + e.bank + e.worn)
    end
    row.who:SetText(table.concat(parts, "   "))
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local function visibleRows() return floor(frame.list:GetHeight() / ROW_H) end

function Items.Render()
    if not frame or not frame:IsShown() then return end
    local n = visibleRows()
    offset = max(0, min(offset, #results - n))
    for i, row in ipairs(frame.rows) do
        local r = results[offset + i]
        if r and i <= n then
            fillRow(row, r)
            row:Show()
        else
            row.result = nil
            row:Hide()
        end
    end
    -- Thin scroll indicator.
    if #results > n and n > 0 then
        local trackH = frame.list:GetHeight()
        local thumbH = max(24, trackH * n / #results)
        frame.thumb:SetHeight(thumbH)
        frame.thumb:ClearAllPoints()
        frame.thumb:SetPoint("TOPRIGHT", frame.list, "TOPRIGHT", -2, -(trackH - thumbH) * offset / (#results - n))
        frame.thumb:Show()
    else
        frame.thumb:Hide()
    end
end

local function runSearch()
    local text = strtrim(frame.box:GetText() or "")
    offset = 0
    if #text < 2 then
        results = {}
        frame.info:SetText("Type at least 2 letters to search bags, bank and equipped items of all characters.")
    else
        results = Data.Search(text)
        local shownN = #results
        if shownN > MAX_RESULTS then
            for i = #results, MAX_RESULTS + 1, -1 do results[i] = nil end
        end
        frame.info:SetText(shownN == 0 and "Nothing found." or
            (shownN > MAX_RESULTS and ("%d items (first %d shown)"):format(shownN, MAX_RESULTS) or ("%d items"):format(shownN)))
    end
    Items.Render()
end

local function savePosition()
    local db = AB.db.itemsWindow
    db.left, db.top = Theme:Snap(frame:GetLeft(), frame), Theme:Snap(frame:GetTop(), frame)
end

local function restorePosition()
    local db = AB.db.itemsWindow
    frame:ClearAllPoints()
    if db.left and db.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.left, db.top)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

local function build()
    frame = CreateFrame("Frame", "AltBoardItemsFrame", UIParent)
    tinsert(UISpecialFrames, "AltBoardItemsFrame") -- ESC closes it
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetSize(WIDTH, HEIGHT)
    frame.bg = W.Fill(frame, "window", 0.96)
    frame.bg:SetAllPoints()
    W.Border(frame, "line")

    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(S.titleH)
    W.Line(title, "bottom", "line")
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() frame:StartMoving() end)
    title:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
        restorePosition()
    end)
    local name = W.Text(title, 3, "text")
    name:SetPoint("LEFT", PAD, 0)
    name:SetText("Search items")
    local close = W.CloseButton(title, function() frame:Hide() end)
    close:SetPoint("RIGHT", -8, 0)

    frame.box = W.EditBox(frame, "Item name, e.g. runecloth")
    frame.box:SetPoint("TOPLEFT", PAD, -(S.titleH + PAD))
    frame.box:SetPoint("TOPRIGHT", -PAD, -(S.titleH + PAD))
    frame.box:SetScript("OnTextChanged", function(self, userInput)
        if userInput ~= false then runSearch() end
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
    end)
    frame.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    frame.info = W.Text(frame, -1, "textFaint")
    frame.info:SetPoint("TOPLEFT", frame.box, "BOTTOMLEFT", 2, -8)
    frame.info:SetPoint("RIGHT", -PAD, 0)

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 0, -(S.titleH + PAD + 28 + 30))
    list:SetPoint("BOTTOMRIGHT", 0, 6)
    list:SetClipsChildren(true)
    frame.list = list
    W.Line(list, "top", "line")

    frame.rows = {}
    local maxRows = ceil((HEIGHT - S.titleH) / ROW_H)
    for i = 1, maxRows do
        local row = createRow(list)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", -8, -(i - 1) * ROW_H)
        row:Hide()
        frame.rows[i] = row
    end
    frame.thumb = list:CreateTexture(nil, "OVERLAY")
    frame.thumb:SetWidth(3)
    frame.thumb:SetColorTexture(Theme:Color("line"))
    frame.thumb:Hide()

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Items.Render()
    end)

    frame:SetScript("OnHide", function()
        frame.box:ClearFocus()
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame:Hide()
    restorePosition()
end

local function applyLook()
    if not frame then return end
    frame:SetScale(AB.db.settings.scale or 1)
    frame.bg:SetAlpha(AB.db.settings.bgAlpha or 0.96)
end

-- Open (optionally with a search text) or close.
function Items.Toggle(text)
    if not AB.db then return end
    if not frame then
        build()
        applyLook()
    end
    if frame:IsShown() and not text then
        frame:Hide()
        return
    end
    Data.Flush()
    frame:Show()
    if text then frame.box:SetText(text) end
    runSearch()
    if not text or text == "" then frame.box:SetFocus() end
end

AB:OnSettingChanged(function(key)
    if frame and (key == "scale" or key == "bgAlpha") then applyLook() end
end)

AB:AddSlashCommand("find", function(text) Items.Toggle(text ~= "" and text or nil) end,
    "search all characters' bags, bank and equipped items: /ab find <name>")
