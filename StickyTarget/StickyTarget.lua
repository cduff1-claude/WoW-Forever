-- deselectOnClick is the inverse of the "Sticky Targeting" option:
-- "0" = sticky (clicking empty ground keeps your target), "1" = clicking empty ground clears it.
local CVAR = "deselectOnClick"

local function SetSticky(sticky)
    local value = sticky and "0" or "1"
    if C_CVar.GetCVar(CVAR) ~= value then
        C_CVar.SetCVar(CVAR, value)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Fires just before combat lockdown starts, so the CVar can still be changed here.
        SetSticky(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        SetSticky(false)
    elseif not InCombatLockdown() then
        -- Login/reload/zoning: make sure we don't stay stuck in sticky mode out of combat.
        SetSticky(UnitAffectingCombat("player"))
    end
end)
