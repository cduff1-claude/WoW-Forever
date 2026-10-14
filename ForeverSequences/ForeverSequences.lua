-- Forever Sequences: rows of spell icons. Each icon fills with colour (left to right) as you
-- gain the mana to cast it after everything before it in the row.
--
-- A sequence is a Primary row plus optional sub-sequences. Only one of them shows in the
-- sequence's row, chosen by how much mana you have; with "always show Primary" the Primary
-- keeps its row (and can be clicked to cast) and the best sub-sequence shows below it.
--
-- Player mana is a secret value on Forever, so Lua never compares it. Every comparison is
-- done by StatusBars (which accept secret values) and frames that clip to their fill edges:
--
-- "Mana needed" for a spell counts what happens before its cost is taken, if you start the
-- sequence now: cast and channel times, the global cooldown, regen and the 5-second rule,
-- mana restored by potions and the like, instant-cast effects (Nature's Swiftness) and
-- Clearcasting.
--
--   fill bar   : range [mana needed before this spell, mana needed up to and including it],
--                value = current mana. Its fill edge is how far the colour icon is revealed.
--   now switch : range [total - 1, total], value = current mana. Empty or full width.
--   prev switch: the same, but its value is the mana reading from FLASH_HOLD seconds ago.
--   highlight  : clipped to "now full" and "prev empty", so it shows for FLASH_HOLD seconds
--                after the mana for this spell arrives, then disappears by itself.
--   band       : every candidate row of a sequence sits in the same place, clipped to
--                "mana >= low" and "mana < high". The bands don't overlap, so one row shows.

local ADDON_NAME, ns = ...

local MANA_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

local ICON_SIZE = 36
local SUB_ICON_SIZE = 28     -- the sub-sequence row under an always-shown Primary
local SUB_INDENT = 14
local ICON_GAP = 4
local ROW_GAP = 6
local PADDING = 6
local GLOW_SIZE = 3          -- highlight border width, drawn just outside the icon
local FLASH_HOLD = 2.0       -- seconds the highlight stays after a spell becomes affordable
local TICK = 0.05            -- how often mana is re-read
local REFRESH = 1.0          -- how often spell data, cooldowns and auras are re-read
local TEST_SWEEP_TIME = 15   -- seconds for /fseq test to sweep from no mana to full
local FIVE_SECOND_RULE = 5.0 -- seconds of reduced regen after spending mana
local GLOBAL_COOLDOWN = 1.5  -- used when the game won't say a spell's global cooldown
local REGEN_TICK = 2.0       -- seconds between mana ticks in "ticks" regen mode
local TICK_PHASE_STEPS = 20  -- tick timings tried when working out the worst case
local INSTANT_LIMIT = 10     -- "instant cast" effects work on casts shorter than this
local FAKE_COOLDOWN = 10     -- seconds, for /fseq cdtest
local NEVER = 1e9            -- a mana value no one reaches

local GREY_SHADE = 0.5
local GLOW_COLOR = { 1.0, 0.85, 0.2 }
local POTION_ICON = 134853   -- a generic blue potion, for "best mana potion" with none in bags

-- The Clearcasting buff (Omen of Clarity) makes the next spell that uses it free. These
-- don't use it, so it carries on to the next spell. Forms and items never use it either.
local CLEARCASTING = "Clearcasting"
local CLEARCASTING_IGNORES = {
    ["Wrath"] = true,
}

-- Forms, cast as "/cast !Form" so clicking them never shifts you back out. The stance bar
-- adds whatever forms you know; this list covers them before they're learned.
local FORM_NAMES = {
    ["Bear Form"] = true,
    ["Dire Bear Form"] = true,
    ["Cat Form"] = true,
    ["Travel Form"] = true,
    ["Aquatic Form"] = true,
    ["Moonkin Form"] = true,
}

-- Spells that are replaced by another once learned (the spellbook then only lists the new one).
local REPLACED_BY = {
    ["Bear Form"] = "Dire Bear Form",
}

local function Spell(name, rank)
    return { kind = "spell", name = name, rank = rank }
end

-- Starting sequences, until you make your own in the editor.
local DEFAULT_SEQUENCES = {
    {
        name = "Bear out",
        enabled = true,
        alwaysPrimary = false,
        hideOnCooldown = false,
        entries = { Spell("Regrowth"), Spell("Rejuvenation"), Spell("Bear Form") },
        subs = {
            { entries = { Spell("Regrowth"), Spell("Bear Form") }, hideOnCooldown = false },
            { entries = { Spell("Rejuvenation"), Spell("Bear Form") }, hideOnCooldown = false },
        },
    },
    {
        name = "Root and run",
        enabled = true,
        alwaysPrimary = true,
        hideOnCooldown = false,
        entries = { Spell("Entangling Roots"), Spell("Rejuvenation"), Spell("Travel Form") },
        subs = {
            { entries = { Spell("Entangling Roots"), Spell("Travel Form") }, hideOnCooldown = false },
        },
    },
}

ForeverSequencesDB = ForeverSequencesDB or {}
local db = ForeverSequencesDB

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -150,
    locked = false,
    regenMode = "ticks", -- "ticks" (safe: worst-case tick timing), "smooth" or "off"
    clickable = true,    -- click an always-shown Primary to cast
}

local function CopyTable(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = type(v) == "table" and CopyTable(v) or v
    end
    return copy
end
ns.CopyTable = CopyTable

-- Sequences saved by the first prototype held spell names in `spells`.
local function MigrateSequences(list)
    local function Convert(def)
        if def.spells and not def.entries then
            def.entries = {}
            for _, name in ipairs(def.spells) do
                def.entries[#def.entries + 1] = Spell(name)
            end
            def.spells = nil
        end
        def.entries = def.entries or {}
    end
    for _, def in ipairs(list) do
        Convert(def)
        def.subs = def.subs or {}
        for _, sub in ipairs(def.subs) do
            Convert(sub)
        end
    end
end

local function Print(msg)
    print("|cff66ccffForever Sequences:|r " .. msg)
end
ns.Print = Print

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function IsReadableNumber(value)
    return value ~= nil and not IsSecret(value) and type(value) == "number"
end

-- A readable, non-empty string, or nil.
local function Text(value)
    if value ~= nil and not IsSecret(value) and type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

local function Describe(value)
    if IsSecret(value) then
        return "secret"
    end
    return tostring(value)
end

----------------------------------------------------------------------------------------------
-- Spellbook: every rank of every spell you know
----------------------------------------------------------------------------------------------

local BOOK_BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local spellbook = {}   -- name -> { ranks = { [rank] = spellID }, maxRank = n, maxID = id }
local rankOfSpell = {} -- spellID -> rank (0 for spells without ranks)
local formSpells = {}  -- spellID -> true, from the stance bar

local function ScanSpellbook()
    wipe(spellbook)
    wipe(rankOfSpell)
    local book = C_SpellBook
    if book and book.GetNumSpellBookSkillLines then
        local futureType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
        for line = 1, book.GetNumSpellBookSkillLines() or 0 do
            local info = book.GetSpellBookSkillLineInfo(line)
            if info and not info.shouldHide then
                local first = (info.itemIndexOffset or 0) + 1
                local last = (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0)
                for index = first, last do
                    local okType, itemType = pcall(book.GetSpellBookItemType, index, BOOK_BANK)
                    local item = book.GetSpellBookItemInfo(index, BOOK_BANK)
                    local name = item and Text(item.name)
                    local spellID = item and (item.spellID or item.actionID)
                    if name and IsReadableNumber(spellID) and not item.isPassive
                        and not (okType and futureType and itemType == futureType) then
                        local rank = tonumber((Text(item.subName) or ""):match("(%d+)")) or 0
                        local entry = spellbook[name]
                        if not entry then
                            entry = { ranks = {}, maxRank = -1 }
                            spellbook[name] = entry
                        end
                        entry.ranks[rank] = spellID
                        rankOfSpell[spellID] = rank
                        if rank > entry.maxRank then
                            entry.maxRank, entry.maxID = rank, spellID
                        end
                    end
                end
            end
        end
    end

    wipe(formSpells)
    if GetNumShapeshiftForms and GetShapeshiftFormInfo then
        for i = 1, GetNumShapeshiftForms() or 0 do
            local _, _, _, spellID = GetShapeshiftFormInfo(i)
            if IsReadableNumber(spellID) then
                formSpells[spellID] = true
            end
        end
    end
end

local function SpellNameOf(spellID)
    if spellID and C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok then
            return Text(name)
        end
    end
    return nil
end

local function BookEntry(name)
    return spellbook[name] or (REPLACED_BY[name] and spellbook[REPLACED_BY[name]])
end

-- Every rank you know of a spell, lowest first, for the editor.
function ns.KnownRanks(name)
    local entry = BookEntry(name)
    local list = {}
    if entry then
        for rank in pairs(entry.ranks) do
            if rank > 0 then
                list[#list + 1] = rank
            end
        end
        table.sort(list)
    end
    return list
end

-- spellID, rank used, highest rank known (nil when unranked or unknown), known.
local function ResolveSpell(name, pinnedRank)
    local entry = BookEntry(name)
    if entry then
        if pinnedRank and entry.ranks[pinnedRank] then
            return entry.ranks[pinnedRank], pinnedRank, entry.maxRank, true
        end
        return entry.maxID, entry.maxRank, entry.maxRank, true
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and type(info) == "table" and IsReadableNumber(info.spellID) then
            return info.spellID, nil, nil, false
        end
    end
    return nil, nil, nil, false
end

local function IsForm(name, spellID)
    return (spellID and formSpells[spellID]) or FORM_NAMES[name] or false
end

----------------------------------------------------------------------------------------------
-- Spell and item data
----------------------------------------------------------------------------------------------

-- The spell's mana cost after talents and gear (0 when free), or nil if unreadable.
local function GetManaCost(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellPowerCost) then
        return nil
    end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then
        return nil
    end
    for _, info in ipairs(costs) do
        local isMana = false
        if info.type ~= nil and not IsSecret(info.type) then
            isMana = info.type == MANA_POWER_TYPE
        end
        if not isMana and info.name ~= nil and not IsSecret(info.name) then
            isMana = info.name == "MANA"
        end
        if isMana and IsReadableNumber(info.cost) then
            return info.cost
        end
    end
    return 0
end

-- Cast time in seconds (0 for instants), or nil if unreadable.
local function GetCastTime(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellInfo) then
        return nil
    end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if ok and type(info) == "table" and IsReadableNumber(info.castTime) then
        return math.max(0, info.castTime) / 1000
    end
    return nil
end

-- Global cooldown the spell triggers, in seconds (0 when off the global cooldown), or nil.
local function GetGlobalCooldown(spellID)
    local fn = (C_Spell and C_Spell.GetSpellBaseCooldown) or GetSpellBaseCooldown
    if not (spellID and fn) then
        return nil
    end
    local ok, _, gcdMS = pcall(fn, spellID)
    if ok and IsReadableNumber(gcdMS) then
        return gcdMS / 1000
    end
    return nil
end

local function GetDescription(spellID)
    if spellID and C_Spell and C_Spell.GetSpellDescription then
        local ok, text = pcall(C_Spell.GetSpellDescription, spellID)
        if ok then
            return Text(text)
        end
    end
    return nil
end

-- Whether the spell's tooltip says "Channeled".
local function IsChanneled(spellID)
    if not (spellID and C_TooltipInfo and C_TooltipInfo.GetSpellByID) then
        return false
    end
    local ok, data = pcall(C_TooltipInfo.GetSpellByID, spellID)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
        return false
    end
    for _, line in ipairs(data.lines) do
        local left, right = Text(line.leftText), Text(line.rightText)
        if (left and left:find("Channeled")) or (right and right:find("Channeled")) then
            return true
        end
    end
    return false
end

local function Number(text)
    return text and tonumber((text:gsub(",", ""))) or nil
end

-- What a description says about mana: instant amount, or amount and seconds for "over N sec".
-- Uses the low end of "X to Y", so the sequence is never shown as affordable too early.
local function ParseManaGain(description)
    if not description then
        return nil
    end
    local text = description:gsub("\r?\n", " ")
    local low = text:match("[Rr]estores ([%d,]+) to [%d,]+ mana") or text:match("[Rr]estores ([%d,]+) mana")
    local amount = Number(low)
    if not amount then
        return nil
    end
    local over = Number(text:match("[Rr]estores [^%.]-mana over ([%d%.]+) sec"))
    return amount, over
end

local function ChannelTime(spellID, description)
    if not (description and IsChanneled(spellID)) then
        return 0
    end
    return Number(description:match("over ([%d%.]+) sec")) or 0
end

local function MakesNextInstant(description)
    return description ~= nil and description:find("becomes an instant cast") ~= nil
end

local function GetItemUseSpell(itemID)
    if not (itemID and C_Item and C_Item.GetItemSpell) then
        return nil
    end
    local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
    if ok and IsReadableNumber(spellID) then
        return spellID
    end
    return nil
end

local function GetItemIcon(itemID)
    if itemID and C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon then
            return icon
        end
    end
    return 134400
end

local function GetSpellIcon(spellID)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and icon then
            return icon
        end
    end
    return 134400 -- question mark
end

----------------------------------------------------------------------------------------------
-- Bags: counts, and mana potions best first
----------------------------------------------------------------------------------------------

local bagCounts = {}
local manaPotions = {} -- { itemID, gain }, most mana first
local POTION_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local POTION_SUBCLASS = 1 -- Consumable > Potion

local function ScanBags()
    wipe(bagCounts)
    wipe(manaPotions)
    if not (C_Container and C_Container.GetContainerNumSlots) then
        return
    end
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID
            if IsReadableNumber(itemID) then
                bagCounts[itemID] = (bagCounts[itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    for itemID in pairs(bagCounts) do
        local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, itemID)
        if ok and classID == POTION_CLASS and subclassID == POTION_SUBCLASS then
            local spellID = GetItemUseSpell(itemID)
            local gain, over = ParseManaGain(GetDescription(spellID))
            if gain and not over then
                manaPotions[#manaPotions + 1] = { itemID = itemID, gain = gain }
            end
        end
    end
    table.sort(manaPotions, function(a, b)
        if a.gain ~= b.gain then
            return a.gain > b.gain
        end
        return a.itemID < b.itemID
    end)
end

-- What an entry is right now: kind, spellID (an item's use spell), itemID, icon, the rank used
-- and the highest known, and whether you have it (known spell / item in bags).
local function ResolveEntry(entry)
    local info = { kind = entry.kind }
    if entry.kind == "spell" then
        info.spellID, info.rank, info.maxRank, info.known = ResolveSpell(entry.name, entry.rank)
        info.name = entry.name
        info.icon = GetSpellIcon(info.spellID)
        info.available = true
    elseif entry.kind == "item" then
        info.itemID = entry.itemID
        info.spellID = GetItemUseSpell(entry.itemID)
        info.icon = GetItemIcon(entry.itemID)
        info.available = (bagCounts[entry.itemID] or 0) > 0 or (C_Item and C_Item.GetItemCount
            and (C_Item.GetItemCount(entry.itemID) or 0) > 0) or false
    elseif entry.kind == "manapot" then
        local best = manaPotions[1]
        info.itemID = best and best.itemID
        info.spellID = best and GetItemUseSpell(best.itemID)
        info.icon = best and GetItemIcon(best.itemID) or POTION_ICON
        info.available = best ~= nil
    end
    return info
end
ns.ResolveEntry = ResolveEntry

-- The rank label for an icon: "R3" when a lower rank than your best is pinned.
function ns.RankText(info)
    if info.kind == "spell" and info.rank and info.maxRank and info.rank > 0 and info.rank < info.maxRank then
        return "R" .. info.rank
    end
    return nil
end

-- What's on the cursor as an entry: a spell (from the spellbook or an action bar) or an item.
-- A spell dragged at its highest rank follows your highest rank; a lower rank is pinned.
function ns.EntryFromCursor()
    local kind, first, _, spellID = GetCursorInfo()
    if IsSecret(kind) or kind == nil then
        return nil
    end
    if kind == "spell" and IsReadableNumber(spellID) then
        local name = SpellNameOf(spellID)
        if not name then
            return nil, "can't read that spell."
        end
        local rank = rankOfSpell[spellID]
        local entry = BookEntry(name)
        if rank and entry and rank > 0 and rank < entry.maxRank then
            return Spell(name, rank)
        end
        return Spell(name)
    elseif kind == "item" and IsReadableNumber(first) then
        if not GetItemUseSpell(first) then
            return nil, "that item has no use effect."
        end
        return { kind = "item", itemID = first }
    end
    return nil, "only spells and usable items can go in a sequence."
end

function ns.EntryName(entry)
    if entry.kind == "spell" then
        return entry.rank and (entry.name .. " (Rank " .. entry.rank .. ")") or entry.name
    elseif entry.kind == "manapot" then
        return "Best mana potion"
    elseif entry.kind == "item" then
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.itemID)
        return Text(name) or ("item " .. tostring(entry.itemID))
    end
    return "?"
end

-- The same entry? (Used for dragging from the Primary into a sub-sequence.)
function ns.SameEntry(a, b)
    return a.kind == b.kind and a.name == b.name and a.rank == b.rank and a.itemID == b.itemID
end

----------------------------------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------------------------------

local root = CreateFrame("Frame", "ForeverSequencesFrame", UIParent)
root:SetSize(100, 50)
root:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.relativePoint, DEFAULTS.x, DEFAULTS.y)
root:SetMovable(true)
root:SetClampedToScreen(true)

-- While unlocked, a cover over the whole display takes the drags (and clicks, so nothing is
-- cast while moving it). Right-click opens the options.
local mover = CreateFrame("Frame", nil, root, "BackdropTemplate")
mover:SetAllPoints(root)
mover:SetFrameStrata("DIALOG")
mover:EnableMouse(true)
mover:RegisterForDrag("LeftButton")
mover:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
mover:SetBackdropColor(0.1, 0.3, 0.5, 0.35)
mover:SetBackdropBorderColor(0.4, 0.8, 1, 0.9)

local moverLabel = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
moverLabel:SetPoint("BOTTOM", mover, "TOP", 0, 2)
moverLabel:SetText("Forever Sequences: drag to move, right-click for options")

local function SavePosition()
    local point, _, relativePoint, x, y = root:GetPoint(1)
    db.point, db.relativePoint, db.x, db.y = point, relativePoint, x, y
end

local function OpenOptions()
    if ns.ToggleEditor then
        ns.ToggleEditor(true)
    end
end

mover:SetScript("OnDragStart", function()
    -- The display may hold secure buttons, so it can't move in combat.
    if not InCombatLockdown() then
        root:StartMoving()
    end
end)
mover:SetScript("OnDragStop", function()
    root:StopMovingOrSizing()
    SavePosition()
end)
mover:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        OpenOptions()
    end
end)

function ns.ApplyLock()
    mover:SetShown(not db.locked)
end

local function ApplyPosition()
    root:ClearAllPoints()
    root:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
end

local function NewFrame(frameType, parent)
    local frame = CreateFrame(frameType, nil, parent)
    frame:SetFrameLevel(parent:GetFrameLevel() + 1)
    return frame
end

-- An invisible StatusBar covering `area`, used only for its fill edge.
local function NewSwitch(parent, area)
    local bar = NewFrame("StatusBar", parent)
    bar:SetAllPoints(area)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

-- Point a binary switch at a mana value: full from `at` upwards. +-math.huge allowed.
local function SetSwitchAt(switch, at)
    if at == -math.huge then
        switch:SetMinMaxValues(-2, -1)
    elseif at >= NEVER then
        switch:SetMinMaxValues(NEVER - 1, NEVER)
    else
        switch:SetMinMaxValues(at - 1, at)
    end
end

-- A frame clipping its children to the span from left's leftPoint to right's rightPoint.
local function NewClip(parent, left, leftPoint, right, rightPoint)
    local clip = NewFrame("Frame", parent)
    clip:SetClipsChildren(true)
    clip:SetPoint("TOPLEFT", left, "TOP" .. leftPoint, 0, 0)
    clip:SetPoint("BOTTOMRIGHT", right, "BOTTOM" .. rightPoint, 0, 0)
    return clip
end

local function NewIconTexture(frame, layer, area)
    local texture = frame:CreateTexture(nil, layer)
    texture:SetAllPoints(area)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    return texture
end

----------------------------------------------------------------------------------------------
-- Clicking (always-shown Primary only: those buttons never move or swap)
----------------------------------------------------------------------------------------------

local buttonCount = 0
local pendingActions = false -- secure changes waiting for the end of combat

local function SetPassThrough(frame, ...)
    if frame.SetPassThroughButtons then
        pcall(frame.SetPassThroughButtons, frame, ...)
    end
end

-- What a left click does. Secure attributes can only change out of combat.
local function ApplyAction(cell)
    if not cell.secure then
        return
    end
    if InCombatLockdown() then
        pendingActions = true
        return
    end
    local info = cell.info
    local entry = cell.entry
    local spellName = info.kind == "spell" and SpellNameOf(info.spellID)
    cell:SetAttribute("spell", nil)
    cell:SetAttribute("item", nil)
    cell:SetAttribute("macrotext", nil)
    if info.kind == "spell" and spellName and IsForm(entry.name, info.spellID) then
        cell:SetAttribute("type", "macro")
        cell:SetAttribute("macrotext", "/cast !" .. spellName)
    elseif info.kind == "spell" then
        cell:SetAttribute("type", "spell")
        cell:SetAttribute("spell", info.spellID)
    elseif info.kind == "item" then
        cell:SetAttribute("type", "item")
        cell:SetAttribute("item", "item:" .. entry.itemID)
    elseif info.kind == "manapot" then
        -- Every mana potion in your bags, best first: the first one you have is used, and the
        -- shared potion cooldown stops the rest.
        local lines = {}
        for _, potion in ipairs(manaPotions) do
            lines[#lines + 1] = "/use item:" .. potion.itemID
        end
        cell:SetAttribute("type", "macro")
        cell:SetAttribute("macrotext", table.concat(lines, "\n"))
    end
    -- Left clicks pass through when clicking is off; right-click still opens the options.
    if db.clickable then
        SetPassThrough(cell)
    else
        SetPassThrough(cell, "LeftButton")
    end
end

----------------------------------------------------------------------------------------------
-- Display
----------------------------------------------------------------------------------------------

local function ShowTooltip(cell)
    local info = cell.info
    if not info then
        return
    end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    if info.itemID then
        GameTooltip:SetItemByID(info.itemID)
    elseif info.spellID then
        GameTooltip:SetSpellByID(info.spellID)
    else
        GameTooltip:SetText(ns.EntryName(cell.entry))
    end
    GameTooltip:AddLine("Right-click: options", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- secure: a click-to-cast button (always-shown Primary). Otherwise a plain frame that only
-- takes right-clicks; left clicks go through it.
local function CreateCell(row, index, size, secure)
    local cell
    if secure then
        buttonCount = buttonCount + 1
        cell = CreateFrame("Button", "ForeverSequencesButton" .. buttonCount, row.frame, "SecureActionButtonTemplate")
        cell:SetFrameLevel(row.frame:GetFrameLevel() + 1)
        cell:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
        cell:HookScript("OnEnter", ShowTooltip)
        cell:HookScript("OnLeave", function() GameTooltip:Hide() end)
    else
        cell = NewFrame("Frame", row.frame)
        cell:EnableMouse(true)
        SetPassThrough(cell, "LeftButton")
    end
    cell.secure = secure
    cell:SetSize(size, size)
    cell:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (index - 1) * (size + ICON_GAP), 0)
    cell:HookScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            OpenOptions()
        end
    end)
    local level = cell:GetFrameLevel()

    local edge = cell:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", cell, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0, 0, 0, 1)

    -- Grey icon underneath; the colour icon on top is revealed by the fill bar's edge.
    local grey = NewIconTexture(cell, "ARTWORK", cell)
    grey:SetDesaturated(true)
    grey:SetVertexColor(GREY_SHADE, GREY_SHADE, GREY_SHADE)

    local fill = NewSwitch(cell, cell)
    local colorClip = NewClip(cell, fill, "LEFT", fill:GetStatusBarTexture(), "RIGHT")
    local colorHolder = NewFrame("Frame", colorClip)
    colorHolder:SetAllPoints(cell)
    local color = NewIconTexture(colorHolder, "ARTWORK", cell)

    -- Blizzard's cooldown swipe and countdown, over the icon.
    local cooldown = CreateFrame("Cooldown", nil, cell, "CooldownFrameTemplate")
    cooldown:SetAllPoints(cell)
    cooldown:SetFrameLevel(level + 3)
    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(false)
    end

    -- Highlight: shown only while "enough now" and "not enough FLASH_HOLD seconds ago".
    local glowArea = NewFrame("Frame", cell)
    glowArea:SetPoint("TOPLEFT", cell, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    glowArea:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
    local nowSwitch = NewSwitch(cell, glowArea)
    local prevSwitch = NewSwitch(cell, glowArea)
    local enoughNow = NewClip(cell, nowSwitch, "LEFT", nowSwitch:GetStatusBarTexture(), "RIGHT")
    local fresh = NewClip(enoughNow, prevSwitch:GetStatusBarTexture(), "RIGHT", prevSwitch, "RIGHT")
    fresh:SetFrameLevel(level + 4)
    local glow = NewFrame("Frame", fresh)
    glow:SetAllPoints(glowArea)

    local r, g, b = GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3]
    local function Edge(p1, p2, w, h)
        local t = glow:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, 1)
        t:SetPoint(p1, glowArea, p1, 0, 0)
        t:SetPoint(p2, glowArea, p2, 0, 0)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, GLOW_SIZE)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, GLOW_SIZE)
    Edge("TOPLEFT", "BOTTOMLEFT", GLOW_SIZE, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", GLOW_SIZE, nil)

    local flash = glow:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints(cell)
    flash:SetColorTexture(r, g, b, 0.35)
    flash:SetBlendMode("ADD")

    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(0.35)
    pulse:Play()

    -- Rank label ("R3") for a pinned lower rank, on top of everything.
    local top = NewFrame("Frame", cell)
    top:SetAllPoints(cell)
    top:SetFrameLevel(level + 6)
    local rankText = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    rankText:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 2)

    cell.grey = grey
    cell.color = color
    cell.colorClip = colorClip
    cell.fresh = fresh
    cell.fill = fill
    cell.cooldown = cooldown
    cell.nowSwitch = nowSwitch
    cell.prevSwitch = prevSwitch
    cell.rankText = rankText
    cell.start = 0
    cell.total = 0
    return cell
end

local groups = {}
local rows = {}       -- every candidate row of every group, for the threshold maths
local oldLines = {}   -- frames from earlier builds, hidden

local function LineWidth(cellCount, size)
    return cellCount * size + math.max(0, cellCount - 1) * ICON_GAP + GLOW_SIZE * 2
end

-- One row of icons inside `parent`, placed at the top left of `line`.
local function CreateRow(group, parent, line, def, size, label, secure)
    local rowFrame = NewFrame("Frame", parent)
    rowFrame:SetPoint("TOPLEFT", line, "TOPLEFT", GLOW_SIZE, -GLOW_SIZE)
    rowFrame:SetSize(math.max(1, LineWidth(#def.entries, size) - GLOW_SIZE * 2), size)
    local row = { frame = rowFrame, group = group, def = def, label = label, cells = {}, total = 0 }
    for i, entry in ipairs(def.entries) do
        local cell = CreateCell(row, i, size, secure)
        cell.entry = entry
        row.cells[i] = cell
    end
    rows[#rows + 1] = row
    return row
end

-- A row that only shows while mana is inside its band.
local function CreateBandedRow(group, line, def, size, label)
    local low = NewSwitch(line, line)
    local high = NewSwitch(line, line)
    local aboveLow = NewClip(line, low, "LEFT", low:GetStatusBarTexture(), "RIGHT")
    local belowHigh = NewClip(aboveLow, high:GetStatusBarTexture(), "RIGHT", high, "RIGHT")
    local row = CreateRow(group, belowHigh, line, def, size, label, false)
    row.low, row.high = low, high
    return row
end

local function NewLine(width, height, x, y)
    local line = NewFrame("Frame", root)
    line:SetSize(width, height)
    line:SetPoint("TOPLEFT", root, "TOPLEFT", x, y)
    oldLines[#oldLines + 1] = line
    return line
end

local function MostEntries(list)
    local most = 0
    for _, def in ipairs(list) do
        most = math.max(most, #def.entries)
    end
    return most
end

local function BuildDisplay()
    for _, line in ipairs(oldLines) do
        line:Hide()
    end
    wipe(oldLines)
    wipe(groups)
    wipe(rows)

    local y = -PADDING
    local width = 0
    for _, def in ipairs(db.sequences) do
        local subs = {}
        for _, sub in ipairs(def.subs) do
            if #sub.entries > 0 then
                subs[#subs + 1] = sub
            end
        end
        if def.enabled and (#def.entries > 0 or #subs > 0) then
            local group = { name = def.name or "?", def = def, subs = {} }
            local mainCount = #def.entries
            if not def.alwaysPrimary then
                mainCount = math.max(mainCount, MostEntries(subs))
            end
            local mainWidth = LineWidth(mainCount, ICON_SIZE)
            local mainLine = NewLine(mainWidth, ICON_SIZE + GLOW_SIZE * 2, PADDING - GLOW_SIZE, y + GLOW_SIZE)
            width = math.max(width, mainWidth)
            y = y - ICON_SIZE

            if def.alwaysPrimary then
                group.primary = CreateRow(group, mainLine, mainLine, def, ICON_SIZE, "primary", true)
                local subCount = MostEntries(subs)
                if subCount > 0 then
                    -- Its space is always kept: Lua can't tell when the Primary is affordable.
                    local subWidth = LineWidth(subCount, SUB_ICON_SIZE)
                    local subLine = NewLine(subWidth, SUB_ICON_SIZE + GLOW_SIZE * 2,
                        PADDING - GLOW_SIZE + SUB_INDENT, y - ICON_GAP + GLOW_SIZE)
                    width = math.max(width, subWidth + SUB_INDENT)
                    y = y - ICON_GAP - SUB_ICON_SIZE
                    for i, sub in ipairs(subs) do
                        group.subs[i] = CreateBandedRow(group, subLine, sub, SUB_ICON_SIZE, "sub " .. i)
                    end
                end
            else
                group.primary = CreateBandedRow(group, mainLine, def, ICON_SIZE, "primary")
                for i, sub in ipairs(subs) do
                    group.subs[i] = CreateBandedRow(group, mainLine, sub, ICON_SIZE, "sub " .. i)
                end
            end
            groups[#groups + 1] = group
            y = y - ROW_GAP
        end
    end
    local height = -y - ROW_GAP + PADDING
    root:SetSize(math.max(width + PADDING * 2 - GLOW_SIZE * 2, 40), math.max(height, 20))
end

----------------------------------------------------------------------------------------------
-- Updating
----------------------------------------------------------------------------------------------

-- Re-read everything about each entry: what it is, its costs and timings, what it restores.
local function RefreshEntries()
    for _, row in ipairs(rows) do
        for _, cell in ipairs(row.cells) do
            local entry = cell.entry
            local info = ResolveEntry(entry)
            local old = cell.info
            cell.info = info
            if not old or old.spellID ~= info.spellID or old.itemID ~= info.itemID or old.icon ~= info.icon
                or cell.actionPending then
                cell.grey:SetTexture(info.icon)
                cell.color:SetTexture(info.icon)
                cell.actionPending = InCombatLockdown()
                ApplyAction(cell)
            end
            cell.rankText:SetText(ns.RankText(info) or "")

            local spellID = info.spellID
            local description = GetDescription(spellID)
            local isItem = info.kind ~= "spell"
            cell.cost = (not isItem) and GetManaCost(spellID) or 0
            cell.castTime = GetCastTime(spellID)
            cell.gcd = GetGlobalCooldown(spellID) or (isItem and 0 or GLOBAL_COOLDOWN)
            cell.channel = ChannelTime(spellID, description)
            local gain, over = ParseManaGain(description)
            if info.kind == "manapot" then
                gain, over = manaPotions[1] and manaPotions[1].gain or nil, nil
            end
            cell.gain = (gain and not over) and gain or 0
            cell.gainOver = (gain and over and over > 0) and { amount = gain, duration = over } or nil
            cell.instantNext = MakesNextInstant(description)
            cell.usesClearcasting = info.kind == "spell" and not IsForm(entry.name, spellID)
                and not CLEARCASTING_IGNORES[entry.name]
        end
    end
end

-- Cooldown of an entry: start, duration, modRate, isOnGCD (any may be secret), or nil.
local function ReadCooldown(info)
    if info.kind ~= "spell" then
        if info.itemID and C_Container and C_Container.GetItemCooldown then
            local ok, start, duration = pcall(C_Container.GetItemCooldown, info.itemID)
            if ok then
                return start, duration, 1, nil
            end
        end
        return nil
    end
    if info.spellID and C_Spell and C_Spell.GetSpellCooldown then
        local ok, result = pcall(C_Spell.GetSpellCooldown, info.spellID)
        if ok and type(result) == "table" then
            return result.startTime, result.duration, result.modRate, result.isOnGCD
        end
    end
    return nil
end

-- Whether an entry is on a real cooldown (not just the global one): true / false / nil when
-- the game won't say. Also draws Blizzard's swipe and countdown on the cell.
local function UpdateCellCooldown(cell, now)
    local cooldown = cell.cooldown
    if cell.fakeCooldownEnd and cell.fakeCooldownEnd > now then
        cooldown:SetCooldown(cell.fakeCooldownEnd - FAKE_COOLDOWN, FAKE_COOLDOWN)
        cell.onCooldown = true
        cell.cooldownNote = "fake"
        return
    end
    if cell.fakeCooldownEnd then
        cell.fakeCooldownEnd = nil
        cell.shownStart, cell.shownDuration = nil, nil
        cooldown:Clear()
    end

    local start, duration, modRate, onGCD = ReadCooldown(cell.info)
    if start == nil and duration == nil then
        cell.onCooldown = nil
        cell.cooldownNote = "no answer"
        cooldown:Clear()
        return
    end

    if IsReadableNumber(start) and IsReadableNumber(duration) then
        local isGCD = (onGCD ~= nil and not IsSecret(onGCD) and onGCD) or duration <= GLOBAL_COOLDOWN
        if start > 0 and duration > 0 and not isGCD then
            if cell.shownStart ~= start or cell.shownDuration ~= duration then
                cooldown:SetCooldown(start, duration, IsReadableNumber(modRate) and modRate or 1)
                cell.shownStart, cell.shownDuration = start, duration
            end
            cell.onCooldown = true
        else
            if cell.shownStart then
                cooldown:Clear()
                cell.shownStart, cell.shownDuration = nil, nil
            end
            cell.onCooldown = false
        end
        cell.cooldownNote = string.format("start=%.1f duration=%.1f", start, duration)
        return
    end

    -- Secret: Lua can't tell, but Blizzard's widget may still draw it.
    cell.onCooldown = nil
    cell.cooldownNote = "secret"
    local drawn = false
    if cell.info.kind == "spell" and C_Spell.GetSpellCooldownDuration and cooldown.SetCooldownFromDurationObject then
        local ok, durationObject = pcall(C_Spell.GetSpellCooldownDuration, cell.info.spellID)
        if ok and durationObject then
            drawn = pcall(cooldown.SetCooldownFromDurationObject, cooldown, durationObject)
        end
    end
    if not drawn then
        pcall(cooldown.SetCooldown, cooldown, start, duration)
    end
end

local function UpdateCooldowns()
    local now = GetTime()
    for _, row in ipairs(rows) do
        local blocked = false
        for _, cell in ipairs(row.cells) do
            UpdateCellCooldown(cell, now)
            -- Greyed out while on cooldown or not in your bags: no colour, no highlight.
            local unusable = cell.onCooldown == true or not cell.info.available
            local alpha = unusable and 0 or 1
            cell.colorClip:SetAlpha(alpha)
            cell.fresh:SetAlpha(alpha)
            blocked = blocked or unusable
        end
        row.onCooldown = blocked
    end
end

local clearcasting = false

local function UpdateClearcasting()
    clearcasting = false
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", CLEARCASTING, "HELPFUL")
        clearcasting = ok and aura ~= nil
    elseif AuraUtil and AuraUtil.FindAuraByName then
        local ok, name = pcall(AuraUtil.FindAuraByName, CLEARCASTING, "player", "HELPFUL")
        clearcasting = ok and name ~= nil
    end
end

-- Mana regen per second outside and inside the 5-second rule, or nil when unreadable.
local function ReadRegen()
    if not GetManaRegen then
        return nil, nil
    end
    local ok, base, casting = pcall(GetManaRegen)
    if not ok or not IsReadableNumber(base) or not IsReadableNumber(casting) then
        return nil, nil
    end
    return base, casting
end

-- Length of [0, T] covered by the 5-second-rule windows (each { start, finish }, in order).
local function TimeInside(windows, T)
    local covered, reached = 0, 0
    for _, w in ipairs(windows) do
        local a = math.max(w[1], reached, 0)
        local b = math.min(w[2], T)
        if b > a then
            covered = covered + (b - a)
        end
        reached = math.max(reached, math.min(w[2], T))
    end
    return covered
end

local function IsInside(windows, t)
    for _, w in ipairs(windows) do
        if t >= w[1] and t < w[2] then
            return true
        end
    end
    return false
end

-- Mana regained between now (0) and time T (seconds from now). Smooth: a constant flow.
-- Ticks: REGEN_TICK-second ticks that land at `phase`, phase + REGEN_TICK, ..., before T.
-- `extras` are restores spread over time ({ start, finish, perSecond }), counted smoothly.
local function Gain(T, windows, extras, base, casting, phase)
    if T <= 0 then
        return 0
    end
    local gained = 0
    if phase == nil then
        local inside = TimeInside(windows, T)
        gained = base * (T - inside) + casting * inside
    else
        local t = phase
        while t < T do
            gained = gained + REGEN_TICK * (IsInside(windows, t) and casting or base)
            t = t + REGEN_TICK
        end
    end
    for _, e in ipairs(extras) do
        local span = math.min(e[2], T) - e[1]
        if span > 0 then
            gained = gained + span * e[3]
        end
    end
    return gained
end

-- Mana thresholds for one row, given the regen model and tick phase: threshold[i] is how much
-- mana you need now to start the sequence and still have the mana for entry i when it's due.
-- Each cost is taken (and each restore given) when the cast ends (instants: at once). The next
-- entry starts once the cast and any channel are done and the global cooldown has passed.
-- Mana can't go above max, so a restore or regen while full is lost.
local function RowThresholds(row, base, casting, phase, fsrRemaining, maxMana, freeNext)
    local windows, extras = {}, {}
    if fsrRemaining > 0 then
        windows[1] = { -math.huge, fsrRemaining }
    end
    local thresholds = {}
    local startTime, spent, highest = 0, 0, -math.huge
    local peak = -math.huge -- highest mana (relative to now) reached so far, before a cost
    local instantNext = false
    for i, cell in ipairs(row.cells) do
        local castTime = cell.castTime or 0
        if instantNext and castTime > 0 and castTime < INSTANT_LIMIT then
            castTime = 0
            instantNext = false
        end
        local cost = cell.cost or 0
        if freeNext and cell.usesClearcasting and cost > 0 then
            cost = 0
            freeNext = false
        end
        local due = startTime + castTime

        local regained = Gain(due, windows, extras, base, casting, phase)
        peak = math.max(peak, regained - spent)
        spent = spent + cost - (cell.gain or 0)
        local net = regained - spent -- mana now + net = mana after this entry

        local need = -net
        if maxMana and maxMana + net - peak < 0 then
            need = maxMana + 1 -- not even full mana is enough
        end
        highest = math.max(highest, need)
        thresholds[i] = highest

        if cost > 0 then
            windows[#windows + 1] = { due, due + FIVE_SECOND_RULE }
        end
        if cell.gainOver then
            local o = cell.gainOver
            extras[#extras + 1] = { due, due + o.duration, o.amount / o.duration }
        end
        if cell.instantNext then
            instantNext = true
        end
        startTime = startTime + math.max(castTime + (cell.channel or 0), cell.gcd or GLOBAL_COOLDOWN)
    end
    return thresholds
end

local fsrEndTime = 0

-- Lay the thresholds out along each row. Tick mode takes the worst case over every tick timing.
local function UpdateThresholds(now)
    local base, casting = 0, 0
    local ticks = false
    if db.regenMode ~= "off" then
        local b, c = ReadRegen()
        if b then
            base, casting = b, c
            ticks = db.regenMode == "ticks"
        end
    end
    local maxMana = UnitPowerMax("player", MANA_POWER_TYPE)
    if not IsReadableNumber(maxMana) or maxMana <= 0 then
        maxMana = nil
    end
    local fsrRemaining = math.max(0, fsrEndTime - now)

    for _, row in ipairs(rows) do
        local thresholds
        if ticks then
            thresholds = {}
            for step = 0, TICK_PHASE_STEPS - 1 do
                local phase = REGEN_TICK * step / TICK_PHASE_STEPS
                local list = RowThresholds(row, base, casting, phase, fsrRemaining, maxMana, clearcasting)
                for i, need in ipairs(list) do
                    thresholds[i] = math.max(thresholds[i] or -math.huge, need)
                end
            end
        else
            thresholds = RowThresholds(row, base, casting, nil, fsrRemaining, maxMana, clearcasting)
        end

        local previous = 0
        row.total = 0
        for i, cell in ipairs(row.cells) do
            -- Whole mana points: mana is an integer, so round the requirement up.
            local need = math.ceil(thresholds[i])
            cell.start = math.min(previous, need)
            cell.total = need
            if cell.total > cell.start then
                cell.fill:SetMinMaxValues(cell.start, cell.total)
            else
                -- Free entry: all or nothing on the mana before it.
                cell.fill:SetMinMaxValues(cell.total - 1, cell.total)
            end
            cell.nowSwitch:SetMinMaxValues(cell.total - 1, cell.total)
            cell.prevSwitch:SetMinMaxValues(cell.total - 1, cell.total)
            previous = need
            row.total = need
        end
    end
end

local function SetBand(row, low, high)
    low, high = low or -math.huge, high or math.huge
    if low >= high then
        low, high = NEVER, NEVER -- never shown
    end
    row.bandLow, row.bandHigh = low, high
    SetSwitchAt(row.low, low)
    SetSwitchAt(row.high, high)
end

-- Rows that may show, cheapest first. Rows set to hide on cooldown drop out while one of
-- their entries is on cooldown (or an item isn't in your bags).
local function Candidates(list)
    local result = {}
    for _, row in ipairs(list) do
        if row.def.hideOnCooldown and row.onCooldown then
            SetBand(row, NEVER, NEVER)
        else
            result[#result + 1] = row
        end
    end
    table.sort(result, function(a, b)
        if a.total ~= b.total then
            return a.total < b.total
        end
        return a.label < b.label
    end)
    return result
end

-- Decide which row of each group shows, as mana bands.
local function UpdateBands()
    for _, group in ipairs(groups) do
        if group.def.alwaysPrimary then
            -- Primary always shown. Below it: the most complete sub-sequence you can afford
            -- (the cheapest if none), until you can afford the Primary.
            local list = Candidates(group.subs)
            local primaryTotal = group.primary.total
            for k, row in ipairs(list) do
                local low = (k == 1) and -math.huge or row.total
                local nextRow = list[k + 1]
                local high = math.min(nextRow and nextRow.total or math.huge, primaryTotal)
                SetBand(row, low, high)
            end
        else
            -- One row: the cheapest sequence you can't afford yet, i.e. the one you're working
            -- towards, and the Primary once you can afford everything.
            local all = { group.primary }
            for _, row in ipairs(group.subs) do
                all[#all + 1] = row
            end
            local list = Candidates(all)
            for k, row in ipairs(list) do
                if row == group.primary then
                    table.remove(list, k)
                    list[#list + 1] = row
                    break
                end
            end
            for k, row in ipairs(list) do
                local previous = list[k - 1]
                local low = previous and previous.total or -math.huge
                local high = (k < #list) and row.total or math.huge
                SetBand(row, low, high)
            end
        end
    end
end

local function GetHighestTotal()
    local highest = 0
    for _, row in ipairs(rows) do
        highest = math.max(highest, row.total)
    end
    return highest
end

-- /fseq test: a readable fake mana value sweeping from 0 to a bit past the dearest sequence.
local testStartTime = nil

local function ReadMana()
    if testStartTime then
        local top = math.max(GetHighestTotal() * 1.15, 100)
        local t = ((GetTime() - testStartTime) % TEST_SWEEP_TIME) / TEST_SWEEP_TIME
        return math.floor(top * t)
    end
    local mana = UnitPower("player", MANA_POWER_TYPE)
    if mana == nil then
        return 0
    end
    return mana
end

-- Mana readings from the last FLASH_HOLD seconds, oldest first. They may be secret; they're
-- only ever stored and handed to StatusBars.
local samples = {}

local function PreviousMana(now, mana)
    samples[#samples + 1] = { time = now, mana = mana }
    while #samples >= 2 and samples[2].time <= now - FLASH_HOLD do
        table.remove(samples, 1)
    end
    return samples[1].mana
end

local function UpdateMana()
    local now = GetTime()
    UpdateThresholds(now)
    UpdateBands()
    local mana = ReadMana()
    local previous = PreviousMana(now, mana)
    for _, row in ipairs(rows) do
        if row.low then
            row.low:SetValue(mana)
            row.high:SetValue(mana)
        end
        for _, cell in ipairs(row.cells) do
            cell.fill:SetValue(mana)
            cell.nowSwitch:SetValue(mana)
            cell.prevSwitch:SetValue(previous)
        end
    end
end

local driver = CreateFrame("Frame")
local tickElapsed, refreshElapsed = 0, 0
local active = false

local function Refresh()
    RefreshEntries()
    UpdateCooldowns()
    UpdateClearcasting()
    UpdateMana()
end

driver:SetScript("OnUpdate", function(_, elapsed)
    if not active then
        return
    end
    refreshElapsed = refreshElapsed + elapsed
    if refreshElapsed >= REFRESH then
        refreshElapsed = 0
        RefreshEntries()
        UpdateCooldowns()
        UpdateClearcasting()
    end
    tickElapsed = tickElapsed + elapsed
    if tickElapsed >= TICK then
        tickElapsed = 0
        UpdateMana()
    end
end)

-- Rebuilding moves and hides secure buttons, so in combat it waits for the end of combat.
local pendingRebuild = false

local function Rebuild()
    if not active then
        return
    end
    if InCombatLockdown() then
        if not pendingRebuild then
            Print("the display will update after combat.")
        end
        pendingRebuild = true
        return
    end
    pendingRebuild = false
    BuildDisplay()
    wipe(samples)
    Refresh()
end
ns.Rebuild = Rebuild

----------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------

local function IsDruid()
    local _, class = UnitClass("player")
    return class == "DRUID"
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
driver:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
driver:RegisterEvent("SPELL_UPDATE_COOLDOWN")
driver:RegisterEvent("BAG_UPDATE_COOLDOWN")
driver:RegisterEvent("BAG_UPDATE_DELAYED")
driver:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
driver:RegisterUnitEvent("UNIT_MAXPOWER", "player")
driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
driver:RegisterUnitEvent("UNIT_AURA", "player")

-- Times of recent mana updates, for /fseq debug: steady 2s gaps mean Forever regens in ticks.
local manaEventTimes = {}

driver:SetScript("OnEvent", function(_, event, unit, arg2, arg3)
    if event == "PLAYER_LOGIN" then
        -- SavedVariables are loaded by now; pick up the saved table.
        ForeverSequencesDB = ForeverSequencesDB or {}
        db = ForeverSequencesDB
        ns.db = db
        for key, value in pairs(DEFAULTS) do
            if db[key] == nil then
                db[key] = value
            end
        end
        if type(db.sequences) ~= "table" then
            db.sequences = CopyTable(DEFAULT_SEQUENCES)
        end
        MigrateSequences(db.sequences)
        ApplyPosition()
        ns.ApplyLock()
        active = IsDruid()
        root:SetShown(active)
        ScanSpellbook()
        ScanBags()
        Rebuild()
    elseif not active then
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingRebuild then
            Rebuild()
        elseif pendingActions then
            pendingActions = false
            Refresh()
        end
    elseif event == "UNIT_POWER_FREQUENT" then
        if arg2 == "MANA" then
            manaEventTimes[#manaEventTimes + 1] = GetTime()
            if #manaEventTimes > 9 then
                table.remove(manaEventTimes, 1)
            end
        end
        UpdateMana()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- A spell that costs mana starts the 5-second rule.
        local spellID = arg3
        if spellID ~= nil and not IsSecret(spellID) then
            local cost = GetManaCost(spellID)
            if cost and cost > 0 then
                fsrEndTime = GetTime() + FIVE_SECOND_RULE
            end
        end
        UpdateMana()
    elseif event == "UNIT_AURA" then
        UpdateClearcasting()
        UpdateMana()
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        UpdateCooldowns()
        UpdateMana()
    elseif event == "SPELLS_CHANGED" or event == "UPDATE_SHAPESHIFT_FORMS" then
        ScanSpellbook()
        Refresh()
        if ns.RefreshEditor then ns.RefreshEditor() end
    elseif event == "BAG_UPDATE_DELAYED" then
        ScanBags()
        Refresh()
    else
        Refresh()
    end
end)

-- Clicking on/off, from the options. Secure buttons only change out of combat.
function ns.SetClickable(value)
    db.clickable = value
    if InCombatLockdown() then
        pendingActions = true
        for _, row in ipairs(rows) do
            for _, cell in ipairs(row.cells) do
                cell.actionPending = true
            end
        end
        Print("clicking will change after combat.")
        return
    end
    for _, row in ipairs(rows) do
        for _, cell in ipairs(row.cells) do
            ApplyAction(cell)
        end
    end
end

function ns.SetRegenMode(mode)
    db.regenMode = mode
    if active then
        UpdateMana()
    end
end

----------------------------------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------------------------------

local function Band(value)
    if value == nil then return "-" end
    if value == -math.huge then return "-inf" end
    if value == math.huge then return "inf" end
    if value >= NEVER then return "never" end
    return tostring(value)
end

local function PrintDebug()
    local mana = UnitPower("player", MANA_POWER_TYPE)
    local maxMana = UnitPowerMax("player", MANA_POWER_TYPE)
    Print(string.format("class druid=%s, mana=%s (secret=%s), max mana=%s, test mode=%s, clearcasting=%s",
        tostring(IsDruid()), Describe(mana), tostring(IsSecret(mana)), Describe(maxMana),
        tostring(testStartTime ~= nil), tostring(clearcasting)))
    local okRegen, base, casting = pcall(GetManaRegen)
    if not okRegen then base, casting = "error", "error" end
    local gaps = {}
    for i = 2, #manaEventTimes do
        gaps[#gaps + 1] = string.format("%.2f", manaEventTimes[i] - manaEventTimes[i - 1])
    end
    Print(string.format("regen mode=%s, regen/s outside 5SR=%s, inside=%s, 5SR left=%.1fs, mana update gaps: %s",
        db.regenMode, Describe(base), Describe(casting), math.max(0, fsrEndTime - GetTime()),
        #gaps > 0 and table.concat(gaps, " ") or "none yet"))
    local potions = {}
    for _, potion in ipairs(manaPotions) do
        potions[#potions + 1] = potion.itemID .. " (" .. potion.gain .. ")"
    end
    Print("mana potions in bags, best first: " .. (#potions > 0 and table.concat(potions, ", ") or "none"))
    for _, group in ipairs(groups) do
        Print(string.format("\"%s\": always show Primary=%s", group.name, tostring(group.def.alwaysPrimary and true or false)))
        local list = { group.primary }
        for _, row in ipairs(group.subs) do
            list[#list + 1] = row
        end
        for _, row in ipairs(list) do
            print(string.format("  %s: needs %s, shows from %s to %s, blocked=%s, hide on cooldown=%s",
                row.label, tostring(row.total),
                row.low and Band(row.bandLow) or "always", row.low and Band(row.bandHigh) or "always",
                tostring(row.onCooldown), tostring(row.def.hideOnCooldown and true or false)))
            for _, cell in ipairs(row.cells) do
                local info = cell.info or {}
                print(string.format("     %s: id=%s rank=%s/%s known=%s cost=%s cast=%ss gcd=%ss channel=%ss gain=%s%s instantNext=%s clearcasting=%s, needs %s-%s, cooldown: %s",
                    ns.EntryName(cell.entry), tostring(info.spellID), tostring(info.rank), tostring(info.maxRank),
                    tostring(info.known), tostring(cell.cost), tostring(cell.castTime), tostring(cell.gcd),
                    tostring(cell.channel), tostring(cell.gain),
                    cell.gainOver and string.format(" (+%s over %ss)", cell.gainOver.amount, cell.gainOver.duration) or "",
                    tostring(cell.instantNext), tostring(cell.usesClearcasting),
                    tostring(cell.start), tostring(cell.total), tostring(cell.cooldownNote)))
            end
        end
    end
end

SLASH_FOREVERSEQUENCES1 = "/fseq"
SlashCmdList["FOREVERSEQUENCES"] = function(msg)
    msg = (msg or ""):lower()
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" or cmd == "options" then
        OpenOptions()
    elseif cmd == "lock" or cmd == "unlock" then
        db.locked = cmd == "lock"
        ns.ApplyLock()
        if ns.RefreshEditor then ns.RefreshEditor() end
        Print(db.locked and "locked." or "unlocked: drag to move.")
    elseif cmd == "reset" then
        for _, key in ipairs({ "point", "relativePoint", "x", "y" }) do
            db[key] = DEFAULTS[key]
        end
        if InCombatLockdown() then
            Print("can't move it in combat.")
        else
            ApplyPosition()
            Print("position reset.")
        end
    elseif cmd == "test" then
        if testStartTime then
            testStartTime = nil
            Print("test sweep off.")
        else
            testStartTime = GetTime()
            wipe(samples)
            Print("test sweep on: fake mana goes from 0 to full every " .. TEST_SWEEP_TIME .. "s. /fseq test to stop.")
        end
        if active then
            UpdateMana()
        end
    elseif cmd == "cdtest" then
        local target = arg ~= "" and arg or "rejuvenation"
        local count = 0
        local ends = GetTime() + FAKE_COOLDOWN
        for _, row in ipairs(rows) do
            for _, cell in ipairs(row.cells) do
                if ns.EntryName(cell.entry):lower():find(target, 1, true) then
                    cell.fakeCooldownEnd = ends
                    count = count + 1
                end
            end
        end
        Print(string.format("fake %ds cooldown on %d %s icon(s).", FAKE_COOLDOWN, count, target))
        if active then
            UpdateCooldowns()
            UpdateMana()
        end
    elseif cmd == "defaults" then
        db.sequences = CopyTable(DEFAULT_SEQUENCES)
        Print("sequences reset to the defaults.")
        if ns.RefreshEditor then ns.RefreshEditor() end
        Rebuild()
    elseif cmd == "debug" then
        PrintDebug()
    else
        Print("/fseq (options) | lock | unlock | reset | test | cdtest [spell] | defaults | debug")
    end
end
