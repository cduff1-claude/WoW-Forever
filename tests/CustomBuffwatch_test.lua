-- CustomBuffwatch: the "Party members in second row" and "Keep centred" layout options.
-- Run from the repo root: lua5.1 tests/CustomBuffwatch_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

-- Reach the file's local tables, which the layout code reads.
local EXPOSE = [[
BUFFWATCHADDON._T = {
    Setup = function(order, info, buffs, tempEnch, nameWidth)
        Player_Order, Current_Order, Player_Info = order, CopyTable(order), info
        for i, v in ipairs(order) do Current_Order[i] = v end
        BuffwatchPlayerBuffs, BuffwatchPlayerTempEnch, maxnamewidth = buffs, tempEnch, nameWidth
    end,
    Queue = function() return InCombat_Events end,
    Info = function() return Player_Info end,
}
]]

local ns = {}
W.Load("CustomBuffwatch/Buffwatch.lua", "CustomBuffwatch", ns, EXPOSE)
local B = ns

-- The window and its player-frame container, as Buffwatch.xml makes them.
local window = CreateFrame("Frame", "BuffwatchFrame", UIParent)
window:SetSize(150, 44)
window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 500, 800)
local container = CreateFrame("Frame", "BuffwatchFrame_PlayerFrame", window)
container:SetPoint("TOPLEFT", window, "TOPLEFT", 6, -18)
container:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -6, 6)

-- Four players: you with 2 buffs, then three party members with 3, 1 and 0.
local names = { "Roam", "Niuniu", "Selah", "Bob" }
local buffCounts = { 2, 3, 1, 0 }
local order, info, buffs = {}, {}, {}
for i, name in ipairs(names) do
    local v = { ID = i, Name = name, IsUnitPlayer = (i == 1) }
    order[i], info[name] = v, v
    buffs[name] = { Buffs = {} }
    for b = 1, buffCounts[i] do buffs[name].Buffs[b] = { Buff = "Buff" .. b } end
    local f = CreateFrame("Frame", "BuffwatchFrame_PlayerFrame" .. i, container)
    f:SetSize(100, 18)
    local lock = CreateFrame("CheckButton", "BuffwatchFrame_PlayerFrame" .. i .. "_Lock", f)
    lock:SetChecked(false)
end
local NAME_WIDTH = 40
B._T.Setup(order, info, buffs, {}, NAME_WIDTH)

B.framePositioned = true
local cfg = BuffwatchPlayerConfig
cfg.AnchorPoint = "Auto"
cfg.HideUnmonitored = false
cfg.Minimized = false

local function block(count) return 20 + NAME_WIDTH + count * 18 end
local function frame(i) return _G["BuffwatchFrame_PlayerFrame" .. i] end

print("Single column (both options off)")
cfg.PartySecondRow, cfg.KeepCentred = false, false
B.ResizeWindow()
W.Near(window:GetHeight(), 24 + 4 * 18, "window is 4 rows tall")
W.Near(window:GetWidth(), 32 + NAME_WIDTH + 3 * 18, "window fits the most buffs (3)")
for i = 2, 4 do
    W.Near(frame(i):GetTop(), frame(i - 1):GetTop() - 18, "player " .. i .. " sits one row below player " .. (i - 1))
    W.Near(frame(i):GetLeft(), container:GetLeft(), "player " .. i .. " starts at the left edge")
end
W.Near(window:GetLeft(), 500, "window keeps its left edge (grows right)")

print("Party members in second row")
cfg.PartySecondRow = true
B.ResizeWindow()
W.Near(frame(1):GetTop(), container:GetTop(), "you are on the top row")
W.Near(frame(1):GetLeft(), container:GetLeft(), "you start at the left edge")
for i = 2, 4 do
    W.Near(frame(i):GetTop(), container:GetTop() - 18, names[i] .. " is on the second row")
end
W.Near(frame(2):GetLeft(), container:GetLeft(), "first party member starts at the left edge")
W.Near(frame(3):GetLeft(), frame(2):GetLeft() + block(3) + B.ROW_GAP, "second party member follows the first's buffs")
W.Near(frame(4):GetLeft(), frame(3):GetLeft() + block(1) + B.ROW_GAP, "third party member follows the second's buffs")
local rowWidth = block(3) + block(1) + block(0) + 2 * B.ROW_GAP
W.Near(window:GetHeight(), 24 + 2 * 18, "window is 2 rows tall")
W.Near(window:GetWidth(), 12 + rowWidth, "window fits the whole second row")

print("Solo with the option on: back to one row")
local solo = { order[1] }
B._T.Setup(solo, { Roam = info.Roam }, { Roam = buffs.Roam }, {}, NAME_WIDTH)
for i = 2, 4 do frame(i):Hide() end
B.ResizeWindow()
W.Check(not B.UsingSecondRow(), "two-row layout not used when alone")
W.Near(window:GetHeight(), 24 + 18, "window is 1 row tall")
B._T.Setup(order, info, buffs, {}, NAME_WIDTH)

print("Keep centred")
cfg.KeepCentred = true
window:ClearAllPoints()
window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 500, 800)
window:SetWidth(150)
local centre = 500 + 150 / 2
B.ResizeWindow()
W.Near(select(1, window:GetCenter()), centre, "centre unchanged after the first resize")
W.Near(window:GetTop(), 800, "top edge unchanged")
local before = window:GetWidth()
buffs.Niuniu.Buffs[4] = { Buff = "Buff4" }
buffs.Niuniu.Buffs[5] = { Buff = "Buff5" }
B.ResizeWindow()
W.Check(window:GetWidth() > before, "window grew when buffs were added")
W.Near(select(1, window:GetCenter()), centre, "centre unchanged after growing")
buffs.Niuniu.Buffs[4], buffs.Niuniu.Buffs[5], buffs.Niuniu.Buffs[3], buffs.Niuniu.Buffs[2] = nil, nil, nil, nil
B.ResizeWindow()
W.Near(select(1, window:GetCenter()), centre, "centre unchanged after shrinking")
local point, relPoint, x, y = unpack(cfg.AutoPosition) -- saved as point, relativePoint, x, y
W.Check(point == "TOP" and relPoint == "BOTTOMLEFT", "saved position is the top centre (survives a restart)")
W.Near(x, centre, "saved x is the centre")

print("Combat: layout waits until it ends")
cfg.PartySecondRow = false
W.combat = true
B.ResizeWindow()
B.ApplyLayout()
W.Check(B.layoutPending == true, "layout marked as pending in combat")
W.Near(frame(3):GetTop(), container:GetTop() - 18, "rows not moved during combat")
W.combat = false
B.Process_InCombat_Events()
W.Check(not B.layoutPending, "pending layout applied after combat")
W.Near(frame(3):GetTop(), container:GetTop() - 2 * 18, "single column restored after combat")
W.Near(select(1, window:GetCenter()), centre, "still centred after combat")

print("After combat: buffs still unreadable doesn't loop forever")
local player = B._T.Info().Niuniu
-- Locked row (the path from the bug report): its buffs are re-read, and re-queued if unreadable.
local lockName = "BuffwatchFrame_PlayerFrame" .. player.ID .. "_Lock"
local lock = _G[lockName] or CreateFrame("CheckButton", lockName, UIParent)
lock:SetChecked(true)
local realRead = B.ReadBuff
local reads = 0
B.ReadBuff = function() reads = reads + 1; return false end
B.Add_InCombat_Events({ "GetBuffs", player })
local okRun = pcall(B.Process_InCombat_Events)
W.Check(okRun and reads < 5, "queue runs once and returns (read " .. reads .. " times)")
W.Check(#B._T.Queue() == 1, "the job waits for a retry")
W.Advance(1.1)
W.Check(reads >= 2, "retried a second later")
W.Advance(20)
local after = reads
W.Advance(5)
W.Check(reads == after, "gives up after a few retries")
B.ReadBuff = function() return true, nil end -- readable now: no buffs
B.Process_InCombat_Events()
W.Check(#B._T.Queue() == 0, "readable again: queue empties")
B.ReadBuff = realRead
lock:SetChecked(false)

W.Done()
