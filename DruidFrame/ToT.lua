-- DruidFrame: target of target. A small frame of its own (not tied to Blizzard's target frame),
-- so it can sit by DruidFrame's bars and the Player and Target frames can go elsewhere.
--
--   * Their portrait, overhanging the bar's left end: circle, square or off.
--   * Health bar (with DruidFrame's health colour gradient if that's on) and the unit's name,
--     class-coloured for players, reaction-coloured for NPCs; "You" when it's you.
--   * Aggro border, when your target is an enemy: in Bear Form green while it's on you and red
--     when it's on someone else in your group (you've lost it); out of Bear Form red while it's
--     on you (you've pulled it).
--   * Left-click targets the unit. It's a secure button, so its showing and hiding is left to
--     the game (a state driver), and it's only moved or set up out of combat.
--   * Unlocked with DruidFrame's options: shown even with nothing to show, and left-drag moves it.
--     Right-click opens its options page.

local _, ns = ...

local T = {}
ns.ToT = T

local UNIT = "targettarget"
local UPDATE_INTERVAL = 0.1

T.DEFAULTS = {
    totEnabled = true,
    totShow = "always", -- "always" or "combat"
    totGroup = false,   -- only while in a party or raid
    totAggro = true,
    totPortrait = "circle", -- their picture, left of the bar: "circle", "square" or "none"
    totWidth = 120,
    totHeight = 18,
    -- totX / totY: its centre, in UIParent coordinates (nil: next to DruidFrame)
}

T.PORTRAIT = {
    { key = "circle", label = "Circle" },
    { key = "square", label = "Square" },
    { key = "none", label = "Off" },
}

T.SHOW = {
    { key = "always", label = "Whenever your target has a target" },
    { key = "combat", label = "Only in combat" },
}

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- A yes/no from the game, or nil when it won't say.
local function Ask(fn, ...)
    if not fn then
        return nil
    end
    local ok, answer = pcall(fn, ...)
    if not ok or IsSecret(answer) then
        return nil
    end
    return answer and true or false
end

function T.Settings()
    local s = ns.Resource and ns.Resource.Settings() or {}
    -- The portrait option was briefly on/off.
    if s.totPortrait == true then s.totPortrait = "circle" elseif s.totPortrait == false then s.totPortrait = "none" end
    for key, value in pairs(T.DEFAULTS) do
        if s[key] == nil then
            s[key] = value
        end
    end
    return s
end

-------------------------------------------------------------------------------
-- The frame
-------------------------------------------------------------------------------

function T.Build()
    if T.frame then
        return
    end
    local f = CreateFrame("Button", "DruidFrameTargetOfTarget", UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetAttribute("unit", UNIT)
    f:SetAttribute("type1", "target")
    f:RegisterForClicks("AnyUp")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    local health = CreateFrame("StatusBar", nil, f)
    health:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    health:SetMinMaxValues(0, 1)
    health:SetValue(1)
    local gloss = health:CreateTexture(nil, "OVERLAY")
    gloss:SetTexture("Interface\\Buttons\\WHITE8X8")
    gloss:SetVertexColor(1, 1, 1, 0.12)
    gloss:SetPoint("TOPLEFT", health, "TOPLEFT")
    gloss:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "RIGHT")

    local text = CreateFrame("Frame", nil, health)
    text:SetAllPoints(health)
    text:SetFrameLevel(health:GetFrameLevel() + 2)
    local name = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", text, "LEFT", 4, 0)
    name:SetPoint("RIGHT", text, "RIGHT", -4, 0)
    name:SetJustifyH("CENTER")
    name:SetWordWrap(false)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", f, "TOP", 0, 3)
    label:SetText("Target of target: drag to move")
    label:Hide()

    -- Portrait: the game draws it (SetPortraitTexture), cut to a circle, on a dark ring.
    local ring = f:CreateTexture(nil, "BACKGROUND")
    ring:SetColorTexture(0, 0, 0, 1)
    local ringMask = f:CreateMaskTexture()
    ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    ringMask:SetAllPoints(ring)
    local portrait = f:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("TOPLEFT", ring, "TOPLEFT", 2, -2)
    portrait:SetPoint("BOTTOMRIGHT", ring, "BOTTOMRIGHT", -2, 2)
    local mask = f:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(portrait)
    T.ring, T.portrait, T.ringMask, T.portraitMask = ring, portrait, ringMask, mask

    T.frame, T.health, T.name, T.label = f, health, name, label

    -- Dragging (only while unlocked, out of combat) and right-click for the options.
    f:HookScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and T.unlocked and not InCombatLockdown() then
            local cx, cy = ns.Resource.Cursor()
            local x, y = f:GetCenter()
            T.drag = { dx = x - cx, dy = y - cy }
            f:SetScript("OnUpdate", T.DragUpdate)
        elseif button == "RightButton" then
            T.rightDown = { ns.Resource.Cursor() }
        end
    end)
    f:HookScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and T.drag then
            T.DragUpdate()
            T.drag = nil
            f:SetScript("OnUpdate", T.Tick)
        elseif button == "RightButton" and T.rightDown then
            local x, y = ns.Resource.Cursor()
            local moved = math.abs(x - T.rightDown[1]) + math.abs(y - T.rightDown[2])
            T.rightDown = nil
            if moved < 5 and ns.OpenOptions then
                ns.OpenOptions("tot")
            end
        end
    end)
    f:SetScript("OnUpdate", T.Tick)
    f:HookScript("OnShow", function()
        T.Update()
        T.UpdatePortrait()
    end)
    f:Hide()
end

function T.DragUpdate()
    if not T.drag then
        return
    end
    local s = T.Settings()
    local cx, cy = ns.Resource.Cursor()
    s.totX, s.totY = cx + T.drag.dx, cy + T.drag.dy
    T.ApplyPosition()
end

-- Saved centre, or (first time) just right of DruidFrame's health and mana bars, past the
-- Thorns button's spot.
function T.ApplyPosition()
    local f = T.frame
    if not f or InCombatLockdown() then
        return
    end
    local s = T.Settings()
    f:SetSize(s.totWidth, s.totHeight)
    -- The portrait overhangs the bar's left end, a little taller than the bar.
    local size = s.totHeight + 14
    T.ring:SetSize(size, size)
    T.ring:ClearAllPoints()
    T.ring:SetPoint("RIGHT", f, "LEFT", 6, 0)
    T.ApplyPortraitShape(s.totPortrait)
    f:ClearAllPoints()
    if s.totX and s.totY then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", s.totX, s.totY)
        return
    end
    local R = ns.Resource
    local host = R and R.health
    local right, top = host and host:GetRight(), host and host:GetTop()
    if right and top and R.mana and R.mana:GetBottom() then
        local scale = R.frame:GetScale() or 1
        local tall = (top - R.mana:GetBottom()) * scale
        local overhang = s.totPortrait ~= "none" and (s.totHeight + 8) or 0
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right * scale + tall + 16 + overhang, top * scale)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 200, -150)
    end
end

function T.ResetPosition()
    local s = T.Settings()
    s.totX, s.totY = nil, nil
    T.ApplyPosition()
end

-------------------------------------------------------------------------------
-- Showing and hiding (secure: the game decides, from a state driver)
-------------------------------------------------------------------------------

function T.Driver()
    local s = T.Settings()
    if not s.totEnabled then
        return "hide"
    end
    local conditions = "@targettarget,exists"
    if s.totShow == "combat" then
        conditions = "combat," .. conditions
    end
    if s.totGroup then
        conditions = "group," .. conditions
    end
    return "[" .. conditions .. "] show; hide"
end

-- Visibility changes wait for the end of combat.
function T.ApplyVisibility()
    local f = T.frame
    if not f then
        return
    end
    if InCombatLockdown() then
        T.pending = true
        return
    end
    T.pending = false
    UnregisterStateDriver(f, "visibility")
    if T.unlocked and T.Settings().totEnabled then
        f:SetAttribute("type1", nil) -- dragging, not targeting
        f:Show()
    else
        f:SetAttribute("type1", "target")
        RegisterStateDriver(f, "visibility", T.Driver())
    end
    T.label:SetShown(T.unlocked and T.Settings().totEnabled or false)
    T.Update()
end

function T.SetUnlocked(unlocked)
    T.unlocked = unlocked and true or false
    T.ApplyVisibility()
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local REACTION = {
    hostile = { 1.0, 0.25, 0.2 },
    neutral = { 1.0, 0.85, 0.2 },
    friendly = { 0.3, 0.9, 0.3 },
}

local function NameColour()
    local player = Ask(UnitIsPlayer, UNIT)
    if player then
        local ok, _, class = pcall(UnitClass, UNIT)
        local c = ok and not IsSecret(class) and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then
            return c.r, c.g, c.b
        end
    end
    local ok, reaction = pcall(UnitReaction, UNIT, "player")
    if ok and reaction and not IsSecret(reaction) then
        local c = reaction <= 3 and REACTION.hostile or reaction == 4 and REACTION.neutral or REACTION.friendly
        return c[1], c[2], c[3]
    end
    return 1, 1, 1
end

-- The aggro border colour, or nil for none.
function T.AggroColour()
    if not T.Settings().totAggro then
        return nil
    end
    if not Ask(UnitCanAttack, "player", "target") then
        return nil
    end
    local onYou = Ask(UnitIsUnit, UNIT, "player")
    local bear = GetShapeshiftFormID and GetShapeshiftFormID() == 5
    if onYou then
        return bear and { 0.2, 0.9, 0.2 } or { 0.95, 0.15, 0.1 }
    end
    if bear then
        local grouped = Ask(UnitInParty, UNIT) or Ask(UnitInRaid, UNIT) or Ask(UnitPlayerOrPetInParty, UNIT)
        if grouped then
            return { 0.95, 0.15, 0.1 }
        end
    end
    return nil
end

function T.Update()
    local f = T.frame
    if not (f and f:IsShown()) then
        return
    end
    local exists = Ask(UnitExists, UNIT)
    if not exists then
        -- Only while unlocked with nothing to show: a preview.
        T.health:SetMinMaxValues(0, 1)
        T.health:SetValue(1)
        T.health:SetStatusBarColor(0.4, 0.73, 0.17, 1)
        T.name:SetText("Target of target")
        T.name:SetTextColor(1, 1, 1)
        T.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if T.Settings().totPortrait == "square" then
            T.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        f:SetBackdropBorderColor(0, 0, 0, 1)
        return
    end
    T.health:SetMinMaxValues(0, UnitHealthMax(UNIT))
    T.health:SetValue(UnitHealth(UNIT))
    local R = ns.Resource
    local r, g, b
    if R and R.Settings().healthGradient and R.HealthGradient then
        r, g, b = R.HealthGradient(UNIT)
    end
    if r == nil then
        r, g, b = 0.40, 0.73, 0.17
    end
    T.health:SetStatusBarColor(r, g, b, 1)
    if Ask(UnitIsUnit, UNIT, "player") then
        T.name:SetText("You")
    else
        T.name:SetText(UnitName(UNIT))
    end
    T.name:SetTextColor(NameColour())
    local border = T.AggroColour()
    if border then
        f:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    else
        f:SetBackdropBorderColor(0, 0, 0, 1)
    end
end

-- The portrait is redrawn when the target of target may have changed (not on every poll).
function T.UpdatePortrait()
    if T.portrait and T.frame and T.Settings().totPortrait ~= "none" and Ask(UnitExists, UNIT) then
        SetPortraitTexture(T.portrait, UNIT)
        T.portrait:SetTexCoord(0, 1, 0, 1)
    end
end

-- Circle: both cut by the round mask. Square: no mask, a square dark edge. Off: hidden.
function T.ApplyPortraitShape(shape)
    if not T.ring then
        return
    end
    local round = shape == "circle"
    if round ~= T.round then
        T.round = round
        if round then
            T.ring:AddMaskTexture(T.ringMask)
            T.portrait:AddMaskTexture(T.portraitMask)
        else
            T.ring:RemoveMaskTexture(T.ringMask)
            T.portrait:RemoveMaskTexture(T.portraitMask)
        end
    end
    T.ring:SetShown(shape ~= "none")
    T.portrait:SetShown(shape ~= "none")
end

-- Target of target has no events of its own, so it's polled while shown (only then).
local sinceUpdate = 0
function T.Tick(_, elapsed)
    sinceUpdate = sinceUpdate + (elapsed or 0)
    if sinceUpdate >= UPDATE_INTERVAL then
        sinceUpdate = 0
        T.Update()
    end
end

-------------------------------------------------------------------------------
-- Options page: DruidFrame > Target of Target
-------------------------------------------------------------------------------

local panel = CreateFrame("Frame", "DruidFrameToTOptions", UIParent)
panel.name = "Target of Target"
panel:Hide()
ns.panels = ns.panels or {}
ns.panels.tot = panel

local widgets = {}

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Target of Target")
local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetWidth(560)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Who your target is targeting, as a small frame of its own. Left-click it to target them. "
    .. "While these options are open, drag it to move it. /druidtot opens this page.")

local function Changed()
    T.ApplyPosition()
    T.ApplyVisibility()
end

local function Check(name, anchor, label, key, y)
    local cb = CreateFrame("CheckButton", name, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -6)
    local text = cb.Text or _G[name .. "Text"]
    if text then text:SetText(label) end
    cb:SetScript("OnClick", function(self)
        T.Settings()[key] = self:GetChecked() and true or false
        Changed()
    end)
    widgets[#widgets + 1] = function() cb:SetChecked(T.Settings()[key]) end
    return cb
end

local enabledBox = Check("DruidFrameToTEnabled", subtitle, "Show the target of target frame", "totEnabled", -14)
local aggroBox = Check("DruidFrameToTAggro", enabledBox,
    "Aggro border: green when it's on you in Bear Form, red when you lose it (Bear) or pull it (other forms)",
    "totAggro")

local groupBox = Check("DruidFrameToTGroup", aggroBox, "Only when in a group (party or raid)", "totGroup")

local portraitButton = CreateFrame("Button", "DruidFrameToTPortrait", panel, "UIPanelButtonTemplate")
portraitButton:SetSize(300, 22)
portraitButton:SetPoint("TOPLEFT", groupBox, "BOTTOMLEFT", 4, -12)
local function PortraitLabel()
    for _, choice in ipairs(T.PORTRAIT) do
        if choice.key == T.Settings().totPortrait then
            return "Portrait: " .. choice.label
        end
    end
    return "Portrait: " .. T.PORTRAIT[1].label
end
portraitButton:SetScript("OnClick", function(self)
    local s = T.Settings()
    local index = 1
    for i, choice in ipairs(T.PORTRAIT) do
        if choice.key == s.totPortrait then index = i end
    end
    s.totPortrait = T.PORTRAIT[index % #T.PORTRAIT + 1].key
    self:SetText(PortraitLabel())
    Changed()
    T.UpdatePortrait()
end)
widgets[#widgets + 1] = function() portraitButton:SetText(PortraitLabel()) end
local portraitBox = portraitButton

local showButton = CreateFrame("Button", "DruidFrameToTShow", panel, "UIPanelButtonTemplate")
showButton:SetSize(300, 22)
showButton:SetPoint("TOPLEFT", portraitBox, "BOTTOMLEFT", 0, -10)
local function ShowLabel()
    for _, choice in ipairs(T.SHOW) do
        if choice.key == T.Settings().totShow then
            return "Show: " .. choice.label
        end
    end
    return "Show: " .. T.SHOW[1].label
end
showButton:SetScript("OnClick", function(self)
    local s = T.Settings()
    local index = 1
    for i, choice in ipairs(T.SHOW) do
        if choice.key == s.totShow then index = i end
    end
    s.totShow = T.SHOW[index % #T.SHOW + 1].key
    self:SetText(ShowLabel())
    Changed()
end)
widgets[#widgets + 1] = function() showButton:SetText(ShowLabel()) end

local function Slider(name, anchor, label, key, low, high, step, y)
    local slider = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -34)
    slider:SetWidth(240)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local text = slider.Text or _G[name .. "Text"]
    local function Label(v)
        if text then text:SetText(label .. ": " .. math.floor(v + 0.5)) end
    end
    if slider.Low then slider.Low:SetText(low) elseif _G[name .. "Low"] then _G[name .. "Low"]:SetText(low) end
    if slider.High then slider.High:SetText(high) elseif _G[name .. "High"] then _G[name .. "High"]:SetText(high) end
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        T.Settings()[key] = value
        Label(value)
        Changed()
    end)
    widgets[#widgets + 1] = function()
        slider:SetValue(T.Settings()[key])
        Label(T.Settings()[key])
    end
    return slider
end

local widthSlider = Slider("DruidFrameToTWidth", showButton, "Width", "totWidth", 60, 300, 5, -30)
local heightSlider = Slider("DruidFrameToTHeight", widthSlider, "Height", "totHeight", 10, 40, 1)

local resetButton = CreateFrame("Button", "DruidFrameToTReset", panel, "UIPanelButtonTemplate")
resetButton:SetSize(200, 22)
resetButton:SetPoint("TOPLEFT", heightSlider, "BOTTOMLEFT", 0, -30)
resetButton:SetText("Put it next to DruidFrame")
resetButton:SetScript("OnClick", function() T.ResetPosition() end)

panel:SetScript("OnShow", function()
    for _, refresh in ipairs(widgets) do refresh() end
end)
panel:HookScript("OnShow", function() if ns.PageShown then ns.PageShown(true) end end)
panel:HookScript("OnHide", function() if ns.PageShown then ns.PageShown(false) end end)

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "UNIT_TARGET", "PLAYER_TARGET_CHANGED",
    "UPDATE_SHAPESHIFT_FORM", "UNIT_PORTRAIT_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        if not (ns.IsDruid and ns.IsDruid()) then
            return
        end
        T.Settings()
        if not InCombatLockdown() then
            T.Build()
            T.ApplyPosition()
            T.ApplyVisibility()
        else
            T.pending = true
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not T.frame and ns.IsDruid and ns.IsDruid() then
            T.Build()
            T.ApplyPosition()
        end
        if T.pending then
            T.ApplyVisibility()
        end
    elseif event == "UNIT_TARGET" then
        if unit == "target" then
            T.Update()
            T.UpdatePortrait()
        end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "UNIT_PORTRAIT_UPDATE" then
        T.Update()
        T.UpdatePortrait()
    else
        T.Update()
    end
end)

SLASH_DRUIDTOT1 = "/druidtot"
SlashCmdList.DRUIDTOT = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "debug" then
        local s = T.Settings()
        print("|cff55ff55DruidFrame target of target|r on:", tostring(s.totEnabled), "| show:", s.totShow,
            "| only in a group:", tostring(s.totGroup), "| rule:", T.Driver(),
            "| frame shown:", tostring(T.frame and T.frame:IsShown()))
        print("  exists:", tostring(Ask(UnitExists, UNIT)), "| is you:", tostring(Ask(UnitIsUnit, UNIT, "player")),
            "| target hostile:", tostring(Ask(UnitCanAttack, "player", "target")),
            "| in your group:", tostring(Ask(UnitInParty, UNIT) or Ask(UnitInRaid, UNIT)),
            "| name secret:", tostring(IsSecret(UnitName(UNIT))), "| health secret:", tostring(IsSecret(UnitHealth(UNIT))))
        return
    end
    if ns.OpenOptions then
        ns.OpenOptions("tot")
    end
end
