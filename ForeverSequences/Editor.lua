-- Forever Sequences editor: a library of sequences, the windows that show them, and the
-- sequences' rows of icons.
--
--   - Left, top: windows, each with the sequences it shows, in display order. Tick to show or
--     hide, arrows to reorder, drag a sequence onto another window (or before another
--     sequence) to move it there.
--   - Left, bottom: the library, every sequence you've made. Drag one onto a window to show
--     it there too; the same sequence can be in several windows. Copy makes an independent
--     copy to change for another window.
--   - Right: the selected window's settings, then the selected sequence's rows.
--   - Beside it: every spell you know (in spellbook order) and every usable item you carry,
--     to drag into a row (or click to add to the end of the Primary).
--   - Drag a spell from the spellbook or an item from your bags onto a slot; the "+" slot
--     adds at the end. Drag an icon within its row to move it, onto another row to copy it
--     (from the Primary onto a sub-sequence's "+" slot it goes in Primary order), or off the
--     window to remove it. Shift-right-click also removes. Right-click a spell to step down
--     through the ranks you know ("R3" on the icon), and back round to your highest.
--   - While this is open every window is shown and can be dragged to move it.

local _, ns = ...

local MAX_ENTRIES = 8
local SLOT_SIZE = 34
local SLOT_GAP = 4
local SUB_BLOCK_HEIGHT = SLOT_SIZE + 20
local WINDOW_ROWS = 11
local LIBRARY_ROWS = 9
local LIST_ROW_HEIGHT = 22
local LEFT = 20
local RIGHT_X = 250
local PICKER_WIDTH = 300
local PICKER_ROW_HEIGHT = 30
local REGEN_MODES = { "smooth", "ticks", "off" }
local REGEN_LABELS = { smooth = "Regen: smooth", ticks = "Regen: 2s ticks", off = "Regen: off" }

local editor
local selWindow -- the selected window (nil when a library sequence is picked on its own)
local selItem   -- the selected placement of a sequence in selWindow, or nil
local selSeq    -- the selected sequence (from the library), or nil
local windowOffset, libraryOffset = 0, 0
local drag      -- an icon being dragged: { entry, row (nil from the list of spells), index }
local listDrag  -- a sequence being dragged: { def, window and item (nil from the library) }
-- A sequence picked under a window is only shown; it's edited from the library.
local function ReadOnly()
    return selItem ~= nil
end

-- The selected sequence's rows only change while it's unlocked; until it's locked again, its
-- variations keep their order (so a row doesn't jump while you're adding to it), and an
-- empty sub-sequence waits at the bottom.
local function Unlocked()
    return selSeq ~= nil and ns.unsortedSequence == selSeq and not ReadOnly()
end

local function IsEmpty(sub)
    return #sub.entries == 0
end

-- While unlocked, the last sub-sequence is always an empty one to add to.
local function KeepEmptyRow()
    local def = ns.unsortedSequence
    if def then
        local last = def.subs[#def.subs]
        if not last or not IsEmpty(last) then
            def.subs[#def.subs + 1] = { entries = {}, hideOnCooldown = false }
        end
    end
end

local function Print(msg)
    ns.Print(msg)
end

local function Windows()
    return ns.db.windows
end

local function Library()
    return ns.db.library
end

local function Changed()
    -- An edit can make a sub-sequence the costliest; the Primary is always the costliest.
    KeepEmptyRow()
    ns.SortAllVariations()
    ns.RequestRebuild()
    if editor then
        editor:Refresh()
    end
end

-- Lock the unlocked sequence: empty sub-sequences go, and the variations sort again.
local function Lock()
    local def = ns.unsortedSequence
    if not def then
        return
    end
    ns.unsortedSequence = nil
    for i = #def.subs, 1, -1 do
        if IsEmpty(def.subs[i]) then
            table.remove(def.subs, i)
        end
    end
    Changed()
end

local function IndexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then
            return i
        end
    end
    return nil
end

local function ItemIndex(window, id)
    for i, item in ipairs(window.items) do
        if item.id == id then
            return i
        end
    end
    return nil
end

-- Names of the windows a sequence is in.
local function UsedIn(def)
    local names = {}
    for _, window in ipairs(Windows()) do
        if ItemIndex(window, def.id) then
            names[#names + 1] = window.name or "?"
        end
    end
    return names
end

----------------------------------------------------------------------------------------------
-- Small widgets (standard Blizzard templates and art)
----------------------------------------------------------------------------------------------

local function NewButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function NewCheck(parent, label, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", check, "RIGHT", 2, 1)
    text:SetText(label)
    check.label = text
    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    return check
end

local function NewLabel(parent, text, template)
    local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    label:SetText(text)
    return label
end

local function NewArrow(parent, up, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(20, 20)
    local name = up and "ScrollUp" or "ScrollDown"
    button:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-" .. name .. "-Up")
    button:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-" .. name .. "-Down")
    button:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-" .. name .. "-Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", onClick)
    return button
end

local function NewEditBox(parent, width, onSave)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    box:SetScript("OnEnterPressed", function(self)
        onSave(self:GetText())
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        onSave(self:GetText())
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if editor then
            editor:Refresh()
        end
    end)
    return box
end

local function Tooltip(frame, title, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if text then
            GameTooltip:AddLine(text, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Backdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
end

----------------------------------------------------------------------------------------------
-- Dragging icons
----------------------------------------------------------------------------------------------

local ghost = CreateFrame("Frame", nil, UIParent)
ghost:SetSize(SLOT_SIZE, SLOT_SIZE)
ghost:SetFrameStrata("TOOLTIP")
ghost:Hide()
local ghostIcon = ghost:CreateTexture(nil, "ARTWORK")
ghostIcon:SetAllPoints()
ghostIcon:SetAlpha(0.8)
ghost:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end)

local slotRows = {} -- every slot row in the editor: { list = function, isPrimary, slots }

local function Insert(list, index, entry)
    if #list >= MAX_ENTRIES then
        Print("a row holds up to " .. MAX_ENTRIES .. " icons.")
        return false
    end
    table.insert(list, math.max(1, math.min(index, #list + 1)), entry)
    return true
end

-- Where an entry from the Primary goes in a sub-sequence to keep the Primary's order.
local function PrimaryOrderIndex(target, primary, fromIndex)
    local function PrimaryIndex(entry)
        for i, e in ipairs(primary) do
            if ns.SameEntry(e, entry) then
                return i
            end
        end
        return nil
    end
    for j, entry in ipairs(target) do
        local p = PrimaryIndex(entry)
        if p and p > fromIndex then
            return j
        end
    end
    return #target + 1
end

local function SlotUnderMouse()
    if not Unlocked() then
        return nil
    end
    for _, row in ipairs(slotRows) do
        if row.frame:IsVisible() and (not row.clip or row.clip:IsMouseOver()) then
            for index, slot in ipairs(row.slots) do
                if slot:IsVisible() and slot:IsMouseOver() then
                    return row, index
                end
            end
        end
    end
    return nil
end

local function StartDrag(entry, row, index)
    drag = { entry = entry, row = row, index = index }
    ghostIcon:SetTexture(ns.ResolveEntry(entry).icon)
    ghost:Show()
end

local function FinishDrag()
    if not drag then
        return
    end
    ghost:Hide()
    local source = drag
    drag = nil

    local targetRow, targetIndex = SlotUnderMouse()
    if not targetRow then
        -- Dropped off the window: remove it from its row.
        if source.row and not editor:IsMouseOver() and not editor.picker:IsMouseOver() then
            table.remove(source.row.list(), source.index)
            Changed()
        end
        return
    end

    local targetList = targetRow.list()
    if targetRow == source.row then
        -- Move within the row.
        if targetIndex == source.index then
            return
        end
        local entry = table.remove(targetList, source.index)
        if targetIndex > source.index then
            targetIndex = targetIndex - 1
        end
        table.insert(targetList, math.min(targetIndex, #targetList + 1), entry)
    else
        -- Copy into another row.
        local entry = ns.CopyTable(source.entry)
        if source.row and source.row.isPrimary and not targetRow.isPrimary and targetIndex > #targetList then
            targetIndex = PrimaryOrderIndex(targetList, source.row.list(), source.index)
        end
        if not Insert(targetList, targetIndex, entry) then
            return
        end
    end
    Changed()
end

-- A spell or item on the game's cursor, dropped on a slot.
local function DropCursor(row, index)
    local entry, problem = ns.EntryFromCursor()
    if entry then
        if Insert(row.list(), index, entry) then
            ClearCursor()
            Changed()
        end
    elseif problem then
        Print(problem)
    end
end

-- Step a spell one rank down (shift-right-click) or up (ctrl-click). Down stops at rank 1;
-- up to your highest rank unpins it, so it follows newly learned ranks again.
local function StepRank(row, index, delta)
    local entry = row.list()[index]
    if not entry or entry.kind ~= "spell" then
        return
    end
    local ranks = ns.KnownRanks(entry.name)
    if #ranks <= 1 then
        Print(entry.name .. ": only one rank known.")
        return
    end
    -- Where it is now: its pinned rank (or the highest known below it), else the highest.
    local current = #ranks
    if entry.rank then
        current = 1
        for i, rank in ipairs(ranks) do
            if rank <= entry.rank then
                current = i
            end
        end
    end
    local target = current + delta
    if target < 1 then
        Print(entry.name .. ": already rank " .. ranks[1] .. ", the lowest.")
        return
    end
    if target >= #ranks then
        if not entry.rank then
            Print(entry.name .. ": already your highest rank.")
            return
        end
        entry.rank = nil
    else
        entry.rank = ranks[target]
    end
    Changed()
end

----------------------------------------------------------------------------------------------
-- Slot rows
----------------------------------------------------------------------------------------------

local function EntryTooltip(owner, entry)
    local info = ns.ResolveEntry(entry)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if info.itemID then
        GameTooltip:SetItemByID(info.itemID)
    elseif info.spellID then
        GameTooltip:SetSpellByID(info.spellID)
    else
        GameTooltip:SetText(ns.EntryName(entry))
    end
    if entry.kind == "manapot" then
        GameTooltip:AddLine("Best mana potion: the best one in your bags, counting its lowest restore.", 1, 1, 1, true)
    end
    return info
end

local function SlotTooltip(slot)
    local entry = slot.row.list()[slot.index]
    if entry then
        EntryTooltip(slot, entry)
        if entry.kind == "spell" and entry.rank then
            GameTooltip:AddLine("Pinned to rank " .. entry.rank, 0.4, 0.8, 1)
        end
        if ReadOnly() then
            GameTooltip:AddLine("Press Edit in library to change this sequence.", 0.6, 0.6, 0.6, true)
        elseif not Unlocked() then
            GameTooltip:AddLine("Press Unlock to change the rows.", 0.6, 0.6, 0.6, true)
        else
            GameTooltip:AddLine("Drag to move or copy, or off the window to remove.", 0.6, 0.6, 0.6, true)
            if entry.kind == "spell" then
                GameTooltip:AddLine("Right-click: remove. Shift-right-click: one rank down. Ctrl-click: one rank up "
                    .. "(at your highest rank it follows new ranks again).", 0.6, 0.6, 0.6, true)
            else
                GameTooltip:AddLine("Right-click: remove.", 0.6, 0.6, 0.6, true)
            end
        end
    else
        GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add to this row")
        GameTooltip:AddLine("Drop a spell or item here: from the list beside this window, your spellbook, " ..
            "your bags, or another row.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function CreateSlot(row, index)
    local slot = CreateFrame("Button", nil, row.frame)
    slot:SetSize(SLOT_SIZE, SLOT_SIZE)
    slot:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (index - 1) * (SLOT_SIZE + SLOT_GAP), 0)
    slot.row, slot.index = row, index

    local back = slot:CreateTexture(nil, "BACKGROUND")
    back:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    back:SetPoint("CENTER")
    back:SetSize(SLOT_SIZE * 1.6, SLOT_SIZE * 1.6)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    slot.plus = slot:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    slot.plus:SetPoint("CENTER", 0, 1)
    slot.plus:SetText("+")

    slot.rank = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    slot.rank:SetPoint("BOTTOMRIGHT", -1, 2)

    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:RegisterForDrag("LeftButton")

    slot:SetScript("OnClick", function(self, button)
        if not Unlocked() then
            return
        end
        if GetCursorInfo() then
            DropCursor(self.row, self.index)
        elseif IsControlKeyDown() and self.row.list()[self.index] then
            StepRank(self.row, self.index, 1)
        elseif button == "RightButton" and self.row.list()[self.index] then
            if IsShiftKeyDown() then
                StepRank(self.row, self.index, -1)
            else
                table.remove(self.row.list(), self.index)
                Changed()
            end
        end
    end)
    slot:SetScript("OnReceiveDrag", function(self)
        if Unlocked() then
            DropCursor(self.row, self.index)
        end
    end)
    slot:SetScript("OnDragStart", function(self)
        local entry = self.row.list()[self.index]
        if entry and not GetCursorInfo() and Unlocked() then
            StartDrag(entry, self.row, self.index)
        end
    end)
    slot:SetScript("OnDragStop", FinishDrag)
    slot:SetScript("OnEnter", SlotTooltip)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return slot
end

-- A row of slots for a list of entries. `list` returns the list it shows (it changes as the
-- selection changes).
local function CreateSlotRow(parent, list, isPrimary)
    local row = { list = list, isPrimary = isPrimary, slots = {} }
    row.frame = CreateFrame("Frame", nil, parent)
    row.frame:SetSize((MAX_ENTRIES + 1) * (SLOT_SIZE + SLOT_GAP), SLOT_SIZE)
    for i = 1, MAX_ENTRIES + 1 do
        row.slots[i] = CreateSlot(row, i)
    end
    slotRows[#slotRows + 1] = row
    return row
end

local function RefreshSlotRow(row)
    local list = row.list() or {}
    for i, slot in ipairs(row.slots) do
        local entry = list[i]
        if entry then
            local info = ns.ResolveEntry(entry)
            slot.icon:SetTexture(info.icon)
            local unlearned = info.known == false
            slot.icon:SetDesaturated(unlearned)
            slot.icon:SetVertexColor(unlearned and 0.5 or 1, unlearned and 0.5 or 1, unlearned and 0.5 or 1)
            slot.icon:Show()
            slot.plus:Hide()
            slot.rank:SetText(ns.RankText(info) or "")
            slot:Show()
        elseif i == #list + 1 and i <= MAX_ENTRIES and Unlocked() then
            slot.icon:Hide()
            slot.plus:Show()
            slot.rank:SetText("")
            slot:Show()
        else
            slot:Hide()
        end
    end
end

-- "Mana cost: X (Y gained)": what the row costs in all, and the mana regained before its last
-- icon plus any potions or other restores in it.
local function CostText(entries)
    if not entries or #entries == 0 then
        return ""
    end
    local missing = ns.Unlearned(entries)
    if #missing > 0 then
        return "|cffff8080Not learned yet: " .. table.concat(missing, ", ") .. "|r (left out of windows until then)"
    end
    local cost, gained = ns.CostSummary(entries)
    -- The gain is shown negative: it comes off the cost.
    return string.format("Mana cost: %d (%s gained)", cost, gained ~= 0 and ("-" .. gained) or "0")
end

----------------------------------------------------------------------------------------------
-- Windows, the library, and placements
----------------------------------------------------------------------------------------------

StaticPopupDialogs["FOREVERSEQUENCES_DELETE"] = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data)
        if data and data.def then
            -- Delete from the library, and from every window that shows it.
            table.remove(Library(), IndexOf(Library(), data.def))
            for _, window in ipairs(Windows()) do
                local index = ItemIndex(window, data.def.id)
                while index do
                    table.remove(window.items, index)
                    index = ItemIndex(window, data.def.id)
                end
            end
            selSeq, selItem = nil, nil
        elseif data and data.window then
            table.remove(Windows(), IndexOf(Windows(), data.window))
            selWindow, selItem = Windows()[1], nil
        end
        Changed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function Confirm(text, data)
    local popup = StaticPopup_Show("FOREVERSEQUENCES_DELETE", text)
    if popup then
        popup.data = data
    end
end

-- A window's type is chosen when it's made and can't be changed afterwards.
local function AddWindow(windowType)
    local list = Windows()
    local window = ns.NewWindow("Window " .. (#list + 1))
    window.type = windowType
    list[#list + 1] = window
    selWindow, selItem, selSeq = window, nil, nil
    Changed()
end

StaticPopupDialogs["FOREVERSEQUENCES_NEW_WINDOW"] = {
    text = "New window. Which type?\n\nDynamic: one row per sequence, showing whichever of its sequences fits " ..
        "your mana; can show only when mana or health is low, or for some targets.\n\nFixed: the Primary is " ..
        "always shown and can be clicked to cast. Nothing moves.\n\nYou can switch it later.",
    button1 = "Dynamic",
    button2 = CANCEL or "Cancel",
    button3 = "Fixed",
    OnAccept = function() AddWindow("dynamic") end,
    OnAlt = function() AddWindow("fixed") end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function NewWindow()
    StaticPopup_Show("FOREVERSEQUENCES_NEW_WINDOW")
end

-- Show a library sequence in a window, before `beforeIndex` (default: at the end).
local function Place(def, window, beforeIndex)
    if ItemIndex(window, def.id) then
        Print("\"" .. (def.name or "?") .. "\" is already in " .. (window.name or "?") .. ".")
        return nil
    end
    local item = { id = def.id, enabled = true }
    table.insert(window.items, math.min(beforeIndex or #window.items + 1, #window.items + 1), item)
    return item
end

-- A new sequence goes in the library, and in the selected window if there is one.
local function NewSequence()
    local library = Library()
    local def = {
        id = ns.NewId(),
        name = "Sequence " .. (#library + 1),
        hideOnCooldown = false,
        entries = {},
        subs = {},
    }
    library[#library + 1] = def
    selSeq = def
    selItem = selWindow and Place(def, selWindow) or nil
    -- Placed in a window it's shown read-only there; from the library, ready to fill.
    if not selItem then
        Lock()
        ns.unsortedSequence = def
    end
    Changed()
end

-- An independent copy, next to the original in the library, to change for another window.
local function CopySequence()
    if not selSeq then
        return
    end
    local copy = ns.CopyTable(selSeq)
    copy.id = ns.NewId()
    copy.name = (selSeq.name or "?") .. " (copy)"
    local library = Library()
    table.insert(library, (IndexOf(library, selSeq) or #library) + 1, copy)
    selWindow, selItem, selSeq = nil, nil, copy
    Print("copied. Drag \"" .. copy.name .. "\" from the library onto a window to show it there.")
    Changed()
end

local function Move(list, item, delta)
    local index = IndexOf(list, item)
    local other = index and index + delta
    if not other or other < 1 or other > #list then
        return
    end
    list[index], list[other] = list[other], list[index]
    Changed()
end

-- The windows list: each window, then the sequences it shows.
local function WindowListItems()
    local items = {}
    for _, window in ipairs(Windows()) do
        items[#items + 1] = { window = window }
        for _, item in ipairs(window.items) do
            local def = ns.FindSequence(item.id)
            if def then
                items[#items + 1] = { window = window, item = item, def = def }
            end
        end
    end
    return items
end


----------------------------------------------------------------------------------------------
-- The two lists on the left
----------------------------------------------------------------------------------------------

local windowRows, libraryRows = {}, {}

local function StartListDrag(data)
    listDrag = data
    local first = data.def.entries[1]
    ghostIcon:SetTexture(first and ns.ResolveEntry(first).icon or 134400)
    ghost:Show()
end

-- Dropped on the windows list: onto a window (to the end of it) or a sequence (before it).
local function FinishListDrag()
    if not listDrag then
        return
    end
    ghost:Hide()
    local source = listDrag
    listDrag = nil
    for _, row in ipairs(windowRows) do
        local data = row.data
        if row:IsVisible() and row:IsMouseOver() and data and not (source.item and data.item == source.item) then
            local target = data.window
            if source.window then
                -- Move from one window (or place in it) to another.
                local from = IndexOf(source.window.items, source.item)
                if source.window ~= target and ItemIndex(target, source.def.id) then
                    Print("\"" .. (source.def.name or "?") .. "\" is already in " .. (target.name or "?") .. ".")
                    return
                end
                table.remove(source.window.items, from)
                local index = data.item and IndexOf(target.items, data.item) or #target.items + 1
                table.insert(target.items, index, source.item)
                selWindow, selItem, selSeq = target, source.item, source.def
            else
                -- From the library: show it in this window too.
                local index = data.item and IndexOf(target.items, data.item) or nil
                local item = Place(source.def, target, index)
                if not item then
                    return
                end
                selWindow, selItem, selSeq = target, item, source.def
            end
            Changed()
            return
        end
    end
end

local function NewListRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(parent:GetWidth(), LIST_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:RegisterForDrag("LeftButton")
    row.selectedTexture = row:CreateTexture(nil, "BACKGROUND")
    row.selectedTexture:SetAllPoints()
    row.selectedTexture:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.selectedTexture:SetBlendMode("ADD")
    row.selectedTexture:SetVertexColor(1, 0.82, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    return row
end

local function CreateWindowRow(f, area, i)
    local row = NewListRow(area, i)
    row.enabled = NewCheck(row, "", function(checked)
        local target = row.data and (row.data.item or row.data.window)
        if target then
            target.enabled = checked
            Changed()
        end
    end)
    Tooltip(row.enabled, "Show on screen", "Unticked ones are kept but hidden, and take no space.")

    local function Shift(delta)
        local data = row.data
        if data.item then
            Move(data.window.items, data.item, delta)
        else
            Move(Windows(), data.window, delta)
        end
    end
    row.down = NewArrow(row, false, function() Shift(1) end)
    row.down:SetPoint("RIGHT", 0, 0)
    row.up = NewArrow(row, true, function() Shift(-1) end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", 0, 0)
    row.text:SetPoint("RIGHT", row.up, "LEFT", -2, 0)

    row:SetScript("OnClick", function(self)
        selWindow, selItem, selSeq = self.data.window, self.data.item, self.data.def
        f.subScroll:SetVerticalScroll(0)
        f:Refresh()
    end)
    row:SetScript("OnDragStart", function(self)
        if self.data and self.data.item then
            StartListDrag({ def = self.data.def, window = self.data.window, item = self.data.item })
        end
    end)
    row:SetScript("OnDragStop", FinishListDrag)
    return row
end

local function CreateLibraryRow(f, area, i)
    local row = NewListRow(area, i)
    row.down = NewArrow(row, false, function() if row.def then Move(Library(), row.def, 1) end end)
    row.down:SetPoint("RIGHT", 0, 0)
    row.up = NewArrow(row, true, function() if row.def then Move(Library(), row.def, -1) end end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", 0, 0)
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetPoint("RIGHT", row.up, "LEFT", -2, 0)
    row:SetScript("OnClick", function(self)
        selWindow, selItem, selSeq = nil, nil, self.def
        f.subScroll:SetVerticalScroll(0)
        f:Refresh()
    end)
    row:SetScript("OnDragStart", function(self)
        if self.def then
            StartListDrag({ def = self.def })
        end
    end)
    row:SetScript("OnDragStop", FinishListDrag)
    row:SetScript("OnEnter", function(self)
        if not self.def then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.def.name or "?")
        local used = UsedIn(self.def)
        GameTooltip:AddLine(#used > 0 and ("Used in: " .. table.concat(used, ", ")) or "Not in any window yet.", 1, 1, 1, true)
        GameTooltip:AddLine("Drag onto a window to show it there.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function ScrollArea(f, rowsShown, onWheel)
    local area = CreateFrame("Frame", nil, f)
    area:SetSize(RIGHT_X - LEFT - 16, rowsShown * LIST_ROW_HEIGHT)
    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(_, delta)
        onWheel(delta)
        f:Refresh()
    end)
    return area
end

-- Beside the editor: sections of rows (icon, name, a short line) in a scroll frame.
local function CreatePicker(f)
    local picker = CreateFrame("Frame", nil, f, "BackdropTemplate")
    picker:SetPoint("TOPLEFT", f, "TOPRIGHT", -6, 0)
    picker:SetSize(PICKER_WIDTH, f:GetHeight())
    Backdrop(picker)
    picker:EnableMouse(true)
    picker:EnableMouseWheel(true)
    picker:SetScript("OnMouseWheel", function() end)

    local title = NewLabel(picker, "Spells and items", "GameFontNormal")
    title:SetPoint("TOP", 0, -18)
    local hint = NewLabel(picker, "Drag into a row, or click to add to the Primary.", "GameFontDisableSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)

    local search = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    search:SetSize(PICKER_WIDTH - 140, 20)
    search:SetPoint("TOPLEFT", 26, -58)
    search:SetAutoFocus(false)
    local searchHint = NewLabel(search, "Search", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 4, 0)
    search:SetScript("OnTextChanged", function(self)
        searchHint:SetShown(self:GetText() == "")
        picker:Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local showAll = NewCheck(picker, "Show all", function(checked)
        ns.db.pickerShowAll = checked
        picker:Refresh()
    end)
    showAll:SetPoint("LEFT", search, "RIGHT", 8, 0)
    Tooltip(showAll, "Show all",
        "Off: spells you'd spend mana on in combat, forms, and a few in-form abilities that buy time to regen " ..
        "(War Stomp, Bash, Feral Charge, Frenzied Regeneration, Innervate). On: every spell, plus your usable items. " ..
        "Quest items, recipes, items with no Use, and internal spells are never listed.")

    local scroll = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -86)
    scroll:SetPoint("BOTTOMRIGHT", -36, 18)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PICKER_WIDTH - 60, 10)
    scroll:SetScrollChild(content)

    local headers, rows = {}, {}

    local function Header(i)
        local header = headers[i]
        if not header then
            header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header:SetJustifyH("LEFT")
            headers[i] = header
        end
        return header
    end

    local function Row(i)
        local row = rows[i]
        if row then
            return row
        end
        row = CreateFrame("Button", nil, content)
        row:SetSize(PICKER_WIDTH - 60, PICKER_ROW_HEIGHT)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(PICKER_ROW_HEIGHT - 4, PICKER_ROW_HEIGHT - 4)
        row.icon:SetPoint("LEFT", 2, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
        row.name:SetPoint("RIGHT", -2, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.summary:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
        row.summary:SetPoint("RIGHT", -2, 0)
        row.summary:SetJustifyH("LEFT")
        row.summary:SetWordWrap(false)
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self)
            StartDrag(self.item.entry)
        end)
        row:SetScript("OnDragStop", FinishDrag)
        row:SetScript("OnClick", function(self)
            if ReadOnly() then
                Print("press Edit in library to change this sequence.")
            elseif selSeq and not Unlocked() then
                Print("press Unlock to change this sequence's rows.")
            elseif selSeq and Insert(selSeq.entries, #selSeq.entries + 1, ns.CopyTable(self.item.entry)) then
                Changed()
            elseif not selSeq then
                Print("select a sequence in the library first.")
            end
        end)
        row:SetScript("OnEnter", function(self)
            EntryTooltip(self, self.item.entry)
            GameTooltip:AddLine("Drag into a row, or click to add to the end of the Primary.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = row
        return row
    end

    function picker:Refresh()
        showAll:SetChecked(ns.db.pickerShowAll and true or false)
        local sections = ns.PickerEntries(search:GetText():lower(), ns.db.pickerShowAll)
        local y, h, r = 0, 0, 0
        for _, section in ipairs(sections) do
            h = h + 1
            local header = Header(h)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 2, -y - 4)
            header:SetText(section.title)
            header:Show()
            y = y + 22
            for _, item in ipairs(section.items) do
                r = r + 1
                local row = Row(r)
                row.item = item
                row.icon:SetTexture(item.icon)
                row.name:SetText(item.name)
                row.summary:SetText(item.summary or "")
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:Show()
                y = y + PICKER_ROW_HEIGHT
            end
            y = y + 6
        end
        for i = h + 1, #headers do
            headers[i]:Hide()
        end
        for i = r + 1, #rows do
            rows[i]:Hide()
        end
        content:SetHeight(math.max(y, 10))
    end
    return picker
end

----------------------------------------------------------------------------------------------
-- Profiles
----------------------------------------------------------------------------------------------

local function PopupEditBox(popup)
    return popup.editBox or popup.EditBox or (popup.GetEditBox and popup:GetEditBox())
end

StaticPopupDialogs["FOREVERSEQUENCES_PROFILE_NAME"] = {
    text = "%s",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = 1,
    maxLetters = 40,
    OnShow = function(self, data)
        local box = PopupEditBox(self)
        if box and data then
            box:SetText(data.text or "")
            box:HighlightText()
        end
    end,
    OnAccept = function(self, data)
        local box = PopupEditBox(self)
        local text = box and box:GetText() or ""
        if data and text ~= "" then
            data.action(text)
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local popup = self:GetParent()
        local text = self:GetText()
        if popup.data and text ~= "" then
            popup.data.action(text)
        end
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["FOREVERSEQUENCES_CONFIRM"] = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data)
        if data then
            data()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function AskName(prompt, text, action)
    local popup = StaticPopup_Show("FOREVERSEQUENCES_PROFILE_NAME", prompt, nil, { text = text, action = action })
    if popup then
        popup.data = { text = text, action = action }
        local box = PopupEditBox(popup)
        if box then
            box:SetText(text or "")
            box:HighlightText()
        end
    end
end

local function AskConfirm(text, action)
    local popup = StaticPopup_Show("FOREVERSEQUENCES_CONFIRM", text)
    if popup then
        popup.data = action
    end
end

local function ProfileLabel(name)
    return name == ns.ClassDefault() and (name .. " (class default)") or name
end

local function ProfileActions()
    return {
        { text = "New profile (a copy of this one)...", action = function()
            AskName("Name for the new profile (a copy of this one):", ns.CurrentProfile() .. " copy", function(name)
                ns.NewProfile(name)
            end)
        end },
        { text = "Rename this profile...", action = function()
            AskName("New name for this profile:", ns.CurrentProfile(), function(name)
                ns.RenameProfile(name)
            end)
        end },
        { text = "Save this profile as the class default", action = function()
            local existing = ns.ClassDefault()
            local function Save()
                local name = ns.SaveAsClassDefault()
                Print("saved as the class default (\"" .. name .. "\"). New characters of this class start with a copy.")
            end
            if existing and existing ~= ns.CurrentProfile() then
                AskConfirm("Replace the class default (\"" .. existing .. "\") with a copy of this profile?", Save)
            else
                Save()
            end
        end },
        { text = "Delete this profile", action = function()
            AskConfirm("Delete the profile \"" .. ns.CurrentProfile() .. "\"?", function()
                ns.DeleteProfile()
            end)
        end },
    }
end

local function OpenProfileMenu(owner)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
            rootDescription:CreateTitle("Profiles (" .. (UnitClass("player")) .. ")")
            for _, name in ipairs(ns.ProfileNames()) do
                rootDescription:CreateRadio(ProfileLabel(name),
                    function() return name == ns.CurrentProfile() end,
                    function() ns.UseProfile(name) end)
            end
            rootDescription:CreateDivider()
            for _, item in ipairs(ProfileActions()) do
                rootDescription:CreateButton(item.text, item.action)
            end
        end)
    else
        -- No menu API: cycle through this class's profiles.
        local names = ns.ProfileNames()
        local index = 1
        for i, name in ipairs(names) do
            if name == ns.CurrentProfile() then
                index = i
            end
        end
        if #names > 1 then
            ns.UseProfile(names[index % #names + 1])
        end
    end
end

local function NewNumberBox(parent, onSave)
    local box = NewEditBox(parent, 32, function(text)
        local value = tonumber(text)
        if value then
            onSave(value)
        end
    end)
    box:SetNumeric(true)
    box:SetMaxLetters(3)
    return box
end

local function CreateEditor()
    local f = CreateFrame("Frame", "ForeverSequencesEditor", UIParent, "BackdropTemplate")
    f:SetSize(800, 680)
    f:SetPoint("CENTER", -150, 0)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Backdrop(f)
    tinsert(UISpecialFrames, "ForeverSequencesEditor") -- Escape closes it
    -- Take the mouse wheel anywhere over the window, so it never reaches a key binding.
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function() end)

    local title = NewLabel(f, "Forever Sequences", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local profileLabel = NewLabel(f, "Profile", "GameFontNormalSmall")
    profileLabel:SetPoint("TOPLEFT", LEFT + 4, -20)
    f.profileButton = NewButton(f, "", 200, function(self)
        OpenProfileMenu(self)
    end)
    f.profileButton:SetPoint("LEFT", profileLabel, "RIGHT", 6, 0)
    Tooltip(f.profileButton, "Profiles",
        "Windows and sequences are saved per profile. Every character of a class can use any of that class's " ..
        "profiles. A character without one starts with its own copy of the class default, window positions and " ..
        "all; editing it never changes the class default. To tidy up the class default itself, switch to it here.")

    -- Left, top: windows and the sequences they show.
    local windowsLabel = NewLabel(f, "Windows")
    windowsLabel:SetPoint("TOPLEFT", LEFT, -48)
    local windowArea = ScrollArea(f, WINDOW_ROWS, function(delta)
        local most = math.max(0, #WindowListItems() - WINDOW_ROWS)
        windowOffset = math.max(0, math.min(most, windowOffset - delta))
    end)
    windowArea:SetPoint("TOPLEFT", LEFT, -66)
    for i = 1, WINDOW_ROWS do
        windowRows[i] = CreateWindowRow(f, windowArea, i)
    end
    local newWindow = NewButton(f, "New window", 104, NewWindow)
    newWindow:SetPoint("TOPLEFT", windowArea, "BOTTOMLEFT", 0, -6)
    f.windowDelete = NewButton(f, "Delete", 104, function()
        if selItem and selWindow then
            -- Take the sequence out of this window; it stays in the library.
            table.remove(selWindow.items, IndexOf(selWindow.items, selItem))
            selItem = nil
            Changed()
        elseif selWindow then
            Confirm(string.format("Delete the window \"%s\"? Its sequences stay in the library.",
                selWindow.name or "?"), { window = selWindow })
        end
    end)
    f.windowDelete:SetPoint("LEFT", newWindow, "RIGHT", 4, 0)

    -- Left, bottom: the library.
    local libraryLabel = NewLabel(f, "Sequence Library")
    libraryLabel:SetPoint("TOPLEFT", newWindow, "BOTTOMLEFT", 0, -14)
    local libraryHint = NewLabel(f, "drag onto a window", "GameFontDisableSmall")
    libraryHint:SetPoint("LEFT", libraryLabel, "RIGHT", 8, 0)
    local libraryArea = ScrollArea(f, LIBRARY_ROWS, function(delta)
        local most = math.max(0, #Library() - LIBRARY_ROWS)
        libraryOffset = math.max(0, math.min(most, libraryOffset - delta))
    end)
    libraryArea:SetPoint("TOPLEFT", libraryLabel, "BOTTOMLEFT", 0, -4)
    for i = 1, LIBRARY_ROWS do
        libraryRows[i] = CreateLibraryRow(f, libraryArea, i)
    end
    local newSequence = NewButton(f, "New", 68, NewSequence)
    newSequence:SetPoint("TOPLEFT", libraryArea, "BOTTOMLEFT", 0, -6)
    f.copySequence = NewButton(f, "Copy", 68, CopySequence)
    f.copySequence:SetPoint("LEFT", newSequence, "RIGHT", 4, 0)
    Tooltip(f.copySequence, "Copy", "Makes an independent copy of the selected sequence, to change for another window.")
    f.librarySequenceDelete = NewButton(f, "Delete", 68, function()
        if selSeq then
            local used = UsedIn(selSeq)
            Confirm(string.format("Delete the sequence \"%s\"%s?", selSeq.name or "?",
                #used > 0 and (" from the library and from " .. table.concat(used, ", ")) or ""), { def = selSeq })
        end
    end)
    f.librarySequenceDelete:SetPoint("LEFT", f.copySequence, "RIGHT", 4, 0)

    -- Right, top: the selected window.
    local windowPanel = CreateFrame("Frame", nil, f)
    windowPanel:SetPoint("TOPLEFT", RIGHT_X, -44)
    windowPanel:SetSize(520, 200)
    f.windowPanel = windowPanel

    local windowLabel = NewLabel(windowPanel, "Window")
    windowLabel:SetPoint("TOPLEFT", 0, -6)
    f.windowName = NewEditBox(windowPanel, 180, function(text)
        if selWindow and text ~= "" and text ~= selWindow.name then
            selWindow.name = text
            Changed()
        end
    end)
    f.windowName:SetPoint("LEFT", windowLabel, "RIGHT", 12, 0)
    -- Switching type keeps the other type's settings (thresholds and targets for dynamic,
    -- click to cast for fixed) on the window for switching back; only the current type's
    -- settings are used.
    f.windowType = NewButton(windowPanel, "", 190, function()
        if selWindow then
            selWindow.type = selWindow.type == "fixed" and "dynamic" or "fixed"
            Changed()
        end
    end)
    f.windowType:SetPoint("LEFT", f.windowName, "RIGHT", 10, 0)
    f.windowTypeText = f.windowType
    Tooltip(f.windowType, "Window type (click to switch)",
        "Dynamic: one row per sequence, showing whichever of its sequences fits your mana; rows close up " ..
        "when a sequence has nothing to show. Can show only when mana or health is low, or for some targets.\n" ..
        "Fixed: the Primary is always shown and can be clicked to cast, with the best sub-sequence under it. " ..
        "Nothing moves.\nSwitching keeps each type's own settings for when you switch back.")
    f.onlyInCombat = NewCheck(windowPanel, "Only show in combat", function(checked)
        if selWindow then
            selWindow.onlyInCombat = checked
            Changed()
        end
    end)
    f.onlyInCombat:SetPoint("TOPLEFT", 0, -30)
    f.windowClick = NewCheck(windowPanel, "Click the Primary to cast", function(checked)
        if selWindow then
            ns.SetClickable(selWindow, checked)
        end
    end)
    f.windowClick:SetPoint("LEFT", f.onlyInCombat.label, "RIGHT", 24, -1)

    -- Dynamic windows only: what the fight is against, then the thresholds.
    local fightRow = CreateFrame("Frame", nil, windowPanel)
    fightRow:SetPoint("TOPLEFT", 24, -54)
    fightRow:SetSize(480, 22)
    f.fightRow = fightRow
    f.fightLabel = NewLabel(fightRow, "Fight against:", "GameFontHighlightSmall")
    f.fightLabel:SetPoint("LEFT", 4, 0)
    f.fightChecks = {}
    local previousCheck
    for _, choice in ipairs({ { "pvp", "PvP" }, { "pve", "PvE" }, { "all", "All" } }) do
        local key = choice[1]
        local check = NewCheck(fightRow, choice[2], function()
            if selWindow then
                selWindow.fight = key
                Changed()
            end
        end)
        check.key = key
        check:SetPoint("LEFT", previousCheck and previousCheck.label or f.fightLabel, "RIGHT", 12, previousCheck and -1 or 0)
        f.fightChecks[#f.fightChecks + 1] = check
        previousCheck = check
    end
    Tooltip(f.fightChecks[1], "PvP fights",
        "A fight counts as PvP once you target anything PvP-flagged (players, guards and other PvP NPCs) or " ..
        "controlled by a player (pets, totems, summons), and stays PvP until combat ends. Until then it's PvE, " ..
        "including when it starts with no enemy targeted. Friendly targets, yourself included, never count.")
    Tooltip(f.fightChecks[2], "PvE fights", "Fights that haven't turned PvP (see PvP).")

    local gates = CreateFrame("Frame", nil, windowPanel)
    gates:SetPoint("TOPLEFT", 0, -80)
    gates:SetSize(520, 70)
    f.gates = gates

    f.manaGate = NewCheck(gates, "Only show when mana is below the costliest sequence's need, plus", function(checked)
        if selWindow then
            selWindow.manaGate = checked
            Changed()
        end
    end)
    f.manaGate:SetPoint("TOPLEFT", 0, 0)
    f.manaMargin = NewNumberBox(gates, function(value)
        if selWindow and value ~= selWindow.manaMargin then
            selWindow.manaMargin = value
            Changed()
        end
    end)
    f.manaMargin:SetPoint("LEFT", f.manaGate.label, "RIGHT", 10, 0)
    local percent = NewLabel(gates, "%", "GameFontHighlightSmall")
    percent:SetPoint("LEFT", f.manaMargin, "RIGHT", 2, 0)

    local holdLabel = NewLabel(gates, "and keep showing for", "GameFontHighlightSmall")
    holdLabel:SetPoint("TOPLEFT", 28, -26)
    f.holdSeconds = NewNumberBox(gates, function(value)
        value = math.min(value, 10)
        if selWindow and value ~= selWindow.holdSeconds then
            selWindow.holdSeconds = value
            Changed()
        end
    end)
    f.holdSeconds:SetPoint("LEFT", holdLabel, "RIGHT", 10, 0)
    local seconds = NewLabel(gates, "seconds after it goes back above (up to 10)", "GameFontHighlightSmall")
    seconds:SetPoint("LEFT", f.holdSeconds, "RIGHT", 4, 0)

    f.healthGate = NewCheck(gates, "Only show when health is below", function(checked)
        if selWindow then
            selWindow.healthGate = checked
            Changed()
        end
    end)
    f.healthGate:SetPoint("TOPLEFT", 0, -46)
    f.healthPercent = NewNumberBox(gates, function(value)
        if selWindow and value ~= selWindow.healthPercent then
            selWindow.healthPercent = value
            Changed()
        end
    end)
    f.healthPercent:SetPoint("LEFT", f.healthGate.label, "RIGHT", 10, 0)
    local healthPercentLabel = NewLabel(gates, "%   (with both ticked, it shows when either is low)", "GameFontHighlightSmall")
    healthPercentLabel:SetPoint("LEFT", f.healthPercent, "RIGHT", 2, 0)

    f.divider = f:CreateTexture(nil, "ARTWORK")
    f.divider:SetColorTexture(1, 0.82, 0, 0.25)
    f.divider:SetHeight(1)
    f.divider:SetPoint("RIGHT", f, "RIGHT", -20, 0)

    -- Right: the selected sequence.
    local detail = CreateFrame("Frame", nil, f)
    detail:SetPoint("TOPLEFT", RIGHT_X, -44)
    detail:SetPoint("BOTTOMRIGHT", -20, 60)
    f.detail = detail

    local nameLabel = NewLabel(detail, "Sequence")
    nameLabel:SetPoint("TOPLEFT", 0, -6)
    f.nameBox = NewEditBox(detail, 220, function(text)
        if selSeq and text ~= "" and text ~= selSeq.name then
            selSeq.name = text
            Changed()
        end
    end)
    f.nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
    f.primaryHide = NewCheck(detail, "Hide when unusable", function(checked)
        if selSeq then
            selSeq.hideOnCooldown = checked
            Changed()
        end
    end)
    f.primaryHide:SetPoint("LEFT", f.nameBox, "RIGHT", 16, 0)
    Tooltip(f.primaryHide, "Hide when unusable",
        "While a spell or item in it is on cooldown, an item has run out, or the target is the wrong kind " ..
        "(Hibernate: beasts and dragonkin only), the next sequence shows instead. In dynamic windows; fixed " ..
        "windows always show the Primary.")
    f.usedIn = NewLabel(detail, "", "GameFontDisableSmall")
    f.usedIn:SetPoint("TOPLEFT", 0, -26)
    f.usedIn:SetPoint("RIGHT", detail, "RIGHT", -130, 0)
    f.usedIn:SetJustifyH("LEFT")

    local primaryLabel = NewLabel(detail, "Primary")
    primaryLabel:SetPoint("TOPLEFT", 0, -44)
    f.primaryCost = NewLabel(detail, "", "GameFontHighlightSmall")
    f.primaryCost:SetPoint("LEFT", primaryLabel, "RIGHT", 10, 0)
    f.primaryRow = CreateSlotRow(detail, function() return selSeq and selSeq.entries end, true)
    f.primaryRow.frame:SetPoint("TOPLEFT", 0, -62)

    local subsLabel = NewLabel(detail, "Sub-sequences")
    subsLabel:SetPoint("TOPLEFT", 0, -104)

    -- Sub-sequences: any number, in a scroll frame.
    local subScroll = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
    subScroll:SetPoint("TOPLEFT", 0, -120)
    subScroll:SetPoint("BOTTOMRIGHT", -24, 40)
    local subContent = CreateFrame("Frame", nil, subScroll)
    subContent:SetSize(500, 10)
    subScroll:SetScrollChild(subContent)
    f.subScroll, f.subContent = subScroll, subContent

    f.subBlocks = {}
    local function SubAt(block)
        return selSeq and selSeq.subs[block.index]
    end
    function f:SubBlock(i)
        local block = self.subBlocks[i]
        if block then
            return block
        end
        block = CreateFrame("Frame", nil, subContent)
        block:SetSize(500, SUB_BLOCK_HEIGHT)
        block:SetPoint("TOPLEFT", 0, -(i - 1) * SUB_BLOCK_HEIGHT)
        block.index = i
        block.row = CreateSlotRow(block, function()
            local sub = SubAt(block)
            return sub and sub.entries
        end, false)
        block.row.clip = subScroll
        block.row.frame:SetPoint("TOPLEFT", 0, -14)
        block.cost = NewLabel(block, "", "GameFontHighlightSmall")
        block.cost:SetPoint("TOPLEFT", 0, 0)
        block.remove = NewButton(block, "Remove", 70, function()
            if SubAt(block) and Unlocked() then
                table.remove(selSeq.subs, block.index)
                Changed()
            end
        end)
        block.remove:SetPoint("LEFT", block.row.frame, "LEFT", 6 * (SLOT_SIZE + SLOT_GAP) + 150, 0)
        block.hide = NewCheck(block, "Hide when unusable", function(checked)
            local sub = SubAt(block)
            if sub then
                sub.hideOnCooldown = checked
                Changed()
            end
        end)
        block.hide:SetPoint("BOTTOMLEFT", block.remove, "TOPLEFT", 0, 0)
        self.subBlocks[i] = block
        return block
    end

    f.lockButton = NewButton(subContent, "Unlock", 90, function()
        if Unlocked() then
            Lock()
        elseif selSeq and not ReadOnly() then
            Lock() -- any other sequence still unlocked
            ns.unsortedSequence = selSeq
            Changed()
            subScroll:SetVerticalScroll(subScroll:GetVerticalScrollRange())
        end
    end)
    Tooltip(f.lockButton, "Unlock / Lock",
        "Unlock to change the Primary and sub-sequences: an empty row waits at the bottom, and rows keep " ..
        "their places while you work. Lock (or pick something else) to drop empty rows and put them back in " ..
        "order, costliest first.")

    -- A sequence picked under a window is shown read-only, with a way into the library.
    f.nameText = NewLabel(detail, "", "GameFontHighlight")
    f.nameText:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
    f.editButton = NewButton(detail, "Edit in library", 120, function()
        selWindow, selItem = nil, nil
        -- You pressed it to change the sequence, so it opens unlocked.
        if selSeq then
            ns.unsortedSequence = selSeq
            KeepEmptyRow()
        end
        f:Refresh()
    end)
    f.editButton:SetPoint("TOPRIGHT", 0, -22)

    local hint = NewLabel(detail,
        "Unlock, then drag spells and items onto a row from the list on the right, your spellbook or your bags. " ..
        "Drag icons to move them, onto another row to copy them, or off the window to remove them. " ..
        "Right-click an icon to remove it; shift-right-click a spell for one rank down, ctrl-click for one up.",
        "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 0, 4)
    hint:SetPoint("BOTTOMRIGHT", 0, 4)
    hint:SetJustifyH("LEFT")

    f.empty = NewLabel(f, "", "GameFontDisable")
    f.empty:SetPoint("CENTER", detail, "CENTER")

    -- Bottom: options for every window.

    f.regen = NewButton(f, "", 150, function()
        local current = 1
        for i, mode in ipairs(REGEN_MODES) do
            if mode == ns.db.regenMode then
                current = i
            end
        end
        ns.SetRegenMode(REGEN_MODES[current % #REGEN_MODES + 1])
        f:Refresh()
    end)
    f.regen:SetPoint("BOTTOMLEFT", LEFT, 22)
    Tooltip(f.regen, "Mana regen during a sequence",
        "Smooth: a steady flow (Forever's regen). 2s ticks: mana in 2-second ticks with the worst timing. " ..
        "Off: ignore regen.")
    local moveHint = NewLabel(f, "While this is open, every window is shown and can be dragged.", "GameFontDisableSmall")
    moveHint:SetPoint("LEFT", f.regen, "RIGHT", 16, 0)

    f.picker = CreatePicker(f)

    function f:Refresh()
        local windows = Windows()
        if selWindow and not IndexOf(windows, selWindow) then
            selWindow, selItem = nil, nil
        end
        if selItem and not (selWindow and IndexOf(selWindow.items, selItem)) then
            selItem = nil
        end
        if selSeq and not IndexOf(Library(), selSeq) then
            selSeq = nil
        end
        if not selWindow and not selSeq then
            selWindow = windows[1]
        end
        -- Picking anything else locks the sequence being edited.
        if ns.unsortedSequence and not Unlocked() then
            Lock()
        end

        -- Windows list.
        local items = WindowListItems()
        windowOffset = math.max(0, math.min(windowOffset, #items - WINDOW_ROWS))
        for i, row in ipairs(windowRows) do
            local data = items[i + windowOffset]
            row.data = data
            if data then
                local isWindow = data.item == nil
                local target = data.item or data.window
                local list = isWindow and windows or data.window.items
                local index = IndexOf(list, target)
                row.enabled:ClearAllPoints()
                row.enabled:SetPoint("LEFT", isWindow and 0 or 16, 0)
                row.text:SetPoint("LEFT", row.enabled, "RIGHT", 2, 0)
                row.text:SetFontObject(isWindow and "GameFontNormal" or "GameFontHighlight")
                if isWindow then
                    row.text:SetText((data.window.name or "?") .. (data.window.type == "fixed" and " (fixed)" or " (dynamic)"))
                else
                    local learned = ns.AllLearned(data.def.entries)
                    row.text:SetText(learned and (data.def.name or "?") or
                        ("|cff808080" .. (data.def.name or "?") .. " (not learned)|r"))
                end
                row.enabled:SetChecked(target.enabled and true or false)
                local selected = (isWindow and data.window == selWindow and selItem == nil)
                    or (not isWindow and data.item == selItem)
                row.selectedTexture:SetShown(selected)
                row.up:SetEnabled(index > 1)
                row.down:SetEnabled(index < #list)
                row:Show()
            else
                row:Hide()
            end
        end
        self.windowDelete:SetText(selItem and "Remove" or "Delete")
        self.windowDelete:SetEnabled(selWindow ~= nil)

        -- Library.
        local library = Library()
        libraryOffset = math.max(0, math.min(libraryOffset, #library - LIBRARY_ROWS))
        for i, row in ipairs(libraryRows) do
            local def = library[i + libraryOffset]
            row.def = def
            if def then
                local used = #UsedIn(def)
                local learned = ns.AllLearned(def.entries)
                row.text:SetText((learned and "" or "|cff808080") .. (def.name or "?") .. (learned and "" or "|r") ..
                    (used > 0 and ("  |cff808080(" .. used .. ")|r") or "  |cff808080(unused)|r"))
                row.selectedTexture:SetShown(def == selSeq and selItem == nil)
                local index = i + libraryOffset
                row.up:SetEnabled(index > 1)
                row.down:SetEnabled(index < #library)
                row:Show()
            else
                row:Hide()
            end
        end
        self.copySequence:SetEnabled(selSeq ~= nil)
        self.librarySequenceDelete:SetEnabled(selSeq ~= nil)

        -- Window settings.
        self.windowPanel:SetShown(selWindow ~= nil)
        local dynamic = selWindow and selWindow.type ~= "fixed"
        if selWindow then
            if not self.windowName:HasFocus() then
                self.windowName:SetText(selWindow.name or "")
            end
            self.windowTypeText:SetText(selWindow.type == "fixed" and "Type: Fixed (switch)" or "Type: Dynamic (switch)")
            self.windowClick:SetShown(selWindow.type == "fixed")
            self.windowClick:SetChecked(selWindow.clickable ~= false)
            self.onlyInCombat:SetChecked(selWindow.onlyInCombat and true or false)
            self.gates:SetShown(dynamic)
            if dynamic then
                self.manaGate:SetChecked(selWindow.manaGate and true or false)
                self.healthGate:SetChecked(selWindow.healthGate and true or false)
                for box, key in pairs({ [self.manaMargin] = "manaMargin", [self.holdSeconds] = "holdSeconds",
                    [self.healthPercent] = "healthPercent" }) do
                    if not box:HasFocus() then
                        box:SetText(tostring(selWindow[key] or 0))
                    end
                end
            end
            -- Only applies with "only show in combat": greyed out without it.
            self.fightRow:SetShown(dynamic)
            local inCombatOnly = selWindow.onlyInCombat and true or false
            for _, check in ipairs(self.fightChecks) do
                check:SetChecked((selWindow.fight or "all") == check.key)
                check:SetEnabled(inCombatOnly)
                check.label:SetFontObject(inCombatOnly and "GameFontHighlightSmall" or "GameFontDisableSmall")
            end
            self.fightLabel:SetFontObject(inCombatOnly and "GameFontHighlightSmall" or "GameFontDisableSmall")
        end
        self.divider:Hide()

        -- The sequence: editable from the library, read-only when picked under a window.
        local def = selSeq
        local readOnly = ReadOnly()
        self.windowPanel:SetShown(selWindow ~= nil and not readOnly)
        self.detail:SetShown(def ~= nil)
        self.empty:SetShown(def == nil and selWindow == nil)
        self.empty:SetText("Press New window to start.")
        if def then
            self.nameBox:SetShown(not readOnly)
            self.nameText:SetShown(readOnly)
            self.nameText:SetText(def.name or "")
            self.editButton:SetShown(readOnly)
            if not self.nameBox:HasFocus() then
                self.nameBox:SetText(def.name or "")
            end
            local used = UsedIn(def)
            self.usedIn:SetText(#used > 0 and ("Used in: " .. table.concat(used, ", "))
                or "Not in any window yet: drag it from the library onto one.")
            self.primaryHide:SetShown(ns.AnyCooldown(def.entries))
            self.primaryHide:SetChecked(def.hideOnCooldown and true or false)
            self.primaryHide:SetEnabled(not readOnly)
            self.primaryCost:SetText(CostText(def.entries))
            RefreshSlotRow(self.primaryRow)
            for i = 1, math.max(#def.subs, #self.subBlocks) do
                local sub = def.subs[i]
                if sub then
                    local block = self:SubBlock(i)
                    block.hide:SetShown(ns.AnyCooldown(sub.entries))
                    block.hide:SetChecked(sub.hideOnCooldown and true or false)
                    block.hide:SetEnabled(not readOnly)
                    block.remove:SetShown(Unlocked() and not IsEmpty(sub))
                    block.cost:SetText(i .. ". " .. CostText(sub.entries))
                    RefreshSlotRow(block.row)
                    block:Show()
                elseif self.subBlocks[i] then
                    self.subBlocks[i]:Hide()
                end
            end
            self.lockButton:ClearAllPoints()
            self.lockButton:SetPoint("TOPLEFT", 0, -#def.subs * SUB_BLOCK_HEIGHT - 2)
            self.lockButton:SetText(Unlocked() and "Lock" or "Unlock")
            self.lockButton:SetShown(not readOnly)
            self.subContent:SetHeight(#def.subs * SUB_BLOCK_HEIGHT + 30)
        end

        self.profileButton:SetText(ProfileLabel(ns.CurrentProfile() or "?"))
        self.regen:SetText(REGEN_LABELS[ns.db.regenMode] or ns.db.regenMode)
        self.picker:Refresh()
    end

    -- The mana figures change with regen and the 5-second rule; keep them current.
    local elapsedSinceCosts = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        elapsedSinceCosts = elapsedSinceCosts + elapsed
        if elapsedSinceCosts < 1 or not selSeq then
            return
        end
        elapsedSinceCosts = 0
        self.primaryCost:SetText(CostText(selSeq.entries))
        for i, block in ipairs(self.subBlocks) do
            local sub = selSeq.subs[i]
            if sub and block:IsShown() then
                block.cost:SetText(i .. ". " .. CostText(sub.entries))
            end
        end
    end)

    f:SetScript("OnShow", function(self)
        if ns.SortAllVariations() then
            ns.Rebuild()
        end
        ns.SetEditorOpen(true)
        self:Refresh()
    end)
    f:SetScript("OnHide", function()
        Lock()
        ns.SetEditorOpen(false)
        if drag or listDrag then
            drag, listDrag = nil, nil
            ghost:Hide()
        end
    end)
    f:Hide()
    return f
end

-- Open (show = true) or toggle the editor. With a window, select it (and scroll the windows
-- list to it).
function ns.ToggleEditor(show, window)
    if not ns.db then
        return
    end
    editor = editor or CreateEditor()
    if show or not editor:IsShown() then
        if window and IndexOf(Windows(), window) then
            selWindow, selItem, selSeq = window, nil, nil
            for i, data in ipairs(WindowListItems()) do
                if data.window == window and data.item == nil then
                    if i <= windowOffset or i > windowOffset + WINDOW_ROWS then
                        windowOffset = math.max(0, i - 1)
                    end
                end
            end
        end
        if editor:IsShown() then
            editor:Refresh()
        else
            editor:Show()
        end
        editor:Raise()
    else
        editor:Hide()
    end
end

function ns.RefreshEditor()
    if editor and editor:IsShown() then
        editor:Refresh()
    end
end

----------------------------------------------------------------------------------------------
-- Esc > Options > AddOns: a page with a button to open the editor
----------------------------------------------------------------------------------------------

local panel = CreateFrame("Frame")
panel.name = "Forever Sequences"
local panelTitle = NewLabel(panel, "Forever Sequences", "GameFontNormalLarge")
panelTitle:SetPoint("TOPLEFT", 16, -16)
local panelText = NewLabel(panel,
    "Windows and the library of sequences are set up in their own window. Open it here, with /fseq, or by right-clicking " ..
    "an icon.", "GameFontHighlight")
panelText:SetPoint("TOPLEFT", panelTitle, "BOTTOMLEFT", 0, -8)
panelText:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
panelText:SetJustifyH("LEFT")
local panelButton = NewButton(panel, "Open Forever Sequences", 200, function()
    if SettingsPanel and SettingsPanel:IsShown() then
        HideUIPanel(SettingsPanel)
    end
    ns.ToggleEditor(true)
end)
panelButton:SetPoint("TOPLEFT", panelText, "BOTTOMLEFT", 0, -12)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end
