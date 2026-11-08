--[[
    DruidRange
    One solid-colour bar showing whether your target is in range, based on form and target.

    Enemy (all forms, checked in this order):
      hidden = the "Hide based on what?" option applies (checked before any colour, so no flicker)
      green  = in melee range (Growl in Bear/caster, Claw in Cat)
      Cat / Bear only, with "Feral Charge colours" on:
        green  = inside charge's minimum range: in combat, has been in melee/charge range since
                 targeted, now in neither but still within 30 yd (needs Feral Charge learned)
        yellow = in Feral Charge range (8-25 yd)
      purple = within 30 yd (Faerie Fire, or Wrath until Faerie Fire is learned)
      grey   = out of range
    Friendly (all forms):
      purple = within 30 yd (Mark of the Wild, or Thorns)
      teal   = within 40 yd (Healing Touch)
      grey   = out of range
      Cat / Bear: only while the target is hurt or in combat (if neither can be read because of
      secret values, always). Friendly NPCs: only while you're in combat and the NPC can be healed.
    Dead friendly target: purple in Revive range (30 yd), grey out of it, hidden until Revive is learned.
    No target: hidden.

    Range is only ever a yes/no answer from the game for a spell; unlearned spells give no
    answer (nil), so any rule that needs one just does not apply until it is learned.

    /druidrange opens the options, /druidrange debug prints what the game currently answers.
]]

DruidRangeDB = DruidRangeDB or {}

-- Part of DruidFrame (shares its namespace: ns.Resource is the frame, ns.OpenOptions the pages).
local _, ns = ...

local _, playerClass = UnitClass("player")
local isDruid = (playerClass == "DRUID")

--------------------------------------------------------------------------
-- Spells & forms
--------------------------------------------------------------------------

-- GetShapeshiftFormID(): same IDs as DruidForeverManabarPlus. Bear and Dire Bear share 5.
local FORM_CAT = 1
local FORM_BEAR = 5

-- 30 yd, same in and out of forms. Wrath stands in until Faerie Fire is learned.
local SPELL_FAERIE_FIRE = "Faerie Fire"
local SPELL_WRATH = "Wrath"
-- Friendly 30 yd and 40 yd.
local SPELL_MARK = "Mark of the Wild"
local SPELL_THORNS = "Thorns"
local SPELL_HEAL = "Healing Touch"
-- Dead friendly targets: Revive (Forever's out-of-combat res, 30 yd). Unlearned spells give no
-- range answer, so the bar stays hidden on corpses until Revive is learned.
local SPELL_REVIVE = "Revive"
-- Same name and range in Cat and Bear Form on Forever.
local SPELL_CHARGE = "Feral Charge"
-- Maul is an on-next-swing ability and its range answer can't be trusted (it can say "in range"
-- at any distance), so melee range uses normal melee attacks instead. Debug output only.
local SPELL_MAUL = "Maul"
local SPELL_BASH = "Bash"
local SPELL_CLAW = "Claw"
local SPELL_RAKE = "Rake"

-- Growl (learned with Bear Form) has the same range as Bash on Forever, so it is the Bear melee check.
local function GetGrowlName()
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(6795)
        if info and info.name then return info.name end
    end
    return "Growl"
end
local SPELL_GROWL = GetGrowlName()

local HIDE_NONE = "none"
local HIDE_MELEE = "melee"
local HIDE_CHARGE_MIN = "chargemin"

local COLOR_GREEN  = { 0, 1, 0 }
local COLOR_YELLOW = { 1, 0.85, 0 }
local COLOR_PURPLE = { 0.6, 0.2, 0.9 }
local COLOR_TEAL   = { 0, 1, 1 }
local COLOR_GREY   = { 0.5, 0.5, 0.5 }

--------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------

local function InitDefaults()
    local db = DruidRangeDB
    if db.enabled == nil then db.enabled = true end
    db.unlocked = nil -- old setting: now unlocked while DruidFrame's options are open
    -- Position: "top"/"bottom" of DruidFrame's display, or "free" (placed by dragging).
    if db.anchor ~= "top" and db.anchor ~= "bottom" and db.anchor ~= "free" then
        db.anchor = "free" -- where it was before DruidFrame
    end
    if db.keepCentred == nil then db.keepCentred = true end
    db.snapMelee = nil -- old setting: snapping to a swing timer was removed
    if db.chargeEnabled == nil then db.chargeEnabled = true end
    if db.stealthNoHide == nil then db.stealthNoHide = true end
    if db.hideMode ~= HIDE_NONE and db.hideMode ~= HIDE_MELEE and db.hideMode ~= HIDE_CHARGE_MIN then
        db.hideMode = HIDE_NONE
    end
    db.faerieFireSpell = nil -- old setting, no longer used
    db.width = db.width or 100
    db.height = db.height or 75
    db.opacity = db.opacity or 75
end

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- true / false / nil (nil = no answer, e.g. spell not learned).
local function InRange(spellName, unit)
    if not spellName or spellName == "" or not UnitExists(unit) then return nil end
    local result
    if C_Spell and C_Spell.IsSpellInRange then
        result = C_Spell.IsSpellInRange(spellName, unit)
    elseif IsSpellInRange then
        result = IsSpellInRange(spellName, unit)
    end
    if IsSecret(result) then return nil end
    if result == true or result == 1 then return true end
    if result == false or result == 0 then return false end
    return nil
end

-- Answer from the first spell in the list that gives one, plus that spell's name.
local function FirstInRange(spells, unit)
    for _, name in ipairs(spells) do
        local r = InRange(name, unit)
        if r ~= nil then return r, name end
    end
    return nil, nil
end

local function GetFormID()
    return GetShapeshiftFormID and GetShapeshiftFormID() or nil
end

local function IsFeralForm(formID)
    return formID == FORM_CAT or formID == FORM_BEAR
end

local function MeleeSpells(formID)
    if formID == FORM_CAT then return { SPELL_CLAW, SPELL_RAKE, SPELL_GROWL } end
    return { SPELL_GROWL, SPELL_BASH, SPELL_CLAW }
end

local function PlayerInCombat()
    local c = UnitAffectingCombat("player")
    if IsSecret(c) then return false end
    return c and true or false
end

local function IsPlayerStealthed()
    if not IsStealthed then return false end
    local s = IsStealthed()
    if IsSecret(s) then return false end
    return s and true or false
end

local function HasLivingEnemyTarget()
    return UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")
end

-- Dead friendly targets count too (for Revive range).
local function HasFriendlyTarget()
    return UnitExists("target") and not UnitCanAttack("player", "target")
        and UnitIsFriend("player", "target")
end

-- Returns known, needsAttention. known = false when neither health nor combat can be read.
local function FriendlyNeedsAttention(unit)
    local known, attention = false, false

    local health, maxHealth = UnitHealth(unit), UnitHealthMax(unit)
    if health and maxHealth and not IsSecret(health) and not IsSecret(maxHealth) and maxHealth > 0 then
        known = true
        if health < maxHealth then attention = true end
    end

    local combat = UnitAffectingCombat(unit)
    if not IsSecret(combat) then
        known = true
        if combat then attention = true end
    end

    return known, attention
end

--------------------------------------------------------------------------
-- Engagement memory (for the gap inside charge's minimum range)
-- Set once the current target has been in melee or charge range; cleared on target
-- change and on leaving combat.
--------------------------------------------------------------------------

local engaged = false

local function ResetEngaged()
    engaged = false
end

--------------------------------------------------------------------------
-- Enemy
--------------------------------------------------------------------------

-- melee / charge / far are true/false/nil. closeGap = best guess that the target is inside
-- charge's minimum range: only with Feral Charge learned (otherwise "not in charge range" can't
-- be told apart from "anywhere out to 30 yd").
local function GetEnemyState(formID)
    local s = {}
    s.melee, s.meleeSpell = FirstInRange(MeleeSpells(formID), "target")
    s.charge = InRange(SPELL_CHARGE, "target")
    s.far, s.farSpell = FirstInRange({ SPELL_FAERIE_FIRE, SPELL_WRATH }, "target")

    if s.melee == true or s.charge == true then
        engaged = true
    end

    s.inCombat = PlayerInCombat()
    s.closeGap = s.charge ~= nil and s.inCombat and engaged
        and s.melee ~= true and s.charge ~= true and s.far == true
    return s
end

local function ShouldHide(s)
    local mode = DruidRangeDB.hideMode
    if mode == HIDE_NONE then return false end
    if DruidRangeDB.stealthNoHide and IsPlayerStealthed() then return false end

    if mode == HIDE_MELEE then
        -- "Melee (5yd)": same melee spells as the green check for this form.
        return s.melee == true
    elseif mode == HIDE_CHARGE_MIN then
        -- "Charge (8yd)": in melee, or inside charge's minimum range (needs Feral Charge learned;
        -- without it only melee range hides).
        return s.melee == true or s.closeGap
    end
    return false
end

local function GetEnemyColor(formID, s)
    if s.melee == true then return COLOR_GREEN end
    if IsFeralForm(formID) and DruidRangeDB.chargeEnabled then
        if s.closeGap then return COLOR_GREEN end
        if s.charge == true then return COLOR_YELLOW end
    end
    if s.far == true then return COLOR_PURPLE end
    return COLOR_GREY
end

--------------------------------------------------------------------------
-- Friendly
--------------------------------------------------------------------------

-- Friendly NPCs (not players or their pets) only show when you're in combat and the NPC can
-- be healed (Healing Touch gives a range answer for it).
local function FriendlyNPCAllowed()
    if UnitPlayerControlled("target") then return true end
    if not PlayerInCombat() then return false end
    if UnitCanAssist and not UnitCanAssist("player", "target") then return false end
    return InRange(SPELL_HEAL, "target") ~= nil
end

-- Returns a colour, or nil to hide.
local function GetFriendlyColor(formID)
    if not FriendlyNPCAllowed() then return nil end
    if IsFeralForm(formID) then
        local known, attention = FriendlyNeedsAttention("target")
        if known and not attention then return nil end
    end

    if UnitIsDeadOrGhost("target") then
        local r = InRange(SPELL_REVIVE, "target")
        if r == nil then return nil end
        return r and COLOR_PURPLE or COLOR_GREY
    end

    if FirstInRange({ SPELL_MARK, SPELL_THORNS }, "target") == true then return COLOR_PURPLE end
    if InRange(SPELL_HEAL, "target") == true then return COLOR_TEAL end
    return COLOR_GREY
end

--------------------------------------------------------------------------
-- Bar frame
--------------------------------------------------------------------------

local BASE_WIDTH = 200
local BASE_HEIGHT = 4.921875
local optionsPanelOpen = false

local bar = CreateFrame("Frame", "DruidRangeBarFrame", UIParent, "BackdropTemplate")
bar:SetSize(BASE_WIDTH, BASE_HEIGHT)
bar:SetClampedToScreen(true)
bar:EnableMouse(true)
if bar.SetBackdrop then
    bar:SetBackdrop({ edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 8 })
    bar:SetBackdropBorderColor(0, 0, 0, 1)
end
bar.fill = bar:CreateTexture(nil, "ARTWORK")
bar.fill:SetPoint("TOPLEFT", 2, -2)
bar.fill:SetPoint("BOTTOMRIGHT", -2, 2)
bar.fill:SetColorTexture(1, 1, 1, 1)
bar:Hide()


-- DruidFrame's display, when the bar is attached to it.
local function AttachFrame()
    local R = ns.Resource
    local anchor = DruidRangeDB.anchor
    if R and R.frame and (anchor == "top" or anchor == "bottom") then
        return R.frame, anchor
    end
end

local function RefreshLayout()
    local db = DruidRangeDB
    local host, side = AttachFrame()
    local height = BASE_HEIGHT * ((db.height or 75) / 50)
    local width
    if host then
        -- Attached: as wide as DruidFrame's bars (times the width setting), its padding apart.
        width = host:GetWidth() * host:GetScale() * ((db.width or 100) / 100)
    else
        width = BASE_WIDTH * ((db.width or 100) / 100)
    end
    bar:SetSize(width, height)
    bar:SetAlpha((db.opacity or 75) / 100)

    bar:ClearAllPoints()
    if host then
        local gap = ((ns.Resource.Settings().padding or 4) + 1) * host:GetScale()
        if side == "top" then
            bar:SetPoint("BOTTOM", host, "TOP", 0, gap)
        else
            bar:SetPoint("TOP", host, "BOTTOM", 0, -gap)
        end
    else
        local p = db.point
        local x, y = 0, -180
        if p and p.point == "CENTER" then
            x, y = p.x or 0, p.y or y
        elseif p then
            -- Older saves used other anchor points: convert once, from where it ends up.
            bar:SetPoint(p.point, UIParent, p.point, p.x, p.y)
            local cx, cy = bar:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if cx and ux then
                x, y = cx - ux, cy - uy
                db.point = { point = "CENTER", x = x, y = y }
            end
            bar:ClearAllPoints()
        end
        if db.keepCentred then
            x = 0
        end
        bar:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
end

-- Unlocked while any DruidFrame options page is open (as the display is). Only a free bar
-- can be dragged; attached, it moves with the display. Right-click opens its options page.
local unlocked = false
local drag

local function Cursor()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return cx / scale, cy / scale
end

local function CanDrag()
    return unlocked and not AttachFrame()
end

local function UpdateDraggability()
    if bar.SetPassThroughButtons then
        if CanDrag() then
            pcall(bar.SetPassThroughButtons, bar)
        else
            pcall(bar.SetPassThroughButtons, bar, "LeftButton")
        end
    end
end

local function DragUpdate()
    if not drag then return end
    local cx, cy = Cursor()
    local ux, uy = UIParent:GetCenter()
    local x = DruidRangeDB.keepCentred and 0 or (cx + drag.dx - ux)
    DruidRangeDB.point = { point = "CENTER", x = x, y = cy + drag.dy - uy }
    RefreshLayout()
end

bar:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" and CanDrag() then
        local bx, by = bar:GetCenter()
        local cx, cy = Cursor()
        drag = { dx = bx - cx, dy = by - cy }
        if DruidRangeDB.keepCentred and ns.Resource and ns.Resource.guide then
            ns.Resource.guide:Show()
        end
        bar:SetScript("OnUpdate", DragUpdate)
    elseif button == "RightButton" then
        bar.rightDown = { Cursor() }
    end
end)
bar:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and bar.rightDown then
        local x, y = Cursor()
        local moved = math.abs(x - bar.rightDown[1]) + math.abs(y - bar.rightDown[2])
        bar.rightDown = nil
        if moved < 5 and ns.OpenOptions then
            ns.OpenOptions("range")
        end
    elseif drag then
        DragUpdate()
        drag = nil
        bar:SetScript("OnUpdate", nil)
        if ns.Resource and ns.Resource.guide then
            ns.Resource.guide:Hide()
        end
    end
end)

local function ShowColor(c)
    bar.fill:SetColorTexture(c[1], c[2], c[3], 1)
    bar:Show()
end

local function UpdateBar()
    if not isDruid or not DruidRangeDB.enabled then
        bar:Hide()
        return
    end

    local formID = GetFormID()
    local color

    if HasLivingEnemyTarget() then
        local s = GetEnemyState(formID)
        if not ShouldHide(s) or optionsPanelOpen then
            color = GetEnemyColor(formID, s)
        end
    elseif HasFriendlyTarget() then
        color = GetFriendlyColor(formID)
    end

    -- Preview while the options panel is open.
    if not color and optionsPanelOpen then color = COLOR_GREEN end

    if color then ShowColor(color) else bar:Hide() end
end

--------------------------------------------------------------------------
-- Options panel
--------------------------------------------------------------------------

local panel = CreateFrame("Frame", "DruidRangeOptionsPanel", UIParent)
panel.name = "DruidRange"
-- Start hidden so the "options open" preview only runs while the panel is really showing.
panel:Hide()

-- Registered by Options.lua as a page under DruidFrame.
ns.panels = ns.panels or {}
ns.panels.range = panel
local function OpenOptions()
    if ns.OpenOptions then
        ns.OpenOptions("range")
    end
end

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("DruidRange")

local function CreateCheck(name, label, small)
    local cb = CreateFrame("CheckButton", name, panel, "UICheckButtonTemplate")
    cb.text = _G[name .. "Text"] or cb.Text
    if small then
        cb:SetSize(20, 20)
        cb.text:SetFontObject("GameFontHighlightSmall")
    end
    cb.text:SetText(label)
    return cb
end

local function CreatePercentSlider(name, label, minV, maxV, step, anchor, yOffset, dbKey)
    local s = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetWidth(150)
    _G[name .. "Low"]:SetText(minV .. "%")
    _G[name .. "High"]:SetText(maxV .. "%")
    _G[name .. "Text"]:SetText(label)

    s.valText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.valText:SetPoint("LEFT", s, "RIGHT", 12, 0)

    s:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        self.valText:SetText(value .. "%")
        DruidRangeDB[dbKey] = value
        RefreshLayout()
    end)
    return s
end

-- Left column: display

local enableCB = CreateCheck("DruidRangeEnableCheck", "Show DruidRange bar")
enableCB:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
enableCB:SetScript("OnClick", function(self)
    DruidRangeDB.enabled = self:GetChecked() and true or false
    UpdateBar()
end)

-- Position: attached to the top or bottom of DruidFrame's display, or free.
local posLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
posLabel:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -10)
posLabel:SetText("Position")
local posButtons = {}
local POSITIONS = {
    { anchor = "top", label = "Above DruidFrame" },
    { anchor = "bottom", label = "Below DruidFrame" },
    { anchor = "free", label = "Free (drag it while the options are open)" },
}
local centredCB
local function RefreshPositionButtons()
    local free = DruidRangeDB.anchor == "free"
    for _, b in ipairs(posButtons) do
        b:SetChecked(DruidRangeDB.anchor == b.anchor)
    end
    if centredCB then
        centredCB:SetEnabled(free)
        centredCB:SetAlpha(free and 1 or 0.5)
    end
end
local lastPos = posLabel
for i, opt in ipairs(POSITIONS) do
    local b = CreateCheck("DruidRangePosition" .. i, opt.label, true)
    b:SetPoint("TOPLEFT", lastPos, "BOTTOMLEFT", 0, -4)
    b.anchor = opt.anchor
    b:SetScript("OnClick", function(self)
        DruidRangeDB.anchor = self.anchor
        RefreshPositionButtons()
        UpdateDraggability()
        RefreshLayout()
    end)
    posButtons[i] = b
    lastPos = b
end

centredCB = CreateCheck("DruidRangeCentredCheck", "Keep centred (free only: dragging moves it up and down)", true)
centredCB:SetPoint("TOPLEFT", lastPos, "BOTTOMLEFT", 16, -2)
centredCB:SetScript("OnClick", function(self)
    DruidRangeDB.keepCentred = self:GetChecked() and true or false
    RefreshLayout()
end)

local widthSlider = CreatePercentSlider("DruidRangeWidthSlider", "Bar Width", 10, 300, 10, centredCB, -24, "width")
local heightSlider = CreatePercentSlider("DruidRangeHeightSlider", "Bar Height", 50, 300, 25, widthSlider, -26, "height")
local opacitySlider = CreatePercentSlider("DruidRangeOpacitySlider", "Bar Opacity", 10, 100, 5, heightSlider, -26, "opacity")

-- Right column: behaviour

local chargeCB = CreateCheck("DruidRangeChargeCheck", "Feral Charge colour (yellow)")
chargeCB:SetPoint("TOPLEFT", title, "TOPLEFT", 260, -8)
chargeCB:SetScript("OnClick", function(self)
    DruidRangeDB.chargeEnabled = self:GetChecked() and true or false
    UpdateBar()
end)

local hideLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hideLabel:SetPoint("TOPLEFT", chargeCB, "BOTTOMLEFT", 0, -16)
hideLabel:SetText("Hide based on what?")

local hideButtons = {}
local HIDE_OPTIONS = {
    { mode = HIDE_NONE, label = "None" },
    { mode = HIDE_MELEE, label = "Melee (5yd)" },
    { mode = HIDE_CHARGE_MIN, label = "Charge (8yd)" },
}

local function RefreshHideButtons()
    for _, b in ipairs(hideButtons) do
        b:SetChecked(DruidRangeDB.hideMode == b.mode)
    end
end

local lastHideAnchor = hideLabel
for i, opt in ipairs(HIDE_OPTIONS) do
    local b = CreateCheck("DruidRangeHideOption" .. i, opt.label, true)
    b:SetPoint("TOPLEFT", lastHideAnchor, "BOTTOMLEFT", 0, -4)
    b.mode = opt.mode
    b:SetScript("OnClick", function(self)
        DruidRangeDB.hideMode = self.mode
        RefreshHideButtons()
        UpdateBar()
    end)
    hideButtons[i] = b
    lastHideAnchor = b
end

local stealthCB = CreateCheck("DruidRangeStealthCheck", "Don't hide while stealthed", true)
stealthCB:SetPoint("TOPLEFT", lastHideAnchor, "BOTTOMLEFT", 0, -8)
stealthCB:SetScript("OnClick", function(self)
    DruidRangeDB.stealthNoHide = self:GetChecked() and true or false
    UpdateBar()
end)

local function RefreshOptionsUI()
    InitDefaults()
    local db = DruidRangeDB
    enableCB:SetChecked(db.enabled)
    centredCB:SetChecked(db.keepCentred)
    RefreshPositionButtons()
    widthSlider:SetValue(db.width)
    heightSlider:SetValue(db.height)
    opacitySlider:SetValue(db.opacity)
    widthSlider.valText:SetText(db.width .. "%")
    heightSlider.valText:SetText(db.height .. "%")
    opacitySlider.valText:SetText(db.opacity .. "%")
    chargeCB:SetChecked(db.chargeEnabled)
    stealthCB:SetChecked(db.stealthNoHide)
    RefreshHideButtons()
end

panel:SetScript("OnShow", function()
    RefreshOptionsUI()
    if ns.PageShown then ns.PageShown(true) end
end)
panel:SetScript("OnHide", function()
    if ns.PageShown then ns.PageShown(false) end
end)

-- Any DruidFrame options page open: unlocked, and the bar previews (green) so you can see it.
ns.Range = {}
function ns.Range.SetUnlocked(value)
    unlocked = value and true or false
    optionsPanelOpen = unlocked
    if not unlocked and drag then
        drag = nil
        bar:SetScript("OnUpdate", nil)
    end
    UpdateDraggability()
    RefreshLayout()
    UpdateBar()
end
ns.Range.RefreshLayout = RefreshLayout
ns.Range.bar = bar

--------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------

local function Answer(v)
    if v == nil then return "no answer" end
    return v and "in range" or "out of range"
end

local function PrintDebug()
    local p = function(msg) print("|cff55ff55DruidRange:|r " .. msg) end
    local formID = GetFormID()
    p(string.format("form ID = %s (%s), in combat = %s, stealthed = %s, engaged = %s",
        tostring(formID), IsFeralForm(formID) and "Cat/Bear rules" or "caster rules",
        tostring(PlayerInCombat()), tostring(IsPlayerStealthed()), tostring(engaged)))

    if not UnitExists("target") then
        p("no target.")
        return
    end

    local function line(name)
        p(string.format("  %s: %s", name, Answer(InRange(name, "target"))))
    end
    for _, name in ipairs({ SPELL_FAERIE_FIRE, SPELL_WRATH, SPELL_MARK, SPELL_THORNS, SPELL_HEAL, SPELL_CHARGE,
        SPELL_GROWL, SPELL_BASH, SPELL_CLAW, SPELL_RAKE, SPELL_MAUL }) do line(name) end
    if UnitIsDeadOrGhost("target") then
        line(SPELL_REVIVE)
    end

    if HasLivingEnemyTarget() then
        local s = GetEnemyState(formID)
        p(string.format("  enemy: melee (%s) = %s, charge = %s, 30yd (%s) = %s, gap = %s, hidden = %s",
            tostring(s.meleeSpell), Answer(s.melee), Answer(s.charge),
            tostring(s.farSpell), Answer(s.far), tostring(s.closeGap), tostring(ShouldHide(s))))
    elseif HasFriendlyTarget() then
        local health, maxHealth = UnitHealth("target"), UnitHealthMax("target")
        local combat = UnitAffectingCombat("target")
        p(string.format("  friendly: health readable = %s, combat readable = %s",
            tostring(not IsSecret(health) and not IsSecret(maxHealth)), tostring(not IsSecret(combat))))
        local known, attention = FriendlyNeedsAttention("target")
        p(string.format("  friendly: known = %s, hurt or in combat = %s", tostring(known), tostring(attention)))
        p(string.format("  friendly: player-controlled = %s, can assist = %s, shown as NPC = %s",
            tostring(UnitPlayerControlled("target")), tostring(UnitCanAssist and UnitCanAssist("player", "target")),
            tostring(FriendlyNPCAllowed())))
    end
end

SLASH_DRUIDRANGE1 = "/druidrange"
SlashCmdList["DRUIDRANGE"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "debug" then
        PrintDebug()
    else
        OpenOptions()
    end
end

--------------------------------------------------------------------------
-- Event driver
--------------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

driver:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        -- Saved variables are loaded by now.
        InitDefaults()
        RefreshOptionsUI()
        UpdateDraggability()
        RefreshLayout()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
        ResetEngaged()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ResetEngaged()
        RefreshLayout()
    end
    UpdateBar()
end)

local elapsedTotal = 0
driver:SetScript("OnUpdate", function(self, elapsed)
    if not isDruid then return end
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < 0.1 then return end
    elapsedTotal = 0
    UpdateBar()
end)
