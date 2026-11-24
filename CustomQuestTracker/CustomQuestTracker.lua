-- CustomQuestTracker: click the "Quests" header line of Blizzard's objective tracker to minimise
-- the whole tracker down to that line, and click it again to put every section back as it was.
--
-- Retail's tracker (ObjectiveTrackerFrame) is made of modules (Quests, Achievements, ...), each with
-- a Header and its own collapsed state (module:SetCollapsed / IsCollapsed). Minimising remembers
-- every module's state and collapses them all; restoring puts the remembered states back. Blizzard's
-- own minimise buttons keep working as before.
--
-- The tracker holds secure quest-item buttons, so changing its layout from addon code in combat
-- could get them blocked. A click in combat waits until combat ends.

local ADDON = ...
local PREFIX = "|cff66ccffCustomQuestTracker|r"
local addon = {}
CustomQuestTracker = addon

local db

local function Tracker() return ObjectiveTrackerFrame end

-- The tracker's modules, in order.
function addon.Modules()
    local list, seen = {}, {}
    local function Add(m)
        if type(m) == "table" and not seen[m] then seen[m] = true; list[#list + 1] = m end
    end
    local t = Tracker()
    if t and type(t.modules) == "table" then
        for _, m in ipairs(t.modules) do Add(m) end
    end
    Add(QuestObjectiveTracker)
    return list
end

function addon.Key(m)
    return (m.GetName and m:GetName()) or m.headerText or tostring(m)
end

function addon.IsCollapsed(m)
    if m.IsCollapsed then return m:IsCollapsed() and true or false end
    return m.collapsed and true or false
end

function addon.SetCollapsed(m, on)
    if addon.IsCollapsed(m) == on then return end
    if m.SetCollapsed then
        m:SetCollapsed(on)
    elseif m.Header and m.Header.MinimizeButton then
        m.Header.MinimizeButton:Click()
    end
end

-- The line to click: the Quests module's header, else the first module's.
function addon.QuestHeader()
    local q = QuestObjectiveTracker
    if q and q.Header then return q.Header end
    local first = addon.Modules()[1]
    return first and first.Header
end

function addon.Minimise()
    db.saved = {}
    for _, m in ipairs(addon.Modules()) do
        db.saved[addon.Key(m)] = addon.IsCollapsed(m)
        addon.SetCollapsed(m, true)
    end
    db.minimised = true
end

function addon.Restore()
    for _, m in ipairs(addon.Modules()) do
        local was = db.saved and db.saved[addon.Key(m)]
        addon.SetCollapsed(m, was and true or false)
    end
    db.minimised = false
end

function addon.Toggle()
    if InCombatLockdown() then
        addon.pending = not addon.pending
        print(PREFIX, addon.pending and "will toggle the tracker when combat ends." or "toggle cancelled.")
        return
    end
    if db.minimised then addon.Restore() else addon.Minimise() end
end

-- Hook the header (once). The tracker may build its modules after login, so this is retried.
function addon.Hook()
    local h = addon.QuestHeader()
    if not h or addon.hooked == h then return h ~= nil end
    addon.hooked = h
    if h.EnableMouse then h:EnableMouse(true) end
    h:HookScript("OnMouseUp", function(_, button)
        if button == nil or button == "LeftButton" then addon.Toggle() end
    end)
    -- Keep a minimised tracker minimised after a reload or login.
    if db.minimised and not InCombatLockdown() then
        for _, m in ipairs(addon.Modules()) do addon.SetCollapsed(m, true) end
    end
    return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            CustomQuestTrackerDB = CustomQuestTrackerDB or {}
            db = CustomQuestTrackerDB
        end
        if db and not addon.hooked then addon.Hook() end -- the tracker can load after us
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        db = CustomQuestTrackerDB or db
        if not addon.Hook() then
            C_Timer.After(2, addon.Hook)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if addon.pending then
            addon.pending = false
            addon.Toggle()
        end
    end
end)

SLASH_CUSTOMQUESTTRACKER1 = "/cqt"
SlashCmdList.CUSTOMQUESTTRACKER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "debug" then
        local t = Tracker()
        print(PREFIX, "tracker:", tostring(t ~= nil), "| tracker collapsed:",
            tostring(t and t.IsCollapsed and t:IsCollapsed()), "| minimised:", tostring(db and db.minimised),
            "| hooked:", tostring(addon.hooked ~= nil), "| in combat:", tostring(InCombatLockdown()))
        for i, m in ipairs(addon.Modules()) do
            local h = m.Header
            local text = h and h.Text and h.Text.GetText and h.Text:GetText()
            print("  " .. i .. ":", addon.Key(m), "| header:", tostring(text), "| collapsed:", tostring(addon.IsCollapsed(m)),
                "| SetCollapsed:", tostring(m.SetCollapsed ~= nil), "| shown:", tostring(m.IsShown and m:IsShown()),
                "| saved:", tostring(db and db.saved and db.saved[addon.Key(m)]))
        end
        return
    end
    if db then addon.Toggle() end
end
