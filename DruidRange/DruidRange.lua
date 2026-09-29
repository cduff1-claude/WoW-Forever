--[[
    DruidRange
    One solid-colour bar showing whether your target is in range, based on form and target.

    Caster / Travel / Aquatic / Moonkin:
      enemy:    green = in Wrath range, red = out of range
      friendly: teal  = in Healing Touch range, grey = out of range
    Cat / Bear / Dire Bear, enemy (checked in this order):
      green  = in melee range (Growl in Bear, Claw in Cat)
      brown  = in Feral Charge range (optional)
      yellow = in combat, has been in melee/charge range since targeted, now in neither
               but still in Faerie Fire range (the gap inside charge's minimum range)
      purple = in Faerie Fire range
      red    = out of Faerie Fire range
    Cat / Bear / Dire Bear, friendly: teal/grey while the target is hurt or in combat, hidden
      otherwise. If neither can be read (secret values), behaves as in caster form.
    Dead friendly targets are treated the same (resurrection has heal range).
    Friendly NPCs: hidden unless you're in combat and the NPC can be healed.
    No target: hidden.

    Range is only ever a yes/no answer from the game for a spell; unlearned spells give no
    answer (nil), so any rule that needs one just does not apply until it is learned.

    /druidrange opens the options, /druidrange debug prints what the game currently answers.
]]

DruidRangeDB = DruidRangeDB or {}

local _, playerClass = UnitClass("player")
local isDruid = (playerClass == "DRUID")

--------------------------------------------------------------------------
-- Spells & forms
--------------------------------------------------------------------------

-- GetShapeshiftFormID(): same IDs as DruidForeverManabarPlus. Bear and Dire Bear share 5.
local FORM_CAT = 1
local FORM_BEAR = 5

local SPELL_WRATH = "Wrath"
local SPELL_HEAL = "Healing Touch"
-- Dead friendly targets: Revive (Forever's out-of-combat res, same range as heals), then
-- Healing Touch until Revive is learned.
local HEAL_SPELLS_DEAD = { "Revive", SPELL_HEAL }
-- Maul is an on-next-swing ability and its range answer can't be trusted (it can say "in range"
-- at any distance), so melee range uses normal melee attacks instead.
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
local DEFAULT_FAERIE_FIRE = "Faerie Fire"

-- First name that the game answers for wins. The Cat charge is new in WoW Forever and its
-- name is not known yet, so both likely names are tried.
local CHARGE_SPELLS_BEAR = { "Feral Charge", "Feral Charge - Bear", "Feral Charge - Cat" }
local CHARGE_SPELLS_CAT = { "Feral Charge - Cat", "Feral Charge", "Feral Charge - Bear" }

local HIDE_NONE = "none"
local HIDE_MELEE = "melee"
local HIDE_CHARGE_MIN = "chargemin"

local COLOR_GREEN  = { 0, 1, 0 }
local COLOR_RED    = { 1, 0, 0 }
local COLOR_TEAL   = { 0, 1, 1 }
local COLOR_GREY   = { 0.5, 0.5, 0.5 }
local COLOR_BROWN  = { 0.6, 0.4, 0.2 }
local COLOR_YELLOW = { 1, 0.85, 0 }
local COLOR_PURPLE = { 0.6, 0.2, 0.9 }

--------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------

local function InitDefaults()
    local db = DruidRangeDB
    if db.enabled == nil then db.enabled = true end
    if db.unlocked == nil then db.unlocked = false end
    if db.snapMelee == nil then db.snapMelee = true end
    if db.chargeEnabled == nil then db.chargeEnabled = true end
    if db.stealthNoHide == nil then db.stealthNoHide = true end
    if db.hideMode ~= HIDE_NONE and db.hideMode ~= HIDE_MELEE and db.hideMode ~= HIDE_CHARGE_MIN then
        db.hideMode = HIDE_NONE
    end
    if not db.faerieFireSpell or db.faerieFireSpell == "" then db.faerieFireSpell = DEFAULT_FAERIE_FIRE end
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

local function ChargeSpells(formID)
    if formID == FORM_CAT then return CHARGE_SPELLS_CAT end
    return CHARGE_SPELLS_BEAR
end

-- Faerie Fire, falling back to Wrath (same 30 yd) until Faerie Fire answers.
local function FaerieFireInRange(unit)
    return FirstInRange({ DruidRangeDB.faerieFireSpell, SPELL_WRATH }, unit)
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

-- Dead friendly targets count too (for resurrection range).
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
-- Engagement memory (for yellow)
-- Set once the current target has been in melee or charge range; cleared on target
-- change and on leaving combat.
--------------------------------------------------------------------------

local engaged = false

local function ResetEngaged()
    engaged = false
end

--------------------------------------------------------------------------
-- Enemy range state
--------------------------------------------------------------------------

-- melee / charge / faerie are true/false/nil. closeGap = the target is inside charge's
-- minimum range (best guess, see header) and not in melee range.
local function GetEnemyState(formID)
    local s = {}
    s.melee, s.meleeSpell = FirstInRange(MeleeSpells(formID), "target")
    s.charge, s.chargeSpell = FirstInRange(ChargeSpells(formID), "target")
    s.faerie, s.faerieSpell = FaerieFireInRange("target")

    if s.melee == true or s.charge == true then
        engaged = true
    end

    s.inCombat = PlayerInCombat()
    s.closeGap = s.inCombat and engaged and s.melee ~= true and s.charge ~= true and s.faerie == true
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
        -- "Charge (8yd)": in melee, or inside charge's minimum range. Needs Feral Charge learned
        -- to tell the gap apart; without it only melee range hides.
        if s.melee == true then return true end
        return s.charge ~= nil and s.closeGap
    end
    return false
end

-- Returns a colour, or nil to hide.
local function GetEnemyColor(formID, s)
    if IsFeralForm(formID) then
        if s.melee == true then return COLOR_GREEN end
        if DruidRangeDB.chargeEnabled then
            if s.charge == true then return COLOR_BROWN end
            if s.closeGap then return COLOR_YELLOW end
        end
        if s.faerie == true then return COLOR_PURPLE end
        return COLOR_RED
    end

    local r = InRange(SPELL_WRATH, "target")
    return (r == true) and COLOR_GREEN or COLOR_RED
end

-- Friendly NPCs (not players or their pets) only show when you're in combat and the NPC can
-- be healed (Healing Touch gives a range answer for it).
local function FriendlyNPCAllowed()
    if UnitPlayerControlled("target") then return true end
    if not PlayerInCombat() then return false end
    if UnitCanAssist and not UnitCanAssist("player", "target") then return false end
    return InRange(SPELL_HEAL, "target") ~= nil
end

local function GetFriendlyColor(formID)
    if not FriendlyNPCAllowed() then return nil end
    if IsFeralForm(formID) then
        local known, attention = FriendlyNeedsAttention("target")
        if known and not attention then return nil end
    end
    local r
    if UnitIsDeadOrGhost("target") then
        r = FirstInRange(HEAL_SPELLS_DEAD, "target")
    else
        r = InRange(SPELL_HEAL, "target")
    end
    return (r == true) and COLOR_TEAL or COLOR_GREY
end

--------------------------------------------------------------------------
-- Bar frame
--------------------------------------------------------------------------

local BASE_WIDTH = 200
local BASE_HEIGHT = 4.921875
local cachedSwingWidth = nil
local optionsPanelOpen = false

local SWING_TIMER_FRAMES = { "SwingTimerMainHandFrame", "SwingTimerFrame", "SwingTimerMeleeFrame", "MainHandSwingTimerBar", "MainHandSwingBar", "PlayerSwingBar" }

local function GetSnapFrame()
    for _, name in ipairs(SWING_TIMER_FRAMES) do
        local f = _G[name]
        if f then return f end
    end
    return nil
end

local bar = CreateFrame("Frame", "DruidRangeBarFrame", UIParent, "BackdropTemplate")
bar:SetSize(BASE_WIDTH, BASE_HEIGHT)
bar:SetClampedToScreen(true)
bar:SetMovable(true)
bar:EnableMouse(false)
bar:RegisterForDrag("LeftButton")
if bar.SetBackdrop then
    bar:SetBackdrop({ edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 8 })
    bar:SetBackdropBorderColor(0, 0, 0, 1)
end
bar.fill = bar:CreateTexture(nil, "ARTWORK")
bar.fill:SetPoint("TOPLEFT", 2, -2)
bar.fill:SetPoint("BOTTOMRIGHT", -2, 2)
bar.fill:SetColorTexture(1, 1, 1, 1)
bar:Hide()

local function SaveBarPosition()
    if not bar:GetPoint() then return end
    local point, _, _, x, y = bar:GetPoint()
    DruidRangeDB.point = { point = point, x = x, y = y }
end

local function RefreshLayout()
    local db = DruidRangeDB
    local swingFrame = db.snapMelee and GetSnapFrame() or nil

    if swingFrame and swingFrame:GetWidth() and swingFrame:GetWidth() > 0 then
        cachedSwingWidth = swingFrame:GetWidth()
    end
    local baseWidth = cachedSwingWidth or BASE_WIDTH
    bar:SetSize(baseWidth * ((db.width or 100) / 100), BASE_HEIGHT * ((db.height or 75) / 50))
    bar:SetAlpha((db.opacity or 75) / 100)

    bar:ClearAllPoints()
    if swingFrame then
        bar:SetPoint("BOTTOM", swingFrame, "TOP", 0, 4)
    elseif db.point then
        bar:SetPoint(db.point.point, UIParent, db.point.point, db.point.x, db.point.y)
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

local function UpdateDraggability()
    local enabled = DruidRangeDB.unlocked and true or false
    bar:EnableMouse(enabled)
    if enabled then
        bar:SetScript("OnDragStart", bar.StartMoving)
        bar:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            SaveBarPosition()
        end)
    else
        bar:SetScript("OnDragStart", nil)
        bar:SetScript("OnDragStop", nil)
    end
end

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

local settingsCategory

local function OpenOptions()
    if Settings and Settings.OpenToCategory and settingsCategory then
        local ok = pcall(Settings.OpenToCategory, settingsCategory:GetID())
        if not ok then
            pcall(Settings.OpenToCategory, settingsCategory)
        end
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
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

local snapCB = CreateCheck("DruidRangeSnapCheck", "Snap to Main Hand Swing Timer")
snapCB:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -2)

local unlockCB = CreateCheck("DruidRangeUnlockCheck", "Unlock (drag to move)")
unlockCB:SetPoint("TOPLEFT", snapCB, "BOTTOMLEFT", 0, -2)

snapCB:SetScript("OnClick", function(self)
    DruidRangeDB.snapMelee = self:GetChecked() and true or false
    RefreshLayout()
end)

unlockCB:SetScript("OnClick", function(self)
    DruidRangeDB.unlocked = self:GetChecked() and true or false
    if DruidRangeDB.unlocked and DruidRangeDB.snapMelee then
        -- Dragging a snapped bar makes no sense: keep it where it is and unsnap.
        SaveBarPosition()
        DruidRangeDB.snapMelee = false
        snapCB:SetChecked(false)
    end
    UpdateDraggability()
    RefreshLayout()
end)

local widthSlider = CreatePercentSlider("DruidRangeWidthSlider", "Bar Width", 10, 300, 10, unlockCB, -24, "width")
local heightSlider = CreatePercentSlider("DruidRangeHeightSlider", "Bar Height", 50, 300, 25, widthSlider, -26, "height")
local opacitySlider = CreatePercentSlider("DruidRangeOpacitySlider", "Bar Opacity", 10, 100, 5, heightSlider, -26, "opacity")

-- Right column: behaviour

local chargeCB = CreateCheck("DruidRangeChargeCheck", "Feral Charge colours (brown / yellow)")
chargeCB:SetPoint("TOPLEFT", title, "TOPLEFT", 260, -8)
chargeCB:SetScript("OnClick", function(self)
    DruidRangeDB.chargeEnabled = self:GetChecked() and true or false
    UpdateBar()
end)

local ffLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ffLabel:SetPoint("TOPLEFT", chargeCB, "BOTTOMLEFT", 0, -10)
ffLabel:SetText("Faerie Fire spell name (Cat/Bear purple range):")

local ffEdit = CreateFrame("EditBox", "DruidRangeFaerieFireEdit", panel, "InputBoxTemplate")
ffEdit:SetSize(180, 20)
ffEdit:SetAutoFocus(false)
ffEdit:SetPoint("TOPLEFT", ffLabel, "BOTTOMLEFT", 6, -4)
ffEdit:SetScript("OnEnterPressed", function(self)
    local text = strtrim(self:GetText() or "")
    DruidRangeDB.faerieFireSpell = (text ~= "") and text or DEFAULT_FAERIE_FIRE
    self:SetText(DruidRangeDB.faerieFireSpell)
    self:ClearFocus()
    UpdateBar()
end)
ffEdit:SetScript("OnEscapePressed", function(self)
    self:SetText(DruidRangeDB.faerieFireSpell)
    self:ClearFocus()
end)
ffEdit:SetScript("OnEditFocusLost", function(self)
    self:SetText(DruidRangeDB.faerieFireSpell)
end)

local ffHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ffHint:SetPoint("TOPLEFT", ffEdit, "BOTTOMLEFT", -6, -4)
ffHint:SetText("Press Enter to save. Uses Wrath until this spell answers.")

local hideLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hideLabel:SetPoint("TOPLEFT", ffHint, "BOTTOMLEFT", 0, -16)
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
    snapCB:SetChecked(db.snapMelee)
    unlockCB:SetChecked(db.unlocked)
    widthSlider:SetValue(db.width)
    heightSlider:SetValue(db.height)
    opacitySlider:SetValue(db.opacity)
    widthSlider.valText:SetText(db.width .. "%")
    heightSlider.valText:SetText(db.height .. "%")
    opacitySlider.valText:SetText(db.opacity .. "%")
    chargeCB:SetChecked(db.chargeEnabled)
    ffEdit:SetText(db.faerieFireSpell)
    stealthCB:SetChecked(db.stealthNoHide)
    RefreshHideButtons()
end

panel:SetScript("OnShow", function()
    optionsPanelOpen = true
    RefreshOptionsUI()
    RefreshLayout()
    UpdateBar()
end)

panel:SetScript("OnHide", function()
    optionsPanelOpen = false
    UpdateBar()
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(settingsCategory)
elseif InterfaceOptionsFrame_AddCategory then
    InterfaceOptionsFrame_AddCategory(panel)
end

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
    for _, name in ipairs({ SPELL_WRATH, SPELL_HEAL, SPELL_MAUL, SPELL_BASH, SPELL_CLAW, SPELL_RAKE, SPELL_GROWL }) do line(name) end
    for _, name in ipairs(CHARGE_SPELLS_BEAR) do line(name) end
    line(DruidRangeDB.faerieFireSpell)
    if UnitIsDeadOrGhost("target") then
        line(HEAL_SPELLS_DEAD[1])
    end

    if HasLivingEnemyTarget() then
        local s = GetEnemyState(formID)
        p(string.format("  enemy: melee (%s) = %s, charge (%s) = %s, faerie (%s) = %s, gap = %s, hidden = %s",
            tostring(s.meleeSpell), Answer(s.melee), tostring(s.chargeSpell), Answer(s.charge),
            tostring(s.faerieSpell), Answer(s.faerie), tostring(s.closeGap), tostring(ShouldHide(s))))
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
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

driver:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "DruidRange" then return end
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
    if DruidRangeDB.snapMelee then
        RefreshLayout()
    end
end)
