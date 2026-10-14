-- Forever Sequences editor: build sequences by dragging spells and items into rows.
--
--   - Drag a spell from the spellbook (or an action bar), or an item from your bags, onto a
--     slot. It goes in at that slot; the "+" slot adds it at the end.
--   - Drag an icon within its row to move it, or onto another row to copy it there. An icon
--     dragged from the Primary onto a sub-sequence's "+" slot goes in Primary order.
--   - Drag an icon off the window, or shift-right-click it, to remove it.
--   - Right-click a spell to step down through the ranks you know ("R3" on the icon), and
--     back round to your highest rank.

local _, ns = ...

local MAX_ENTRIES = 8
local MAX_SUBS = 4
local SLOT_SIZE = 34
local SLOT_GAP = 4
local VISIBLE_SEQUENCES = 12
local LIST_ROW_HEIGHT = 24
local LEFT = 20
local RIGHT_X = 240
local REGEN_MODES = { "ticks", "smooth", "off" }
local REGEN_LABELS = { ticks = "Regen: ticks (safe)", smooth = "Regen: smooth", off = "Regen: off" }

local editor
local selected = 1
local listOffset = 0
local drag       -- { entry, row (nil for the potion tile), index }

local function Print(msg)
    ns.Print(msg)
end

local function Sequences()
    return ns.db.sequences
end

local function Selected()
    return Sequences()[selected]
end

local function Changed()
    ns.Rebuild()
    if editor then
        editor:Refresh()
    end
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

----------------------------------------------------------------------------------------------
-- Dragging
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
        if source.row and not editor:IsMouseOver() then
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

local function SlotTooltip(slot)
    local row, index = slot.row, slot.index
    local entry = row.list()[index]
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    if entry then
        local info = ns.ResolveEntry(entry)
        if info.itemID then
            GameTooltip:SetItemByID(info.itemID)
        elseif info.spellID then
            GameTooltip:SetSpellByID(info.spellID)
        else
            GameTooltip:SetText(ns.EntryName(entry))
        end
        if entry.kind == "manapot" then
            GameTooltip:AddLine("Best mana potion: the best one in your bags.", 1, 1, 1, true)
        end
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
        GameTooltip:SetText("Add to this row")
        GameTooltip:AddLine("Drop a spell from your spellbook, an item from your bags, or an icon from another row.",
            1, 1, 1, true)
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

----------------------------------------------------------------------------------------------
-- The window
----------------------------------------------------------------------------------------------

StaticPopupDialogs["FOREVERSEQUENCES_DELETE"] = {
    text = "Delete the sequence \"%s\"?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, index)
        table.remove(Sequences(), index)
        selected = math.max(1, math.min(selected, #Sequences()))
        Changed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function NewSequence()
    local list = Sequences()
    list[#list + 1] = {
        name = "Sequence " .. (#list + 1),
        enabled = true,
        alwaysPrimary = false,
        hideOnCooldown = false,
        entries = {},
        subs = {},
    }
    selected = #list
    if selected > listOffset + VISIBLE_SEQUENCES then
        listOffset = selected - VISIBLE_SEQUENCES
    end
    Changed()
end

local function MoveSequence(index, delta)
    local list = Sequences()
    local other = index + delta
    if other < 1 or other > #list then
        return
    end
    list[index], list[other] = list[other], list[index]
    if selected == index then
        selected = other
    elseif selected == other then
        selected = index
    end
    Changed()
end

local function CreateEditor()
    local f = CreateFrame("Frame", "ForeverSequencesEditor", UIParent, "BackdropTemplate")
    f:SetSize(800, 560)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    tinsert(UISpecialFrames, "ForeverSequencesEditor") -- Escape closes it

    local title = NewLabel(f, "Forever Sequences", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Left: the sequences, in display order.
    local listLabel = NewLabel(f, "Sequences")
    listLabel:SetPoint("TOPLEFT", LEFT, -48)

    local listArea = CreateFrame("Frame", nil, f)
    listArea:SetPoint("TOPLEFT", LEFT, -66)
    listArea:SetSize(RIGHT_X - LEFT - 16, VISIBLE_SEQUENCES * LIST_ROW_HEIGHT)
    listArea:EnableMouseWheel(true)
    listArea:SetScript("OnMouseWheel", function(_, delta)
        local most = math.max(0, #Sequences() - VISIBLE_SEQUENCES)
        listOffset = math.max(0, math.min(most, listOffset - delta))
        f:Refresh()
    end)

    f.listRows = {}
    for i = 1, VISIBLE_SEQUENCES do
        local item = CreateFrame("Button", nil, listArea)
        item:SetSize(listArea:GetWidth(), LIST_ROW_HEIGHT)
        item:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_HEIGHT)
        item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        item.selectedTexture = item:CreateTexture(nil, "BACKGROUND")
        item.selectedTexture:SetAllPoints()
        item.selectedTexture:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        item.selectedTexture:SetBlendMode("ADD")
        item.selectedTexture:SetVertexColor(1, 0.82, 0)

        item.enabled = NewCheck(item, "", function(checked)
            local def = Sequences()[item.index]
            if def then
                def.enabled = checked
                Changed()
            end
        end)
        item.enabled:SetPoint("LEFT", 0, 0)
        item.enabled:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Show on screen")
            GameTooltip:AddLine("Unticked sequences are kept but hidden, and take no space.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        item.enabled:SetScript("OnLeave", function() GameTooltip:Hide() end)

        item.down = NewArrow(item, false, function() MoveSequence(item.index, 1) end)
        item.down:SetPoint("RIGHT", 0, 0)
        item.up = NewArrow(item, true, function() MoveSequence(item.index, -1) end)
        item.up:SetPoint("RIGHT", item.down, "LEFT", 0, 0)

        item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        item.text:SetPoint("LEFT", item.enabled, "RIGHT", 2, 0)
        item.text:SetPoint("RIGHT", item.up, "LEFT", -2, 0)
        item.text:SetJustifyH("LEFT")
        item.text:SetWordWrap(false)

        item:SetScript("OnClick", function(self)
            selected = self.index
            f:Refresh()
        end)
        f.listRows[i] = item
    end

    local newButton = NewButton(f, "New", 80, NewSequence)
    newButton:SetPoint("TOPLEFT", listArea, "BOTTOMLEFT", 0, -8)
    local deleteButton = NewButton(f, "Delete", 80, function()
        local def = Selected()
        if def then
            local popup = StaticPopup_Show("FOREVERSEQUENCES_DELETE", def.name or "?")
            if popup then
                popup.data = selected
            end
        end
    end)
    deleteButton:SetPoint("LEFT", newButton, "RIGHT", 6, 0)
    f.deleteButton = deleteButton

    -- Right: the selected sequence.
    local detail = CreateFrame("Frame", nil, f)
    detail:SetPoint("TOPLEFT", RIGHT_X, -44)
    detail:SetPoint("BOTTOMRIGHT", -20, 60)
    f.detail = detail

    local nameLabel = NewLabel(detail, "Name")
    nameLabel:SetPoint("TOPLEFT", 0, -6)
    local nameBox = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
    nameBox:SetSize(220, 20)
    nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(40)
    local function SaveName(self)
        local def = Selected()
        local text = self:GetText()
        if def and text ~= "" and text ~= def.name then
            def.name = text
            Changed()
        end
    end
    nameBox:SetScript("OnEnterPressed", function(self)
        SaveName(self)
        self:ClearFocus()
    end)
    nameBox:SetScript("OnEditFocusLost", SaveName)
    nameBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        f:Refresh()
    end)
    f.nameBox = nameBox

    f.alwaysPrimary = NewCheck(detail, "Always show Primary (and click it to cast)", function(checked)
        local def = Selected()
        if def then
            def.alwaysPrimary = checked
            Changed()
        end
    end)
    f.alwaysPrimary:SetPoint("TOPLEFT", 0, -32)
    f.primaryHide = NewCheck(detail, "Hide when on cooldown", function(checked)
        local def = Selected()
        if def then
            def.hideOnCooldown = checked
            Changed()
        end
    end)
    f.primaryHide:SetPoint("TOPLEFT", 300, -32)

    local primaryLabel = NewLabel(detail, "Primary")
    primaryLabel:SetPoint("TOPLEFT", 0, -66)
    f.primaryRow = CreateSlotRow(detail, function()
        local def = Selected()
        return def and def.entries
    end, true)
    f.primaryRow.frame:SetPoint("TOPLEFT", 0, -84)

    local subsLabel = NewLabel(detail, "Sub-sequences")
    subsLabel:SetPoint("TOPLEFT", 0, -132)

    f.subBlocks = {}
    for i = 1, MAX_SUBS do
        local block = CreateFrame("Frame", nil, detail)
        block:SetSize(520, SLOT_SIZE + 8)
        block:SetPoint("TOPLEFT", 0, -150 - (i - 1) * (SLOT_SIZE + 10))
        block.row = CreateSlotRow(block, function()
            local def = Selected()
            local sub = def and def.subs[i]
            return sub and sub.entries
        end, false)
        block.row.frame:SetPoint("TOPLEFT", 0, 0)
        block.hide = NewCheck(block, "Hide on cooldown", function(checked)
            local def = Selected()
            local sub = def and def.subs[i]
            if sub then
                sub.hideOnCooldown = checked
                Changed()
            end
        end)
        block.hide:SetPoint("LEFT", block.row.frame, "RIGHT", 4, 0)
        block.remove = NewButton(block, "Remove", 70, function()
            local def = Selected()
            if def and def.subs[i] then
                table.remove(def.subs, i)
                Changed()
            end
        end)
        block.remove:SetPoint("LEFT", block.hide.label, "RIGHT", 10, 0)
        f.subBlocks[i] = block
    end

    f.addSub = NewButton(detail, "Add sub-sequence", 140, function()
        local def = Selected()
        if def and #def.subs < MAX_SUBS then
            def.subs[#def.subs + 1] = { entries = {}, hideOnCooldown = false }
            Changed()
        end
    end)

    -- A tile to drag "best mana potion" into any row.
    local potionLabel = NewLabel(detail, "Drag into a row:", "GameFontHighlightSmall")
    potionLabel:SetPoint("BOTTOMLEFT", 0, 44)
    local potion = CreateFrame("Button", nil, detail)
    potion:SetSize(SLOT_SIZE, SLOT_SIZE)
    potion:SetPoint("LEFT", potionLabel, "RIGHT", 8, 0)
    local potionIcon = potion:CreateTexture(nil, "ARTWORK")
    potionIcon:SetAllPoints()
    potionIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    potion:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    potion:RegisterForDrag("LeftButton")
    potion:SetScript("OnDragStart", function()
        StartDrag({ kind = "manapot" })
    end)
    potion:SetScript("OnDragStop", FinishDrag)
    potion:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Best mana potion")
        GameTooltip:AddLine("Uses the best mana potion in your bags, and counts its lowest restore.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    potion:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.potionIcon = potionIcon
    local potionName = NewLabel(detail, "Best mana potion", "GameFontHighlightSmall")
    potionName:SetPoint("LEFT", potion, "RIGHT", 8, 0)

    local hint = NewLabel(detail,
        "Drag spells from your spellbook or items from your bags onto a row. Drag icons to move them, " ..
        "onto another row to copy them, or off the window to remove them. Right-click a spell to change its rank.",
        "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 0, 4)
    hint:SetPoint("BOTTOMRIGHT", 0, 4)
    hint:SetJustifyH("LEFT")

    f.empty = NewLabel(f, "No sequences yet. Press New to make one.", "GameFontDisable")
    f.empty:SetPoint("CENTER", detail, "CENTER")

    -- Bottom: display options.
    f.lock = NewCheck(f, "Lock display", function(checked)
        ns.db.locked = checked
        ns.ApplyLock()
    end)
    f.lock:SetPoint("BOTTOMLEFT", LEFT, 22)
    f.click = NewCheck(f, "Click always-shown Primary to cast", function(checked)
        ns.SetClickable(checked)
    end)
    f.click:SetPoint("LEFT", f.lock.label, "RIGHT", 24, -1)
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
    f.regen:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Mana regen during a sequence")
        GameTooltip:AddLine("Ticks: mana comes in 2-second ticks; assumes the worst timing, so never too early.", 1, 1, 1, true)
        GameTooltip:AddLine("Smooth: a steady flow. Off: ignore regen.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.regen:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function f:Refresh()
        local list = Sequences()
        selected = math.max(1, math.min(selected, #list))
        listOffset = math.max(0, math.min(listOffset, #list - VISIBLE_SEQUENCES))
        for i, item in ipairs(self.listRows) do
            local index = i + listOffset
            local def = list[index]
            item.index = index
            if def then
                item.text:SetText(def.name or "?")
                item.enabled:SetChecked(def.enabled and true or false)
                item.selectedTexture:SetShown(index == selected)
                item.up:SetEnabled(index > 1)
                item.down:SetEnabled(index < #list)
                item:Show()
            else
                item:Hide()
            end
        end
        self.deleteButton:SetEnabled(#list > 0)

        local def = Selected()
        self.detail:SetShown(def ~= nil)
        self.empty:SetShown(def == nil)
        if def then
            if not self.nameBox:HasFocus() then
                self.nameBox:SetText(def.name or "")
            end
            self.alwaysPrimary:SetChecked(def.alwaysPrimary and true or false)
            self.primaryHide:SetChecked(def.hideOnCooldown and true or false)
            RefreshSlotRow(self.primaryRow)
            local lastBlock
            for i, block in ipairs(self.subBlocks) do
                local sub = def.subs[i]
                if sub then
                    block.hide:SetChecked(sub.hideOnCooldown and true or false)
                    RefreshSlotRow(block.row)
                    block:Show()
                    lastBlock = block
                else
                    block:Hide()
                end
            end
            self.addSub:ClearAllPoints()
            if lastBlock then
                self.addSub:SetPoint("TOPLEFT", lastBlock, "BOTTOMLEFT", 0, -2)
            else
                self.addSub:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 0, -150)
            end
            self.addSub:SetShown(#def.subs < MAX_SUBS)
            self.potionIcon:SetTexture(ns.ResolveEntry({ kind = "manapot" }).icon)
        end

        self.lock:SetChecked(ns.db.locked and true or false)
        self.click:SetChecked(ns.db.clickable and true or false)
        self.regen:SetText(REGEN_LABELS[ns.db.regenMode] or ns.db.regenMode)
    end

    f:SetScript("OnShow", f.Refresh)
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
    "Sequences are set up in their own window. Open it here, with /fseq, or by right-clicking the display.",
    "GameFontHighlight")
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
