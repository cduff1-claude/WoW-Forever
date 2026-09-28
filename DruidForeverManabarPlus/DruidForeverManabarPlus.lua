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

-- Bear and Dire Bear share form ID 5.
local TRACKED_FORMS = {
    [1] = true, -- Cat Form
    [3] = true, -- Travel Form
    [4] = true, -- Aquatic Form
    [5] = true, -- Bear / Dire Bear Form
}

DruidForeverManabarPlusDB = DruidForeverManabarPlusDB or {}

local DEFAULTS = {
    width = 124,
    height = 10,
    scale = 1.0,
    point = "CENTER",
    relativePoint = "CENTER",
    xOfs = 0,
    yOfs = -150,
    attachToPlayerFrame = true,
    unlocked = false,
    colorR = 0.0,
    colorG = 0.4,
    colorB = 0.85,
    textFormat = "both",
    showTimerText = true,
    showOutsideForms = false,
    fontKey = "arial",
    fontSize = 10,
    showShiftMarker = false,
    showShiftShade = true,
    showShiftOnPlayerFrame = true,
}

local function EnsureDB()
    for key, value in pairs(DEFAULTS) do
        if DruidForeverManabarPlusDB[key] == nil then
            DruidForeverManabarPlusDB[key] = value
        end
    end
    return DruidForeverManabarPlusDB
end

local db = EnsureDB()

local FONT_CHOICES = {
    arial = { label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    friz = { label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    morpheus = { label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    skurri = { label = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

local manaFrame = CreateFrame("Frame", "DruidForeverManabarPlusMainFrame", UIParent, "BackdropTemplate")
manaFrame:SetSize(db.width, db.height)
manaFrame:SetScale(db.scale)
manaFrame:SetMovable(true)
manaFrame:EnableMouse(true)
manaFrame:RegisterForDrag("LeftButton")
manaFrame:SetClampedToScreen(true)

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
manaBar:SetStatusBarColor(db.colorR, db.colorG, db.colorB, 1)
manaBar:SetMinMaxValues(0, 1)
manaBar:SetValue(0)

-- Shade over the part of the filled bar that a Cat/Bear shift would spend.
--
-- The client does not let addons read mana values (they come back "secret"), so nothing
-- here compares mana in Lua. Instead StatusBar widgets, which accept secret values, do the
-- work and the other pieces are anchored to the edges of their fill textures:
--
--   fillClip  : clips to [bar left .. right edge of the mana fill], so shades never draw
--               past current mana.
--   stepNow   : invisible. Range [cost - 1, cost], value = current mana, so its fill is
--               either empty (mana below shift cost) or full-width (at/above it).
--   stepCast  : the same, but the threshold also includes the cost of the spell being cast.
--               It is never fuller than stepNow.
--   okClip    : [bar left .. stepCast edge]      - whole bar only when mana stays >= cost
--                                                  after the current cast.
--   castClip  : [stepCast edge .. stepNow edge]  - whole bar only when mana is >= cost now
--                                                  but the current cast would take it below.
--   lowClip   : [stepNow edge .. bar right]      - whole bar only when mana is below cost.
--
-- Each clip holds a StatusBar (value = shift cost over max mana) in its own colour. Exactly
-- one of the three clips has any width at a time, so only one colour is ever visible.
local function CreateStepBar(bar)
    local step = CreateFrame("StatusBar", nil, bar)
    step:SetAllPoints(bar)
    step:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    step:SetStatusBarColor(0, 0, 0, 0)
    step:SetMinMaxValues(0, 1)
    step:SetValue(1)
    return step
end

local function CreateClippedShade(parent, bar, texturePath, left, leftPoint, right, rightPoint)
    local clip = CreateFrame("Frame", nil, parent)
    clip:SetClipsChildren(true)
    clip:SetPoint("TOPLEFT", left, "TOP" .. leftPoint, 0, 0)
    clip:SetPoint("BOTTOMRIGHT", right, "BOTTOM" .. rightPoint, 0, 0)

    local shade = CreateFrame("StatusBar", nil, clip)
    shade:SetAllPoints(bar)
    shade:SetStatusBarTexture(texturePath)
    shade:SetMinMaxValues(0, 1)
    shade:SetValue(0)
    return clip, shade
end

local function CreateShiftShade(bar, texturePath)
    local set = { bar = bar }

    set.fillClip = CreateFrame("Frame", nil, bar)
    set.fillClip:SetClipsChildren(true)

    set.stepNow = CreateStepBar(bar)
    set.stepCast = CreateStepBar(bar)
    local nowEdge = set.stepNow:GetStatusBarTexture()
    local castEdge = set.stepCast:GetStatusBarTexture()

    set.okClip, set.okBar = CreateClippedShade(set.fillClip, bar, texturePath, bar, "LEFT", castEdge, "RIGHT")
    set.castClip, set.castBar = CreateClippedShade(set.fillClip, bar, texturePath, castEdge, "RIGHT", nowEdge, "RIGHT")
    set.lowClip, set.lowBar = CreateClippedShade(set.fillClip, bar, texturePath, nowEdge, "RIGHT", bar, "RIGHT")

    set.shades = { set.okBar, set.castBar, set.lowBar }
    return set
end

-- (Re)anchor to the bar's fill and put the pieces above it. Called again for the Player
-- Frame bar because Blizzard may swap the fill texture when the power type changes.
local function AnchorShiftShade(set)
    local bar = set.bar
    local level = bar:GetFrameLevel()
    local strata = bar:GetFrameStrata()

    set.fillClip:ClearAllPoints()
    set.fillClip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    set.fillClip:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)

    local frames = {
        set.fillClip, set.stepNow, set.stepCast,
        set.okClip, set.castClip, set.lowClip,
        set.okBar, set.castBar, set.lowBar,
    }
    for _, frame in ipairs(frames) do
        frame:SetFrameStrata(strata)
    end
    set.stepNow:SetFrameLevel(level + 1)
    set.stepCast:SetFrameLevel(level + 1)
    set.fillClip:SetFrameLevel(level + 1)
    set.okClip:SetFrameLevel(level + 2)
    set.castClip:SetFrameLevel(level + 2)
    set.lowClip:SetFrameLevel(level + 2)
    set.okBar:SetFrameLevel(level + 3)
    set.castBar:SetFrameLevel(level + 3)
    set.lowBar:SetFrameLevel(level + 3)
end

local function ShowShiftShade(set, shown)
    set.fillClip:SetShown(shown)
    set.stepNow:SetShown(shown)
    set.stepCast:SetShown(shown)
end

local druidShade = CreateShiftShade(manaBar, "Interface\\TargetingFrame\\UI-StatusBar")
AnchorShiftShade(druidShade)
ShowShiftShade(druidShade, false)

-- Text and markers live on their own frame so they draw above the shift shade.
local overlayFrame = CreateFrame("Frame", nil, manaFrame)
overlayFrame:SetAllPoints(manaFrame)
overlayFrame:SetFrameLevel(manaBar:GetFrameLevel() + 5)

local shiftLine = overlayFrame:CreateTexture(nil, "OVERLAY", nil, 6)
shiftLine:SetColorTexture(1, 1, 1, 1)
shiftLine:SetWidth(2)
shiftLine:SetPoint("TOP", druidShade.lowBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
shiftLine:SetPoint("BOTTOM", druidShade.lowBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
shiftLine:Hide()

local manaText = overlayFrame:CreateFontString(nil, "OVERLAY")
manaText:SetPoint("CENTER", manaBar, "CENTER", 0, 0)

local fsrMarker = overlayFrame:CreateTexture(nil, "OVERLAY", nil, 7)
fsrMarker:SetColorTexture(1, 1, 1, 0.95)
fsrMarker:SetWidth(2)
fsrMarker:SetHeight(db.height + 4)
fsrMarker:Hide()

local fsrText = manaFrame:CreateFontString(nil, "OVERLAY")
fsrText:SetPoint("TOP", manaFrame, "BOTTOM", 0, -2)
fsrText:Hide()

local function ApplyFont()
    local choice = FONT_CHOICES[db.fontKey] or FONT_CHOICES.arial
    local size = db.fontSize or 10

    manaText:SetFont(choice.path, size, "")
    manaText:SetTextColor(1, 1, 1, 1)
    manaText:SetShadowColor(0, 0, 0, 0.9)
    manaText:SetShadowOffset(1, -1)

    fsrText:SetFont(choice.path, math.max(8, size - 1), "")
    fsrText:SetTextColor(1, 1, 1, 1)
    fsrText:SetShadowColor(0, 0, 0, 0.9)
    fsrText:SetShadowOffset(1, -1)
end

ApplyFont()

-- Shade colours: pale red = the current cast will take mana below the shift cost,
-- dark red = mana is below the shift cost now.
local SHADE_CAST_R, SHADE_CAST_G, SHADE_CAST_B = 1.0, 0.66, 0.66
local SHADE_LOW_R, SHADE_LOW_G, SHADE_LOW_B = 0.85, 0.25, 0.25
-- The Player Frame bar uses Blizzard's own texture, so it gets translucent washes that blend
-- with the blue underneath.
local PF_SHADE_OK_R, PF_SHADE_OK_G, PF_SHADE_OK_B, PF_SHADE_OK_A = 1.0, 1.0, 1.0, 0.3
local PF_SHADE_CAST_R, PF_SHADE_CAST_G, PF_SHADE_CAST_B, PF_SHADE_CAST_A = 1.0, 0.66, 0.66, 0.79
local PF_SHADE_LOW_R, PF_SHADE_LOW_G, PF_SHADE_LOW_B, PF_SHADE_LOW_A = 1.0, 0.45, 0.45, 0.7

local pfShade = nil

local function ApplyShiftShadeColor()
    local shown = db.showShiftShade

    -- Lighten the configured bar colour towards white.
    local lighten = 0.45
    local r = db.colorR + (1 - db.colorR) * lighten
    local g = db.colorG + (1 - db.colorG) * lighten
    local b = db.colorB + (1 - db.colorB) * lighten
    druidShade.okBar:SetStatusBarColor(r, g, b, shown and 1 or 0)
    druidShade.castBar:SetStatusBarColor(SHADE_CAST_R, SHADE_CAST_G, SHADE_CAST_B, shown and 1 or 0)
    druidShade.lowBar:SetStatusBarColor(SHADE_LOW_R, SHADE_LOW_G, SHADE_LOW_B, shown and 1 or 0)

    if pfShade then
        pfShade.okBar:SetStatusBarColor(PF_SHADE_OK_R, PF_SHADE_OK_G, PF_SHADE_OK_B, shown and PF_SHADE_OK_A or 0)
        pfShade.castBar:SetStatusBarColor(PF_SHADE_CAST_R, PF_SHADE_CAST_G, PF_SHADE_CAST_B, shown and PF_SHADE_CAST_A or 0)
        pfShade.lowBar:SetStatusBarColor(PF_SHADE_LOW_R, PF_SHADE_LOW_G, PF_SHADE_LOW_B, shown and PF_SHADE_LOW_A or 0)
    end
end

ApplyShiftShadeColor()

local isDruid = false
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

local function ApplyAnchor()
    manaFrame:ClearAllPoints()

    if db.attachToPlayerFrame and PlayerFrame then
        local resourceBar = GetPlayerResourceBar()

        manaFrame:SetParent(PlayerFrame)
        manaFrame:SetScale(1)
        manaFrame:SetHeight(10)

        if resourceBar then
            -- Match the real Blizzard power bar instead of relying on fixed PlayerFrame offsets.
            manaFrame:SetPoint("TOPLEFT", resourceBar, "BOTTOMLEFT", 0, 0)
            manaFrame:SetPoint("TOPRIGHT", resourceBar, "BOTTOMRIGHT", 0, 0)
        else
            -- Fallback for beta builds where the resource-bar hierarchy changes.
            manaFrame:SetWidth(124)
            manaFrame:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 85, -74)
        end
    else
        manaFrame:SetParent(UIParent)
        manaFrame:SetScale(db.scale)
        manaFrame:SetSize(db.width, db.height)
        manaFrame:SetPoint(db.point, UIParent, db.relativePoint, db.xOfs, db.yOfs)
    end

    fsrMarker:SetHeight(manaFrame:GetHeight() + 4)

    -- Re-layer after reparenting so the shade stays between the bar and the text.
    AnchorShiftShade(druidShade)
    overlayFrame:SetFrameStrata(manaBar:GetFrameStrata())
    overlayFrame:SetFrameLevel(manaBar:GetFrameLevel() + 5)
end

local function HideFiveSecondRuleVisual()
    fsrMarker:Hide()
    fsrText:Hide()
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

    if db.showTimerText then
        fsrText:SetText(string.format("%.1f", remaining))
        fsrText:Show()
    else
        fsrText:Hide()
    end
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

local function SetManaText(currentMana, maxMana)
    local format = db.textFormat

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

local function RefreshShiftCost()
    shiftCost = nil
    shiftCostSpellID = nil

    if not isDruid then
        return
    end

    for _, spellID in ipairs(FindShiftCostSpells()) do
        local cost = GetManaCostFromSpell(spellID)
        if cost ~= nil then
            -- A readable zero cost means "not usable"; keep looking for a better source.
            if IsSecretValue(cost) or cost > 0 then
                shiftCost = cost
                shiftCostSpellID = spellID
                return
            end
        end
    end
end

-- Second copy of the shift-cost shade/line on the Blizzard Player Frame mana bar, used
-- whenever that bar is showing mana (caster form, Moonkin, etc.).
local pfLineFrame = nil
local pfLine = nil
local pfOverlayActive = false

local function EnsurePlayerFrameOverlay()
    local resourceBar = GetPlayerResourceBar()
    if not resourceBar or not resourceBar.GetStatusBarTexture then
        return false
    end

    if pfShade and pfShade.bar == resourceBar then
        return true
    end

    if pfShade then
        ShowShiftShade(pfShade, false)
        pfLineFrame:Hide()
    end

    pfShade = CreateShiftShade(resourceBar, "Interface\\Buttons\\WHITE8X8")

    pfLineFrame = CreateFrame("Frame", nil, resourceBar)
    pfLineFrame:SetAllPoints(resourceBar)
    pfLine = pfLineFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    pfLine:SetColorTexture(1, 1, 1, 1)
    pfLine:SetWidth(2)
    pfLine:SetPoint("TOP", pfShade.lowBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    pfLine:SetPoint("BOTTOM", pfShade.lowBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)

    ShowShiftShade(pfShade, false)
    pfLineFrame:Hide()
    ApplyShiftShadeColor()
    return true
end

local function HidePlayerFrameOverlay()
    pfOverlayActive = false
    if pfShade then
        ShowShiftShade(pfShade, false)
        pfLineFrame:Hide()
    end
end

local function ShowPlayerFrameOverlay()
    if not EnsurePlayerFrameOverlay() then
        HidePlayerFrameOverlay()
        return
    end

    AnchorShiftShade(pfShade)
    pfLineFrame:SetFrameStrata(pfShade.bar:GetFrameStrata())
    pfLineFrame:SetFrameLevel(pfShade.bar:GetFrameLevel() + 8)
    pfOverlayActive = true
end

-- Mana cost of the spell currently being cast, like the darker "cost prediction" section
-- Blizzard draws on the Player Frame bar while casting.
local pendingCastCost = 0
local pendingCastGUID = nil

local function IsReadableNumber(value)
    return type(value) == "number" and not IsSecretValue(value)
end

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
    for _, shade in ipairs(set.shades) do
        shade:SetMinMaxValues(0, maxMana)
        shade:SetValue(shiftCost)
    end

    SetStep(set.stepNow, threshold and shiftCost, currentMana)
    SetStep(set.stepCast, threshold, currentMana)

    ShowShiftShade(set, true)
end

local function UpdateShiftCostVisual(maxMana, currentMana)
    if shiftCost == nil or (not db.showShiftMarker and not db.showShiftShade) then
        ShowShiftShade(druidShade, false)
        shiftLine:Hide()
        if pfShade then
            ShowShiftShade(pfShade, false)
            pfLineFrame:Hide()
        end
        return
    end

    local threshold = GetShiftThreshold()

    UpdateShiftShade(druidShade, maxMana, currentMana, threshold)
    shiftLine:SetShown(db.showShiftMarker)

    if pfOverlayActive and pfShade then
        UpdateShiftShade(pfShade, maxMana, currentMana, threshold)
        pfLineFrame:SetShown(db.showShiftMarker)
    elseif pfShade then
        ShowShiftShade(pfShade, false)
        pfLineFrame:Hide()
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

local function PlayerFrameBarShowsMana()
    local powerType = UnitPowerType("player")
    if powerType == nil or IsSecretValue(powerType) then
        return false
    end
    return powerType == MANA_POWER_TYPE
end

local function UpdateFormState()
    local formID = GetShapeshiftFormID()
    local tracked = isDruid and IsTrackedForm(formID)
    local shouldShow = isDruid and (tracked or db.showOutsideForms)

    if isDruid and db.showShiftOnPlayerFrame and PlayerFrameBarShowsMana() then
        ShowPlayerFrameOverlay()
    else
        HidePlayerFrameOverlay()
    end

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
end

local OpenOptions

manaFrame:SetScript("OnMouseDown", function(_, button)
    if button == "RightButton" and OpenOptions then
        OpenOptions()
    end
end)

manaFrame:SetScript("OnDragStart", function(self)
    if db.unlocked and not db.attachToPlayerFrame then
        self:StartMoving()
    end
end)

manaFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    db.point = point
    db.relativePoint = relativePoint
    db.xOfs = xOfs
    db.yOfs = yOfs
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
pcall(manaFrame.RegisterEvent, manaFrame, "PLAYER_TALENT_UPDATE")
pcall(manaFrame.RegisterEvent, manaFrame, "CHARACTER_POINTS_CHANGED")

manaFrame:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
    if event == "PLAYER_LOGIN" then
        -- SavedVariables are loaded after this file runs, so re-read them here.
        db = EnsureDB()

        local _, classFile = UnitClass("player")
        isDruid = (classFile == "DRUID")

        manaBar:SetStatusBarColor(db.colorR, db.colorG, db.colorB, 1)
        ApplyShiftShadeColor()
        ApplyFont()
        ApplyAnchor()

        UpdateFormState()

        if isDruid then
            print("|cff00ff00DruidForeverManabarPlus loaded.|r Right-click the mana bar or type |cffffffff/dfmp|r for options.")
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
        UpdateFormState()
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
        end
    elseif event == "UNIT_MAXPOWER" then
        if powerType == nil or powerType == "MANA" then
            UpdateManaBar()
        end
    end
end)

manaFrame:Hide()

local panel = CreateFrame("Frame", "DruidForeverManabarPlusOptionsPanel", UIParent)
panel.name = "Druid Forever Manabar Plus"
panel:SetSize(460, 690)

local settingsCategory

OpenOptions = function()
    if Settings and Settings.OpenToCategory and settingsCategory then
        local ok = pcall(Settings.OpenToCategory, settingsCategory:GetID())
        if not ok then
            pcall(Settings.OpenToCategory, settingsCategory)
        end
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Druid Forever Manabar Plus Settings")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetText("Right-click the mana bar in-game anytime to open this menu.")

local attachCheckbox = CreateFrame("CheckButton", "DFMPAttachCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
attachCheckbox:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -15)
_G[attachCheckbox:GetName() .. "Text"]:SetText("Snap directly below Player Frame resource bar")
attachCheckbox:SetChecked(db.attachToPlayerFrame)
attachCheckbox:SetScript("OnClick", function(self)
    db.attachToPlayerFrame = self:GetChecked()
    ApplyAnchor()
end)

local unlockCheckbox = CreateFrame("CheckButton", "DFMPUnlockCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
unlockCheckbox:SetPoint("TOPLEFT", attachCheckbox, "BOTTOMLEFT", 0, -10)
_G[unlockCheckbox:GetName() .. "Text"]:SetText("Unlock bar for dragging (disable anchoring first)")
unlockCheckbox:SetChecked(db.unlocked)
unlockCheckbox:SetScript("OnClick", function(self)
    db.unlocked = self:GetChecked()
end)

local timerTextCheckbox = CreateFrame("CheckButton", "DFMPTimerTextCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
timerTextCheckbox:SetPoint("TOPLEFT", unlockCheckbox, "BOTTOMLEFT", 0, -10)
_G[timerTextCheckbox:GetName() .. "Text"]:SetText("Show 5-second-rule countdown text below the mana bar")
timerTextCheckbox:SetChecked(db.showTimerText)
timerTextCheckbox:SetScript("OnClick", function(self)
    db.showTimerText = self:GetChecked()
    UpdateFiveSecondRuleVisual()
end)

local outsideFormsCheckbox = CreateFrame("CheckButton", "DFMPOutsideFormsCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
outsideFormsCheckbox:SetPoint("TOPLEFT", timerTextCheckbox, "BOTTOMLEFT", 0, -10)
_G[outsideFormsCheckbox:GetName() .. "Text"]:SetText("Show mana bar in Caster Form (outside shapeshift forms)")
outsideFormsCheckbox:SetChecked(db.showOutsideForms)
outsideFormsCheckbox:SetScript("OnClick", function(self)
    db.showOutsideForms = self:GetChecked()
    UpdateFormState()
end)

local shiftLineCheckbox = CreateFrame("CheckButton", "DFMPShiftLineCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
shiftLineCheckbox:SetPoint("TOPLEFT", outsideFormsCheckbox, "BOTTOMLEFT", 0, -10)
_G[shiftLineCheckbox:GetName() .. "Text"]:SetText("Show white line at the Cat/Bear shift cost")
shiftLineCheckbox:SetChecked(db.showShiftMarker)
shiftLineCheckbox:SetScript("OnClick", function(self)
    db.showShiftMarker = self:GetChecked()
    UpdateManaBar()
end)

local shiftShadeCheckbox = CreateFrame("CheckButton", "DFMPShiftShadeCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
shiftShadeCheckbox:SetPoint("TOPLEFT", shiftLineCheckbox, "BOTTOMLEFT", 0, -10)
_G[shiftShadeCheckbox:GetName() .. "Text"]:SetText("Lighter shade on the mana a Cat/Bear shift would spend")
shiftShadeCheckbox:SetChecked(db.showShiftShade)
shiftShadeCheckbox:SetScript("OnClick", function(self)
    db.showShiftShade = self:GetChecked()
    ApplyShiftShadeColor()
    UpdateManaBar()
end)

local playerFrameShiftCheckbox = CreateFrame("CheckButton", "DFMPPlayerFrameShiftCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
playerFrameShiftCheckbox:SetPoint("TOPLEFT", shiftShadeCheckbox, "BOTTOMLEFT", 0, -10)
_G[playerFrameShiftCheckbox:GetName() .. "Text"]:SetText("Also show shift cost on the Player Frame mana bar (caster form)")
playerFrameShiftCheckbox:SetChecked(db.showShiftOnPlayerFrame)
playerFrameShiftCheckbox:SetScript("OnClick", function(self)
    db.showShiftOnPlayerFrame = self:GetChecked()
    UpdateFormState()
end)

local function CreateSlider(name, parent, minVal, maxVal, step, labelText, valueKey, callback)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValue(db[valueKey])
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    _G[slider:GetName() .. "Low"]:SetText(tostring(minVal))
    _G[slider:GetName() .. "High"]:SetText(tostring(maxVal))
    local label = _G[slider:GetName() .. "Text"]

    local function DisplayValue(value)
        if step < 1 then
            return string.format("%.1f", value)
        end
        return tostring(math.floor(value + 0.5))
    end

    label:SetText(labelText .. ": " .. DisplayValue(db[valueKey]))

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        db[valueKey] = value
        label:SetText(labelText .. ": " .. DisplayValue(value))
        if callback then callback(value) end
    end)

    return slider
end

local widthSlider = CreateSlider("DFMPWidthSlider", panel, 50, 400, 10, "Bar Width (Manual)", "width", function(val)
    if not db.attachToPlayerFrame then
        manaFrame:SetSize(val, db.height)
        fsrMarker:SetHeight(manaFrame:GetHeight() + 4)
    end
end)
widthSlider:SetPoint("TOPLEFT", playerFrameShiftCheckbox, "BOTTOMLEFT", 0, -35)

local heightSlider = CreateSlider("DFMPHeightSlider", panel, 6, 30, 2, "Bar Height (Manual)", "height", function(val)
    if not db.attachToPlayerFrame then
        manaFrame:SetSize(manaFrame:GetWidth(), val)
        fsrMarker:SetHeight(manaFrame:GetHeight() + 4)
    end
end)
heightSlider:SetPoint("TOPLEFT", widthSlider, "BOTTOMLEFT", 0, -35)

local scaleSlider = CreateSlider("DFMPScaleSlider", panel, 0.5, 2.0, 0.1, "UI Scale (Manual)", "scale", function(val)
    if not db.attachToPlayerFrame then
        manaFrame:SetScale(val)
    end
end)
scaleSlider:SetPoint("TOPLEFT", heightSlider, "BOTTOMLEFT", 0, -35)

local formatLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
formatLabel:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -35)
formatLabel:SetText("Mana text format:")

local formatButtons = {}

local function RefreshFormatButtons()
    for mode, btn in pairs(formatButtons) do
        if mode == db.textFormat then
            btn:SetText("[" .. btn.label .. "]")
        else
            btn:SetText(btn.label)
        end
    end
end

local function CreateFormatButton(mode, label, xOffset)
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(80, 22)
    btn:SetPoint("TOPLEFT", formatLabel, "BOTTOMLEFT", xOffset, -8)
    btn.label = label
    btn:SetText(label)
    btn:SetScript("OnClick", function()
        db.textFormat = mode
        RefreshFormatButtons()
        UpdateManaBar()
    end)
    formatButtons[mode] = btn
    return btn
end

CreateFormatButton("numeric", "Numeric", 0)
CreateFormatButton("percent", "Percent", 85)
CreateFormatButton("both", "Both", 170)
RefreshFormatButtons()

local fontLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
fontLabel:SetPoint("TOPLEFT", formatLabel, "BOTTOMLEFT", 0, -42)
fontLabel:SetText("Mana bar font:")

local fontButtons = {}

local function RefreshFontButtons()
    for key, btn in pairs(fontButtons) do
        if key == db.fontKey then
            btn:SetText("[" .. btn.label .. "]")
        else
            btn:SetText(btn.label)
        end
    end
end

local function CreateFontButton(key, xOffset, width)
    local choice = FONT_CHOICES[key]
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(width or 95, 22)
    btn:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", xOffset, -8)
    btn.label = choice.label
    btn:SetText(choice.label)
    btn:SetScript("OnClick", function()
        db.fontKey = key
        ApplyFont()
        RefreshFontButtons()
        UpdateManaBar()
        UpdateFiveSecondRuleVisual()
    end)
    fontButtons[key] = btn
    return btn
end

CreateFontButton("arial", 0, 95)
CreateFontButton("friz", 100, 95)
CreateFontButton("morpheus", 200, 95)
CreateFontButton("skurri", 300, 80)
RefreshFontButtons()

local fontSizeSlider = CreateSlider("DFMPFontSizeSlider", panel, 8, 16, 1, "Font Size", "fontSize", function()
    ApplyFont()
    UpdateManaBar()
    UpdateFiveSecondRuleVisual()
end)
fontSizeSlider:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -55)

panel:SetScript("OnShow", function()
    attachCheckbox:SetChecked(db.attachToPlayerFrame)
    unlockCheckbox:SetChecked(db.unlocked)
    timerTextCheckbox:SetChecked(db.showTimerText)
    outsideFormsCheckbox:SetChecked(db.showOutsideForms)
    shiftLineCheckbox:SetChecked(db.showShiftMarker)
    shiftShadeCheckbox:SetChecked(db.showShiftShade)
    playerFrameShiftCheckbox:SetChecked(db.showShiftOnPlayerFrame)
    widthSlider:SetValue(db.width)
    heightSlider:SetValue(db.height)
    scaleSlider:SetValue(db.scale)
    fontSizeSlider:SetValue(db.fontSize)
    RefreshFormatButtons()
    RefreshFontButtons()
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(settingsCategory)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

local function PrintDebugInfo()
    local version, build, _, tocVersion = GetBuildInfo()
    local formID = GetShapeshiftFormID()
    local powerID, powerToken = UnitPowerType("player")
    local currentMana = UnitPower("player", MANA_POWER_TYPE)
    local maxMana = UnitPowerMax("player", MANA_POWER_TYPE)
    local manaIsSecret = IsSecretValue(currentMana)
    local remaining = math.max(0, fsrEndTime - GetTime())

    print("|cff55ff55DruidForeverManabarPlus debug|r")
    print("Client:", tostring(version), "build", tostring(build), "TOC", tostring(tocVersion))
    print("Form ID:", tostring(formID), "tracked:", tostring(IsTrackedForm(formID)))
    print("Primary power:", tostring(powerID), tostring(powerToken))
    local resourceBar = GetPlayerResourceBar()
    print("Snap target:", resourceBar and (resourceBar.GetDebugName and resourceBar:GetDebugName() or tostring(resourceBar)) or "fallback PlayerFrame offset")
    print("Mana secret:", tostring(manaIsSecret), "max mana:", tostring(maxMana))
    if not manaIsSecret then
        print("Current mana:", tostring(currentMana))
    end
    print("5SR remaining:", string.format("%.2f", remaining))
    RefreshShiftCost()
    if shiftCost == nil then
        print("Shift cost: not found (no Cat/Bear Form mana cost available)")
    elseif IsSecretValue(shiftCost) then
        print("Shift cost: restricted value, spell ID", tostring(shiftCostSpellID))
    else
        print("Shift cost:", tostring(shiftCost), "mana, from spell ID", tostring(shiftCostSpellID))
    end
    print("Player Frame shift overlay active:", tostring(pfOverlayActive), "bar shows mana:", tostring(PlayerFrameBarShowsMana()))
    local threshold = GetShiftThreshold()
    print("Red/blue threshold:", threshold and tostring(threshold) or "unavailable (shift cost restricted)",
        "pending cast cost:", tostring(pendingCastCost))
    local fontChoice = FONT_CHOICES[db.fontKey] or FONT_CHOICES.arial
    print("Font:", fontChoice.label, "size", tostring(db.fontSize), "show outside forms:", tostring(db.showOutsideForms))
    if lastManaSpellID and not IsSecretValue(lastManaSpellID) then
        local spellName = nil
        if C_Spell and C_Spell.GetSpellName then
            local ok, name = pcall(C_Spell.GetSpellName, lastManaSpellID)
            if ok then spellName = name end
        end
        print("Last mana spell:", tostring(spellName or "?"), "ID", tostring(lastManaSpellID))
    end
end

SLASH_DRUIDFOREVERMANABARPLUS1 = "/dfmp"
SlashCmdList["DRUIDFOREVERMANABARPLUS"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "debug" then
        PrintDebugInfo()
    elseif msg == "test" or msg == "testtimer" then
        manaFrame:Show()
        StartFiveSecondRule()
        print("|cff55ff55DFMP:|r started a 5-second visual test timer.")
    else
        OpenOptions()
    end
end
