-- DruidFrame: small unit frames of its own, in one style, so they can sit by DruidFrame's bars
-- and Blizzard's Player and Target frames can go elsewhere:
--
--   Target            your target
--   Target of Target  who your target is targeting
--   Tank's Target     what the group's tank (by assigned role) is targeting, when that isn't you
--
-- Each has:
--   * Their portrait, round, overhanging the bar's left end (option).
--   * Health bar (with DruidFrame's health colour gradient if that's on) and the name, class-
--     coloured for players, reaction-coloured for NPCs; "You" when it's you.
--   * The raid target icon, if one's been put on them, and Blizzard's elite (or rare) dragon.
--   * An aggro border, when an enemy is involved (see each frame's AggroColour).
--   * Left-click targets the unit. They're secure buttons, so showing and hiding is left to the
--     game (a state driver), and they're only moved or set up out of combat.
--   * Unlocked with DruidFrame's options: shown even with nothing to show, and left-drag moves
--     them. Right-click opens their options page.

local _, ns = ...

local UPDATE_INTERVAL = 0.1
local RED, GREEN = { 0.95, 0.15, 0.1 }, { 0.2, 0.9, 0.2 }

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

local function InGroup(unit)
    return Ask(UnitInParty, unit) or Ask(UnitInRaid, unit) or Ask(UnitPlayerOrPetInParty, unit)
end

local function Bear()
    return GetShapeshiftFormID and GetShapeshiftFormID() == 5
end

ns.UnitFrames = {}

-------------------------------------------------------------------------------
-- The group's tank (by assigned role), for Tank's Target. nil when there's none, or it's you.
-------------------------------------------------------------------------------

function ns.TankUnit()
    local units = {}
    local raid = Ask(IsInRaid)
    if raid then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    if UnitGroupRolesAssigned then
        local ok, mine = pcall(UnitGroupRolesAssigned, "player")
        if ok and mine == "TANK" then
            return nil -- you're the tank: your own target frame covers it
        end
    end
    for _, unit in ipairs(units) do
        if Ask(UnitExists, unit) and not Ask(UnitIsUnit, unit, "player") and UnitGroupRolesAssigned then
            local ok, role = pcall(UnitGroupRolesAssigned, unit)
            if ok and not IsSecret(role) and role == "TANK" then
                return unit
            end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- One frame
-------------------------------------------------------------------------------

local function NewUnitFrame(def)
    local T = { def = def }
    local P = def.prefix -- settings keys: P .. "Enabled", P .. "Width", ...
    ns.UnitFrames[#ns.UnitFrames + 1] = T

    local DEFAULTS = {
        Enabled = true,
        Show = "always", -- "always" or "combat"
        Group = false,   -- only while in a party or raid
        Aggro = true,
        Portrait = true,
        Width = 120,
        Height = 18,
        -- X / Y: its centre, in UIParent coordinates (nil: next to DruidFrame)
    }
    T.SHOW = {
        { key = "always", label = def.showAlways },
        { key = "combat", label = "Only in combat" },
    }

    function T.Settings()
        local s = ns.Resource and ns.Resource.Settings() or {}
        -- The target-of-target portrait was briefly a circle / square / off choice.
        if type(s[P .. "Portrait"]) == "string" then s[P .. "Portrait"] = (s[P .. "Portrait"] ~= "none") end
        for key, value in pairs(DEFAULTS) do
            if s[P .. key] == nil then
                s[P .. key] = value
            end
        end
        return s
    end
    local function Get(key) return T.Settings()[P .. key] end

    -- The unit this frame shows (nil: none right now, e.g. no tank).
    function T.Unit()
        return def.Unit()
    end

    function T.Build()
        if T.frame then
            return
        end
        local f = CreateFrame("Button", def.frameName, UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
        f:SetFrameStrata("MEDIUM")
        f:SetClampedToScreen(true)
        T.unitAttribute = T.Unit() or def.fallbackUnit
        f:SetAttribute("unit", T.unitAttribute)
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
        label:SetText(def.title .. ": drag to move")
        label:Hide()

        -- Portrait: the game draws it (SetPortraitTexture), cut to a circle, on a dark ring.
        local ring = f:CreateTexture(nil, "BACKGROUND")
        ring:SetColorTexture(0, 0, 0, 1)
        local ringMask = f:CreateMaskTexture()
        ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ringMask:SetAllPoints(ring)
        ring:AddMaskTexture(ringMask)
        local portrait = f:CreateTexture(nil, "ARTWORK")
        portrait:SetPoint("TOPLEFT", ring, "TOPLEFT", 2, -2)
        portrait:SetPoint("BOTTOMRIGHT", ring, "BOTTOMRIGHT", -2, 2)
        local mask = f:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(portrait)
        portrait:AddMaskTexture(mask)

        -- Above the text: the raid target icon (centred on the top edge) and the elite dragon
        -- (just past the bar's right end).
        local marks = CreateFrame("Frame", nil, f)
        marks:SetAllPoints(f)
        marks:SetFrameLevel(text:GetFrameLevel() + 2)
        local raidIcon = marks:CreateTexture(nil, "OVERLAY")
        raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        raidIcon:Hide()
        local elite = marks:CreateTexture(nil, "OVERLAY")
        elite:Hide()

        T.frame, T.health, T.name, T.label = f, health, name, label
        T.ring, T.portrait, T.raidIcon, T.elite = ring, portrait, raidIcon, elite

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
                    ns.OpenOptions(def.key)
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
        s[P .. "X"], s[P .. "Y"] = cx + T.drag.dx, cy + T.drag.dy
        T.ApplyPosition()
    end

    -- Saved centre, or (first time) to the right of DruidFrame's bars, past the Thorns button's
    -- spot, stacked: Target, then Target of Target, then Tank's Target.
    function T.ApplyPosition()
        local f = T.frame
        if not f or InCombatLockdown() then
            return
        end
        local s = T.Settings()
        local width, height = s[P .. "Width"], s[P .. "Height"]
        f:SetSize(width, height)
        -- The portrait overhangs the bar's left end, a little taller than the bar.
        local size = height + 14
        T.ring:SetSize(size, size)
        T.ring:ClearAllPoints()
        T.ring:SetPoint("RIGHT", f, "LEFT", 6, 0)
        T.ring:SetShown(s[P .. "Portrait"])
        T.portrait:SetShown(s[P .. "Portrait"])
        T.raidIcon:SetSize(height + 2, height + 2)
        T.raidIcon:ClearAllPoints()
        T.raidIcon:SetPoint("CENTER", f, "TOP", 0, 1)
        T.elite:SetSize(height + 6, height + 6)
        T.elite:ClearAllPoints()
        T.elite:SetPoint("LEFT", f, "RIGHT", 0, 0)
        f:ClearAllPoints()
        if s[P .. "X"] and s[P .. "Y"] then
            f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", s[P .. "X"], s[P .. "Y"])
            return
        end
        local R = ns.Resource
        local host = R and R.health
        local right, top = host and host:GetRight(), host and host:GetTop()
        if right and top and R.mana and R.mana:GetBottom() then
            local scale = R.frame:GetScale() or 1
            local tall = (top - R.mana:GetBottom()) * scale
            local overhang = s[P .. "Portrait"] and (height + 8) or 0
            local down = (def.order - 1) * (height + 22)
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right * scale + tall + 16 + overhang, top * scale - down)
        else
            f:SetPoint("CENTER", UIParent, "CENTER", 200, -150 - (def.order - 1) * 40)
        end
    end

    function T.ResetPosition()
        local s = T.Settings()
        s[P .. "X"], s[P .. "Y"] = nil, nil
        T.ApplyPosition()
    end

    ---------------------------------------------------------------------------
    -- Showing and hiding (secure: the game decides, from a state driver)
    ---------------------------------------------------------------------------

    function T.Driver()
        local s = T.Settings()
        local unit = T.Unit()
        if not s[P .. "Enabled"] or not unit then
            return "hide"
        end
        local conditions = "@" .. unit .. ",exists"
        if s[P .. "Show"] == "combat" then
            conditions = "combat," .. conditions
        end
        if s[P .. "Group"] or def.groupOnly then
            conditions = "group," .. conditions
        end
        return "[" .. conditions .. "] show; hide"
    end

    -- Visibility (and, for the tank, which unit) change only out of combat.
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
        local unit = T.Unit() or def.fallbackUnit
        if unit ~= T.unitAttribute then
            T.unitAttribute = unit
            f:SetAttribute("unit", unit)
        end
        UnregisterStateDriver(f, "visibility")
        if T.unlocked and Get("Enabled") then
            f:SetAttribute("type1", nil) -- dragging, not targeting
            f:Show()
        else
            f:SetAttribute("type1", "target")
            RegisterStateDriver(f, "visibility", T.Driver())
        end
        T.label:SetShown(T.unlocked and Get("Enabled") or false)
        T.Update()
        T.UpdatePortrait()
    end

    function T.SetUnlocked(unlocked)
        T.unlocked = unlocked and true or false
        T.ApplyVisibility()
    end

    ---------------------------------------------------------------------------
    -- Drawing
    ---------------------------------------------------------------------------

    local REACTION = {
        hostile = { 1.0, 0.25, 0.2 },
        neutral = { 1.0, 0.85, 0.2 },
        friendly = { 0.3, 0.9, 0.3 },
    }

    local function NameColour(unit)
        if Ask(UnitIsPlayer, unit) then
            local ok, _, class = pcall(UnitClass, unit)
            local c = ok and not IsSecret(class) and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if c then
                return c.r, c.g, c.b
            end
        end
        local ok, reaction = pcall(UnitReaction, unit, "player")
        if ok and reaction and not IsSecret(reaction) then
            local c = reaction <= 3 and REACTION.hostile or reaction == 4 and REACTION.neutral or REACTION.friendly
            return c[1], c[2], c[3]
        end
        return 1, 1, 1
    end

    function T.AggroColour()
        if not Get("Aggro") then
            return nil
        end
        return def.AggroColour()
    end

    local function ShowMarks(unit)
        -- Raid target icon.
        local ok, index = pcall(GetRaidTargetIndex, unit)
        if ok and index and not IsSecret(index) and SetRaidTargetIconTexture then
            SetRaidTargetIconTexture(T.raidIcon, index)
            T.raidIcon:Show()
        elseif ok and index and IsSecret(index) and SetRaidTargetIconTexture then
            -- Can't compare it, but the game can still draw it.
            pcall(SetRaidTargetIconTexture, T.raidIcon, index)
            T.raidIcon:Show()
        else
            T.raidIcon:Hide()
        end
        -- Elite / rare dragon.
        local okClass, class = pcall(UnitClassification, unit)
        local atlas
        if okClass and class and not IsSecret(class) then
            if class == "elite" or class == "worldboss" then
                atlas = "nameplates-icon-elite-gold"
            elseif class == "rareelite" or class == "rare" then
                atlas = "nameplates-icon-elite-silver"
            end
        end
        if atlas and T.elite.SetAtlas and pcall(T.elite.SetAtlas, T.elite, atlas) then
            T.elite:Show()
        else
            T.elite:Hide()
        end
    end

    function T.Update()
        local f = T.frame
        if not (f and f:IsShown()) then
            return
        end
        local unit = T.Unit()
        if not (unit and Ask(UnitExists, unit)) then
            -- Only while unlocked with nothing to show: a preview.
            T.health:SetMinMaxValues(0, 1)
            T.health:SetValue(1)
            T.health:SetStatusBarColor(0.4, 0.73, 0.17, 1)
            T.name:SetText(def.title)
            T.name:SetTextColor(1, 1, 1)
            T.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            T.raidIcon:Hide()
            T.elite:Hide()
            f:SetBackdropBorderColor(0, 0, 0, 1)
            f:SetAlpha(1)
            return
        end
        T.health:SetMinMaxValues(0, UnitHealthMax(unit))
        T.health:SetValue(UnitHealth(unit))
        local R = ns.Resource
        local r, g, b
        if R and R.Settings().healthGradient and R.HealthGradient then
            r, g, b = R.HealthGradient(unit)
        end
        if r == nil then
            r, g, b = 0.40, 0.73, 0.17
        end
        T.health:SetStatusBarColor(r, g, b, 1)
        if Ask(UnitIsUnit, unit, "player") then
            T.name:SetText("You")
        else
            T.name:SetText(UnitName(unit))
        end
        T.name:SetTextColor(NameColour(unit))
        ShowMarks(unit)
        -- Frames that would only repeat your target (Tank's Target, when you're on the same mob)
        -- go transparent: the game won't let them be hidden in combat.
        local same = def.hideWhenTargeted and Ask(UnitIsUnit, unit, "target")
        f:SetAlpha(same and 0 or 1)
        local border = T.AggroColour()
        if border then
            f:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        else
            f:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end

    -- The portrait is redrawn when the unit may have changed (not on every poll).
    function T.UpdatePortrait()
        local unit = T.Unit()
        if T.portrait and T.frame and Get("Portrait") and unit and Ask(UnitExists, unit) then
            SetPortraitTexture(T.portrait, unit)
        end
    end

    -- These units have no events of their own, so they're polled while shown (only then).
    local sinceUpdate = 0
    function T.Tick(_, elapsed)
        sinceUpdate = sinceUpdate + (elapsed or 0)
        if sinceUpdate >= UPDATE_INTERVAL then
            sinceUpdate = 0
            T.Update()
        end
    end

    ---------------------------------------------------------------------------
    -- Options page: DruidFrame > <title>
    ---------------------------------------------------------------------------

    local W = def.widgetPrefix
    local panel = CreateFrame("Frame", W .. "Options", UIParent)
    panel.name = def.title
    panel:Hide()
    ns.panels = ns.panels or {}
    ns.panels[def.key] = panel
    T.panel = panel

    local widgets = {}

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(def.title)
    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(560)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(def.about .. " Left-click it to target them. While these options are open, drag it to move it. "
        .. def.slash .. " opens this page.")

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
            T.Settings()[P .. key] = self:GetChecked() and true or false
            Changed()
        end)
        widgets[#widgets + 1] = function() cb:SetChecked(Get(key)) end
        return cb
    end

    local last = Check(W .. "Enabled", subtitle, "Show the " .. def.title:lower() .. " frame", "Enabled", -14)
    last = Check(W .. "Aggro", last, def.aggroLabel, "Aggro")
    if not def.groupOnly then
        last = Check(W .. "Group", last, "Only when in a group (party or raid)", "Group")
    end
    last = Check(W .. "Portrait", last, "Show their portrait (round, left of the bar)", "Portrait")

    local showButton = CreateFrame("Button", W .. "Show", panel, "UIPanelButtonTemplate")
    showButton:SetSize(300, 22)
    showButton:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 4, -12)
    local function ShowLabel()
        for _, choice in ipairs(T.SHOW) do
            if choice.key == Get("Show") then
                return "Show: " .. choice.label
            end
        end
        return "Show: " .. T.SHOW[1].label
    end
    showButton:SetScript("OnClick", function(self)
        local s = T.Settings()
        local index = 1
        for i, choice in ipairs(T.SHOW) do
            if choice.key == s[P .. "Show"] then index = i end
        end
        s[P .. "Show"] = T.SHOW[index % #T.SHOW + 1].key
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
            T.Settings()[P .. key] = value
            Label(value)
            Changed()
        end)
        widgets[#widgets + 1] = function()
            slider:SetValue(Get(key))
            Label(Get(key))
        end
        return slider
    end

    local widthSlider = Slider(W .. "Width", showButton, "Width", "Width", 60, 300, 5, -30)
    local heightSlider = Slider(W .. "Height", widthSlider, "Height", "Height", 10, 40, 1)

    local resetButton = CreateFrame("Button", W .. "Reset", panel, "UIPanelButtonTemplate")
    resetButton:SetSize(200, 22)
    resetButton:SetPoint("TOPLEFT", heightSlider, "BOTTOMLEFT", 0, -30)
    resetButton:SetText("Put it next to DruidFrame")
    resetButton:SetScript("OnClick", function() T.ResetPosition() end)

    panel:SetScript("OnShow", function()
        for _, refresh in ipairs(widgets) do refresh() end
    end)
    panel:HookScript("OnShow", function() if ns.PageShown then ns.PageShown(true) end end)
    panel:HookScript("OnHide", function() if ns.PageShown then ns.PageShown(false) end end)

    ---------------------------------------------------------------------------
    -- Slash command
    ---------------------------------------------------------------------------

    local slashKey = "DRUIDFRAME_" .. def.key:upper()
    _G["SLASH_" .. slashKey .. "1"] = def.slash
    SlashCmdList[slashKey] = function(msg)
        msg = (msg or ""):lower():match("^%s*(.-)%s*$")
        if msg == "debug" then
            local s = T.Settings()
            local unit = T.Unit()
            print("|cff55ff55DruidFrame " .. def.title:lower() .. "|r on:", tostring(s[P .. "Enabled"]),
                "| unit:", tostring(unit), "| show:", s[P .. "Show"], "| rule:", T.Driver(),
                "| frame shown:", tostring(T.frame and T.frame:IsShown()))
            if unit then
                local okIcon, icon = pcall(GetRaidTargetIndex, unit)
                local okClass, class = pcall(UnitClassification, unit)
                print("  exists:", tostring(Ask(UnitExists, unit)), "| is you:", tostring(Ask(UnitIsUnit, unit, "player")),
                    "| hostile:", tostring(Ask(UnitCanAttack, "player", unit)),
                    "| raid icon:", okIcon and (IsSecret(icon) and "(secret)" or tostring(icon)) or "error",
                    "| classification:", okClass and (IsSecret(class) and "(secret)" or tostring(class)) or "error",
                    "| name secret:", tostring(IsSecret(UnitName(unit))), "| health secret:", tostring(IsSecret(UnitHealth(unit))))
            end
            if def.key == "tank" and UnitGroupRolesAssigned then
                for i = 1, 4 do
                    local u = "party" .. i
                    if Ask(UnitExists, u) then
                        local ok, role = pcall(UnitGroupRolesAssigned, u)
                        print("  ", u, tostring(UnitName(u)), "role:", ok and tostring(role) or "error")
                    end
                end
            end
            return
        end
        if ns.OpenOptions then
            ns.OpenOptions(def.key)
        end
    end

    return T
end

-------------------------------------------------------------------------------
-- The three frames
-------------------------------------------------------------------------------

-- Aggro on an enemy ("mob") that's targeting "victim": in Bear Form green while it's on you and
-- red when it's on someone else in your group (you've lost it); out of Bear Form red while it's
-- on you (you've pulled it).
local function YourAggro(mob, victim)
    if not Ask(UnitCanAttack, "player", mob) then
        return nil
    end
    local onYou = Ask(UnitIsUnit, victim, "player")
    if onYou then
        return Bear() and GREEN or RED
    end
    if Bear() and InGroup(victim) then
        return RED
    end
    return nil
end

local Target = NewUnitFrame({
    key = "target", prefix = "tgt", order = 1, title = "Target",
    frameName = "DruidFrameTarget", widgetPrefix = "DruidFrameTarget", slash = "/druidtarget",
    showAlways = "Whenever you have a target",
    about = "Your target, as a small frame of its own, with its raid icon and elite dragon.",
    aggroLabel = "Aggro border: green when it's on you in Bear Form, red when you lose it (Bear) or pull it (other forms)",
    Unit = function() return "target" end,
    fallbackUnit = "target",
    AggroColour = function() return YourAggro("target", "targettarget") end,
})

local ToT = NewUnitFrame({
    key = "tot", prefix = "tot", order = 2, title = "Target of Target",
    frameName = "DruidFrameTargetOfTarget", widgetPrefix = "DruidFrameToT", slash = "/druidtot",
    showAlways = "Whenever your target has a target",
    about = "Who your target is targeting, as a small frame of its own.",
    aggroLabel = "Aggro border: green when it's on you in Bear Form, red when you lose it (Bear) or pull it (other forms)",
    Unit = function() return "targettarget" end,
    fallbackUnit = "targettarget",
    AggroColour = function() return YourAggro("target", "targettarget") end,
})

local Tank = NewUnitFrame({
    key = "tank", prefix = "tank", order = 3, title = "Tank's Target",
    frameName = "DruidFrameTankTarget", widgetPrefix = "DruidFrameTankTarget", slash = "/druidtank",
    showAlways = "Whenever the tank has a target",
    about = "What your group's tank (the member with the Tank role) is targeting. Not shown when you're the tank, "
        .. "when no one has the Tank role, or while you're targeting the same thing.",
    aggroLabel = "Aggro border: green while it's on the tank, red when it's on someone else (the tank has lost it)",
    groupOnly = true,
    hideWhenTargeted = true,
    Unit = function()
        local tank = ns.TankUnit()
        return tank and (tank .. "target") or nil
    end,
    fallbackUnit = "party1target",
    AggroColour = function()
        local tank = ns.TankUnit()
        if not tank then return nil end
        local mob = tank .. "target"
        if not Ask(UnitCanAttack, "player", mob) then return nil end
        local victim = mob .. "target"
        if Ask(UnitIsUnit, victim, tank) then
            return GREEN
        end
        if Ask(UnitIsUnit, victim, "player") or InGroup(victim) then
            return RED
        end
        return nil
    end,
})

ns.Target, ns.ToT, ns.TankTarget = Target, ToT, Tank

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local function Each(method)
    for _, T in ipairs(ns.UnitFrames) do
        T[method]()
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "UNIT_TARGET", "PLAYER_TARGET_CHANGED",
    "UPDATE_SHAPESHIFT_FORM", "UNIT_PORTRAIT_UPDATE", "RAID_TARGET_UPDATE", "UNIT_CLASSIFICATION_CHANGED",
    "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not (ns.IsDruid and ns.IsDruid()) then
            return
        end
        for _, T in ipairs(ns.UnitFrames) do
            T.Settings()
            if not InCombatLockdown() then
                T.Build()
                T.ApplyPosition()
                T.ApplyVisibility()
            else
                T.pending = true
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        for _, T in ipairs(ns.UnitFrames) do
            if not T.frame and ns.IsDruid and ns.IsDruid() then
                T.Build()
                T.ApplyPosition()
            end
            if T.pending then
                T.ApplyVisibility()
            end
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        -- Who the tank is can change: the tank frame's unit is set again (out of combat).
        Tank.ApplyVisibility()
        Each("Update")
    elseif event == "UNIT_TARGET" or event == "PLAYER_TARGET_CHANGED" or event == "UNIT_PORTRAIT_UPDATE" then
        Each("Update")
        Each("UpdatePortrait")
    else
        Each("Update")
    end
end)
