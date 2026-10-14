-- Forever Sequences: rows of spell icons. Each icon fills with colour (left to right) as you
-- gain the mana to cast it after everything before it in the row.
--
-- A sequence is a Primary row plus optional sub-sequences (shorter rows made from its spells).
-- Only one of them shows in the sequence's row, chosen by how much mana you have; with
-- "always show Primary" the Primary keeps its row and the best sub-sequence shows below it.
--
-- Player mana is a secret value on Forever, so Lua never compares it. Every comparison is
-- done by StatusBars (which accept secret values) and frames that clip to their fill edges:
--
-- "Mana needed" for a spell counts the regen you'll get before its cost is taken, if you start
-- the sequence now: cast times, the global cooldown and the 5-second rule are all included.
--
--   fill bar   : range [mana needed before this spell, mana needed up to and including it],
--                value = current mana. Its fill edge is how far the colour icon is revealed.
--   now switch : range [total - 1, total], value = current mana. Empty or full width.
--   prev switch: the same, but its value is the mana reading from FLASH_HOLD seconds ago.
--   highlight  : clipped to "now full" and "prev empty", so it shows for FLASH_HOLD seconds
--                after the mana for this spell arrives, then disappears by itself.
--   band       : every candidate row of a sequence sits in the same place, clipped to
--                "mana >= low" and "mana < high". The bands don't overlap, so one row shows.

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
local COST_REFRESH = 1.0     -- how often spell costs and cooldowns are re-read
local TEST_SWEEP_TIME = 15   -- seconds for /fseq test to sweep from no mana to full
local FIVE_SECOND_RULE = 5.0 -- seconds of reduced regen after spending mana
local GLOBAL_COOLDOWN = 1.5  -- seconds before the next spell after an instant
local REGEN_TICK = 2.0       -- seconds between mana ticks in "ticks" regen mode
local TICK_PHASE_STEPS = 20  -- tick timings tried when working out the worst case
local FAKE_COOLDOWN = 10     -- seconds, for /fseq cdtest
local NEVER = 1e9            -- a mana value no one reaches

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

-- Forms are cast as "/cast !Form" so clicking them never shifts you back out.
local FORMS = {
    ["Bear Form"] = true,
    ["Cat Form"] = true,
    ["Travel Form"] = true,
    ["Aquatic Form"] = true,
    ["Moonkin Form"] = true,
}

-- Prototype sequences, in the shape the editor will save. The second one shows its Primary
-- all the time, so both display modes can be tried at once.
local DEFAULT_SEQUENCES = {
    {
        name = "Bear out",
        enabled = true,
        alwaysPrimary = false,
        hideOnCooldown = false,
        spells = { "Regrowth", "Rejuvenation", "Bear Form" },
        subs = {
            { spells = { "Regrowth", "Bear Form" }, hideOnCooldown = false },
            { spells = { "Rejuvenation", "Bear Form" }, hideOnCooldown = false },
        },
    },
    {
        name = "Root and run",
        enabled = true,
        alwaysPrimary = true,
        hideOnCooldown = false,
        spells = { "Entangling Roots", "Rejuvenation", "Travel Form" },
        subs = {
            { spells = { "Entangling Roots", "Travel Form" }, hideOnCooldown = false },
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
    clickable = true,
    clickLog = false,
}

local function CopyTable(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = type(v) == "table" and CopyTable(v) or v
    end
    return copy
end

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

local function GetIcon(spellID)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and icon then
            return icon
        end
    end
    return 134400 -- question mark
end

local function GetSpellName(spellID)
    if spellID and C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and not IsSecret(name) then
            return name
        end
    end
    return nil
end

----------------------------------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------------------------------

local root = CreateFrame("Frame", "ForeverSequencesFrame", UIParent)
root:SetSize(100, 50)
root:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.relativePoint, DEFAULTS.x, DEFAULTS.y)
root:SetMovable(true)
root:SetClampedToScreen(true)

-- While unlocked, a cover over the whole display takes the drags (and the clicks, so you
-- can't cast while moving it).
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
moverLabel:SetText("Forever Sequences: drag to move, /fseq lock")

local function SavePosition()
    local point, _, relativePoint, x, y = root:GetPoint(1)
    db.point, db.relativePoint, db.x, db.y = point, relativePoint, x, y
end

mover:SetScript("OnDragStart", function()
    -- The display holds secure buttons, so it can't move in combat.
    if not InCombatLockdown() then
        root:StartMoving()
    end
end)
mover:SetScript("OnDragStop", function()
    root:StopMovingOrSizing()
    SavePosition()
end)

local function ApplyLock()
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

local buttonCount = 0
local pendingActions = false -- secure attributes waiting for the end of combat

-- What a click does. Secure attributes can only change out of combat.
local function ApplyAction(cell)
    if InCombatLockdown() then
        pendingActions = true
        return
    end
    local name = GetSpellName(cell.spellID)
    if FORMS[cell.spellName] and name then
        cell:SetAttribute("type", "macro")
        cell:SetAttribute("macrotext", "/cast !" .. name)
        cell:SetAttribute("spell", nil)
    else
        cell:SetAttribute("type", "spell")
        cell:SetAttribute("spell", cell.spellID)
        cell:SetAttribute("macrotext", nil)
    end
    cell:EnableMouse(db.clickable)
end

local function CreateCell(row, index, size)
    buttonCount = buttonCount + 1
    local cell = CreateFrame("Button", "ForeverSequencesButton" .. buttonCount, row.frame, "SecureActionButtonTemplate")
    cell:SetFrameLevel(row.frame:GetFrameLevel() + 1)
    cell:SetSize(size, size)
    cell:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (index - 1) * (size + ICON_GAP), 0)
    cell:RegisterForClicks("AnyUp", "AnyDown")
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

    -- Mouse-over highlight, on top of everything.
    local top = NewFrame("Frame", cell)
    top:SetAllPoints(cell)
    top:SetFrameLevel(level + 6)
    local hover = top:CreateTexture(nil, "OVERLAY")
    hover:SetAllPoints(cell)
    hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hover:SetBlendMode("ADD")
    hover:Hide()

    cell:HookScript("OnEnter", function(self)
        hover:Show()
        if self.spellID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end
    end)
    cell:HookScript("OnLeave", function()
        hover:Hide()
        GameTooltip:Hide()
    end)
    cell:HookScript("OnClick", function(self, mouseButton, down)
        if db.clickLog then
            Print(string.format("click (%s %s): %s, row \"%s\" of \"%s\"",
                tostring(mouseButton), down and "down" or "up", self.spellName, row.label, row.group.name))
        end
    end)

    cell.grey = grey
    cell.color = color
    cell.colorClip = colorClip
    cell.fresh = fresh
    cell.fill = fill
    cell.cooldown = cooldown
    cell.nowSwitch = nowSwitch
    cell.prevSwitch = prevSwitch
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
local function CreateRow(group, parent, line, def, size, label)
    local rowFrame = NewFrame("Frame", parent)
    rowFrame:SetPoint("TOPLEFT", line, "TOPLEFT", GLOW_SIZE, -GLOW_SIZE)
    rowFrame:SetSize(LineWidth(#def.spells, size) - GLOW_SIZE * 2, size)
    local row = { frame = rowFrame, group = group, def = def, label = label, cells = {}, total = 0 }
    for i, name in ipairs(def.spells) do
        local cell = CreateCell(row, i, size)
        cell.spellName = name
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
    local row = CreateRow(group, belowHigh, line, def, size, label)
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
        if def.enabled then
            local group = { name = def.name or "?", def = def, subs = {} }
            local subLabel = function(i) return "sub " .. i end

            local mainCount = #def.spells
            if not def.alwaysPrimary then
                for _, sub in ipairs(def.subs or {}) do
                    mainCount = math.max(mainCount, #sub.spells)
                end
            end
            local mainWidth = LineWidth(mainCount, ICON_SIZE)
            local mainHeight = ICON_SIZE + GLOW_SIZE * 2
            local mainLine = NewLine(mainWidth, mainHeight, PADDING - GLOW_SIZE, y + GLOW_SIZE)
            width = math.max(width, mainWidth)
            y = y - ICON_SIZE

            if def.alwaysPrimary then
                group.primary = CreateRow(group, mainLine, mainLine, def, ICON_SIZE, "primary")
                local subCount = 0
                for _, sub in ipairs(def.subs or {}) do
                    subCount = math.max(subCount, #sub.spells)
                end
                if subCount > 0 then
                    -- Its space is always kept: Lua can't tell when the Primary is affordable.
                    local subWidth = LineWidth(subCount, SUB_ICON_SIZE)
                    local subLine = NewLine(subWidth, SUB_ICON_SIZE + GLOW_SIZE * 2,
                        PADDING - GLOW_SIZE + SUB_INDENT, y - ICON_GAP + GLOW_SIZE)
                    width = math.max(width, subWidth + SUB_INDENT)
                    y = y - ICON_GAP - SUB_ICON_SIZE
                    for i, sub in ipairs(def.subs) do
                        group.subs[i] = CreateBandedRow(group, subLine, sub, SUB_ICON_SIZE, subLabel(i))
                    end
                end
            else
                group.primary = CreateBandedRow(group, mainLine, def, ICON_SIZE, "primary")
                for i, sub in ipairs(def.subs or {}) do
                    group.subs[i] = CreateBandedRow(group, mainLine, sub, ICON_SIZE, subLabel(i))
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

-- Re-resolve spells, their costs and cast times.
local function RefreshCosts()
    for _, row in ipairs(rows) do
        for _, cell in ipairs(row.cells) do
            local spellID, known = ResolveSpell(cell.spellName)
            if spellID ~= cell.spellID or cell.actionPending then
                cell.spellID = spellID
                local icon = GetIcon(spellID)
                cell.grey:SetTexture(icon)
                cell.color:SetTexture(icon)
                cell.actionPending = InCombatLockdown()
                ApplyAction(cell)
            end
            cell.known = known
            cell.cost = GetManaCost(spellID)
            cell.castTime = GetCastTime(spellID)
        end
    end
end

-- Whether a spell is on a real cooldown (not just the global one): true / false / nil when
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

    local info
    if cell.spellID and C_Spell and C_Spell.GetSpellCooldown then
        local ok, result = pcall(C_Spell.GetSpellCooldown, cell.spellID)
        if ok and type(result) == "table" then
            info = result
        end
    end
    if not info then
        cell.onCooldown = nil
        cell.cooldownNote = "no answer"
        cooldown:Clear()
        return
    end

    local start, duration = info.startTime, info.duration
    if IsReadableNumber(start) and IsReadableNumber(duration) then
        local onGCD = info.isOnGCD
        local isGCD = (onGCD ~= nil and not IsSecret(onGCD) and onGCD) or duration <= GLOBAL_COOLDOWN
        if start > 0 and duration > 0 and not isGCD then
            if cell.shownStart ~= start or cell.shownDuration ~= duration then
                cooldown:SetCooldown(start, duration, info.modRate)
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
    if C_Spell.GetSpellCooldownDuration and cooldown.SetCooldownFromDurationObject then
        local ok, durationObject = pcall(C_Spell.GetSpellCooldownDuration, cell.spellID)
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
        local onCooldown = false
        for _, cell in ipairs(row.cells) do
            UpdateCellCooldown(cell, now)
            -- Greyed out while on cooldown: no colour, no highlight.
            local alpha = cell.onCooldown and 0 or 1
            cell.colorClip:SetAlpha(alpha)
            cell.fresh:SetAlpha(alpha)
            onCooldown = onCooldown or cell.onCooldown == true
        end
        row.onCooldown = onCooldown
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

-- Length of [0, T] covered by the 5-second-rule windows (each { start, finish }).
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
local function Gain(T, windows, base, casting, phase)
    if T <= 0 then
        return 0
    end
    if phase == nil then
        local inside = TimeInside(windows, T)
        return base * (T - inside) + casting * inside
    end
    local gained = 0
    local t = phase
    while t < T do
        gained = gained + REGEN_TICK * (IsInside(windows, t) and casting or base)
        t = t + REGEN_TICK
    end
    return gained
end

-- Mana thresholds for one row, given the regen model and tick phase: threshold[i] is how much
-- mana you need now to start the sequence and still have the mana for spell i when it's due.
-- Each spell's cost is taken when its cast ends (instants: at once), and the next spell starts
-- when that cast or the global cooldown ends, whichever is later.
local function RowThresholds(row, regen, phase, fsrRemaining, maxMana)
    local base, casting = regen and regen[1], regen and regen[2]
    local windows = {}
    if fsrRemaining > 0 then
        windows[1] = { -math.huge, fsrRemaining }
    end
    local thresholds = {}
    local startTime, totalCost, highest = 0, 0, -math.huge
    local firstGain = nil
    for i, cell in ipairs(row.cells) do
        local cost = cell.cost or 0
        local castTime = cell.castTime or 0
        local due = startTime + castTime
        totalCost = totalCost + cost

        local gain = 0
        if base then
            gain = Gain(due, windows, base, casting, phase)
        end
        firstGain = firstGain or gain

        local need = totalCost - gain
        -- Mana can't go above max, so regen before the first spell is wasted when you're full.
        -- If even full mana isn't enough, the spell can never be reached.
        if maxMana and maxMana - firstGain + gain < totalCost then
            need = maxMana + 1
        end
        highest = math.max(highest, need)
        thresholds[i] = highest

        if cost > 0 then
            windows[#windows + 1] = { due, due + FIVE_SECOND_RULE }
        end
        startTime = startTime + math.max(castTime, GLOBAL_COOLDOWN)
    end
    return thresholds
end


local fsrEndTime = 0

-- Lay the thresholds out along each row. Tick mode takes the worst case over every tick timing.
local function UpdateThresholds(now)
    local regen = nil
    if db.regenMode ~= "off" then
        local base, casting = ReadRegen()
        if base then
            regen = { base, casting }
        end
    end
    local maxMana = UnitPowerMax("player", MANA_POWER_TYPE)
    if not IsReadableNumber(maxMana) or maxMana <= 0 then
        maxMana = nil
    end
    local fsrRemaining = math.max(0, fsrEndTime - now)

    for _, row in ipairs(rows) do
        local thresholds
        if regen and db.regenMode == "ticks" then
            thresholds = {}
            for step = 0, TICK_PHASE_STEPS - 1 do
                local phase = REGEN_TICK * step / TICK_PHASE_STEPS
                for i, need in ipairs(RowThresholds(row, regen, phase, fsrRemaining, maxMana)) do
                    thresholds[i] = math.max(thresholds[i] or -math.huge, need)
                end
            end
        else
            thresholds = RowThresholds(row, regen, nil, fsrRemaining, maxMana)
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
                -- Free spell: all or nothing on the mana before it.
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
-- their spells is on cooldown.
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
        UpdateCooldowns()
    end
    tickElapsed = tickElapsed + elapsed
    if tickElapsed >= TICK then
        tickElapsed = 0
        UpdateMana()
    end
end)

local function Refresh()
    RefreshCosts()
    UpdateCooldowns()
    UpdateMana()
end

-- Rebuilding moves and hides secure buttons, so it waits for the end of combat.
local pendingRebuild = false

local function Rebuild()
    if InCombatLockdown() then
        pendingRebuild = true
        Print("will update after combat.")
        return
    end
    pendingRebuild = false
    BuildDisplay()
    wipe(samples)
    Refresh()
end

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
driver:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
driver:RegisterEvent("SPELL_UPDATE_COOLDOWN")
driver:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
driver:RegisterUnitEvent("UNIT_MAXPOWER", "player")
driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

-- Times of recent mana updates, for /fseq debug: steady 2s gaps mean Forever regens in ticks.
local manaEventTimes = {}

driver:SetScript("OnEvent", function(_, event, unit, arg2, arg3)
    if event == "PLAYER_LOGIN" then
        -- SavedVariables are loaded by now; pick up the saved table.
        ForeverSequencesDB = ForeverSequencesDB or {}
        db = ForeverSequencesDB
        for key, value in pairs(DEFAULTS) do
            if db[key] == nil then
                db[key] = value
            end
        end
        if type(db.sequences) ~= "table" then
            db.sequences = CopyTable(DEFAULT_SEQUENCES)
        end
        ApplyPosition()
        ApplyLock()
        active = IsDruid()
        root:SetShown(active)
        if active then
            Rebuild()
        end
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
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        UpdateCooldowns()
        UpdateMana()
    else
        Refresh()
    end
end)

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
    Print(string.format("class druid=%s, mana=%s (secret=%s), max mana=%s, test mode=%s, clickable=%s, in combat=%s",
        tostring(IsDruid()), Describe(mana), tostring(IsSecret(mana)), Describe(maxMana),
        tostring(testStartTime ~= nil), tostring(db.clickable), tostring(InCombatLockdown())))
    local okRegen, base, casting = pcall(GetManaRegen)
    if not okRegen then base, casting = "error", "error" end
    local gaps = {}
    for i = 2, #manaEventTimes do
        gaps[#gaps + 1] = string.format("%.2f", manaEventTimes[i] - manaEventTimes[i - 1])
    end
    Print(string.format("regen mode=%s, regen/s outside 5SR=%s, inside=%s, 5SR left=%.1fs, mana update gaps: %s",
        db.regenMode, Describe(base), Describe(casting), math.max(0, fsrEndTime - GetTime()),
        #gaps > 0 and table.concat(gaps, " ") or "none yet"))
    for _, group in ipairs(groups) do
        Print(string.format("\"%s\": always show Primary=%s", group.name, tostring(group.def.alwaysPrimary and true or false)))
        local list = { group.primary }
        for _, row in ipairs(group.subs) do
            list[#list + 1] = row
        end
        for _, row in ipairs(list) do
            print(string.format("  %s: %s, needs %s, shows from %s to %s, on cooldown=%s, hide on cooldown=%s",
                row.label, table.concat(row.def.spells, " > "), tostring(row.total),
                row.low and Band(row.bandLow) or "always", row.low and Band(row.bandHigh) or "always",
                tostring(row.onCooldown), tostring(row.def.hideOnCooldown and true or false)))
            for _, cell in ipairs(row.cells) do
                local usable, noMana
                if cell.spellID and C_Spell and C_Spell.IsSpellUsable then
                    local ok, u, n = pcall(C_Spell.IsSpellUsable, cell.spellID)
                    if ok then usable, noMana = u, n end
                end
                print(string.format("     %s: id=%s known=%s cost=%s cast=%ss, needs %s-%s, usable=%s noMana=%s, cooldown: %s",
                    cell.spellName, tostring(cell.spellID), tostring(cell.known),
                    tostring(cell.cost), tostring(cell.castTime), tostring(cell.start), tostring(cell.total),
                    Describe(usable), Describe(noMana), tostring(cell.cooldownNote)))
            end
        end
    end
end

-- Toggle a flag on every sequence (prototype: until the editor exists).
local function ToggleAll(key, includeSubs)
    if not db.sequences[1] then
        return false
    end
    local value = not db.sequences[1][key]
    for _, def in ipairs(db.sequences) do
        def[key] = value
        if includeSubs then
            for _, sub in ipairs(def.subs or {}) do
                sub[key] = value
            end
        end
    end
    return value
end

local function OnOff(value)
    return value and "on" or "off"
end

SLASH_FOREVERSEQUENCES1 = "/fseq"
SlashCmdList["FOREVERSEQUENCES"] = function(msg)
    msg = (msg or ""):lower()
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
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
    elseif cmd == "regen" then
        if arg == "ticks" or arg == "smooth" or arg == "off" then
            db.regenMode = arg
            if active then
                UpdateMana()
            end
            Print("regen mode: " .. arg .. ".")
        else
            Print("regen mode is " .. db.regenMode .. ". /fseq regen ticks | smooth | off")
        end
    elseif cmd == "click" then
        if InCombatLockdown() then
            Print("can't change that in combat.")
            return
        end
        if arg == "on" or arg == "off" then
            db.clickable = arg == "on"
        else
            db.clickable = not db.clickable
        end
        Refresh()
        for _, row in ipairs(rows) do
            for _, cell in ipairs(row.cells) do
                cell:EnableMouse(db.clickable)
            end
        end
        Print("clicking to cast " .. OnOff(db.clickable) .. ".")
    elseif cmd == "clicklog" then
        db.clickLog = not db.clickLog
        Print("click log " .. OnOff(db.clickLog) .. ".")
    elseif cmd == "primary" then
        Print("always show Primary " .. OnOff(ToggleAll("alwaysPrimary", false)) .. " for every sequence.")
        Rebuild()
    elseif cmd == "hidecd" then
        Print("hide on cooldown " .. OnOff(ToggleAll("hideOnCooldown", true)) .. " for every sequence and sub-sequence.")
        if active then
            UpdateMana()
        end
    elseif cmd == "cdtest" then
        local target = arg ~= "" and arg or "rejuvenation"
        local count = 0
        local ends = GetTime() + FAKE_COOLDOWN
        for _, row in ipairs(rows) do
            for _, cell in ipairs(row.cells) do
                if cell.spellName:lower() == target then
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
        Rebuild()
    elseif cmd == "debug" then
        PrintDebug()
    else
        Print("/fseq lock | unlock | reset | test | regen | click [on|off] | clicklog | primary | hidecd | cdtest [spell] | defaults | debug")
    end
end
