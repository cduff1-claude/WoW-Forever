-- deselectOnClick is the inverse of the "Sticky Targeting" option:
-- "0" = sticky (clicking empty ground keeps your target), "1" = clicking empty ground clears it.
local CVAR = "deselectOnClick"

local debug = false
local lastEvent, lastResult = "none", "none"

local function Print(msg)
    print("|cff33ff99StickyTarget|r: " .. msg)
end

local function SetSticky(sticky, event)
    local value = sticky and "0" or "1"
    local before = C_CVar.GetCVar(CVAR)
    local ok, err, method = true, nil, "unchanged"
    if before ~= value then
        -- On the WoW Forever client C_CVar.SetCVar is silently ignored for this CVar,
        -- but the console command ("/console deselectOnClick 0") works, so fall back to it.
        method = "SetCVar"
        ok, err = pcall(C_CVar.SetCVar, CVAR, value)
        if C_CVar.GetCVar(CVAR) ~= value and ConsoleExec then
            method = "ConsoleExec"
            ok, err = pcall(ConsoleExec, CVAR .. " " .. value)
        end
    end
    local after = C_CVar.GetCVar(CVAR)

    lastEvent = event
    lastResult = string.format("wanted %s, before %s, after %s, via %s, lockdown %s%s",
        value, tostring(before), tostring(after), method, tostring(InCombatLockdown()),
        ok and "" or (", error: " .. tostring(err)))

    if debug or after ~= value then
        Print(event .. ": " .. lastResult)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Fires just before combat lockdown starts, so the CVar can still be changed here.
        SetSticky(true, event)
    elseif event == "PLAYER_REGEN_ENABLED" then
        SetSticky(false, event)
    elseif not InCombatLockdown() then
        -- Login/reload/zoning: make sure we don't stay stuck in sticky mode out of combat.
        SetSticky(UnitAffectingCombat("player"), event)
    end
end)

SLASH_STICKYTARGET1 = "/sticky"
SLASH_STICKYTARGET2 = "/stickytarget"
SlashCmdList.STICKYTARGET = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "debug" then
        debug = not debug
        Print("debug " .. (debug and "on" or "off"))
    else
        Print(string.format("loaded. %s = %s, in combat: %s",
            CVAR, tostring(C_CVar.GetCVar(CVAR)), tostring(UnitAffectingCombat("player"))))
        Print("last event: " .. lastEvent .. " (" .. lastResult .. ")")
    end
end

Print("loaded (type /sticky for status, /sticky debug to log every change)")
