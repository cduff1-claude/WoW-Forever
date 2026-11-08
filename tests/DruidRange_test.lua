-- DruidFrame's DruidRange part (DruidFrame/DruidRange.lua): positioning above or below the
-- resource display, or free with "Keep centred"; unlocking with the options; right-click.
-- Run from the repo root: lua5.1 tests/DruidRange_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

W.spellCosts[768] = { { type = 0, name = "MANA", cost = 100 } }
W.spellCosts[1082] = { { type = 3, name = "ENERGY", cost = 45 } }
W.power[4], W.powerMax[4] = 0, 5

-- Saved from the standalone DruidRange: a free bar placed by its top-left corner.
DruidRangeDB = { enabled = true, unlocked = true, snapMelee = true, width = 100, height = 75, opacity = 75,
    point = { point = "TOPLEFT", x = 800, y = -600 } }

local ns = {}
for _, file in ipairs({ "DruidBar.lua", "Resource.lua", "Buffs.lua", "DruidRange.lua", "Options.lua" }) do
    W.Load("DruidFrame/" .. file, "DruidFrame", ns)
end
W.class, W.powerType, W.formID = "DRUID", 0, nil
W.Fire("PLAYER_LOGIN")
W.Fire("PLAYER_ENTERING_WORLD")

local bar = ns.Range.bar
local R = ns.Resource
local f = R.frame
local db = DruidRangeDB

-- An enemy in melee range: the bar shows.
W.target, W.enemy = true, true
W.range = { ["Faerie Fire"] = true, ["Wrath"] = true, ["Growl"] = true, ["Bash"] = true, ["Claw"] = true }
W.Fire("PLAYER_TARGET_CHANGED")
W.Advance(0.2)

print("Upgrading from the standalone DruidRange")
W.Check(db.unlocked == nil, "old unlock setting removed (it follows the options now)")
W.Check(db.anchor == "free", "stays free, where you had it")
W.Check(db.point.point == "CENTER", "old top-left position converted to a centre position")
W.Check(db.keepCentred == true, "keep centred on by default")
W.Near(select(1, bar:GetCenter()), UIParent:GetWidth() / 2, "keep centred: horizontally centred")
W.Check(bar:IsShown(), "shown with an enemy target")

print("Above DruidFrame")
db.anchor = "top"
R.Refresh()
local s = R.Settings()
W.Near(bar:GetBottom(), f:GetTop() + s.padding + 1, "sits just above the display")
W.Near(bar:GetWidth(), f:GetWidth(), "as wide as the display's bars")
W.Near(select(1, bar:GetCenter()), select(1, f:GetCenter()), "centred over it")

print("Below DruidFrame, following it as it grows")
db.anchor = "bottom"
R.Refresh()
W.Near(bar:GetTop(), f:GetBottom() - s.padding - 1, "sits just below the display")
W.powerType, W.formID = 3, 1
W.power[3], W.powerMax[3] = 100, 100
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)
W.Near(bar:GetTop(), f:GetBottom() - s.padding - 1, "Cat Form: still just below (energy and combo rows added)")
W.Check(R.power:IsShown() and bar:GetTop() < R.power:GetBottom(), "below the energy bar")
_G.DruidBarResourceWidth:GetScript("OnValueChanged")(_G.DruidBarResourceWidth, 300)
W.Near(bar:GetWidth(), 300, "follows the display's width setting")
db.width = 50
ns.Range.RefreshLayout()
W.Near(bar:GetWidth(), 150, "its own width setting is a percentage of that")
db.width = 100
W.powerType, W.formID = 0, nil
W.Fire("UPDATE_SHAPESHIFT_FORM")
W.Advance(0.2)

print("Attached: moves with the display, not dragged itself")
ns.panels.frame:GetScript("OnShow")(ns.panels.frame)
local before = bar:GetTop()
local bx, by = bar:GetCenter()
W.cursor = { bx, by }
bar:GetScript("OnMouseDown")(bar, "LeftButton")
W.cursor = { bx, by - 100 }
W.Advance(0.05)
bar:GetScript("OnMouseUp")(bar, "LeftButton")
W.Near(bar:GetTop(), before, "attached bar doesn't drag")
local fx, fy = f:GetCenter()
W.cursor = { fx, f:GetTop() - 2 }
f:GetScript("OnMouseDown")(f, "LeftButton")
W.cursor = { fx, f:GetTop() - 52 }
W.Advance(0.05)
f:GetScript("OnMouseUp")(f, "LeftButton")
W.Near(bar:GetTop(), f:GetBottom() - s.padding - 1, "dragging the display takes the bar with it")
ns.panels.frame:GetScript("OnHide")(ns.panels.frame)

print("Free, with Keep centred")
db.anchor = "free"
db.snapMelee = false
R.Refresh()
W.Near(select(1, bar:GetCenter()), UIParent:GetWidth() / 2, "centred")
bx, by = bar:GetCenter()
W.cursor = { bx, by }
bar:GetScript("OnMouseDown")(bar, "LeftButton")
W.cursor = { bx + 200, by + 60 }
W.Advance(0.05)
bar:GetScript("OnMouseUp")(bar, "LeftButton")
W.Near(select(2, bar:GetCenter()), by, "locked (options closed): doesn't drag")
ns.panels.range:GetScript("OnShow")(ns.panels.range)
W.Check(R.unlocked, "the DruidRange page unlocks the display too")
W.cursor = { bx, by }
bar:GetScript("OnMouseDown")(bar, "LeftButton")
W.Check(R.guide:IsShown(), "red centre line while dragging")
W.cursor = { bx + 200, by + 60 }
W.Advance(0.05)
bar:GetScript("OnMouseUp")(bar, "LeftButton")
W.Near(select(2, bar:GetCenter()), by + 60, "moved up with the mouse")
W.Near(select(1, bar:GetCenter()), UIParent:GetWidth() / 2, "but stayed centred")
W.Check(not R.guide:IsShown(), "centre line gone")

print("Free, without Keep centred")
db.keepCentred = false
bx, by = bar:GetCenter()
W.cursor = { bx, by }
bar:GetScript("OnMouseDown")(bar, "LeftButton")
W.cursor = { bx - 150, by }
W.Advance(0.05)
bar:GetScript("OnMouseUp")(bar, "LeftButton")
W.Near(select(1, bar:GetCenter()), bx - 150, "moves sideways freely")
db.keepCentred = true

print("Combat: no protected calls")
W.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
local okShift = pcall(function()
    W.powerType, W.formID = 1, 5
    W.Fire("UPDATE_SHAPESHIFT_FORM")
    W.Advance(0.2)
    R.Refresh()
    ns.Range.RefreshLayout()
    W.powerType, W.formID = 0, nil
    W.Fire("UPDATE_SHAPESHIFT_FORM")
    W.Advance(0.2)
end)
W.Check(okShift, "shifting and refreshing in combat doesn't touch SetPassThroughButtons")
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
W.Check(f._passThrough == (not R.unlocked), "pass-through matches the lock state after combat")

print("Moving between options pages keeps it unlocked")
ns.panels.frame:GetScript("OnShow")(ns.panels.frame)
ns.panels.range:GetScript("OnHide")(ns.panels.range)
W.Check(R.unlocked, "still unlocked on the DruidFrame page")
ns.panels.frame:GetScript("OnHide")(ns.panels.frame)
W.Check(not R.unlocked, "locked once every page is closed")

print("Preview while the options are open")
W.target = false
W.Fire("PLAYER_TARGET_CHANGED")
W.Advance(0.2)
W.Check(not bar:IsShown(), "no target: hidden")
ns.panels.range:GetScript("OnShow")(ns.panels.range)
W.Advance(0.2)
W.Check(bar:IsShown(), "shown (green) while the options are open, so you can place it")
ns.panels.range:GetScript("OnHide")(ns.panels.range)
W.Advance(0.2)
W.Check(not bar:IsShown(), "hidden again when they close")

print("Right-click and slash commands")
W.target = true
W.Fire("PLAYER_TARGET_CHANGED")
W.Advance(0.2)
local opened
local realOpen = Settings.OpenToCategory
Settings.OpenToCategory = function(id) opened = id end
bx, by = bar:GetCenter()
W.cursor = { bx, by }
bar:GetScript("OnMouseDown")(bar, "RightButton")
bar:GetScript("OnMouseUp")(bar, "RightButton")
W.Check(opened == "DruidRange", "right-click opens the DruidRange page (got " .. tostring(opened) .. ")")
opened = nil
W.Slash("/druidrange")
W.Check(opened == "DruidRange", "/druidrange opens the DruidRange page")
W.Slash("/druidframe")
W.Check(opened == "DruidFrame", "/druidframe opens the DruidFrame page")
W.Slash("/druidbar")
W.Check(opened == "DruidBar", "/druidbar opens the DruidBar page")
opened = nil
W.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
f:GetScript("OnMouseDown")(f, "RightButton")
f:GetScript("OnMouseUp")(f, "RightButton")
W.Slash("/druidframe")
W.Check(opened == nil, "in combat: no options (the client blocks them)")
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
Settings.OpenToCategory = realOpen
local ok = pcall(W.Slash, "/druidrange debug")
W.Check(ok, "/druidrange debug runs without errors")

print("Position buttons on the DruidRange page")
ns.panels.range:GetScript("OnShow")(ns.panels.range)
_G.DruidRangePosition1:SetChecked(true)
_G.DruidRangePosition1:Click()
W.Check(db.anchor == "top", "Above DruidFrame")
W.Check(_G.DruidRangePosition1:GetChecked() and not _G.DruidRangePosition3:GetChecked(), "only that one ticked")
_G.DruidRangePosition3:Click()
W.Check(db.anchor == "free", "Free")
ns.panels.range:GetScript("OnHide")(ns.panels.range)

W.Done()
