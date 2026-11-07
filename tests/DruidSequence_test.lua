-- DruidSequence: the minimap button (click opens the settings, drag moves it, /fseq minimap
-- hides it), and a smoke test that the whole addon loads and logs in without errors.
-- Run from the repo root: lua5.1 tests/DruidSequence_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

local ns = {}
for _, file in ipairs({ "DruidSequence.lua", "Editor.lua", "MinimapButton.lua" }) do
    W.Load("DruidSequence/" .. file, "DruidSequence", ns)
end

print("Login as a druid")
W.class = "DRUID"
local ok, err = pcall(W.Fire, "PLAYER_LOGIN")
W.Check(ok, "PLAYER_LOGIN runs without errors" .. (ok and "" or (": " .. tostring(err))))
pcall(W.Fire, "PLAYER_ENTERING_WORLD")

local button = _G.DruidSequenceMinimapButton
W.Check(button ~= nil, "minimap button created")
W.Check(button:IsShown(), "button shown by default")

local function Angle()
    local bx, by = button:GetCenter()
    local mx, my = Minimap:GetCenter()
    return math.deg(math.atan2(by - my, bx - mx)) % 360, math.sqrt((bx - mx) ^ 2 + (by - my) ^ 2)
end
local angle, distance = Angle()
W.Near(angle, 200, "starts at the default angle (lower left)")
W.Near(distance, Minimap:GetWidth() / 2 + 5, "sits just outside the minimap's edge")

print("Click opens the settings")
local opened = 0
local realToggle = ns.ToggleEditor
ns.ToggleEditor = function(...) opened = opened + 1 end
button:Click("LeftButton")
W.Check(opened == 1, "click calls the settings window toggle")
ns.ToggleEditor = realToggle
if realToggle then
    ok, err = pcall(button:GetScript("OnClick"), button, "LeftButton")
    W.Check(ok, "the real settings window opens without errors" .. (ok and "" or (": " .. tostring(err))))
end

print("Drag moves it round the edge")
local mx, my = Minimap:GetCenter()
W.cursor = { mx + 50, my + 50 } -- up and to the right
button:GetScript("OnDragStart")(button)
W.Advance(0.1)
button:GetScript("OnDragStop")(button)
angle, distance = Angle()
W.Near(angle, 45, "moved to where the cursor was (45 degrees)")
W.Near(distance, Minimap:GetWidth() / 2 + 5, "still on the edge")
W.Near(ForeverSequencesDB.minimap.angle, 45, "angle saved to the settings")
W.Check(button:GetScript("OnUpdate") == nil, "stops following the cursor after the drag")

print("/fseq minimap hides and shows it")
W.Slash("/fseq minimap")
W.Check(not button:IsShown(), "hidden")
W.Check(ForeverSequencesDB.minimap.hide == true, "hidden state saved")
W.Slash("/fseq minimap")
W.Check(button:IsShown(), "shown again")

print("Tooltip")
ok = pcall(button:GetScript("OnEnter"), button)
W.Check(ok, "tooltip shows without errors")

W.Done()
