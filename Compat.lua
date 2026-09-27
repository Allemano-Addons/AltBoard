-- Compat: everything that may differ on WoW Forever. Other files go through here
-- instead of calling version-sensitive APIs directly.
local _, AB = ...

local Compat = {}
AB.Compat = Compat

function Compat.PlayerRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName() or ""):gsub("[%s%-]", "")
    end
    return realm
end

-- Full character name. On WoW Forever UnitName returns first name and SURNAME
-- separately, and first names are not unique.
function Compat.PlayerName()
    local name, second = UnitName("player")
    name = name or "Unknown"
    if type(second) == "string" and second ~= "" then
        local sep = Constants and Constants.CharacterNameSeparatorConsts
            and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
        return name .. sep .. second
    end
    return name
end

function Compat.GetAddOnMetadata(addon, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addon, field)
    end
    return GetAddOnMetadata(addon, field)
end

function Compat.After(seconds, fn)
    if C_Timer and C_Timer.After then return C_Timer.After(seconds, fn) end
    fn()
end
