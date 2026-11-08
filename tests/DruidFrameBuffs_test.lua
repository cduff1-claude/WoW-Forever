-- DruidFrame's buff reminders (DruidFrame/Buffs.lua): Mark of the Wild to the left of the
-- display and Thorns to the right while missing, checked only out of combat.
-- Run from the repo root: lua5.1 tests/DruidFrameBuffs_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

W.spellCosts[768] = { { type = 0, name = "MANA", cost = 100 } }
W.power[4], W.powerMax[4] = 0, 5

local auras = {}
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
    if auras[id] then return { spellId = id } end
end
local learned = { [1126] = true, [467] = true }
IsPlayerSpell = function(id) return learned[id] or false end
IsSpellKnown = IsPlayerSpell

local ns = {}
for _, file in ipairs({ "DruidBar.lua", "Resource.lua", "Buffs.lua", "DruidRange.lua", "Options.lua" }) do
    W.Load("DruidFrame/" .. file, "DruidFrame", ns)
end
W.class, W.powerType, W.formID = "DRUID", 0, nil
W.Fire("PLAYER_LOGIN")
W.Fire("PLAYER_ENTERING_WORLD")

local R = ns.Resource
local s = R.Settings()
local mark, thorns = _G.DruidFrameMarkButton, _G.DruidFrameThornsButton

print("Neither buff up")
W.Check(s.buffButtons == true, "on by default")
W.Check(mark and thorns, "both buttons made, with the names macros can use")
W.Check(mark:IsShown() and thorns:IsShown(), "both shown")
W.Check(mark:GetAttribute("type") == "macro" and mark:GetAttribute("macrotext"):find("Mark of the Wild", 1, true),
    "Mark of the Wild button casts it")
W.Check(thorns:GetAttribute("macrotext"):find("@player", 1, true), "on yourself")
local tall = R.health:GetTop() - R.mana:GetBottom()
W.Near(mark:GetHeight(), tall, "as tall as health + mana + the gap between them")
W.Near(mark:GetWidth(), tall, "and square")
W.Near(mark:GetTop(), R.health:GetTop(), "level with the health bar's top")
W.Check(mark:GetRight() < R.health:GetLeft(), "Mark of the Wild on the left")
W.Check(thorns:GetLeft() > R.health:GetRight(), "Thorns on the right")
W.Near(R.health:GetLeft() - mark:GetRight(), s.padding + 1, "a padding's gap from the bars")

print("Glow while missing, out of combat")
local function Glowing(b) return b.glow and b.glow.frame:IsShown() end
W.Check(Glowing(mark) and Glowing(thorns), "both glow")
W.Fire("PLAYER_REGEN_DISABLED")
W.Check(not Glowing(mark) and not Glowing(thorns), "combat: no glow")
W.Fire("PLAYER_REGEN_ENABLED")
W.Check(Glowing(mark), "out of combat again: glowing")

print("Clicking: fades out")
mark:GetScript("PostClick")(mark, "LeftButton", false)
W.Advance(0.25)
W.Check(mark:GetAlpha() < 1 and mark:GetAlpha() > 0, "fading")
auras[1126] = true
W.Fire("UNIT_AURA", "player")
W.Advance(0.4)
W.Check(not mark:IsShown(), "gone once faded, now the buff is up")
W.Check(thorns:IsShown(), "Thorns still waiting")

print("A click that didn't land")
thorns:GetScript("PostClick")(thorns, "LeftButton", false)
W.Advance(0.6)
W.Check(thorns:IsShown() and thorns:GetAlpha() == 1, "Thorns still missing: back after the fade")
auras[467] = true
W.Fire("UNIT_AURA", "player")
W.Check(not thorns:IsShown(), "Thorns up: hidden")

print("Only out of combat")
W.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
auras[467] = nil
W.Fire("UNIT_AURA", "player")
W.Check(not thorns:IsShown(), "Thorns drops in combat: nothing changes")
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
W.Check(thorns:IsShown(), "after combat: Thorns button")

print("Gift of the Wild counts; unlearned spells don't show")
auras[1126] = nil
auras[21849] = true
W.Fire("UNIT_AURA", "player")
W.Check(not mark:IsShown(), "Gift of the Wild: no Mark of the Wild button")
learned[467] = nil
W.Fire("SPELLS_CHANGED")
W.Check(not thorns:IsShown(), "Thorns not learned: no button")
learned[467] = true

print("Unlocked: both shown so you can see where they go")
ns.panels.frame:GetScript("OnShow")(ns.panels.frame)
W.Check(mark:IsShown() and thorns:IsShown(), "both shown while the options are open")
W.Check(not Glowing(mark), "no glow on the preview")
local before = mark:GetTop()
_G.DruidBarResourceHealthHeight:GetScript("OnValueChanged")(_G.DruidBarResourceHealthHeight, 24)
W.Near(mark:GetHeight(), R.health:GetTop() - R.mana:GetBottom(), "follows the bars' height")
ns.panels.frame:GetScript("OnHide")(ns.panels.frame)
W.Check(not mark:IsShown() and thorns:IsShown(), "closed: back to just what's missing")

print("Battlegrounds and arenas")
local instance = "pvp"
IsInInstance = function() return instance ~= "none", instance end
W.Check(s.buffButtonsPvP == false, "off there by default")
W.Fire("ZONE_CHANGED_NEW_AREA")
W.Check(not mark:IsShown() and not thorns:IsShown(), "battleground: no buttons")
instance = "arena"
W.Fire("ZONE_CHANGED_NEW_AREA")
W.Check(not thorns:IsShown(), "arena: no buttons")
_G.DruidBarResourceBuffsPvP:SetChecked(true)
_G.DruidBarResourceBuffsPvP:Click()
W.Check(s.buffButtonsPvP == true and thorns:IsShown(), "ticked: shown there too")
_G.DruidBarResourceBuffsPvP:SetChecked(false)
_G.DruidBarResourceBuffsPvP:Click()
W.Check(s.buffButtonsPvP == false and not thorns:IsShown(), "unticked: hidden again")
instance = "party"
W.Fire("ZONE_CHANGED_NEW_AREA")
W.Check(thorns:IsShown(), "dungeon: shown")
instance = "none"
W.Fire("ZONE_CHANGED_NEW_AREA")

print("Option off")
s.buffButtons = false
R.Refresh()
W.Check(not mark:IsShown() and not thorns:IsShown(), "no buttons")
s.buffButtons = true
R.Refresh()
W.Check(thorns:IsShown(), "on again")
local ok = pcall(W.Slash, "/druidframe buffs")
W.Check(ok, "/druidframe buffs runs without errors")

W.Done()
