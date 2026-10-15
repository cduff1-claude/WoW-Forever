-- Forever Sequences editor: the windows, a library of sequences, and the sequences' rows of
-- icons.
--
--   - Left, top: the windows, in sections by type (Static, Switching, Stacked; click a
--     heading to open or close it). Click one for its settings; drag to reorder within its
--     section. Drop a sequence from the library on a window to add it there.
--   - Left, bottom: the library, every sequence you've made. Drag to reorder, or onto a window
--     (or a window's Sequences tab) to show it there; the same sequence can be in several.
--   - Right, for a window: a Settings tab and a Sequences tab (its sequences, in display
--     order; click one to show its details, drag to reorder, right-click or drag off to take
--     it out of the window).
--   - Right, for a library sequence: its name and rows. Unlock to change them: drag spells and
--     items in from the list beside the editor, your spellbook or your bags; the "+" slot adds
--     at the end. Drag an icon within its row to move it, onto another row to copy it (from the
--     Primary onto a sub-sequence's "+" slot it goes in Primary order), or off the window to
--     remove it. Right-click removes; shift-right-click / ctrl-click step a spell's rank.
--   - While this is open every window is shown and can be dragged to move it, or resized from
--     its corner.

local _, ns = ...

local MAX_ENTRIES = 8
local SLOT_SIZE = 34
local SLOT_GAP = 4
local SUB_BLOCK_HEIGHT = SLOT_SIZE + 20
local WINDOW_ROWS = 12
local LIBRARY_ROWS = 12
local LIST_ROW_HEIGHT = 22
local LEFT = 20
local RIGHT_X = 250
local PICKER_WIDTH = 300
local PICKER_ROW_HEIGHT = 30
local MINI_SIZE = 20      -- icons in a window's Sequences tab
local STRIP_HEIGHT = 24

local editor
local selWindow -- the selected window, shown with its tabs (when no library sequence is picked)
local selSeq    -- the selected library sequence, shown in the sequence editor, or nil
local tab = "settings" -- the window's tab: "settings" or "sequences"
local windowOffset, libraryOffset = 0, 0
local drag      -- an icon being dragged: { entry, row (nil from the list of spells), index }
-- A list item being dragged: { kind = "window" (window), "seq" (def, from the library) or
-- "placement" (def, window, item: from a window's Sequences tab) }.
local listDrag

-- The selected sequence's rows only change while it's unlocked; until it's locked again, its
-- variations keep their order (so a row doesn't jump while you're adding to it), and an
-- empty sub-sequence waits at the bottom.
local function Unlocked()
    return selSeq ~= nil and ns.unsortedSequence == selSeq
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
            def.subs[#def.subs + 1] = { entries = {} }
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
        if source.row and not editor:IsMouseOver() and not (editor.picker:IsShown() and editor.picker:IsMouseOver()) then
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
        if not Unlocked() then
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
            selSeq = nil
        elseif data and data.window then
            table.remove(Windows(), IndexOf(Windows(), data.window))
            selWindow = nil
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

-- The window types, in the order of their sections, with what each does.
local WINDOW_TYPES = {
    { key = "fixed", text = "the Primary is always shown and can be clicked to cast, with the best " ..
        "sub-sequence under it. Nothing moves." },
    { key = "dynamic", text = "one row per sequence, switching between its variations to show the one you're " ..
        "working towards; rows close up when a sequence has nothing to show. Can show only when mana or health " ..
        "is low, or for some fights, and skip sequences that would overheal." },
    { key = "stacked", text = "every variation you include from its sequences, as a list: the ones you can " ..
        "afford, costliest at the top (or in your order), filling down from the top as mana rises. Optionally " ..
        "the next one up too, and one sequence's Primary always at the top. Same show-when options as " ..
        "Switching." },
}

local function TypeHelp()
    local lines = {}
    for _, t in ipairs(WINDOW_TYPES) do
        lines[#lines + 1] = ns.TypeLabel(t.key) .. ": " .. t.text
    end
    return table.concat(lines, "\n")
end

-- A menu of the window types at `owner`; `current` (a type key) is ticked.
local function TypeMenu(owner, title, current, onPick)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        -- No menu API: step through the types.
        local index = 0
        for i, t in ipairs(WINDOW_TYPES) do
            if t.key == current then
                index = i
            end
        end
        onPick(WINDOW_TYPES[index % #WINDOW_TYPES + 1].key)
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        rootDescription:CreateTitle(title)
        for _, t in ipairs(WINDOW_TYPES) do
            local key = t.key
            local button = rootDescription:CreateRadio(ns.TypeLabel(key),
                function() return key == current end,
                function() onPick(key) end)
            if button and button.SetTooltip then
                button:SetTooltip(function(tooltip)
                    GameTooltip_SetTitle(tooltip, ns.TypeLabel(key))
                    GameTooltip_AddNormalLine(tooltip, t.text)
                end)
            end
        end
    end)
end

-- New windows open beside the options: to their left, or to the right (past the list of
-- spells and items) when there's no room, each a little below the last.
local function NewWindowPosition()
    if not (editor and editor:GetLeft()) then
        return nil, nil
    end
    local step = (#Windows() % 5) * 24
    local top = editor:GetTop() - 40 - step
    if editor:GetLeft() > 260 then
        return editor:GetLeft() - 240 + step, top
    end
    return editor:GetRight() + PICKER_WIDTH + 10 + step, top
end

local function AddWindow(windowType)
    local list = Windows()
    local window = ns.NewWindow("Window " .. (#list + 1))
    window.type = windowType
    window.id = ns.NewId()
    window.left, window.top = NewWindowPosition()
    list[#list + 1] = window
    ns.UIState().closed[windowType] = nil
    Lock()
    selWindow, selSeq, tab = window, nil, "settings"
    Changed()
end

local function NewWindow(owner)
    TypeMenu(owner, "New window", nil, AddWindow)
end

-- Show a library sequence in a window, before `beforeIndex` (default: at the end).
local function Place(def, window, beforeIndex)
    if ItemIndex(window, def.id) then
        Print("\"" .. (def.name or "?") .. "\" is already in " .. (window.name or "?") .. ".")
        return nil
    end
    local item = { id = def.id, enabled = true }
    table.insert(window.items, math.max(1, math.min(beforeIndex or #window.items + 1, #window.items + 1)), item)
    return item
end

-- Edit a library sequence (unlocked when asked, ready to change).
local function EditSequence(def, unlocked)
    if def == selSeq and not unlocked then
        -- Already open (and maybe unlocked): leave it as it is.
        if editor then
            editor:Refresh()
        end
        return
    end
    Lock()
    selWindow, selSeq = nil, def
    if unlocked then
        ns.unsortedSequence = def
    end
    if editor then
        editor.subScroll:SetVerticalScroll(0)
    end
    Changed()
end

-- A new sequence goes in the library, and in the selected window if one is showing.
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
    if selWindow and not selSeq then
        Place(def, selWindow)
    end
    EditSequence(def, true)
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
    Print("copied. Drag \"" .. copy.name .. "\" from the library onto a window to show it there.")
    EditSequence(copy, false)
end

-- The windows list: a heading per type, then (unless it's closed) its windows.
local function WindowListItems()
    local closed = ns.UIState().closed
    local items = {}
    for _, t in ipairs(WINDOW_TYPES) do
        local windows = {}
        for _, window in ipairs(Windows()) do
            if (window.type or "dynamic") == t.key then
                windows[#windows + 1] = window
            end
        end
        items[#items + 1] = { section = t.key, count = #windows }
        if not closed[t.key] then
            for _, window in ipairs(windows) do
                items[#items + 1] = { window = window }
            end
        end
    end
    return items
end

local function ExpandedKey(window, def)
    return tostring(window.id) .. ":" .. tostring(def.id)
end

----------------------------------------------------------------------------------------------
-- Dragging list items: windows (to reorder), library sequences (to reorder, or into a window)
-- and a window's sequences (to reorder, move to another window, or drag off to take out). A
-- gold line shows where it'll go.
----------------------------------------------------------------------------------------------

local windowRows, libraryRows = {}, {}

local function SequenceIcon(def)
    local first = def and def.entries[1]
    return first and ns.ResolveEntry(first).icon or 134400
end

local function StartListDrag(data, icon)
    listDrag = data
    ghostIcon:SetTexture(icon or 134400)
    ghost:Show()
end

-- The row under the cursor among `rows` that `accept` takes, and whether a drop there goes
-- before it (cursor in its upper half) or after it.
local function RowAtCursor(rows, accept, clip)
    if clip and not clip:IsMouseOver() then
        return nil
    end
    local _, y = GetCursorPosition()
    y = y / UIParent:GetEffectiveScale()
    for _, row in ipairs(rows) do
        if row:IsVisible() and row:IsMouseOver() and accept(row) then
            local _, centre = row:GetCenter()
            return row, y > centre
        end
    end
    return nil
end

-- Where the dragged item would go: { kind, row, before, ... }, or nil.
local function ResolveDrop(source)
    if not editor then
        return nil
    end
    if source.kind == "window" then
        -- Within its own section (the order only matters in the list).
        local row, before = RowAtCursor(windowRows, function(r)
            return r.data and r.data.window and (r.data.window.type or "dynamic") == (source.window.type or "dynamic")
        end)
        if row then
            return { kind = "reorderWindow", row = row, before = before }
        end
        local heading = RowAtCursor(windowRows, function(r)
            return r.data and r.data.section == (source.window.type or "dynamic")
        end)
        if heading then
            return { kind = "reorderWindow", row = heading, before = false, toStart = true }
        end
        return nil
    end
    local windowRow = RowAtCursor(windowRows, function(r) return r.data and r.data.window ~= nil end)
    if windowRow then
        return { kind = "toWindow", row = windowRow, window = windowRow.data.window }
    end
    if source.kind == "seq" then
        local row, before = RowAtCursor(libraryRows, function(r) return r.def ~= nil end)
        if row then
            return { kind = "reorderLibrary", row = row, before = before }
        end
    end
    if selWindow and not selSeq and editor.sequencesTab:IsVisible() then
        local entry, before = RowAtCursor(editor.entries, function(r) return r.item ~= nil end, editor.seqScroll)
        if entry then
            return { kind = "intoWindow", row = entry, before = before }
        end
        if editor.sequencesTab:IsMouseOver() then
            return { kind = "intoWindow", atEnd = true, row = editor.lastEntry }
        end
    end
    if source.kind == "placement" and not editor:IsMouseOver() then
        return { kind = "remove" }
    end
    return nil
end

-- While dragging: the gold line (or, over a window name, its highlight).
local highlighted
local function UpdateDropLine()
    local line = editor and editor.dropLine
    if not line then
        return
    end
    if highlighted then
        highlighted:UnlockHighlight()
        highlighted = nil
    end
    local target = listDrag and ResolveDrop(listDrag)
    if not target or not target.row or target.kind == "toWindow" or target.kind == "remove" then
        line:Hide()
        if target and target.kind == "toWindow" then
            highlighted = target.row
            highlighted:LockHighlight()
        end
        return
    end
    local before = target.before and not target.atEnd
    line:ClearAllPoints()
    line:SetPoint("LEFT", target.row, before and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
    line:SetPoint("RIGHT", target.row, before and "TOPRIGHT" or "BOTTOMRIGHT", 0, 0)
    line:Show()
end

local function FinishListDrag()
    if not listDrag then
        return
    end
    local source = listDrag
    local target = ResolveDrop(source)
    listDrag = nil
    ghost:Hide()
    UpdateDropLine()
    if not target then
        return
    end
    if target.kind == "reorderWindow" then
        local list = Windows()
        local onto = target.row.data.window
        if onto == source.window then
            return
        end
        table.remove(list, IndexOf(list, source.window))
        local index = #list + 1
        if target.toStart then
            for i, window in ipairs(list) do
                if (window.type or "dynamic") == (source.window.type or "dynamic") then
                    index = i
                    break
                end
            end
        else
            index = IndexOf(list, onto) + (target.before and 0 or 1)
        end
        table.insert(list, index, source.window)
    elseif target.kind == "reorderLibrary" then
        local list = Library()
        if target.row.def == source.def then
            return
        end
        table.remove(list, IndexOf(list, source.def))
        table.insert(list, IndexOf(list, target.row.def) + (target.before and 0 or 1), source.def)
    elseif target.kind == "toWindow" then
        local window = target.window
        if source.kind == "placement" then
            if window == source.window then
                return
            end
            if ItemIndex(window, source.def.id) then
                Print("\"" .. (source.def.name or "?") .. "\" is already in " .. (window.name or "?") .. ".")
                return
            end
            table.remove(source.window.items, IndexOf(source.window.items, source.item))
            table.insert(window.items, source.item)
        elseif Place(source.def, window) then
            Print("\"" .. (source.def.name or "?") .. "\" added to " .. (window.name or "?") .. ".")
        else
            return
        end
    elseif target.kind == "intoWindow" then
        local window = selWindow
        local index = #window.items + 1
        if not target.atEnd then
            index = IndexOf(window.items, target.row.item) + (target.before and 0 or 1)
        end
        if source.kind == "placement" and source.window == window then
            local from = IndexOf(window.items, source.item)
            if from < index then
                index = index - 1
            end
            table.remove(window.items, from)
            table.insert(window.items, index, source.item)
        elseif not Place(source.def, window, index) then
            return
        end
    elseif target.kind == "remove" then
        table.remove(source.window.items, IndexOf(source.window.items, source.item))
    end
    Changed()
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
    row.text:SetPoint("RIGHT", -4, 0)
    return row
end

local function CreateWindowRow(f, area, i)
    local row = NewListRow(area, i)
    row:SetScript("OnClick", function(self)
        local data = self.data
        if not data then
            return
        end
        if data.section then
            local closed = ns.UIState().closed
            closed[data.section] = (not closed[data.section]) or nil
        else
            Lock()
            if selWindow ~= data.window or selSeq then
                tab = "settings"
            end
            selWindow, selSeq = data.window, nil
        end
        f:Refresh()
    end)
    row:SetScript("OnDragStart", function(self)
        if self.data and self.data.window then
            StartListDrag({ kind = "window", window = self.data.window }, 134400)
        end
    end)
    row:SetScript("OnDragStop", FinishListDrag)
    return row
end

local function CreateLibraryRow(f, area, i)
    local row = NewListRow(area, i)
    row.text:SetPoint("LEFT", 4, 0)
    row:SetScript("OnClick", function(self)
        if self.def then
            EditSequence(self.def, false)
        end
    end)
    row:SetScript("OnDragStart", function(self)
        if self.def then
            StartListDrag({ kind = "seq", def = self.def }, SequenceIcon(self.def))
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
        GameTooltip:AddLine("Drag onto a window, or a window's Sequences tab, to show it there; drag within the " ..
            "library to reorder.", 0.6, 0.6, 0.6, true)
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

-- A shaded box behind a part of the options; brought forward (gold) while it's what you're
-- working on.
local PANE_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function NewPane(parent)
    local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pane:SetBackdrop(PANE_BACKDROP)
    pane:SetFrameLevel(parent:GetFrameLevel())
    return pane
end

local function SetPaneActive(pane, active)
    if active then
        pane:SetBackdropColor(1, 0.82, 0, 0.08)
        pane:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    else
        pane:SetBackdropColor(1, 1, 1, 0.03)
        pane:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.6)
    end
end

-- A scroll frame whose scroll bar only shows when there's something to scroll to.
local function NewScroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local bar = scroll.ScrollBar
    if type(bar) == "table" then
        bar:Hide()
        scroll:HookScript("OnScrollRangeChanged", function(self, _, yRange)
            bar:SetShown((yRange or self:GetVerticalScrollRange()) > 0.5)
        end)
    end
    return scroll
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

    local scroll = NewScroll(picker)
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
            if selSeq and not Unlocked() then
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

-- A window's Settings tab: everything about the window itself.
local function CreateSettingsTab(f, panel)
    local windowLabel = NewLabel(panel, "Window")
    windowLabel:SetPoint("TOPLEFT", 0, -6)
    f.windowName = NewEditBox(panel, 180, function(text)
        if selWindow and text ~= "" and text ~= selWindow.name then
            selWindow.name = text
            Changed()
        end
    end)
    f.windowName:SetPoint("LEFT", windowLabel, "RIGHT", 12, 0)
    -- Changing type keeps the other types' settings on the window for changing back; only the
    -- current type's are used.
    f.windowType = NewButton(panel, "", 190, function(self)
        if selWindow then
            local window = selWindow
            TypeMenu(self, "Window type", window.type, function(key)
                window.type = key
                ns.UIState().closed[key] = nil
                Changed()
            end)
        end
    end)
    f.windowType:SetPoint("LEFT", f.windowName, "RIGHT", 10, 0)
    Tooltip(f.windowType, "Window type (click to change)",
        TypeHelp() .. "\n\nChanging keeps each type's own settings for when you change back.")

    f.windowEnabled = NewCheck(panel, "Enabled", function(checked)
        if selWindow then
            selWindow.enabled = checked
            Changed()
        end
    end)
    f.windowEnabled:SetPoint("TOPLEFT", 0, -30)
    Tooltip(f.windowEnabled, "Enabled", "Disabled windows are kept, greyed out in the list, but not shown.")
    f.onlyInCombat = NewCheck(panel, "Only show in combat", function(checked)
        if selWindow then
            selWindow.onlyInCombat = checked
            Changed()
        end
    end)
    f.onlyInCombat:SetPoint("LEFT", f.windowEnabled.label, "RIGHT", 24, -1)
    f.windowClick = NewCheck(panel, "Click the Primary to cast", function(checked)
        if selWindow then
            ns.SetClickable(selWindow, checked)
        end
    end)
    f.windowClick:SetPoint("LEFT", f.onlyInCombat.label, "RIGHT", 24, -1)

    -- Switching and stacked windows only: what the fight is against, then the thresholds.
    local fightRow = CreateFrame("Frame", nil, panel)
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

    local gates = CreateFrame("Frame", nil, panel)
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

    -- Switching windows only.
    f.skipOverheal = NewCheck(panel, "Skip sequences that would overheal", function(checked)
        if selWindow then
            selWindow.skipOverheal = checked
            Changed()
        end
    end)
    f.skipOverheal:SetPoint("TOPLEFT", 0, -154)
    Tooltip(f.skipOverheal, "Skip sequences that would overheal",
        "A row (a Primary or sub-sequence) is skipped while your health plus all its direct heals, at the low " ..
        "end, would go over your maximum, and the next one shows instead. Heals over time (Rejuvenation, " ..
        "Regrowth's over-time part, bandages) don't count; healing potions do. Health is checked as it " ..
        "changes, so skipped rows come back as you take damage. With every row of a sequence overhealing, " ..
        "nothing shows for it.")

    -- Stacked windows only.
    f.showNext = NewCheck(panel, "Show the next one up", function(checked)
        if selWindow then
            selWindow.showNext = checked
            Changed()
        end
    end)
    f.showNext:SetPoint("TOPLEFT", 0, -154)
    Tooltip(f.showNext, "Show the next one up",
        "As well as the ones you can afford, show the cheapest one you can't yet, filling from grey as your " ..
        "mana rises. With costliest at the top, it's the top row.")
    f.costOrder = NewCheck(panel, "Costliest at the top", function(checked)
        if selWindow then
            selWindow.costOrder = checked
            Changed()
        end
    end)
    f.costOrder:SetPoint("LEFT", f.showNext.label, "RIGHT", 24, -1)
    Tooltip(f.costOrder, "Costliest at the top",
        "Ticked: the costliest at the top, so a newly affordable one takes the top row and the rest move down. " ..
        "Unticked: in the order they're listed in the window's Sequences tab (each sequence's Primary, then " ..
        "its sub-sequences), with the gaps closed up.")

    f.windowDelete = NewButton(panel, "Delete window", 120, function()
        if selWindow then
            Confirm(string.format("Delete the window \"%s\"? Its sequences stay in the library.",
                selWindow.name or "?"), { window = selWindow })
        end
    end)
    f.windowDelete:SetPoint("TOPLEFT", 0, -196)

    function f:RefreshSettings()
        local window = selWindow
        if not self.windowName:HasFocus() then
            self.windowName:SetText(window.name or "")
        end
        self.windowType:SetText("Type: " .. ns.TypeLabel(window.type) .. " (change)")
        self.windowEnabled:SetChecked(window.enabled and true or false)
        local stacked = window.type == "stacked"
        local dynamic = window.type ~= "fixed"
        self.skipOverheal:SetShown(window.type == "dynamic")
        self.skipOverheal:SetChecked(window.skipOverheal and true or false)
        self.showNext:SetShown(stacked)
        self.costOrder:SetShown(stacked)
        self.showNext:SetChecked(window.showNext and true or false)
        self.costOrder:SetChecked(window.costOrder ~= false)
        -- Delete sits just under the last of this type's settings.
        self.windowDelete:ClearAllPoints()
        self.windowDelete:SetPoint("TOPLEFT", 0, window.type == "fixed" and -66 or -192)
        self.windowClick:SetShown(window.type == "fixed")
        self.windowClick:SetChecked(window.clickable ~= false)
        self.onlyInCombat:SetChecked(window.onlyInCombat and true or false)
        self.gates:SetShown(dynamic)
        if dynamic then
            self.manaGate:SetChecked(window.manaGate and true or false)
            self.healthGate:SetChecked(window.healthGate and true or false)
            for box, key in pairs({ [self.manaMargin] = "manaMargin", [self.holdSeconds] = "holdSeconds",
                [self.healthPercent] = "healthPercent" }) do
                if not box:HasFocus() then
                    box:SetText(tostring(window[key] or 0))
                end
            end
        end
        -- Only applies with "only show in combat": greyed out without it.
        self.fightRow:SetShown(dynamic)
        local inCombatOnly = window.onlyInCombat and true or false
        for _, check in ipairs(self.fightChecks) do
            check:SetChecked((window.fight or "all") == check.key)
            check:SetEnabled(inCombatOnly)
            check.label:SetFontObject(inCombatOnly and "GameFontHighlightSmall" or "GameFontDisableSmall")
        end
        self.fightLabel:SetFontObject(inCombatOnly and "GameFontHighlightSmall" or "GameFontDisableSmall")
    end
end

-- A window's Sequences tab: its sequences in display order, each opening (on a click) to
-- small strips of its rows and its options in this window.
local function CreateSequencesTab(f, panel)
    local hint = NewLabel(panel, "Drag sequences here from the library, and within the list to reorder. Click one " ..
        "for its details; right-click it, or drag it off the options, to take it out of this window.",
        "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, -2)
    hint:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")

    local scroll = NewScroll(panel)
    scroll:SetPoint("TOPLEFT", 0, -34)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(490, 10)
    scroll:SetScrollChild(content)
    f.seqScroll, f.seqContent, f.entries = scroll, content, {}
    f.seqEmpty = NewLabel(panel, "No sequences in this window yet: drag one here from the library.", "GameFontDisable")
    f.seqEmpty:SetPoint("TOP", 0, -70)

    local function SetIncluded(entry, variation, included)
        if entry.item and variation then
            ns.EnsureVariationIds(entry.def)
            entry.item.excluded = entry.item.excluded or {}
            entry.item.excluded[variation.vid] = (not included) or nil
            Changed()
        end
    end

    local function Strip(entry, k)
        local strip = entry.strips[k]
        if strip then
            return strip
        end
        strip = CreateFrame("Frame", nil, entry.details)
        strip:SetSize(470, STRIP_HEIGHT)
        strip.icons = {}
        for i = 1, MAX_ENTRIES do
            local icon = CreateFrame("Button", nil, strip)
            icon:SetSize(MINI_SIZE, MINI_SIZE)
            icon:SetPoint("LEFT", (i - 1) * (MINI_SIZE + 2), 0)
            icon.texture = icon:CreateTexture(nil, "ARTWORK")
            icon.texture:SetAllPoints()
            icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon:SetScript("OnEnter", function(self)
                if self.entry then
                    EntryTooltip(self, self.entry)
                    GameTooltip:Show()
                end
            end)
            icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
            strip.icons[i] = icon
        end
        strip.label = NewLabel(strip, "", "GameFontDisableSmall")
        strip.label:SetPoint("LEFT", MAX_ENTRIES * (MINI_SIZE + 2) + 6, 0)
        strip.include = NewCheck(strip, "Include", function(checked)
            SetIncluded(entry, strip.variation, checked)
        end)
        strip.include:SetPoint("LEFT", MAX_ENTRIES * (MINI_SIZE + 2) + 110, 0)
        Tooltip(strip.include, "Include in this window",
            "Stacked windows list every row you include from their sequences. This only changes this window.")
        entry.strips[k] = strip
        return strip
    end

    function f:Entry(i)
        local entry = self.entries[i]
        if entry then
            return entry
        end
        entry = CreateFrame("Frame", nil, content)
        entry:SetWidth(490)
        entry.strips = {}
        local header = CreateFrame("Button", nil, entry)
        header:SetHeight(LIST_ROW_HEIGHT)
        header:SetPoint("TOPLEFT")
        header:SetPoint("TOPRIGHT")
        header:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        header:RegisterForDrag("LeftButton")
        header.text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        header.text:SetPoint("LEFT", 4, 0)
        header.text:SetPoint("RIGHT", -4, 0)
        header.text:SetJustifyH("LEFT")
        header.text:SetWordWrap(false)
        header:SetScript("OnClick", function(_, button)
            local window, item, def = selWindow, entry.item, entry.def
            if not (window and item) then
                return
            end
            if button == "RightButton" then
                table.remove(window.items, IndexOf(window.items, item))
                Changed()
            else
                local expanded = ns.UIState().expanded
                local key = ExpandedKey(window, def)
                expanded[key] = (not expanded[key]) or nil
                f:Refresh()
            end
        end)
        header:SetScript("OnDragStart", function()
            if entry.item then
                StartListDrag({ kind = "placement", window = selWindow, item = entry.item, def = entry.def },
                    SequenceIcon(entry.def))
            end
        end)
        header:SetScript("OnDragStop", FinishListDrag)
        entry.header = header

        local details = CreateFrame("Frame", nil, entry)
        details:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 16, 0)
        details:SetPoint("RIGHT", entry, "RIGHT", 0, 0)
        details:SetHeight(10)
        entry.details = details
        details.show = NewCheck(details, "Show in this window", function(checked)
            if entry.item then
                entry.item.enabled = checked
                Changed()
            end
        end)
        details.show:SetPoint("TOPLEFT", 0, 0)
        details.edit = NewButton(details, "Edit in library", 110, function()
            if entry.def then
                EditSequence(entry.def, true)
            end
        end)
        details.edit:SetPoint("LEFT", details.show.label, "RIGHT", 16, 0)
        details.pin = NewCheck(details, "Pin Primary to the top", function(checked)
            if selWindow and entry.def then
                selWindow.topId = checked and entry.def.id or nil
                Changed()
            end
        end)
        details.pin:SetPoint("LEFT", details.edit, "RIGHT", 12, 0)
        Tooltip(details.pin, "Pin Primary to the top",
            "This sequence's Primary is always shown at the top of the window, filling from grey as your mana " ..
            "rises; the rest stack under it. One sequence per window.")
        self.entries[i] = entry
        return entry
    end

    function f:RefreshSequences()
        local window = selWindow
        local expanded = ns.UIState().expanded
        local stacked = window.type == "stacked"
        local y, n = 0, 0
        self.lastEntry = nil
        for _, item in ipairs(window.items) do
            local def = ns.FindSequence(item.id)
            if def then
                n = n + 1
                local entry = self:Entry(n)
                entry.item, entry.def = item, def
                local open = expanded[ExpandedKey(window, def)]
                local learned = ns.AllLearned(def.entries)
                local name = (def.name or "?") .. (learned and "" or " (not learned)")
                entry.header.text:SetText((open and "-  " or "+  ") ..
                    ((item.enabled and learned) and name or ("|cff808080" .. name .. "|r")))
                local height = LIST_ROW_HEIGHT
                if open then
                    local details = entry.details
                    details.show:SetChecked(item.enabled and true or false)
                    details.pin:SetShown(stacked)
                    details.pin:SetChecked(window.topId == def.id)
                    ns.EnsureVariationIds(def)
                    local excluded = item.excluded or {}
                    local variations = { def }
                    for _, sub in ipairs(def.subs) do
                        if #sub.entries > 0 then
                            variations[#variations + 1] = sub
                        end
                    end
                    local dy = 26
                    for k, variation in ipairs(variations) do
                        local strip = Strip(entry, k)
                        strip.variation = variation
                        strip:ClearAllPoints()
                        strip:SetPoint("TOPLEFT", 0, -dy)
                        for i, icon in ipairs(strip.icons) do
                            local e = variation.entries[i]
                            icon.entry = e
                            if e then
                                local info = ns.ResolveEntry(e)
                                icon.texture:SetTexture(info.icon)
                                icon.texture:SetDesaturated(info.known == false)
                                icon:Show()
                            else
                                icon:Hide()
                            end
                        end
                        strip.label:SetText(k == 1 and "Primary" or ("Sub-sequence " .. (k - 1)))
                        strip.include:SetShown(stacked and not (k == 1 and window.topId == def.id))
                        strip.include:SetChecked(not excluded[variation.vid])
                        strip:Show()
                        dy = dy + STRIP_HEIGHT
                    end
                    for k = #variations + 1, #entry.strips do
                        entry.strips[k]:Hide()
                    end
                    details:SetHeight(dy + 4)
                    details:Show()
                    height = height + dy + 4
                else
                    entry.details:Hide()
                end
                entry:SetHeight(height)
                entry:ClearAllPoints()
                entry:SetPoint("TOPLEFT", 0, -y)
                entry:Show()
                self.lastEntry = entry
                y = y + height + 2
            end
        end
        for i = n + 1, #self.entries do
            self.entries[i]:Hide()
            self.entries[i].item = nil
        end
        content:SetHeight(math.max(y, 10))
        self.seqEmpty:SetShown(n == 0)
    end
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

    -- The line showing where a dragged list item will go.
    f.dropLine = f:CreateTexture(nil, "OVERLAY")
    f.dropLine:SetColorTexture(1, 0.82, 0, 1)
    f.dropLine:SetHeight(2)
    f.dropLine:Hide()

    -- Shaded boxes behind the windows list, the library and the right-hand side.
    f.windowsPane = NewPane(f)
    f.libraryPane = NewPane(f)
    f.rightPane = NewPane(f)

    -- Left, top: the windows, by type.
    local windowsLabel = NewLabel(f, "Windows")
    windowsLabel:SetPoint("TOPLEFT", LEFT, -52)
    local newWindow = NewButton(f, "New window", 100, NewWindow)
    newWindow:SetPoint("TOPRIGHT", f, "TOPLEFT", RIGHT_X - 20, -46)
    Tooltip(newWindow, "New window", "Pick its type. You can change it later.\n\n" .. TypeHelp())
    local windowArea = ScrollArea(f, WINDOW_ROWS, function(delta)
        local most = math.max(0, #WindowListItems() - WINDOW_ROWS)
        windowOffset = math.max(0, math.min(most, windowOffset - delta))
    end)
    windowArea:SetPoint("TOPLEFT", LEFT, -72)
    for i = 1, WINDOW_ROWS do
        windowRows[i] = CreateWindowRow(f, windowArea, i)
    end

    -- Left, bottom: the library.
    local libraryLabel = NewLabel(f, "Sequence Library")
    libraryLabel:SetPoint("TOPLEFT", windowArea, "BOTTOMLEFT", 0, -18)
    local newSequence = NewButton(f, "New sequence", 100, NewSequence)
    newSequence:SetPoint("RIGHT", newWindow, "RIGHT", 0, 0)
    newSequence:SetPoint("TOP", libraryLabel, "TOP", 0, 6)
    Tooltip(newSequence, "New sequence", "A new, empty sequence in the library, opened for editing. With a " ..
        "window showing, it's added to that window too.")
    local libraryArea = ScrollArea(f, LIBRARY_ROWS, function(delta)
        local most = math.max(0, #Library() - LIBRARY_ROWS)
        libraryOffset = math.max(0, math.min(most, libraryOffset - delta))
    end)
    libraryArea:SetPoint("TOPLEFT", libraryLabel, "BOTTOMLEFT", 0, -8)
    for i = 1, LIBRARY_ROWS do
        libraryRows[i] = CreateLibraryRow(f, libraryArea, i)
    end
    f.windowsPane:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT - 8, -42)
    f.windowsPane:SetPoint("BOTTOMRIGHT", windowArea, "BOTTOMRIGHT", 8, -6)
    f.libraryPane:SetPoint("TOPLEFT", libraryLabel, "TOPLEFT", -8, 10)
    f.libraryPane:SetPoint("BOTTOMRIGHT", libraryArea, "BOTTOMRIGHT", 8, -6)
    f.rightPane:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X - 10, -40)
    f.rightPane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 36)

    -- Right, for a window: its tabs.
    local windowView = CreateFrame("Frame", nil, f)
    windowView:SetPoint("TOPLEFT", RIGHT_X, -44)
    windowView:SetPoint("BOTTOMRIGHT", -20, 40)
    f.windowView = windowView
    -- Tabs: a box for the tab's contents, with the tabs along its top. The open tab is the
    -- box's colour and sits over its top edge, so it reads as joined to it; the other is darker.
    local tabBox = CreateFrame("Frame", nil, windowView, "BackdropTemplate")
    tabBox:SetPoint("TOPLEFT", 0, -26)
    tabBox:SetPoint("BOTTOMRIGHT", 0, 0)
    tabBox:SetBackdrop(PANE_BACKDROP)
    tabBox:SetBackdropColor(0.22, 0.2, 0.14, 0.75)
    tabBox:SetBackdropBorderColor(1, 0.82, 0, 0.7)
    f.tabButtons = {}
    for i, key in ipairs({ "settings", "sequences" }) do
        local button = CreateFrame("Button", nil, windowView, "BackdropTemplate")
        button:SetSize(110, 26)
        button:SetPoint("BOTTOMLEFT", tabBox, "TOPLEFT", 10 + (i - 1) * 114, -3)
        button:SetBackdrop(PANE_BACKDROP)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.text:SetPoint("CENTER", 0, 1)
        button.text:SetText(key == "settings" and "Settings" or "Sequences")
        button:SetScript("OnClick", function()
            tab = key
            f:Refresh()
        end)
        button.key = key
        function button:SetSelected(selected)
            if selected then
                self:SetFrameLevel(tabBox:GetFrameLevel() + 2)
                self:SetBackdropColor(0.22, 0.2, 0.14, 1)
                self:SetBackdropBorderColor(1, 0.82, 0, 0.9)
                self.text:SetFontObject("GameFontNormal")
            else
                self:SetFrameLevel(tabBox:GetFrameLevel())
                self:SetBackdropColor(0, 0, 0, 0.5)
                self:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.6)
                self.text:SetFontObject("GameFontDisable")
            end
        end
        f.tabButtons[i] = button
    end
    -- Covers the box's top edge under the open tab (on a frame above the box, so it's on top).
    local joinFrame = CreateFrame("Frame", nil, windowView)
    joinFrame:SetAllPoints(windowView)
    joinFrame:SetFrameLevel(tabBox:GetFrameLevel() + 3)
    f.tabJoin = joinFrame:CreateTexture(nil, "OVERLAY")
    f.tabJoin:SetColorTexture(0.22, 0.2, 0.14, 1)
    f.tabJoin:SetHeight(5)
    local settingsTab = CreateFrame("Frame", nil, tabBox)
    settingsTab:SetPoint("TOPLEFT", 10, -10)
    settingsTab:SetPoint("BOTTOMRIGHT", -8, 8)
    f.settingsTab = settingsTab
    CreateSettingsTab(f, settingsTab)
    local sequencesTab = CreateFrame("Frame", nil, tabBox)
    sequencesTab:SetPoint("TOPLEFT", 10, -10)
    sequencesTab:SetPoint("BOTTOMRIGHT", -8, 8)
    f.sequencesTab = sequencesTab
    CreateSequencesTab(f, sequencesTab)

    -- Right, for a library sequence: the editor.
    local detail = CreateFrame("Frame", nil, f)
    detail:SetPoint("TOPLEFT", RIGHT_X, -44)
    detail:SetPoint("BOTTOMRIGHT", -20, 40)
    f.detail = detail

    local nameLabel = NewLabel(detail, "Sequence")
    nameLabel:SetPoint("TOPLEFT", 0, -6)
    f.nameBox = NewEditBox(detail, 200, function(text)
        if selSeq and text ~= "" and text ~= selSeq.name then
            selSeq.name = text
            Changed()
        end
    end)
    f.nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
    local copySequence = NewButton(detail, "Copy", 70, CopySequence)
    copySequence:SetPoint("LEFT", f.nameBox, "RIGHT", 12, 0)
    Tooltip(copySequence, "Copy", "Makes an independent copy of this sequence, to change for another window.")
    local deleteSequence = NewButton(detail, "Delete", 70, function()
        if selSeq then
            local used = UsedIn(selSeq)
            Confirm(string.format("Delete the sequence \"%s\"%s?", selSeq.name or "?",
                #used > 0 and (" from the library and from " .. table.concat(used, ", ")) or ""), { def = selSeq })
        end
    end)
    deleteSequence:SetPoint("LEFT", copySequence, "RIGHT", 4, 0)
    f.usedIn = NewLabel(detail, "", "GameFontDisableSmall")
    f.usedIn:SetPoint("TOPLEFT", 0, -28)
    f.usedIn:SetPoint("RIGHT", detail, "RIGHT", 0, 0)
    f.usedIn:SetJustifyH("LEFT")

    f.lockButton = NewButton(detail, "Unlock", 90, function()
        if Unlocked() then
            Lock()
        elseif selSeq then
            Lock() -- any other sequence still unlocked
            ns.unsortedSequence = selSeq
            Changed()
        end
    end)
    f.lockButton:SetPoint("TOPLEFT", 0, -44)
    Tooltip(f.lockButton, "Unlock / Lock",
        "Unlock to change the Primary and sub-sequences: an empty row waits at the bottom, and rows keep " ..
        "their places while you work. Lock (or pick something else) to drop empty rows and put them back in " ..
        "order, costliest first.")
    f.hideCheck = NewCheck(detail, "Hide when unusable", function(checked)
        if selSeq then
            selSeq.hideOnCooldown = checked
            Changed()
        end
    end)
    f.hideCheck:SetPoint("LEFT", f.lockButton, "RIGHT", 16, 0)
    Tooltip(f.hideCheck, "Hide when unusable",
        "While a row (the Primary or a sub-sequence) has a spell or item on cooldown, an item that's run out, a " ..
        "bandage while you're Recently Bandaged, or the wrong kind of target (Hibernate: beasts and dragonkin " ..
        "only), it's skipped and the next one shows instead. In switching and stacked windows; static windows " ..
        "always show the Primary. Cooldowns are only seen when the game lets addons read them.")

    local primaryLabel = NewLabel(detail, "Primary")
    primaryLabel:SetPoint("TOPLEFT", 0, -78)
    f.primaryCost = NewLabel(detail, "", "GameFontHighlightSmall")
    f.primaryCost:SetPoint("LEFT", primaryLabel, "RIGHT", 10, 0)
    f.primaryRow = CreateSlotRow(detail, function() return selSeq and selSeq.entries end, true)
    f.primaryRow.frame:SetPoint("TOPLEFT", 22, -96)

    local subsLabel = NewLabel(detail, "Sub-sequences")
    subsLabel:SetPoint("TOPLEFT", 0, -146)

    -- Sub-sequences: any number, in a scroll frame.
    local subScroll = NewScroll(detail)
    subScroll:SetPoint("TOPLEFT", 0, -162)
    subScroll:SetPoint("BOTTOMRIGHT", -24, 44)
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
        block.row.frame:SetPoint("TOPLEFT", 22, -14)
        block.cost = NewLabel(block, "", "GameFontHighlightSmall")
        block.cost:SetPoint("TOPLEFT", 22, 0)
        -- Remove: a small X to the left of the row.
        block.remove = CreateFrame("Button", nil, block)
        block.remove:SetSize(18, 18)
        block.remove:SetPoint("RIGHT", block.row.frame, "LEFT", -2, 0)
        block.remove:SetNormalFontObject("GameFontRedLarge")
        block.remove:SetHighlightFontObject("GameFontHighlightLarge")
        block.remove:SetText("x")
        block.remove:SetScript("OnClick", function()
            if SubAt(block) and Unlocked() then
                table.remove(selSeq.subs, block.index)
                Changed()
            end
        end)
        Tooltip(block.remove, "Remove this sub-sequence")
        self.subBlocks[i] = block
        return block
    end

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

    local moveHint = NewLabel(f, "While this is open, every window is shown: drag one to move it, or its corner to " ..
        "resize it (double-click the corner for normal size).", "GameFontDisableSmall")
    moveHint:SetPoint("BOTTOMLEFT", LEFT, 22)

    f.picker = CreatePicker(f)

    function f:Refresh()
        local windows = Windows()
        if selWindow and not IndexOf(windows, selWindow) then
            selWindow = nil
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
        local closed = ns.UIState().closed
        for i, row in ipairs(windowRows) do
            local data = items[i + windowOffset]
            row.data = data
            if data then
                row.text:ClearAllPoints()
                row.text:SetPoint("RIGHT", -4, 0)
                if data.section then
                    row.text:SetPoint("LEFT", 2, 0)
                    row.text:SetFontObject("GameFontNormal")
                    row.text:SetText((closed[data.section] and "+  " or "-  ") .. ns.TypeLabel(data.section) ..
                        "  |cff808080(" .. data.count .. ")|r")
                    row.selectedTexture:Hide()
                else
                    local window = data.window
                    row.text:SetPoint("LEFT", 18, 0)
                    row.text:SetFontObject("GameFontHighlight")
                    row.text:SetText(window.enabled and (window.name or "?") or ("|cff808080" .. (window.name or "?") .. "|r"))
                    row.selectedTexture:SetShown(window == selWindow and not selSeq)
                end
                row:Show()
            else
                row:Hide()
            end
        end

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
                row.selectedTexture:SetShown(def == selSeq)
                row:Show()
            else
                row:Hide()
            end
        end

        -- Right: a window's tabs, or a library sequence. Its side is brought forward.
        local showWindow = selWindow ~= nil and selSeq == nil
        SetPaneActive(self.windowsPane, showWindow)
        SetPaneActive(self.libraryPane, selSeq ~= nil)
        SetPaneActive(self.rightPane, showWindow or selSeq ~= nil)
        self.windowView:SetShown(showWindow)
        self.detail:SetShown(selSeq ~= nil)
        self.empty:SetShown(not showWindow and selSeq == nil)
        self.empty:SetText("Press New window to start.")
        if showWindow then
            for _, button in ipairs(self.tabButtons) do
                button:SetSelected(button.key == tab)
                if button.key == tab then
                    self.tabJoin:ClearAllPoints()
                    self.tabJoin:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 4, -2)
                    self.tabJoin:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, -2)
                end
            end
            self.settingsTab:SetShown(tab == "settings")
            self.sequencesTab:SetShown(tab == "sequences")
            self:RefreshSettings()
            self:RefreshSequences()
        end

        local def = selSeq
        if def then
            if not self.nameBox:HasFocus() then
                self.nameBox:SetText(def.name or "")
            end
            local used = UsedIn(def)
            self.usedIn:SetText(#used > 0 and ("Used in: " .. table.concat(used, ", "))
                or "Not in any window yet: drag it from the library onto one.")
            self.lockButton:SetText(Unlocked() and "Lock" or "Unlock")
            local anyCooldown = ns.AnyCooldown(def.entries)
            for _, sub in ipairs(def.subs) do
                anyCooldown = anyCooldown or ns.AnyCooldown(sub.entries)
            end
            self.hideCheck:SetShown(anyCooldown or def.hideOnCooldown)
            self.hideCheck:SetChecked(def.hideOnCooldown and true or false)
            self.primaryCost:SetText(CostText(def.entries))
            RefreshSlotRow(self.primaryRow)
            for i = 1, math.max(#def.subs, #self.subBlocks) do
                local sub = def.subs[i]
                if sub then
                    local block = self:SubBlock(i)
                    block.remove:SetShown(Unlocked() and not IsEmpty(sub))
                    block.cost:SetText(i .. ". " .. CostText(sub.entries))
                    RefreshSlotRow(block.row)
                    block:Show()
                elseif self.subBlocks[i] then
                    self.subBlocks[i]:Hide()
                end
            end
            self.subContent:SetHeight(math.max(#def.subs * SUB_BLOCK_HEIGHT, 10))
        end

        self.profileButton:SetText(ProfileLabel(ns.CurrentProfile() or "?"))
        -- The list of spells and items is only for adding to a sequence: open while one is unlocked.
        self.picker:SetShown(Unlocked())
        if Unlocked() then
            self.picker:Refresh()
        end
    end

    -- The mana figures change with regen and the 5-second rule; keep them current. While a
    -- list item is dragged, the line showing where it'll go follows the cursor.
    local elapsedSinceCosts = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        if listDrag then
            UpdateDropLine()
        end
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
            UpdateDropLine()
        end
    end)
    f:Hide()
    return f
end

-- Open (show = true) or toggle the editor. With a window, select it (opening its section and
-- scrolling the list to it).
function ns.ToggleEditor(show, window)
    if not ns.db then
        return
    end
    editor = editor or CreateEditor()
    if show or not editor:IsShown() then
        if window and IndexOf(Windows(), window) then
            Lock()
            selWindow, selSeq, tab = window, nil, "settings"
            ns.UIState().closed[window.type or "dynamic"] = nil
            for i, data in ipairs(WindowListItems()) do
                if data.window == window then
                    if i <= windowOffset or i > windowOffset + WINDOW_ROWS then
                        windowOffset = math.max(0, i - 2)
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
