-- Forever Sequences: rows of spell icons, one row per sequence. Each icon fills with colour
-- (left to right) as you gain the mana to cast it after everything before it in the row.
--
-- Player mana is a secret value on Forever, so Lua never compares it. Every comparison is
-- done by StatusBars (which accept secret values) and frames that clip to their fill edges:
--
--   fill bar   : range [mana needed before this spell, mana needed up to and including it],
--                value = current mana. Its fill edge is how far the colour icon is revealed.
--   now switch : range [total - 1, total], value = current mana. Empty or full width.
--   prev switch: the same, but its value is the mana reading from FLASH_HOLD seconds ago.
--   highlight  : clipped to "now full" and "prev empty", so it shows for FLASH_HOLD seconds
--                after the mana for this spell arrives, then disappears by itself.

local MANA_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

local ICON_SIZE = 36
local ICON_GAP = 4
local ROW_GAP = 6
local PADDING = 6
local GLOW_SIZE = 3          -- highlight border width, drawn just outside the icon
local FLASH_HOLD = 2.0       -- seconds the highlight stays after a spell becomes affordable
local TICK = 0.05            -- how often mana is re-read
local COST_REFRESH = 1.0     -- how often spell costs are re-read
local TEST_SWEEP_TIME = 15   -- seconds for /fseq test to sweep from no mana to full

local GREY_SHADE = 0.5
local GLOW_COLOR = { 1.0, 0.85, 0.2 }

-- Spell IDs of every rank, lowest first. The highest rank you know is used. Where one spell
-- replaces another (Dire Bear Form replaces Bear Form), the replacement is listed last.
local SPELL_RANKS = {
    ["Regrowth"] = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },
    ["Rejuvenation"] = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 },
    ["Entangling Roots"] = { 339, 1062, 5195, 5196, 9852, 9853 },
    ["Bear Form"] = { 5487, 9634 },
    ["Travel Form"] = { 783 },
}

-- Proof of concept: fixed sequences. These will come from the settings once there's a UI.
local SEQUENCES = {
    { "Regrowth", "Rejuvenation", "Bear Form" },
    { "Entangling Roots", "Rejuvenation", "Travel Form" },
}

ForeverSequencesDB = ForeverSequencesDB or {}
local db = ForeverSequencesDB

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -150,
    locked = false,
}

local function Print(msg)
    print("|cff66ccffForever Sequences:|r " .. msg)
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function IsReadableNumber(value)
    return value ~= nil and not IsSecret(value) and type(value) == "number"
end

local function Describe(value)
    if IsSecret(value) then
        return "secret"
    end
    return tostring(value)
end

----------------------------------------------------------------------------------------------
-- Spells
----------------------------------------------------------------------------------------------

local function KnowsSpell(spellID)
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and known ~= nil and not IsSecret(known) then
            return known and true or false
        end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and known ~= nil and not IsSecret(known) then
            return known and true or false
        end
    end
    return nil
end

-- Returns spellID, known (true / false / nil when the game won't say).
local function ResolveSpell(name)
    local ranks = SPELL_RANKS[name]
    if ranks then
        local anyUnknownAnswer = false
        for i = #ranks, 1, -1 do
            local known = KnowsSpell(ranks[i])
            if known then
                return ranks[i], true
            elseif known == nil then
                anyUnknownAnswer = true
            end
        end
        return ranks[1], (not anyUnknownAnswer) and false or nil
    end

    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and type(info) == "table" and IsReadableNumber(info.spellID) then
            return info.spellID, KnowsSpell(info.spellID)
        end
    end
    return nil, nil
end

-- The spell's mana cost after talents and gear, or nil if there's no readable mana cost.
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
    -- No mana entry: the spell is free.
    return 0
end

local function GetIcon(spellID)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and icon then
            return icon
        end
    end
    return 134400 -- question mark
end

----------------------------------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------------------------------

local root = CreateFrame("Frame", "ForeverSequencesFrame", UIParent, "BackdropTemplate")
root:SetSize(100, 50)
root:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.relativePoint, DEFAULTS.x, DEFAULTS.y)
root:SetMovable(true)
root:SetClampedToScreen(true)
root:RegisterForDrag("LeftButton")
root:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
root:SetBackdropColor(0, 0, 0, 0.4)
root:SetBackdropBorderColor(0.4, 0.8, 1, 0.8)

local unlockedLabel = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
unlockedLabel:SetPoint("BOTTOM", root, "TOP", 0, 2)
unlockedLabel:SetText("Forever Sequences: drag to move, /fseq lock")

local function SavePosition()
    local point, _, relativePoint, x, y = root:GetPoint(1)
    db.point, db.relativePoint, db.x, db.y = point, relativePoint, x, y
end

root:SetScript("OnDragStart", function(self)
    if not db.locked then
        self:StartMoving()
    end
end)
root:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

local function ApplyLock()
    local unlocked = not db.locked
    root:EnableMouse(unlocked)
    unlockedLabel:SetShown(unlocked)
    if unlocked then
        root:SetBackdropColor(0, 0, 0, 0.4)
        root:SetBackdropBorderColor(0.4, 0.8, 1, 0.8)
    else
        root:SetBackdropColor(0, 0, 0, 0)
        root:SetBackdropBorderColor(0, 0, 0, 0)
    end
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

local function CreateCell(row, index)
    local cell = NewFrame("Frame", row.frame)
    cell:SetSize(ICON_SIZE, ICON_SIZE)
    cell:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (index - 1) * (ICON_SIZE + ICON_GAP), 0)

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

    -- Highlight: shown only while "enough now" and "not enough FLASH_HOLD seconds ago".
    local glowArea = NewFrame("Frame", cell)
    glowArea:SetPoint("TOPLEFT", cell, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    glowArea:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
    local nowSwitch = NewSwitch(cell, glowArea)
    local prevSwitch = NewSwitch(cell, glowArea)
    local enoughNow = NewClip(cell, nowSwitch, "LEFT", nowSwitch:GetStatusBarTexture(), "RIGHT")
    local fresh = NewClip(enoughNow, prevSwitch:GetStatusBarTexture(), "RIGHT", prevSwitch, "RIGHT")
    -- Above the colour icon.
    fresh:SetFrameLevel(colorHolder:GetFrameLevel() + 1)
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

    return {
        frame = cell,
        grey = grey,
        color = color,
        fill = fill,
        nowSwitch = nowSwitch,
        prevSwitch = prevSwitch,
        spellID = nil,
        known = nil,
        cost = nil,
        start = 0,
        total = 0,
    }
end

local rows = {}

local function BuildRows()
    local width = 0
    for rowIndex, names in ipairs(SEQUENCES) do
        local rowFrame = NewFrame("Frame", root)
        rowFrame:SetSize(#names * ICON_SIZE + (#names - 1) * ICON_GAP, ICON_SIZE)
        rowFrame:SetPoint("TOPLEFT", root, "TOPLEFT", PADDING, -PADDING - (rowIndex - 1) * (ICON_SIZE + ROW_GAP))
        width = math.max(width, rowFrame:GetWidth())

        local row = { frame = rowFrame, names = names, cells = {} }
        for i, name in ipairs(names) do
            local cell = CreateCell(row, i)
            cell.name = name
            row.cells[i] = cell
        end
        rows[rowIndex] = row
    end
    local height = #SEQUENCES * ICON_SIZE + (#SEQUENCES - 1) * ROW_GAP
    root:SetSize(width + PADDING * 2, height + PADDING * 2)
end

----------------------------------------------------------------------------------------------
-- Updating
----------------------------------------------------------------------------------------------

-- Re-resolve spells and costs, and lay the thresholds out along each row.
local function RefreshCosts()
    for _, row in ipairs(rows) do
        local running = 0
        for _, cell in ipairs(row.cells) do
            local spellID, known = ResolveSpell(cell.name)
            if spellID ~= cell.spellID then
                cell.spellID = spellID
                local icon = GetIcon(spellID)
                cell.grey:SetTexture(icon)
                cell.color:SetTexture(icon)
            end
            cell.known = known
            cell.cost = GetManaCost(spellID)

            cell.start = running
            running = running + (cell.cost or 0)
            cell.total = running

            if cell.total > cell.start then
                cell.fill:SetMinMaxValues(cell.start, cell.total)
            else
                -- Free (or unreadable) spell: all or nothing on the mana before it.
                cell.fill:SetMinMaxValues(cell.start - 1, cell.start)
            end
            cell.nowSwitch:SetMinMaxValues(cell.total - 1, cell.total)
            cell.prevSwitch:SetMinMaxValues(cell.total - 1, cell.total)
        end
    end
end

local function GetHighestTotal()
    local highest = 0
    for _, row in ipairs(rows) do
        local last = row.cells[#row.cells]
        if last and last.total > highest then
            highest = last.total
        end
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
    local mana = ReadMana()
    local previous = PreviousMana(now, mana)
    for _, row in ipairs(rows) do
        for _, cell in ipairs(row.cells) do
            cell.fill:SetValue(mana)
            cell.nowSwitch:SetValue(mana)
            cell.prevSwitch:SetValue(previous)
        end
    end
end

local driver = CreateFrame("Frame")
local tickElapsed, costElapsed = 0, 0
local active = false

driver:SetScript("OnUpdate", function(_, elapsed)
    if not active then
        return
    end
    costElapsed = costElapsed + elapsed
    if costElapsed >= COST_REFRESH then
        costElapsed = 0
        RefreshCosts()
    end
    tickElapsed = tickElapsed + elapsed
    if tickElapsed >= TICK then
        tickElapsed = 0
        UpdateMana()
    end
end)

----------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------

local function IsDruid()
    local _, class = UnitClass("player")
    return class == "DRUID"
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
driver:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
driver:RegisterUnitEvent("UNIT_MAXPOWER", "player")

driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- SavedVariables are loaded by now; pick up the saved table.
        ForeverSequencesDB = ForeverSequencesDB or {}
        db = ForeverSequencesDB
        for key, value in pairs(DEFAULTS) do
            if db[key] == nil then
                db[key] = value
            end
        end
        BuildRows()
        ApplyPosition()
        ApplyLock()
        active = IsDruid()
        root:SetShown(active)
        if active then
            RefreshCosts()
            UpdateMana()
        end
    elseif not active then
        return
    elseif event == "UNIT_POWER_FREQUENT" then
        UpdateMana()
    else
        RefreshCosts()
        UpdateMana()
    end
end)

----------------------------------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------------------------------

local function PrintDebug()
    local mana = UnitPower("player", MANA_POWER_TYPE)
    local maxMana = UnitPowerMax("player", MANA_POWER_TYPE)
    Print(string.format("class druid=%s, mana=%s (secret=%s), max mana=%s, test mode=%s",
        tostring(IsDruid()), Describe(mana), tostring(IsSecret(mana)), Describe(maxMana),
        tostring(testStartTime ~= nil)))
    for rowIndex, row in ipairs(rows) do
        Print("Sequence " .. rowIndex .. ": " .. table.concat(row.names, " > "))
        for _, cell in ipairs(row.cells) do
            local usable, noMana
            if cell.spellID and C_Spell and C_Spell.IsSpellUsable then
                local ok, u, n = pcall(C_Spell.IsSpellUsable, cell.spellID)
                if ok then usable, noMana = u, n end
            end
            local okWidth, fillWidth = pcall(cell.fill:GetStatusBarTexture().GetWidth, cell.fill:GetStatusBarTexture())
            if not okWidth then fillWidth = "error" end
            print(string.format("   %s: id=%s known=%s cost=%s, needs %s-%s, usable=%s noMana=%s, fill width=%s",
                cell.name, tostring(cell.spellID), tostring(cell.known),
                tostring(cell.cost), tostring(cell.start), tostring(cell.total),
                Describe(usable), Describe(noMana), Describe(fillWidth)))
        end
    end
end

SLASH_FOREVERSEQUENCES1 = "/fseq"
SlashCmdList["FOREVERSEQUENCES"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "lock" then
        db.locked = true
        ApplyLock()
        Print("locked.")
    elseif cmd == "unlock" then
        db.locked = false
        ApplyLock()
        Print("unlocked: drag to move.")
    elseif cmd == "reset" then
        for _, key in ipairs({ "point", "relativePoint", "x", "y" }) do
            db[key] = DEFAULTS[key]
        end
        ApplyPosition()
        Print("position reset.")
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
    elseif cmd == "debug" then
        PrintDebug()
    else
        Print("/fseq lock | unlock | reset | test | debug")
    end
end
