-- DruidFrame: buff reminders. Out of combat, a Mark of the Wild button shows to the left of
-- the display while you don't have it, and a Thorns button to the right. Clicking casts it on
-- you and the button fades out.
--
-- The buttons are secure (they cast spells), so they're only shown, hidden, moved or set up
-- out of combat. They're parented to UIParent and placed by screen position, not anchored to
-- the display: anchoring a secure frame to ours would stop the display changing its layout
-- in combat (e.g. when you shift).

local _, ns = ...

local B = {}
ns.Buffs = B

local FADE_TIME = 0.5

B.BUFFS = {
    {
        key = "mark", side = "left", name = "Mark of the Wild", frameName = "DruidFrameMarkButton",
        icon = "Interface\\Icons\\Spell_Nature_Regeneration",
        ranks = { 9885, 9884, 8907, 5234, 6756, 5232, 1126 },
        -- Gift of the Wild counts as having it.
        also = { 21850, 21849 }, alsoName = "Gift of the Wild",
    },
    {
        key = "thorns", side = "right", name = "Thorns", frameName = "DruidFrameThornsButton",
        icon = "Interface\\Icons\\Spell_Nature_Thorns",
        ranks = { 9910, 9756, 8914, 1075, 782, 467 },
    },
}

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Knows(spellID)
    for _, fn in ipairs({ IsPlayerSpell, IsSpellKnown }) do
        local ok, known = pcall(fn, spellID)
        if ok and known and not IsSecret(known) then
            return true
        end
    end
    return false
end

function B.Learned(buff)
    for _, spellID in ipairs(buff.ranks) do
        if Knows(spellID) then
            return true
        end
    end
    return false
end

-- true = you have it, false = you don't, nil = the client won't say (then leave things be).
local function HasAura(ids, name)
    local answered = false
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, spellID in ipairs(ids) do
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
            if ok then
                answered = true
                if aura ~= nil then
                    return true
                end
            end
        end
    end
    if name and AuraUtil and AuraUtil.FindAuraByName then
        local ok, found = pcall(AuraUtil.FindAuraByName, name, "player", "HELPFUL")
        if ok then
            answered = true
            if found ~= nil then
                return true
            end
        end
    end
    if answered then
        return false
    end
    return nil
end

function B.HasBuff(buff)
    local has = HasAura(buff.ranks, buff.name)
    if has then
        return true
    end
    if buff.also then
        local also = HasAura(buff.also, buff.alsoName)
        if also then
            return true
        end
        if has == nil then
            return also
        end
    end
    return has
end

-- Battlegrounds and arenas: buffs get purged, so re-casting isn't usually worth the mana.
function B.InPvP()
    if not IsInInstance then
        return false
    end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    return ok and inInstance and (instanceType == "pvp" or instanceType == "arena") or false
end

local function Enabled()
    local R = ns.Resource
    if not (R and ns.IsDruid and ns.IsDruid()) then
        return false
    end
    local s = R.Settings()
    return s.buffButtons and (s.buffButtonsPvP or not B.InPvP())
end

-- Fade out after a click, then look again (in case the cast didn't land).
local function FadeUpdate(button, elapsed)
    button.fade = button.fade + elapsed
    if button.fade >= FADE_TIME then
        button:SetScript("OnUpdate", nil)
        button.fade = nil
        button:SetAlpha(0)
        if not InCombatLockdown() then
            button:Hide()
        end
        B.Check()
    else
        button:SetAlpha(1 - button.fade / FADE_TIME)
    end
end

local function StartFade(button)
    if button.fade then
        return
    end
    button.fade = 0
    button:SetScript("OnUpdate", FadeUpdate)
end

function B.Create()
    if B.buttons or InCombatLockdown() then
        return B.buttons ~= nil
    end
    B.buttons = {}
    for _, buff in ipairs(B.BUFFS) do
        local button = CreateFrame("Button", buff.frameName, UIParent, "SecureActionButtonTemplate")
        button:SetFrameStrata("MEDIUM")
        button:RegisterForClicks("AnyUp", "AnyDown")
        -- A macro, so it works from a form too: leave the form, then cast on yourself.
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", "/cancelform [form]\n/cast [@player] " .. buff.name)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexture(buff.icon)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        button.icon = icon
        local border = button:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0, 0, 0, 1)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(button)
        highlight:SetColorTexture(1, 1, 1, 0.2)
        button:SetScript("PostClick", function(self)
            if not (ns.Resource and ns.Resource.unlocked) then
                StartFade(self)
            end
        end)
        button:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(buff.name)
                GameTooltip:AddLine("Click to cast it on yourself.", 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        button.buff = buff
        button:Hide()
        B.buttons[buff.key] = button
    end
    return true
end

-- Beside the health and mana bars: as tall as both plus the gap between them, square.
function B.Layout()
    local R = ns.Resource
    if not (B.buttons and R and R.frame and R.health and R.mana) or InCombatLockdown() then
        return
    end
    local scale = R.frame:GetScale() or 1
    local left, right, top = R.health:GetLeft(), R.health:GetRight(), R.health:GetTop()
    local bottom = R.mana:GetBottom()
    if not (left and right and top and bottom) then
        return
    end
    local size = (top - bottom) * scale
    local gap = ((R.Settings().padding or 4) + 1) * scale
    for _, button in pairs(B.buttons) do
        button:SetSize(size, size)
        button:ClearAllPoints()
        if button.buff.side == "left" then
            button:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left * scale - gap, top * scale)
        else
            button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right * scale + gap, top * scale)
        end
    end
end

-- Show the button for each missing buff. Out of combat only: in combat nothing changes.
function B.Check()
    if InCombatLockdown() then
        B.dirty = true
        return
    end
    B.dirty = false
    if not Enabled() then
        if B.buttons then
            for _, button in pairs(B.buttons) do
                button:Hide()
            end
        end
        return
    end
    if not B.Create() then
        return
    end
    B.Layout()
    local R = ns.Resource
    local preview = R.unlocked -- shown while the options are open, so you can see where
    local unavailable = UnitIsDeadOrGhost("player") or (UnitOnTaxi and UnitOnTaxi("player"))
    for _, button in pairs(B.buttons) do
        if not button.fade then
            local buff = button.buff
            local show = button:IsShown()
            if preview then
                show = true
            elseif unavailable or not B.Learned(buff) then
                show = false
            else
                local has = B.HasBuff(buff)
                if has ~= nil then
                    show = not has
                end
            end
            button:SetAlpha(1)
            button:SetShown(show)
        end
    end
end

-- Called by Resource.lua when the display changes (layout, position, settings, unlocking).
function B.Refresh()
    B.Check()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UNIT_AURA",
    "SPELLS_CHANGED", "PLAYER_UNGHOST", "PLAYER_ALIVE", "PLAYER_CONTROL_GAINED", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then
        return
    end
    B.Check()
end)

function B.Debug()
    print("|cff55ff55DruidFrame buff buttons|r on:", tostring(ns.Resource and ns.Resource.Settings().buffButtons),
        "| in combat:", tostring(InCombatLockdown()), "| battleground/arena:", tostring(B.InPvP()),
        "| shown there:", tostring(ns.Resource and ns.Resource.Settings().buffButtonsPvP))
    for _, buff in ipairs(B.BUFFS) do
        local button = B.buttons and B.buttons[buff.key]
        print(buff.name, "learned:", tostring(B.Learned(buff)), "| have it:", tostring(B.HasBuff(buff)),
            "| button shown:", tostring(button and button:IsShown()))
    end
end
