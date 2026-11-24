-- CustomAddonFixes: secret messages are kept from ExperiencePlus's and ForeverForge's private event
-- frames (and only theirs), and Account Wide Interface Settings skips rejoining chat channels in
-- instances or combat. Run from the repo root: lua5.1 tests/CustomAddonFixes_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

local SECRET = "secret system message"
W.secret[SECRET] = true

-- ExperiencePlus's private event frame: errors on a secret message, as in game.
local xpGot = {}
local xp = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_TURNED_IN", "CHAT_MSG_SYSTEM", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_LOGOUT" }) do
    xp:RegisterEvent(e)
end
xp:SetScript("OnEvent", function(_, event, msg)
    if event == "CHAT_MSG_SYSTEM" then
        if issecretvalue(msg) then error("attempt to index local 'msg' (a secret string value)") end
        table.insert(xpGot, msg)
    end
end)

-- ForeverForge's.
local ffGot = {}
local ff = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "CHANNEL_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE", "CHAT_MSG_CHANNEL_NOTICE" }) do
    ff:RegisterEvent(e)
end
ff:SetScript("OnEvent", function(_, event, msg)
    if event == "CHAT_MSG_CHANNEL_NOTICE" then
        if issecretvalue(msg) then error("attempt to compare local 'msg' (a secret string value)") end
        table.insert(ffGot, msg)
    end
end)

-- Someone else's frame on CHAT_MSG_SYSTEM (a chat window): must still get secret messages.
local chatGot = {}
local chat = CreateFrame("Frame", "ChatFrame1", UIParent)
chat:RegisterEvent("CHAT_MSG_SYSTEM")
chat:SetScript("OnEvent", function(_, _, msg) table.insert(chatGot, msg) end)

-- Account Wide Interface Settings.
local joins = {}
local toggles = { chatChannels = true }
AccWideUIAceAddon = { db = { profile = { syncToggles = toggles } } }
function AccWideUIAceAddon:LoadUISettings(a, b)
    if self.db.profile.syncToggles.chatChannels == true then table.insert(joins, "General") end
    return "loaded", a, b
end

W.loadedAddons = { ExperiencePlus = true, ForeverForge = true, AccWideUILayoutSelection = true }
W.Load("CustomAddonFixes/CustomAddonFixes.lua", "CustomAddonFixes")
W.Fire("ADDON_LOADED", "CustomAddonFixes")
local A = CustomAddonFixes
W.Check(A.status.ExperiencePlus == "fixed" and A.status.ForeverForge == "fixed" and A.status.AccWide == "fixed",
    "all three fixes in place")

print("Secret messages")
W.Check(pcall(W.Fire, "CHAT_MSG_SYSTEM", SECRET), "secret system message: no ExperiencePlus error")
W.Fire("CHAT_MSG_SYSTEM", "Experience gained: 484.")
W.Check(#xpGot == 1 and xpGot[1] == "Experience gained: 484.", "readable ones still reach ExperiencePlus")
W.Check(#chatGot == 2, "the chat window still gets both, the secret one too")
W.Check(pcall(W.Fire, "CHAT_MSG_CHANNEL_NOTICE", SECRET), "secret channel notice: no ForeverForge error")
W.Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED")
W.Check(#ffGot == 1, "readable notices still reach ForeverForge")
W.Check(A.dropped.ExperiencePlus == 1 and A.dropped.ForeverForge == 1, "counted")

print("Chat channels")
local r1, r2 = AccWideUIAceAddon:LoadUISettings(true, false)
W.Check(#joins == 1 and r1 == "loaded" and r2 == true, "outside: channels rejoined, results passed through")
W.instance = true
AccWideUIAceAddon:LoadUISettings()
W.Check(#joins == 1, "in a battleground: rejoin skipped")
W.Check(toggles.chatChannels == true, "and the setting is left as it was")
W.instance = false
W.combat = true
AccWideUIAceAddon:LoadUISettings()
W.Check(#joins == 1, "in combat: skipped")
W.combat = false

print("Only one matching frame")
local xp2 = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_TURNED_IN", "CHAT_MSG_SYSTEM", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_LOGOUT" }) do
    xp2:RegisterEvent(e)
end
xp2:SetScript("OnEvent", function() end)
A.status.ExperiencePlus = nil
A.FixExperiencePlus()
W.Check(A.status.ExperiencePlus == "2 frames match, left alone", "two candidates: neither touched (" .. tostring(A.status.ExperiencePlus) .. ")")
W.Check(pcall(W.Slash, "/caf"), "/caf runs")

W.Done()
