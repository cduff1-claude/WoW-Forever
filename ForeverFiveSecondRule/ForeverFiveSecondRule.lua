local MANA_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local FIVE_SECOND_RULE = 5.0
local FSR_UPDATE_INTERVAL = 0.05

ForeverFiveSecondRuleDB = ForeverFiveSecondRuleDB or {}

local DEFAULTS = {
    enabled = true,
    showTimerText = true,
    markerWidth = 2,
    playerFrame = true,       -- marker on the Player Frame mana bar
    personalResource = true,  -- marker on the Personal Resource Display mana bar
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

-- Personal Resource Display (Midnight-style PersonalResourceDisplayFrame): PowerBar shows
-- the primary power; for a druid in Cat/Bear the AlternatePowerBar is the mana bar.
local isDruid = false

local function GetPersonalResourceFrame()
    local frame = _G.PersonalResourceDisplayFrame
    if frame and type(frame) == "table" and frame.GetObjectType then
        return frame
    end
end

-- Overlay frames on the Blizzard mana bars, created lazily and keyed by bar.
local targets = {}

local function GetTarget(bar)
    local target = targets[bar]
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

    target = { bar = bar, frame = frame, marker = marker, text = text }
    targets[bar] = target
    return target
end

local function HideAllTargets()
    for _, target in pairs(targets) do
        target.frame:Hide()
    end
end

local fsrEndTime = 0
local pendingManaCasts = {}
local lastManaSpellID = nil
local fsrUpdateFrame = CreateFrame("Frame")
local fsrUpdateElapsed = 0

-- nil when the power type can't be read.
local function PrimaryPowerIsMana()
    local powerType = UnitPowerType("player")
    if powerType == nil or IsSecretValue(powerType) then
        return nil
    end
    return powerType == MANA_POWER_TYPE
end

local function PlayerBarShowsMana()
    return PrimaryPowerIsMana() == true
end

-- The Blizzard bars currently showing mana that should carry the marker.
local function GetWantedBars()
    local bars = {}
    if not db.enabled then
        return bars
    end

    local primaryIsMana = PrimaryPowerIsMana()
    if primaryIsMana == nil then
        return bars
    end

    if db.playerFrame and primaryIsMana then
        local bar = GetPlayerResourceBar()
        if bar then
            bars[#bars + 1] = bar
        end
    end

    if db.personalResource then
        local prd = GetPersonalResourceFrame()
        if prd then
            local bar
            if primaryIsMana then
                bar = prd.PowerBar
            elseif isDruid then
                bar = prd.AlternatePowerBar
            end
            if bar and bar.GetObjectType then
                bars[#bars + 1] = bar
            end
        end
    end

    return bars
end

local function ShouldShowOverlay()
    return #GetWantedBars() > 0
end

local function HideFiveSecondRuleVisual()
    HideAllTargets()
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

    -- No bar to draw on right now (e.g. mid-shift): hide the markers but keep ticking, so
    -- they come back as soon as a mana bar is available again.
    local wanted = GetWantedBars()
    if #wanted == 0 then
        HideAllTargets()
        return
    end

    local elapsed = FIVE_SECOND_RULE - remaining
    local progress = elapsed / FIVE_SECOND_RULE
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end

    local shown = {}
    for _, bar in ipairs(wanted) do
        local target = GetTarget(bar)
        shown[target] = true

        -- Keep above the bar's own text and spark.
        target.frame:SetFrameStrata(bar:GetFrameStrata())
        target.frame:SetFrameLevel(bar:GetFrameLevel() + 10)
        target.frame:Show()

        local markerWidth = db.markerWidth
        target.marker:SetWidth(markerWidth)
        target.marker:SetHeight(target.frame:GetHeight() + 4)
        local usableWidth = math.max(0, target.frame:GetWidth() - markerWidth)
        local x = (markerWidth / 2) + (progress * usableWidth)
        target.marker:ClearAllPoints()
        target.marker:SetPoint("CENTER", target.frame, "LEFT", x, 0)

        if db.showTimerText then
            target.text:SetText(string.format("%.1f", remaining))
            target.text:Show()
        else
            target.text:Hide()
        end
    end

    for _, target in pairs(targets) do
        if not shown[target] then
            target.frame:Hide()
        end
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
    if fsrEndTime > GetTime() and db.enabled then
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
        local _, classFile = UnitClass("player")
        isDruid = (classFile == "DRUID")
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        wipe(pendingManaCasts)
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
    local prd = GetPersonalResourceFrame()

    print("|cff55ff55ForeverFiveSecondRule debug|r")
    print("Client:", tostring(version), "build", tostring(build), "TOC", tostring(tocVersion))
    print("Primary power:", tostring(powerID), tostring(powerToken), "shows mana:", tostring(PlayerBarShowsMana()))
    print("Player Frame bar:", resourceBar and "found" or "not found", "| enabled:", tostring(db.playerFrame))
    print("Personal Resource Display:", prd and "found" or "not found", "| shown:", prd and tostring(prd:IsShown()) or "-",
        "| enabled:", tostring(db.personalResource))
    print("Bars that would get the marker now:", tostring(#GetWantedBars()))
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
    print("  /ffsr player      - toggle the marker on the Player Frame mana bar")
    print("  /ffsr prd         - toggle the marker on the Personal Resource Display")
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
            ResumeFiveSecondRuleVisual()
            print("|cff55ff55FFSR:|r marker width set to " .. db.markerWidth .. ".")
        else
            print("|cff55ff55FFSR:|r usage: /ffsr width <1-6>")
        end
    elseif cmd == "player" or cmd == "prd" then
        local key = cmd == "player" and "playerFrame" or "personalResource"
        local label = cmd == "player" and "Player Frame" or "Personal Resource Display"
        db[key] = not db[key]
        ResumeFiveSecondRuleVisual()
        print("|cff55ff55FFSR:|r " .. label .. " marker " .. (db[key] and "on." or "off."))
    elseif cmd == "test" then
        StartFiveSecondRule()
        if ShouldShowOverlay() then
            print("|cff55ff55FFSR:|r started a 5-second visual test timer.")
        else
            print("|cff55ff55FFSR:|r test timer started, but no enabled bar is showing mana (or the addon is disabled).")
        end
    elseif cmd == "debug" then
        PrintDebugInfo()
    else
        PrintHelp()
    end
end
