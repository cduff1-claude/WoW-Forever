-- ForeverForge Bags Keep Uncategorized
-- In Manual sorting the bag window's Uncategorized section disappears when
-- it's empty, which reshuffles the section columns. This keeps it as an
-- empty title (still a drop target - UI/Sorter.lua's Decorate handles that),
-- the way ForeverForge Bags already keeps your own empty sections.
-- Written against ForeverForge Bags 0.21.0. Wraps
-- ForeverForgeBags.Window.CollectBySection; changes no ForeverForge files.

local ADDON = ...
local PREFIX = "|cff8fa5b2ForeverForge Bags Keep Uncategorized|r: "
local TESTED_VERSION = "0.21.0"

local db = { enabled = true }
local origCollect
local lastAdded = false

local function Print(msg) print(PREFIX .. msg) end
local function FB() return _G.ForeverForgeBags end

local function uncatName()
    local L = FB() and FB().L
    return L and L.UNCATEGORIZED or "Uncategorized"
end

local function wanted(win)
    local fb = FB()
    return db.enabled and fb and fb.Filters and fb.Filters.IsManual and fb.Filters:IsManual()
        and not (win.IsBank and win:IsBank())
end

local function collectBySection(self, ...)
    local blocks, freeCount = origCollect(self, ...)
    lastAdded = false
    if type(blocks) ~= "table" or not wanted(self) then return blocks, freeCount end
    local name = uncatName()
    local byName, names = {}, {}
    for _, b in ipairs(blocks) do
        if b.name == name then return blocks, freeCount end
        byName[b.name] = b
        names[#names + 1] = b.name
    end
    byName[name] = { name = name, kind = "items", entries = {}, groups = {}, empty = true }
    names[#names + 1] = name
    -- Same order the window would give it with items in it.
    local Filters = FB().Filters
    local ok, ordered = pcall(Filters.OrderSections, Filters, names)
    local out = {}
    if ok and type(ordered) == "table" and #ordered == #names then
        for i, n in ipairs(ordered) do out[i] = byName[n] end
    else
        out = blocks
        table.insert(out, 1, byName[name])
    end
    lastAdded = true
    return out, freeCount
end

local installed = false
local function install()
    local W = FB() and FB().Window
    if installed or not (W and type(W.CollectBySection) == "function") then return end
    origCollect = W.CollectBySection
    W.CollectBySection = collectBySection
    installed = true
end

local function redraw()
    local bags = FB() and FB().Container
    if bags and bags.Rebuild then pcall(bags.Rebuild, bags) end
end

install()

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        ForeverForge_Bags_KeepUncategorizedDB = ForeverForge_Bags_KeepUncategorizedDB or {}
        db = ForeverForge_Bags_KeepUncategorizedDB
        if db.enabled == nil then db.enabled = true end
    elseif event == "PLAYER_LOGIN" then
        install()
    end
end)

local function version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    return (get and get("ForeverForge_Bags", "Version")) or (FB() and FB().VERSION) or "?"
end

SLASH_FOREVERFORGEBAGSKEEPUNCAT1 = "/ffku"
SlashCmdList.FOREVERFORGEBAGSKEEPUNCAT = function(msg)
    local cmd = strtrim(string.lower(msg or ""))
    if cmd == "on" or cmd == "off" then
        db.enabled = (cmd == "on")
        Print("keep an empty Uncategorized section: " .. (db.enabled and "on" or "off"))
        redraw()
    elseif cmd == "debug" then
        local fb = FB()
        local v = version()
        Print("debug")
        print(("  ForeverForge Bags %s%s"):format(tostring(v),
            v == TESTED_VERSION and "" or (" |cffffaa00(written against " .. TESTED_VERSION .. ")|r")))
        print("  hooked: " .. tostring(installed) .. ", still ours: "
            .. tostring(fb and fb.Window and fb.Window.CollectBySection == collectBySection))
        print("  enabled: " .. tostring(db.enabled) .. ", Manual mode: "
            .. tostring(fb and fb.Filters and fb.Filters:IsManual()) .. ", section name: \"" .. uncatName() .. "\"")
        print("  last redraw added an empty Uncategorized: " .. tostring(lastAdded))
    else
        Print("/ffku on|off - keep an empty Uncategorized section in Manual mode (now "
            .. (db.enabled and "on" or "off") .. ")")
        Print("/ffku debug - hook status and what the last redraw did")
    end
end
