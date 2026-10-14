-- Forever Sequences editor: windows, the sequences in them, and their rows of icons.
--
--   - Left: windows and their sequences, in display order. Tick to show or hide, arrows to
--     reorder, drag a sequence onto another window (or another sequence) to move it there.
--   - Right: the selected window's settings, then the selected sequence's rows.
--   - Beside it: every spell you know and every usable item you carry, to drag into a row
--     (or click to add to the end of the Primary).
--   - Drag a spell from the spellbook or an item from your bags onto a slot; the "+" slot
--     adds at the end. Drag an icon within its row to move it, onto another row to copy it
--     (from the Primary onto a sub-sequence's "+" slot it goes in Primary order), or off the
--     window to remove it. Shift-right-click also removes. Right-click a spell to step down
--     through the ranks you know ("R3" on the icon), and back round to your highest.
--   - While this is open every window is shown and can be dragged to move it.

local _, ns = ...

local MAX_ENTRIES = 8
local MAX_SUBS = 4
local SLOT_SIZE = 34
local SLOT_GAP = 4
local VISIBLE_ROWS = 18
local LIST_ROW_HEIGHT = 22
local LEFT = 20
local RIGHT_X = 250
local PICKER_COLUMNS = 7
local PICKER_ROWS = 13
local PICKER_TILE = 34
local REGEN_MODES = { "smooth", "ticks", "off" }
local REGEN_LABELS = { smooth = "Regen: smooth", ticks = "Regen: 2s ticks", off = "Regen: off" }

local editor
local selWindow, selSeq   -- the selected window, and sequence (nil when a window is selected)
local listOffset = 0
local drag                -- an icon being dragged: { entry, row (nil from the list of spells), index }
local listDrag            -- a sequence being dragged in the list: { def, window }

local function Print(msg)
    ns.Print(msg)
end

local function Windows()
    return ns.db.windows
end

local function Changed()
    ns.Rebuild()
    if editor then
        editor:Refresh()
    end
end

local function IndexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then
            return i
        end
    end
    return nil
end

local function WindowOf(def)
    for _, window in ipairs(Windows()) do
        if IndexOf(window.sequences, def) then
            return window
        end
    end
    return nil
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
    for _, row in ipairs(slotRows) do
        if row.frame:IsVisible() then
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

-- Right-click a spell: next rank down, then back to the highest.
local function CycleRank(row, index)
    local entry = row.list()[index]
    if not entry or entry.kind ~= "spell" then
        return
    end
    local ranks = ns.KnownRanks(entry.name)
    if #ranks <= 1 then
        Print(entry.name .. ": only one rank known.")
        return
    end
    local current = #ranks
    for i, rank in ipairs(ranks) do
        if rank == entry.rank then
            current = i
        end
    end
    local nextIndex = current - 1
    if nextIndex < 1 or ranks[nextIndex] == ranks[#ranks] then
        entry.rank = nil
    else
        entry.rank = ranks[nextIndex]
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
        GameTooltip:AddLine("Drag to move or copy, or off the window to remove.", 0.6, 0.6, 0.6, true)
        if entry.kind == "spell" then
            GameTooltip:AddLine("Right-click: change rank. Shift-right-click: remove.", 0.6, 0.6, 0.6, true)
        else
            GameTooltip:AddLine("Shift-right-click: remove.", 0.6, 0.6, 0.6, true)
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
        if GetCursorInfo() then
            DropCursor(self.row, self.index)
        elseif button == "RightButton" and self.row.list()[self.index] then
            if IsShiftKeyDown() then
                table.remove(self.row.list(), self.index)
                Changed()
            else
                CycleRank(self.row, self.index)
            end
        end
    end)
    slot:SetScript("OnReceiveDrag", function(self)
        DropCursor(self.row, self.index)
    end)
    slot:SetScript("OnDragStart", function(self)
        local entry = self.row.list()[self.index]
        if entry and not GetCursorInfo() then
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
            slot.icon:Show()
            slot.plus:Hide()
            slot.rank:SetText(ns.RankText(info) or "")
            slot:Show()
        elseif i == #list + 1 and i <= MAX_ENTRIES then
            slot.icon:Hide()
            slot.plus:Show()
            slot.rank:SetText("")
            slot:Show()
        else
            slot:Hide()
        end
    end
end

local function CostText(entries)
    if not entries or #entries == 0 then
        return ""
    end
    local need, cost = ns.Need(entries)
    return string.format("needs %d mana now (costs %d)", need, cost)
end

----------------------------------------------------------------------------------------------
-- Windows and sequences
----------------------------------------------------------------------------------------------

StaticPopupDialogs["FOREVERSEQUENCES_DELETE"] = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data)
        if data and data.def then
            table.remove(data.window.sequences, IndexOf(data.window.sequences, data.def))
            selSeq = nil
        elseif data and data.window then
            table.remove(Windows(), IndexOf(Windows(), data.window))
            selWindow, selSeq = Windows()[1], nil
        end
        Changed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function NewWindow()
    local list = Windows()
    local window = {
        name = "Window " .. (#list + 1),
        type = "dynamic",
        enabled = true,
        onlyInCombat = false,
        sequences = {},
    }
    list[#list + 1] = window
    selWindow, selSeq = window, nil
    Changed()
end

local function NewSequence()
    if not selWindow then
        NewWindow()
    end
    local def = {
        name = "Sequence " .. (#selWindow.sequences + 1),
        enabled = true,
        hideOnCooldown = false,
        entries = {},
        subs = {},
    }
    selWindow.sequences[#selWindow.sequences + 1] = def
    selSeq = def
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

-- The list on the left: each window, then its sequences.
local function ListItems()
    local items = {}
    for _, window in ipairs(Windows()) do
        items[#items + 1] = { window = window }
        for _, def in ipairs(window.sequences) do
            items[#items + 1] = { window = window, def = def }
        end
    end
    return items
end

-- Sub-sequences listed dearest first, as they're worked out when the options open.
local function SortSubs()
    local changed = false
    for _, window in ipairs(Windows()) do
        for _, def in ipairs(window.sequences) do
            local needs = {}
            for _, sub in ipairs(def.subs) do
                needs[sub] = ns.Need(sub.entries)
            end
            local before = {}
            for i, sub in ipairs(def.subs) do
                before[i] = sub
            end
            table.sort(def.subs, function(a, b)
                if needs[a] ~= needs[b] then
                    return needs[a] > needs[b]
                end
                return IndexOf(before, a) < IndexOf(before, b)
            end)
            for i, sub in ipairs(def.subs) do
                changed = changed or before[i] ~= sub
            end
        end
    end
    return changed
end

----------------------------------------------------------------------------------------------
-- The window
----------------------------------------------------------------------------------------------

local function CreateListRow(f, listArea, i)
    local item = CreateFrame("Button", nil, listArea)
    item:SetSize(listArea:GetWidth(), LIST_ROW_HEIGHT)
    item:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_HEIGHT)
    item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    item:RegisterForDrag("LeftButton")
    item.selectedTexture = item:CreateTexture(nil, "BACKGROUND")
    item.selectedTexture:SetAllPoints()
    item.selectedTexture:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    item.selectedTexture:SetBlendMode("ADD")
    item.selectedTexture:SetVertexColor(1, 0.82, 0)

    item.enabled = NewCheck(item, "", function(checked)
        local target = item.data and (item.data.def or item.data.window)
        if target then
            target.enabled = checked
            Changed()
        end
    end)
    item.enabled:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show on screen")
        GameTooltip:AddLine("Unticked ones are kept but hidden, and take no space.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    item.enabled:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function Shift(delta)
        local data = item.data
        if data.def then
            Move(data.window.sequences, data.def, delta)
        else
            Move(Windows(), data.window, delta)
        end
    end
    item.down = NewArrow(item, false, function() Shift(1) end)
    item.down:SetPoint("RIGHT", 0, 0)
    item.up = NewArrow(item, true, function() Shift(-1) end)
    item.up:SetPoint("RIGHT", item.down, "LEFT", 0, 0)

    item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    item.text:SetPoint("RIGHT", item.up, "LEFT", -2, 0)
    item.text:SetJustifyH("LEFT")
    item.text:SetWordWrap(false)

    item:SetScript("OnClick", function(self)
        selWindow = self.data.window
        selSeq = self.data.def
        f:Refresh()
    end)

    -- Drag a sequence onto a window (to the end of it) or onto another sequence (before it).
    item:SetScript("OnDragStart", function(self)
        if self.data and self.data.def then
            listDrag = { def = self.data.def, window = self.data.window }
            local first = self.data.def.entries[1]
            ghostIcon:SetTexture(first and ns.ResolveEntry(first).icon or 134400)
            ghost:Show()
        end
    end)
    item:SetScript("OnDragStop", function()
        if not listDrag then
            return
        end
        ghost:Hide()
        local source = listDrag
        listDrag = nil
        for _, other in ipairs(f.listRows) do
            if other:IsVisible() and other:IsMouseOver() and other.data and other.data.def ~= source.def then
                table.remove(source.window.sequences, IndexOf(source.window.sequences, source.def))
                local target = other.data.window.sequences
                local index = other.data.def and IndexOf(target, other.data.def) or #target + 1
                table.insert(target, index, source.def)
                selWindow, selSeq = other.data.window, source.def
                Changed()
                return
            end
        end
    end)
    return item
end

local function CreatePicker(f)
    local picker = CreateFrame("Frame", nil, f, "BackdropTemplate")
    picker:SetPoint("TOPLEFT", f, "TOPRIGHT", -6, 0)
    picker:SetSize(PICKER_COLUMNS * (PICKER_TILE + 4) + 40, f:GetHeight())
    Backdrop(picker)
    picker:EnableMouse(true)

    local title = NewLabel(picker, "Spells and items", "GameFontNormal")
    title:SetPoint("TOP", 0, -18)
    local hint = NewLabel(picker, "Drag into a row, or click to add to the Primary.", "GameFontDisableSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)

    local search = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    search:SetSize(PICKER_COLUMNS * (PICKER_TILE + 4) - 10, 20)
    search:SetPoint("TOPLEFT", 26, -58)
    search:SetAutoFocus(false)
    local searchHint = NewLabel(search, "Search", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 4, 0)
    search:SetScript("OnTextChanged", function(self)
        searchHint:SetShown(self:GetText() == "")
        picker.offset = 0
        picker:Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local grid = CreateFrame("Frame", nil, picker)
    grid:SetPoint("TOPLEFT", 20, -86)
    grid:SetSize(PICKER_COLUMNS * (PICKER_TILE + 4), PICKER_ROWS * (PICKER_TILE + 4))
    grid:EnableMouseWheel(true)
    picker.offset = 0
    grid:SetScript("OnMouseWheel", function(_, delta)
        local rowsTotal = math.ceil(#(picker.entries or {}) / PICKER_COLUMNS)
        picker.offset = math.max(0, math.min(math.max(0, rowsTotal - PICKER_ROWS), picker.offset - delta))
        picker:Refresh()
    end)

    picker.tiles = {}
    for i = 1, PICKER_COLUMNS * PICKER_ROWS do
        local tile = CreateFrame("Button", nil, grid)
        tile:SetSize(PICKER_TILE, PICKER_TILE)
        local col = (i - 1) % PICKER_COLUMNS
        local rowIndex = math.floor((i - 1) / PICKER_COLUMNS)
        tile:SetPoint("TOPLEFT", col * (PICKER_TILE + 4), -rowIndex * (PICKER_TILE + 4))
        tile.icon = tile:CreateTexture(nil, "ARTWORK")
        tile.icon:SetAllPoints()
        tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        tile:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        tile:RegisterForDrag("LeftButton")
        tile:SetScript("OnDragStart", function(self)
            StartDrag(self.item.entry)
        end)
        tile:SetScript("OnDragStop", FinishDrag)
        tile:SetScript("OnClick", function(self)
            if selSeq and Insert(selSeq.entries, #selSeq.entries + 1, ns.CopyTable(self.item.entry)) then
                Changed()
            elseif not selSeq then
                Print("select a sequence first.")
            end
        end)
        tile:SetScript("OnEnter", function(self)
            EntryTooltip(self, self.item.entry)
            GameTooltip:AddLine("Drag into a row, or click to add to the end of the Primary.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
        picker.tiles[i] = tile
    end

    local more = NewLabel(picker, "", "GameFontDisableSmall")
    more:SetPoint("BOTTOM", 0, 20)

    function picker:Refresh()
        self.entries = ns.PickerEntries(search:GetText():lower())
        for i, tile in ipairs(self.tiles) do
            local item = self.entries[i + self.offset * PICKER_COLUMNS]
            tile.item = item
            if item then
                tile.icon:SetTexture(item.icon)
                tile:Show()
            else
                tile:Hide()
            end
        end
        local rowsTotal = math.ceil(#self.entries / PICKER_COLUMNS)
        more:SetText(rowsTotal > PICKER_ROWS and "Scroll for more" or "")
    end
    return picker
end

local function CreateEditor()
    local f = CreateFrame("Frame", "ForeverSequencesEditor", UIParent, "BackdropTemplate")
    f:SetSize(800, 600)
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

    -- Escape closes it. (It isn't a "special frame", so opening the spellbook leaves it open.)
    if not InCombatLockdown() then
        f:EnableKeyboard(true)
        pcall(f.SetPropagateKeyboardInput, f, true)
    end
    f:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then
            return
        end
        if key == "ESCAPE" then
            pcall(self.SetPropagateKeyboardInput, self, false)
            self:Hide()
        else
            pcall(self.SetPropagateKeyboardInput, self, true)
        end
    end)

    local title = NewLabel(f, "Forever Sequences", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Left: windows and their sequences, in display order.
    local listLabel = NewLabel(f, "Windows and sequences")
    listLabel:SetPoint("TOPLEFT", LEFT, -48)

    local listArea = CreateFrame("Frame", nil, f)
    listArea:SetPoint("TOPLEFT", LEFT, -66)
    listArea:SetSize(RIGHT_X - LEFT - 16, VISIBLE_ROWS * LIST_ROW_HEIGHT)
    listArea:EnableMouseWheel(true)
    listArea:SetScript("OnMouseWheel", function(_, delta)
        local most = math.max(0, #ListItems() - VISIBLE_ROWS)
        listOffset = math.max(0, math.min(most, listOffset - delta))
        f:Refresh()
    end)
    f.listRows = {}
    for i = 1, VISIBLE_ROWS do
        f.listRows[i] = CreateListRow(f, listArea, i)
    end

    local newWindow = NewButton(f, "New window", 104, NewWindow)
    newWindow:SetPoint("TOPLEFT", listArea, "BOTTOMLEFT", 0, -8)
    local newSequence = NewButton(f, "New sequence", 110, NewSequence)
    newSequence:SetPoint("LEFT", newWindow, "RIGHT", 4, 0)
    f.deleteButton = NewButton(f, "Delete", 104, function()
        local text, data
        if selSeq then
            text = string.format("Delete the sequence \"%s\"?", selSeq.name or "?")
            data = { def = selSeq, window = WindowOf(selSeq) }
        elseif selWindow then
            text = string.format("Delete the window \"%s\" and its %d sequence(s)?",
                selWindow.name or "?", #selWindow.sequences)
            data = { window = selWindow }
        end
        if text then
            local popup = StaticPopup_Show("FOREVERSEQUENCES_DELETE", text)
            if popup then
                popup.data = data
            end
        end
    end)
    f.deleteButton:SetPoint("TOPLEFT", newWindow, "BOTTOMLEFT", 0, -4)

    -- Right, top: the selected window.
    local windowPanel = CreateFrame("Frame", nil, f)
    windowPanel:SetPoint("TOPLEFT", RIGHT_X, -44)
    windowPanel:SetSize(520, 56)
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
    f.windowType = NewButton(windowPanel, "", 190, function()
        if selWindow then
            selWindow.type = selWindow.type == "fixed" and "dynamic" or "fixed"
            Changed()
        end
    end)
    f.windowType:SetPoint("LEFT", f.windowName, "RIGHT", 10, 0)
    Tooltip(f.windowType, "Window type",
        "Dynamic: one row per sequence, showing whichever of its sequences fits your mana; rows close up " ..
        "when a sequence has nothing to show.\nFixed: the Primary is always shown and can be clicked to cast, " ..
        "with the best sub-sequence under it. Nothing moves.")
    f.onlyInCombat = NewCheck(windowPanel, "Only show in combat", function(checked)
        if selWindow then
            selWindow.onlyInCombat = checked
            Changed()
        end
    end)
    f.onlyInCombat:SetPoint("TOPLEFT", 0, -30)

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 0.82, 0, 0.25)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", RIGHT_X, -104)
    divider:SetPoint("RIGHT", f, "RIGHT", -20, 0)

    -- Right: the selected sequence.
    local detail = CreateFrame("Frame", nil, f)
    detail:SetPoint("TOPLEFT", RIGHT_X, -112)
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

    f.primaryHide = NewCheck(detail, "Hide when on cooldown", function(checked)
        if selSeq then
            selSeq.hideOnCooldown = checked
            Changed()
        end
    end)
    f.primaryHide:SetPoint("LEFT", f.nameBox, "RIGHT", 16, 0)

    local primaryLabel = NewLabel(detail, "Primary")
    primaryLabel:SetPoint("TOPLEFT", 0, -38)
    f.primaryCost = NewLabel(detail, "", "GameFontHighlightSmall")
    f.primaryCost:SetPoint("LEFT", primaryLabel, "RIGHT", 10, 0)
    f.primaryRow = CreateSlotRow(detail, function() return selSeq and selSeq.entries end, true)
    f.primaryRow.frame:SetPoint("TOPLEFT", 0, -56)

    local subsLabel = NewLabel(detail, "Sub-sequences")
    subsLabel:SetPoint("TOPLEFT", 0, -102)

    f.subBlocks = {}
    for i = 1, MAX_SUBS do
        local block = CreateFrame("Frame", nil, detail)
        block:SetSize(520, SLOT_SIZE + 20)
        block:SetPoint("TOPLEFT", 0, -120 - (i - 1) * (SLOT_SIZE + 22))
        block.row = CreateSlotRow(block, function()
            local sub = selSeq and selSeq.subs[i]
            return sub and sub.entries
        end, false)
        block.row.frame:SetPoint("TOPLEFT", 0, -14)
        block.cost = NewLabel(block, "", "GameFontHighlightSmall")
        block.cost:SetPoint("TOPLEFT", 0, 0)
        block.remove = NewButton(block, "Remove", 70, function()
            if selSeq and selSeq.subs[i] then
                table.remove(selSeq.subs, i)
                Changed()
            end
        end)
        block.remove:SetPoint("LEFT", block.row.frame, "LEFT", 6 * (SLOT_SIZE + SLOT_GAP) + 150, 0)
        block.hide = NewCheck(block, "Hide on cooldown", function(checked)
            local sub = selSeq and selSeq.subs[i]
            if sub then
                sub.hideOnCooldown = checked
                Changed()
            end
        end)
        block.hide:SetPoint("BOTTOMLEFT", block.remove, "TOPLEFT", 0, 0)
        f.subBlocks[i] = block
    end

    f.addSub = NewButton(detail, "Add sub-sequence", 140, function()
        if selSeq and #selSeq.subs < MAX_SUBS then
            selSeq.subs[#selSeq.subs + 1] = { entries = {}, hideOnCooldown = false }
            Changed()
        end
    end)

    local hint = NewLabel(detail,
        "Drag spells and items onto a row from the list on the right, your spellbook or your bags. " ..
        "Drag icons to move them, onto another row to copy them, or off the window to remove them. " ..
        "Right-click a spell to change its rank. Sub-sequences are listed dearest first when this opens.",
        "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 0, 4)
    hint:SetPoint("BOTTOMRIGHT", 0, 4)
    hint:SetJustifyH("LEFT")

    f.empty = NewLabel(f, "", "GameFontDisable")
    f.empty:SetPoint("CENTER", detail, "CENTER")

    -- Bottom: options for every window.
    f.click = NewCheck(f, "Click a fixed window's Primary to cast", function(checked)
        ns.SetClickable(checked)
    end)
    f.click:SetPoint("BOTTOMLEFT", LEFT, 22)
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
    f.regen:SetPoint("LEFT", f.click.label, "RIGHT", 24, 1)
    Tooltip(f.regen, "Mana regen during a sequence",
        "Smooth: a steady flow (Forever's regen). 2s ticks: mana in 2-second ticks with the worst timing. " ..
        "Off: ignore regen.")
    local moveHint = NewLabel(f, "While this is open, every window is shown and can be dragged.", "GameFontDisableSmall")
    moveHint:SetPoint("LEFT", f.regen, "RIGHT", 16, 0)

    f.picker = CreatePicker(f)

    function f:Refresh()
        local windows = Windows()
        if selWindow and not IndexOf(windows, selWindow) then
            selWindow, selSeq = nil, nil
        end
        if selSeq and WindowOf(selSeq) ~= selWindow then
            selSeq = nil
        end
        selWindow = selWindow or windows[1]

        local items = ListItems()
        listOffset = math.max(0, math.min(listOffset, #items - VISIBLE_ROWS))
        for i, row in ipairs(self.listRows) do
            local data = items[i + listOffset]
            row.data = data
            if data then
                local isWindow = data.def == nil
                local target = data.def or data.window
                local list = isWindow and windows or data.window.sequences
                local index = IndexOf(list, target)
                row.enabled:ClearAllPoints()
                row.enabled:SetPoint("LEFT", isWindow and 0 or 16, 0)
                row.text:SetPoint("LEFT", row.enabled, "RIGHT", 2, 0)
                row.text:SetFontObject(isWindow and "GameFontNormal" or "GameFontHighlight")
                if isWindow then
                    row.text:SetText((target.name or "?") .. (target.type == "fixed" and " (fixed)" or " (dynamic)"))
                else
                    row.text:SetText(target.name or "?")
                end
                row.enabled:SetChecked(target.enabled and true or false)
                row.selectedTexture:SetShown(target == (selSeq or selWindow) and (isWindow == (selSeq == nil)))
                row.up:SetEnabled(index > 1)
                row.down:SetEnabled(index < #list)
                row:Show()
            else
                row:Hide()
            end
        end
        self.deleteButton:SetEnabled(selWindow ~= nil)

        self.windowPanel:SetShown(selWindow ~= nil)
        if selWindow then
            if not self.windowName:HasFocus() then
                self.windowName:SetText(selWindow.name or "")
            end
            self.windowType:SetText(selWindow.type == "fixed" and "Fixed (click to cast)" or "Dynamic")
            self.onlyInCombat:SetChecked(selWindow.onlyInCombat and true or false)
        end

        local def = selSeq
        self.detail:SetShown(def ~= nil)
        self.empty:SetShown(def == nil)
        self.empty:SetText(selWindow and "Select a sequence, or press New sequence." or
            "Press New window to start.")
        if def then
            if not self.nameBox:HasFocus() then
                self.nameBox:SetText(def.name or "")
            end
            -- Fixed windows always show the Primary, so it has no "hide when on cooldown".
            local canHide = selWindow.type ~= "fixed" and ns.AnyCooldown(def.entries)
            self.primaryHide:SetShown(canHide)
            self.primaryHide:SetChecked(def.hideOnCooldown and true or false)
            self.primaryCost:SetText(CostText(def.entries))
            RefreshSlotRow(self.primaryRow)
            local lastBlock
            for i, block in ipairs(self.subBlocks) do
                local sub = def.subs[i]
                if sub then
                    block.hide:SetShown(ns.AnyCooldown(sub.entries))
                    block.hide:SetChecked(sub.hideOnCooldown and true or false)
                    block.cost:SetText(i .. ". " .. CostText(sub.entries))
                    RefreshSlotRow(block.row)
                    block:Show()
                    lastBlock = block
                else
                    block:Hide()
                end
            end
            self.addSub:ClearAllPoints()
            if lastBlock then
                self.addSub:SetPoint("TOPLEFT", lastBlock, "BOTTOMLEFT", 0, 0)
            else
                self.addSub:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 0, -120)
            end
            self.addSub:SetShown(#def.subs < MAX_SUBS)
        end

        self.click:SetChecked(ns.db.clickable and true or false)
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
            if sub then
                block.cost:SetText(i .. ". " .. CostText(sub.entries))
            end
        end
    end)

    f:SetScript("OnShow", function(self)
        if SortSubs() then
            ns.Rebuild()
        end
        ns.SetEditorOpen(true)
        self:Refresh()
    end)
    f:SetScript("OnHide", function()
        ns.SetEditorOpen(false)
        if drag or listDrag then
            drag, listDrag = nil, nil
            ghost:Hide()
        end
    end)
    f:Hide()
    return f
end

-- Open (show = true) or toggle the editor.
function ns.ToggleEditor(show)
    if not ns.db then
        return
    end
    editor = editor or CreateEditor()
    if show or not editor:IsShown() then
        editor:Show()
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
    "Windows and sequences are set up in their own window. Open it here, with /fseq, or by right-clicking " ..
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
