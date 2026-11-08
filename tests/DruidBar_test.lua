-- DruidFrame's DruidBar part (DruidFrame/DruidBar.lua): the Player Frame features. By default it
-- leaves the Player Frame alone, and it never touches the Personal Resource Display at all.
-- Run from the repo root: lua5.1 tests/DruidBar_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

-- Blizzard's bars: the Player Frame mana bar, and a Personal Resource Display that must be left alone.
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
prdPower:SetStatusBarColor(0, 0, 1, 1)
local prdChildren = #prdPower._children + #prdAlt._children

-- Spells: Healing Touch costs mana, Claw costs energy, the forms cost mana.
local HEALING_TOUCH = 5185
W.spellCosts[HEALING_TOUCH] = { { type = 0, name = "MANA", cost = 55 } }
W.spellCosts[768] = { { type = 0, name = "MANA", cost = 100 } }
W.spellCosts[5487] = { { type = 0, name = "MANA", cost = 100 } }
W.spellCosts[1082] = { { type = 3, name = "ENERGY", cost = 45 } }
W.spellCosts["Claw"] = W.spellCosts[1082]

-- Spy: only Blizzard (the test, standing in for it) may set these bars' values.
for _, bar in ipairs({ pfBar, prdPower, prdAlt }) do
    local real = bar.SetValue
    bar.SetValue = function(self, ...)
        if not W.blizzard then W.touchedBlizzard = true end
        return real(self, ...)
    end
end

local ns = {}
for _, file in ipairs({ "DruidBar.lua", "Resource.lua", "Buffs.lua", "DruidRange.lua", "Options.lua" }) do
    W.Load("DruidFrame/" .. file, "DruidFrame", ns)
end

-- The 5SR marker on a bar: a white texture in a child frame of that bar.
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
local function MarkerShown(bar)
    local marker, holder = Marker(bar)
    return marker ~= nil and holder:IsShown()
end
local function Orange(bar)
    for _, t in ipairs(W.Textures(bar)) do
        local c = t._color
        if c and c[1] == 1 and c[2] == 0.5 and c[3] == 0 and c[4] == 0.9 then return t end
    end
end
local function SetEnergy(value)
    W.power[3] = value
    W.blizzard = true -- Blizzard's own fill
    pfBar:SetMinMaxValues(0, 100)
    pfBar:SetValue(value)
    W.blizzard = false
    W.Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
end

print("Login: the Player Frame is left alone by default")
DruidForeverManabarPlusDB = { enablePlayerFrame = true, fsrPlayerFrame = true, enablePersonalResource = true,
    prdMatchColours = true, fsrPersonalResource = true } -- settings from before DruidFrame
W.class, W.powerType, W.formID = "DRUID", 0, nil
W.Fire("PLAYER_LOGIN")
W.Fire("PLAYER_ENTERING_WORLD")
local db = DruidForeverManabarPlusDB
W.Check(db.enablePlayerFrame == false and db.fsrPlayerFrame == false, "old Player Frame settings switched off once")
W.Check(db.finisherSpell == "bite" and db.settingsVersion == 2, "full combo points default to Ferocious Bite")
W.Check(db.enablePersonalResource == nil and db.prdMatchColours == nil and db.fsrPersonalResource == nil,
    "Personal Resource Display settings removed")
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", HEALING_TOUCH)
W.Advance(0.1)
W.Check(not MarkerShown(pfBar), "no 5SR marker on the Player Frame")
W.Check(not _G.DruidForeverManabarPlusMainFrame:IsShown(), "no druid bar under the Player Frame")

print("Turning the Player Frame options on")
db.enablePlayerFrame, db.fsrPlayerFrame = true, true
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", HEALING_TOUCH)
W.Advance(0.1)
W.Check(MarkerShown(pfBar), "5SR marker on the Player Frame mana bar")
W.Advance(2.4)
local marker = Marker(pfBar)
W.Near(marker:GetCenter() - pfBar:GetLeft(), 1 + 0.5 * (124 - 2), "marker halfway at 2.5s", 1.5)
W.Advance(3)
W.Check(not MarkerShown(pfBar), "marker gone after 5 seconds")

print("Cat Form: druid bar under the Player Frame, Claw orange on its energy bar")
W.powerType, W.formID = 3, 1
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Fire("SPELLS_CHANGED")
W.Advance(1.1)
W.Check(_G.DruidForeverManabarPlusMainFrame:IsShown(), "druid bar shown in Cat Form")
SetEnergy(30)
local orange = Orange(pfBar)
W.Near(orange and W.VisibleWidth(orange) or -1, 0.30 * 124, "30 energy: the Player Frame energy bar is orange", 0.01)
SetEnergy(80)
W.Near(W.VisibleWidth(orange), 0, "80 energy: no orange")
W.power[3] = 30
W.blizzard = true
pfBar:SetValue(80) -- Blizzard's fill still easing down
W.blizzard = false
W.Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
W.Near(W.VisibleWidth(orange), 0.80 * 124, "orange covers Blizzard's lagging fill too", 0.01)

print("The Personal Resource Display is never touched")
W.Check(#prdPower._children + #prdAlt._children == prdChildren, "nothing added to its bars")
local r, g, b = prdPower:GetStatusBarColor()
W.Check(r == 0 and g == 0 and b == 1, "its colours left as Blizzard set them")
W.Check(not W.touchedBlizzard, "no SetValue on Blizzard's bars")

print("Options page and slash commands")
W.Check(ns.categories.bar ~= nil, "DruidBar page registered under DruidFrame")
local opened
local realOpen = Settings.OpenToCategory
Settings.OpenToCategory = function(id) opened = id end
W.Slash("/druidbar")
W.Check(opened == "DruidBar", "/druidbar opens the DruidBar page (got " .. tostring(opened) .. ")")
Settings.OpenToCategory = realOpen
local ok = pcall(W.Slash, "/druidbar debug")
W.Check(ok, "/druidbar debug runs without errors")
ok = pcall(W.Slash, "/druidbar test")
W.Check(ok, "/druidbar test runs without errors")
local okShow = pcall(ns.panels.bar:GetScript("OnShow"), ns.panels.bar)
W.Check(okShow, "DruidBar page opens without errors")
W.Check(_G.DFMPPersonalResourceCheckbox == nil and _G.DFMPColourCheckbox == nil and _G.DFMPFsrPrdCheckbox == nil,
    "no Personal Resource Display options")

W.Done()
