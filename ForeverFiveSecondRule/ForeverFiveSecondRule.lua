local MANA_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local FIVE_SECOND_RULE = 5.0
local FSR_UPDATE_INTERVAL = 0.05

ForeverFiveSecondRuleDB = ForeverFiveSecondRuleDB or {}

local DEFAULTS = {
    enabled = true,
    showTimerText = true,
    markerWidth = 2,
}

local function EnsureDB()
    for key, value in pairs(DEFAULTS) do
        if ForeverFiveSecondRuleDB[key] == nil then
            ForeverFiveSecondRuleDB[key] = value
        end
    end
    return ForeverFiveSecondRuleDB
end

local db = EnsureDB()

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value) or false
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

-- Overlay frame that sits on top of the Blizzard Player Frame mana bar. It is created
-- parented to UIParent and re-anchored to the resource bar once the Player Frame exists.
local overlay = CreateFrame("Frame", "ForeverFiveSecondRuleOverlay", UIParent)
overlay:SetSize(124, 10)
overlay:Hide()

local fsrMarker = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
fsrMarker:SetColorTexture(1, 1, 1, 0.95)
fsrMarker:SetWidth(db.markerWidth)

local fsrText = overlay:CreateFontString(nil, "OVERLAY")
fsrText:SetFont("Fonts\\ARIALN.TTF", 10, "")
fsrText:SetTextColor(1, 1, 1, 1)
fsrText:SetShadowColor(0, 0, 0, 0.9)
fsrText:SetShadowOffset(1, -1)
fsrText:SetPoint("LEFT", overlay, "RIGHT", 3, 0)
fsrText:Hide()

local anchoredBar = nil

local function ApplyAnchor()
    local resourceBar = GetPlayerResourceBar()
    if not resourceBar then
        return false
    end

    if anchoredBar ~= resourceBar then
        overlay:SetParent(resourceBar)
        overlay:ClearAllPoints()
        overlay:SetAllPoints(resourceBar)
        anchoredBar = resourceBar
    end

    -- Keep above the bar's own text and spark.
    overlay:SetFrameStrata(resourceBar:GetFrameStrata())
    overlay:SetFrameLevel(resourceBar:GetFrameLevel() + 10)
    fsrMarker:SetHeight(overlay:GetHeight() + 4)
    return true
end

local fsrEndTime = 0
local pendingManaCasts = {}
local lastManaSpellID = nil
local fsrUpdateFrame = CreateFrame("Frame")
local fsrUpdateElapsed = 0

-- Only draw on the Player Frame bar while it is actually showing mana
-- (e.g. not while a Druid is in Cat/Bear Form and the bar shows energy/rage).
local function PlayerBarShowsMana()
    local powerType = UnitPowerType("player")
    if powerType == nil or IsSecretValue(powerType) then
        return false
    end
    return powerType == MANA_POWER_TYPE
end

local function ShouldShowOverlay()
    return db.enabled and PlayerBarShowsMana() and anchoredBar ~= nil
end

local function HideFiveSecondRuleVisual()
    overlay:Hide()
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

    if not ShouldShowOverlay() then
        HideFiveSecondRuleVisual()
        return
    end

    overlay:Show()

    local elapsed = FIVE_SECOND_RULE - remaining
    local progress = elapsed / FIVE_SECOND_RULE
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end

    local markerWidth = fsrMarker:GetWidth() or 2
    local usableWidth = math.max(0, overlay:GetWidth() - markerWidth)
    local x = (markerWidth / 2) + (progress * usableWidth)

    fsrMarker:ClearAllPoints()
    fsrMarker:SetPoint("CENTER", overlay, "LEFT", x, 0)
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

-- The timer keeps running while the overlay is hidden (e.g. while in a Druid form), so
-- the marker reappears at the correct position when the bar goes back to showing mana.
local function ResumeFiveSecondRuleVisual()
    if fsrEndTime > GetTime() and ShouldShowOverlay() then
        fsrUpdateElapsed = 0
        UpdateFiveSecondRuleVisual()
        fsrUpdateFrame:SetScript("OnUpdate", OnFiveSecondRuleUpdate)
    elseif fsrEndTime > 0 and fsrEndTime <= GetTime() then
        StopFiveSecondRule()
    else
        HideFiveSecondRuleVisual()
    end
end

local function StartFiveSecondRule()
    fsrEndTime = GetTime() + FIVE_SECOND_RULE
    ResumeFiveSecondRuleVisual()
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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")

eventFrame:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
    if event == "PLAYER_LOGIN" then
        -- SavedVariables are loaded after this file runs, so re-read them here.
        db = EnsureDB()
        fsrMarker:SetWidth(db.markerWidth)
        ApplyAnchor()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        wipe(pendingManaCasts)
        ApplyAnchor()
        ResumeFiveSecondRuleVisual()
        return
    end

    if event == "UPDATE_SHAPESHIFT_FORM" or (event == "UNIT_DISPLAYPOWER" and unit == "player") then
        ResumeFiveSecondRuleVisual()
        return
    end

    if unit ~= "player" then
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
        return
    end
end)

local function PrintDebugInfo()
    local version, build, _, tocVersion = GetBuildInfo()
    local powerID, powerToken = UnitPowerType("player")
    local remaining = math.max(0, fsrEndTime - GetTime())
    local resourceBar = GetPlayerResourceBar()

    print("|cff55ff55ForeverFiveSecondRule debug|r")
    print("Client:", tostring(version), "build", tostring(build), "TOC", tostring(tocVersion))
    print("Primary power:", tostring(powerID), tostring(powerToken), "shows mana:", tostring(PlayerBarShowsMana()))
    print("Attach target:", resourceBar and (resourceBar.GetDebugName and resourceBar:GetDebugName() or tostring(resourceBar)) or "not found")
    print("Enabled:", tostring(db.enabled), "timer text:", tostring(db.showTimerText))
    print("5SR remaining:", string.format("%.2f", remaining))
    if lastManaSpellID and not IsSecretValue(lastManaSpellID) then
        local spellName = nil
        if C_Spell and C_Spell.GetSpellName then
            local ok, name = pcall(C_Spell.GetSpellName, lastManaSpellID)
            if ok then spellName = name end
        end
        print("Last mana spell:", tostring(spellName or "?"), "ID", tostring(lastManaSpellID))
    end
end

local function PrintHelp()
    print("|cff55ff55ForeverFiveSecondRule|r commands:")
    print("  /ffsr on | off    - enable or disable the marker")
    print("  /ffsr text        - toggle the countdown text")
    print("  /ffsr width <1-6> - marker width in pixels")
    print("  /ffsr test        - start a 5-second test timer")
    print("  /ffsr debug       - print debug information")
end

SLASH_FOREVERFIVESECONDRULE1 = "/ffsr"
SlashCmdList["FOREVERFIVESECONDRULE"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")

    if cmd == "on" then
        db.enabled = true
        ResumeFiveSecondRuleVisual()
        print("|cff55ff55FFSR:|r enabled.")
    elseif cmd == "off" then
        db.enabled = false
        HideFiveSecondRuleVisual()
        print("|cff55ff55FFSR:|r disabled.")
    elseif cmd == "text" then
        db.showTimerText = not db.showTimerText
        ResumeFiveSecondRuleVisual()
        print("|cff55ff55FFSR:|r countdown text " .. (db.showTimerText and "shown." or "hidden."))
    elseif cmd == "width" then
        local width = tonumber(arg)
        if width and width >= 1 and width <= 6 then
            db.markerWidth = math.floor(width + 0.5)
            fsrMarker:SetWidth(db.markerWidth)
            print("|cff55ff55FFSR:|r marker width set to " .. db.markerWidth .. ".")
        else
            print("|cff55ff55FFSR:|r usage: /ffsr width <1-6>")
        end
    elseif cmd == "test" then
        ApplyAnchor()
        StartFiveSecondRule()
        if ShouldShowOverlay() then
            print("|cff55ff55FFSR:|r started a 5-second visual test timer.")
        else
            print("|cff55ff55FFSR:|r test timer started, but the Player Frame bar is not showing mana (or the addon is disabled).")
        end
    elseif cmd == "debug" then
        PrintDebugInfo()
    else
        PrintHelp()
    end
end
