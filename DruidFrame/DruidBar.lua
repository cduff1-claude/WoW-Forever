-- Shared with Resource.lua (the resource display) through the addon namespace.
local _, ns = ...
local MANA_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local FIVE_SECOND_RULE = 5.0
local FSR_UPDATE_INTERVAL = 0.05

-- Cat Form, Bear Form and Dire Bear Form. All share the same mana cost, so whichever
-- the player knows is used to read the current (talent/item-modified) shift cost.
local SHIFT_COST_SPELLS = {
    [768] = true,  -- Cat Form
    [5487] = true, -- Bear Form
    [9634] = true, -- Dire Bear Form
}
local SHIFT_COST_SPELL_ORDER = { 768, 9634, 5487 }

-- Travel Form and Aquatic Form share a cost, so whichever the player knows sets the
-- "escape form" (red) threshold. Travel first, then Aquatic.
local ESCAPE_FORM_SPELLS = {
    { id = 783, name = "Travel Form" },
    { id = 1066, name = "Aquatic Form" },
}

-- Bear and Dire Bear share form ID 5.
local TRACKED_FORMS = {
    [1] = true, -- Cat Form
    [3] = true, -- Travel Form
    [4] = true, -- Aquatic Form
    [5] = true, -- Bear / Dire Bear Form
}

-- Saved variables keep the old name (DruidForeverManabarPlusDB) so settings carry over.
DruidForeverManabarPlusDB = DruidForeverManabarPlusDB or {}

local DEFAULTS = {
    -- Player Frame features: off by default, DruidFrame's resource display replaces them.
    enablePlayerFrame = false,      -- druid bar under the Player Frame + caster shading on its mana bar
    useAquaticCost = true,          -- use Aquatic Form's cost for the travel section if Travel isn't known
    clawShade = true,               -- Cat Form: energy bars turn orange when you can't afford Claw
    -- 5-second-rule marker on Blizzard's own mana bars (what ForeverFiveSecondRule used to do)
    fsrPlayerFrame = false,         -- the Player Frame mana bar, while it shows mana
    fsrText = true,                 -- countdown number beside the marker
    fsrWidth = 2,                   -- marker width in pixels (1-6)
    resource = {},                  -- the resource display's own settings (Resource.lua fills them in)
    settingsVersion = 0,
}

-- Fixed look of the druid bar.
local BAR_COLOR_R, BAR_COLOR_G, BAR_COLOR_B = 0.0, 0.4, 0.85
local BAR_WIDTH_FALLBACK, BAR_HEIGHT = 124, 10
local FALLBACK_FONT, FALLBACK_FONT_SIZE = "Fonts\\ARIALN.TTF", 10

local function EnsureDB()
    -- Drop settings from older versions that no longer exist.
    for key in pairs(DruidForeverManabarPlusDB) do
        if DEFAULTS[key] == nil then
            DruidForeverManabarPlusDB[key] = nil
        end
    end
    for key, value in pairs(DEFAULTS) do
        if DruidForeverManabarPlusDB[key] == nil then
            DruidForeverManabarPlusDB[key] = value
        end
    end
    -- Version 1 (DruidFrame): stop touching the Player Frame (the resource display replaces it).
    local db = DruidForeverManabarPlusDB
    if db.settingsVersion < 1 then
        db.settingsVersion = 1
        db.enablePlayerFrame = false
        db.fsrPlayerFrame = false
    end
    return db
end

local db = EnsureDB()

local manaFrame = CreateFrame("Frame", "DruidForeverManabarPlusMainFrame", UIParent, "BackdropTemplate")
manaFrame:SetSize(BAR_WIDTH_FALLBACK, BAR_HEIGHT)
manaFrame:EnableMouse(true)

manaFrame:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
})
manaFrame:SetBackdropBorderColor(0.08, 0.08, 0.10, 0.95)

local background = manaFrame:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints(manaFrame)
background:SetColorTexture(0, 0, 0, 0.6)

local manaBar = CreateFrame("StatusBar", nil, manaFrame)
manaBar:SetAllPoints(manaFrame)
manaBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
manaBar:SetStatusBarColor(BAR_COLOR_R, BAR_COLOR_G, BAR_COLOR_B, 1)
manaBar:SetMinMaxValues(0, 1)
manaBar:SetValue(0)

-- Shade over the part of the filled bar that a Bear/Cat shift would spend, split into a
-- Travel Form section [0 .. travel cost] and a Bear section [travel cost .. bear cost].
--
--                                         | travel section | bear section
--   enough for bear, even after the cast  | blue           | blue
--   cast -> below bear (above travel)     | blue           | pale orange
--   cast -> below travel                  | pale red       | (unshaded)
--   below bear now, cast stays >= travel  | pale yellow    | bold orange
--   below bear now, cast -> below travel  | grey           | (unshaded)
--   below travel now                      | dark red       | (empty, fill ends before it)
--
-- Without Travel Form (or with its cost unknown) the travel section is empty and the bear
-- section uses only blue / pale orange / bold orange.
--
-- The client does not let addons read mana values (they come back "secret"), so nothing
-- here compares mana in Lua. StatusBar widgets, which accept secret values, do the work and
-- everything else is anchored to the right edges of their fill textures:
--
--   step bars : invisible. Range [threshold - 1, threshold], value = current mana, so the
--               fill is either empty (mana below threshold) or full-width (at/above it).
--               nowT / castT = travel cost (+ current cast), nowB / castB = bear cost (+ cast).
--   edge bars : invisible. value = travel cost / bear cost over max mana; their fill edges
--               mark where the sections end.
--   clips     : frames that clip their children. A clip from the bar's left edge to a step
--               bar's edge is full-width when there is enough mana and empty otherwise; a
--               clip from a step bar's edge to the bar's right edge is the opposite. Nesting
--               clips intersects them, so exactly one colour layer shows in each section.
local function CreateInvisibleBar(set, bar)
    local statusBar = CreateFrame("StatusBar", nil, bar)
    statusBar:SetAllPoints(bar)
    statusBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    statusBar:SetStatusBarColor(0, 0, 0, 0)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(1)
    set.tree[#set.tree + 1] = { frame = statusBar, parent = bar }
    set.topLevel[#set.topLevel + 1] = statusBar
    return statusBar
end

local function CreateClip(set, parent, left, leftPoint, right, rightPoint)
    local clip = CreateFrame("Frame", nil, parent)
    clip:SetClipsChildren(true)
    clip:SetPoint("TOPLEFT", left, "TOP" .. leftPoint, 0, 0)
    clip:SetPoint("BOTTOMRIGHT", right, "BOTTOM" .. rightPoint, 0, 0)
    set.tree[#set.tree + 1] = { frame = clip, parent = parent }
    return clip
end

-- A full-bar texture inside a clip; only the part inside the clip is drawn.
local function CreateLayer(set, clip, role)
    local holder = CreateFrame("Frame", nil, clip)
    holder:SetAllPoints(set.bar)
    set.tree[#set.tree + 1] = { frame = holder, parent = clip }

    local texture = holder:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(set.bar)
    texture:SetTexture(set.texturePath)
    set.layers[#set.layers + 1] = { texture = texture, role = role }
    return texture
end

local function CreateShiftShade(bar, texturePath)
    local set = { bar = bar, texturePath = texturePath, tree = {}, topLevel = {}, layers = {} }

    set.nowT = CreateInvisibleBar(set, bar)
    set.castT = CreateInvisibleBar(set, bar)
    set.nowB = CreateInvisibleBar(set, bar)
    set.castB = CreateInvisibleBar(set, bar)
    set.travelEdge = CreateInvisibleBar(set, bar)
    set.bearEdge = CreateInvisibleBar(set, bar)

    local nowT = set.nowT:GetStatusBarTexture()
    local castT = set.castT:GetStatusBarTexture()
    local nowB = set.nowB:GetStatusBarTexture()
    local castB = set.castB:GetStatusBarTexture()
    local travelEdge = set.travelEdge:GetStatusBarTexture()
    local bearEdge = set.bearEdge:GetStatusBarTexture()
    set.bearEdgeTexture = bearEdge

    -- Everything is clipped to the current mana fill (anchored in AnchorShiftShade).
    set.fillClip = CreateFrame("Frame", nil, bar)
    set.fillClip:SetClipsChildren(true)
    set.tree[#set.tree + 1] = { frame = set.fillClip, parent = bar }
    set.topLevel[#set.topLevel + 1] = set.fillClip

    -- Travel section. Above travel after the cast: blue if mana is at/above bear cost now,
    -- pale yellow if below it. Above travel now but not after the cast: pale red if at/above
    -- bear cost now, grey if below it. Below travel now: dark red.
    local travel = CreateClip(set, set.fillClip, bar, "LEFT", travelEdge, "RIGHT")
    local travelAfterCast = CreateClip(set, travel, bar, "LEFT", castT, "RIGHT")
    CreateLayer(set, CreateClip(set, travelAfterCast, bar, "LEFT", nowB, "RIGHT"), "blue")
    CreateLayer(set, CreateClip(set, travelAfterCast, nowB, "RIGHT", bar, "RIGHT"), "paleYellow")
    local travelCastBelow = CreateClip(set, travel, castT, "RIGHT", nowT, "RIGHT")
    CreateLayer(set, CreateClip(set, travelCastBelow, bar, "LEFT", nowB, "RIGHT"), "paleRed")
    CreateLayer(set, CreateClip(set, travelCastBelow, nowB, "RIGHT", bar, "RIGHT"), "grey")
    CreateLayer(set, CreateClip(set, travel, nowT, "RIGHT", bar, "RIGHT"), "darkRed")

    -- Bear section.
    local bear = CreateClip(set, set.fillClip, travelEdge, "RIGHT", bearEdge, "RIGHT")
    local aboveTravelAfterCast = CreateClip(set, bear, bar, "LEFT", castT, "RIGHT")
    CreateLayer(set, CreateClip(set, aboveTravelAfterCast, bar, "LEFT", castB, "RIGHT"), "blue")
    CreateLayer(set, CreateClip(set, aboveTravelAfterCast, castB, "RIGHT", nowB, "RIGHT"), "paleOrange")
    CreateLayer(set, CreateClip(set, aboveTravelAfterCast, nowB, "RIGHT", bar, "RIGHT"), "boldOrange")
    -- When the cast would take mana below the travel cost, the bear section is left unshaded.

    return set
end

-- (Re)anchor to the bar's fill and put the pieces above it. Called again for the Player
-- Frame bar because Blizzard may swap the fill texture when the power type changes.
local function AnchorShiftShade(set)
    local bar = set.bar
    local strata = bar:GetFrameStrata()

    set.fillClip:ClearAllPoints()
    set.fillClip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    set.fillClip:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)

    -- Entries are in creation order, so each parent is levelled before its children.
    for _, entry in ipairs(set.tree) do
        entry.frame:SetFrameStrata(strata)
        entry.frame:SetFrameLevel(entry.parent:GetFrameLevel() + 1)
    end
end

local function ShowShiftShade(set, shown)
    for _, frame in ipairs(set.topLevel) do
        frame:SetShown(shown)
    end
end

local druidShade = CreateShiftShade(manaBar, "Interface\\TargetingFrame\\UI-StatusBar")
AnchorShiftShade(druidShade)
ShowShiftShade(druidShade, false)

-- Text and markers live on their own frame so they draw above the shift shade.
local overlayFrame = CreateFrame("Frame", nil, manaFrame)
overlayFrame:SetAllPoints(manaFrame)
overlayFrame:SetFrameLevel(manaBar:GetFrameLevel() + 5)

local manaText = overlayFrame:CreateFontString(nil, "OVERLAY")
manaText:SetPoint("CENTER", manaBar, "CENTER", 0, 0)

local fsrMarker = overlayFrame:CreateTexture(nil, "OVERLAY", nil, 7)
fsrMarker:SetColorTexture(1, 1, 1, 0.95)
fsrMarker:SetWidth(2)
fsrMarker:SetHeight(BAR_HEIGHT + 4)
fsrMarker:Hide()

-- Shade colours. Orange = Bear/Cat cost, red = Travel/Aquatic Form cost; pale = the current cast
-- will take mana below that cost, bold/dark = already below it.
local DRUID_BAR_COLORS = {
    paleYellow = { 1.0, 0.95, 0.6, 1 },
    grey = { 0.6, 0.6, 0.6, 1 },
    paleOrange = { 1.0, 0.8, 0.55, 1 },
    boldOrange = { 1.0, 0.55, 0.1, 1 },
    paleRed = { 1.0, 0.66, 0.66, 1 },
    darkRed = { 0.85, 0.25, 0.25, 1 },
}
-- The Player Frame bar uses Blizzard's own texture, so it gets translucent washes that blend
-- with the blue underneath.
local PLAYER_FRAME_COLORS = {
    blue = { 1.0, 1.0, 1.0, 0.3 },
    paleYellow = { 1.0, 0.95, 0.4, 0.75 },
    grey = { 0.55, 0.55, 0.55, 0.85 },
    paleOrange = { 1.0, 0.55, 0.1, 0.75 },
    boldOrange = { 1.0, 0.4, 0.0, 0.92 },
    paleRed = { 1.0, 0.45, 0.45, 0.7 },
    darkRed = { 0.7, 0.05, 0.05, 0.92 },
}

-- Overlays on the Player Frame's mana bar and DruidFrame's own bars, keyed by bar.
local blizzardOverlays = {}

-- Cat Form energy shading for Claw. Kept in one table to save top-level locals; the
-- functions are filled in further down.
-- 5-second-rule markers on Blizzard's mana bars; filled in further down.
local FSR = { targets = {}, elapsed = 0 }

-- Colours measured from the Player Frame's bars in game. Its bar art darkens towards the
-- left, so these come from the brighter right-hand part. Rage was only seen at 10% (the
-- dark left end, 153/255 red), so its value is an estimate between that and Blizzard's 252.
-- The resource display (Resource.lua) uses these.
local Look = {
    COLOURS = {
        HEALTH = { 0.40, 0.73, 0.17 },
        MANA = { 0.00, 0.34, 0.73 },
        -- Energy: the user preferred the paler yellow the old Claw wash gave (white at 35%
        -- over the Player Frame yellow 1.00 1.00 0.23), so the whole bar uses that.
        ENERGY = { 1.00, 1.00, 0.50 },
        RAGE = { 0.75, 0.00, 0.00 },
    } }
ns.COLOURS = Look.COLOURS
-- Called by Resource.lua when its bars are shown or hidden; filled in below UpdateFormState.
ns.OverlaysChanged = nil

local Claw = {
    POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3,
    SPELLS = { 9850, 9849, 5201, 3029, 1082 }, -- Claw ranks, highest first
    cost = nil,
    spellID = nil,
    overlays = {}, -- keyed by bar
    -- Washes over Blizzard's yellow energy texture: "enough" = you have the energy for
    -- Claw, "short" = you don't yet (the whole fill is then inside the Claw section).
    COLORS = {
        enough = { 1.0, 1.0, 1.0, 0 }, -- no shading while you have the energy for Claw
        short = { 1.0, 0.5, 0.0, 0.9 },
    },
}

local function ColorShiftShade(set, colors, shown)
    for _, layer in ipairs(set.layers) do
        local c = colors[layer.role]
        layer.texture:SetVertexColor(c[1], c[2], c[3], shown and c[4] or 0)
    end
end

local function ApplyShiftShadeColor()
    local shown = true

    -- Lighten the configured bar colour towards white.
    local lighten = 0.45
    DRUID_BAR_COLORS.blue = {
        BAR_COLOR_R + (1 - BAR_COLOR_R) * lighten,
        BAR_COLOR_G + (1 - BAR_COLOR_G) * lighten,
        BAR_COLOR_B + (1 - BAR_COLOR_B) * lighten,
        1,
    }
    ColorShiftShade(druidShade, DRUID_BAR_COLORS, shown)

    for _, overlay in pairs(blizzardOverlays) do
        ColorShiftShade(overlay.shade, PLAYER_FRAME_COLORS, shown)
    end
end

ApplyShiftShadeColor()

local isDruid = false
ns.IsDruid = function() return isDruid end
local fsrEndTime = 0
local pendingManaCasts = {}
local lastManaSpellID = nil
local fsrUpdateFrame = CreateFrame("Frame")
local fsrUpdateElapsed = 0

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value) or false
end

local function IsTrackedForm(formID)
    return formID ~= nil and TRACKED_FORMS[formID] == true
end

local function GetPlayerResourceBar()
    if PlayerFrame then
        local content = PlayerFrame.PlayerFrameContent
        local main = content and content.PlayerFrameContentMain
        local manaArea = main and main.ManaBarArea
        local resourceBar = manaArea and manaArea.ManaBar

        if resourceBar and resourceBar.GetObjectType then
            return resourceBar
        end
    end

    if PlayerFrameManaBar and PlayerFrameManaBar.GetObjectType then
        return PlayerFrameManaBar
    end
end

-- The druid bar's text copies the Player Frame mana bar's font, scaled by how much
-- shorter the druid bar is than that bar.
local function GetPlayerManaTextFont(resourceBar)
    if not resourceBar then
        return nil
    end
    for _, key in ipairs({ "TextString", "ManaBarText", "LeftText", "RightText" }) do
        local fontString = resourceBar[key]
        if fontString and fontString.GetFont then
            local path, size, flags = fontString:GetFont()
            if path and size and size > 0 then
                return path, size, flags
            end
        end
    end
    if PlayerFrameManaBarText and PlayerFrameManaBarText.GetFont then
        local path, size, flags = PlayerFrameManaBarText:GetFont()
        if path and size and size > 0 then
            return path, size, flags
        end
    end
end

local function ApplyFont()
    local resourceBar = GetPlayerResourceBar()
    local path, size, flags = GetPlayerManaTextFont(resourceBar)

    if path then
        local barHeight = resourceBar:GetHeight()
        local ratio = (barHeight and barHeight > 0) and (manaFrame:GetHeight() / barHeight) or 1
        size = math.max(6, math.floor(size * math.min(ratio, 1) + 0.5))
    else
        path, size, flags = FALLBACK_FONT, FALLBACK_FONT_SIZE, ""
    end

    manaText:SetFont(path, size, flags or "")
    manaText:SetTextColor(1, 1, 1, 1)
    manaText:SetShadowColor(0, 0, 0, 0.9)
    manaText:SetShadowOffset(1, -1)
end

-- Always attached directly under the Player Frame's mana bar.
local function ApplyAnchor()
    manaFrame:ClearAllPoints()

    if PlayerFrame then
        local resourceBar = GetPlayerResourceBar()

        manaFrame:SetParent(PlayerFrame)
        manaFrame:SetScale(1)
        manaFrame:SetHeight(BAR_HEIGHT)

        if resourceBar then
            -- Match the real Blizzard power bar instead of relying on fixed PlayerFrame offsets.
            manaFrame:SetPoint("TOPLEFT", resourceBar, "BOTTOMLEFT", 0, 0)
            manaFrame:SetPoint("TOPRIGHT", resourceBar, "BOTTOMRIGHT", 0, 0)
        else
            -- Fallback for beta builds where the resource-bar hierarchy changes.
            manaFrame:SetWidth(BAR_WIDTH_FALLBACK)
            manaFrame:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 85, -74)
        end
    else
        manaFrame:SetParent(UIParent)
        manaFrame:SetSize(BAR_WIDTH_FALLBACK, BAR_HEIGHT)
        manaFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end

    fsrMarker:SetHeight(manaFrame:GetHeight() + 4)

    -- Re-layer after reparenting so the shade stays between the bar and the text.
    AnchorShiftShade(druidShade)
    overlayFrame:SetFrameStrata(manaBar:GetFrameStrata())
    overlayFrame:SetFrameLevel(manaBar:GetFrameLevel() + 5)

    ApplyFont()
end

local function HideFiveSecondRuleVisual()
    fsrMarker:Hide()
    fsrUpdateFrame:SetScript("OnUpdate", nil)
    fsrUpdateElapsed = 0
end

local function StopFiveSecondRule()
    fsrEndTime = 0
    HideFiveSecondRuleVisual()
end

local function UpdateFiveSecondRuleVisual()
    if fsrEndTime <= 0 then
        StopFiveSecondRule()
        return
    end

    local remaining = fsrEndTime - GetTime()
    if remaining <= 0 then
        StopFiveSecondRule()
        return
    end

    if not manaFrame:IsShown() then
        HideFiveSecondRuleVisual()
        return
    end

    local elapsed = FIVE_SECOND_RULE - remaining
    local progress = elapsed / FIVE_SECOND_RULE
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end

    local markerWidth = fsrMarker:GetWidth() or 2
    local usableWidth = math.max(0, manaBar:GetWidth() - markerWidth)
    local x = (markerWidth / 2) + (progress * usableWidth)

    fsrMarker:ClearAllPoints()
    fsrMarker:SetPoint("CENTER", manaBar, "LEFT", x, 0)
    fsrMarker:Show()
end

local function OnFiveSecondRuleUpdate(_, elapsed)
    fsrUpdateElapsed = fsrUpdateElapsed + elapsed
    if fsrUpdateElapsed < FSR_UPDATE_INTERVAL then
        return
    end

    fsrUpdateElapsed = 0
    UpdateFiveSecondRuleVisual()
end

local function ResumeFiveSecondRuleVisual()
    if fsrEndTime > GetTime() and manaFrame:IsShown() then
        fsrUpdateElapsed = 0
        UpdateFiveSecondRuleVisual()
        fsrUpdateFrame:SetScript("OnUpdate", OnFiveSecondRuleUpdate)
    elseif fsrEndTime > 0 and fsrEndTime <= GetTime() then
        StopFiveSecondRule()
    end
end

local function StartFiveSecondRule()
    fsrEndTime = GetTime() + FIVE_SECOND_RULE
    if FSR.Refresh then
        FSR.Refresh()
    end

    if manaFrame:IsShown() then
        fsrUpdateElapsed = 0
        UpdateFiveSecondRuleVisual()
        fsrUpdateFrame:SetScript("OnUpdate", OnFiveSecondRuleUpdate)
    else
        HideFiveSecondRuleVisual()
    end
end

local function GetManaPercent(currentMana, maxMana)
    -- Avoid direct arithmetic when power values are restricted.
    if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, manaPercent = pcall(UnitPowerPercent, "player", MANA_POWER_TYPE, false, CurveConstants.ScaleTo100)
        if ok then
            return true, manaPercent
        end
    end

    if not IsSecretValue(currentMana) and not IsSecretValue(maxMana) and maxMana and maxMana > 0 then
        return true, (currentMana / maxMana) * 100
    end

    return false, nil
end

-- Follows the Player Frame's status text setting (Options > Interface > Status Text):
-- NONE, NUMERIC, PERCENT or BOTH.
local function GetStatusTextFormat()
    local value = GetCVar and GetCVar("statusTextDisplay")
    value = value and value:upper() or "BOTH"
    if value == "NONE" then return "none" end
    if value == "NUMERIC" then return "numeric" end
    if value == "PERCENT" then return "percent" end
    return "both"
end

local function SetManaText(currentMana, maxMana)
    local format = GetStatusTextFormat()

    if format == "none" then
        manaText:SetText("")
        return
    end

    if format == "numeric" then
        manaText:SetFormattedText("%s / %s", currentMana, maxMana)
        return
    end

    local hasPercent, manaPercent = GetManaPercent(currentMana, maxMana)
    if hasPercent then
        if format == "percent" then
            manaText:SetFormattedText("%.0f%%", manaPercent)
        else
            manaText:SetFormattedText("%s / %s (%.0f%%)", currentMana, maxMana, manaPercent)
        end
    else
        manaText:SetText("Mana")
    end
end

local shiftCost = nil
local shiftCostSpellID = nil

local function GetManaCostFromSpell(spellID)
    if not (C_Spell and C_Spell.GetSpellPowerCost) then
        return nil
    end

    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then
        return nil
    end

    for _, costInfo in ipairs(costs) do
        local powerType = costInfo.type
        local powerName = costInfo.name

        local isMana = false
        if powerType ~= nil and not IsSecretValue(powerType) then
            isMana = (powerType == MANA_POWER_TYPE)
        end
        if not isMana and powerName ~= nil and not IsSecretValue(powerName) then
            isMana = (powerName == "MANA")
        end

        -- "cost" is the final cost after talents (e.g. Natural Shapeshifter) and items.
        if isMana and costInfo.cost ~= nil then
            return costInfo.cost
        end
    end

    return nil
end

local function PlayerKnowsSpell(spellID)
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and known then
            return true
        end
    end
    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, spellID)
        if ok and known then
            return true
        end
    end
    return false
end

local function FindShiftCostSpells()
    local found = {}

    -- Prefer the forms actually on the player's stance bar.
    if GetNumShapeshiftForms and GetShapeshiftFormInfo then
        for index = 1, GetNumShapeshiftForms() or 0 do
            local _, _, _, spellID = GetShapeshiftFormInfo(index)
            if spellID and not IsSecretValue(spellID) and SHIFT_COST_SPELLS[spellID] then
                found[#found + 1] = spellID
            end
        end
    end

    for _, spellID in ipairs(SHIFT_COST_SPELL_ORDER) do
        if PlayerKnowsSpell(spellID) then
            found[#found + 1] = spellID
        end
    end

    return found
end

local travelCost = nil
local travelCostOverride = nil -- set with /druidbar testtravel, for testing without Travel Form

local function IsReadableNumber(value)
    return type(value) == "number" and not IsSecretValue(value)
end

local travelCostSource = nil

local function PlayerHasForm(formSpellID)
    if GetNumShapeshiftForms and GetShapeshiftFormInfo then
        for index = 1, GetNumShapeshiftForms() or 0 do
            local _, _, _, spellID = GetShapeshiftFormInfo(index)
            if spellID == formSpellID then
                return true
            end
        end
    end
    return PlayerKnowsSpell(formSpellID)
end

local function RefreshTravelCost()
    travelCost = nil
    travelCostSource = nil

    if travelCostOverride then
        travelCost = travelCostOverride
        travelCostSource = "test override"
    elseif isDruid then
        for _, form in ipairs(ESCAPE_FORM_SPELLS) do
            local allowed = form.id ~= 1066 or db.useAquaticCost
            if allowed and PlayerHasForm(form.id) then
                local cost = GetManaCostFromSpell(form.id)
                if IsReadableNumber(cost) and cost > 0 then
                    travelCost = cost
                    travelCostSource = form.name
                    break
                end
            end
        end
    end

    -- Only useful when it is cheaper than a Bear/Cat shift.
    if travelCost and IsReadableNumber(shiftCost) and travelCost >= shiftCost then
        travelCost = nil
        travelCostSource = nil
    end
end

local function RefreshShiftCost()
    shiftCost = nil
    shiftCostSpellID = nil
    Claw.Refresh()

    if not isDruid then
        travelCost = nil
        return
    end

    for _, spellID in ipairs(FindShiftCostSpells()) do
        local cost = GetManaCostFromSpell(spellID)
        if cost ~= nil then
            -- A readable zero cost means "not usable"; keep looking for a better source.
            if IsSecretValue(cost) or cost > 0 then
                shiftCost = cost
                shiftCostSpellID = spellID
                break
            end
        end
    end

    RefreshTravelCost()
end

-- Copies of the shift-cost shade/line on other mana bars: the Player Frame bar whenever it
-- shows mana (if enabled), and DruidFrame's mana bar. They share the translucent
-- PLAYER_FRAME_COLORS washes.
local function EnsureBarOverlay(bar)
    local overlay = blizzardOverlays[bar]
    if overlay then
        return overlay
    end

    overlay = { bar = bar, active = false }
    overlay.shade = CreateShiftShade(bar, "Interface\\Buttons\\WHITE8X8")

    ShowShiftShade(overlay.shade, false)
    ColorShiftShade(overlay.shade, PLAYER_FRAME_COLORS, true)

    blizzardOverlays[bar] = overlay
    return overlay
end

local function SetBarOverlayActive(overlay, active)
    overlay.active = active
    if active then
        AnchorShiftShade(overlay.shade)
    else
        ShowShiftShade(overlay.shade, false)
    end
end

local RefreshBlizzardOverlays
local UpdateManaBarLater

local function PrimaryPowerIsMana()
    local powerType = UnitPowerType("player")
    if powerType == nil or IsSecretValue(powerType) then
        return nil
    end
    return powerType == MANA_POWER_TYPE
end

local function PlayerFrameBarShowsMana()
    local powerType = UnitPowerType("player")
    if powerType == nil or IsSecretValue(powerType) then
        return false
    end
    return powerType == MANA_POWER_TYPE
end

-- Work out which Blizzard bars should carry an overlay right now. reanchor = true forces
-- active overlays to re-anchor (after Blizzard repaints a bar).
RefreshBlizzardOverlays = function(reanchor)
    local wanted = {}

    if isDruid and db.enablePlayerFrame and PlayerFrameBarShowsMana() then
        local resourceBar = GetPlayerResourceBar()
        if resourceBar and resourceBar.GetStatusBarTexture then
            wanted[resourceBar] = true
        end
    end

    -- The resource display's mana bar (Resource.lua), while it's shown.
    local ownMana = isDruid and ns.Resource and ns.Resource.ManaBar()
    if ownMana then
        wanted[ownMana] = true
    end

    for bar in pairs(wanted) do
        local overlay = EnsureBarOverlay(bar)
        if reanchor or not overlay.active then
            SetBarOverlayActive(overlay, true)
        end
    end
    for bar, overlay in pairs(blizzardOverlays) do
        if overlay.active and not wanted[bar] then
            SetBarOverlayActive(overlay, false)
        end
    end

    if Claw.RefreshOverlays then
        Claw.RefreshOverlays(reanchor)
    end
end

local function CountActiveOverlays()
    local count = 0
    for _, overlay in pairs(blizzardOverlays) do
        if overlay.active then count = count + 1 end
    end
    for _, overlay in pairs(Claw.overlays) do
        if overlay.active then count = count + 1 end
    end
    return count
end

-- Cat Form: shade the part of the energy bar that Claw costs, on DruidFrame's energy bar and
-- (if enabled) the Player Frame's power bar. Energy
-- is secret like mana, so this uses the same step bar / clip trick as the shift shade:
--   step : range [cost - 1, cost], value = energy, so it is full-width with enough energy.
--   edge : value = cost over max energy; its fill edge marks the end of the Claw section.
-- "enough" (transparent, kept for symmetry) sits in the section left of the step bar's edge;
-- "short" covers the whole current fill right of it, so it only shows when you're short.
function Claw.GetCost(spell)
    if not (C_Spell and C_Spell.GetSpellPowerCost) then
        return nil
    end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spell)
    if not ok or type(costs) ~= "table" then
        return nil
    end
    for _, costInfo in ipairs(costs) do
        local powerType, powerName = costInfo.type, costInfo.name
        local isEnergy = false
        if powerType ~= nil and not IsSecretValue(powerType) then
            isEnergy = (powerType == Claw.POWER_TYPE)
        end
        if not isEnergy and powerName ~= nil and not IsSecretValue(powerName) then
            isEnergy = (powerName == "ENERGY")
        end
        if isEnergy and IsReadableNumber(costInfo.cost) and costInfo.cost > 0 then
            return costInfo.cost
        end
    end
    return nil
end

function Claw.Refresh()
    Claw.cost = nil
    Claw.spellID = nil
    if not isDruid then
        return
    end
    for _, spellID in ipairs(Claw.SPELLS) do
        if PlayerKnowsSpell(spellID) then
            local cost = Claw.GetCost(spellID)
            if cost then
                Claw.cost, Claw.spellID = cost, spellID
                return
            end
        end
    end
    -- Fall back to the spell name, in case Forever's rank IDs differ.
    local cost = Claw.GetCost("Claw")
    if cost then
        Claw.cost, Claw.spellID = cost, "Claw"
    end
end

function Claw.CreateShade(bar)
    local set = { bar = bar, texturePath = "Interface\\Buttons\\WHITE8X8", tree = {}, topLevel = {}, layers = {} }

    set.step = CreateInvisibleBar(set, bar)
    set.edge = CreateInvisibleBar(set, bar)
    local step = set.step:GetStatusBarTexture()
    local edge = set.edge:GetStatusBarTexture()

    set.fillClip = CreateFrame("Frame", nil, bar)
    set.fillClip:SetClipsChildren(true)
    set.tree[#set.tree + 1] = { frame = set.fillClip, parent = bar }
    set.topLevel[#set.topLevel + 1] = set.fillClip

    local section = CreateClip(set, set.fillClip, bar, "LEFT", edge, "RIGHT")
    CreateLayer(set, CreateClip(set, section, bar, "LEFT", step, "RIGHT"), "enough")
    -- Short of energy: the whole fill, not just the Claw section. Blizzard eases its bars
    -- down after you spend energy, so for a moment its fill is longer than your energy;
    -- covering all of it keeps that lingering part orange too. (Setting Blizzard's bar
    -- value ourselves instead taints its text code, which then errors on secret values.)
    CreateLayer(set, CreateClip(set, set.fillClip, step, "RIGHT", bar, "RIGHT"), "short")

    return set
end

function Claw.ShowsEnergy()
    local powerType = UnitPowerType("player")
    if powerType == nil or IsSecretValue(powerType) then
        return false
    end
    return powerType == Claw.POWER_TYPE
end

-- Like RefreshBlizzardOverlays, for the energy bars. Called from it.
function Claw.RefreshOverlays(reanchor)
    local wanted = {}

    if isDruid and db.clawShade and Claw.cost and Claw.ShowsEnergy() then
        if db.enablePlayerFrame then
            local bar = GetPlayerResourceBar()
            if bar and bar.GetStatusBarTexture then
                wanted[bar] = true
            end
        end
        local ownEnergy = ns.Resource and ns.Resource.EnergyBar()
        if ownEnergy then
            wanted[ownEnergy] = true
        end
    end

    for bar in pairs(wanted) do
        local overlay = Claw.overlays[bar]
        if not overlay then
            overlay = { bar = bar, shade = Claw.CreateShade(bar), active = false }
            ShowShiftShade(overlay.shade, false)
            ColorShiftShade(overlay.shade, Claw.COLORS, true)
            Claw.overlays[bar] = overlay
        end
        if reanchor or not overlay.active then
            overlay.active = true
            AnchorShiftShade(overlay.shade)
        end
    end
    for bar, overlay in pairs(Claw.overlays) do
        if overlay.active and not wanted[bar] then
            overlay.active = false
            ShowShiftShade(overlay.shade, false)
        end
    end
end

function Claw.Update()
    if not next(Claw.overlays) then
        return
    end
    local maxEnergy = UnitPowerMax("player", Claw.POWER_TYPE)
    local energy = UnitPower("player", Claw.POWER_TYPE)
    local usable = Claw.cost and IsReadableNumber(maxEnergy) and maxEnergy > 0

    for _, overlay in pairs(Claw.overlays) do
        local shade = overlay.shade
        if overlay.active and usable then
            shade.edge:SetMinMaxValues(0, maxEnergy)
            shade.edge:SetValue(Claw.cost)
            shade.step:SetMinMaxValues(Claw.cost - 1, Claw.cost)
            shade.step:SetValue(energy)
            ShowShiftShade(shade, true)
        else
            ShowShiftShade(shade, false)
        end
    end
end

-- 5-second-rule markers on Blizzard's own mana bars (merged in from ForeverFiveSecondRule):
-- DruidFrame's mana bar, and (if enabled) the Player Frame mana bar while it shows mana.
-- They follow the same timer as the druid bar's
-- marker (fsrEndTime), and only tick while there is a timer and a bar to draw on.
FSR.frame = CreateFrame("Frame")

function FSR.GetTarget(bar)
    local target = FSR.targets[bar]
    if target then
        return target
    end
    local frame = CreateFrame("Frame", nil, bar)
    frame:SetAllPoints(bar)
    frame:Hide()
    local marker = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    marker:SetColorTexture(1, 1, 1, 0.95)
    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\ARIALN.TTF", 10, "")
    text:SetTextColor(1, 1, 1, 1)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    text:SetPoint("LEFT", frame, "RIGHT", 3, 0)
    target = { frame = frame, marker = marker, text = text }
    FSR.targets[bar] = target
    return target
end

function FSR.WantedBars()
    local bars = {}
    if not isDruid then
        return bars
    end
    local powerType = UnitPowerType("player")
    if powerType == nil or IsSecretValue(powerType) then
        return bars
    end
    local primaryIsMana = (powerType == MANA_POWER_TYPE)
    if db.fsrPlayerFrame and primaryIsMana then
        local bar = GetPlayerResourceBar()
        if bar then
            bars[#bars + 1] = bar
        end
    end
    local ownMana = ns.Resource and ns.Resource.ManaBar()
    if ownMana then
        bars[#bars + 1] = ownMana
    end
    return bars
end

function FSR.Stop()
    FSR.frame:SetScript("OnUpdate", nil)
    for _, target in pairs(FSR.targets) do
        target.frame:Hide()
    end
end

function FSR.Update()
    local remaining = fsrEndTime - GetTime()
    local wanted = remaining > 0 and FSR.WantedBars() or {}
    if #wanted == 0 then
        -- Timer over, or no mana bar to draw on (e.g. mid-shift). A form change or a new
        -- timer calls FSR.Refresh again.
        FSR.Stop()
        return
    end

    local progress = math.min(1, math.max(0, (FIVE_SECOND_RULE - remaining) / FIVE_SECOND_RULE))
    local width = db.fsrWidth or 2
    local shown = {}
    for _, bar in ipairs(wanted) do
        local target = FSR.GetTarget(bar)
        shown[target] = true
        -- Keep above the bar's own text and spark.
        target.frame:SetFrameStrata(bar:GetFrameStrata())
        target.frame:SetFrameLevel(bar:GetFrameLevel() + 10)
        target.frame:Show()
        target.marker:SetWidth(width)
        target.marker:SetHeight(target.frame:GetHeight() + 4)
        local x = (width / 2) + progress * math.max(0, target.frame:GetWidth() - width)
        target.marker:ClearAllPoints()
        target.marker:SetPoint("CENTER", target.frame, "LEFT", x, 0)
        if db.fsrText then
            target.text:SetText(string.format("%.1f", remaining))
            target.text:Show()
        else
            target.text:Hide()
        end
    end
    for _, target in pairs(FSR.targets) do
        if not shown[target] then
            target.frame:Hide()
        end
    end
end

function FSR.Refresh()
    FSR.Update()
    if fsrEndTime > GetTime() and #FSR.WantedBars() > 0 then
        FSR.elapsed = 0
        FSR.frame:SetScript("OnUpdate", function(_, elapsed)
            FSR.elapsed = FSR.elapsed + elapsed
            if FSR.elapsed >= FSR_UPDATE_INTERVAL then
                FSR.elapsed = 0
                FSR.Update()
            end
        end)
    end
end


-- Mana cost of the spell currently being cast, like the darker "cost prediction" section
-- Blizzard draws on the Player Frame bar while casting.
local pendingCastCost = 0
local pendingCastGUID = nil

-- Mana needed after the current cast for the shade to stay blue. Needs a readable shift
-- cost to add to; if the cost itself is restricted, returns nil and the shade stays blue.
local function GetShiftThreshold()
    if not IsReadableNumber(shiftCost) then
        return nil
    end
    return shiftCost + pendingCastCost
end

local function SetStep(step, threshold, currentMana)
    if threshold then
        step:SetMinMaxValues(threshold - 1, threshold)
        step:SetValue(currentMana)
    else
        -- No readable threshold: always "enough mana", so the shade stays blue.
        step:SetMinMaxValues(0, 1)
        step:SetValue(1)
    end
end

local function UpdateShiftShade(set, maxMana, currentMana, threshold)
    set.bearEdge:SetMinMaxValues(0, maxMana)
    set.bearEdge:SetValue(shiftCost)
    set.travelEdge:SetMinMaxValues(0, maxMana)
    set.travelEdge:SetValue(travelCost or 0)

    SetStep(set.nowB, threshold and shiftCost, currentMana)
    SetStep(set.castB, threshold, currentMana)
    SetStep(set.nowT, travelCost, currentMana)
    SetStep(set.castT, travelCost and (travelCost + pendingCastCost), currentMana)

    ShowShiftShade(set, true)
end

local function UpdateShiftCostVisual(maxMana, currentMana)
    if shiftCost == nil then
        ShowShiftShade(druidShade, false)
        for _, overlay in pairs(blizzardOverlays) do
            ShowShiftShade(overlay.shade, false)
        end
        return
    end

    local threshold = GetShiftThreshold()

    UpdateShiftShade(druidShade, maxMana, currentMana, threshold)

    for _, overlay in pairs(blizzardOverlays) do
        if overlay.active then
            UpdateShiftShade(overlay.shade, maxMana, currentMana, threshold)
        else
            ShowShiftShade(overlay.shade, false)
        end
    end
end

local function UpdateManaBar()
    if not isDruid then
        return
    end

    local maxMana = UnitPowerMax("player", MANA_POWER_TYPE)
    local currentMana = UnitPower("player", MANA_POWER_TYPE)

    manaBar:SetMinMaxValues(0, maxMana)
    manaBar:SetValue(currentMana)
    SetManaText(currentMana, maxMana)
    UpdateShiftCostVisual(maxMana, currentMana)
    Claw.Update()
end

-- Deferred a frame, so it runs after Blizzard has finished updating its bars.
local updateQueued = false
UpdateManaBarLater = function()
    if updateQueued then
        return
    end
    updateQueued = true
    C_Timer.After(0, function()
        updateQueued = false
        UpdateManaBar()
    end)
end

local function SetPendingCast(castGUID, spellID)
    pendingCastGUID = castGUID
    pendingCastCost = 0
    if spellID ~= nil and not IsSecretValue(spellID) then
        local cost = GetManaCostFromSpell(spellID)
        if IsReadableNumber(cost) and cost > 0 then
            pendingCastCost = cost
        end
    end
    UpdateManaBar()
end

local function ClearPendingCast(castGUID)
    if pendingCastCost == 0 and pendingCastGUID == nil then
        return
    end
    -- Ignore failures for a different cast attempt (e.g. pressing a spell mid-cast).
    if castGUID ~= nil and pendingCastGUID ~= nil and not IsSecretValue(castGUID)
        and not IsSecretValue(pendingCastGUID) and castGUID ~= pendingCastGUID then
        return
    end
    pendingCastGUID = nil
    pendingCastCost = 0
    UpdateManaBar()
end

local function HasPositiveReadableValue(value)
    return value ~= nil and not IsSecretValue(value) and value > 0
end

local function SpellSpendsMana(spellID)
    if spellID == nil or IsSecretValue(spellID) then
        return false
    end

    if not (C_Spell and C_Spell.GetSpellPowerCost) then
        return false
    end

    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then
        return false
    end

    for _, costInfo in ipairs(costs) do
        local powerType = costInfo.type
        local powerName = costInfo.name

        local isMana = false
        if powerType ~= nil and not IsSecretValue(powerType) then
            isMana = (powerType == MANA_POWER_TYPE)
        end
        if not isMana and powerName ~= nil and not IsSecretValue(powerName) then
            isMana = (powerName == "MANA")
        end

        if isMana then
            if HasPositiveReadableValue(costInfo.cost)
                or HasPositiveReadableValue(costInfo.minCost)
                or HasPositiveReadableValue(costInfo.costPercent)
                or HasPositiveReadableValue(costInfo.costPerSec) then
                return true
            end
        end
    end

    return false
end

-- Cat and Bear switch the primary power away from mana, so a non-mana power type also
-- means "in a tracked form". This helps when the form ID lags behind the real form.
local function PrimaryPowerIsNotMana()
    local powerType = UnitPowerType("player")
    if powerType == nil or IsSecretValue(powerType) then
        return false
    end
    return powerType ~= MANA_POWER_TYPE
end

local function UpdateFormState()
    -- The resource display first, so its bars are laid out before the overlays look for them.
    if ns.Resource then
        ns.Resource.Refresh()
    end
    local formID = GetShapeshiftFormID()
    local tracked = isDruid and (IsTrackedForm(formID) or PrimaryPowerIsNotMana())
    local shouldShow = isDruid and db.enablePlayerFrame and tracked

    RefreshBlizzardOverlays()

    if shouldShow then
        manaFrame:Show()
        ApplyAnchor()
    else
        manaFrame:Hide()
        HideFiveSecondRuleVisual()
    end

    if isDruid then
        RefreshShiftCost()
        UpdateManaBar()
    end

    if shouldShow then
        ResumeFiveSecondRuleVisual()
    else
        manaText:ClearText()
    end
    FSR.Refresh()
end

ns.OverlaysChanged = function()
    RefreshBlizzardOverlays(true)
    UpdateManaBar()
    FSR.Refresh()
end

-- Form watcher.
--
-- On Forever, re-casting the current form (e.g. "/cast !Cat Form" in Cat to break roots)
-- drops to caster and back, and the client's form state can lag the server by a few
-- seconds. The last UPDATE_SHAPESHIFT_FORM may arrive while the client still reports
-- caster, with no event when the form ID later settles. So also poll the cheap form/power
-- readings a few times a second and refresh whenever they change.
local FORM_POLL_INTERVAL = 0.1
local formWatcher = CreateFrame("Frame")
local formPollElapsed = 0
local overlayRescanElapsed = 0
local OVERLAY_RESCAN_INTERVAL = 1.0
local lastFormSignature = nil

local function GetFormSignature()
    local powerType = UnitPowerType("player")
    if IsSecretValue(powerType) then
        powerType = "secret"
    end
    return tostring(GetShapeshiftFormID()) .. ":" .. tostring(powerType)
end

-- /druidbar formlog: print every change in the form-related readings, with timings, so we can
-- see which signal updates first after a shift.
local formLogEnabled = false
local formLogStart = 0
local lastFormLogLine = nil

local function FormAuraName()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return "n/a"
    end
    local names = { [768] = "Cat", [5487] = "Bear", [9634] = "DireBear", [783] = "Travel", [1066] = "Aquatic" }
    for spellID, name in pairs(names) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and aura then
            return name
        end
    end
    return "none"
end

local function LogFormReadings(source)
    if not formLogEnabled then
        return
    end
    local powerID, powerToken = UnitPowerType("player")
    if IsSecretValue(powerID) then powerID = "secret" end
    if IsSecretValue(powerToken) then powerToken = "secret" end
    local bonusBar = GetBonusBarOffset and GetBonusBarOffset() or "n/a"
    local line = string.format("formID=%s stance=%s bonusbar=%s power=%s(%s) aura=%s shown=%s",
        tostring(GetShapeshiftFormID()), tostring(GetShapeshiftForm()), tostring(bonusBar),
        tostring(powerID), tostring(powerToken), FormAuraName(), tostring(manaFrame:IsShown()))
    if line == lastFormLogLine and source == "poll" then
        return
    end
    lastFormLogLine = line
    local now = GetTime()
    if formLogStart == 0 or now - formLogStart > 10 then
        formLogStart = now
    end
    print(string.format("|cff55ff55DFMP|r +%.2fs [%s] %s", now - formLogStart, source, line))
end

formWatcher:SetScript("OnUpdate", function(_, elapsed)
    formPollElapsed = formPollElapsed + elapsed
    if formPollElapsed < FORM_POLL_INTERVAL then
        return
    end
    formPollElapsed = 0

    if not isDruid then
        return
    end

    local signature = GetFormSignature()
    if signature ~= lastFormSignature then
        lastFormSignature = signature
        overlayRescanElapsed = 0
        UpdateFormState()
    else
        -- Blizzard can swap the Player Frame's bar texture without a form change, so look
        -- for the bars again now and then.
        overlayRescanElapsed = overlayRescanElapsed + FORM_POLL_INTERVAL
        if overlayRescanElapsed >= OVERLAY_RESCAN_INTERVAL then
            overlayRescanElapsed = 0
            local before = CountActiveOverlays()
            RefreshBlizzardOverlays()
            if CountActiveOverlays() ~= before then
                UpdateManaBar()
            end
        end
    end
    LogFormReadings("poll")
end)

local OpenOptions

manaFrame:SetScript("OnMouseDown", function(_, button)
    if button == "RightButton" and OpenOptions then
        OpenOptions()
    end
end)

manaFrame:RegisterEvent("PLAYER_LOGIN")
manaFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
manaFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
manaFrame:RegisterEvent("UNIT_DISPLAYPOWER")
manaFrame:RegisterEvent("UNIT_POWER_UPDATE")
manaFrame:RegisterEvent("UNIT_POWER_FREQUENT")
manaFrame:RegisterEvent("UNIT_MAXPOWER")
manaFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
manaFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
manaFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
manaFrame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
manaFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
manaFrame:RegisterEvent("UNIT_SPELLCAST_START")
manaFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
-- Events that can change the Cat/Bear shift cost (talents, gear, level, learning a form).
manaFrame:RegisterEvent("SPELLS_CHANGED")
manaFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
manaFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
manaFrame:RegisterEvent("PLAYER_LEVEL_UP")
-- The Player Frame's status text setting, which the druid bar's text follows.
manaFrame:RegisterEvent("CVAR_UPDATE")
pcall(manaFrame.RegisterEvent, manaFrame, "PLAYER_TALENT_UPDATE")
pcall(manaFrame.RegisterEvent, manaFrame, "CHARACTER_POINTS_CHANGED")

manaFrame:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
    if event == "PLAYER_LOGIN" then
        -- SavedVariables are loaded after this file runs, so re-read them here.
        db = EnsureDB()

        local _, classFile = UnitClass("player")
        isDruid = (classFile == "DRUID")

        manaBar:SetStatusBarColor(BAR_COLOR_R, BAR_COLOR_G, BAR_COLOR_B, 1)
        ApplyShiftShadeColor()
        ApplyAnchor()

        UpdateFormState()

        if isDruid then
            print("|cff00ff00DruidFrame loaded.|r Type |cffffffff/druidframe|r for options.")
        end
        return
    end

    if not isDruid then
        manaFrame:Hide()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        wipe(pendingManaCasts)
        pendingCastGUID = nil
        pendingCastCost = 0
        ApplyAnchor()
        UpdateFormState()
        return
    end

    if event == "UPDATE_SHAPESHIFT_FORM" or (event == "UNIT_DISPLAYPOWER" and unit == "player") then
        lastFormSignature = GetFormSignature()
        UpdateFormState()
        LogFormReadings(event)
        return
    end

    if event == "CVAR_UPDATE" then
        UpdateManaBar()
        return
    end

    if event == "SPELLS_CHANGED"
        or event == "UPDATE_SHAPESHIFT_FORMS"
        or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "PLAYER_LEVEL_UP"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "CHARACTER_POINTS_CHANGED" then
        RefreshShiftCost()
        UpdateManaBar()
        return
    end

    if unit ~= "player" then
        return
    end

    if event == "UNIT_SPELLCAST_START" then
        SetPendingCast(arg2, arg3)
        return
    end

    if event == "UNIT_SPELLCAST_STOP" then
        ClearPendingCast(arg2)
        return
    end

    if event == "UNIT_SPELLCAST_SENT" then
        local castGUID = arg3
        local spellID = arg4
        if castGUID ~= nil and not IsSecretValue(castGUID) then
            pendingManaCasts[castGUID] = SpellSpendsMana(spellID)
        end
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local castGUID = arg2
        local spellID = arg3
        local spendsMana = nil

        if castGUID ~= nil and not IsSecretValue(castGUID) then
            spendsMana = pendingManaCasts[castGUID]
            pendingManaCasts[castGUID] = nil
        end

        if spendsMana == nil then
            spendsMana = SpellSpendsMana(spellID)
        end

        ClearPendingCast(castGUID)

        if spendsMana then
            lastManaSpellID = spellID
            StartFiveSecondRule()
        end
        return
    end

    if event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local castGUID = arg2
        if castGUID ~= nil and not IsSecretValue(castGUID) then
            pendingManaCasts[castGUID] = nil
        end
        ClearPendingCast(castGUID)
        return
    end

    local powerType = arg2
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
        if powerType == "MANA" then
            UpdateManaBar()
        elseif powerType == "ENERGY" then
            Claw.Update()
        end
    elseif event == "UNIT_MAXPOWER" then
        if powerType == nil or powerType == "MANA" then
            UpdateManaBar()
        elseif powerType == "ENERGY" then
            Claw.Update()
        end
    end
end)

manaFrame:Hide()

local panel = CreateFrame("Frame", "DruidForeverManabarPlusOptionsPanel", UIParent)
panel.name = "DruidBar"
panel:SetSize(460, 490)


-- Registered by Options.lua as a page under DruidFrame.
ns.panels = ns.panels or {}
ns.panels.bar = panel
OpenOptions = function()
    if ns.OpenOptions then
        ns.OpenOptions("bar")
    end
end

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("DruidBar")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetText("The Player Frame parts (off by default; DruidFrame's display replaces them). /druidbar opens this page.")

local function CreateCheckbox(name, anchor, label, key)
    local checkbox = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    _G[name .. "Text"]:SetText(label)
    checkbox:SetChecked(db[key])
    checkbox:SetScript("OnClick", function(self)
        db[key] = self:GetChecked() and true or false
        UpdateFormState()
    end)
    return checkbox
end

local playerFrameCheckbox = CreateCheckbox("DFMPPlayerFrameCheckbox", subtitle,
    "Druid mana bar under the Player Frame in forms, and shift-cost shading on its mana bar", "enablePlayerFrame")

local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
local aquaticCheckbox = CreateCheckbox("DFMPAquaticCheckbox", playerFrameCheckbox,
    "Use Aquatic Form's cost for the travel section when Travel Form isn't learned", "useAquaticCost")

local clawCheckbox = CreateCheckbox("DFMPClawCheckbox", aquaticCheckbox,
    "Turn energy bars orange in Cat Form when you can't afford Claw (DruidFrame's, and the Player Frame's if on)",
    "clawShade")

local fsrHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
fsrHeader:SetPoint("TOPLEFT", clawCheckbox, "BOTTOMLEFT", 0, -16)
fsrHeader:SetText("5-second rule marker (always on DruidFrame's mana bar)")
local fsrPlayerCheckbox = CreateCheckbox("DFMPFsrPlayerCheckbox", fsrHeader,
    "Also show it on the Player Frame mana bar (caster form)", "fsrPlayerFrame")
local fsrTextCheckbox = CreateCheckbox("DFMPFsrTextCheckbox", fsrPlayerCheckbox,
    "Show the countdown number", "fsrText")

local fsrWidthSlider = CreateFrame("Slider", "DFMPFsrWidthSlider", panel, "OptionsSliderTemplate")
fsrWidthSlider:SetPoint("TOPLEFT", fsrTextCheckbox, "BOTTOMLEFT", 4, -26)
fsrWidthSlider:SetWidth(200)
fsrWidthSlider:SetMinMaxValues(1, 6)
fsrWidthSlider:SetValueStep(1)
fsrWidthSlider:SetObeyStepOnDrag(true)
_G[fsrWidthSlider:GetName() .. "Low"]:SetText("1")
_G[fsrWidthSlider:GetName() .. "High"]:SetText("6")
fsrWidthSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value + 0.5)
    db.fsrWidth = value
    _G[fsrWidthSlider:GetName() .. "Text"]:SetText("Marker width: " .. value)
    FSR.Refresh()
end)

note:SetPoint("TOPLEFT", fsrWidthSlider, "BOTTOMLEFT", -4, -24)
note:SetWidth(420)
note:SetJustifyH("LEFT")
note:SetText("The mana text follows the Player Frame's Status Text setting (Options > Interface).")

panel:SetScript("OnShow", function()
    playerFrameCheckbox:SetChecked(db.enablePlayerFrame)
    aquaticCheckbox:SetChecked(db.useAquaticCost)
    clawCheckbox:SetChecked(db.clawShade)
    fsrPlayerCheckbox:SetChecked(db.fsrPlayerFrame)
    fsrTextCheckbox:SetChecked(db.fsrText)
    fsrWidthSlider:SetValue(db.fsrWidth or 2)
end)

-- Unlock DruidFrame's bars while any of its pages is open.
panel:HookScript("OnShow", function() if ns.PageShown then ns.PageShown(true) end end)
panel:HookScript("OnHide", function() if ns.PageShown then ns.PageShown(false) end end)

local function PrintDebugInfo()
    local version, build, _, tocVersion = GetBuildInfo()
    local formID = GetShapeshiftFormID()
    local powerID, powerToken = UnitPowerType("player")
    local currentMana = UnitPower("player", MANA_POWER_TYPE)
    local maxMana = UnitPowerMax("player", MANA_POWER_TYPE)
    local manaIsSecret = IsSecretValue(currentMana)
    local remaining = math.max(0, fsrEndTime - GetTime())

    print("|cff55ff55DruidBar debug|r")
    print("Client:", tostring(version), "build", tostring(build), "TOC", tostring(tocVersion))
    print("Form ID:", tostring(formID), "tracked:", tostring(IsTrackedForm(formID)))
    print("Primary power:", tostring(powerID), tostring(powerToken))
    local resourceBar = GetPlayerResourceBar()
    print("Snap target:", resourceBar and (resourceBar.GetDebugName and resourceBar:GetDebugName() or tostring(resourceBar)) or "fallback PlayerFrame offset")
    print("Mana secret:", tostring(manaIsSecret), "max mana:", tostring(maxMana))
    if not manaIsSecret then
        print("Current mana:", tostring(currentMana))
    end
    print("5SR remaining:", string.format("%.2f", remaining),
        "| Player Frame marker:", tostring(db.fsrPlayerFrame),
        "bars now:", tostring(#FSR.WantedBars()))
    RefreshShiftCost()
    if shiftCost == nil then
        print("Shift cost: not found (no Cat/Bear Form mana cost available)")
    elseif IsSecretValue(shiftCost) then
        print("Shift cost: restricted value, spell ID", tostring(shiftCostSpellID))
    else
        print("Shift cost:", tostring(shiftCost), "mana, from spell ID", tostring(shiftCostSpellID))
    end
    print("Blizzard bar overlays active:", tostring(CountActiveOverlays()), "Player Frame bar shows mana:", tostring(PlayerFrameBarShowsMana()))
    local threshold = GetShiftThreshold()
    print("Bear threshold (incl. cast):", threshold and tostring(threshold) or "unavailable (shift cost restricted)",
        "pending cast cost:", tostring(pendingCastCost))
    print("Travel/Aquatic cost:", travelCost and tostring(travelCost) or "none (not learned, not readable, or not below bear cost)",
        travelCostSource and ("from " .. travelCostSource) or "")
    local energy = UnitPower("player", Claw.POWER_TYPE)
    print("Claw cost:", Claw.cost and (tostring(Claw.cost) .. " energy, from " .. tostring(Claw.spellID)) or "not found (Claw not learned?)",
        "| max energy:", tostring(UnitPowerMax("player", Claw.POWER_TYPE)),
        "| energy secret:", tostring(IsSecretValue(energy)),
        "| bar shows energy:", tostring(Claw.ShowsEnergy()), "| Claw shade:", tostring(db.clawShade))
    local fontPath, fontSize = manaText:GetFont()
    print("Text format:", GetStatusTextFormat(), "font:", tostring(fontPath), "size", tostring(fontSize),
        "| player frame:", tostring(db.enablePlayerFrame))
    if lastManaSpellID and not IsSecretValue(lastManaSpellID) then
        local spellName = nil
        if C_Spell and C_Spell.GetSpellName then
            local ok, name = pcall(C_Spell.GetSpellName, lastManaSpellID)
            if ok then spellName = name end
        end
        print("Last mana spell:", tostring(spellName or "?"), "ID", tostring(lastManaSpellID))
    end
end

SLASH_DRUIDFOREVERMANABARPLUS1 = "/druidbar"
SlashCmdList["DRUIDFOREVERMANABARPLUS"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    local testTravel = msg:match("^testtravel%s*(.*)$")

    if msg == "debug" then
        PrintDebugInfo()
    elseif msg == "formlog" then
        formLogEnabled = not formLogEnabled
        formLogStart = 0
        lastFormLogLine = nil
        if formLogEnabled then
            print("|cff55ff55DFMP:|r form log on. Shift forms, then /druidbar formlog again to stop.")
            LogFormReadings("start")
        else
            print("|cff55ff55DFMP:|r form log off.")
        end
    elseif testTravel then
        local value = tonumber(testTravel)
        if value and value > 0 then
            travelCostOverride = value
            print("|cff55ff55DFMP:|r pretending Travel Form costs " .. value .. " mana until /reload or /druidbar testtravel off.")
        else
            travelCostOverride = nil
            print("|cff55ff55DFMP:|r Travel Form test cost cleared.")
        end
        RefreshShiftCost()
        UpdateManaBar()
    elseif msg == "test" or msg == "testtimer" then
        manaFrame:Show()
        StartFiveSecondRule()
        print("|cff55ff55DFMP:|r started a 5-second visual test timer.")
    else
        OpenOptions()
    end
end
