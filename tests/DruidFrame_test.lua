-- DruidFrame's resource display (DruidFrame/Resource.lua): layout in each form, text, combo points, the
-- cast bar, visibility, dragging with "Keep centred", and DruidBar's overlays on its bars.
-- Run from the repo root: lua5.1 tests/DruidFrame_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

local HEALING_TOUCH = 5185
W.spellCosts[HEALING_TOUCH] = { { type = 0, name = "MANA", cost = 55 } }
W.spellCosts[768] = { { type = 0, name = "MANA", cost = 100 } }
W.spellCosts[5487] = { { type = 0, name = "MANA", cost = 100 } }
W.spellCosts[1082] = { { type = 3, name = "ENERGY", cost = 45 } }
W.spellCosts["Claw"] = W.spellCosts[1082]
W.power[4], W.powerMax[4] = 0, 5 -- combo points

local ns = {}
for _, file in ipairs({ "DruidBar.lua", "Resource.lua", "Buffs.lua", "DruidRange.lua", "Options.lua" }) do
    W.Load("DruidFrame/" .. file, "DruidFrame", ns)
end
local R = ns.Resource

W.class, W.powerType, W.formID = "DRUID", 0, nil
W.power[0], W.powerMax[0] = 847, 847
W.Fire("PLAYER_LOGIN")
W.Fire("PLAYER_ENTERING_WORLD")
local s = R.Settings()
local f = R.frame

local function Top(bar) return bar:GetTop() end
local function Shown(bar) return bar:IsShown() end

print("Defaults: flat style and the PRD's spacing")
W.Check(s.style == "flat", "flat style by default")
W.Near(s.padding, 4, "PRD-like gap between bars")
W.Check(R.health:GetStatusBarTexture():GetTexture() == "Interface\\Buttons\\WHITE8X8", "flat: plain fill texture")
W.Check(R.health.gloss:IsShown(), "flat: lighter top half shown")
W.Near(R.health.gloss:GetBottom(), (R.health:GetTop() + R.health:GetBottom()) / 2, "gloss covers the top half")

print("Caster form")
W.Check(f:IsShown(), "frame shown")
W.Near(Top(R.health), f:GetTop(), "health at the top")
W.Near(Top(R.mana), f:GetTop() - s.healthHeight - s.padding, "mana right below health")
W.Check(Shown(R.cast) and not Shown(R.power), "caster form: the cast row is held in place")
W.Check((R.cast.centre._text or "") == "" and R.cast:GetStatusBarTexture():GetWidth() == 0, "and empty until a spell goes off")
W.Check(R.cast:GetAlpha() == 0, "the empty row isn't drawn")
ns.panels.frame:GetScript("OnShow")(ns.panels.frame)
W.Check(R.cast:GetAlpha() == 1, "but shows while unlocked, so the layout can be seen")
ns.panels.frame:GetScript("OnHide")(ns.panels.frame)
W.Check(R.cast:GetAlpha() == 0, "and hides again when locked")
W.Check(not R.combo:IsShown(), "no combo points in caster form")
W.Near(R.health:GetWidth(), s.width, "health is the full width")
W.Near(R.mana:GetWidth(), s.width, "mana is the full width")
W.Near(f:GetHeight(), s.healthHeight + 2 * s.padding + 2 * s.powerHeight, "frame fits three rows")
W.Check(s.text == "centre", "text set to current, centred")
W.Check(R.health.centre._text == "989" and R.health.left._text == "" and R.health.right._text == "", "health: current, centred")
W.Check(R.mana.centre._text == "847", "mana: current, centred")
local healthTop, manaTop = Top(R.health), Top(R.mana)

local function Combat(on)
    W.combat = on
    W.Fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

print("Cat Form: energy below mana, combo points at the bottom")
W.powerType, W.formID = 3, 1
W.power[3], W.powerMax[3] = 100, 100
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.Near(Top(R.health), healthTop, "health hasn't moved")
W.Near(Top(R.mana), manaTop, "mana hasn't moved")
W.Check(Shown(R.power), "energy bar shown")
W.Near(Top(R.power), manaTop - s.powerHeight - s.padding, "energy right below mana")
W.Near(R.power:GetWidth(), s.width, "energy is the full width")
W.Check(R.power.centre._text == "100", "energy: current, centred")
W.Check(not R.combo:IsShown(), "out of combat: no combo points")
local bottomOOC = R.frame:GetBottom()
Combat(true)
W.Check(R.combo:IsShown(), "in combat: combo points shown")
W.Check(R.frame:GetBottom() < bottomOOC, "the frame grows down for them")
W.Near(Top(R.mana), manaTop, "mana still hasn't moved")
W.Check(R.combo:GetTop() < R.power:GetBottom(), "combo points below the energy bar")
W.Check(#R.comboPoints == 5, "five combo points")
W.power[4] = 3
W.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
local lit = 0
for _, point in ipairs(R.comboPoints) do
    if point.fill:GetStatusBarTexture():GetWidth() > 0 then lit = lit + 1 end
end
W.Check(lit == 3, "three combo points lit (got " .. lit .. ")")
local c = R.power:GetStatusBarTexture()._color
W.Check(c and c[1] == 0.95 and c[2] == 0.80 and c[3] == 0.18, "energy uses the warm gold")
local left, right = R.comboPoints[1]:GetLeft(), R.comboPoints[5]:GetRight()
W.Near((left + right) / 2, (f:GetLeft() + f:GetRight()) / 2, "combo points centred under the bars")

print("Claw orange on the energy bar")
local function Orange(bar)
    for _, t in ipairs(W.Textures(bar)) do
        local col = t._color
        if col and col[1] == 1 and col[2] == 0.5 and col[3] == 0 and col[4] == 0.9 then return t end
    end
end
W.Fire("SPELLS_CHANGED")
W.Advance(1.1)
W.power[3] = 20
W.Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
local orange = Orange(R.power)
W.Check(orange ~= nil, "Claw orange layer on the resource display's energy bar")
W.Near(orange and W.VisibleWidth(orange) or -1, 0.20 * s.width, "20 energy: the fill is orange", 0.01)
W.power[3] = 80
W.Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
W.Near(W.VisibleWidth(orange), 0, "80 energy: no orange")

print("Which ability the energy warning is for")
local db = DruidForeverManabarPlusDB
W.Check(db.energySpell == "claw" and db.finisherSpell == "bite" and db.openerSpell == "ravage", "defaults: Claw, Ferocious Bite, Ravage")
db.finisherSpell = "none"
W.spellCosts[5221] = { { type = 3, name = "ENERGY", cost = 60 } }  -- Shred
W.spellCosts[1079] = { { type = 3, name = "ENERGY", cost = 30 } }  -- Rip
W.spellCosts[22568] = { { type = 3, name = "ENERGY", cost = 35 } } -- Ferocious Bite
W.spellCosts[6785] = { { type = 3, name = "ENERGY", cost = 60 } }  -- Ravage
W.spellCosts[9005] = { { type = 3, name = "ENERGY", cost = 50 } }  -- Pounce
local learned = { [5221] = true, [1079] = true, [22568] = true, [6785] = true, [9005] = true, [1082] = true }
local realKnows = IsPlayerSpell
IsPlayerSpell = function(id) return learned[id] or false end
IsSpellKnown = IsPlayerSpell
-- All the orange showing (one layer for the ability, one for the finisher).
local function OrangeWidth()
    local total = 0
    for _, t in ipairs(W.Textures(R.power)) do
        local col = t._color
        if col and col[1] == 1 and col[2] == 0.5 and col[3] == 0 and col[4] == 0.9 then
            total = total + W.VisibleWidth(t)
        end
    end
    return total
end
local function Energy(value)
    W.power[3] = value
    W.Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
    return OrangeWidth()
end
local function Pick(name, key)
    W.Check(W.Pick(_G[name], key), "option " .. key .. " offered")
end
W.Fire("SPELLS_CHANGED")
W.power[4] = 0
W.Check(Energy(50) == 0, "Claw (45): 50 energy is enough")
Pick("DFMPEnergySpellDropdown", "shred")
W.Check(db.energySpell == "shred", "Shred picked from the options")
W.Check(Energy(50) > 0, "Shred (60): 50 energy is short")
W.Check(Energy(60) == 0, "Shred: 60 is enough")
learned[5221] = nil
W.Fire("SPELLS_CHANGED")
W.Check(Energy(50) == 0, "Shred not learned: falls back to Claw")
learned[5221] = true
W.Fire("SPELLS_CHANGED")

print("  ... full combo points: Rip or Ferocious Bite")
Pick("DFMPFinisherDropdown", "bite")
W.Check(db.finisherSpell == "bite", "Ferocious Bite picked")
W.power[4] = 4
W.Check(Energy(40) > 0, "4 combo points: still warns for Shred")
W.power[4] = 5
W.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
W.Check(OrangeWidth() == 0, "5 combo points: 40 is enough for Ferocious Bite (35)")
W.Check(Energy(30) > 0, "and 30 isn't")
db.finisherSpell = "rip"
learned[1079] = nil
W.Fire("SPELLS_CHANGED")
W.Check(Energy(50) > 0, "Rip not learned: no override, Shred's 60 still counts")
learned[1079] = true
W.Fire("SPELLS_CHANGED")
W.Check(Energy(30) == 0, "Rip learned: 30 is enough at full combo points")
W.power[4] = 0
W.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")

print("  ... in Prowl: Ravage or Pounce, with live costs")
local realStealth = IsStealthed
local stealthed = true
IsStealthed = function() return stealthed end
W.Fire("UPDATE_STEALTH")
W.Check(Energy(55) > 0, "Prowl: 55 is short of Ravage (60)")
W.spellCosts[6785][1].cost = 50 -- Forever: openers cost less at full energy in stealth
W.Fire("SPELL_UPDATE_USABLE")
W.Check(OrangeWidth() == 0, "a cheaper Ravage is picked up without any setting")
W.spellCosts[6785][1].cost = 60
Pick("DFMPOpenerDropdown", "pounce")
W.Check(db.openerSpell == "pounce" and Energy(55) == 0, "Pounce (50): 55 is enough")
Pick("DFMPOpenerDropdown", "none")
W.Check(db.openerSpell == "none" and Energy(55) > 0, "no override: back to Shred in Prowl")
db.openerSpell = "ravage"
stealthed = false
W.Fire("UPDATE_STEALTH")

print("  ... Clearcasting: back to plain yellow")
W.Check(Energy(20) > 0, "20 energy: orange")
local realAura = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id) if id == 16870 then return { spellId = 16870 } end end
W.Fire("UNIT_AURA", "player")
W.Check(OrangeWidth() == 0, "Clearcasting up: no orange")
C_UnitAuras.GetPlayerAuraBySpellID = realAura
W.Fire("UNIT_AURA", "player")
W.Check(OrangeWidth() > 0, "spent: orange again")
IsPlayerSpell, IsSpellKnown, IsStealthed = realKnows, realKnows, realStealth
db.energySpell, db.finisherSpell = "claw", "none"
W.Fire("SPELLS_CHANGED")
W.Check(Energy(80) == 0, "back to Claw: 80 is enough")

Combat(false)
W.Check(not R.combo:IsShown(), "combat over: combo points gone")
ns.panels.frame:GetScript("OnShow")(ns.panels.frame)
W.Check(R.combo:IsShown(), "shown while the options are open, to see the layout")
ns.panels.frame:GetScript("OnHide")(ns.panels.frame)
W.Check(not R.combo:IsShown(), "and gone again when they close")

print("Bear Form: rage below mana, no combo points")
W.powerType, W.formID = 1, 5
W.power[1], W.powerMax[1] = 10, 100
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.Near(Top(R.mana), manaTop, "mana still hasn't moved")
W.Check(Shown(R.power) and R.power.centre._text == "10", "rage bar shows 10")
W.Check(not R.combo:IsShown(), "no combo points in Bear")
c = R.power:GetStatusBarTexture()._color
W.Check(c and c[1] == 0.75 and c[2] == 0, "rage uses the darker red")

print("Bear Form: rage orange below Swipe's cost, in combat only")
W.spellCosts[779] = { { type = 1, name = "RAGE", cost = 20 } } -- Swipe
W.Fire("SPELLS_CHANGED")
W.Advance(1.1)
local function RageOrange()
    local total = 0
    for _, t in ipairs(W.Textures(R.power)) do
        local col = t._color
        if col and col[1] == 1 and col[2] == 0.5 and col[3] == 0 and col[4] == 0.9 then
            total = total + W.VisibleWidth(t)
        end
    end
    return total
end
W.Check(DruidForeverManabarPlusDB.rageShade == true, "on by default")
W.Check(RageOrange() == 0, "out of combat at 10 rage: still plain red")
W.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
W.Near(RageOrange(), 0.10 * s.width, "in combat at 10 rage: orange (Swipe costs 20)", 0.01)
W.power[1] = 25
W.Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
W.Check(RageOrange() == 0, "25 rage: enough for Swipe")
W.power[1] = 5
W.Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
W.Check(RageOrange() > 0, "5 rage: orange again")
DruidForeverManabarPlusDB.rageShade = false
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.Check(RageOrange() == 0, "option off: no orange")
DruidForeverManabarPlusDB.rageShade = true
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
W.Check(RageOrange() == 0, "combat over: plain red")
W.power[1] = 10

print("Incoming heals on the health bar")
local savedHealth, savedMax = W.health, W.healthMax
W.health, W.healthMax = 600, 1000
W.incomingHeals = 200
W.Fire("UNIT_HEAL_PREDICTION", "player")
local hr, hg, hb = R.heal:GetStatusBarColor()
W.Check(hr == 0.0 and hg == 0.63 and hb == 0.56, "teal")
W.Near(R.heal:GetLeft(), R.health:GetLeft() + 0.6 * s.width, "starts where the health ends")
W.Near(W.VisibleWidth(R.heal:GetStatusBarTexture()), 0.2 * s.width, "as long as the heals", 0.5)
W.incomingHeals = 800
W.Fire("UNIT_HEAL_PREDICTION", "player")
W.Near(W.VisibleWidth(R.heal:GetStatusBarTexture()), 0.4 * s.width, "clipped at the end of the bar", 0.5)
W.incomingHeals = nil
W.Fire("UNIT_HEAL_PREDICTION", "player")
W.Near(W.VisibleWidth(R.heal:GetStatusBarTexture()), 0, "no heals: nothing")
W.health, W.healthMax = savedHealth, savedMax
W.Fire("UNIT_HEALTH", "player")

print("Caster form: cast bar while casting")
W.powerType, W.formID = 0, nil
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.casting = { name = "Healing Touch", startMS = W.time * 1000, endMS = W.time * 1000 + 2000 }
W.Fire("UNIT_SPELLCAST_START", "player", "cast-1", HEALING_TOUCH)
W.Check(Shown(R.cast), "cast bar shown while casting")
W.Near(Top(R.cast), manaTop - s.powerHeight - s.padding, "cast bar where energy/rage go")
W.Near(R.cast:GetWidth(), s.width, "cast bar is the full width")
W.Check(R.cast.centre._text == "Healing Touch (55)", "spell name and mana cost, centred (got " .. tostring(R.cast.centre._text) .. ")")
W.Check(select(1, R.cast.centre:GetPoint()) == "CENTER", "cast text anchored in the centre")
W.Check(R.cast.left._text == "" and R.cast.right._text == "", "nothing at the sides")
W.Check(R.cast.spark:IsShown(), "spark shown while casting")
W.Advance(1.0)
W.Near(R.cast:GetStatusBarTexture():GetWidth(), 0.5 * s.width, "half full after 1 of 2 seconds", 1)
local sx = R.cast.spark:GetCenter()
W.Near(sx, R.cast:GetLeft() + 0.5 * s.width, "spark rides the fill's edge", 1)

print("Energy in caster form (Never / In combat / Always)")
W.Check(s.casterEnergy == "combat", "default: in combat")
W.Check(not Shown(R.power), "caster form, out of combat: no energy bar")
W.power[3], W.powerMax[3] = 40, 100
W.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
W.Check(Shown(R.power) and R.power:GetValue() == 40, "in combat: energy bar shown")
local er, eg = R.power:GetStatusBarColor()
W.Check(er == 0.95 and eg == 0.80, "in the energy colour")
W.Check(R.power:GetTop() > R.cast:GetTop(), "above the cast bar row")
W.Near(R.power:GetTop(), R.mana:GetBottom() - s.padding, "right under the mana bar")
W.power[3] = 55
W.Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
W.Check(R.power:GetValue() == 55, "follows energy regen")
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
W.Check(not Shown(R.power), "combat over: gone")
W.Check(W.Pick(_G.DruidBarResourceCasterEnergy, "always") and s.casterEnergy == "always", "Always picked")
W.Check(Shown(R.power), "always: shown out of combat")
W.Check(W.Pick(_G.DruidBarResourceCasterEnergy, "never"), "Never picked")
W.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
W.Check(not Shown(R.power), "never: not even in combat")
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
s.casterEnergy = "combat"
local cr, cg, cb = R.cast:GetStatusBarColor()
W.Check(cr == 0.6 and cg == 0.2 and cb == 0.9, "cast bar is the range bar's purple")

print("Spell goes off: name and cost stay for 3 seconds, then fade")
local plays = R.cast.flashAnim._plays
W.casting = nil
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", HEALING_TOUCH)
W.Fire("UNIT_SPELLCAST_STOP", "player", "cast-1", HEALING_TOUCH)
W.Check(Shown(R.cast) and R.cast.centre._text == "Healing Touch (55)", "name and cost still showing after the cast")
W.Near(R.cast:GetStatusBarTexture():GetWidth(), s.width, "bar shown full")
W.Check(R.cast.flashAnim._plays == plays + 1, "finish flash played")
W.Check(not R.cast.spark:IsShown(), "spark gone")
W.Advance(2.9)
W.Check(R.cast.centre:GetAlpha() == 1, "still fully shown just before 3 seconds")
W.Advance(0.35)
W.Check(R.cast.centre._alpha and R.cast.centre._alpha < 1 and R.cast.centre._alpha > 0, "name fading after 3 seconds")
W.Check(R.cast:GetAlpha() == 1, "the bar itself still fully shown")
W.Advance(0.4)
W.Check(R.cast.centre:GetAlpha() == 0, "name gone")
W.Check(R.cast:GetAlpha() < 1 and R.cast:GetAlpha() > 0, "then the bar fades (got " .. R.cast:GetAlpha() .. ")")
W.Advance(0.4)
W.Check(R.cast.centre._text == "" and R.linger == nil, "gone after the fade")
W.Check(R.cast:GetAlpha() == 0, "bar no longer drawn")
W.Check(Shown(R.cast), "row stays in place")
W.Near(f:GetHeight(), s.healthHeight + 2 * s.padding + 2 * s.powerHeight, "frame still three rows")

print("Instant spells, replacing, shifting, interrupts, channels")
local REJUV = 774
W.spellCosts[REJUV] = { { type = 0, name = "MANA", cost = 25 } }
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "instant-1", REJUV)
W.Check(R.cast.centre._text == "Spell 774 (25)", "instant spell shown with its cost (got " .. tostring(R.cast.centre._text) .. ")")
W.Advance(2)
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "instant-2", HEALING_TOUCH)
W.Check(R.cast.centre._text == "Spell 5185 (55)", "a new spell replaces it")
W.Advance(2.9)
W.Check(R.cast.centre._text ~= "", "and gets its own 3 seconds")
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "instant-3", REJUV)
W.powerType, W.formID = 3, 1
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.powerType, W.formID = 0, nil
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.Check(R.cast.centre._text == "" and R.linger == nil, "shifting forms clears it")
W.casting = { name = "Healing Touch", startMS = W.time * 1000, endMS = W.time * 1000 + 2000 }
W.Fire("UNIT_SPELLCAST_START", "player", "cast-5", HEALING_TOUCH)
W.casting = nil
W.Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-5", HEALING_TOUCH)
W.Check(R.cast.centre._text == "" and R.linger == nil, "interrupted: nothing lingers")
W.channel = { name = "Tranquility", startMS = W.time * 1000, endMS = W.time * 1000 + 3000 }
W.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "chan-1", 740)
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "chan-1", 740) -- channels report this at the start
W.Check(R.casting and R.casting.channel, "still channelling after its SUCCEEDED")
W.Advance(1.5)
W.Near(R.cast:GetStatusBarTexture():GetWidth(), 0.5 * s.width, "channel drains: half left at halfway", 1)
W.channel = nil
W.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "chan-1", 740)
W.Check(R.cast.centre._text == "Tranquility", "channel's name lingers after it ends")
s.castLinger = false
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "instant-4", REJUV)
W.Check(R.cast.centre._text == "", "linger option off: nothing shown after a spell")
s.castLinger = true
s.castLocked = false
R.ClearCast()
W.Check(not Shown(R.cast), "row not held in place with that option off")
W.Near(f:GetHeight(), s.healthHeight + s.padding + s.powerHeight, "frame back to two rows")
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "instant-5", REJUV)
W.Check(Shown(R.cast), "but appears for a lingering instant")
W.Advance(4.1)
W.Check(not Shown(R.cast), "and goes when it fades")
s.castLocked = true
R.Refresh()

print("Cat Form: casts with a cast time (skinning, opening) show too")
W.powerType, W.formID = 3, 1
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.Check(not Shown(R.cast), "no cast row in Cat Form normally")
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "claw-1", 1082)
W.Check(not Shown(R.cast), "instant abilities (Claw) don't show")
W.casting = { name = "Skinning", startMS = W.time * 1000, endMS = W.time * 1000 + 2000 }
W.Fire("UNIT_SPELLCAST_START", "player", "skin-1", 8613)
W.Check(Shown(R.cast) and R.cast.centre._text == "Skinning", "skinning shows (got " .. tostring(R.cast.centre._text) .. ")")
W.Check(R.cast:GetTop() < R.power:GetBottom(), "below the energy bar")
W.Advance(2)
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "skin-1", 8613)
W.casting = nil
W.Fire("UNIT_SPELLCAST_STOP", "player", "skin-1", 8613)
W.Check(Shown(R.cast) and R.cast.centre._text == "Skinning", "lingers after it finishes")
W.Advance(4.1)
W.Check(not Shown(R.cast), "then goes")
W.powerType, W.formID = 0, nil
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
s.castBar = false
W.casting = { name = "Healing Touch", startMS = W.time * 1000, endMS = W.time * 1000 + 2000 }
W.Fire("UNIT_SPELLCAST_START", "player", "cast-2", HEALING_TOUCH)
W.Check(not Shown(R.cast), "no cast bar with the option off")
W.casting = nil
W.Fire("UNIT_SPELLCAST_STOP", "player", "cast-2", HEALING_TOUCH)
s.castBar = true

print("5-second-rule marker on the mana bar")
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", HEALING_TOUCH)
W.Advance(0.1)
local marker
for _, child in ipairs(R.mana._children) do
    for _, region in ipairs(child._regions) do
        local col = region._color
        if col and col[1] == 1 and col[2] == 1 and col[3] == 1 and col[4] == 0.95 and child:IsShown() then marker = region end
    end
end
W.Check(marker ~= nil, "marker on the resource display's mana bar")

print("Text options")
s.text = "values"
R.Refresh()
W.Check(R.health.left._text == "989" and R.health.right._text == "989", "values: current left, max right")
W.Near(select(4, R.health.left:GetPoint()), 4, "current indented from the left")
W.Near(select(4, R.health.right:GetPoint()), -4, "max indented from the right")
s.text = "percent"
CurveConstants = { ScaleTo100 = 1 }
UnitHealthPercent = function() return 52 end
UnitPowerPercent = function() return 75 end
R.Refresh()
W.Check(R.health.left._text == "52%" and R.health.right._text == "", "percent: health 52%")
W.Check(R.mana.left._text == "75%", "percent: mana 75%")
s.text = "both"
R.Refresh()
W.Check(R.health.left._text == "989" and R.health.right._text == "52%", "both: current left, percent right")
s.text = "current"
R.Refresh()
W.Check(R.health.left._text == "989" and R.health.right._text == "", "current: no max")
s.text = "none"
R.Refresh()
W.Check(R.health.left._text == "" and R.health.right._text == "", "none: no text")
s.text = "centre"
R.Refresh()

print("Visibility")
s.visibility = "combat"
R.Refresh()
W.Check(not f:IsShown(), "in-combat mode: hidden out of combat")
W.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
W.Check(f:IsShown(), "shown when combat starts")
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", HEALING_TOUCH)
W.Advance(0.1)
local markerNow
for _, child in ipairs(R.mana._children) do
    for _, region in ipairs(child._regions) do
        local col = region._color
        if col and col[4] == 0.95 and col[1] == 1 and child:IsShown() then markerNow = true end
    end
end
W.Check(markerNow, "overlays follow the frame when it appears in combat")
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
W.Check(not f:IsShown(), "hidden when combat ends")
s.visibility = "combatOrTarget"
W.target = true
W.Fire("PLAYER_TARGET_CHANGED")
W.Check(f:IsShown(), "combat-or-target mode: shown with a target")
W.target = false
W.Fire("PLAYER_TARGET_CHANGED")
W.Check(not f:IsShown(), "hidden without one")
s.visibility = "hidden"
R.panel:GetScript("OnShow")(R.panel)
W.Check(f:IsShown(), "shown while the options are open, even when set to hidden (so you can place it)")
R.panel:GetScript("OnHide")(R.panel)
W.Check(not f:IsShown(), "hidden again when the options close")
s.visibility = "always"
R.Refresh()
W.Check(f:IsShown(), "always mode: shown")

print("Dragging with Keep centred")
W.Check(not R.unlocked, "locked while the options are closed")
f:GetScript("OnMouseDown")(f, "LeftButton")
W.Check(R.drag == nil, "left-drag does nothing while locked")
f:GetScript("OnMouseUp")(f, "LeftButton")
R.panel:GetScript("OnShow")(R.panel)
W.Check(R.unlocked and R.unlockTint:IsShown(), "opening the options unlocks it (highlighted)")
local centreX = UIParent:GetWidth() / 2
W.Near((f:GetLeft() + f:GetRight()) / 2, centreX, "starts centred")
local startTop = f:GetTop()
W.cursor = { centreX + 20, startTop - 10 }
f:GetScript("OnMouseDown")(f, "LeftButton")
W.Check(R.guide:IsShown(), "red centre line shown while dragging")
W.cursor = { centreX + 320, startTop - 90 } -- wanders right as well as down
W.Advance(0.05)
f:GetScript("OnMouseUp")(f, "LeftButton")
W.Near((f:GetLeft() + f:GetRight()) / 2, centreX, "still centred after a sideways wobble")
W.Near(f:GetTop(), startTop - 80, "moved down with the mouse")
W.Check(not R.guide:IsShown(), "centre line gone after the drag")
W.Near(s.y, startTop - 80, "position saved")

print("Dragging without Keep centred")
s.keepCentred = false
local before = (f:GetLeft() + f:GetRight()) / 2
W.cursor = { before, f:GetTop() - 5 }
f:GetScript("OnMouseDown")(f, "LeftButton")
W.Check(not R.guide:IsShown(), "no centre line")
W.cursor = { before - 200, f:GetTop() - 5 }
W.Advance(0.05)
f:GetScript("OnMouseUp")(f, "LeftButton")
W.Near((f:GetLeft() + f:GetRight()) / 2, before - 200, "moves sideways freely")
R.ResetPosition()
local dx, dy = R.DefaultPosition()
W.Near(f:GetTop(), dy, "reset puts it back at the default height")
s.keepCentred = true
R.panel:GetScript("OnHide")(R.panel)
W.Check(not R.unlocked and not R.unlockTint:IsShown(), "closing the options locks it")

print("Right-click opens the options")
local opened = 0
local realOpen = Settings.OpenToCategory
Settings.OpenToCategory = function() opened = opened + 1 end
local fx, fy = f:GetCenter()
W.cursor = { fx, fy }
f:GetScript("OnMouseDown")(f, "RightButton")
f:GetScript("OnMouseUp")(f, "RightButton")
W.Check(opened == 1, "right-click opens the options")
f:GetScript("OnMouseDown")(f, "RightButton")
W.cursor = { fx + 40, fy }
f:GetScript("OnMouseUp")(f, "RightButton")
W.Check(opened == 1, "right-drag (turning the camera) doesn't")
Settings.OpenToCategory = realOpen
W.Check(DruidForeverManabarPlusDB.resource.unlocked == nil, "unlocked isn't saved")

print("Omen of Clarity glow")
local auraUp = false
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
    if id == 16870 and auraUp then return { spellId = 16870 } end
end
local function Glowing(bar) return bar.procGlow.frame:IsShown() and bar.procGlow.pulse:IsPlaying() end
W.powerType, W.formID = 3, 1
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.Check(not Glowing(R.mana) and not Glowing(R.power), "no glow without the proc")
auraUp = true
W.Fire("UNIT_AURA", "player")
W.Check(Glowing(R.mana) and Glowing(R.power), "proc: mana and energy bars glow (aura seen)")
local glowFlash = R.mana.procGlow.flash
W.Near(glowFlash:GetWidth(), R.mana:GetWidth(), "flash covers the bar")
auraUp = false
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "claw-1", 1082)
W.Check(not Glowing(R.mana) and not Glowing(R.power), "proc spent: glow stops at once")
print("  ... when the client hides the aura in combat, via spell costs")
C_UnitAuras.GetPlayerAuraBySpellID = function() error("Auras cannot be accessed when secret") end
W.Fire("UNIT_AURA", "player")
W.Check(not Glowing(R.power), "normal costs: no glow")
W.spellCosts["Claw"] = { { type = 3, name = "ENERGY", cost = 0 } }
W.Fire("UNIT_AURA", "player")
W.Check(Glowing(R.power), "Claw suddenly free: glow")
local active, how = R.ClearcastingActive()
W.Check(how == "cost of Claw", "told by Claw's cost (got " .. tostring(how) .. ")")
W.spellCosts["Claw"] = W.spellCosts[1082]
W.Fire("SPELL_UPDATE_USABLE")
W.Check(not Glowing(R.power), "cost back: glow stops")
W.powerType, W.formID = 0, nil
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
auraUp = true
C_UnitAuras.GetPlayerAuraBySpellID = function(id) if id == 16870 and auraUp then return {} end end
W.Fire("UNIT_AURA", "player")
W.Check(Glowing(R.mana) and not Glowing(R.power), "caster form: only the mana bar (no energy bar showing)")
s.clearcastGlow = false
W.Fire("UNIT_AURA", "player")
W.Check(not Glowing(R.mana), "option off: no glow")
s.clearcastGlow = true
auraUp = false
W.Fire("UNIT_AURA", "player")
local okDebug = pcall(W.Slash, "/druidframe clearcasting")
W.Check(okDebug, "/druidframe clearcasting runs without errors")

Combat(true)
print("Shaded style, and the Claw orange still lines up after the switch")
s.style = "shaded"
R.Refresh()
if ns.OverlaysChanged then ns.OverlaysChanged() end
W.Check(R.health:GetStatusBarTexture():GetTexture() == "Interface\\TargetingFrame\\UI-StatusBar", "shaded: Blizzard's bar texture")
W.Check(not R.health.gloss:IsShown(), "shaded: no gloss")
W.powerType, W.formID = 3, 1
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.power[3] = 30
W.Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
local orange2 = Orange(R.power)
W.Near(orange2 and W.VisibleWidth(orange2) or -1, 0.30 * s.width, "Claw orange still matches the fill", 0.01)
s.comboStyle = "bar"
R.Refresh()
W.Check(#R.comboSegments == 5 and R.comboSegments[1].fill:GetStatusBarTexture():GetTexture() == "Interface\\TargetingFrame\\UI-StatusBar"
    and not R.comboSegments[1].gloss:IsShown(), "combo bar segments follow the shaded style")
s.style = "flat"
R.Refresh()
W.Check(R.comboSegments[1].fill:GetStatusBarTexture():GetTexture() == "Interface\\Buttons\\WHITE8X8"
    and R.comboSegments[1].gloss:IsShown(), "and the flat style")
s.style = "shaded"
R.Refresh()
W.Pick(_G.DruidBarResourceStyle, "flat")
W.Check(s.style == "flat", "style dropdown switches back to flat")
W.powerType, W.formID = 0, nil
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)

print("Combo points as a bar")
W.Pick(_G.DruidBarResourceCombo, "bar")
W.Check(s.comboStyle == "bar", "combo style set to bar")
W.powerType, W.formID = 3, 1
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.Check(R.comboBar:IsShown() and not R.combo:IsShown(), "bar shown instead of circles")
W.Near(R.comboBar:GetTop(), R.power:GetBottom() - s.padding, "below energy, with the usual padding")
W.Near(R.comboBar:GetWidth(), s.width, "full width")
W.Near(R.comboBar:GetHeight(), s.powerHeight, "power bar height")
local segs = R.comboSegments
W.Check(#segs == 5, "five segments")
W.Near(segs[1]:GetLeft(), R.comboBar:GetLeft(), "first segment starts at the bar's left edge")
W.Near(segs[5]:GetRight(), R.comboBar:GetRight(), "last segment ends at the bar's right edge (borders included)")
W.Near(segs[2]:GetLeft() - segs[1]:GetRight(), 2, "small gap between segments")
W.Near(segs[1]:GetWidth(), (s.width - 4 * 2) / 5, "equal widths")
W.Near(segs[1].fill:GetLeft() - segs[1]:GetLeft(), 1, "fill sits inside the 1-pixel border")
W.power[4] = 3
W.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
local filled = 0
for _, seg in ipairs(segs) do
    if seg.fill:GetStatusBarTexture():GetWidth() > 0 then filled = filled + 1 end
end
W.Check(filled == 3, "three segments filled (got " .. filled .. ")")
local glowFlash = R.glow.pieces[1][5]
W.Near(W.VisibleWidth(glowFlash), 0, "no glow at 3 combo points")
W.power[4] = 5
W.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
W.Check(W.VisibleWidth(glowFlash) > 0, "glow at 5 combo points")
W.Check(W.VisibleWidth(R.glow.pieces[5][4]) > 0, "glow around the last segment too")
W.Check(R.glow.pulse:IsPlaying(), "glow pulsing")
W.power[4] = 4
W.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
W.Near(W.VisibleWidth(glowFlash), 0, "glow gone after spending one")
W.Pick(_G.DruidBarResourceCombo, "hide")
W.Check(not R.comboBar:IsShown() and not R.combo:IsShown(), "Hide: no combo points")
W.Pick(_G.DruidBarResourceCombo, "circles")
W.Check(R.combo:IsShown() and not R.comboBar:IsShown(), "Circles: back to circles")
W.powerType, W.formID = 0, nil
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)

Combat(false)
print("Upgrading old settings")
DruidForeverManabarPlusDB.resource = { padding = 1, style = "shaded", comboPoints = false, text = "values" }
local up = R.Settings()
W.Near(up.padding, 4, "old 1-pixel padding moves to the PRD's gap")
W.Check(up.style == "flat" and up.version == 3, "switched to flat once")
W.Check(up.text == "centre", "text switched to current, centred once")
W.Check(up.comboStyle == "hide" and up.comboPoints == nil, "old 'no combo points' becomes Hide")
up.style = "shaded"
W.Check(R.Settings().style == "shaded", "after that, your choice sticks")
DruidForeverManabarPlusDB.resource = s

print("Options page")
local okShow = pcall(R.panel:GetScript("OnShow"), R.panel)
W.Check(okShow, "options page opens without errors")
local choices = W.OpenDropdown(_G.DruidBarResourceVisibility)
W.Check(#choices == 4 and choices[1].checked, "visibility dropdown lists 4 choices, current one ticked")
W.Pick(_G.DruidBarResourceVisibility, "combat")
W.Check(s.visibility == "combat", "picking a choice sets it (got " .. tostring(s.visibility) .. ")")
W.Check(_G.DruidBarResourceVisibility._ddText == "In combat", "dropdown shows the choice")
local comboChoices = W.OpenDropdown(_G.DruidBarResourceCombo)
W.Check(#comboChoices == 3 and comboChoices[1].text == "Hide" and comboChoices[2].text == "Circles"
    and comboChoices[3].text == "Bar", "combo dropdown: Hide, Circles, Bar")
s.visibility = "always"
R.Refresh()
_G.DruidBarResourceWidth:GetScript("OnValueChanged")(_G.DruidBarResourceWidth, 300)
W.Near(R.health:GetWidth(), 300, "width slider resizes the bars")
W.Near(R.mana:GetWidth(), 300, "all bars together")
local ok = pcall(W.Slash, "/druidframe debug")
W.Check(ok, "/druidframe debug runs without errors")
print("Options layout: the left column lines up")
R.panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 200, -100) -- the game places it when the options open
local function LeftOf(name) return _G[name]:GetLeft() end
local column = LeftOf("DruidBarResourceEnabled")
for _, name in ipairs({ "DruidBarResourceCentred", "DruidBarResourceClearcast", "DruidBarResourceCast",
    "DruidBarResourceCastLocked", "DruidBarResourceCastLinger" }) do
    W.Near(LeftOf(name), column, name .. " lines up with the first tick box")
end
local ddLeft = LeftOf("DruidBarResourceVisibility")
for _, name in ipairs({ "DruidBarResourceText", "DruidBarResourceStyle", "DruidBarResourceCombo" }) do
    W.Near(LeftOf(name), ddLeft, name .. " lines up with the first dropdown")
end
local tops = {}
for _, name in ipairs({ "DruidBarResourceEnabled", "DruidBarResourceVisibility", "DruidBarResourceText",
    "DruidBarResourceStyle", "DruidBarResourceCombo", "DruidBarResourceCasterEnergy", "DruidBarResourceCentred",
    "DruidBarResourceBuffs", "DruidBarResourceBuffsPvP" }) do
    tops[#tops + 1] = _G[name]:GetTop()
end
local ordered = true
for i = 2, #tops do if not (tops[i] < tops[i - 1]) then ordered = false end end
W.Check(ordered, "rows run top to bottom without overlapping")
W.Check(_G.DruidBarResourceBuffsPvP:GetBottom() > R.panel:GetBottom(), "left column fits on the page")
W.Check(_G.DruidBarResourceReset:GetLeft() > _G.DruidBarResourceBuffs:GetLeft() + 200
    and _G.DruidBarResourceReset:GetBottom() > R.panel:GetBottom(), "reset button in the right column, on the page")

W.Done()
