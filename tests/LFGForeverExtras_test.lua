-- LFGForeverExtras: the member panel, click-to-/who, and %dungeon% in Ask to Join, against a stand-in for LFG Forever.
-- Run from the repo root: lua5.1 tests/LFGForeverExtras_test.lua
package.path = "tests/?.lua;" .. package.path
local W = require("wow")
C_LFGList = {
  GetSearchResultInfo = function(id) return { numMembers = 3, leaderName = "Bob", activityIDs = { 7, 8 } } end,
  GetSearchResultPlayerInfo = function(id, i) return ({ { name = "Bob", areaName = "Darkshore", classFilename = "DRUID" },
    { name = "Amy-Realm", areaName = "Ashenvale", classFilename = "MAGE" }, { name = "Cid", classFilename = "ROGUE" } })[i] end,
  GetActivityInfoTable = function(id) return { fullName = ({ [7] = "The Deadmines", [8] = "Wailing Caverns", [9] = "Gnomeregan" })[id] } end,
}
local sent
C_FriendList = { SendWho = function(q) sent = q end, GetNumWhoResults = function() return 1 end,
  GetWhoInfo = function() return { fullName = "Bob", fullGuildName = "Moonglade", area = "Darkshore" } end }
GetGuildInfo = function() return nil end
LFGForeverFrame = CreateFrame("Frame", "LFGForeverFrame", UIParent)
local filter = CreateFrame("Frame", nil, LFGForeverFrame)
local ticked = {}
function filter:SelectedActivityIDs() return ticked end
local row = CreateFrame("Button", nil, LFGForeverFrame)
row.resultID = 5
row:SetScript("OnClick", function() end)
local ask = CreateFrame("Button", nil, row)
row.LFGFAskToJoin = ask
LFGForeverCharDB = { askToJoinMessage = "LF %dungeon%, %class%" }
local whispered
ask:SetScript("OnClick", function() whispered = LFGForeverCharDB.askToJoinMessage end)
LFGBrowseSearchEntryTooltip = CreateFrame("Frame", "LFGBrowseSearchEntryTooltip", UIParent)
function LFGBrowseSearchEntryTooltip_UpdateAndShow(t, id) t:Show() end
W.Load("LFGForeverExtras/LFGForeverExtras.lua", "LFGForeverExtras", {})
W.Fire("PLAYER_LOGIN")
LFGForeverFrame:Show()
LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, 5)
W.Check(LFGForeverExtrasPanel:IsShown(), "panel shown for a group")
local found = false
for _, r in ipairs(LFGForeverExtrasPanel._regions or {}) do if r._text and r._text:find("Ashenvale") then found = true end end
W.Check(found, "zone listed")
row:Click("LeftButton")
W.Check(sent == 'n-"Bob"', "click: /who the first unknown member (got " .. tostring(sent) .. ")")
W.Fire("WHO_LIST_UPDATE")
W.Check(LFGForeverExtras.Guild("Bob") == "Moonglade", "guild remembered")
LFGForeverExtrasDB.guilds.bob.seen = time() - 4 * 86400
W.Check(LFGForeverExtras.Guild("Bob") == nil, "forgotten after 3 days")
LFGForeverExtrasDB.guilds.bob.seen = time()
C_FriendList.GetWhoInfo = function() return { fullName = "Cid", fullGuildName = "", area = "Westfall" } end
row:Click("LeftButton")
W.Check(sent == 'n-"Amy"' , "next click: the next member (got " .. tostring(sent) .. ")")
sent = nil
row:Click("LeftButton")
W.Check(sent == 'n-"Amy"' , "no answer: the same member again (got " .. tostring(sent) .. ")")
sent = nil
row:Click("LeftButton")
W.Check(sent == 'n-"Cid"' , "still none after two tries: moves on (got " .. tostring(sent) .. ")")
LFGForeverExtras.pending = { key = "cid", name = "Cid", sent = GetTime() }
W.Fire("WHO_LIST_UPDATE")
LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, 5)
local westfall = false
for _, r in ipairs(LFGForeverExtrasPanel._regions or {}) do if r._text and r._text:find("Cid") and r._text:find("Westfall") then westfall = true end end
W.Check(westfall, "/who's zone shown for a member the listing gave no zone")
ask:Click()
W.Check(whispered == "LF The Deadmines, Wailing Caverns, %class%", "nothing ticked: the group's dungeons (got " .. tostring(whispered) .. ")")
ticked = { 8 }
ask:Click()
W.Check(whispered == "LF Wailing Caverns, %class%", "the one you searched for (got " .. tostring(whispered) .. ")")
ticked = { 9 }
ask:Click()
W.Check(whispered == "LF Gnomeregan, %class%", "group doesn't list it: what you searched for (got " .. tostring(whispered) .. ")")
W.Check(LFGForeverCharDB.askToJoinMessage == "LF %dungeon%, %class%", "saved message restored")
W.Done()
