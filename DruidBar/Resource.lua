-- DruidBar resource display: our own replacement for Blizzard's Personal Resource Display.
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
}
-- Bar styles: "flat" copies Blizzard's Personal Resource Display (a plain fill with a lighter
-- top half, measured as about 15% white); "shaded" is Blizzard's classic bar texture.
local STYLE_TEXTURE = {
    flat = "Interface\\Buttons\\WHITE8X8",
    shaded = "Interface\\TargetingFrame\\UI-StatusBar",
}
local GLOSS_ALPHA = 0.15
local FONT = "Fonts\\FRIZQT__.TTF"
local ART = "Interface\\AddOns\\DruidBar\\"
local CAST_COLOUR = { 1.0, 0.7, 0.0 }
local COMBO_COLOUR = { 0.95, 0.25, 0.1 }

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
R.TEXT = {
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
    unlocked = false,
    castBar = true,
    comboPoints = true,
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
    R.mana = NewBar()
    R.power = NewBar()
    R.cast = NewBar()
    R.cast:SetStatusBarColor(CAST_COLOUR[1], CAST_COLOUR[2], CAST_COLOUR[3], 1)

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
    unlockLabel:SetText("DruidBar: drag to move (/druidbar lock)")
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

    f:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and R.Settings().unlocked then
            R.StartDrag()
        end
    end)
    f:SetScript("OnMouseUp", function()
        R.StopDrag()
    end)

    R.cast:SetScript("OnUpdate", function(bar)
        if R.casting then
            bar:SetValue(R.CastValue())
        end
    end)
end

----------------------------------------------------------------------------------------------
-- Layout and position
----------------------------------------------------------------------------------------------

-- The row under mana: the energy/rage bar in Cat/Bear, else the cast bar while casting.
function R.ThirdRow()
    local s = R.Settings()
    local powerType = PowerType()
    if powerType ~= nil and powerType ~= POWER.MANA then
        return R.power
    end
    if s.castBar and R.casting then
        return R.cast
    end
    return nil
end

function R.ShowsCombo()
    local s = R.Settings()
    local _, token = PowerType()
    return s.comboPoints and token == "ENERGY"
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
    bar:Show()
    return y + height + s.padding
end

function R.ApplyStyle()
    local s = R.Settings()
    local texture = STYLE_TEXTURE[s.style] or STYLE_TEXTURE.flat
    for _, bar in ipairs({ R.health, R.mana, R.power, R.cast }) do
        bar:SetStatusBarTexture(texture)
        local fill = bar:GetStatusBarTexture()
        bar.gloss:ClearAllPoints()
        bar.gloss:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        bar.gloss:SetPoint("BOTTOMRIGHT", fill, "RIGHT", 0, 0)
        bar.gloss:SetShown(s.style == "flat")
    end
end

function R.Layout()
    if not R.frame then
        return
    end
    local s = R.Settings()
    local y = 0
    y = PlaceBar(R.health, y, s.healthHeight)
    y = PlaceBar(R.mana, y, s.powerHeight)

    local third = R.ThirdRow()
    R.power:Hide()
    R.cast:Hide()
    if third then
        y = PlaceBar(third, y, s.powerHeight)
    end

    if R.ShowsCombo() then
        local count = UnitPowerMax("player", POWER.COMBO)
        if type(count) ~= "number" or IsSecret(count) or count < 1 or count > 10 then
            count = 5
        end
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

    R.frame:SetSize(s.width, math.max(1, y))
    R.frame:SetScale(s.scale)
    R.frame:SetAlpha(s.opacity)
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
end

-- Cursor position in UIParent units.
local function Cursor()
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
    local cx, cy = Cursor()
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
    local cx, cy = Cursor()
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

function R.SetUnlocked(unlocked)
    local s = R.Settings()
    s.unlocked = unlocked and true or false
    if R.frame then
        R.frame:EnableMouse(s.unlocked)
        R.unlockTint:SetShown(s.unlocked)
        R.unlockLabel:SetShown(s.unlocked)
        if not s.unlocked then
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
    if mode == "none" then
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

function R.UpdateHealth()
    if not R.frame then
        return
    end
    local current, max = UnitHealth("player"), UnitHealthMax("player")
    R.health:SetMinMaxValues(0, max)
    R.health:SetValue(current)
    SetBarText(R.health, current, max, "health", nil, true)
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
    local powerType = PowerType()
    if powerType == nil or powerType == POWER.MANA then
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
    Paint(R.health, "HEALTH", { 0.4, 0.73, 0.17 })
    Paint(R.mana, "MANA", { 0, 0.34, 0.73 })
    local _, token = PowerType()
    Paint(R.power, token or "", { 1, 1, 1 })
end

----------------------------------------------------------------------------------------------
-- Cast bar (caster form)
----------------------------------------------------------------------------------------------

function R.CastValue()
    local now = GetTime() * 1000
    local c = R.casting
    -- Channels drain from full. If the times are secret, just fill instead.
    if c.channel and not IsSecret(c.startMS) and not IsSecret(c.endMS) then
        return c.startMS + c.endMS - now
    end
    return now
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
    R.casting = { channel = channel, startMS = startMS, endMS = endMS }
    R.cast:SetMinMaxValues(startMS, endMS)
    R.cast:SetValue(R.CastValue())
    -- Centred: the spell's name, with its mana cost in brackets.
    R.cast.left:SetText("")
    R.cast.right:SetText("")
    local cost = ManaCost(spellID)
    if cost then
        R.cast.centre:SetFormattedText("%s (%d)", name, cost)
    else
        R.cast.centre:SetFormattedText("%s", name)
    end
    R.Layout()
end

function R.StopCast()
    if R.casting then
        R.casting = nil
        R.Layout()
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
    if s.unlocked then
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
function R.EnergyBar()
    local _, token = PowerType()
    if R.frame and R.frame:IsShown() and token == "ENERGY" then
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
    R.ApplyStyle()
    R.Layout()
    R.ApplyPosition()
    R.ApplyColours()
    R.UpdateHealth()
    R.UpdateMana()
    R.UpdatePower()
    R.UpdateCombo()
    R.SetUnlocked(R.Settings().unlocked)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
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
        R.UpdateVisibility()
        return
    end
    if unit ~= "player" then
        return
    end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
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
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        R.StopCast()
    end
end)

function R.Debug()
    local s = R.Settings()
    local powerType, token = PowerType()
    print("|cff55ff55DruidBar resource display|r enabled:", tostring(s.enabled), "shown:",
        tostring(R.frame and R.frame:IsShown()), "visibility:", s.visibility, "unlocked:", tostring(s.unlocked))
    print("  power:", tostring(powerType), tostring(token), "| third row:",
        R.ThirdRow() == R.power and "energy/rage" or R.ThirdRow() == R.cast and "cast bar" or "none",
        "| combo points:", tostring(R.ShowsCombo()), "| casting:", tostring(R.casting ~= nil))
    print("  size:", s.width, "x", s.healthHeight, "/", s.powerHeight, "padding", s.padding, "scale", s.scale,
        "opacity", s.opacity, "| position:", tostring(s.x), tostring(s.y), "keep centred:", tostring(s.keepCentred))
    print("  health secret:", tostring(IsSecret(UnitHealth("player"))), "| combo points secret:",
        tostring(IsSecret(UnitPower("player", POWER.COMBO))), "max:", tostring(UnitPowerMax("player", POWER.COMBO)))
end

----------------------------------------------------------------------------------------------
-- Options: a page under DruidBar in Esc > Options > AddOns
----------------------------------------------------------------------------------------------

local panel = CreateFrame("Frame", "DruidBarResourceOptionsPanel", UIParent)
panel.name = "Resource display"
panel.parent = "DruidBar"
panel:SetSize(620, 470)
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
title:SetText("DruidBar resource display")
local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetWidth(580)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Health, mana and energy/rage bars to use instead of Blizzard's Personal Resource Display. " ..
    "Turn Blizzard's off in its own settings so there aren't two.")

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

local enabledBox = Checkbox("DruidBarResourceEnabled", subtitle, "Show the resource display", "enabled")
local visibilityButton = Cycle("DruidBarResourceVisibility", enabledBox, "Visibility", "visibility", R.VISIBILITY)
local textButton = Cycle("DruidBarResourceText", visibilityButton, "Text", "text", R.TEXT)
local styleButton = Cycle("DruidBarResourceStyle", textButton, "Bar style", "style", R.STYLE)
styleButton:SetPoint("TOPLEFT", textButton, "BOTTOMLEFT", 0, -10)
local centredBox = Checkbox("DruidBarResourceCentred", styleButton, "Keep centred (dragging only moves it up and down)",
    "keepCentred")
centredBox:SetPoint("TOPLEFT", styleButton, "BOTTOMLEFT", -4, -8)
local unlockBox = Checkbox("DruidBarResourceUnlocked", centredBox, "Unlock to move (drag it)", "unlocked")
local castBox = Checkbox("DruidBarResourceCast", unlockBox, "Cast bar below mana in caster form, while casting", "castBar")
local comboBox = Checkbox("DruidBarResourceCombo", castBox, "Combo points in Cat Form", "comboPoints")

local resetButton = CreateFrame("Button", "DruidBarResourceReset", panel, "UIPanelButtonTemplate")
resetButton:SetSize(200, 22)
resetButton:SetPoint("TOPLEFT", comboBox, "BOTTOMLEFT", 4, -12)
resetButton:SetText("Reset to default position")
resetButton:SetScript("OnClick", function() R.ResetPosition() end)

local sizeSlider = Slider("DruidBarResourceScale", subtitle, "Size", "scale", 0.5, 2.0, 0.05, true, 340, -40)
local widthSlider = Slider("DruidBarResourceWidth", sizeSlider, "Bar width", "width", 80, 400, 5)
local healthSlider = Slider("DruidBarResourceHealthHeight", widthSlider, "Health bar height", "healthHeight", 4, 40, 1)
local powerSlider = Slider("DruidBarResourcePowerHeight", healthSlider, "Power bar height", "powerHeight", 4, 40, 1)
local paddingSlider = Slider("DruidBarResourcePadding", powerSlider, "Padding", "padding", 0, 10, 1)
Slider("DruidBarResourceOpacity", paddingSlider, "Opacity", "opacity", 0.1, 1.0, 0.05, true)

panel:SetScript("OnShow", function()
    for _, refresh in ipairs(widgets) do
        refresh()
    end
end)

if Settings and Settings.RegisterCanvasLayoutSubcategory and ns.settingsCategory then
    local sub = Settings.RegisterCanvasLayoutSubcategory(ns.settingsCategory, panel, panel.name)
    R.settingsCategory = sub
elseif Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "DruidBar resource display")
    Settings.RegisterAddOnCategory(category)
    R.settingsCategory = category
end

function R.OpenOptions()
    if Settings and Settings.OpenToCategory and R.settingsCategory then
        local ok = pcall(Settings.OpenToCategory, R.settingsCategory:GetID())
        if not ok then
            pcall(Settings.OpenToCategory, R.settingsCategory)
        end
    end
end
