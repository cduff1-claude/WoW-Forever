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
local MAX_GATES = 13         -- health, mana now, and mana 1..MAX_HOLD seconds ago
local MAX_HOLD = 10          -- longest "keep showing" time for the mana threshold

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

-- spellID is any rank's ID, kept so the icon and name still show on a character that hasn't
-- learned the spell yet.
local function Spell(name, rank, spellID)
    return { kind = "spell", name = name, rank = rank, spellID = spellID }
end

-- Starting windows and sequences, until you make your own in the editor. Dynamic windows
-- show one row per sequence and close up gaps; fixed windows always show the Primary (which
-- can be clicked to cast) with the best sub-sequence under it, and never move anything.
local DEFAULT_WINDOWS = {
    {
        name = "Main",
        type = "dynamic",
        enabled = true,
        onlyInCombat = false,
        sequences = {
            {
                name = "Bear out",
                enabled = true,
                hideOnCooldown = false,
                entries = { Spell("Regrowth"), Spell("Rejuvenation"), Spell("Bear Form") },
                subs = {
                    { entries = { Spell("Regrowth"), Spell("Bear Form") }, hideOnCooldown = false },
                    { entries = { Spell("Rejuvenation"), Spell("Bear Form") }, hideOnCooldown = false },
                },
            },
        },
    },
    {
        name = "Clickable",
        type = "fixed",
        enabled = true,
        onlyInCombat = false,
        sequences = {
            {
                name = "Root and run",
                enabled = true,
                hideOnCooldown = false,
                entries = { Spell("Entangling Roots"), Spell("Rejuvenation"), Spell("Travel Form") },
                subs = {
                    { entries = { Spell("Entangling Roots"), Spell("Travel Form") }, hideOnCooldown = false },
                },
            },
        },
    },
}

ForeverSequencesDB = ForeverSequencesDB or {}
local db = ForeverSequencesDB

local DEFAULTS = {
    regenMode = "smooth", -- "smooth" (Forever's regen), "ticks" (2-second ticks, worst timing) or "off"
    clickable = true,     -- click a fixed window's Primary to cast
}

local function CopyTable(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = type(v) == "table" and CopyTable(v) or v
    end
    return copy
end
ns.CopyTable = CopyTable

-- The first prototype held spell names in `spells`.
local function MigrateSequence(def)
    local function Convert(list)
        if list.spells and not list.entries then
            list.entries = {}
            for _, name in ipairs(list.spells) do
                list.entries[#list.entries + 1] = Spell(name)
            end
            list.spells = nil
        end
        list.entries = list.entries or {}
    end
    Convert(def)
    def.subs = def.subs or {}
    for _, sub in ipairs(def.subs) do
        Convert(sub)
    end
end

-- Settings a window gets when it doesn't have them yet. The thresholds and target filter
-- only apply to dynamic windows.
local WINDOW_DEFAULTS = {
    type = "dynamic",
    enabled = true,
    onlyInCombat = false,
    manaGate = false,   -- show only when mana is below the dearest sequence's need + manaMargin %
    manaMargin = 20,
    healthGate = false, -- show only when health is below healthPercent %
    healthPercent = 50,
    holdSeconds = 5,    -- and keep showing this long after mana goes back above
    targets = { pvp = true, npcs = true, none = true }, -- what the fight is against (see lastEnemy)
}

local function NewId()
    db.nextId = (db.nextId or 0) + 1
    return db.nextId
end
ns.NewId = NewId

-- Sequences live in a library; each window lists the ones it shows ({ id, enabled }), so the
-- same sequence can appear in several windows. Windows saved before the library held their
-- own sequences; those move into the library.
local function MoveSequencesToLibrary()
    db.library = db.library or {}
    for _, window in ipairs(db.windows) do
        window.items = window.items or {}
        if window.sequences then
            for _, def in ipairs(window.sequences) do
                MigrateSequence(def)
                def.id = def.id or NewId()
                window.items[#window.items + 1] = { id = def.id, enabled = def.enabled ~= false }
                def.enabled = nil
                db.library[#db.library + 1] = def
            end
            window.sequences = nil
        end
        for key, value in pairs(WINDOW_DEFAULTS) do
            if window[key] == nil then
                window[key] = type(value) == "table" and CopyTable(value) or value
            end
        end
        -- "Players and their pets" became "PvP targets".
        if window.targets.players ~= nil then
            window.targets.pvp = window.targets.players
            window.targets.players = nil
        end
    end
    for _, def in ipairs(db.library) do
        MigrateSequence(def)
        def.id = def.id or NewId()
    end
end

-- Older versions kept one list of sequences, each with its own "always show Primary". Those
-- become a dynamic window and (for the always-shown ones) a fixed window.
local function MigrateSettings()
    if type(db.windows) ~= "table" then
        if type(db.sequences) == "table" then
            local dynamic = { name = "Main", type = "dynamic", enabled = true, onlyInCombat = false, sequences = {} }
            local fixed = { name = "Clickable", type = "fixed", enabled = true, onlyInCombat = false, sequences = {} }
            for _, def in ipairs(db.sequences) do
                local list = def.alwaysPrimary and fixed.sequences or dynamic.sequences
                def.alwaysPrimary = nil
                list[#list + 1] = def
            end
            db.windows = { dynamic }
            if #fixed.sequences > 0 then
                db.windows[2] = fixed
            end
        else
            db.windows = CopyTable(DEFAULT_WINDOWS)
        end
    end
    db.sequences, db.point, db.relativePoint, db.x, db.y, db.locked = nil, nil, nil, nil, nil, nil
    MoveSequencesToLibrary()
    -- Forever's regen is smooth; earlier versions defaulted to ticks.
    if not db.smoothRegenDefault then
        db.regenMode = "smooth"
        db.smoothRegenDefault = true
    end
end

function ns.ResetToDefaults()
    db.windows = CopyTable(DEFAULT_WINDOWS)
    db.library = {}
    MoveSequencesToLibrary()
end

function ns.NewWindow(name)
    local window = { name = name, items = {} }
    for key, value in pairs(WINDOW_DEFAULTS) do
        window[key] = type(value) == "table" and CopyTable(value) or value
    end
    return window
end

function ns.FindSequence(id)
    for _, def in ipairs(db.library) do
        if def.id == id then
            return def
        end
    end
    return nil
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
local bookLines = {}   -- spellbook order: { name = skill line, spells = { names } }

local function ScanSpellbook()
    wipe(spellbook)
    wipe(rankOfSpell)
    wipe(bookLines)
    local book = C_SpellBook
    if book and book.GetNumSpellBookSkillLines then
        local futureType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
        for line = 1, book.GetNumSpellBookSkillLines() or 0 do
            local info = book.GetSpellBookSkillLineInfo(line)
            if info and not info.shouldHide then
                local bookLine = { name = Text(info.name) or "", spells = {} }
                bookLines[#bookLines + 1] = bookLine
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
                            bookLine.spells[#bookLine.spells + 1] = name
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

-- "Increases the target's Mana regeneration by 400% and allows 100% of the target's Mana
-- regeneration to continue while casting. Lasts 20 sec." (Innervate, cast on yourself.)
local function ParseRegenBoost(description)
    if not description then
        return nil
    end
    local text = description:gsub("\r?\n", " ")
    local percent = Number(text:match("[Mm]ana regeneration by ([%d,]+)%%"))
    local duration = Number(text:match("[Ll]asts ([%d%.]+) sec")) or Number(text:match("for ([%d%.]+) sec"))
    if not (percent and duration and duration > 0) then
        return nil
    end
    return {
        multiplier = 1 + percent / 100,
        duration = duration,
        whileCasting = text:find("continue while casting", 1, true) ~= nil,
    }
end

-- "Only works on Beasts and Dragonkin." -> { Beast = true, Dragonkin = true }, matched against
-- UnitCreatureType (singular names).
local function ParseCreatureTypes(description)
    local list = description and description:match("[Oo]nly works on ([%a ,]+)")
    if not list then
        return nil
    end
    local types = {}
    for piece in list:gsub(" and ", ","):gmatch("[^,]+") do
        local word = piece:match("^%s*(.-)%s*$")
        if word ~= "" and not word:find(" ") then
            types[word] = true
            types[(word:gsub("s$", ""))] = true
        end
    end
    return next(types) and types or nil
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
        if not info.known and next(spellbook) == nil then
            info.known = nil -- the spellbook couldn't be read: don't treat everything as unlearned
        end
        if info.known then
            entry.spellID = info.spellID
        elseif entry.spellID then
            info.spellID = entry.spellID
        end
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

-- Whether every spell in a list of entries has been learned. Items and potions don't count:
-- not having them greys the icon instead.
function ns.AllLearned(entries)
    for _, entry in ipairs(entries) do
        if entry.kind == "spell" and ResolveEntry(entry).known == false then
            return false
        end
    end
    return true
end

-- Names of the spells in a list of entries that haven't been learned yet.
function ns.Unlearned(entries)
    local names = {}
    for _, entry in ipairs(entries) do
        if entry.kind == "spell" and ResolveEntry(entry).known == false then
            names[#names + 1] = entry.name
        end
    end
    return names
end

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
            return Spell(name, rank, spellID)
        end
        return Spell(name, nil, spellID)
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

-- Whether an entry has a cooldown of its own (longer than the global cooldown). Items and
-- potions always count: they share cooldowns the spell data doesn't show.
-- Whether an entry can be unusable for a while: a cooldown of its own (longer than the global
-- cooldown), or only working on some creature types (Hibernate). Items and potions always
-- count: they share cooldowns the spell data doesn't show.
function ns.HasCooldown(entry)
    if entry.kind ~= "spell" then
        return true
    end
    local spellID = ResolveSpell(entry.name, entry.rank) or entry.spellID
    if ParseCreatureTypes(GetDescription(spellID)) then
        return true
    end
    local fn = (C_Spell and C_Spell.GetSpellBaseCooldown) or GetSpellBaseCooldown
    if spellID and fn then
        local ok, cooldownMS = pcall(fn, spellID)
        if ok and IsReadableNumber(cooldownMS) then
            return cooldownMS > GLOBAL_COOLDOWN * 1000
        end
    end
    return false
end

function ns.AnyCooldown(entries)
    for _, entry in ipairs(entries) do
        if ns.HasCooldown(entry) then
            return true
        end
    end
    return false
end

-- Items with a use that never belongs in a sequence: hearthstones and anything you have to
-- sit down for (food, drink, bandage-style channels).
local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12

-- Whether the item's tooltip has a "Use:" line (true when the tooltip can't be read).
local function HasUseLine(itemID)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
        return true
    end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
        return true
    end
    for _, line in ipairs(data.lines) do
        local text = Text(line.leftText)
        if text and text:find("^Use:") then
            return true
        end
    end
    return false
end

-- Items that never belong in a sequence: quest items, items with no "Use:", hearthstones and
-- anything you have to sit down for (food, drink).
local function IsOutOfCombatItem(itemID, description)
    if itemID == 6948 then -- Hearthstone
        return true
    end
    local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
    if ok and classID == QUEST_CLASS then
        return true
    end
    if not HasUseLine(itemID) then
        return true
    end
    local text = (description or ""):lower()
    return text:find("must remain seated", 1, true) ~= nil or text:find("returns you to", 1, true) ~= nil
end

-- A short second line for the editor's list.
local function SpellSummary(spellID)
    local parts = {}
    local rank = rankOfSpell[spellID]
    if rank and rank > 0 then
        parts[#parts + 1] = "Rank " .. rank
    end
    local cost = GetManaCost(spellID)
    if cost and cost > 0 then
        parts[#parts + 1] = cost .. " mana"
    end
    local castTime = GetCastTime(spellID)
    parts[#parts + 1] = (castTime and castTime > 0) and string.format("%.1fs cast", castTime) or "Instant"
    return table.concat(parts, " - ")
end

local function ItemSummary(itemID, description)
    local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID)) or bagCounts[itemID] or 0
    local first = description and description:match("^[^%.\n]+%.?") or ""
    return (IsReadableNumber(count) and count > 1 and ("x" .. count .. " - ") or "") .. first
end

-- The editor's list shows what you'd use mana on in combat, plus a few in-form abilities that
-- buy time to regen; "Show all" shows everything. Never listed: passives, internal spells
-- ("(DND)", "Shapeshift"), and spells that can't be cast in combat.
local NEVER_LISTED = {
    ["Shapeshift"] = true,
}
-- Listed even though they cost no mana.
local ALWAYS_LISTED = {
    ["War Stomp"] = true,
    ["Shadowmeld"] = true,
    ["Bash"] = true,
    ["Feral Charge"] = true,
    ["Feral Charge - Bear"] = true,
    ["Feral Charge - Cat"] = true,
    ["Frenzied Regeneration"] = true,
    ["Innervate"] = true,
}
-- Mana spells left out unless "Show all": buffs and utility you wouldn't use mid-fight.
local NOT_LISTED = {
    ["Mark of the Wild"] = true,
    ["Gift of the Wild"] = true,
    ["Thorns"] = true,
    ["Omen of Clarity"] = true,
    ["Teleport: Moonglade"] = true,
    ["Soothe Animal"] = true,
    ["Revive"] = true,
    ["Track Humanoids"] = true,
}
-- Spellbook tabs that only list ALWAYS_LISTED spells (the rest there aren't mana spells).
local LISTED_ONLY_TABS = {
    ["General"] = true,
    ["Feral Combat"] = true,
}

local function IsInternalSpell(name, description)
    return NEVER_LISTED[name] or name:find("DND", 1, true) ~= nil
        or (description ~= nil and description:find("DND", 1, true) ~= nil)
end

local function NotInCombat(description)
    local text = (description or ""):lower()
    return text:find("cannot be cast in combat", 1, true) ~= nil or text:find("out of combat", 1, true) ~= nil
end

local function IsListed(name, spellID, tab, description)
    if NOT_LISTED[name] then
        return false
    end
    if ALWAYS_LISTED[name] then
        return true
    end
    if LISTED_ONLY_TABS[tab] or NotInCombat(description) then
        return false
    end
    local cost = GetManaCost(spellID)
    return (cost and cost > 0) or ns.HasCooldown(Spell(name, nil, spellID))
end

-- Everything that can go in a sequence, for the editor's list, in sections: the
-- best-mana-potion entry, your spells in spellbook order (by spellbook tab), then usable
-- items (equipped trinkets and bags). `filter` is a lower-case piece of the name, or nil.
-- Returns { { title, items = { { entry, icon, name, summary } } } }.
function ns.PickerEntries(filter, showAll)
    local sections = {}
    local function Section(title)
        local section = { title = title, items = {} }
        sections[#sections + 1] = section
        return section
    end
    local function Add(section, entry, icon, name, summary)
        if not filter or filter == "" or name:lower():find(filter, 1, true) then
            section.items[#section.items + 1] = { entry = entry, icon = icon, name = name, summary = summary }
        end
    end

    local potions = Section("Potions")
    Add(potions, { kind = "manapot" }, ResolveEntry({ kind = "manapot" }).icon, "Best mana potion",
        manaPotions[1] and ("Restores " .. manaPotions[1].gain .. "+ mana") or "None in your bags")

    -- Forms get their own section, just above the Feral tab (or after the other spells).
    local forms = { title = "Forms", items = {} }
    local formsPlaced = false
    for _, line in ipairs(bookLines) do
        if line.name == "Feral Combat" then
            sections[#sections + 1] = forms
            formsPlaced = true
        end
        local section = Section(line.name ~= "" and line.name or "Spells")
        for _, name in ipairs(line.spells) do
            local spellID = spellbook[name].maxID
            local description = GetDescription(spellID)
            if not IsInternalSpell(name, description) then
                local entry = Spell(name, nil, spellID)
                local target = IsForm(name, spellID) and forms
                    or ((showAll or IsListed(name, spellID, line.name, description)) and section)
                if target then
                    Add(target, entry, GetSpellIcon(spellID), name, SpellSummary(spellID))
                end
            end
        end
    end
    if not formsPlaced then
        sections[#sections + 1] = forms
    end

    local items = Section("Items")
    local seen = {}
    local itemIDs = {}
    if GetInventoryItemID then
        for _, slot in ipairs({ 13, 14 }) do
            local itemID = GetInventoryItemID("player", slot)
            if IsReadableNumber(itemID) and not seen[itemID] then
                seen[itemID] = true
                itemIDs[#itemIDs + 1] = itemID
            end
        end
    end
    local bagIDs = {}
    for itemID in pairs(bagCounts) do
        if not seen[itemID] then
            bagIDs[#bagIDs + 1] = itemID
        end
    end
    table.sort(bagIDs)
    for _, itemID in ipairs(bagIDs) do
        itemIDs[#itemIDs + 1] = itemID
    end
    for _, itemID in ipairs(itemIDs) do
        local spellID = GetItemUseSpell(itemID)
        local description = spellID and GetDescription(spellID)
        if spellID and not IsOutOfCombatItem(itemID, description) then
            local entry = { kind = "item", itemID = itemID }
            Add(items, entry, GetItemIcon(itemID), ns.EntryName(entry), ItemSummary(itemID, description))
        end
    end

    local result = {}
    for _, section in ipairs(sections) do
        if #section.items > 0 then
            result[#result + 1] = section
        end
    end
    return result
end

----------------------------------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------------------------------

local active = false
local editorOpen = false

local function OpenOptions()
    if ns.ToggleEditor then
        ns.ToggleEditor(true)
    end
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
-- Display windows: one on-screen frame per window in the settings
----------------------------------------------------------------------------------------------

local roots = {} -- by window index; reused across rebuilds

local function SavePosition(root)
    local window = root.window
    if not window then
        return
    end
    window.left, window.top = root:GetLeft(), root:GetTop()
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", window.left, window.top)
end

local function ApplyPosition(root, window, index)
    root:ClearAllPoints()
    if window.left and window.top then
        root:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", window.left, window.top)
    else
        root:SetPoint("TOP", UIParent, "CENTER", (index - 1) * 30, -120 - (index - 1) * 110)
    end
end

local function GetRoot(index)
    if roots[index] then
        return roots[index]
    end
    local root = CreateFrame("Frame", "ForeverSequencesWindow" .. index, UIParent)
    root:SetSize(100, 50)
    root:SetMovable(true)
    root:SetClampedToScreen(true)

    -- While the options are open, a cover over the window takes the drags (and clicks, so
    -- nothing is cast while moving it).
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
    mover:SetScript("OnDragStart", function()
        -- Windows may hold secure buttons, so they can't move in combat.
        if not InCombatLockdown() then
            root:StartMoving()
        end
    end)
    mover:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        SavePosition(root)
    end)
    mover:Hide()
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", mover, "TOPLEFT", 0, 2)

    -- Dynamic windows can be set to show only when mana or health is low. The rows sit in
    -- `content`, which clips to "any condition true". Each switch is full while its condition
    -- is false; switch k+1 is squeezed to switch k's fill, so if any switch is empty the ones
    -- after it have no width, and the clip (from the last switch's fill edge to the right)
    -- opens fully. Unused switches are kept full; with no conditions the first is kept empty.
    root.gates = {}
    local previous
    for i = 1, MAX_GATES do
        local gate = NewFrame("StatusBar", root)
        gate:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        gate:SetStatusBarColor(0, 0, 0, 0)
        gate:SetMinMaxValues(NEVER - 1, NEVER)
        gate:SetValue(0)
        gate:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
        if previous then
            gate:SetPoint("BOTTOMRIGHT", previous:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        else
            gate:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
        end
        root.gates[i] = gate
        previous = gate
    end
    root.content = NewClip(root, previous:GetStatusBarTexture(), "RIGHT", root, "RIGHT")
    root.mover, root.label = mover, label
    root.lines, root.groups = {}, {}
    roots[index] = root
    return root
end

-- Shown, hidden, or shown only in combat (a secure state driver, so it works for windows with
-- click-to-cast buttons too). Always shown, unlocked, while the options are open.
local pendingVisibility = false

local function ApplyVisibility()
    for _, root in ipairs(roots) do
        local window = root.window
        root.mover:SetShown(editorOpen and window ~= nil and window.enabled and true or false)
    end
    if InCombatLockdown() then
        pendingVisibility = true
        return
    end
    pendingVisibility = false
    for _, root in ipairs(roots) do
        local window = root.window
        if UnregisterStateDriver then
            UnregisterStateDriver(root, "visibility")
        end
        if not (active and window and window.enabled) then
            root:Hide()
        elseif editorOpen or not window.onlyInCombat or not RegisterStateDriver then
            root:Show()
        else
            RegisterStateDriver(root, "visibility", "[combat] show; hide")
        end
    end
end

function ns.SetEditorOpen(open)
    editorOpen = open and true or false
    ApplyVisibility()
end

----------------------------------------------------------------------------------------------
-- Clicking (fixed windows' Primary only: those buttons never move or swap)
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
-- Icons and rows
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

-- secure: a click-to-cast button (a fixed window's Primary). Otherwise a plain frame that
-- only takes right-clicks; left clicks go through it.
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

local function NewLine(root, width, height)
    local line = NewFrame("Frame", root.content)
    line:SetSize(width, height)
    root.lines[#root.lines + 1] = line
    return line
end

local function MostEntries(list)
    local most = 0
    for _, def in ipairs(list) do
        most = math.max(most, #def.entries)
    end
    return most
end

local function BuildWindow(root, window)
    for _, item in ipairs(window.items) do
        local def = ns.FindSequence(item.id)
        local subs = {}
        -- A sequence waits until its Primary's spells are all learned; a sub-sequence with a
        -- spell not learned yet is left out.
        for _, sub in ipairs(def and def.subs or {}) do
            if #sub.entries > 0 and ns.AllLearned(sub.entries) then
                subs[#subs + 1] = sub
            end
        end
        if def and item.enabled and #def.entries > 0 and ns.AllLearned(def.entries) then
            local group = { name = def.name or "?", def = def, subs = {}, root = root, fixed = root.fixed }
            if root.fixed then
                group.mainLine = NewLine(root, LineWidth(#def.entries, ICON_SIZE), ICON_SIZE + GLOW_SIZE * 2)
                group.primary = CreateRow(group, group.mainLine, group.mainLine, def, ICON_SIZE, "primary", true)
                local subCount = MostEntries(subs)
                if subCount > 0 then
                    -- Its space is always kept: Lua can't tell when the Primary is affordable,
                    -- and click-to-cast buttons can't move in combat.
                    group.subLine = NewLine(root, LineWidth(subCount, SUB_ICON_SIZE), SUB_ICON_SIZE + GLOW_SIZE * 2)
                    for i, sub in ipairs(subs) do
                        group.subs[i] = CreateBandedRow(group, group.subLine, sub, SUB_ICON_SIZE, "sub " .. i)
                    end
                end
            else
                local count = math.max(#def.entries, MostEntries(subs))
                group.mainLine = NewLine(root, LineWidth(count, ICON_SIZE), ICON_SIZE + GLOW_SIZE * 2)
                group.primary = CreateBandedRow(group, group.mainLine, def, ICON_SIZE, "primary")
                for i, sub in ipairs(subs) do
                    group.subs[i] = CreateBandedRow(group, group.mainLine, sub, ICON_SIZE, "sub " .. i)
                end
            end
            root.groups[#root.groups + 1] = group
            groups[#groups + 1] = group
        end
    end
end

-- Stack each window's rows. Dynamic windows skip sequences with nothing to show, so the rows
-- below move up; fixed windows keep every row (and their buttons) in place.
local function LayoutWindows()
    for _, root in ipairs(roots) do
        if root.window and not (root.fixed and InCombatLockdown()) then
            local key = {}
            for i, group in ipairs(root.groups) do
                key[i] = (root.fixed or not group.collapsed) and "1" or "0"
            end
            key = table.concat(key)
            if key ~= root.layoutKey then
                root.layoutKey = key
                local y = -PADDING
                local width = 0
                for _, group in ipairs(root.groups) do
                    local shown = root.fixed or not group.collapsed
                    group.mainLine:SetShown(shown)
                    if group.subLine then
                        group.subLine:SetShown(shown)
                    end
                    if shown then
                        group.mainLine:ClearAllPoints()
                        group.mainLine:SetPoint("TOPLEFT", root, "TOPLEFT", PADDING - GLOW_SIZE, y + GLOW_SIZE)
                        width = math.max(width, group.mainLine:GetWidth())
                        y = y - ICON_SIZE
                        if group.subLine then
                            group.subLine:ClearAllPoints()
                            group.subLine:SetPoint("TOPLEFT", root, "TOPLEFT",
                                PADDING - GLOW_SIZE + SUB_INDENT, y - ICON_GAP + GLOW_SIZE)
                            width = math.max(width, group.subLine:GetWidth() + SUB_INDENT)
                            y = y - ICON_GAP - SUB_ICON_SIZE
                        end
                        y = y - ROW_GAP
                    end
                end
                local height = -y - ROW_GAP + PADDING
                root:SetSize(math.max(width + PADDING * 2 - GLOW_SIZE * 2, 60), math.max(height, 24))
            end
        end
    end
end

local function BuildDisplay()
    for _, root in ipairs(roots) do
        for _, line in ipairs(root.lines) do
            line:Hide()
        end
        wipe(root.lines)
        wipe(root.groups)
        root.window = nil
        root.layoutKey = nil
    end
    wipe(groups)
    wipe(rows)

    for index, window in ipairs(db.windows) do
        local root = GetRoot(index)
        root.window = window
        root.fixed = window.type == "fixed"
        root.label:SetText((window.name or "?") .. (root.fixed and " (fixed)" or " (dynamic)") .. ": drag to move")
        ApplyPosition(root, window, index)
        if window.enabled then
            BuildWindow(root, window)
        end
    end
    LayoutWindows()
    ApplyVisibility()
end

function ns.ResetPositions()
    if InCombatLockdown() then
        Print("can't move windows in combat.")
        return
    end
    for index, window in ipairs(db.windows) do
        window.left, window.top = nil, nil
        if roots[index] then
            ApplyPosition(roots[index], window, index)
        end
    end
end

----------------------------------------------------------------------------------------------
-- Updating
----------------------------------------------------------------------------------------------

-- Everything the timing maths needs about one entry, written into `target`.
local function EntryData(entry, info, target)
    local spellID = info.spellID
    local description = GetDescription(spellID)
    local isItem = info.kind ~= "spell"
    target.cost = (not isItem) and GetManaCost(spellID) or 0
    target.castTime = GetCastTime(spellID)
    target.gcd = GetGlobalCooldown(spellID) or (isItem and 0 or GLOBAL_COOLDOWN)
    target.channel = ChannelTime(spellID, description)
    local gain, over = ParseManaGain(description)
    if info.kind == "manapot" then
        gain, over = manaPotions[1] and manaPotions[1].gain or nil, nil
    end
    target.gain = (gain and not over) and gain or 0
    target.gainOver = (gain and over and over > 0) and { amount = gain, duration = over } or nil
    target.instantNext = MakesNextInstant(description)
    target.regenBoost = ParseRegenBoost(description)
    target.creatureTypes = ParseCreatureTypes(description)
    target.usesClearcasting = info.kind == "spell" and not IsForm(entry.name, spellID)
        and not CLEARCASTING_IGNORES[entry.name]
end

-- Re-read everything about each icon.
local function RefreshEntries()
    for _, row in ipairs(rows) do
        for _, cell in ipairs(row.cells) do
            local info = ResolveEntry(cell.entry)
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
            EntryData(cell.entry, info, cell)
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

-- For spells that only work on some creature types (Hibernate): true when the current target
-- isn't one of them (or there's no enemy target). Nil when the game won't say.
local function TargetDoesNotFit(types)
    if not types then
        return false
    end
    if not UnitExists("target") then
        return true
    end
    local okAttack, canAttack = pcall(UnitCanAttack, "player", "target")
    if okAttack and not IsSecret(canAttack) and not canAttack then
        return true
    end
    local ok, creature = pcall(UnitCreatureType, "target")
    if not ok or creature == nil or IsSecret(creature) then
        return nil
    end
    return not types[creature]
end

local function UpdateCooldowns()
    local now = GetTime()
    for _, row in ipairs(rows) do
        local blocked = false
        for _, cell in ipairs(row.cells) do
            UpdateCellCooldown(cell, now)
            -- Greyed out while on cooldown or not in your bags: no colour, no highlight.
            cell.wrongTarget = TargetDoesNotFit(cell.creatureTypes)
            local unusable = cell.onCooldown == true or not cell.info.available or cell.wrongTarget
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
local function RegenAt(t, windows, boosts, base, casting)
    local inside = IsInside(windows, t)
    for _, boost in ipairs(boosts) do
        if t >= boost[1] and t < boost[2] then
            return boost[3] * ((inside and not boost[4]) and casting or base)
        end
    end
    return inside and casting or base
end

-- `boosts` raise regen for a while ({ start, finish, multiplier, full regen while casting }),
-- from Innervate and the like; with any, smooth regen is added up in small steps.
local REGEN_STEP = 0.1

local function Gain(T, windows, extras, base, casting, phase, boosts)
    if T <= 0 then
        return 0
    end
    local gained = 0
    if phase == nil and (not boosts or #boosts == 0) then
        local inside = TimeInside(windows, T)
        gained = base * (T - inside) + casting * inside
    elseif phase == nil then
        local t = 0
        while t < T do
            local dt = math.min(REGEN_STEP, T - t)
            gained = gained + dt * RegenAt(t + dt / 2, windows, boosts, base, casting)
            t = t + REGEN_STEP
        end
    else
        local t = phase
        while t < T do
            gained = gained + REGEN_TICK * RegenAt(t, windows, boosts or {}, base, casting)
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
local function RowThresholds(row, ctx, phase)
    local windows, extras, boosts = {}, {}, {}
    if ctx.fsrRemaining > 0 then
        windows[1] = { -math.huge, ctx.fsrRemaining }
    end
    local freeNext = ctx.clearcasting
    local thresholds = {}
    local startTime, spent, highest = 0, 0, -math.huge
    local peak = -math.huge -- highest mana (relative to now) reached so far, before a cost
    local instantNext = false
    local lastRegained = 0
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

        local regained = Gain(due, windows, extras, ctx.base, ctx.casting, phase, boosts)
        lastRegained = regained
        peak = math.max(peak, regained - spent)
        spent = spent + cost - (cell.gain or 0)
        local net = regained - spent -- mana now + net = mana after this entry

        local need = -net
        if ctx.maxMana and ctx.maxMana + net - peak < 0 then
            need = ctx.maxMana + 1 -- not even full mana is enough
        end
        highest = math.max(highest, need)
        thresholds[i] = highest

        if cost > 0 then
            windows[#windows + 1] = { due, due + FIVE_SECOND_RULE }
        end
        if cell.regenBoost then
            local r = cell.regenBoost
            boosts[#boosts + 1] = { due, due + r.duration, r.multiplier, r.whileCasting }
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
    return thresholds, lastRegained
end

local fsrEndTime = 0

-- What the maths needs to know right now.
local function Context(now)
    local ctx = { base = 0, casting = 0, ticks = false, clearcasting = clearcasting }
    if db.regenMode ~= "off" then
        local base, casting = ReadRegen()
        if base then
            ctx.base, ctx.casting = base, casting
            ctx.ticks = db.regenMode == "ticks"
        end
    end
    local maxMana = UnitPowerMax("player", MANA_POWER_TYPE)
    ctx.maxMana = (IsReadableNumber(maxMana) and maxMana > 0) and maxMana or nil
    ctx.fsrRemaining = math.max(0, fsrEndTime - now)
    return ctx
end

-- Whole-mana thresholds for a row. Tick mode takes the worst case over every tick timing.
local function RowNeeds(row, ctx)
    local thresholds
    if ctx.ticks then
        thresholds = {}
        for step = 0, TICK_PHASE_STEPS - 1 do
            local phase = REGEN_TICK * step / TICK_PHASE_STEPS
            for i, need in ipairs(RowThresholds(row, ctx, phase)) do
                thresholds[i] = math.max(thresholds[i] or -math.huge, need)
            end
        end
    else
        thresholds = RowThresholds(row, ctx, nil)
    end
    for i, need in ipairs(thresholds) do
        thresholds[i] = math.ceil(need) -- mana is an integer
    end
    return thresholds
end

-- For the editor: the mana needed now to start these entries, and what they cost in all.
-- For the editor: what the entries cost in all, and the mana gained before the last one is
-- cast (regen, plus potions and other restores in the sequence).
function ns.CostSummary(entries)
    local row = { cells = {} }
    local cost, restored = 0, 0
    for i, entry in ipairs(entries) do
        local cell = {}
        EntryData(entry, ResolveEntry(entry), cell)
        row.cells[i] = cell
        cost = cost + (cell.cost or 0)
        restored = restored + (cell.gain or 0)
    end
    local ctx = Context(GetTime())
    local regained
    if ctx.ticks then
        for step = 0, TICK_PHASE_STEPS - 1 do
            local _, r = RowThresholds(row, ctx, REGEN_TICK * step / TICK_PHASE_STEPS)
            regained = math.min(regained or math.huge, r)
        end
    else
        local _, r = RowThresholds(row, ctx, nil)
        regained = r
    end
    return cost, math.floor((regained or 0) + restored)
end

function ns.Need(entries)
    local row = { cells = {} }
    local cost = 0
    for i, entry in ipairs(entries) do
        local cell = {}
        EntryData(entry, ResolveEntry(entry), cell)
        row.cells[i] = cell
        cost = cost + (cell.cost or 0)
    end
    local thresholds = RowNeeds(row, Context(GetTime()))
    return math.max(0, thresholds[#thresholds] or 0), cost
end

local function UpdateThresholds(now)
    local ctx = Context(now)
    for _, row in ipairs(rows) do
        local thresholds = RowNeeds(row, ctx)
        local previous = 0
        row.total = 0
        for i, cell in ipairs(row.cells) do
            local need = thresholds[i]
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

-- Decide which row of each sequence shows, as mana bands.
local function UpdateBands()
    for _, group in ipairs(groups) do
        if group.fixed then
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
            -- towards, and the Primary once you can afford everything. With nothing left to
            -- show (all hidden on cooldown), the row closes up.
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
            group.collapsed = #list == 0
        end
    end
    LayoutWindows()
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

local HISTORY = math.max(FLASH_HOLD, MAX_HOLD) + 0.5

local function RecordMana(now, mana)
    samples[#samples + 1] = { time = now, mana = mana }
    while #samples >= 2 and samples[2].time <= now - HISTORY do
        table.remove(samples, 1)
    end
end

-- The mana reading from `seconds` ago (the oldest one kept if there's none that old).
local function ManaAgo(now, seconds)
    for i = #samples, 1, -1 do
        if samples[i].time <= now - seconds then
            return samples[i].mana
        end
    end
    return samples[1].mana
end

-- What the fight is against, from your last living non-friendly target (hostile or neutral):
-- "pvp" (a PvP-flagged unit, or anything a player controls: players, pets, totems, summons),
-- "npc", or "none" (none yet, or it died). Friendly targets, yourself included, never change
-- it. In combat it only moves towards "pvp": re-targeting, or a target dying, during the same
-- fight doesn't switch it back, so windows don't flick on and off. It settles again when
-- combat ends.
local lastEnemy = "none"
local inFight = false

local function Flag(fn, unit)
    local ok, value = pcall(fn, unit)
    if ok and value ~= nil and not IsSecret(value) then
        return value and true or false
    end
    return nil
end

-- "pvp", "npc", "dead", or nil for no target / a friendly one / no answer.
local function TargetKind()
    if not UnitExists("target") then
        return nil
    end
    local ok, canAttack = pcall(UnitCanAttack, "player", "target")
    if not ok or IsSecret(canAttack) or not canAttack then
        return nil
    end
    if Flag(UnitIsDeadOrGhost, "target") then
        return "dead"
    end
    local controlled = Flag(UnitPlayerControlled, "target")
    local flagged = UnitIsPVP and Flag(UnitIsPVP, "target")
    local freeForAll = UnitIsPVPFreeForAll and Flag(UnitIsPVPFreeForAll, "target")
    if controlled == nil and flagged == nil then
        return nil
    end
    return (controlled or flagged or freeForAll) and "pvp" or "npc"
end

local function ReadTarget()
    local kind = TargetKind()
    if not kind then
        return
    end
    if inFight then
        if kind == "pvp" or (kind == "npc" and lastEnemy == "none") then
            lastEnemy = kind
        end
    else
        lastEnemy = kind == "dead" and "none" or kind
    end
end

local function SetInFight(fighting)
    inFight = fighting
    if not fighting then
        -- The fight is over: start again from what you're targeting now.
        local kind = TargetKind()
        lastEnemy = (kind == "pvp" or kind == "npc") and kind or "none"
    end
    ReadTarget()
end

local TARGET_KEYS = { pvp = "pvp", npc = "npcs", none = "none" }

local function FullSwitch(switch)
    switch:SetMinMaxValues(-2, -1)
    switch:SetValue(0)
end

-- Thresholds and target filter for each dynamic window (see GetRoot). Shown regardless
-- while the options are open.
local function UpdateGates(now, mana)
    for _, root in ipairs(roots) do
        local window = root.window
        if window then
            local gates = root.gates
            local used = 0
            if not (editorOpen or root.fixed) then
                if window.healthGate then
                    local maxHealth = UnitHealthMax("player")
                    if IsReadableNumber(maxHealth) and maxHealth > 0 then
                        used = used + 1
                        SetSwitchAt(gates[used], math.ceil(maxHealth * (window.healthPercent or 50) / 100))
                        gates[used]:SetValue(UnitHealth("player") or 0)
                    end
                end
                if window.manaGate then
                    local dearest = 0
                    for _, group in ipairs(root.groups) do
                        dearest = math.max(dearest, group.primary.total)
                        for _, row in ipairs(group.subs) do
                            dearest = math.max(dearest, row.total)
                        end
                    end
                    local threshold = math.ceil(dearest * (1 + (window.manaMargin or 0) / 100))
                    root.manaThreshold = threshold
                    local hold = math.max(0, math.min(MAX_HOLD, math.floor(window.holdSeconds or 0)))
                    for t = 0, hold do
                        used = used + 1
                        SetSwitchAt(gates[used], threshold)
                        gates[used]:SetValue(t == 0 and mana or ManaAgo(now, t))
                    end
                end
            end
            if used == 0 then
                -- Always open: the first switch empty.
                gates[1]:SetMinMaxValues(NEVER - 1, NEVER)
                gates[1]:SetValue(0)
                used = 1
            end
            for i = used + 1, #gates do
                FullSwitch(gates[i])
            end
            root.gatesUsed = used

            local targets = window.targets or {}
            local show = editorOpen or root.fixed or targets[TARGET_KEYS[lastEnemy]] ~= false
            if root.content:IsShown() ~= show then
                root.content:SetShown(show)
            end
        end
    end
end

local function UpdateMana()
    local now = GetTime()
    UpdateThresholds(now)
    UpdateBands()
    local mana = ReadMana()
    RecordMana(now, mana)
    local previous = ManaAgo(now, FLASH_HOLD)
    UpdateGates(now, mana)
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

-- Which placed sequences and sub-sequences have all their spells learned; a change means the
-- windows need rebuilding (a spell was learned, or unlearned by a talent reset).
local learnedSignature = nil

local function LearnedSignature()
    local parts = {}
    for _, window in ipairs(db.windows or {}) do
        for _, item in ipairs(window.items or {}) do
            local def = ns.FindSequence(item.id)
            if def then
                parts[#parts + 1] = ns.AllLearned(def.entries) and "1" or "0"
                for _, sub in ipairs(def.subs) do
                    parts[#parts + 1] = ns.AllLearned(sub.entries) and "1" or "0"
                end
            end
        end
    end
    return table.concat(parts)
end

local function Rebuild()
    if not active then
        return
    end
    learnedSignature = LearnedSignature()
    if InCombatLockdown() then
        if not pendingRebuild then
            Print("the windows will update after combat.")
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

local LoadProfile -- defined with the profiles below

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
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")

-- The target dying counts as no enemy target.
local targetWatcher = CreateFrame("Frame")
targetWatcher:RegisterUnitEvent("UNIT_HEALTH", "target")
targetWatcher:RegisterUnitEvent("UNIT_FLAGS", "target")
targetWatcher:SetScript("OnEvent", function()
    ReadTarget()
end)

-- Times of recent mana updates, for /fseq debug: steady 2s gaps would mean regen in ticks.
local manaEventTimes = {}

driver:SetScript("OnEvent", function(_, event, unit, arg2, arg3)
    if event == "PLAYER_LOGIN" then
        -- SavedVariables are loaded by now: pick this character's profile.
        LoadProfile()
        inFight = InCombatLockdown() and true or false
        active = IsDruid()
        ScanSpellbook()
        ScanBags()
        if active then
            Rebuild()
        end
    elseif not active then
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        SetInFight(true)
        UpdateMana()
    elseif event == "PLAYER_REGEN_ENABLED" then
        SetInFight(false)
        UpdateMana()
        if pendingRebuild then
            Rebuild()
        else
            if pendingVisibility then
                ApplyVisibility()
            end
            if pendingActions then
                pendingActions = false
                Refresh()
            end
            LayoutWindows()
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
    elseif event == "PLAYER_TARGET_CHANGED" then
        ReadTarget()
        UpdateCooldowns()
        UpdateMana()
    elseif event == "UNIT_AURA" then
        UpdateClearcasting()
        UpdateMana()
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        UpdateCooldowns()
        UpdateMana()
    elseif event == "SPELLS_CHANGED" or event == "UPDATE_SHAPESHIFT_FORMS" then
        ScanSpellbook()
        if LearnedSignature() ~= learnedSignature then
            Rebuild()
        end
        Refresh()
        if ns.RefreshEditor then ns.RefreshEditor() end
    elseif event == "BAG_UPDATE_DELAYED" then
        ScanBags()
        Refresh()
        if ns.RefreshEditor then ns.RefreshEditor() end
    else
        Refresh()
    end
end)

----------------------------------------------------------------------------------------------
-- Profiles
----------------------------------------------------------------------------------------------

-- ForeverSequencesDB (account-wide) holds the profiles, each tagged with its class, and each
-- class's default profile. ForeverSequencesCharDB (per character) says which profile this
-- character uses. A character without one (a new character, say) gets its own copy of its
-- class default, window positions and all, so editing it never changes the class default.
local root, charDB, playerClass, className

local function ProfileName(base)
    local name, n = base, 1
    while root.profiles[name] do
        n = n + 1
        name = base .. " " .. n
    end
    return name
end

local function UseProfileTable(name)
    db = root.profiles[name]
    charDB.profile = name
    ns.db = db
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then
            db[key] = value
        end
    end
    MigrateSettings()
end

LoadProfile = function()
    ForeverSequencesDB = ForeverSequencesDB or {}
    ForeverSequencesCharDB = ForeverSequencesCharDB or {}
    root, charDB = ForeverSequencesDB, ForeverSequencesCharDB
    root.profiles = root.profiles or {}
    root.classDefaults = root.classDefaults or {}
    className, playerClass = UnitClass("player")

    -- Settings from before profiles were shared by every character: they become a profile
    -- for whoever logs in first, and a copy becomes the class default.
    if root.windows or root.sequences or root.library then
        local old = {}
        for key, value in pairs(root) do
            if key ~= "profiles" and key ~= "classDefaults" then
                old[key] = value
            end
        end
        for key in pairs(old) do
            root[key] = nil
        end
        old.class = playerClass
        local name = ProfileName("Default")
        root.profiles[name] = old
        charDB.profile = charDB.profile or name
        if not root.classDefaults[playerClass] then
            local defaultName = ProfileName(className .. " class default")
            root.profiles[defaultName] = CopyTable(old)
            root.classDefaults[playerClass] = defaultName
        end
    end

    local current = charDB.profile and root.profiles[charDB.profile]
    if not (current and current.class == playerClass) then
        local base = root.classDefaults[playerClass] and root.profiles[root.classDefaults[playerClass]]
        local name = ProfileName(UnitName("player") .. " - " .. (GetRealmName() or "?"))
        root.profiles[name] = base and CopyTable(base) or { class = playerClass }
        root.profiles[name].class = playerClass
        charDB.profile = name
    end
    UseProfileTable(charDB.profile)
end

function ns.CurrentProfile()
    return charDB.profile
end

function ns.ClassDefault()
    return root.classDefaults[playerClass]
end

-- This class's profiles, sorted.
function ns.ProfileNames()
    local names = {}
    for name, profile in pairs(root.profiles) do
        if profile.class == playerClass then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

local function AfterSwitch()
    if ns.RefreshEditor then
        ns.RefreshEditor()
    end
    Rebuild()
end

function ns.UseProfile(name)
    if root.profiles[name] and root.profiles[name].class == playerClass and name ~= charDB.profile then
        UseProfileTable(name)
        AfterSwitch()
    end
end

-- A copy of the current profile under a new name, and switch to it.
function ns.NewProfile(name)
    name = ProfileName(name ~= "" and name or "Profile")
    root.profiles[name] = CopyTable(db)
    UseProfileTable(name)
    AfterSwitch()
    return name
end

function ns.RenameProfile(name)
    if name == "" or name == charDB.profile then
        return
    end
    name = ProfileName(name)
    local old = charDB.profile
    root.profiles[name], root.profiles[old] = root.profiles[old], nil
    for class, defaultName in pairs(root.classDefaults) do
        if defaultName == old then
            root.classDefaults[class] = name
        end
    end
    charDB.profile = name
    AfterSwitch()
end

-- Delete the current profile and switch to another of this class (or a fresh one).
function ns.DeleteProfile()
    local old = charDB.profile
    root.profiles[old] = nil
    if root.classDefaults[playerClass] == old then
        root.classDefaults[playerClass] = nil
    end
    local others = ns.ProfileNames()
    if others[1] then
        UseProfileTable(others[1])
    else
        local name = ProfileName(UnitName("player") .. " - " .. (GetRealmName() or "?"))
        root.profiles[name] = { class = playerClass }
        UseProfileTable(name)
    end
    AfterSwitch()
end

-- Copy the current profile into this class's default (made if there isn't one yet).
function ns.SaveAsClassDefault()
    local name = root.classDefaults[playerClass]
    if name == charDB.profile then
        return name
    end
    if not (name and root.profiles[name]) then
        name = ProfileName(className .. " class default")
        root.classDefaults[playerClass] = name
    end
    root.profiles[name] = CopyTable(db)
    if ns.RefreshEditor then
        ns.RefreshEditor()
    end
    return name
end

-- Clicking on/off, from the options. Secure buttons only change out of combat.
function ns.SetClickable(value)
    db.clickable = value
    for _, row in ipairs(rows) do
        for _, cell in ipairs(row.cells) do
            cell.actionPending = true
        end
    end
    if InCombatLockdown() then
        pendingActions = true
        Print("clicking will change after combat.")
        return
    end
    Refresh()
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
    local health, maxHealth = UnitHealth("player"), UnitHealthMax("player")
    Print(string.format("health=%s (secret=%s), max health=%s, fighting=%s (in combat=%s)",
        Describe(health), tostring(IsSecret(health)), Describe(maxHealth), lastEnemy, tostring(inFight)))
    if UnitExists("target") then
        local okA, canAttack = pcall(UnitCanAttack, "player", "target")
        Print(string.format("target: can attack=%s, dead=%s, player-controlled=%s, PvP flagged=%s, free-for-all=%s -> %s",
            okA and Describe(canAttack) or "error", Describe(select(2, pcall(UnitIsDeadOrGhost, "target"))),
            Describe(select(2, pcall(UnitPlayerControlled, "target"))),
            UnitIsPVP and Describe(select(2, pcall(UnitIsPVP, "target"))) or "n/a",
            UnitIsPVPFreeForAll and Describe(select(2, pcall(UnitIsPVPFreeForAll, "target"))) or "n/a",
            tostring(TargetKind())))
    end
    Print("mana potions in bags, best first: " .. (#potions > 0 and table.concat(potions, ", ") or "none"))
    for _, root in ipairs(roots) do
        local window = root.window
        if window then
            Print(string.format("window \"%s\": %s, enabled=%s, only in combat=%s, shown=%s",
                window.name or "?", window.type, tostring(window.enabled), tostring(window.onlyInCombat),
                tostring(root:IsShown())))
            if not root.fixed then
                local targets = {}
                for key, on in pairs(window.targets or {}) do
                    if on then targets[#targets + 1] = key end
                end
                table.sort(targets)
                print(string.format("  mana threshold=%s (%s), health threshold=%s (%s%%), hold=%ss, switches used=%s, targets: %s, rows shown for target=%s",
                    tostring(window.manaGate), tostring(root.manaThreshold), tostring(window.healthGate),
                    tostring(window.healthPercent), tostring(window.holdSeconds), tostring(root.gatesUsed),
                    table.concat(targets, ", "), tostring(root.content:IsShown())))
            end
            for _, group in ipairs(root.groups) do
                print(string.format("  \"%s\"%s", group.name, group.collapsed and " (closed up: nothing to show)" or ""))
                local list = { group.primary }
                for _, row in ipairs(group.subs) do
                    list[#list + 1] = row
                end
                for _, row in ipairs(list) do
                    print(string.format("    %s: needs %s, shows from %s to %s, blocked=%s, hide on cooldown=%s",
                        row.label, tostring(row.total),
                        row.low and Band(row.bandLow) or "always", row.low and Band(row.bandHigh) or "always",
                        tostring(row.onCooldown), tostring(row.def.hideOnCooldown and true or false)))
                    for _, cell in ipairs(row.cells) do
                        local info = cell.info or {}
                        print(string.format("       %s: id=%s rank=%s/%s known=%s cost=%s cast=%ss gcd=%ss channel=%ss gain=%s%s instantNext=%s clearcasting=%s, needs %s-%s, cooldown: %s",
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
    end
end

SLASH_FOREVERSEQUENCES1 = "/fseq"
SlashCmdList["FOREVERSEQUENCES"] = function(msg)
    msg = (msg or ""):lower()
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" or cmd == "options" then
        OpenOptions()
    elseif cmd == "reset" then
        ns.ResetPositions()
        Print("window positions reset.")
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
        ns.ResetToDefaults()
        Print("windows and sequences reset to the defaults.")
        if ns.RefreshEditor then ns.RefreshEditor() end
        Rebuild()
    elseif cmd == "debug" then
        PrintDebug()
    else
        Print("/fseq (options) | reset | test | cdtest [spell] | defaults | debug")
    end
end
