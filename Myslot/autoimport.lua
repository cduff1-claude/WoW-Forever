local _, MySlot = ...
local L = MySlot.L
local RegEvent = MySlot.regevent

-- Level 1 default profiles (WoW Forever addition).
--
-- MyslotExports.levelOneDefaults[CLASS_TOKEN] = profile name (account-wide).
-- MyslotSettings.autoImportDone = true once a character has had its default
-- imported, or was past level 1 when first seen (per character).

-- Seconds to wait after login before importing, so addons that create macros
-- at login have done so and the spellbook is loaded.
local AUTO_IMPORT_DELAY = 5

local function Exports()
    MyslotExports = MyslotExports or {}
    MyslotExports["exports"] = MyslotExports["exports"] or {}
    MyslotExports["levelOneDefaults"] = MyslotExports["levelOneDefaults"] or {}
    return MyslotExports
end

local function MyClass()
    return select(2, UnitClass("player"))
end

local function ClassName(token)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token or "?"
end

function MySlot:FindProfileByName(name)
    if not name or name == "" then
        return nil
    end
    for _, profile in ipairs(Exports()["exports"]) do
        if profile.name == name then
            return profile
        end
    end
    return nil
end

function MySlot:GetLevelOneDefault(classToken)
    return Exports()["levelOneDefaults"][classToken or MyClass()]
end

function MySlot:SetLevelOneDefault(name, classToken)
    classToken = classToken or MyClass()
    Exports()["levelOneDefaults"][classToken] = name
    if name then
        self:Print(L["Level 1 default for %s set to '%s'"]:format(ClassName(classToken), name))
    else
        self:Print(L["Level 1 default for %s cleared"]:format(ClassName(classToken)))
    end
end

-- The same options as "/myslot load": everything imported, nothing ignored.
local function FullImportOptions()
    local ignoreActionBars = {}
    for i = 1, 15 do
        ignoreActionBars[i] = false
    end
    return {
        ignoreActionBars = ignoreActionBars,
        ignoreBinding = false,
        ignoreMacros = { ["ACCOUNT"] = false, ["CHARACTOR"] = false },
        ignorePetActionBar = false,
        ignoreCooldownManager = false,
        ignoreClickBindings = false,
    }
end

local importing = false

-- Import this class's level 1 default profile. Returns false if it couldn't start.
function MySlot:ImportLevelOneDefault()
    if importing then
        return false
    end

    local name = self:GetLevelOneDefault()
    if not name then
        self:Print(L["No level 1 default set for %s. Use /myslot default <profile name>"]:format(ClassName(MyClass())))
        return false
    end

    local profile = self:FindProfileByName(name)
    if not profile or not profile.value or profile.value == "" then
        self:Print(L["Level 1 default profile '%s' not found or empty"]:format(name))
        return false
    end

    if InCombatLockdown() then
        self:Print(L["Import is not allowed when you are in combat"])
        return false
    end

    local msg = self:Import(profile.value, { force = false })
    if not msg then
        return false
    end

    local opt = FullImportOptions()
    importing = true
    self:Print(L["Importing level 1 default profile '%s'"]:format(name))
    self:RunAsync(function()
        MySlot:RecoverData(msg, {
            actionOpt = opt,
            clearOpt = opt,
        })
    end, nil, function(ok)
        importing = false
        if ok then
            MyslotSettings.autoImportDone = true
        end
    end)
    return true
end

local waitingForCombat = false

local function TryAutoImport()
    MyslotSettings = MyslotSettings or {}
    if MyslotSettings.autoImportDone or importing then
        return
    end

    -- Only brand-new characters. A character seen past level 1 never gets it.
    if UnitLevel("player") ~= 1 then
        MyslotSettings.autoImportDone = true
        return
    end

    if not MySlot:GetLevelOneDefault() then
        return
    end

    if InCombatLockdown() then
        waitingForCombat = true
        return
    end

    MySlot:ImportLevelOneDefault()
end

RegEvent("PLAYER_LOGIN", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(AUTO_IMPORT_DELAY, TryAutoImport)
    else
        TryAutoImport()
    end
end)

RegEvent("PLAYER_REGEN_ENABLED", function()
    if waitingForCombat then
        waitingForCombat = false
        TryAutoImport()
    end
end)

-- "/myslot default ..." handler. `rest` is everything after "default".
function MySlot:LevelOneDefaultCommand(rest)
    rest = strtrim(rest or "")
    local class = MyClass()

    if rest == "" then
        MyslotSettings = MyslotSettings or {}
        local name = self:GetLevelOneDefault()
        local profile = self:FindProfileByName(name)
        self:Print(("class=%s level=%s autoImportDone=%s inCombat=%s"):format(
            tostring(class), tostring(UnitLevel("player")),
            tostring(MyslotSettings.autoImportDone and true or false), tostring(InCombatLockdown() and true or false)))
        self:Print(("default=%s found=%s"):format(
            name and ("'" .. name .. "'") or "none", tostring(profile ~= nil)))
        for token, n in pairs(Exports()["levelOneDefaults"]) do
            self:Print(("  %s: '%s'"):format(ClassName(token), n))
        end
        return
    end

    if rest == "clear" then
        self:SetLevelOneDefault(nil)
        return
    end

    if rest == "now" then
        self:ImportLevelOneDefault()
        return
    end

    if rest == "skip" then
        MyslotSettings = MyslotSettings or {}
        MyslotSettings.autoImportDone = true
        self:Print(L["This character will not auto-import a level 1 default"])
        return
    end

    if rest == "reset" then
        MyslotSettings = MyslotSettings or {}
        MyslotSettings.autoImportDone = nil
        self:Print(L["This character will auto-import its level 1 default at next login (if level 1)"])
        return
    end

    if not self:FindProfileByName(rest) then
        self:Print(L["No profile found with name " .. rest])
        return
    end
    self:SetLevelOneDefault(rest)
end
