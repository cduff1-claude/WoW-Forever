-- DruidBar: the 5-second-rule markers on Blizzard's mana bars (merged in from
-- ForeverFiveSecondRule), plus a smoke test of login, shifting and the options.
-- Run from the repo root: lua5.1 tests/DruidBar_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

-- Blizzard's bars: the Player Frame mana bar and the Personal Resource Display.
PlayerFrame = CreateFrame("Frame", "PlayerFrame", UIParent)
PlayerFrame:SetSize(232, 100)
PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
PlayerFrame.PlayerFrameContent = { PlayerFrameContentMain = { ManaBarArea = {} } }
local pfBar = CreateFrame("StatusBar", nil, PlayerFrame)
pfBar:SetSize(124, 10)
pfBar:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 85, -60)
PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar = pfBar

PersonalResourceDisplayFrame = CreateFrame("Frame", "PersonalResourceDisplayFrame", UIParent)
PersonalResourceDisplayFrame:SetSize(200, 30)
PersonalResourceDisplayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
local prdPower = CreateFrame("StatusBar", nil, PersonalResourceDisplayFrame)
prdPower:SetSize(200, 8)
prdPower:SetPoint("TOPLEFT", PersonalResourceDisplayFrame, "TOPLEFT")
local prdAlt = CreateFrame("StatusBar", nil, PersonalResourceDisplayFrame)
prdAlt:SetSize(200, 6)
prdAlt:SetPoint("TOPLEFT", prdPower, "BOTTOMLEFT")
PersonalResourceDisplayFrame.PowerBar = prdPower
PersonalResourceDisplayFrame.AlternatePowerBar = prdAlt
PersonalResourceDisplayFrame.UpdatePowerBar = function() end
local prdHealth = CreateFrame("StatusBar", nil, PersonalResourceDisplayFrame)
prdHealth:SetSize(200, 10)
prdHealth:SetPoint("BOTTOMLEFT", prdPower, "TOPLEFT")
PersonalResourceDisplayFrame.HealthBarsContainer = { healthBar = prdHealth }

-- Bar art: the Player Frame's shaded atlases, and the PRD's flat bright colours.
local ATLAS = {
    HEALTH = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
    MANA = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
}
local FLAT = "Interface\\TargetingFrame\\UI-StatusBar"
local pfHealth = CreateFrame("StatusBar", nil, PlayerFrame)
pfHealth:SetSize(124, 20)
pfHealth:SetPoint("BOTTOMLEFT", pfBar, "TOPLEFT")
PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer = { HealthBar = pfHealth }
pfHealth:GetStatusBarTexture():SetAtlas(ATLAS.HEALTH)
pfHealth:SetStatusBarColor(0.9, 0.9, 0.9, 1)
pfBar:GetStatusBarTexture():SetAtlas(ATLAS.MANA)
pfBar:SetStatusBarColor(1, 1, 1, 1)
for bar, colour in pairs({ [prdHealth] = { 0, 1, 0 }, [prdPower] = { 0, 0, 1 }, [prdAlt] = { 0, 0, 1 } }) do
    bar:SetStatusBarTexture(FLAT)
    bar:SetStatusBarColor(colour[1], colour[2], colour[3], 1)
end
PersonalResourceDisplayFrame.UpdateAlternatePowerBar = function() end

-- Spells: Healing Touch costs mana, Claw costs energy, the forms cost mana.
local HEALING_TOUCH = 5185
W.spellCosts[HEALING_TOUCH] = { { type = 0, name = "MANA", cost = 55 } }
W.spellCosts[768] = { { type = 0, name = "MANA", cost = 100 } }
W.spellCosts[5487] = { { type = 0, name = "MANA", cost = 100 } }
W.spellCosts[1082] = { { type = 3, name = "ENERGY", cost = 45 } }
W.spellCosts["Claw"] = W.spellCosts[1082]

W.Load("DruidBar/DruidBar.lua", "DruidBar", {})

local ok
print("Login")
W.class, W.powerType, W.formID = "DRUID", 0, nil
W.Fire("PLAYER_LOGIN")
W.Fire("PLAYER_ENTERING_WORLD")
W.Check(DruidForeverManabarPlusDB.fsrPlayerFrame == true, "new 5SR settings default to on")
W.Check(DruidForeverManabarPlusDB.fsrWidth == 2, "marker width defaults to 2")

-- The 5SR marker on a Blizzard bar: a white texture in a child frame of that bar.
local function Marker(bar)
    for _, child in ipairs(bar._children) do
        for _, region in ipairs(child._regions) do
            local c = region._color
            if c and c[1] == 1 and c[2] == 1 and c[3] == 1 and c[4] == 0.95 then
                return region, child
            end
        end
    end
end
local function Shown(bar)
    local marker, holder = Marker(bar)
    return marker ~= nil and holder:IsShown()
end
local function MarkerX(bar)
    local marker = Marker(bar)
    return marker:GetCenter() - bar:GetLeft()
end

print("Caster form: casting a mana spell starts the timer")
W.Fire("UNIT_SPELLCAST_SENT", "player", nil, "cast-1", HEALING_TOUCH)
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", HEALING_TOUCH)
W.Advance(0.1)
W.Check(Shown(pfBar), "marker on the Player Frame mana bar")
W.Check(Shown(prdPower), "marker on the PRD mana bar")
W.Check(not Shown(prdAlt), "no marker on the PRD's in-form bar in caster form")
W.Advance(2.4)
W.Near(MarkerX(pfBar), 1 + 0.5 * (124 - 2), "Player Frame marker halfway at 2.5s", 1.5)
W.Near(MarkerX(prdPower), 1 + 0.5 * (200 - 2), "PRD marker halfway at 2.5s", 2)
local _, holder = Marker(pfBar)
local text
for _, r in ipairs(holder._regions) do if r._kind == "FontString" then text = r end end
W.Check(text and text._text == "2.5", "countdown reads 2.5 (got " .. tostring(text and text._text) .. ")")

print("Shift to Cat Form mid-timer")
W.powerType, W.formID = 3, 1
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.1)
W.Check(not Shown(pfBar), "Player Frame marker hidden (bar shows energy)")
W.Check(Shown(prdAlt), "marker moves to the PRD's in-form mana bar")
W.Check(not Shown(prdPower), "no marker on the PRD energy bar")

print("Timer ends")
W.Advance(3)
W.Check(not Shown(prdAlt), "marker hidden after 5 seconds")
W.Advance(1)
W.Check(not Shown(prdAlt), "stays hidden")

print("Options")
DruidForeverManabarPlusDB.fsrText = false
W.powerType, W.formID = 0, nil
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", HEALING_TOUCH)
W.Advance(1)
W.Check(text and not text:IsShown(), "countdown hidden when its option is off")
DruidForeverManabarPlusDB.fsrPlayerFrame = false
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.1)
W.Check(not Shown(pfBar), "Player Frame marker off when its option is off")
W.Check(Shown(prdPower), "PRD marker still on")
DruidForeverManabarPlusDB.fsrWidth = 5
W.Advance(0.1)
W.Near(Marker(prdPower):GetWidth(), 5, "marker width follows the slider setting")

local function Art(bar) return bar:GetStatusBarTexture():GetAtlas() or bar:GetStatusBarTexture():GetTexture() end

print("Personal Resource Display tinted to the Player Frame's colours")
local function Near3(bar, want, label)
    local r, g, b = bar:GetStatusBarColor()
    W.Check(math.abs(r - want[1]) < 0.01 and math.abs(g - want[2]) < 0.01 and math.abs(b - want[3]) < 0.01,
        string.format("%s (got %.2f %.2f %.2f)", label, r, g, b))
end
local HEALTH, MANA, ENERGY = { 0.40, 0.73, 0.17 }, { 0.00, 0.34, 0.73 }, { 1.00, 1.00, 0.23 }
DruidForeverManabarPlusDB.fsrPlayerFrame = true
W.powerType, W.formID = 0, nil
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.Check(Art(prdHealth) == FLAT and Art(prdPower) == FLAT and Art(prdAlt) == FLAT,
    "PRD bars keep their own full-size texture")
Near3(prdHealth, HEALTH, "PRD health tinted to the Player Frame green")
Near3(prdPower, MANA, "PRD mana tinted to the Player Frame blue in caster form")

print("Shift to Cat")
W.powerType, W.formID = 3, 1
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
Near3(prdPower, ENERGY, "PRD energy bar tinted to the Player Frame yellow")
Near3(prdAlt, MANA, "PRD in-form mana bar tinted to the Player Frame blue")

print("Blizzard repaints a PRD bar: the tint is put back")
prdPower:SetStatusBarColor(1, 1, 0, 1)
W.Advance(0.2)
Near3(prdPower, ENERGY, "energy tint reapplied after Blizzard's repaint")

print("Bear Form: rage has no measured colour, so Blizzard's stays")
W.powerType, W.formID = 1, 5
prdPower:SetStatusBarColor(1, 0, 0, 1) -- Blizzard paints the rage bar
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
Near3(prdPower, { 1, 0, 0 }, "rage bar keeps Blizzard's red")
W.powerType, W.formID = 3, 1
prdPower:SetStatusBarColor(1, 1, 0, 1)
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)

print("Claw shading: light wash with enough energy, orange without")
-- The Player Frame bar shows energy in Cat Form; Claw costs 45 of 100.
local function ClawLayers(bar)
    local enough, short
    for _, t in ipairs(W.Textures(bar)) do
        local c = t._color
        if c and c[1] == 1 and c[2] == 1 and c[3] == 1 and c[4] == 0.35 then enough = t end
        if c and c[1] == 1 and c[2] == 0.5 and c[3] == 0 and c[4] == 0.9 then short = t end
    end
    return enough, short
end
local function SetEnergy(value)
    W.power[3] = value
    pfBar:SetMinMaxValues(0, 100)
    pfBar:SetValue(value) -- Blizzard's own fill
    prdPower:SetMinMaxValues(0, 100)
    prdPower:SetValue(value)
    W.Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
end
W.Fire("SPELLS_CHANGED")
W.Advance(1.1)
SetEnergy(80)
local enough, short = ClawLayers(pfBar)
W.Check(enough and short, "both Claw layers exist on the Player Frame energy bar")
W.Near(W.VisibleWidth(enough), 0.45 * 124, "80 energy: wash covers Claw's 45 energy", 0.01)
W.Near(W.VisibleWidth(short), 0, "80 energy: no orange")
SetEnergy(30)
W.Near(W.VisibleWidth(enough), 0, "30 energy: no wash")
W.Near(W.VisibleWidth(short), 0.30 * 124, "30 energy: the whole fill is orange", 0.01)
SetEnergy(45)
W.Near(W.VisibleWidth(enough), 0.45 * 124, "exactly 45 energy counts as enough", 0.01)
W.Near(W.VisibleWidth(short), 0, "exactly 45 energy: no orange")
local prdEnough, prdShort = ClawLayers(prdPower)
SetEnergy(20)
W.Near(W.VisibleWidth(prdShort), 0.20 * 200, "PRD energy bar turns orange too", 0.01)

print("Turning the colour match off puts Blizzard's look back")
DruidForeverManabarPlusDB.prdMatchColours = false
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
Near3(prdHealth, { 0, 1, 0 }, "PRD health back to Blizzard's green")
Near3(prdPower, { 1, 1, 0 }, "PRD energy back to Blizzard's latest colour (not an older one)")

print("Slash commands run")
ok = pcall(W.Slash, "/druidbar colours")
W.Check(ok, "/druidbar colours runs without errors")
ok = pcall(W.Slash, "/druidbar debug")
W.Check(ok, "/druidbar debug runs without errors")
ok = pcall(W.Slash, "/druidbar test")
W.Check(ok, "/druidbar test runs without errors")

W.Done()
