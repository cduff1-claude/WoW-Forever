-- CustomFormBars: the /click buttons (old long names and the short FB ones) switch the main bar
-- at once, a powershift's drop to caster is ignored, and the driver's page wins afterwards.
-- Run from the repo root: lua5.1 tests/CustomFormBars_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")
W.class = "DRUID"

-- Blizzard's main bar buttons.
for i = 1, 12 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b.UpdateAction = function() end
end
function GetOverrideBarIndex() return 14 end
function GetVehicleBarIndex() return 12 end
function GetTempShapeshiftBarIndex() return 13 end
function GetBonusBarOffset() return 0 end
-- Stance bar: Bear, Aquatic, Cat, Travel.
local STANCE = { 5487, 1066, 768, 783 }
function GetNumShapeshiftForms() return #STANCE end
function GetShapeshiftFormInfo(i) return nil, nil, nil, STANCE[i] end

W.Load("CustomFormBars/CustomFormBars.lua", "CustomFormBars")
W.Fire("ADDON_LOADED", "CustomFormBars")
W.Fire("PLAYER_LOGIN")

local header = _G.CustomFormBarsHeader
local function Page() return ActionButton1:GetAttribute("actionpage") end
local function Driver(state) header:SetAttribute("state-page", state) end
Driver(1001) -- caster
W.Check(Page() == 1, "caster: page 1")

-- Every name exists and carries its form's page.
local names = {
    { "FormBarsCat", "FBCat", "FBC", page = 7 },
    { "FormBarsBear", "FBBear", "FBB", page = 9 },
    { "FormBarsMoonkin", "FBMoonkin", "FBM", page = 10 },
    { "FormBarsTravel", "FBTravel", "FBT", page = 1 },
    { "FormBarsAquatic", "FBAquatic", "FBA", page = 1 },
    { "FormBarsDruid", "FBDruid", "FBD", page = 1 },
}
for _, set in ipairs(names) do
    for _, n in ipairs(set) do
        W.Check(_G[n] and _G[n]:GetAttribute("fbpage") == set.page, n .. ": page " .. set.page)
    end
end

-- Powershift into Cat with the short name: bar flips at once, the drop to caster is ignored.
FBC:Click()
W.Check(Page() == 7, "/click FBC: Cat page at once")
Driver(1001)
W.Check(Page() == 7, "drop to caster mid-shift ignored")
Driver(7)
W.Check(Page() == 7, "Cat confirmed")

-- Bear with the long name still works.
FormBarsBear:Click()
W.Check(Page() == 9, "/click FormBarsBear: Bear page at once")
Driver(1001); Driver(9)
W.Check(Page() == 9, "Bear confirmed")

-- Shift out to caster with FBD: page 1 at once, and the drop to caster is taken as the real thing.
FBD:Click()
W.Check(Page() == 1, "/click FBD: normal bar at once")
Driver(1001)
W.Check(Page() == 1, "caster confirmed")
Driver(7)
W.Check(Page() == 7, "a later shift still follows the driver")

-- /fb off clears the buttons.
SlashCmdList.FORMBARS("off")
W.Check(FBC:GetAttribute("fbpage") == nil and FormBarsCat:GetAttribute("fbpage") == nil, "/fb off: buttons do nothing")
SlashCmdList.FORMBARS("on")
W.Check(FBB:GetAttribute("fbpage") == 9, "/fb on: back")

-- A failed shift (no form change) lets go of the held page 5 seconds later.
Driver(1001)
FBB:Click()
W.Check(Page() == 9, "/click FBB: Bear page")
W.Advance(6)
W.Check(Page() == 1, "shift never happened: back to the caster bar after 5s")

W.Done()
