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
PersonalResourceDisplayFrame.UpdateAlternatePowerBar = function() end

-- Spells: Healing Touch costs mana, Claw costs energy, the forms cost mana.
local HEALING_TOUCH = 5185
W.spellCosts[HEALING_TOUCH] = { { type = 0, name = "MANA", cost = 55 } }
W.spellCosts[768] = { { type = 0, name = "MANA", cost = 100 } }
W.spellCosts[5487] = { { type = 0, name = "MANA", cost = 100 } }
W.spellCosts[1082] = { { type = 3, name = "ENERGY", cost = 45 } }
W.spellCosts["Claw"] = W.spellCosts[1082]

W.Load("DruidBar/DruidBar.lua", "DruidBar", {})

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

print("Slash commands run")
local ok = pcall(W.Slash, "/druidbar debug")
W.Check(ok, "/druidbar debug runs without errors")
ok = pcall(W.Slash, "/druidbar test")
W.Check(ok, "/druidbar test runs without errors")

W.Done()
