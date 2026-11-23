-- CustomWeaponSwap: setting swaps up by dragging onto the slots under the character screen,
-- swaps per equipment set, the bar (secure macros, highlights), /ws N and the options page.
-- Run from the repo root: lua5.1 tests/CustomWeaponSwap_test.lua

package.path = "tests/?.lua;" .. package.path
local W = require("wow")

-- Items: a staff (two-handed), a mace (one-handed), a shield, a main-hand-only dagger.
local STAFF, MACE, SHIELD, DAGGER, HELM = 101, 102, 103, 104, 105
local LOCS = { [STAFF] = "INVTYPE_2HWEAPON", [MACE] = "INVTYPE_WEAPON", [SHIELD] = "INVTYPE_SHIELD",
    [DAGGER] = "INVTYPE_WEAPONMAINHAND", [HELM] = "INVTYPE_HEAD" }
C_Item = C_Item or {}
C_Item.GetItemInfoInstant = function(id) return id, nil, nil, LOCS[id] end
C_Item.GetItemIconByID = function(id) return "icon" .. id end
C_Item.GetItemNameByID = function(id) return "item" .. id end
-- What's worn, and equipping.
local worn = { [16] = STAFF }
local equips = {}
function GetInventoryItemID(_, slot) return worn[slot] end
C_Item.EquipItemByName = function(id, slot)
    equips[#equips + 1] = { id, slot }
    worn[slot] = id
    if LOCS[id] == "INVTYPE_2HWEAPON" then worn[17] = nil end
    if slot == 17 and LOCS[worn[16]] == "INVTYPE_2HWEAPON" then worn[16] = nil end
    W.Fire("PLAYER_EQUIPMENT_CHANGED", slot)
end
-- The cursor.
local cursor
function GetCursorInfo() if cursor then return "item", cursor end end
function ClearCursor() cursor = nil end
-- Equipment sets.
local sets = { [1] = { name = "Bear", equipped = false }, [2] = { name = "Healing", equipped = true } }
C_EquipmentSet = {
    GetEquipmentSetIDs = function() return { 1, 2 } end,
    GetEquipmentSetInfo = function(id)
        local s = sets[id]
        if s then return s.name, nil, id, s.equipped end
    end,
}
CharacterFrame = CreateFrame("Frame", "CharacterFrame", UIParent)
CharacterFrame:SetSize(340, 420)
CharacterFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -80)
GameTooltip.SetItemByID = function() end

W.Load("CustomWeaponSwap/CustomWeaponSwap.lua", "CustomWeaponSwap")
W.Fire("PLAYER_LOGIN")
local A = CustomWeaponSwap

local function Drop(slot, id)
    cursor = id
    slot:GetScript("OnReceiveDrag")(slot)
end
local main1, off1 = _G.CustomWeaponSwapSetup1Main, _G.CustomWeaponSwapSetup1Off
local main2, off2 = _G.CustomWeaponSwapSetup2Main, _G.CustomWeaponSwapSetup2Off
local b1, b2, b3 = _G.CustomWeaponSwapButton1, _G.CustomWeaponSwapButton2, _G.CustomWeaponSwapButton3

print("Setup under the character screen")
W.Check(A.CurrentSet() == "Healing", "the equipped set: Healing")
local setupFrame = _G.CustomWeaponSwapSetupFrame
W.Check(setupFrame:GetParent() == CharacterFrame and setupFrame:GetTop() <= CharacterFrame:GetBottom(), "sits under the character screen")
W.Check(main1:GetParent():IsShown() and _G.CustomWeaponSwapSetup3Main:GetParent():IsShown()
    and not _G.CustomWeaponSwapSetup4Main:GetParent():IsShown(), "3 swaps by default")
Drop(main1, STAFF)
W.Check(A.Swaps()[1].main == STAFF and cursor == nil, "staff dragged onto swap 1")
Drop(off1, SHIELD)
W.Check(A.Swaps()[1].off == nil, "no off hand with a two-hander")
Drop(main2, MACE)
Drop(off2, SHIELD)
W.Check(A.Swaps()[2].main == MACE and A.Swaps()[2].off == SHIELD, "mace and shield in swap 2")
Drop(off2, DAGGER)
W.Check(A.Swaps()[2].off == SHIELD, "a main-hand-only dagger can't go in the off hand")
Drop(_G.CustomWeaponSwapSetup3Main, HELM)
W.Check(A.Swaps()[3] == nil or A.Swaps()[3].main == nil, "not a weapon: refused")
main2:GetScript("OnClick")(main2, "RightButton")
W.Check(A.Swaps()[2].main == nil and A.Swaps()[2].off == SHIELD, "right-click clears that slot")
Drop(main2, MACE)

print("The bar")
W.Check(_G.CustomWeaponSwapBar:IsShown(), "shown by default")
W.Check(b1:GetAttribute("type") == "macro" and b1:GetAttribute("macrotext") == "/equipslot 16 item:101", "swap 1's button: a secure macro")
W.Check(b2:GetAttribute("macrotext") == "/equipslot 16 item:102\n/equipslot 17 item:103", "swap 2's: main and off hand")
W.Check(b3:GetAttribute("type") == nil, "an empty swap does nothing")
W.Check(_G.WS1:GetAttribute("type") == "item" and _G.WS1:GetAttribute("item") == "item:101", "/click WS1: equips the staff (item action, not a macro)")
W.Check(_G.WS2:GetAttribute("item") == "item:102" and _G.WO2:GetAttribute("item") == "item:103", "/click WS2 and WO2: mace and shield")
W.Check(_G.WO1:GetAttribute("type") == nil, "/click WO1: nothing (no off hand)")
local function Gold(b) local r, g = b:GetBackdropBorderColor(); return r == 1 and g == 0.82 end
W.Check(Gold(b1) and not Gold(b2), "the staff is on: swap 1 highlighted")

print("/ws")
W.Slash("/ws 1")
W.Check(#equips == 0, "/ws 1 with the staff already on: nothing")
W.Slash("/ws 2")
W.Check(#equips == 2 and worn[16] == MACE and worn[17] == SHIELD, "/ws 2: mace and shield equipped")
W.Check(Gold(b2) and not Gold(b1), "highlight moves to swap 2")
W.Check(Gold(main2), "and on the setup row")
W.Slash("/ws 2")
W.Check(#equips == 2, "/ws 2 again: nothing")
W.Slash("/ws 1")
W.Check(worn[16] == STAFF and worn[17] == nil, "/ws 1: back to the staff")
local okEmpty = pcall(W.Slash, "/ws 3")
W.Check(okEmpty, "/ws 3 (empty): just a message")
W.combat = true
local before = #equips
W.Slash("/ws 2")
W.Check(#equips == before, "/ws in combat: doesn't try (the game blocks it), points to /click")
W.combat = false

print("Equipment sets")
sets[2].equipped, sets[1].equipped = false, true
W.Fire("EQUIPMENT_SWAP_FINISHED", true, 1)
W.Check(A.CurrentSet() == "Bear", "Bear set equipped: its swaps")
W.Check(b1:GetAttribute("type") == nil and main1.icon._texture == nil, "Bear has none yet")
Drop(main1, DAGGER)
W.Check(b1:GetAttribute("macrotext") == "/equipslot 16 item:104", "set up separately")
sets[1].equipped = false -- after a swap the set no longer matches exactly
W.Fire("PLAYER_EQUIPMENT_CHANGED", 16)
W.Check(A.CurrentSet() == "Bear", "still Bear (the last set equipped)")
sets[2].equipped = true
W.Fire("EQUIPMENT_SWAP_FINISHED", true, 2)
W.Check(A.Swaps()[1].main == STAFF, "back to Healing: its swaps again")

print("Combat")
W.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
local okCombat = pcall(function()
    sets[2].equipped, sets[1].equipped = false, true
    W.Fire("EQUIPMENT_SWAP_FINISHED", true, 1)
end)
W.Check(okCombat and b1:GetAttribute("macrotext") == "/equipslot 16 item:101", "no secure changes in combat")
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
W.Check(b1:GetAttribute("macrotext") == "/equipslot 16 item:104", "they catch up after")

print("Edit Mode")
local b1e = _G.CustomWeaponSwapButton1
W.TriggerCallback("EditMode.Enter")
W.Check(b1e:GetAttribute("type") == nil and _G.CustomWeaponSwapBar:IsShown(), "Edit Mode: bar unlocked (drag, not swap)")
W.TriggerCallback("EditMode.Exit")
W.Check(b1e:GetAttribute("type") == "macro", "Edit Mode closed: swapping again")

print("Options")
local opened
Settings.OpenToCategory = function(id) opened = id end
W.Slash("/ws")
W.Check(opened == "CustomWeaponSwap", "/ws opens the options")
A.panel:GetScript("OnShow")(A.panel)
W.Check(b1:GetAttribute("type") == nil, "options open: clicks drag, not swap")
W.TriggerCallback("EditMode.Enter"); W.TriggerCallback("EditMode.Exit")
W.Check(b1:GetAttribute("type") == nil, "leaving Edit Mode with the options still open: still unlocked")
local bar = _G.CustomWeaponSwapBar
local bx, by = bar:GetCenter()
W.cursor = { bx, by }
b1:GetScript("OnMouseDown")(b1, "LeftButton")
W.cursor = { bx + 100, by + 50 }
bar:GetScript("OnUpdate")(bar, 0.05)
b1:GetScript("OnMouseUp")(b1, "LeftButton")
W.Near(select(1, bar:GetCenter()), bx + 100, "dragged")
_G.CustomWeaponSwapCount:GetScript("OnValueChanged")(_G.CustomWeaponSwapCount, 5)
W.Check(_G.CustomWeaponSwapButton5:IsShown() and not _G.CustomWeaponSwapButton6:IsShown(), "5 swaps")
_G.CustomWeaponSwapBarShown:SetChecked(false)
_G.CustomWeaponSwapBarShown:Click()
A.panel:GetScript("OnHide")(A.panel)
W.Check(not bar:IsShown(), "bar turned off")
W.Check(b1:GetAttribute("type") == "macro", "closed: swapping again")
W.Check(pcall(W.Slash, "/ws debug"), "/ws debug runs")

W.Done()
