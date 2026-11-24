-- CustomQuestTracker: clicking the Quests header minimises every tracker section and a second
-- click restores each to how it was; combat defers; the state survives a reload.
-- Run from the repo root: lua5.1 tests/CustomQuestTracker_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

-- Blizzard's objective tracker: modules with a header and a collapsed state.
local layouts = 0
local function Module(name, title, collapsed)
    local m = CreateFrame("Frame", name, UIParent)
    m.Header = CreateFrame("Frame", nil, m)
    m.Header.Text = m.Header:CreateFontString()
    m.Header.Text:SetText(title)
    m.collapsed = collapsed
    function m:IsCollapsed() return self.collapsed end
    function m:SetCollapsed(on) self.collapsed = on; layouts = layouts + 1 end
    return m
end
local quests = Module("QuestObjectiveTracker", "Quests", false)
local achievements = Module("AchievementObjectiveTracker", "Achievements", true)
local bonus = Module("BonusObjectiveTracker", "Bonus Objectives", false)
ObjectiveTrackerFrame = CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent)
ObjectiveTrackerFrame.modules = { quests, achievements, bonus }

local function Load()
    W.Load("CustomQuestTracker/CustomQuestTracker.lua", "CustomQuestTracker")
    W.Fire("ADDON_LOADED", "CustomQuestTracker")
    W.Fire("PLAYER_LOGIN")
    W.Fire("PLAYER_ENTERING_WORLD")
end
Load()
local function Click(button) quests.Header:GetScript("OnMouseUp")(quests.Header, button or "LeftButton") end

print("Click to minimise")
W.Check(quests.Header:IsMouseEnabled(), "Quests line takes clicks")
Click()
W.Check(quests.collapsed and achievements.collapsed and bonus.collapsed, "all sections collapsed to the Quests line")
Click()
W.Check(not quests.collapsed and achievements.collapsed and not bonus.collapsed,
    "restored: Quests and Bonus open, Achievements still collapsed as before")
Click("RightButton")
W.Check(not quests.collapsed, "right-click does nothing")

print("Combat")
W.combat = true
local before = layouts
Click()
W.Check(layouts == before and not quests.collapsed, "in combat: nothing changes yet")
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
W.Check(quests.collapsed and bonus.collapsed, "after combat: minimised")
W.combat = true
Click(); Click()
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
W.Check(quests.collapsed, "two clicks in combat cancel out")

print("Reload while minimised")
-- Blizzard may reopen sections on reload; we keep it minimised and still restore correctly.
quests.collapsed, bonus.collapsed = false, false
Load()
W.Check(quests.collapsed and bonus.collapsed, "still minimised after reload")
W.Slash("/cqt")
W.Check(not quests.collapsed and achievements.collapsed and not bonus.collapsed, "/cqt restores the old states")
W.Check(pcall(W.Slash, "/cqt debug"), "/cqt debug runs")

print("No tracker yet at login")
ObjectiveTrackerFrame, QuestObjectiveTracker = nil, nil
W.Load("CustomQuestTracker/CustomQuestTracker.lua", "CustomQuestTracker")
W.Fire("ADDON_LOADED", "CustomQuestTracker")
W.Check(pcall(W.Fire, "PLAYER_LOGIN"), "no tracker: no error")
QuestObjectiveTracker = quests
ObjectiveTrackerFrame = CreateFrame("Frame", nil, UIParent); ObjectiveTrackerFrame.modules = { quests }
W.Advance(3)
W.Check(CustomQuestTracker.hooked == quests.Header, "hooks the header once the tracker exists")

W.Done()
