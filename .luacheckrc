std = "lua51"
max_line_length = false
self = false

-- The only globals AltBoard may write.
globals = {
    "AltBoardDB",
    "SLASH_ALTBOARD1", "SLASH_ALTBOARD2",
    "SlashCmdList",
}

-- WoW API used by AltBoard (read-only). Extend as new APIs are used.
read_globals = {
    "_G",
    "strjoin", "strsplit", "strtrim", "strlower", "strupper", "tostringall", "tinsert", "tremove",
    "wipe", "sort", "floor", "ceil", "min", "max", "format", "date", "time", "CopyTable", "geterrorhandler",
    "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME", "GameTooltip",
    "GetBuildInfo", "GetTime", "GetAddOnMetadata", "C_AddOns", "C_Timer", "Constants",
    "UnitGUID", "UnitName", "UnitFullName", "UnitClass", "UnitRace", "UnitLevel", "UnitFactionGroup",
    "GetRealmName", "GetNormalizedRealmName", "GetMoney", "GetAverageItemLevel", "RequestTimePlayed",
    "GetGuildInfo", "GetRealZoneText", "GetXPExhaustion", "GetServerTime", "GetQuestResetTime", "C_DateAndTime",
    "RequestRaidInfo", "GetNumSavedInstances", "GetSavedInstanceInfo", "GetSavedInstanceEncounterInfo",
    "GetSavedInstanceChatLink", "GetNumSavedWorldBosses", "GetSavedWorldBossInfo",
    "GetProfessions", "GetNumSkillLines", "GetSkillLineInfo", "IsSpellKnown", "GetSpellInfo", "GetSpellCooldown",
    "C_Spell", "C_TradeSkillUI", "GetNumFactions", "GetFactionInfo", "C_Reputation",
}
