-- CustomWeaponSwap: weapon swaps that follow the equipment manager.
--
-- Each equipment set (or "No set") has a few numbered swaps. A swap is a main hand weapon and
-- an optional off hand (shield, off-hand item or second weapon), so a staff, or a mace and an
-- off hand, are each one swap.
--
--   * Set up: open the character screen; a row of swaps sits under it. Drag weapons onto the
--     slots; right-click a slot to empty it. Changing equipment set (equipment manager) shows
--     that set's swaps.
--   * Swap: a movable bar (option), click a swap; or /ws 1, /ws 2... in a macro. A swap that's
--     already equipped does nothing. The equipped swap is highlighted.
--
-- The bar's buttons are secure (they use /equipslot, so they work in combat). Their setup only
-- changes out of combat. /ws runs the same equips from Lua.

local ADDON = ...

local MAIN, OFF = 16, 17 -- inventory slots
local MAX_SWAPS = 6
local NO_SET = "(no set)"
local PREFIX = "|cff55ff55CustomWeaponSwap|r:"

local DEFAULTS = {
    count = 3,        -- swaps per set
    barShown = true,  -- the swap bar (for when the character screen is closed)
    barScale = 1,
    -- barX / barY: the bar's centre in UIParent coordinates
    -- sets[setName][i] = { main = itemID, off = itemID }
    -- lastSet: the equipment set last equipped
}

local db
local addon = {}
_G.CustomWeaponSwap = addon

local function DB()
    CustomWeaponSwapDB = CustomWeaponSwapDB or {}
    local d = CustomWeaponSwapDB
    for k, v in pairs(DEFAULTS) do
        if d[k] == nil then d[k] = v end
    end
    d.sets = d.sets or {}
    return d
end

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------

-- Where an item goes: "main" (any one-hander or main hand), "two" (two-handed), "off"
-- (off hand only), "either" (one-handers that can go in either hand), or nil (not a weapon).
local EQUIP = {
    INVTYPE_WEAPON = "either",
    INVTYPE_WEAPONMAINHAND = "main",
    INVTYPE_2HWEAPON = "two",
    INVTYPE_WEAPONOFFHAND = "off",
    INVTYPE_SHIELD = "off",
    INVTYPE_HOLDABLE = "off",
}

function addon.EquipKind(itemID)
    if not itemID then return nil end
    local info = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    local ok, _, _, _, equipLoc = pcall(info, itemID)
    if not ok then return nil end
    return EQUIP[equipLoc]
end

function addon.Icon(itemID)
    if not itemID then return nil end
    local fn = C_Item and C_Item.GetItemIconByID or GetItemIcon
    local ok, icon = pcall(fn, itemID)
    return ok and icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function Equipped(slot)
    local id = GetInventoryItemID("player", slot)
    if IsSecret(id) then return nil end
    return id
end

-------------------------------------------------------------------------------
-- Equipment sets
-------------------------------------------------------------------------------

-- The name of the equipment set in use: one that's fully equipped, else the last one equipped.
function addon.CurrentSet()
    local sets = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and C_EquipmentSet.GetEquipmentSetIDs()
    if sets then
        for _, id in ipairs(sets) do
            local name, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(id)
            if isEquipped and name then
                return name
            end
        end
        -- Still a set? (It may have been deleted.)
        if db.lastSet then
            for _, id in ipairs(sets) do
                if C_EquipmentSet.GetEquipmentSetInfo(id) == db.lastSet then
                    return db.lastSet
                end
            end
        end
    end
    return NO_SET
end

function addon.Swaps(setName)
    setName = setName or addon.CurrentSet()
    db.sets[setName] = db.sets[setName] or {}
    return db.sets[setName]
end

function addon.Swap(i, setName)
    local swaps = addon.Swaps(setName)
    swaps[i] = swaps[i] or {}
    return swaps[i]
end

-- Equipped: the main hand matches, and the off hand too if the swap has one (or the hand is
-- empty when the main hand is two-handed).
function addon.IsEquipped(i)
    local swap = addon.Swaps()[i]
    if not (swap and swap.main) then return false end
    if Equipped(MAIN) ~= swap.main then return false end
    if swap.off and Equipped(OFF) ~= swap.off then return false end
    return true
end

-------------------------------------------------------------------------------
-- Swapping
-------------------------------------------------------------------------------

local function EquipByID(itemID, slot)
    local fn = C_Item and C_Item.EquipItemByName or EquipItemByName
    pcall(fn, itemID, slot)
end

-- /ws N: equip swap N of the current set, unless it's already on.
function addon.DoSwap(i)
    local swap = addon.Swaps()[i]
    if not (swap and swap.main) then
        print(PREFIX, "swap " .. i .. " is empty for " .. addon.CurrentSet() .. ". Open the character screen to set it up.")
        return
    end
    if addon.IsEquipped(i) then
        return
    end
    if Equipped(MAIN) ~= swap.main then
        EquipByID(swap.main, MAIN)
    end
    if swap.off and Equipped(OFF) ~= swap.off then
        EquipByID(swap.off, OFF)
    end
end

-- The bar buttons' macro: the same, through /equipslot (secure, so it works in combat).
function addon.MacroText(i)
    local swap = addon.Swaps()[i]
    if not (swap and swap.main) then return nil end
    local lines = { "/equipslot " .. MAIN .. " item:" .. swap.main }
    if swap.off then
        lines[#lines + 1] = "/equipslot " .. OFF .. " item:" .. swap.off
    end
    return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------
-- Slot widgets (shared by the setup row and the bar)
-------------------------------------------------------------------------------

local function Border(frame, r, g, b, a)
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(r, g, b, a)
    end
end

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2,
}

-------------------------------------------------------------------------------
-- Setup row, under the character screen
-------------------------------------------------------------------------------

local setup = {}

local function AcceptCursor(i, hand)
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or not itemID then return end
    local where = addon.EquipKind(itemID)
    if not where then
        print(PREFIX, "that isn't a weapon or off-hand item.")
        ClearCursor()
        return
    end
    local swap = addon.Swap(i)
    if hand == "main" then
        if where == "off" then
            print(PREFIX, "that only goes in the off hand.")
            ClearCursor()
            return
        end
        swap.main = itemID
        if where == "two" then swap.off = nil end
    else
        if where == "main" or where == "two" then
            print(PREFIX, "that can't go in the off hand.")
            ClearCursor()
            return
        end
        if swap.main and addon.EquipKind(swap.main) == "two" then
            print(PREFIX, "the main hand is two-handed, so there's no off hand.")
            ClearCursor()
            return
        end
        swap.off = itemID
    end
    ClearCursor()
    addon.Refresh()
end

local function SetupSlot(parent, i, hand)
    local b = CreateFrame("Button", "CustomWeaponSwapSetup" .. i .. (hand == "main" and "Main" or "Off"), parent,
        "BackdropTemplate")
    b:SetSize(hand == "main" and 34 or 26, hand == "main" and 34 or 26)
    b:SetBackdrop(BACKDROP)
    b:SetBackdropColor(0, 0, 0, 0.6)
    b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.i, b.hand = i, hand
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnReceiveDrag", function(self) AcceptCursor(self.i, self.hand) end)
    b:SetScript("OnClick", function(self, button)
        if GetCursorInfo() then
            AcceptCursor(self.i, self.hand)
        elseif button == "RightButton" then
            local swap = addon.Swap(self.i)
            swap[self.hand] = nil
            addon.Refresh()
        end
    end)
    b:SetScript("OnEnter", function(self)
        local id = addon.Swap(self.i)[self.hand]
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if id then
            GameTooltip:SetItemByID(id)
            GameTooltip:AddLine("Right-click to clear.", 0.7, 0.7, 0.7)
        else
            GameTooltip:SetText(hand == "main" and "Main hand" or "Off hand (optional)")
            GameTooltip:AddLine("Drag a weapon here.", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function addon.BuildSetup()
    if setup.frame or not CharacterFrame then return end
    local f = CreateFrame("Frame", "CustomWeaponSwapSetupFrame", CharacterFrame, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 0, -2)
    f:SetHeight(76)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 10, -8)
    setup.title = title
    setup.frame = f
    setup.rows = {}
    for i = 1, MAX_SWAPS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(70, 50)
        local number = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        number:SetPoint("TOPLEFT", 0, 0)
        number:SetText(i)
        row.main = SetupSlot(row, i, "main")
        row.main:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -2)
        row.off = SetupSlot(row, i, "off")
        row.off:SetPoint("BOTTOMLEFT", row.main, "BOTTOMRIGHT", 3, 0)
        setup.rows[i] = row
    end
end

-------------------------------------------------------------------------------
-- The swap bar
-------------------------------------------------------------------------------

local bar = {}

function addon.BuildBar()
    if bar.frame then return end
    local f = CreateFrame("Frame", "CustomWeaponSwapBar", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetSize(40, 40)
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", f, "TOP", 0, 3)
    label:SetText("Weapon swaps: drag to move")
    label:Hide()
    bar.frame, bar.label, bar.buttons = f, label, {}
    for i = 1, MAX_SWAPS do
        -- Short global names (WS1, WS2...) so "/click WS1" fits in a crowded macro.
        local b = CreateFrame("Button", "WS" .. i, f, "SecureActionButtonTemplate,BackdropTemplate")
        b:SetSize(36, 36)
        b:SetBackdrop(BACKDROP)
        b:SetBackdropColor(0, 0, 0, 0.6)
        b:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.offIcon = b:CreateTexture(nil, "OVERLAY")
        b.offIcon:SetSize(16, 16)
        b.offIcon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.offIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.number = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.number:SetPoint("TOPLEFT", 3, -3)
        b.number:SetText(i)
        b.i = i
        -- Dragging the bar while its options are open.
        b:HookScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and addon.unlocked and not InCombatLockdown() then
                addon.StartDrag()
            end
        end)
        b:HookScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then addon.StopDrag() end
        end)
        b:SetScript("OnEnter", function(self)
            local swap = addon.Swaps()[self.i]
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if swap and swap.main then
                GameTooltip:SetItemByID(swap.main)
                if swap.off then
                    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(swap.off)
                    GameTooltip:AddLine("Off hand: " .. tostring(name or ("item " .. swap.off)), 1, 1, 1)
                end
                GameTooltip:AddLine("Click (or /ws " .. self.i .. ") to equip.", 0.7, 0.7, 0.7)
            else
                GameTooltip:SetText("Swap " .. self.i .. " (empty)")
                GameTooltip:AddLine("Set it up under the character screen.", 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.buttons[i] = b
    end
end

function addon.StartDrag()
    local f = bar.frame
    local scale = f:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local cx, cy = f:GetCenter()
    bar.drag = { dx = cx - x / scale, dy = cy - y / scale }
    f:SetScript("OnUpdate", function()
        local mx, my = GetCursorPosition()
        db.barX, db.barY = mx / scale + bar.drag.dx, my / scale + bar.drag.dy
        addon.PlaceBar()
    end)
end

function addon.StopDrag()
    if bar.drag then
        bar.drag = nil
        bar.frame:SetScript("OnUpdate", nil)
    end
end

function addon.PlaceBar()
    local f = bar.frame
    if not f or InCombatLockdown() then return end
    f:SetScale(db.barScale or 1)
    f:ClearAllPoints()
    if db.barX and db.barY then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.barX, db.barY)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    end
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------

-- Highlights (any time) and the setup row's contents.
function addon.RefreshLooks()
    local count = db.count
    if bar.buttons then
        for i = 1, count do
            local b = bar.buttons[i]
            local swap = addon.Swaps()[i]
            b.icon:SetTexture(swap and swap.main and addon.Icon(swap.main) or nil)
            b.icon:SetDesaturated(not (swap and swap.main))
            b.offIcon:SetTexture(swap and swap.off and addon.Icon(swap.off) or nil)
            if addon.IsEquipped(i) then
                Border(b, 1, 0.82, 0, 1) -- gold: equipped
            else
                Border(b, 0.2, 0.2, 0.2, 1)
            end
        end
    end
    if setup.frame then
        setup.title:SetText("Weapon swaps for: " .. addon.CurrentSet())
        for i = 1, MAX_SWAPS do
            local row = setup.rows[i]
            row:SetShown(i <= count)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", setup.frame, "TOPLEFT", 10 + (i - 1) * 74, -22)
            local swap = addon.Swaps()[i] or {}
            for _, hand in ipairs({ "main", "off" }) do
                local slot = row[hand]
                slot.icon:SetTexture(swap[hand] and addon.Icon(swap[hand]) or nil)
                if i <= count and addon.IsEquipped(i) then
                    Border(slot, 1, 0.82, 0, 1)
                else
                    Border(slot, 0.3, 0.3, 0.3, 1)
                end
            end
        end
        setup.frame:SetWidth(math.max(CharacterFrame:GetWidth() or 0, 20 + count * 74))
    end
end

-- Everything, including the secure parts (only out of combat).
function addon.Refresh()
    if not db then return end
    addon.RefreshLooks()
    if not bar.frame then return end
    if InCombatLockdown() then
        addon.pending = true
        return
    end
    addon.pending = false
    local count = db.count
    for i = 1, MAX_SWAPS do
        local b = bar.buttons[i]
        b:SetShown(i <= count)
        b:ClearAllPoints()
        b:SetPoint("LEFT", bar.frame, "LEFT", (i - 1) * 40, 0)
        local text = addon.MacroText(i)
        if addon.unlocked or not text then
            b:SetAttribute("type", nil) -- dragging (or nothing to equip), not swapping
            b:SetAttribute("typerelease", nil)
        else
            b:SetAttribute("type", "macro")
            -- With "cast on key down" on, secure buttons only act on the press, but /click only
            -- sends a release: "typerelease" makes the release act too (a second equip of the
            -- same weapons does nothing).
            b:SetAttribute("typerelease", "macro")
            b:SetAttribute("macrotext", text)
        end
    end
    bar.frame:SetWidth(math.max(40, count * 40 - 4))
    bar.frame:SetShown(db.barShown or addon.unlocked)
    bar.label:SetShown(addon.unlocked or false)
    addon.PlaceBar()
end

-------------------------------------------------------------------------------
-- Options page
-------------------------------------------------------------------------------

local panel = CreateFrame("Frame", "CustomWeaponSwapOptions", UIParent)
panel.name = "CustomWeaponSwap"
panel:Hide()
addon.panel = panel
do
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("CustomWeaponSwap")
    local about = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    about:SetWidth(560)
    about:SetJustifyH("LEFT")
    about:SetText("Set up swaps under the character screen: drag weapons onto the slots (main hand, then an "
        .. "optional off hand), right-click to clear. Each equipment set has its own swaps. Swap with the bar or "
        .. "/ws 1, /ws 2...; a swap that's already on does nothing. While this page is open, drag the bar to move it.")

    local widgets = {}
    local shown = CreateFrame("CheckButton", "CustomWeaponSwapBarShown", panel, "UICheckButtonTemplate")
    shown:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -14)
    local text = shown.Text or _G["CustomWeaponSwapBarShownText"]
    if text then text:SetText("Show the swap bar") end
    shown:SetScript("OnClick", function(self)
        db.barShown = self:GetChecked() and true or false
        addon.Refresh()
    end)
    widgets[#widgets + 1] = function() shown:SetChecked(db.barShown) end

    local function Slider(name, anchor, label, key, low, high, step, fmt)
        local s = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -30)
        s:SetWidth(240)
        s:SetMinMaxValues(low, high)
        s:SetValueStep(step)
        if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
        local t = s.Text or _G[name .. "Text"]
        s:SetScript("OnValueChanged", function(_, v)
            v = math.floor(v / step + 0.5) * step
            db[key] = v
            if t then t:SetText(label .. ": " .. string.format(fmt, v)) end
            addon.Refresh()
        end)
        widgets[#widgets + 1] = function()
            s:SetValue(db[key])
            if t then t:SetText(label .. ": " .. string.format(fmt, db[key])) end
        end
        return s
    end
    local countSlider = Slider("CustomWeaponSwapCount", shown, "Swaps per set", "count", 1, MAX_SWAPS, 1, "%d")
    Slider("CustomWeaponSwapScale", countSlider, "Bar size", "barScale", 0.5, 2, 0.05, "%.2f")

    panel:SetScript("OnShow", function()
        for _, w in ipairs(widgets) do w() end
        addon.SetUnlocked(true)
    end)
    panel:SetScript("OnHide", function() addon.SetUnlocked(false) end)
end

function addon.SetUnlocked(on)
    addon.unlocked = on and true or false
    if not on then addon.StopDrag() end
    addon.Refresh()
end

function addon.OpenOptions()
    if InCombatLockdown() then
        print(PREFIX, "options can't be opened in combat.")
        return
    end
    if addon.category and Settings and Settings.OpenToCategory then
        if not pcall(Settings.OpenToCategory, addon.category:GetID()) then
            pcall(Settings.OpenToCategory, addon.category)
        end
    end
end

-------------------------------------------------------------------------------
-- Events and commands
-------------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SWAP_FINISHED", "EQUIPMENT_SETS_CHANGED",
    "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        db = DB()
        addon.BuildSetup()
        addon.BuildBar()
        if Settings and Settings.RegisterCanvasLayoutCategory then
            addon.category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
            Settings.RegisterAddOnCategory(addon.category)
        end
        addon.Refresh()
        return
    end
    if not db then return end
    if event == "EQUIPMENT_SWAP_FINISHED" then
        -- a1: succeeded, a2: the set's ID.
        if a1 and a2 and C_EquipmentSet then
            local name = C_EquipmentSet.GetEquipmentSetInfo(a2)
            if name then db.lastSet = name end
        end
        addon.Refresh()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "GET_ITEM_INFO_RECEIVED" then
        addon.RefreshLooks()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if addon.pending then addon.Refresh() end
    else
        addon.Refresh()
    end
end)

SLASH_CUSTOMWEAPONSWAP1 = "/ws"
SLASH_CUSTOMWEAPONSWAP2 = "/weaponswap"
SlashCmdList.CUSTOMWEAPONSWAP = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local n = tonumber(msg)
    if n then
        if db then addon.DoSwap(math.floor(n)) end
        return
    end
    if msg == "debug" then
        print(PREFIX, "set:", addon.CurrentSet(), "| last set:", tostring(db.lastSet), "| swaps:", db.count,
            "| bar shown:", tostring(bar.frame and bar.frame:IsShown()), "| in combat:", tostring(InCombatLockdown()))
        print("  equipped: main", tostring(Equipped(MAIN)), "off", tostring(Equipped(OFF)))
        for i = 1, db.count do
            local swap = addon.Swaps()[i] or {}
            print("  " .. i .. ":", "main", tostring(swap.main), "off", tostring(swap.off),
                "| equipped:", tostring(addon.IsEquipped(i)), "| macro:", (addon.MacroText(i) or "none"):gsub("\n", " / "))
        end
        return
    end
    addon.OpenOptions()
end
