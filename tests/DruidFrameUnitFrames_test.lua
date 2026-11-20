-- DruidFrame's Target and Tank's Target frames (DruidFrame/UnitFrames.lua; Target of Target has
-- its own test): raid icons, the elite dragon, the tank found by role, and hiding.
-- Run from the repo root: lua5.1 tests/DruidFrameUnitFrames_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

W.spellCosts[768] = { { type = 0, name = "MANA", cost = 100 } }
local ns = {}
for _, file in ipairs({ "DruidBar.lua", "Resource.lua", "Buffs.lua", "DruidRange.lua", "UnitFrames.lua", "Options.lua" }) do
    W.Load("DruidFrame/" .. file, "DruidFrame", ns)
end
W.class, W.powerType, W.formID = "DRUID", 0, nil
W.Fire("PLAYER_LOGIN")
W.Fire("PLAYER_ENTERING_WORLD")

local target, tank = _G.DruidFrameTarget, _G.DruidFrameTankTarget
local T, K = ns.Target, ns.TankTarget

print("Target frame")
W.Check(target and target:GetAttribute("unit") == "target" and target:GetAttribute("type1") == "target", "a secure button for your target")
W.target = false
W.Fire("PLAYER_TARGET_CHANGED")
W.Check(not target:IsShown(), "no target: hidden")
W.target, W.enemy, W.tot = true, true, "player"
W.Fire("PLAYER_TARGET_CHANGED")
W.Advance(0.2)
W.Check(target:IsShown() and T.name._text == "target", "shown, with the name (got " .. tostring(T.name._text) .. ")")
W.Check(not T.raidIcon:IsShown() and not T.elite:IsShown(), "no raid icon, not elite")
W.raidIcons.target = 8
W.classification.target = "elite"
W.Fire("RAID_TARGET_UPDATE")
W.Check(T.raidIcon:IsShown() and T.raidIcon._raidIcon == 8, "skull shown")
W.Check(T.elite:IsShown() and T.elite._atlas == "nameplates-icon-elite-gold", "gold elite dragon")
W.classification.target = "rare"
W.Fire("UNIT_CLASSIFICATION_CHANGED", "target")
W.Check(T.elite._atlas == "nameplates-icon-elite-silver", "silver for rares")
W.Check(T.elite:GetLeft() >= target:GetRight() - 0.5, "just past the bar's right end")
W.Near(select(1, T.raidIcon:GetCenter()), select(1, target:GetCenter()), "raid icon centred over the frame")
W.Check(target:GetTop() > _G.DruidFrameTargetOfTarget:GetTop(), "above Target of Target by default")

print("Tank's target")
W.Check(not tank:IsShown(), "solo: hidden")
W.grouped = true
W.party = { party1 = "Healer", party2 = "Warrior" }
W.roles = { party1 = "HEALER", party2 = "TANK" }
W.partyTargets = { party2 = "Gnoll" }
W.targetName = "Other"
W.Fire("GROUP_ROSTER_UPDATE")
W.Advance(0.2)
W.Check(tank:GetAttribute("unit") == "party2target", "follows the member with the Tank role (got " .. tostring(tank:GetAttribute("unit")) .. ")")
W.Check(tank:IsShown() and tank:GetAlpha() == 1, "shown while it targets something else")
W.Check(tank:GetAttribute("type1") == "target", "clicking it (or /click DruidFrameTankTarget) targets it")
W.targetName = "Gnoll"
W.Advance(0.2)
W.Check(tank:GetAlpha() == 0, "you're targeting the same mob: transparent")
W.targetName = "Other"
W.Advance(0.2)
W.Check(tank:GetAlpha() == 1, "different again: back")
W.targetName = "Warrior"
W.Advance(0.2)
W.Check(tank:GetAlpha() == 0, "targeting the tank: transparent (Target of Target shows it)")
W.targetName = "Other"
W.Advance(0.2)
W.roles.player = "TANK"
W.Fire("PLAYER_ROLES_ASSIGNED")
W.Check(not tank:IsShown(), "you're the tank: hidden")
W.roles.player = nil
W.roles.party2 = "DAMAGER"
W.Fire("PLAYER_ROLES_ASSIGNED")
W.Check(not tank:IsShown(), "no one has the Tank role: hidden")
W.Check(tank:GetAttribute("type1") == nil, "and /click or its key does nothing then")
W.roles.party2 = "TANK"
W.Fire("PLAYER_ROLES_ASSIGNED")
W.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
local ok = pcall(function()
    W.roles = { party1 = "TANK" }
    W.partyTargets = { party1 = "Kobold" }
    W.Fire("GROUP_ROSTER_UPDATE")
end)
W.Check(ok, "tank changes in combat: no protected calls")
W.Check(tank:GetAttribute("unit") == "party2target", "the switch waits")
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
W.Check(tank:GetAttribute("unit") == "party1target", "and happens once combat ends")

print("Options and commands")
local opened
local realOpen = Settings.OpenToCategory
Settings.OpenToCategory = function(id) opened = id end
W.Slash("/druidtarget")
W.Check(opened == "Target", "/druidtarget opens its page")
W.Slash("/druidtank")
W.Check(opened == "Tank's Target", "/druidtank opens its page")
Settings.OpenToCategory = realOpen
W.Check(pcall(W.Slash, "/druidtarget debug") and pcall(W.Slash, "/druidtank debug"), "debug commands run")
ns.panels.target:GetScript("OnShow")(ns.panels.target)
W.Check(target:IsShown() and tank:IsShown(), "options open: all frames shown to place")
ns.panels.target:GetScript("OnHide")(ns.panels.target)

W.Done()
