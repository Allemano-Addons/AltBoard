-- Theme: colors, sizes and fonts. The palette is Hush's original look; the accent follows
-- Hush's setting when Hush is installed (read only, AltBoard never needs Hush).
local _, AB = ...

local Theme = {}
AB.Theme = Theme

local function hex(s)
    return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
end
Theme.Hex = hex

Theme.colors = {
    window    = { hex("111418") },
    sidebar   = { hex("0D1013") },
    field     = { hex("15191E") },
    selected  = { hex("1A1F26") },
    line      = { hex("22272E") },
    text      = { hex("E6E8EB") },
    textDim   = { hex("9AA3AD") },
    textFaint = { hex("7C858F") },
    good      = { hex("3FC77F") },
    warn      = { hex("E8A33D") },
    gold      = { 1, 0.82, 0 },
    silver    = { hex("C7C7CF") },
    copper    = { hex("C8753C") },
}

Theme.size = {
    titleH = 40,
    rowH = 22,
    barRowH = 30,
    sectionH = 28,
    headerH = 44,
    labelW = 150,
    colW = 128,
    padding = 12,
}

function Theme:Color(key)
    local c = self.colors[key]
    return c[1], c[2], c[3]
end

local function classColor(classFile)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = classFile and colors and colors[classFile]
    if c then return c.r, c.g, c.b end
end
Theme.ClassColor = classColor

-- Accent: Hush's choice if Hush is installed, else Hush's default blue. HushDB is only
-- complete after every addon loaded, so this is read when the board is built (never at load).
function Theme:Accent()
    local s = type(HushDB) == "table" and type(HushDB.settings) == "table" and HushDB.settings or nil
    if s and s.useClassColor then
        local r, g, b = classColor(select(2, UnitClass("player")))
        if r then return r, g, b end
    end
    local h = s and type(s.accent) == "string" and #s.accent == 6 and s.accent or "3FC7EB"
    return hex(h)
end

-- Fonts from new addon folders are refused on WoW Forever, so the game font it is.
local FONT = "Fonts\\FRIZQT__.TTF"
function Theme:SetFont(fs, delta)
    fs:SetFont(FONT, 12 + (delta or 0), "")
    fs:SetShadowOffset(0, 0)
end

-- Size of one physical pixel in the frame's coordinate space.
function Theme:Pixel(frame)
    local physH = 1080
    if GetPhysicalScreenSize then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then physH = h end
    end
    return 768 / physH / (frame or UIParent):GetEffectiveScale()
end

function Theme:Snap(value, frame)
    local px = self:Pixel(frame)
    return floor(value / px + 0.5) * px
end
