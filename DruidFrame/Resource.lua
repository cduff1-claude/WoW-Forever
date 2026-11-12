-- DruidFrame: the resource display, our own replacement for Blizzard's Personal Resource Display.
--
-- Rows, top to bottom, all the same width:
--   health
--   mana (always, in every form)
--   energy or rage in Cat/Bear; in caster form, an optional cast bar while casting
--   combo points (Cat Form)
-- The frame is anchored by its top edge, so health and mana never move when a row below
-- appears or goes. DruidBar's own features treat these bars as more places to draw: the
-- shift-cost shading and 5-second-rule marker go on the mana bar, the Claw orange on the
-- energy bar (see DruidBar.lua: RefreshBlizzardOverlays, FSR.WantedBars, Claw.RefreshOverlays).
--
-- Values are secret on Forever (Midnight rules). They only ever go into StatusBar:SetValue /
-- SetMinMaxValues and FontString:SetFormattedText, which accept them; no maths or comparisons.

local _, ns = ...
local R = {}
ns.Resource = R

local POWER = {
    MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0,
    COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4,
    ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3,
}
-- Bar styles: "flat" copies Blizzard's Personal Resource Display (a plain fill with a lighter
-- top half, measured as about 15% white); "shaded" is Blizzard's classic bar texture.
local STYLE_TEXTURE = {
    flat = "Interface\\Buttons\\WHITE8X8",
    shaded = "Interface\\TargetingFrame\\UI-StatusBar",
}
local GLOSS_ALPHA = 0.15
local FONT = "Fonts\\FRIZQT__.TTF"
local ART = "Interface\\AddOns\\DruidFrame\\"
-- The range bar's purple (DruidRange's COLOR_PURPLE), bold and clear of the gold energy bar.
-- The Player Frame's incoming-heal teal.
local HEAL_COLOUR = { 0.0, 0.63, 0.56 }
local CAST_COLOUR = { 0.6, 0.2, 0.9 }
local COMBO_COLOUR = { 0.90, 0.13, 0.04 }
-- Seconds the last spell's name stays; then the name fades, then the whole bar.
local LINGER_TIME, LINGER_FADE = 3, 0.5
local SEGMENT_GAP = 2                    -- between combo bar segments
local GLOW_SIZE = 2                      -- full-combo glow, drawn just outside each segment
local GLOW_COLOUR = { 1.0, 0.85, 0.2 }   -- DruidSequence's glow colour
local CLEARCASTING = 16870               -- the Omen of Clarity proc (Classic spell ID)

R.VISIBILITY = {
    { key = "always", label = "Always" },
    { key = "combat", label = "In combat" },
    { key = "combatOrTarget", label = "In combat or with a target" },
    { key = "hidden", label = "Hidden" },
}
R.STYLE = {
    { key = "flat", label = "Flat (like the Personal Resource Display)" },
    { key = "shaded", label = "Shaded" },
}
R.CASTER_ENERGY = {
    { key = "never", label = "Never" },
    { key = "combat", label = "In combat" },
    { key = "always", label = "Always" },
}
R.COMBO = {
    { key = "hide", label = "Hide" },
    { key = "circles", label = "Circles" },
    { key = "bar", label = "Bar" },
}
R.TEXT = {
    { key = "centre", label = "Current, centred" },
    { key = "values", label = "Current and max" },
    { key = "current", label = "Current" },
    { key = "percent", label = "Percent" },
    { key = "both", label = "Current and percent" },
    { key = "none", label = "None" },
}

R.DEFAULTS = {
    enabled = true,
    style = "flat",
    visibility = "always",
    text = "values",
    scale = 1.0,
    width = 210,
    healthHeight = 14,
    powerHeight = 12,
    padding = 4, -- the PRD's gap: about 3 clear pixels between the bars' borders
    opacity = 1.0,
    keepCentred = true,
    clearcastGlow = true, -- gold glow on the mana and energy/rage bars while Omen of Clarity is up
    castBar = true,
    castLocked = true,  -- keep the cast row in place in caster form, not just while casting
    castLinger = true,  -- after a spell goes off (instants too), show its name and cost for a while
    healthGradient = true, -- health bar shifts green > yellow > orange > red between 80% and 20%
    casterEnergy = "combat", -- energy bar in caster form too (Furor's regen): "never", "combat" or "always"
    buffButtons = true, -- out of combat: Mark of the Wild / Thorns buttons beside the display when missing
    buffButtonsPvP = false, -- ...in battlegrounds and arenas too (off: buffs get purged there)
    comboStyle = "circles",
    x = nil, -- position of the frame's top centre, in UIParent units (nil: default spot)
    y = nil,
}

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Settings live in DruidForeverManabarPlusDB.resource (DruidBar keeps the key).
function R.Settings()
    DruidForeverManabarPlusDB = DruidForeverManabarPlusDB or {}
    local s = DruidForeverManabarPlusDB.resource
    if type(s) ~= "table" then
        s = {}
        DruidForeverManabarPlusDB.resource = s
    end
    for key, value in pairs(R.DEFAULTS) do
        if s[key] == nil then
            s[key] = value
        end
    end
    -- Version 2: the PRD's spacing and the flat style became the defaults.
    if (s.version or 1) < 2 then
        s.version = 2
        if s.padding == 1 then
            s.padding = R.DEFAULTS.padding
        end
        s.style = "flat"
    end
    -- Version 3: centred current text (asked for), combo points became a choice.
    s.unlocked = nil -- no longer saved: the frame is unlocked while its options page is open
    if s.version < 3 then
        s.version = 3
        s.text = "centre"
        if s.comboPoints == false then
            s.comboStyle = "hide"
        end
        s.comboPoints = nil
    end
    -- The caster-form energy option was briefly a tick box.
    if type(s.casterEnergy) ~= "string" then
        s.casterEnergy = R.DEFAULTS.casterEnergy
    end
    return s
end

local function PowerType()
    local powerType, token = UnitPowerType("player")
    if powerType == nil or IsSecret(powerType) then
        return nil, nil
    end
    if IsSecret(token) then
        token = nil
    end
    return powerType, token
end

----------------------------------------------------------------------------------------------
-- Building
----------------------------------------------------------------------------------------------

local function NewBar()
    local bar = CreateFrame("StatusBar", nil, R.frame)
    bar:SetStatusBarTexture(STYLE_TEXTURE.flat)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.65)
    bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)

    -- Text sits on its own frame, above DruidBar's overlays (child frames of the bar).
    local textFrame = CreateFrame("Frame", nil, bar)
    textFrame:SetAllPoints(bar)
    textFrame:SetFrameLevel(bar:GetFrameLevel() + 30)
    local function Text(point, x)
        local fs = textFrame:CreateFontString(nil, "OVERLAY")
        fs:SetFont(FONT, 10, "OUTLINE")
        fs:SetTextColor(1, 1, 1, 1)
        fs:SetPoint(point, bar, point, x, 0)
        return fs
    end
    bar.left = Text("LEFT", 4)
    bar.right = Text("RIGHT", -4)
    bar.centre = Text("CENTER", 0)
    bar.textFrame = textFrame

    -- Flat style's lighter top half: over the fill only (anchored to the fill's right edge),
    -- below DruidBar's overlays, which are child frames.
    local gloss = bar:CreateTexture(nil, "OVERLAY")
    gloss:SetColorTexture(1, 1, 1, GLOSS_ALPHA)
    bar.gloss = gloss
    return bar
end

local function NewComboPoint(parent)
    local point = CreateFrame("Frame", nil, parent)
    local back = point:CreateTexture(nil, "BACKGROUND")
    back:SetTexture(ART .. "ComboBack")
    back:SetAllPoints(point)
    -- A status bar with range [i-1, i] is either empty or full: the lit circle, no maths
    -- on the (secret) combo point count.
    local fill = CreateFrame("StatusBar", nil, point)
    fill:SetPoint("TOPLEFT", point, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", point, "BOTTOMRIGHT", -2, 2)
    fill:SetStatusBarTexture(ART .. "ComboFill")
    fill:SetStatusBarColor(COMBO_COLOUR[1], COMBO_COLOUR[2], COMBO_COLOUR[3], 1)
    point.fill = fill
    return point
end

function R.Build()
    if R.frame then
        return
    end
    local f = CreateFrame("Frame", "DruidBarResourceFrame", UIParent)
    R.frame = f
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:Hide()

    R.health = NewBar()
    -- Incoming heals, like the Player Frame's: a teal bar running on from the end of the health
    -- fill, as long as the heals are big, clipped to the bar so it never overflows. Values can be
    -- secret: status bars take them as they are.
    local healClip = CreateFrame("Frame", nil, R.health)
    healClip:SetAllPoints(R.health)
    healClip:SetClipsChildren(true)
    healClip:SetFrameLevel(R.health:GetFrameLevel() + 1)
    local heal = CreateFrame("StatusBar", nil, healClip)
    heal:SetStatusBarTexture(STYLE_TEXTURE.flat)
    heal:SetStatusBarColor(HEAL_COLOUR[1], HEAL_COLOUR[2], HEAL_COLOUR[3], 1)
    heal:SetMinMaxValues(0, 1)
    heal:SetValue(0)
    R.heal = heal
    R.mana = NewBar()
    R.power = NewBar()
    R.cast = NewBar()
    R.cast:SetStatusBarColor(CAST_COLOUR[1], CAST_COLOUR[2], CAST_COLOUR[3], 1)

    -- Cast bar animation (our own: Blizzard's cast bar code can't run for us without taint):
    -- a spark riding the fill's edge while casting, and a flash when a spell goes off.
    local spark = R.cast.textFrame:CreateTexture(nil, "ARTWORK")
    spark:SetTexture(ART .. "CastSpark")
    spark:SetBlendMode("ADD")
    spark:Hide()
    R.cast.spark = spark
    local flash = R.cast.textFrame:CreateTexture(nil, "ARTWORK")
    flash:SetAllPoints(R.cast)
    flash:SetColorTexture(1, 1, 1, 1)
    flash:SetBlendMode("ADD")
    flash:SetAlpha(0)
    R.cast.flash = flash
    local flashAnim = R.cast.textFrame:CreateAnimationGroup()
    local flashIn = flashAnim:CreateAnimation("Alpha")
    flashIn:SetTarget(flash)
    flashIn:SetFromAlpha(0.6)
    flashIn:SetToAlpha(0)
    flashIn:SetDuration(0.4)
    R.cast.flashAnim = flashAnim

    R.comboBar = CreateFrame("Frame", nil, f)
    R.comboSegments = {}

    R.combo = CreateFrame("Frame", nil, f)
    R.comboPoints = {}

    -- Shown while unlocked: a tint and a label, so it's clear the frame can be dragged.
    local unlockTint = f:CreateTexture(nil, "OVERLAY")
    unlockTint:SetColorTexture(0.2, 0.8, 0.2, 0.25)
    unlockTint:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
    unlockTint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    unlockTint:Hide()
    R.unlockTint = unlockTint
    local unlockLabel = f:CreateFontString(nil, "OVERLAY")
    unlockLabel:SetFont(FONT, 10, "OUTLINE")
    unlockLabel:SetPoint("BOTTOM", f, "TOP", 0, 4)
    unlockLabel:SetText("DruidFrame: drag to move (close the options to lock)")
    unlockLabel:Hide()
    R.unlockLabel = unlockLabel

    -- The red centre line shown while dragging with "Keep centred" on, like Edit Mode's snap.
    local guide = CreateFrame("Frame", nil, UIParent)
    guide:SetFrameStrata("BACKGROUND")
    guide:SetWidth(2)
    guide:SetPoint("TOP", UIParent, "TOP", 0, 0)
    guide:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    local line = guide:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(1, 0.15, 0.15, 0.8)
    line:SetAllPoints(guide)
    guide:Hide()
    R.guide = guide

    -- Right-click (without dragging the camera) opens the options; while they're open the
    -- frame is unlocked and left-drag moves it. Locked, left clicks pass through to the world.
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and R.unlocked then
            R.StartDrag()
        elseif button == "RightButton" then
            R.rightDown = { R.Cursor() }
        end
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and R.rightDown then
            local x, y = R.Cursor()
            local moved = math.abs(x - R.rightDown[1]) + math.abs(y - R.rightDown[2])
            R.rightDown = nil
            if moved < 5 then
                R.OpenOptions()
            end
        else
            R.StopDrag()
        end
    end)

    -- Omen of Clarity: a pulsing gold glow around the mana and energy/rage bars.
    R.mana.procGlow = R.EdgeGlow(R.mana)
    R.power.procGlow = R.EdgeGlow(R.power)

    R.cast:SetScript("OnUpdate", function(bar)
        if R.casting then
            bar:SetValue(R.CastValue())
        elseif R.linger then
            R.UpdateLinger()
        end
    end)
end

----------------------------------------------------------------------------------------------
-- Layout and position
----------------------------------------------------------------------------------------------

-- The row under mana: the energy/rage bar in Cat/Bear, else the cast bar while casting.
-- What the energy/rage bar (R.power) shows: the form's power in Cat/Bear, or energy in caster
-- form when "Show energy in caster form" is on (Furor's regen). nil when it's not shown.
function R.BarPower()
    local powerType, token = PowerType()
    if powerType ~= nil and powerType ~= POWER.MANA then
        return powerType, token
    end
    local when = R.Settings().casterEnergy
    local inCombat = R.InCombat()
    if powerType == POWER.MANA and (when == "always" or (when == "combat" and inCombat)) then
        local max = UnitPowerMax("player", POWER.ENERGY)
        if not IsSecret(max) and max and max > 0 then
            return POWER.ENERGY, "ENERGY"
        end
    end
    return nil, nil
end

-- The cast bar's row (caster form only).
-- The cast bar's row. In caster form it can hold its place; in Cat/Bear it shows only while
-- something with a cast time is going (skinning, opening, gathering...), below the energy/rage bar.
function R.CastRowShown()
    local s = R.Settings()
    if not s.castBar then
        return false
    end
    if PowerType() == POWER.MANA then
        return (s.castLocked or R.casting or R.linger) and true or false
    end
    return (R.casting or R.linger) and true or false
end

function R.ThirdRow()
    local s = R.Settings()
    local powerType = PowerType()
    if R.BarPower() then
        return R.power
    end
    if s.castBar and (s.castLocked or R.casting or R.linger) then
        return R.cast
    end
    return nil
end

-- In combat, from the combat events (falls back to asking the game before the first one).
function R.InCombat()
    if R.inCombat == nil then
        return UnitAffectingCombat("player") and true or false
    end
    return R.inCombat
end

-- Combo points: Cat Form, in combat only (and while the options are open, to see the layout).
function R.ShowsCombo()
    local s = R.Settings()
    local _, token = PowerType()
    return s.comboStyle ~= "hide" and token == "ENERGY" and (R.InCombat() or R.unlocked) and true or false
end

local function FontSize(height)
    return math.max(8, math.min(14, math.floor(height * 0.75 + 0.5)))
end

local function PlaceBar(bar, y, height)
    local s = R.Settings()
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", R.frame, "TOPLEFT", 0, -y)
    bar:SetSize(s.width, height)
    local size = FontSize(height)
    bar.left:SetFont(FONT, size, "OUTLINE")
    bar.right:SetFont(FONT, size, "OUTLINE")
    bar.centre:SetFont(FONT, size, "OUTLINE")
    bar:Show()
    return y + height + s.padding
end

function R.ApplyStyle()
    local s = R.Settings()
    local texture = STYLE_TEXTURE[s.style] or STYLE_TEXTURE.flat
    if R.heal then
        R.heal:SetStatusBarTexture(texture)
        R.heal:SetStatusBarColor(HEAL_COLOUR[1], HEAL_COLOUR[2], HEAL_COLOUR[3], 1)
    end
    for _, bar in ipairs({ R.health, R.mana, R.power, R.cast }) do
        bar:SetStatusBarTexture(texture)
        local fill = bar:GetStatusBarTexture()
        bar.gloss:ClearAllPoints()
        bar.gloss:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        bar.gloss:SetPoint("BOTTOMRIGHT", fill, "RIGHT", 0, 0)
        bar.gloss:SetShown(s.style == "flat")
    end
    R.AnchorHeal()
    -- The combo bar's segments follow the same style.
    for _, seg in ipairs(R.comboSegments or {}) do
        seg.fill:SetStatusBarTexture(texture)
        seg.gloss:ClearAllPoints()
        seg.gloss:SetPoint("TOPLEFT", seg.fill, "TOPLEFT", 0, 0)
        seg.gloss:SetPoint("BOTTOMRIGHT", seg.fill:GetStatusBarTexture(), "RIGHT", 0, 0)
        seg.gloss:SetShown(s.style == "flat")
    end
end

-- One segment of the combo bar: a subtle border, a dark inside, and a fill that's either
-- empty or full (range [i-1, i], value = combo points). Border and fill sit inside the
-- segment's size, so the bar never exceeds the width/height settings.
local function NewSegment(parent)
    local seg = CreateFrame("Frame", nil, parent)
    local border = seg:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(seg)
    border:SetColorTexture(0.55, 0.55, 0.55, 0.6)
    local inside = seg:CreateTexture(nil, "BORDER")
    inside:SetPoint("TOPLEFT", seg, "TOPLEFT", 1, -1)
    inside:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -1, 1)
    inside:SetColorTexture(0, 0, 0, 0.75)
    local fill = CreateFrame("StatusBar", nil, seg)
    fill:SetPoint("TOPLEFT", seg, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -1, 1)
    fill:SetStatusBarTexture(STYLE_TEXTURE.flat)
    fill:SetStatusBarColor(COMBO_COLOUR[1], COMBO_COLOUR[2], COMBO_COLOUR[3], 1)
    local gloss = fill:CreateTexture(nil, "OVERLAY")
    gloss:SetColorTexture(1, 1, 1, GLOSS_ALPHA)
    gloss:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    gloss:SetPoint("BOTTOMRIGHT", fill:GetStatusBarTexture(), "RIGHT", 0, 0)
    seg.fill, seg.gloss = fill, gloss
    -- Same style as the other bars (flat or shaded).
    local style = R.Settings().style
    fill:SetStatusBarTexture(STYLE_TEXTURE[style] or STYLE_TEXTURE.flat)
    gloss:SetShown(style ~= "shaded")
    return seg
end

-- The full-combo glow: a switch bar that's full only at max combo points, and a clip frame
-- that's as wide as the switch's fill, so the glow inside is only drawn when you're full.
-- Inside: a gold edge around each segment and a soft gold flash, pulsing (as DruidSequence).
local function BuildGlow()
    local area = CreateFrame("Frame", nil, R.comboBar)
    area:SetPoint("TOPLEFT", R.comboBar, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    area:SetPoint("BOTTOMRIGHT", R.comboBar, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
    local switch = CreateFrame("StatusBar", nil, R.comboBar)
    switch:SetAllPoints(area)
    switch:SetStatusBarTexture(STYLE_TEXTURE.flat)
    switch:SetStatusBarColor(0, 0, 0, 0)
    switch:SetMinMaxValues(0, 1)
    switch:SetValue(0)
    local clip = CreateFrame("Frame", nil, R.comboBar)
    clip:SetClipsChildren(true)
    clip:SetPoint("TOPLEFT", switch, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", switch:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    clip:SetFrameLevel(R.comboBar:GetFrameLevel() + 10)
    local glow = CreateFrame("Frame", nil, clip)
    glow:SetAllPoints(area)
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(0.35)
    pulse:Play()
    R.glow = { area = area, switch = switch, clip = clip, frame = glow, pulse = pulse, pieces = {} }
end

-- Gold edges and flash around segment i (reusing textures between layouts).
local function GlowAround(i, seg)
    local pieces = R.glow.pieces[i]
    if not pieces then
        pieces = {}
        local r, g, b = GLOW_COLOUR[1], GLOW_COLOUR[2], GLOW_COLOUR[3]
        for e = 1, 4 do
            local t = R.glow.frame:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(r, g, b, 1)
            pieces[e] = t
        end
        local flash = R.glow.frame:CreateTexture(nil, "OVERLAY")
        flash:SetColorTexture(r, g, b, 0.35)
        flash:SetBlendMode("ADD")
        pieces[5] = flash
        R.glow.pieces[i] = pieces
    end
    -- Top and bottom edges span the corners; left and right fill in between.
    local G = GLOW_SIZE
    pieces[1]:ClearAllPoints()
    pieces[1]:SetPoint("BOTTOMLEFT", seg, "TOPLEFT", -G, 0)
    pieces[1]:SetPoint("TOPRIGHT", seg, "TOPRIGHT", G, G)
    pieces[1]:Show()
    pieces[2]:ClearAllPoints()
    pieces[2]:SetPoint("TOPLEFT", seg, "BOTTOMLEFT", -G, 0)
    pieces[2]:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", G, -G)
    pieces[2]:Show()
    pieces[3]:ClearAllPoints()
    pieces[3]:SetPoint("TOPRIGHT", seg, "TOPLEFT", 0, 0)
    pieces[3]:SetPoint("BOTTOMLEFT", seg, "BOTTOMLEFT", -G, 0)
    pieces[3]:Show()
    pieces[4]:ClearAllPoints()
    pieces[4]:SetPoint("TOPLEFT", seg, "TOPRIGHT", 0, 0)
    pieces[4]:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", G, 0)
    pieces[4]:Show()
    pieces[5]:ClearAllPoints()
    pieces[5]:SetAllPoints(seg)
    pieces[5]:Show()
end

-- A gold edge just outside a frame plus a soft gold flash over it, pulsing like
-- DruidSequence's glow. Returns a table with Show/Hide.
-- pulseTime: seconds per fade (default 0.35, Omen of Clarity's urgent pulse).
function R.EdgeGlow(target, pulseTime)
    local holder = CreateFrame("Frame", nil, target)
    holder:SetPoint("TOPLEFT", target, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    holder:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
    holder:SetFrameLevel(target:GetFrameLevel() + 25)
    local r, g, b = GLOW_COLOUR[1], GLOW_COLOUR[2], GLOW_COLOUR[3]
    local G = GLOW_SIZE
    local function Edge(p1, x1, y1, p2, x2, y2)
        local t = holder:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, 1)
        t:SetPoint(p1, target, p1, x1, y1)
        t:SetPoint(p2, target, p2, x2, y2)
        return t
    end
    local top = holder:CreateTexture(nil, "OVERLAY")
    top:SetColorTexture(r, g, b, 1)
    top:SetPoint("BOTTOMLEFT", target, "TOPLEFT", -G, 0)
    top:SetPoint("TOPRIGHT", target, "TOPRIGHT", G, G)
    local bottom = holder:CreateTexture(nil, "OVERLAY")
    bottom:SetColorTexture(r, g, b, 1)
    bottom:SetPoint("TOPLEFT", target, "BOTTOMLEFT", -G, 0)
    bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", G, -G)
    local left = holder:CreateTexture(nil, "OVERLAY")
    left:SetColorTexture(r, g, b, 1)
    left:SetPoint("TOPRIGHT", target, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -G, 0)
    local right = holder:CreateTexture(nil, "OVERLAY")
    right:SetColorTexture(r, g, b, 1)
    right:SetPoint("TOPLEFT", target, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", G, 0)
    local flash = holder:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints(target)
    flash:SetColorTexture(r, g, b, 0.35)
    flash:SetBlendMode("ADD")
    local pulse = holder:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(pulseTime or 0.35)
    holder:Hide()
    local glow = { frame = holder, pulse = pulse, flash = flash }
    function glow.Show()
        if not holder:IsShown() then
            holder:Show()
            pulse:Play()
        end
    end
    function glow.Hide()
        pulse:Stop()
        holder:Hide()
    end
    return glow
end

-- Is Omen of Clarity's Clearcasting up? Two ways, as the client may hide auras in combat:
--   aura: C_UnitAuras.GetPlayerAuraBySpellID, when it answers;
--   cost: Clearcasting makes the next spell free, so a known spell's (readable) cost drops to 0.
-- Returns active, and which way told us (for /druidbar clearcasting).
R.PROBES = { "Claw", "Shred", "Rake", "Maul", "Swipe", "Healing Touch", "Regrowth", "Rejuvenation", "Wrath",
    "Moonfire" }

function R.ProbeCost(spell)
    if not (C_Spell and C_Spell.GetSpellPowerCost) then
        return nil
    end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spell)
    if not ok or type(costs) ~= "table" or #costs == 0 then
        return nil
    end
    local info = costs[1]
    if type(info.cost) == "number" and not IsSecret(info.cost) then
        return info.cost
    end
end

function R.ClearcastingActive()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, CLEARCASTING)
        if ok and aura ~= nil then
            return true, "aura"
        end
    end
    -- Free spells: only counts if a spell that normally costs something now costs 0.
    R.normalCost = R.normalCost or {}
    for _, spell in ipairs(R.PROBES) do
        local cost = R.ProbeCost(spell)
        if cost and cost > 0 then
            R.normalCost[spell] = cost
        elseif cost == 0 and R.normalCost[spell] then
            return true, "cost of " .. spell
        end
    end
    return false, nil
end

function R.UpdateClearcasting()
    if not R.frame then
        return
    end
    -- Kept for DruidBar's energy warning, which goes back to plain yellow while it's up.
    local clearcasting = R.ClearcastingActive() and true or false
    if clearcasting ~= R.clearcasting then
        R.clearcasting = clearcasting
        if ns.EnergyCostsChanged then
            ns.EnergyCostsChanged()
        end
    end
    local active = R.Settings().clearcastGlow and clearcasting
    for _, bar in ipairs({ R.mana, R.power }) do
        if active and bar:IsShown() then
            bar.procGlow.Show()
        else
            bar.procGlow.Hide()
        end
    end
end

local function ComboCount()
    local count = UnitPowerMax("player", POWER.COMBO)
    if type(count) ~= "number" or IsSecret(count) or count < 1 or count > 10 then
        count = 5
    end
    return count
end

-- Returns the new y.
local function LayoutComboBar(y)
    local s = R.Settings()
    local count = ComboCount()
    local height = s.powerHeight
    local segWidth = (s.width - (count - 1) * SEGMENT_GAP) / count
    R.comboBar:ClearAllPoints()
    R.comboBar:SetPoint("TOPLEFT", R.frame, "TOPLEFT", 0, -y)
    R.comboBar:SetSize(s.width, height)
    if not R.glow then
        BuildGlow()
    end
    local texture = STYLE_TEXTURE[s.style] or STYLE_TEXTURE.flat
    for i = 1, math.max(count, #R.comboSegments) do
        local seg = R.comboSegments[i]
        if i <= count then
            seg = seg or NewSegment(R.comboBar)
            R.comboSegments[i] = seg
            seg:ClearAllPoints()
            seg:SetSize(segWidth, height)
            seg:SetPoint("TOPLEFT", R.comboBar, "TOPLEFT", (i - 1) * (segWidth + SEGMENT_GAP), 0)
            seg.fill:SetStatusBarTexture(texture)
            seg.fill:SetMinMaxValues(i - 1, i)
            seg.gloss:SetShown(s.style == "flat")
            seg:Show()
            GlowAround(i, seg)
        elseif seg then
            seg:Hide()
            for _, t in ipairs(R.glow.pieces[i] or {}) do
                t:Hide()
            end
        end
    end
    R.glow.switch:SetMinMaxValues(count - 1, count)
    R.comboBar:Show()
    return y + height
end

function R.Layout()
    if not R.frame then
        return
    end
    local s = R.Settings()
    local y = 0
    y = PlaceBar(R.health, y, s.healthHeight)
    R.AnchorHeal()
    y = PlaceBar(R.mana, y, s.powerHeight)

    R.power:Hide()
    R.cast:Hide()
    if R.BarPower() then
        y = PlaceBar(R.power, y, s.powerHeight)
    end
    if R.CastRowShown() then
        y = PlaceBar(R.cast, y, s.powerHeight)
    end

    R.comboBar:Hide()
    if R.ShowsCombo() and s.comboStyle == "bar" then
        R.combo:Hide()
        y = LayoutComboBar(y)
    elseif R.ShowsCombo() then
        local count = ComboCount()
        local size = math.max(10, math.min(24, s.powerHeight + 4))
        local gap = math.max(2, math.floor(size / 3))
        local total = count * size + (count - 1) * gap
        R.combo:ClearAllPoints()
        R.combo:SetPoint("TOPLEFT", R.frame, "TOPLEFT", 0, -(y + 2))
        R.combo:SetSize(s.width, size)
        for i = 1, math.max(count, #R.comboPoints) do
            local point = R.comboPoints[i]
            if i <= count then
                point = point or NewComboPoint(R.combo)
                R.comboPoints[i] = point
                point:ClearAllPoints()
                point:SetSize(size, size)
                point:SetPoint("LEFT", R.combo, "LEFT", (s.width - total) / 2 + (i - 1) * (size + gap), 0)
                point.fill:SetMinMaxValues(i - 1, i)
                point:Show()
            elseif point then
                point:Hide()
            end
        end
        R.combo:Show()
        y = y + 2 + size
    else
        R.combo:Hide()
        y = y - s.padding
    end
    if R.cast:IsShown() then
        R.UpdateSpark()
    end

    R.frame:SetSize(s.width, math.max(1, y))
    R.frame:SetScale(s.scale)
    R.frame:SetAlpha(s.opacity)
    if ns.Buffs then
        ns.Buffs.Layout()
    end
end

-- Default spot: centred, a little below the middle of the screen (where the PRD sits).
function R.DefaultPosition()
    return UIParent:GetWidth() / 2, UIParent:GetHeight() / 2 - 110
end

function R.ApplyPosition()
    if not R.frame then
        return
    end
    local s = R.Settings()
    local x, y = s.x, s.y
    if type(x) ~= "number" or type(y) ~= "number" then
        x, y = R.DefaultPosition()
    end
    if s.keepCentred then
        x = UIParent:GetWidth() / 2
    end
    -- Offsets are in the frame's own (scaled) units.
    R.frame:ClearAllPoints()
    R.frame:SetPoint("TOP", UIParent, "BOTTOMLEFT", x / s.scale, y / s.scale)
    if ns.Buffs then
        ns.Buffs.Layout()
    end
end

-- Cursor position in UIParent units.
function R.Cursor()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return cx / scale, cy / scale
end

function R.StartDrag()
    local s = R.Settings()
    local left, right, top = R.frame:GetLeft(), R.frame:GetRight(), R.frame:GetTop()
    if not (left and right and top) then
        return
    end
    local cx, cy = R.Cursor()
    R.drag = { dx = (left + right) / 2 * s.scale - cx, dy = top * s.scale - cy }
    if s.keepCentred then
        R.guide:Show()
    end
    R.frame:SetScript("OnUpdate", R.DragUpdate)
end

function R.DragUpdate()
    if not R.drag then
        return
    end
    local s = R.Settings()
    local cx, cy = R.Cursor()
    s.x = s.keepCentred and UIParent:GetWidth() / 2 or (cx + R.drag.dx)
    s.y = cy + R.drag.dy
    R.ApplyPosition()
end

function R.StopDrag()
    if not R.drag then
        return
    end
    R.DragUpdate()
    R.drag = nil
    R.frame:SetScript("OnUpdate", nil)
    R.guide:Hide()
end

function R.ResetPosition()
    local s = R.Settings()
    s.x, s.y = nil, nil
    R.ApplyPosition()
end

-- Locked frames let left clicks through to the world. SetPassThroughButtons is blocked in
-- combat (ADDON_ACTION_BLOCKED), so it's only called when the setting actually changes, and
-- in combat it waits until combat ends. (The frames ignore the mouse in combat anyway.)
do
    local applied, waiting = {}, {}
    local function Apply(frame, passLeft)
        if applied[frame] == passLeft then
            return
        end
        if InCombatLockdown() then
            waiting[frame] = passLeft
            return
        end
        applied[frame] = passLeft
        if passLeft then
            pcall(frame.SetPassThroughButtons, frame, "LeftButton")
        else
            pcall(frame.SetPassThroughButtons, frame)
        end
    end
    function ns.SetPassThrough(frame, passLeft)
        if frame and frame.SetPassThroughButtons then
            waiting[frame] = nil
            Apply(frame, passLeft and true or false)
        end
    end
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function()
        for frame, passLeft in pairs(waiting) do
            waiting[frame] = nil
            Apply(frame, passLeft)
        end
    end)
end

-- Unlocked while the options page is open (not saved).
function R.SetUnlocked(unlocked)
    R.unlocked = unlocked and true or false
    if R.frame then
        ns.SetPassThrough(R.frame, not R.unlocked)
        R.unlockTint:SetShown(R.unlocked)
        R.unlockLabel:SetShown(R.unlocked)
        R.UpdateIdleCast()
        -- Combo points show while unlocked (to see the layout), otherwise only in combat.
        if R.health then
            R.Layout()
            R.UpdateCombo()
        end
        if ns.Buffs then
            ns.Buffs.Refresh()
        end
        if not R.unlocked then
            R.StopDrag()
        end
    end
    R.UpdateVisibility()
end

----------------------------------------------------------------------------------------------
-- Values and text
----------------------------------------------------------------------------------------------

local function Percent(kind, powerType)
    if not (CurveConstants and CurveConstants.ScaleTo100) then
        return nil
    end
    local fn = kind == "health" and UnitHealthPercent or UnitPowerPercent
    if not fn then
        return nil
    end
    local ok, value
    if kind == "health" then
        ok, value = pcall(fn, "player", false, CurveConstants.ScaleTo100)
    else
        ok, value = pcall(fn, "player", powerType, false, CurveConstants.ScaleTo100)
    end
    if ok then
        return value
    end
end

-- Health and mana: current on the left, max (or percent) on the right. Energy and rage
-- (showMax false): just the current amount, or its percent in percent mode.
local function SetBarText(bar, current, max, kind, powerType, showMax)
    local mode = R.Settings().text
    bar.left:SetText("")
    bar.right:SetText("")
    bar.centre:SetText("")
    if mode == "none" then
        return
    end
    if mode == "centre" then
        bar.centre:SetFormattedText("%s", current)
        return
    end
    if mode == "percent" then
        local pct = Percent(kind, powerType)
        if pct ~= nil then
            bar.left:SetFormattedText("%.0f%%", pct)
        end
        return
    end
    bar.left:SetFormattedText("%s", current)
    if not showMax or mode == "current" then
        return
    end
    if mode == "both" then
        local pct = Percent(kind, powerType)
        if pct ~= nil then
            bar.right:SetFormattedText("%.0f%%", pct)
        end
    else
        bar.right:SetFormattedText("%s", max)
    end
end

-- Incoming heals on the player (may be secret), and where the number came from.
function R.IncomingHeals()
    -- Midnight: the heal prediction calculator.
    if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
        R.healCalculator = R.healCalculator or CreateUnitHealPredictionCalculator()
        local calc = R.healCalculator
        if calc and pcall(UnitGetDetailedHealPrediction, "player", nil, calc) and calc.GetIncomingHeals then
            local ok, amount = pcall(calc.GetIncomingHeals, calc)
            if ok and amount ~= nil then
                return amount, "heal prediction calculator"
            end
        end
    end
    -- Older clients.
    if UnitGetIncomingHeals then
        local ok, amount = pcall(UnitGetIncomingHeals, "player")
        if ok and amount ~= nil then
            return amount, "UnitGetIncomingHeals"
        end
    end
    return nil, "none"
end

-- The heal bar starts at the end of the health fill and is as wide as the whole bar.
function R.AnchorHeal()
    if not R.heal then
        return
    end
    local fill = R.health:GetStatusBarTexture()
    R.heal:ClearAllPoints()
    R.heal:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    R.heal:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    R.heal:SetWidth(math.max(1, R.health:GetWidth() or 1))
end

-- Health colour gradient: green at 80% and above, red at 20% and below, and through yellow and
-- orange in between, in 2% steps. Health is secret in combat, so the Midnight way is a colour
-- curve that the game evaluates itself (UnitHealthPercent with a curve gives back a colour the
-- bar can take as it is). With no curve API, health is read directly when it's readable.
do
    local STEP = 0.02
    local YELLOW, ORANGE, RED = { 0.90, 0.80, 0.15 }, { 0.95, 0.50, 0.10 }, { 0.80, 0.10, 0.08 }

    local function Green()
        local c = ns.COLOURS and ns.COLOURS.HEALTH
        return c or { 0.40, 0.73, 0.17 }
    end

    local function Lerp(a, b, t)
        return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
    end

    -- The colour for a health fraction (0-1), in steps.
    function R.GradientColour(fraction)
        local green = Green()
        if fraction >= 0.8 then
            return green[1], green[2], green[3]
        elseif fraction <= 0.2 then
            return RED[1], RED[2], RED[3]
        end
        local p = math.floor(fraction / STEP + 1e-6) * STEP
        if p >= 0.6 then
            return Lerp(YELLOW, green, (p - 0.6) / 0.2)
        elseif p >= 0.4 then
            return Lerp(ORANGE, YELLOW, (p - 0.4) / 0.2)
        end
        return Lerp(RED, ORANGE, (p - 0.2) / 0.2)
    end

    local curve
    local function Curve()
        if curve ~= nil then
            return curve or nil
        end
        curve = false
        if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then
            return nil
        end
        local ok, made = pcall(C_CurveUtil.CreateColorCurve)
        if not ok or not made then
            return nil
        end
        if made.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
            pcall(made.SetType, made, Enum.LuaCurveType.Step)
        end
        local function Add(x)
            local r, g, b = R.GradientColour(x)
            made:AddPoint(x, CreateColor(r, g, b, 1))
        end
        local okAdd = pcall(function()
            Add(0)
            for i = 10, 40 do Add(i * STEP) end -- 0.20 to 0.80
            Add(1)
        end)
        curve = okAdd and made or false
        return curve or nil
    end

    -- The colour for a unit's current health (default the player), and how it was found.
    function R.HealthGradient(unit)
        unit = unit or "player"
        local c = Curve()
        if c and UnitHealthPercent then
            local ok, colour = pcall(UnitHealthPercent, unit, false, c)
            if ok and colour and colour.GetRGB then
                local r, g, b = colour:GetRGB()
                return r, g, b, "colour curve"
            end
        end
        local current, max = UnitHealth(unit), UnitHealthMax(unit)
        if not IsSecret(current) and not IsSecret(max) and current and max and max > 0 then
            local r, g, b = R.GradientColour(current / max)
            return r, g, b, "readable health"
        end
        return nil, nil, nil, "none (health secret, no colour curve)"
    end

    function R.UpdateHealthColour()
        if not R.health then
            return
        end
        if R.Settings().healthGradient then
            local r, g, b = R.HealthGradient()
            if r ~= nil then
                R.health:SetStatusBarColor(r, g, b, 1)
                return
            end
        end
        local green = Green()
        R.health:SetStatusBarColor(green[1], green[2], green[3], 1)
    end
end

function R.UpdateHealth()
    if not R.frame then
        return
    end
    local current, max = UnitHealth("player"), UnitHealthMax("player")
    R.health:SetMinMaxValues(0, max)
    R.health:SetValue(current)
    SetBarText(R.health, current, max, "health", nil, true)
    R.UpdateHealthColour()
    if R.heal then
        local incoming = R.IncomingHeals()
        R.heal:SetMinMaxValues(0, max)
        R.heal:SetValue(incoming or 0)
    end
end

function R.UpdateMana()
    if not R.frame then
        return
    end
    local current, max = UnitPower("player", POWER.MANA), UnitPowerMax("player", POWER.MANA)
    R.mana:SetMinMaxValues(0, max)
    R.mana:SetValue(current)
    SetBarText(R.mana, current, max, "power", POWER.MANA, true)
end

function R.UpdatePower()
    if not R.frame then
        return
    end
    local powerType = R.BarPower()
    if powerType == nil then
        return
    end
    local current, max = UnitPower("player", powerType), UnitPowerMax("player", powerType)
    R.power:SetMinMaxValues(0, max)
    R.power:SetValue(current)
    SetBarText(R.power, current, max, "power", powerType, false)
end

function R.UpdateCombo()
    if not R.frame then
        return
    end
    local value = UnitPower("player", POWER.COMBO)
    for _, point in ipairs(R.comboPoints) do
        point.fill:SetValue(value)
    end
    for _, seg in ipairs(R.comboSegments) do
        seg.fill:SetValue(value)
    end
    if R.glow then
        R.glow.switch:SetValue(value)
    end
end

-- Colours: DruidBar's measured Player Frame colours (ns.COLOURS), by power.
function R.ApplyColours()
    if not R.frame then
        return
    end
    local colours = ns.COLOURS or {}
    local function Paint(bar, key, fallback)
        local c = colours[key] or fallback
        bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    end
    R.UpdateHealthColour()
    Paint(R.mana, "MANA", { 0, 0.34, 0.73 })
    local _, token = R.BarPower()
    Paint(R.power, token or "", { 1, 1, 1 })
end

----------------------------------------------------------------------------------------------
-- Cast bar (caster form)
----------------------------------------------------------------------------------------------

-- The bar runs from 0 to the cast's length in seconds, like Blizzard's. (It used to take the
-- game's clock in milliseconds, around 470 million: status bars keep values at single
-- precision, which at that size only moves in ~32 ms steps, and the bar looked jerky.)
function R.CastRange(c)
    if not IsSecret(c.startMS) and not IsSecret(c.endMS) and c.startMS and c.endMS then
        c.relative = true
        return 0, math.max(0.001, (c.endMS - c.startMS) / 1000)
    end
    -- Secret times: no arithmetic, so the absolute times as they are.
    c.relative = false
    return c.startMS, c.endMS
end

function R.CastValue()
    local c = R.casting
    if c.relative then
        local elapsed = GetTime() - c.startMS / 1000
        local length = (c.endMS - c.startMS) / 1000
        if elapsed < 0 then elapsed = 0 elseif elapsed > length then elapsed = length end
        -- Channels drain from full.
        return c.channel and (length - elapsed) or elapsed
    end
    return GetTime() * 1000
end

-- A spell's mana cost, if it has a readable one.
local function ManaCost(spellID)
    if spellID == nil or IsSecret(spellID) or not (C_Spell and C_Spell.GetSpellPowerCost) then
        return nil
    end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then
        return nil
    end
    for _, info in ipairs(costs) do
        local isMana = (info.type == POWER.MANA) or (info.name == "MANA")
        if not IsSecret(info.type) and isMana and type(info.cost) == "number" and not IsSecret(info.cost)
            and info.cost > 0 then
            return info.cost
        end
    end
end

function R.UpdateSpark()
    local spark = R.cast.spark
    if R.casting then
        local h = R.cast:GetHeight()
        spark:SetSize(math.max(8, h * 0.9), h * 2.2)
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", R.cast:GetStatusBarTexture(), "RIGHT", 0, 0)
        spark:Show()
    else
        spark:Hide()
    end
end

local function SetCastText(name, spellID)
    R.cast.left:SetText("")
    R.cast.right:SetText("")
    local cost = ManaCost(spellID)
    if cost then
        R.cast.centre:SetFormattedText("%s (%d)", name, cost)
    else
        R.cast.centre:SetFormattedText("%s", name)
    end
end

local function SetCastAlpha(alpha)
    R.cast:GetStatusBarTexture():SetAlpha(alpha)
    R.cast.centre:SetAlpha(alpha)
    R.cast.gloss:SetAlpha(alpha)
end

-- The empty cast row keeps its place (if locked) but isn't drawn, except while unlocked so
-- the layout can be seen.
function R.UpdateIdleCast()
    if R.cast and not (R.casting or R.linger) then
        R.cast:SetAlpha(R.unlocked and 1 or 0)
    end
end

-- The empty cast row (locked in place, nothing to show).
function R.ClearCast()
    R.casting = nil
    R.linger = nil
    R.cast:SetMinMaxValues(0, 1)
    R.cast:SetValue(0)
    R.cast.centre:SetText("")
    SetCastAlpha(1)
    R.UpdateIdleCast()
    R.UpdateSpark()
    R.Layout()
end

-- After a spell goes off (a finished cast or channel, or an instant): show it full, with
-- its name and cost, for LINGER_TIME seconds, then fade. A new spell or a shift replaces it.
function R.StartLinger(name, spellID)
    local s = R.Settings()
    R.casting = nil
    -- Only spells that cost mana linger: skinning, opening, gathering and the like just end.
    if not (s.castLinger and name and ManaCost(spellID)) then
        R.ClearCast()
        return
    end
    R.linger = { start = GetTime() }
    R.cast:SetMinMaxValues(0, 1)
    R.cast:SetValue(1)
    SetCastText(name, spellID)
    SetCastAlpha(1)
    R.cast:SetAlpha(1)
    R.cast.flashAnim:Stop()
    R.cast.flashAnim:Play()
    R.UpdateSpark()
    R.Layout()
end

function R.UpdateLinger()
    local t = GetTime() - R.linger.start
    if t >= LINGER_TIME + 2 * LINGER_FADE then
        R.ClearCast()
    elseif t > LINGER_TIME + LINGER_FADE then
        -- The name has gone: now the bar fades out.
        R.cast.centre:SetAlpha(0)
        R.cast:SetAlpha(1 - (t - LINGER_TIME - LINGER_FADE) / LINGER_FADE)
    elseif t > LINGER_TIME then
        R.cast.centre:SetAlpha(1 - (t - LINGER_TIME) / LINGER_FADE)
    end
end

-- UNIT_SPELLCAST_SUCCEEDED: an instant (or a cast that just finished; STOP follows it).
-- Channels report SUCCEEDED when they start, so those wait for CHANNEL_STOP instead.
function R.SpellSucceeded(spellID)
    local powerType = PowerType()
    if not R.Settings().castBar then
        return
    end
    if R.casting and R.casting.channel then
        return
    end
    -- In Cat/Bear only casts with a cast time linger (not every Claw).
    if powerType ~= POWER.MANA and not R.casting then
        return
    end
    local name = R.casting and R.casting.name
    if not name and C_Spell and C_Spell.GetSpellName and spellID ~= nil and not IsSecret(spellID) then
        name = C_Spell.GetSpellName(spellID)
    end
    if name then
        R.StartLinger(name, spellID)
    end
end

function R.StartCast(channel, spellID)
    local name, text, texture, startMS, endMS
    if channel then
        name, text, texture, startMS, endMS = UnitChannelInfo("player")
    else
        name, text, texture, startMS, endMS = UnitCastingInfo("player")
    end
    if not name then
        R.StopCast()
        return
    end
    R.linger = nil
    R.casting = { channel = channel, startMS = startMS, endMS = endMS, name = name, spellID = spellID }
    R.cast:SetMinMaxValues(R.CastRange(R.casting))
    R.cast:SetValue(R.CastValue())
    SetCastAlpha(1)
    R.cast:SetAlpha(1)
    -- Centred: the spell's name, with its mana cost in brackets.
    SetCastText(name, spellID)
    R.Layout()
    R.UpdateSpark()
end

-- A channel ended (finished or cut short): show it as gone off.
function R.ChannelStopped()
    local c = R.casting
    if c and c.channel then
        R.StartLinger(c.name, c.spellID)
    end
end

-- Cancelled, failed or interrupted: nothing to show.
function R.StopCast()
    if R.casting or R.linger then
        R.ClearCast()
    end
end

----------------------------------------------------------------------------------------------
-- Visibility, refresh, events
----------------------------------------------------------------------------------------------

function R.ShouldShow()
    local s = R.Settings()
    if not (s.enabled and R.frame and ns.IsDruid and ns.IsDruid()) then
        return false
    end
    if R.unlocked then
        return true -- always visible while you're placing it
    end
    if s.visibility == "hidden" then
        return false
    elseif s.visibility == "combat" then
        return UnitAffectingCombat("player") and true or false
    elseif s.visibility == "combatOrTarget" then
        return (UnitAffectingCombat("player") or UnitExists("target")) and true or false
    end
    return true
end

function R.UpdateVisibility()
    if not R.frame then
        return
    end
    local was = R.frame:IsShown()
    R.frame:SetShown(R.ShouldShow())
    -- DruidBar's overlays (shift shading, Claw orange, 5SR marker) go on or come off our bars.
    if was ~= R.frame:IsShown() and ns.OverlaysChanged then
        ns.OverlaysChanged()
    end
end

-- Bars DruidBar draws on (only while the frame is shown).
function R.ManaBar()
    if R.frame and R.frame:IsShown() then
        return R.mana
    end
end
-- The energy or rage bar (for DruidBar's warning), while shown.
function R.EnergyBar()
    local _, token = PowerType()
    if R.frame and R.frame:IsShown() and (token == "ENERGY" or token == "RAGE") then
        return R.power
    end
end

-- Everything: called at login, on form changes (from DruidBar's form watcher) and when
-- options change.
function R.Refresh()
    if not (ns.IsDruid and ns.IsDruid()) then
        if R.frame then
            R.frame:Hide()
        end
        return
    end
    R.Build()
    local form = GetShapeshiftFormID()
    if form ~= R.lastForm then
        R.lastForm = form
        R.casting, R.linger = nil, nil
        R.cast:SetMinMaxValues(0, 1)
        R.cast:SetValue(0)
        R.cast.centre:SetText("")
    end
    R.UpdateIdleCast()
    R.ApplyStyle()
    R.Layout()
    R.ApplyPosition()
    R.ApplyColours()
    R.UpdateHealth()
    R.UpdateMana()
    R.UpdatePower()
    R.UpdateCombo()
    R.SetUnlocked(R.unlocked)
    R.UpdateClearcasting()
    if ns.Buffs then
        ns.Buffs.Refresh()
    end
    -- A range bar attached to the display follows its size and position.
    if ns.Range and ns.Range.RefreshLayout then
        ns.Range.RefreshLayout()
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION",
    "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA", "SPELL_UPDATE_USABLE", "SPELLS_CHANGED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, unit, powerToken, spellID)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        R.Refresh()
        return
    end
    if not R.frame then
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_TARGET_CHANGED" then
        if event ~= "PLAYER_TARGET_CHANGED" then
            R.inCombat = (event == "PLAYER_REGEN_DISABLED")
            -- Combo points and the caster-form energy bar come and go with combat.
            R.Layout()
            R.ApplyColours()
            R.UpdatePower()
            if R.UpdateCombo then R.UpdateCombo() end
        end
        R.UpdateVisibility()
        return
    end
    if event == "SPELL_UPDATE_USABLE" or event == "SPELLS_CHANGED" then
        R.UpdateClearcasting()
        return
    end
    if unit ~= "player" then
        return
    end
    if event == "UNIT_AURA" then
        R.UpdateClearcasting()
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_HEAL_PREDICTION" then
        R.UpdateHealth()
    elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
        if powerToken == "MANA" then
            R.UpdateMana()
        elseif powerToken == "COMBO_POINTS" then
            if event == "UNIT_MAXPOWER" then
                R.Layout()
            end
            R.UpdateCombo()
        else
            R.UpdatePower()
        end
    elseif event == "UNIT_DISPLAYPOWER" then
        R.Refresh()
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        R.StartCast(false, spellID) -- (unit, castGUID, spellID): powerToken holds the castGUID here
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        R.StartCast(true, spellID)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        R.SpellSucceeded(spellID)
        R.UpdateClearcasting()
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        R.ChannelStopped()
    elseif event == "UNIT_SPELLCAST_STOP" then
        -- After SUCCEEDED this is just the cast ending (already showing as gone off).
        if R.casting and not R.casting.channel then
            R.StopCast()
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if R.casting then
            R.StopCast()
        end
    end
end)

function R.DebugClearcasting()
    local active, how = R.ClearcastingActive()
    print("|cff55ff55DruidFrame Clearcasting|r active:", tostring(active), how and ("(" .. how .. ")") or "")
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, CLEARCASTING)
        print("  aura lookup:", ok and (aura ~= nil and "found" or "not found") or ("error: " .. tostring(aura)),
            "| in combat:", tostring(UnitAffectingCombat("player")))
    end
    for _, spell in ipairs(R.PROBES) do
        local cost = R.ProbeCost(spell)
        if cost ~= nil then
            print("  " .. spell .. " costs", cost, "| normally", tostring(R.normalCost and R.normalCost[spell]))
        end
    end
end

function R.Debug()
    local s = R.Settings()
    local powerType, token = PowerType()
    print("|cff55ff55DruidFrame display|r enabled:", tostring(s.enabled), "shown:",
        tostring(R.frame and R.frame:IsShown()), "visibility:", s.visibility, "unlocked:", tostring(R.unlocked))
    local _, _, _, gradientSource = R.HealthGradient()
    print("  health colour:", R.Settings().healthGradient and ("gradient, from " .. gradientSource) or "plain green")
    local incoming, source = R.IncomingHeals()
    print("  incoming heals:", IsSecret(incoming) and "(secret)" or tostring(incoming), "from", source)
    print("  power:", tostring(powerType), tostring(token), "| third row:",
        R.ThirdRow() == R.power and "energy/rage" or R.ThirdRow() == R.cast and "cast bar" or "none",
        "| combo points:", s.comboStyle, tostring(R.ShowsCombo()), "| casting:", tostring(R.casting ~= nil),
        "| lingering:", tostring(R.linger ~= nil))
    print("  size:", s.width, "x", s.healthHeight, "/", s.powerHeight, "padding", s.padding, "scale", s.scale,
        "opacity", s.opacity, "| position:", tostring(s.x), tostring(s.y), "keep centred:", tostring(s.keepCentred))
    print("  health secret:", tostring(IsSecret(UnitHealth("player"))), "| combo points secret:",
        tostring(IsSecret(UnitPower("player", POWER.COMBO))), "max:", tostring(UnitPowerMax("player", POWER.COMBO)))
end

----------------------------------------------------------------------------------------------
-- Options: a page under DruidBar in Esc > Options > AddOns
----------------------------------------------------------------------------------------------

local panel = CreateFrame("Frame", "DruidBarResourceOptionsPanel", UIParent)
panel.name = "DruidFrame"
ns.panels = ns.panels or {}
ns.panels.frame = panel -- registered by Options.lua as the top page
panel:SetSize(620, 600)
panel:Hide()
R.panel = panel

local function Changed()
    if R.frame then
        R.Refresh()
    end
    if ns.OverlaysChanged then
        ns.OverlaysChanged()
    end
end

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("DruidFrame")
local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetWidth(580)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Health, mana and energy/rage bars to use instead of Blizzard's Personal Resource Display " ..
    "(turn Blizzard's off so there aren't two). /druidframe opens this page.")

local widgets = {}

local function Checkbox(name, anchor, label, key, onChange)
    local cb = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    _G[name .. "Text"]:SetText(label)
    cb:SetScript("OnClick", function(self)
        R.Settings()[key] = self:GetChecked() and true or false
        if onChange then onChange() end
        Changed()
    end)
    widgets[#widgets + 1] = function() cb:SetChecked(R.Settings()[key]) end
    return cb
end

-- A button that steps through a list of choices.
local function Cycle(name, anchor, label, key, choices)
    local button = CreateFrame("Button", name, panel, "UIPanelButtonTemplate")
    button:SetSize(260, 22)
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -10)
    local function Label()
        local current = R.Settings()[key]
        for _, choice in ipairs(choices) do
            if choice.key == current then
                return label .. ": " .. choice.label
            end
        end
        return label
    end
    button:SetScript("OnClick", function(self)
        local s = R.Settings()
        local index = 1
        for i, choice in ipairs(choices) do
            if choice.key == s[key] then index = i end
        end
        s[key] = choices[index % #choices + 1].key
        self:SetText(Label())
        Changed()
    end)
    widgets[#widgets + 1] = function() button:SetText(Label()) end
    return button
end

-- A dropdown of choices, with its label above. Uses Blizzard's UIDropDownMenu (works on
-- Forever, see CustomBuffwatch); falls back to the stepping button without it.
local function Dropdown(name, anchor, label, key, choices)
    if not (UIDropDownMenu_Initialize and UIDropDownMenu_AddButton) then
        return Cycle(name, anchor, label, key, choices)
    end
    local caption = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    caption:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -12)
    caption:SetText(label)
    local dd = CreateFrame("Frame", name, panel, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", -18, -2)
    UIDropDownMenu_SetWidth(dd, 230)
    local function LabelFor(value)
        for _, choice in ipairs(choices) do
            if choice.key == value then return choice.label end
        end
        return ""
    end
    UIDropDownMenu_Initialize(dd, function()
        for _, choice in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = choice.label
            info.value = choice.key
            info.checked = (R.Settings()[key] == choice.key)
            info.func = function()
                R.Settings()[key] = choice.key
                UIDropDownMenu_SetText(dd, choice.label)
                Changed()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    widgets[#widgets + 1] = function() UIDropDownMenu_SetText(dd, LabelFor(R.Settings()[key])) end
    dd.caption = caption
    return dd
end

local function Slider(name, anchor, label, key, minV, maxV, step, asPercent, x, y)
    local slider = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
    if x then
        slider:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
    else
        slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -26)
    end
    slider:SetWidth(220)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local function Show(value)
        return asPercent and string.format("%d%%", value * 100 + 0.5) or tostring(value)
    end
    _G[name .. "Low"]:SetText(Show(minV))
    _G[name .. "High"]:SetText(Show(maxV))
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        R.Settings()[key] = value
        _G[name .. "Text"]:SetText(label .. ": " .. Show(value))
        Changed()
    end)
    widgets[#widgets + 1] = function() slider:SetValue(R.Settings()[key]) end
    return slider
end

-- Left column, at fixed positions (anchoring each widget to the one above drifted, because
-- dropdowns carry their own left padding).
local COLUMN_X = 16
local columnY = -64
local function Place(widget, height, x)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", panel, "TOPLEFT", COLUMN_X + (x or 0), columnY)
    columnY = columnY - height
end
local function PlaceDropdown(dd)
    if dd.caption then
        Place(dd.caption, 16, 4)
        Place(dd, 38, -14) -- the template's art starts ~16px in
    else
        Place(dd, 32, 4)
    end
end

local enabledBox = Checkbox("DruidBarResourceEnabled", subtitle, "Show the resource display", "enabled")
Place(enabledBox, 34)
PlaceDropdown(Dropdown("DruidBarResourceVisibility", enabledBox, "Visibility", "visibility", R.VISIBILITY))
PlaceDropdown(Dropdown("DruidBarResourceText", enabledBox, "Text", "text", R.TEXT))
PlaceDropdown(Dropdown("DruidBarResourceStyle", enabledBox, "Bar style", "style", R.STYLE))
PlaceDropdown(Dropdown("DruidBarResourceCombo", enabledBox, "Combo points (Cat Form)", "comboStyle", R.COMBO))
PlaceDropdown(Dropdown("DruidBarResourceCasterEnergy", enabledBox, "Energy bar in caster form (e.g. Furor's regen)",
    "casterEnergy", R.CASTER_ENERGY))
columnY = columnY - 4
Place(Checkbox("DruidBarResourceCentred", enabledBox, "Keep centred (dragging only moves it up and down)",
    "keepCentred"), 28)
Place(Checkbox("DruidBarResourceClearcast", enabledBox, "Glow while Omen of Clarity is up", "clearcastGlow"), 28)
Place(Checkbox("DruidBarResourceCast", enabledBox, "Cast bar below mana in caster form", "castBar"), 28)
Place(Checkbox("DruidBarResourceCastLocked", enabledBox,
    "Keep the cast bar's row in place (not just while casting)", "castLocked"), 28)
Place(Checkbox("DruidBarResourceCastLinger", enabledBox,
    "Show the last spell's name and cost for 3 seconds (instant spells too)", "castLinger"), 28)
Place(Checkbox("DruidBarResourceBuffs", enabledBox,
    "Mark of the Wild (left) and Thorns (right) buttons when missing (out of combat)", "buffButtons"), 28)
Place(Checkbox("DruidBarResourceBuffsPvP", enabledBox,
    "Also in battlegrounds and arenas", "buffButtonsPvP"), 36, 20)


local sizeSlider = Slider("DruidBarResourceScale", subtitle, "Size", "scale", 0.5, 2.0, 0.05, true, 340, -40)
local widthSlider = Slider("DruidBarResourceWidth", sizeSlider, "Bar width", "width", 80, 400, 5)
local healthSlider = Slider("DruidBarResourceHealthHeight", widthSlider, "Health bar height", "healthHeight", 4, 40, 1)
local powerSlider = Slider("DruidBarResourcePowerHeight", healthSlider, "Power bar height", "powerHeight", 4, 40, 1)
local paddingSlider = Slider("DruidBarResourcePadding", powerSlider, "Padding", "padding", 0, 10, 1)
local opacitySlider = Slider("DruidBarResourceOpacity", paddingSlider, "Opacity", "opacity", 0.1, 1.0, 0.05, true)

-- Moving it: in the right column, under the sliders (the left column is full).
local resetButton = CreateFrame("Button", "DruidBarResourceReset", panel, "UIPanelButtonTemplate")
resetButton:SetSize(200, 22)
resetButton:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", 0, -30)
resetButton:SetText("Reset to default position")
resetButton:SetScript("OnClick", function() R.ResetPosition() end)

local moveNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
moveNote:SetPoint("TOPLEFT", resetButton, "BOTTOMLEFT", 0, -10)
moveNote:SetWidth(250)
moveNote:SetJustifyH("LEFT")
moveNote:SetText("While DruidFrame's options are open, drag the display to move it. Right-click it to come back here.")

local gradientBox = Checkbox("DruidBarResourceHealthGradient", moveNote,
    "Health colour: green to red as it drops", "healthGradient")
gradientBox:ClearAllPoints()
gradientBox:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", -4, -24)
resetButton:ClearAllPoints()
resetButton:SetPoint("TOPLEFT", gradientBox, "BOTTOMLEFT", 4, -10)

panel:SetScript("OnShow", function()
    for _, refresh in ipairs(widgets) do
        refresh()
    end
    if ns.PageShown then ns.PageShown(true) end
end)
panel:SetScript("OnHide", function()
    if ns.PageShown then ns.PageShown(false) end
end)

function R.OpenOptions()
    if ns.OpenOptions then
        ns.OpenOptions("frame")
    end
end
