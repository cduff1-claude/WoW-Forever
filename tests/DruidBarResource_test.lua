-- DruidBar's resource display (Resource.lua): layout in each form, text, combo points, the
-- cast bar, visibility, dragging with "Keep centred", and DruidBar's overlays on its bars.
-- Run from the repo root: lua5.1 tests/DruidBarResource_test.lua

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
W.Load("DruidBar/DruidBar.lua", "DruidBar", ns)
W.Load("DruidBar/Resource.lua", "DruidBar", ns)
local R = ns.Resource

W.class, W.powerType, W.formID = "DRUID", 0, nil
W.power[0], W.powerMax[0] = 847, 847
W.Fire("PLAYER_LOGIN")
W.Fire("PLAYER_ENTERING_WORLD")
local s = R.Settings()
local f = R.frame

local function Top(bar) return bar:GetTop() end
local function Shown(bar) return bar:IsShown() end

print("Caster form")
W.Check(f:IsShown(), "frame shown")
W.Near(Top(R.health), f:GetTop(), "health at the top")
W.Near(Top(R.mana), f:GetTop() - s.healthHeight - s.padding, "mana right below health")
W.Check(not Shown(R.power) and not Shown(R.cast), "no third row in caster form when not casting")
W.Check(not R.combo:IsShown(), "no combo points in caster form")
W.Near(R.health:GetWidth(), s.width, "health is the full width")
W.Near(R.mana:GetWidth(), s.width, "mana is the full width")
W.Near(f:GetHeight(), s.healthHeight + s.padding + s.powerHeight, "frame fits two rows")
W.Check(R.health.left._text == "989" and R.health.right._text == "989", "health: current left, max right")
W.Check(R.mana.left._text == "847" and R.mana.right._text == "847", "mana: current left, max right")
W.Near(select(1, R.health.left:GetPoint()) == "LEFT" and select(4, R.health.left:GetPoint()), 4, "health text indented from the left")
W.Near(select(4, R.health.right:GetPoint()), -4, "max text indented from the right")
local healthTop, manaTop = Top(R.health), Top(R.mana)

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
W.Check(R.power.left._text == "100" and R.power.right._text == "", "energy: current only")
W.Check(R.combo:IsShown(), "combo points shown")
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
W.Check(c and c[1] == 1 and c[2] == 1 and c[3] == 0.5, "energy uses the pale yellow")
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

print("Bear Form: rage below mana, no combo points")
W.powerType, W.formID = 1, 5
W.power[1], W.powerMax[1] = 10, 100
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.Near(Top(R.mana), manaTop, "mana still hasn't moved")
W.Check(Shown(R.power) and R.power.left._text == "10", "rage bar shows 10")
W.Check(not R.combo:IsShown(), "no combo points in Bear")
c = R.power:GetStatusBarTexture()._color
W.Check(c and c[1] == 0.75 and c[2] == 0, "rage uses the darker red")

print("Caster form: cast bar while casting")
W.powerType, W.formID = 0, nil
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.casting = { name = "Healing Touch", startMS = W.time * 1000, endMS = W.time * 1000 + 2000 }
W.Fire("UNIT_SPELLCAST_START", "player", "cast-1", HEALING_TOUCH)
W.Check(Shown(R.cast), "cast bar shown while casting")
W.Near(Top(R.cast), manaTop - s.powerHeight - s.padding, "cast bar where energy/rage go")
W.Near(R.cast:GetWidth(), s.width, "cast bar is the full width")
W.Check(R.cast.left._text == "Healing Touch", "spell name on the cast bar")
W.Advance(1.0)
W.Near(R.cast:GetStatusBarTexture():GetWidth(), 0.5 * s.width, "half full after 1 of 2 seconds", 1)
W.casting = nil
W.Fire("UNIT_SPELLCAST_STOP", "player", "cast-1", HEALING_TOUCH)
W.Check(not Shown(R.cast), "cast bar gone when the cast ends")
W.Near(f:GetHeight(), s.healthHeight + s.padding + s.powerHeight, "frame back to two rows")
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
s.text = "values"
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
s.unlocked = true
R.Refresh()
W.Check(f:IsShown(), "shown while unlocked, even when set to hidden (so you can place it)")
s.visibility = "always"
s.unlocked = false
R.Refresh()
W.Check(f:IsShown(), "always mode: shown")

print("Dragging with Keep centred")
R.SetUnlocked(true)
W.Check(R.unlockTint:IsShown(), "unlocked: highlighted")
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
R.SetUnlocked(false)
W.Check(not R.unlockTint:IsShown(), "locked again")

print("Options page")
local okShow = pcall(R.panel:GetScript("OnShow"), R.panel)
W.Check(okShow, "options page opens without errors")
_G.DruidBarResourceVisibility:Click()
W.Check(s.visibility == "combat", "visibility button steps to the next choice (got " .. tostring(s.visibility) .. ")")
W.Check(_G.DruidBarResourceVisibility:GetText() == "Visibility: In combat", "button label follows")
s.visibility = "always"
R.Refresh()
_G.DruidBarResourceWidth:GetScript("OnValueChanged")(_G.DruidBarResourceWidth, 300)
W.Near(R.health:GetWidth(), 300, "width slider resizes the bars")
W.Near(R.mana:GetWidth(), 300, "all bars together")
local ok = pcall(W.Slash, "/druidbar resource")
W.Check(ok, "/druidbar resource runs without errors")
ok = pcall(W.Slash, "/druidbar unlock")
W.Check(ok and s.unlocked, "/druidbar unlock unlocks it")
pcall(W.Slash, "/druidbar lock")
W.Check(not s.unlocked, "/druidbar lock locks it")

W.Done()
