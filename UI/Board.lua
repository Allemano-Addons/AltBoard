-- Board: the window. Characters are columns, rows are grouped in sections.
-- Built on first open and only redrawn while it is shown.
local _, AB = ...

local Theme, W, Data = AB.Theme, AB.Widgets, AB.Data
local S = Theme.size

local Board = {}
AB.Board = Board

local frame
local colOffset, scrollY = 0, 0

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

local function colorCode(key)
    local r, g, b = Theme:Color(key)
    return ("|cff%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local function money(copper)
    if not copper then return nil end
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then
        local gs = BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)
        parts[#parts + 1] = gs .. colorCode("gold") .. "g|r"
    end
    if s > 0 or g > 0 then parts[#parts + 1] = s .. colorCode("silver") .. "s|r" end
    if g == 0 then parts[#parts + 1] = c .. colorCode("copper") .. "c|r" end
    return table.concat(parts, " ")
end

local function num(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function ago(t)
    if not t then return nil end
    local d = time() - t
    if d < 3600 then return max(1, floor(d / 60)) .. " min ago" end
    if d < 86400 then return floor(d / 3600) .. " h ago" end
    return floor(d / 86400) .. " d ago"
end

-- ---------------------------------------------------------------------------
-- Rows. Each row: label + value(c, isMe) returning text [, colorKey].
-- ---------------------------------------------------------------------------

local OVERVIEW = {
    { label = "Level", value = function(c) return c.level and tostring(c.level) end },
    { label = "Item level", value = function(c) return c.ilvl and ("%.1f"):format(c.ilvl) end },
    { label = "Gold", value = function(c) return money(c.money) end },
    { label = "Rested", value = function(c)
        if not c.rested or not c.xpMax or c.xpMax == 0 then return nil end
        return floor(c.rested / c.xpMax * 100 + 0.5) .. "%", "good"
    end },
    { label = "Guild", value = function(c) return c.guild end },
    { label = "Location", value = function(c) return c.zone end },
    { label = "Last seen", value = function(c, isMe)
        if isMe then return "online", "good" end
        return ago(c.lastSeen), "textDim"
    end },
}

-- Profession rows: every profession any character has, main professions first.
local function professionRows(chars)
    local seen, rows = {}, {}
    for _, e in ipairs(chars) do
        for _, p in ipairs(e.data.profs or {}) do
            if not seen[p.name] then
                seen[p.name] = true
                rows[#rows + 1] = { name = p.name, primary = p.primary, icon = p.icon }
            elseif p.primary then
                for _, r in ipairs(rows) do if r.name == p.name then r.primary = true end end
            end
        end
    end
    sort(rows, function(a, b)
        if a.primary ~= b.primary then return a.primary end
        return a.name < b.name
    end)
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            label = r.name, icon = r.icon,
            value = function(c)
                for _, p in ipairs(c.profs or {}) do
                    if p.name == r.name then
                        return ("%d / %d"):format(p.rank or 0, p.max or 0), (p.max and p.rank == p.max) and "good" or "text"
                    end
                end
            end,
        }
    end
    return out
end

local function currencyRows(chars)
    local seen, names = {}, {}
    for _, e in ipairs(chars) do
        for name, cur in pairs(e.data.currency or {}) do
            if not seen[name] then
                seen[name] = cur.icon or true
                names[#names + 1] = name
            end
        end
    end
    sort(names)
    local out = {}
    for _, name in ipairs(names) do
        out[#out + 1] = {
            label = name, icon = seen[name] ~= true and seen[name] or nil,
            value = function(c)
                local cur = c.currency and c.currency[name]
                if not cur then return nil end
                if cur.max and cur.max > 0 then return ("%d / %d"):format(cur.qty, cur.max) end
                return tostring(cur.qty)
            end,
        }
    end
    return out
end

-- Reputation standing names and colors (the game's own when available).
local STANDING_FALLBACK = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local STANDING_COLOR_FALLBACK = {
    { 0.8, 0.13, 0.13 }, { 0.8, 0.13, 0.13 }, { 0.75, 0.27, 0 }, { 0.9, 0.7, 0 },
    { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 },
}

local function standingName(reaction)
    return _G["FACTION_STANDING_LABEL" .. tostring(reaction)] or STANDING_FALLBACK[reaction] or "?"
end

local function standingCode(reaction)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    local r, g, b
    if c then r, g, b = c.r, c.g, c.b else
        local f = STANDING_COLOR_FALLBACK[reaction] or { 1, 1, 1 }
        r, g, b = f[1], f[2], f[3]
    end
    return ("|cff%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- Rows grouped under their header ("Horde", "Other"...), groups and factions by name.
local function reputationRows(chars)
    local byId, groups = {}, {}
    for _, e in ipairs(chars) do
        for id, rep in pairs(e.data.reps or {}) do
            if not byId[id] then
                local g = rep.group or "Other"
                byId[id] = true
                groups[g] = groups[g] or {}
                tinsert(groups[g], { id = id, name = rep.name })
            end
        end
    end
    local names = {}
    for g in pairs(groups) do names[#names + 1] = g end
    sort(names)
    local out = {}
    for _, g in ipairs(names) do
        out[#out + 1] = { group = g }
        sort(groups[g], function(a, b) return a.name < b.name end)
        for _, f in ipairs(groups[g]) do
            out[#out + 1] = {
                label = f.name,
                value = function(c)
                    local rep = c.reps and c.reps[f.id]
                    if not rep or not rep.reaction then return nil end
                    local name = standingName(rep.reaction)
                    local span = (rep.max or 0) - (rep.min or 0)
                    local into = (rep.cur or 0) - (rep.min or 0)
                    local tip = { rep.name, standingCode(rep.reaction) .. name .. "|r" }
                    local progress = 1
                    if span > 0 and rep.reaction < 8 then
                        progress = max(0, min(1, into / span))
                        tip[#tip + 1] = ("%s / %s  (%d%%)"):format(num(into), num(span), floor(progress * 100))
                        tip[#tip + 1] = colorCode("textFaint") .. ("%s to %s"):format(num(span - into),
                            standingName(rep.reaction + 1)) .. "|r"
                    end
                    return name, "text", tip, progress
                end,
                bar = true,
            }
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Cells and rows (pooled)
-- ---------------------------------------------------------------------------

local rowPool

local function createRow()
    local row = CreateFrame("Frame", nil, frame.content)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", S.padding, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.label = W.Text(row, 0, "textDim")
    row.label:SetWidth(S.labelW - S.padding - 4)
    row.cells = {}
    -- Section headings fold open/closed on click (remembered).
    row:SetScript("OnMouseUp", function(self)
        if not self.toggle then return end
        local collapsed = AB.db.settings.collapsed
        collapsed[self.toggle] = not collapsed[self.toggle] or nil
        Board.Refresh()
    end)
    return row
end

local function cell(row, i)
    local c = row.cells[i]
    if not c then
        c = CreateFrame("Button", nil, row)
        c.text = W.Text(c, 0, "text")
        c.text:SetPoint("LEFT", 8, 0)
        c.text:SetPoint("RIGHT", -6, 0)
        c.sub = W.Text(c, -2, "textFaint")
        c.sub:SetPoint("TOPLEFT", c.text, "BOTTOMLEFT", 0, -3)
        c.sub:SetPoint("RIGHT", -6, 0)
        c.mark = c:CreateTexture(nil, "ARTWORK")
        c.mark:SetPoint("BOTTOMLEFT", 4, 0)
        c.mark:SetPoint("BOTTOMRIGHT", -4, 0)
        W.PixelSize(c.mark, c, "h", 2)
        -- Progress bar (reputation): thin track with an accent fill, under centered text.
        c.track = c:CreateTexture(nil, "BORDER")
        c.track:SetPoint("BOTTOMLEFT", 10, 5)
        c.track:SetPoint("BOTTOMRIGHT", -10, 5)
        W.PixelSize(c.track, c, "h", 3)
        c.track:SetColorTexture(Theme:Color("line"))
        c.fill = c:CreateTexture(nil, "ARTWORK")
        c.fill:SetPoint("TOPLEFT", c.track)
        c.fill:SetPoint("BOTTOMLEFT", c.track)
        c.fill:SetColorTexture(Theme:Accent())
        c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        c:SetScript("OnClick", function(self, button)
            if button == "RightButton" and self.onRightClick then
                W.HideTooltip()
                AB:Call("character menu", self.onRightClick, self)
            end
        end)
        c:SetScript("OnEnter", function(self) if self.tip then W.ShowTooltip(self, self.tip) end end)
        c:SetScript("OnLeave", W.HideTooltip)
        row.cells[i] = c
    end
    c.tip = nil
    c.onRightClick = nil
    c:SetAlpha(1)
    c.sub:SetText("")
    c.mark:Hide()
    c.track:Hide()
    c.fill:Hide()
    c.text:SetJustifyH("LEFT")
    c.text:ClearAllPoints()
    c.text:SetPoint("LEFT", 8, 0)
    c.text:SetPoint("RIGHT", -6, 0)
    c:Show()
    return c
end

local function resetRow(row)
    for _, c in ipairs(row.cells) do c:Hide() end
    row.icon:Hide()
    row.label:ClearAllPoints()
    row.toggle = nil
    row:EnableMouse(false)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local function visibleColumns(total)
    local screenW = UIParent:GetWidth() * 0.92
    local fit = max(1, floor((screenW - S.labelW) / Theme:ColumnWidth()))
    return min(total, fit)
end

local function placeRow(row, y, h, bgKey, bgAlpha)
    row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, y)
    row:SetHeight(h)
    local r, g, b = Theme:Color(bgKey or "window")
    row.bg:SetColorTexture(r, g, b, bgAlpha or 0)
end

function Board.Refresh()
    if not frame or not frame:IsShown() then return end
    rowPool:ReleaseAll()

    local hiddenCount = Data.HiddenCount()
    if hiddenCount == 0 then Board.showHidden = false end
    local chars = Data.Characters(Board.showHidden)
    local nVis = visibleColumns(#chars)
    colOffset = max(0, min(colOffset, #chars - nVis))
    local width = max(380, S.labelW + nVis * Theme:ColumnWidth()) -- room for the title bar
    frame:SetWidth(Theme:Snap(width, frame))

    local total = money(Data.TotalMoney(AB.db.settings.totalIncludesHidden)) or "0"
    frame.total:SetText(total)
    if hiddenCount > 0 then
        frame.hiddenBtn.text:SetText(Board.showHidden and "hide hidden" or (hiddenCount .. " hidden"))
        frame.hiddenBtn:SetWidth(frame.hiddenBtn.text:GetStringWidth() + 12)
        frame.hiddenBtn:Show()
    else
        frame.hiddenBtn:Hide()
    end
    if #chars > nVis then
        frame.paging:SetText(("%d-%d of %d  (mouse wheel)"):format(colOffset + 1, colOffset + nVis, #chars))
    else
        frame.paging:SetText("")
    end

    local me = AB.guid
    local y = scrollY

    -- Header: names.
    local header = rowPool:Acquire()
    placeRow(header, y, S.headerH, "sidebar", 1)
    for i = 1, nVis do
        local e = chars[colOffset + i]
        local c, cd = cell(header, i), e.data
        c:SetPoint("TOPLEFT", header, "TOPLEFT", S.labelW + (i - 1) * Theme:ColumnWidth(), 0)
        c:SetSize(Theme:ColumnWidth(), S.headerH)
        c.text:ClearAllPoints()
        c.text:SetPoint("TOPLEFT", 8, -9)
        c.text:SetPoint("RIGHT", -6, 0)
        c.text:SetText(cd.name)
        local r, g, b = Theme.ClassColor(cd.class)
        if r then c.text:SetTextColor(r, g, b) else c.text:SetTextColor(Theme:Color("text")) end
        c.sub:SetText(("%s %s"):format(cd.level or "?", cd.race or "") .. (cd.hidden and "  (hidden)" or ""))
        if cd.hidden then c:SetAlpha(0.45) end
        if e.guid == me then
            c.mark:SetColorTexture(Theme:Accent())
            c.mark:Show()
        end
        local tip = {
            (cd.name or "?") .. " - " .. (cd.realm or "?"),
            ("Level %s %s %s"):format(cd.level or "?", cd.race or "", cd.class and (LOCALIZED_CLASS_NAMES_MALE or {})[cd.class] or ""),
        }
        if cd.guild then tip[#tip + 1] = "<" .. cd.guild .. ">" end
        tip[#tip + 1] = colorCode("textFaint") .. "Right-click: move, hide, delete|r"
        c.tip = tip
        c.guid = e.guid
        c.onRightClick = Board.CharacterMenu
    end
    y = y - S.headerH

    local collapsed = AB.db.settings.collapsed

    local function section(title, rows, emptyText)
        local sr = rowPool:Acquire()
        placeRow(sr, y, S.sectionH)
        sr.label:SetPoint("BOTTOMLEFT", S.padding, 6)
        local closed = collapsed[title]
        local count = 0
        for _, def in ipairs(rows) do if not def.group then count = count + 1 end end
        sr.label:SetText(strupper(title) .. colorCode("textFaint") .. (closed and ("   + " .. count) or "   -") .. "|r")
        sr.label:SetTextColor(Theme:Accent())
        sr.toggle = title
        sr:EnableMouse(true)
        y = y - S.sectionH
        if closed then return end
        if #rows == 0 then
            local er = rowPool:Acquire()
            placeRow(er, y, S.rowH)
            er.label:SetPoint("LEFT", S.padding, 0)
            er.label:SetText(emptyText)
            er.label:SetTextColor(Theme:Color("textFaint"))
            y = y - S.rowH
            return
        end
        local stripe = 0
        for _, def in ipairs(rows) do
            local row = rowPool:Acquire()
            if def.group then
                -- Sub-heading inside a section ("Horde", "Other").
                placeRow(row, y, S.rowH)
                row.label:SetPoint("BOTTOMLEFT", S.padding, 3)
                row.label:SetText(def.group)
                row.label:SetTextColor(Theme:Color("textFaint"))
                stripe = 0
            else
                stripe = stripe + 1
                local h = def.bar and S.barRowH or S.rowH
                placeRow(row, y, h, "field", stripe % 2 == 0 and 0.6 or 0)
                local x = S.padding
                if def.icon then
                    row.icon:SetTexture(def.icon)
                    row.icon:Show()
                    x = x + 18
                end
                row.label:SetPoint("LEFT", x, 0)
                row.label:SetText(def.label)
                row.label:SetTextColor(Theme:Color("textDim"))
                for i = 1, nVis do
                    local e = chars[colOffset + i]
                    local c = cell(row, i)
                    c:SetPoint("TOPLEFT", row, "TOPLEFT", S.labelW + (i - 1) * Theme:ColumnWidth(), 0)
                    c:SetSize(Theme:ColumnWidth(), h)
                    local ok, text, colorKey, tip, progress = pcall(def.value, e.data, e.guid == me)
                    if not ok then text, colorKey, tip, progress = "error", "warn", nil, nil end
                    c.text:SetText(text or "-")
                    c.text:SetTextColor(Theme:Color(text and (colorKey or "text") or "textFaint"))
                    c.tip = tip
                    if def.bar then
                        c.text:SetJustifyH("CENTER")
                        c.text:ClearAllPoints()
                        c.text:SetPoint("LEFT", 8, progress and 3 or 0)
                        c.text:SetPoint("RIGHT", -8, progress and 3 or 0)
                        if progress then
                            c.track:Show()
                            local w = Theme:ColumnWidth() - 20
                            c.fill:SetWidth(max(0.01, w * progress))
                            c.fill:SetColorTexture(Theme:Accent())
                            c.fill:SetShown(progress > 0)
                        end
                    end
                end
            end
            y = y - (def.bar and S.barRowH or S.rowH)
        end
    end

    local shown = AB.db.settings.sections
    if shown.Overview then section("Overview", OVERVIEW) end
    if shown.Professions then section("Professions", professionRows(chars), "No professions seen yet") end
    if shown.Currency then section("Currency", currencyRows(chars), "No currencies yet") end
    if shown.Reputation then section("Reputation", reputationRows(chars), "No reputations seen yet") end

    -- Height follows the content, up to 85% of the screen; the rest scrolls.
    local contentH = scrollY - y
    local maxH = UIParent:GetHeight() * 0.85 - S.titleH
    frame.contentH, frame.viewH = contentH, min(contentH, maxH)
    frame:SetHeight(Theme:Snap(S.titleH + frame.viewH + 8, frame))
    -- Content got shorter (a section collapsed): don't stay scrolled past the end.
    local maxScroll = max(0, contentH - frame.viewH)
    if scrollY > maxScroll then
        scrollY = maxScroll
        return Board.Refresh()
    end
end

-- Right-click menu on a character name.
function Board.CharacterMenu(c)
    local guid = c.guid
    local cd = AB.db.chars[guid]
    if not cd then return end
    local chars = Data.Characters(Board.showHidden)
    local index
    for i, e in ipairs(chars) do if e.guid == guid then index = i end end
    local isMe = guid == AB.guid
    W.OpenMenu({
        { text = cd.name, title = true },
        { text = "Move left", disabled = index == 1, onClick = function()
            Data.Move(guid, -1, Board.showHidden)
            Board.Refresh()
        end },
        { text = "Move right", disabled = index == #chars, onClick = function()
            Data.Move(guid, 1, Board.showHidden)
            Board.Refresh()
        end },
        { text = cd.hidden and "Unhide" or "Hide", onClick = function()
            Data.SetHidden(guid, not cd.hidden)
            Board.Refresh()
        end },
        { text = isMe and "Delete (not while logged in)" or "Delete...", danger = true, disabled = isMe, onClick = function()
            W.Confirm(("Delete all AltBoard data for %s?\nIt comes back the next time you log in on it."):format(cd.name),
                "Delete", function()
                    Data.Delete(guid)
                    Board.Refresh()
                end)
        end },
    }, c)
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local function savePosition()
    local db = AB.db.window
    db.left = Theme:Snap(frame:GetLeft(), frame)
    db.top = Theme:Snap(frame:GetTop(), frame)
end

local function restorePosition()
    local db = AB.db.window
    frame:ClearAllPoints()
    if db.left and db.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.left, db.top)
    else
        frame:SetPoint("CENTER")
    end
end

local function build()
    frame = CreateFrame("Frame", "AltBoardFrame", UIParent)
    tinsert(UISpecialFrames, "AltBoardFrame") -- ESC closes it
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetSize(S.labelW + Theme:ColumnWidth(), 200)
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
    name:SetPoint("LEFT", S.padding, 0)
    name:SetText("AltBoard")
    local accent = title:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    accent:SetSize(18, 2)
    W.OnAccent(function(r, g, b) accent:SetColorTexture(r, g, b, 1) end)

    local close = W.CloseButton(title, function() frame:Hide() end)
    close:SetPoint("RIGHT", -8, 0)
    local gear = W.SettingsButton(title, "Settings", function() AB:Call("settings button", AB.Settings.Toggle) end)
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)

    frame.total = W.Text(title, 0, "text")
    frame.total:SetPoint("RIGHT", gear, "LEFT", -10, 0)
    -- "N hidden": shows hidden characters (dimmed) until clicked again. Not saved.
    local hb = CreateFrame("Button", nil, title)
    hb:SetHeight(22)
    hb:SetPoint("RIGHT", frame.total, "LEFT", -14, 0)
    hb.text = W.Text(hb, -1, "textFaint")
    hb.text:SetPoint("CENTER")
    hb:SetScript("OnEnter", function(self) self.text:SetTextColor(Theme:Color("text")) end)
    hb:SetScript("OnLeave", function(self) self.text:SetTextColor(Theme:Color("textFaint")) end)
    hb:SetScript("OnClick", function()
        Board.showHidden = not Board.showHidden
        Board.Refresh()
    end)
    hb:Hide()
    frame.hiddenBtn = hb

    frame.paging = W.Text(title, -2, "textFaint")
    frame.paging:SetPoint("LEFT", name, "RIGHT", 14, -1)

    -- Content clips to the window; rows are placed with scrollY applied.
    local clip = CreateFrame("Frame", nil, frame)
    clip:SetPoint("TOPLEFT", 0, -S.titleH)
    clip:SetPoint("BOTTOMRIGHT", 0, 8)
    clip:SetClipsChildren(true)
    frame.content = clip

    rowPool = W.Pool(createRow, resetRow)

    -- Wheel: pages characters when they don't fit; if rows overflow too, shift+wheel scrolls rows.
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local chars = #Data.Characters(Board.showHidden)
        local canCols = chars > visibleColumns(chars)
        local canRows = (frame.contentH or 0) > (frame.viewH or 0)
        if canCols and not (canRows and IsShiftKeyDown()) then
            colOffset = colOffset - delta
        elseif canRows then
            scrollY = max(0, min(scrollY - delta * S.rowH * 3, frame.contentH - frame.viewH))
        else
            return
        end
        Board.Refresh()
    end)

    frame:SetScript("OnShow", function()
        Data.Flush()
        Board.Refresh()
    end)
    frame:SetScript("OnHide", function()
        W.HideTooltip()
        W.CloseMenus()
    end)
    frame:Hide()
    Board.ApplyLook()
    restorePosition()
end

-- Background opacity and window scale from the settings.
function Board.ApplyLook()
    if not frame then return end
    local s = AB.db.settings
    frame.bg:SetAlpha(s.bgAlpha or 0.96)
    frame:SetScale(s.scale or 1)
end

function Board.Frame() return frame end

function Board.ResetPosition()
    AB.db.window.left, AB.db.window.top = nil, nil
    if frame then restorePosition() end
end

function Board.Toggle()
    if not AB.db then return end
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

function Board.Show()
    if not AB.db then return end
    if not frame then build() end
    frame:Show()
end

AB:OnSettingChanged(function(key)
    if not frame then return end
    if key == "bgAlpha" or key == "scale" then
        Board.ApplyLook()
        if key == "scale" then restorePosition() end
    end
    Board.Refresh()
end)

AB.Toggle = function() Board.Toggle() end
