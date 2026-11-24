-- CustomAddonFixes: fixes for other people's addons, from outside their files, so their updates
-- don't undo them. Loads after them (OptionalDeps). /caf shows which fixes are in place.
--
-- * ExperiencePlus: system messages can be "secret" on Forever (battlegrounds); its CHAT_MSG_SYSTEM
--   handler indexes them and errors. Its event frame is private, so it's found by the exact set
--   of events it listens to, and secret system messages are dropped before they reach it.
-- * ForeverForge: the same for CHAT_MSG_CHANNEL_NOTICE (it compares the secret message).
-- * AccWideUILayoutSelection: rejoining its saved chat channels calls JoinChannelByName, which is
--   blocked in combat and in instances (ADDON_ACTION_BLOCKED in battlegrounds). Its load function
--   is wrapped so that, in those cases, the rejoin is switched off for that one run. The server
--   keeps joined channels anyway.

local ADDON = ...
local PREFIX = "|cff66ccffCustomAddonFixes|r"
local addon = { status = {} }
CustomAddonFixes = addon

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

-- Unnamed, parentless frames listening to every event in the list.
function addon.FindEventFrames(events)
    local found = {}
    local f = EnumerateFrames()
    while f do
        if not f:GetName() and not f:GetParent() and f.IsEventRegistered then
            local all = true
            for _, e in ipairs(events) do
                if not f:IsEventRegistered(e) then all = false; break end
            end
            if all then found[#found + 1] = f end
        end
        f = EnumerateFrames(f)
    end
    return found
end

-- Put a filter in front of a private event frame's OnEvent. skip(event, ...) returns true to drop.
-- Only when exactly one frame matches, so nothing else is touched.
function addon.FilterEvents(key, events, skip)
    if addon.status[key] == "fixed" then return end
    local frames = addon.FindEventFrames(events)
    if #frames ~= 1 then
        addon.status[key] = #frames == 0 and "frame not found" or (#frames .. " frames match, left alone")
        return
    end
    local f = frames[1]
    local orig = f:GetScript("OnEvent")
    if not orig then addon.status[key] = "no handler"; return end
    f:SetScript("OnEvent", function(self, event, ...)
        if skip(event, ...) then
            addon.dropped[key] = (addon.dropped[key] or 0) + 1
            return
        end
        return orig(self, event, ...)
    end)
    addon.status[key] = "fixed"
end
addon.dropped = {}

function addon.FixExperiencePlus()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded("ExperiencePlus")) then addon.status.ExperiencePlus = "not loaded"; return end
    addon.FilterEvents("ExperiencePlus",
        { "QUEST_TURNED_IN", "CHAT_MSG_SYSTEM", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_LOGOUT" },
        function(event, msg) return event == "CHAT_MSG_SYSTEM" and IsSecret(msg) end)
end

function addon.FixForeverForge()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded("ForeverForge")) then addon.status.ForeverForge = "not loaded"; return end
    addon.FilterEvents("ForeverForge",
        { "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "CHANNEL_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE", "CHAT_MSG_CHANNEL_NOTICE" },
        function(event, msg, _, _, channelName, _, _, _, _, baseName)
            return event == "CHAT_MSG_CHANNEL_NOTICE" and (IsSecret(msg) or IsSecret(channelName) or IsSecret(baseName))
        end)
end

function addon.FixAccWide()
    local A = AccWideUIAceAddon
    if not A then addon.status.AccWide = "not loaded"; return end
    if addon.status.AccWide == "fixed" then return end
    local orig = A.LoadUISettings
    if type(orig) ~= "function" then addon.status.AccWide = "load function not found"; return end
    A.LoadUISettings = function(self, ...)
        local toggles = self.db and self.db.profile and self.db.profile.syncToggles
        local skip = toggles and toggles.chatChannels == true and (InCombatLockdown() or IsInInstance())
        if skip then
            toggles.chatChannels = false
            addon.dropped.AccWide = (addon.dropped.AccWide or 0) + 1
        end
        local results = { pcall(orig, self, ...) }
        if skip then toggles.chatChannels = true end
        if not results[1] then
            geterrorhandler()(results[2])
            return
        end
        return unpack(results, 2)
    end
    addon.status.AccWide = "fixed"
end

function addon.ApplyAll()
    addon.FixExperiencePlus()
    addon.FixForeverForge()
    addon.FixAccWide()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= ADDON then
        -- One loading later than us (e.g. on demand): try again.
        if arg1 == "ExperiencePlus" then addon.FixExperiencePlus()
        elseif arg1 == "ForeverForge" then addon.FixForeverForge()
        elseif arg1 == "AccWideUILayoutSelection" then addon.FixAccWide() end
    else
        addon.ApplyAll()
    end
end)

SLASH_CUSTOMADDONFIXES1 = "/caf"
SlashCmdList.CUSTOMADDONFIXES = function()
    for _, key in ipairs({ "ExperiencePlus", "ForeverForge", "AccWide" }) do
        print(PREFIX, key .. ":", tostring(addon.status[key] or "not tried"),
            "| times it stepped in:", addon.dropped[key] or 0)
    end
end
