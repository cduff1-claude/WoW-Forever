-- CustomQuestTracker: clicking EnhancedQuestTracker's title minimises its window to the title line,
-- keeps it there when the tracker refits itself, and a second click restores the full height.
-- Run from the repo root: lua5.1 tests/CustomQuestTracker_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

-- A stand-in for EnhancedQuestTracker's window: title, Blizzard-look header, scroll list, and an
-- OnSizeChanged that re-lays out (refits the height) when the width it laid out for changes.
local CONTENT = 300
local f = CreateFrame("Frame", "EnhancedQuestTrackerFrame", UIParent)
f:SetSize(250, CONTENT)
f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -50, -200)
f.title = f:CreateFontString()
f.title:SetPoint("TOPLEFT", 8, -8)
f.title:SetText("Quests (16)")
f.header = CreateFrame("Frame", nil, f)
f.header:SetHeight(26)
f.header:Hide()
f.scroll = CreateFrame("ScrollFrame", nil, f)
local layouts = 0
local layoutWidth = 250
local function Layout() layouts = layouts + 1; layoutWidth = f:GetWidth(); f:SetHeight(CONTENT) end
f:SetScript("OnSizeChanged", function(self, width) if width ~= layoutWidth then Layout() end end)

local function Load()
    W.Load("CustomQuestTracker/CustomQuestTracker.lua", "CustomQuestTracker")
    W.Fire("ADDON_LOADED", "CustomQuestTracker")
    W.Fire("PLAYER_LOGIN")
end
Load()
local A = CustomQuestTracker
local function H() return math.floor(f:GetHeight() + 0.5) end

print("Click the title")
local btn = _G.CustomQuestTrackerTitleButton
W.Check(btn and btn:IsShown(), "a click button sits over the title")
btn:Click()
W.Check(H() == 28 and not f.scroll:IsShown(), "minimised to the title line (got " .. H() .. ")")

print("The tracker refits itself while minimised")
Layout()
W.Check(H() == 28, "still minimised after a quest update")

print("Click again")
btn:Click()
W.Check(H() == CONTENT and f.scroll:IsShown(), "restored to the full list (got " .. H() .. ")")
Layout()
W.Check(H() == CONTENT, "and refits normally afterwards")

print("Combat")
W.combat = true
btn:Click()
W.Check(H() == 28, "minimising works in combat (the window isn't protected)")
btn:Click()
W.combat = false
W.Check(H() == CONTENT, "and restoring")

print("Blizzard look")
f.header:Show()
f.header:GetScript("OnMouseUp")(f.header, "LeftButton")
W.Check(H() == 26, "header bar click: minimised to the header (got " .. H() .. ")")
W.Check(not btn:IsShown(), "title button hidden in this look")
f.header:GetScript("OnMouseUp")(f.header, "RightButton")
W.Check(H() == 26, "right-click on the bar does nothing")
W.Slash("/cqt")
W.Check(H() == CONTENT, "/cqt restores")
f.header:Hide()

print("Reload while minimised")
btn:Click()
f.scroll:Show(); f:SetHeight(CONTENT) -- a fresh UI
A.hooked = nil
Load()
W.Check(H() == 28 and not f.scroll:IsShown(), "still minimised after reload")
W.Check(pcall(W.Slash, "/cqt debug"), "/cqt debug runs")
W.Check(pcall(W.Slash, "/cqt mouse"), "/cqt mouse runs")

W.Done()
