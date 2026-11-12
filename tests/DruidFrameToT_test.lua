-- DruidFrame's target of target (DruidFrame/ToT.lua): showing with the game's state driver,
-- name and "You", the aggro border, unlocking, dragging and its options page.
-- Run from the repo root: lua5.1 tests/DruidFrameToT_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

W.spellCosts[768] = { { type = 0, name = "MANA", cost = 100 } }
local ns = {}
for _, file in ipairs({ "DruidBar.lua", "Resource.lua", "Buffs.lua", "DruidRange.lua", "ToT.lua", "Options.lua" }) do
    W.Load("DruidFrame/" .. file, "DruidFrame", ns)
end
W.class, W.powerType, W.formID = "DRUID", 0, nil
W.health, W.healthMax = 800, 1000
W.Fire("PLAYER_LOGIN")
W.Fire("PLAYER_ENTERING_WORLD")

local T = ns.ToT
local f = _G.DruidFrameTargetOfTarget
local s = T.Settings()

print("Showing")
W.Check(f ~= nil and f:GetAttribute("unit") == "targettarget" and f:GetAttribute("type1") == "target",
    "a secure button that targets the target of target")
W.Check(s.totEnabled and s.totShow == "always" and s.totAggro, "defaults: on, whenever there's one, aggro border")
W.Check(not f:IsShown(), "no target: hidden")
W.target, W.enemy, W.tot = true, true, "player"
W.Fire("PLAYER_TARGET_CHANGED")
W.Advance(0.2)
W.Check(f:IsShown(), "enemy targeting you: shown")
W.Check(T.name._text == "You", "says You (got " .. tostring(T.name._text) .. ")")
W.Check(T.ring:GetLeft() > ns.Resource.health:GetRight(), "starts to the right of DruidFrame, portrait and all")

print("Portrait")
W.Check(s.totPortrait == "circle", "circle by default")
W.Check(T.portrait._masks and next(T.portrait._masks) ~= nil, "cut to a circle")
W.Check(T.portrait:IsShown() and T.portrait._portrait == "Roam", "your portrait while it's on you (got " .. tostring(T.portrait._portrait) .. ")")
W.Check(T.ring:GetRight() > f:GetLeft() and T.ring:GetLeft() < f:GetLeft(), "round, overhanging the bar's left end")
W.Near(T.ring:GetHeight(), s.totHeight + 14, "a bit taller than the bar")
W.tot = "party1"
W.Fire("UNIT_TARGET", "target")
W.Check(T.portrait._portrait == "party1", "changes with the target of target")
W.tot = "player"
W.Fire("UNIT_TARGET", "target")
_G.DruidFrameToTPortrait:Click()
W.Check(s.totPortrait == "square" and T.portrait:IsShown() and not next(T.portrait._masks), "Square: shown, no round mask")
_G.DruidFrameToTPortrait:Click()
W.Check(s.totPortrait == "none" and not T.portrait:IsShown() and not T.ring:IsShown(), "Off: no portrait")
_G.DruidFrameToTPortrait:Click()
W.Check(s.totPortrait == "circle" and T.portrait:IsShown() and next(T.portrait._masks) ~= nil, "back to Circle")

print("Aggro border")
local function Border() return { f:GetBackdropBorderColor() } end
local b = T.AggroColour()
W.Check(b and b[1] > 0.9 and b[2] < 0.2, "caster form, on you: red (you pulled it)")
W.powerType, W.formID = 1, 5
W.Fire("UPDATE_SHAPESHIFT_FORM")
b = T.AggroColour()
W.Check(b and b[2] > 0.8, "Bear Form, on you: green")
W.tot = "party1"
W.Fire("UNIT_TARGET", "target")
b = T.AggroColour()
W.Check(b and b[1] > 0.9 and b[2] < 0.2, "Bear Form, on a party member: red (lost it)")
W.Advance(0.2)
W.Check(T.name._text == "party1", "shows their name")
W.tot = "Mob"
W.Fire("UNIT_TARGET", "target")
W.Check(T.AggroColour() == nil, "on another NPC: no border")
W.enemy = false
W.tot = "player"
W.Fire("UNIT_TARGET", "target")
W.Check(T.AggroColour() == nil, "friendly target: no border")
W.enemy = true
W.powerType, W.formID = 0, nil
W.Fire("UPDATE_SHAPESHIFT_FORM")

print("In combat only")
s.totShow = "combat"
T.ApplyVisibility()
W.Check(not f:IsShown(), "out of combat: hidden")
W.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
W.Check(f:IsShown(), "in combat: shown")
local ok = pcall(function()
    W.tot = nil
    W.Fire("UNIT_TARGET", "target")
    T.SetUnlocked(false)
end)
W.Check(ok and not f:IsShown(), "no protected calls in combat, and the game hides it when there's no one")
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
s.totShow = "always"
T.ApplyVisibility()

print("Only when in a group")
W.Check(s.totGroup == false, "off by default")
W.tot = "player"
W.Fire("UNIT_TARGET", "target")
_G.DruidFrameToTGroup:SetChecked(true)
_G.DruidFrameToTGroup:Click()
W.Check(s.totGroup and not f:IsShown(), "ticked, solo: hidden")
W.grouped = true
W.Fire("GROUP_ROSTER_UPDATE")
W.Check(f:IsShown(), "in a group: shown")
W.grouped = false
W.Fire("GROUP_ROSTER_UPDATE")
W.Check(not f:IsShown(), "left the group: hidden")
_G.DruidFrameToTGroup:SetChecked(false)
_G.DruidFrameToTGroup:Click()
W.Check(f:IsShown(), "unticked: shown solo")

print("Unlocked: preview and dragging")
W.tot = nil
W.Fire("UNIT_TARGET", "target")
ns.panels.tot:GetScript("OnShow")(ns.panels.tot)
W.Check(f:IsShown() and T.name._text == "Target of target", "options open: a preview shows")
W.Check(f:GetAttribute("type1") == nil, "and clicks don't target while unlocked")
local x, y = f:GetCenter()
W.cursor = { x, y }
f:GetScript("OnMouseDown")(f, "LeftButton")
W.cursor = { x + 50, y - 30 }
W.Advance(0.05)
f:GetScript("OnMouseUp")(f, "LeftButton")
local nx, ny = f:GetCenter()
W.Near(nx, x + 50, "dragged right")
W.Near(ny, y - 30, "and down")
W.Near(s.totX, x + 50, "position saved")
ns.panels.tot:GetScript("OnHide")(ns.panels.tot)
W.Check(not f:IsShown() and f:GetAttribute("type1") == "target", "closed: hidden again, targeting back")

print("Options and commands")
_G.DruidFrameToTWidth:GetScript("OnValueChanged")(_G.DruidFrameToTWidth, 200)
W.Near(f:GetWidth(), 200, "width slider")
_G.DruidFrameToTEnabled:SetChecked(false)
_G.DruidFrameToTEnabled:Click()
W.tot = "player"
W.Fire("UNIT_TARGET", "target")
W.Check(not f:IsShown(), "turned off: never shown")
_G.DruidFrameToTEnabled:SetChecked(true)
_G.DruidFrameToTEnabled:Click()
W.Check(f:IsShown(), "on again")
local opened
local realOpen = Settings.OpenToCategory
Settings.OpenToCategory = function(id) opened = id end
W.Slash("/druidtot")
W.Check(opened == "Target of Target", "/druidtot opens its page (got " .. tostring(opened) .. ")")
Settings.OpenToCategory = realOpen
W.Check(pcall(W.Slash, "/druidtot debug"), "/druidtot debug runs")

W.Done()
