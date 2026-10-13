-- ForeverForge Bags Destroy Plus
-- Changes ForeverForge Bags' Destroy mode without touching its files:
--   * Gray items, and anything headed for a vendor (filed in Junk, or in a
--     section automated to sell at vendors), are valued at vendor price only.
--   * The cheapest-first view is split into three sections, stacked in a
--     single column whatever the bags' section-column setting:
--       Junk      - grays, Junk, vendor-automated sections
--       Other     - everything else
--       Protected - sections set to "Protected" (Automate dropdown), your
--                   "Core" section, and anything with no sell value
--     each cheapest first. Junk and Other show their cheapest stack's value
--     in the title; Protected's icons are desaturated.
--   * Protected items always ask before they're destroyed, whatever the
--     rarity setting says.
--   * Quest items are left out of the view (unless filed in Junk, a vendor
--     section or Core).
-- Written against ForeverForge Bags 0.21.0. It replaces
-- ForeverForgeBags.Window.CollectByValue and wraps
-- ForeverForgeBags.Destroy.ItemValue / AsksFirstFor and
-- ForeverForgeBags.Window.Rebuild, and adds "Protected" to
-- ForeverForgeBags.Automation.ACTIONS.

local ADDON = ...
local PREFIX = "|cffe04848ForeverForge Bags Destroy Plus|r: "
local TESTED_VERSION = "0.21.0"

local DEFAULTS = {
    grayVendor = true, sections = true, desaturate = true, singleColumn = true, protectedAsks = true,
    quest = "hide",            -- "hide" or "other"
    coreSection = "Core",
}

local db = {}
for k, v in pairs(DEFAULTS) do db[k] = v end

local origItemValue, origAsksFirstFor, origCollect, origRebuild, origGetStore
local installed = { value = false, asks = false, sections = false, desat = false, rebuild = false, column = false,
    action = false }

-- The Automate dropdown's new choice (Bags settings » Sections » your section).
local PROTECTED = "protected"
local PROTECTED_ACTION = { key = PROTECTED, name = "Protected (Destroy mode)" }

-- Section titles in the Destroy view.
local JUNK_TITLE = "Junk"
local MID_TITLE = "Other"
local LAST_TITLE = "Protected"

local function Print(msg) print(PREFIX .. msg) end

local function FB() return _G.ForeverForgeBags end

------------------------------------------------------------- Classification

local function lower(s) return type(s) == "string" and string.lower(s) or nil end

--- The section an item is filed in by hand (one of yours, or Junk / Quest
--- items), and that section's automation ("vendor", "bank", ...).
local function filedIn(d)
    local Custom = FB() and FB().Custom
    if not Custom then return nil, nil end
    local ok, automate, name = pcall(Custom.AutomateFor, Custom, d)
    if not ok then return nil, nil end
    return name, automate
end

local function junkName()
    local L = FB() and FB().L
    return L and L.JUNK or "Junk"
end

local function questName()
    local L = FB() and FB().L
    return L and L.QUEST or "Quest"
end

local function isQuest(d, filed)
    return lower(d.class) == "quest" or (filed ~= nil and filed == questName())
end

--- Headed for a vendor: gray, filed in Junk, or in a vendor-automated section.
--- Returns the reason as a second value.
local function isVendorJunk(d, filed, automate)
    if filed == nil and automate == nil then filed, automate = filedIn(d) end
    if automate == "vendor" then return true, "vendor section (" .. tostring(filed) .. ")" end
    if filed ~= nil and filed == junkName() then return true, "filed in Junk" end
    if d.quality == 0 then return true, "gray" end
    return false
end

local function isCore(filed)
    local want = lower(db.coreSection)
    return want ~= nil and want ~= "" and lower(filed) == want
end

--- In a section set to Protected, or your Core section. Returns why.
local function isProtectedSection(filed, automate)
    if automate == PROTECTED then return true, "Protected section (" .. tostring(filed) .. ")" end
    if isCore(filed) then return true, "in " .. tostring(filed) end
    return false
end

--- "junk", "mid", "last" or "hide", and why.
local function groupOf(d, value)
    local filed, automate = filedIn(d)
    local protected, why = isProtectedSection(filed, automate)
    if protected then return "last", why end
    -- Filed for selling beats the quest check: you said so by hand.
    if automate == "vendor" or (filed ~= nil and filed == junkName()) then
        return "junk", select(2, isVendorJunk(d, filed, automate))
    end
    if isQuest(d, filed) then
        if db.quest == "other" then return "mid", "quest item" end
        return "hide", "quest item"
    end
    if d.quality == 0 then return "junk", "gray" end
    if value <= 0 then return "last", "no sell value" end
    return "mid", nil
end

------------------------------------------------------------------- Value

local function itemValue(d, ...)
    if db.grayVendor and type(d) == "table" and d.itemId and isVendorJunk(d) then
        local vendor = tonumber(d.vendorPrice) or 0
        return vendor, vendor > 0 and "vendor" or nil
    end
    return origItemValue(d, ...)
end

--- Protected items always ask first; everything else follows the rarity
--- setting (and no sell value, which asks anyway).
local function asksFirstFor(d, ...)
    if db.protectedAsks and type(d) == "table" and d.itemId and isProtectedSection(filedIn(d)) then
        return true
    end
    return origAsksFirstFor(d, ...)
end

------------------------------------------------------------- Sections

-- slotData -> itemId, for the Protected section of the last view drawn.
local lastSlots = {}
-- Section title -> the value of its first (cheapest) stack.
local firstValue = {}

local function byValue(a, b)
    if a.worthless ~= b.worthless then return b.worthless end
    if a.value ~= b.value then return a.value < b.value end
    local an, bn = a.slotData.name or "", b.slotData.name or ""
    if an ~= bn then return an < bn end
    if a.slotData.bag ~= b.slotData.bag then return a.slotData.bag < b.slotData.bag end
    return a.slotData.slot < b.slotData.slot
end

local function collectByValue(self, ...)
    wipe(lastSlots)
    wipe(firstValue)
    if not db.sections then return origCollect(self, ...) end
    local fb = FB()
    local D, B = fb.Destroy, fb.Bags
    D.ResetValues()
    local groups = { junk = {}, mid = {}, last = {}, hide = {} }
    local freeCount = 0
    for _, bag in ipairs(self:Bags()) do
        local content = B.content[bag]
        if content and content.size > 0 then
            for slot = 1, content.size do
                local d = content[slot]
                if d and d.link then
                    local value = D.StackValue(d)
                    local g = groupOf(d, value)
                    local list = groups[g]
                    list[#list + 1] = { slotData = d, total = d.count or 0, stacks = 1,
                        value = value, worthless = value <= 0 }
                    if g == "last" then lastSlots[d] = d.itemId end
                elseif d and B.CountsAsFree(bag) then
                    freeCount = freeCount + 1
                end
            end
        end
    end
    local blocks = {}
    for _, g in ipairs({ { "junk", JUNK_TITLE }, { "mid", MID_TITLE }, { "last", LAST_TITLE } }) do
        local list = groups[g[1]]
        if #list > 0 then
            table.sort(list, byValue)
            blocks[#blocks + 1] = { name = g[2], kind = "destroy", entries = list }
            firstValue[g[2]] = list[1].value
        end
    end
    -- Bags with nothing to show still show one (empty) section, as before.
    if #blocks == 0 then
        blocks[1] = { name = MID_TITLE, kind = "destroy", entries = {} }
    end
    return blocks, freeCount
end

---------------------------------------------------------- Desaturating

local function inDestroyView()
    local fb = FB()
    local bags = fb and fb.Container
    return bags and bags.destroyViewShown and fb.Destroy and fb.Destroy.mode and true or false
end

local function desaturateIfLast(_, button)
    if not (db.sections and db.desaturate) then return end
    local d = button and button.fgSlotData
    if not (d and lastSlots[d] ~= nil and lastSlots[d] == d.itemId) then return end
    if not inDestroyView() then return end
    local icon = button.icon
    if icon and icon.SetDesaturated then icon:SetDesaturated(true) end
end

---------------------------------------------------------- Single column

-- While a Destroy view is being drawn, the bags' "bags" settings store
-- answers 1 for layout.sectionColumns, so the three sections stack.
local oneColumn = false
local proxies = setmetatable({}, { __mode = "k" })

local function proxyFor(store)
    local p = proxies[store]
    if p then return p end
    p = setmetatable({
        Get = function(_, key, ...)
            if oneColumn and key == "layout.sectionColumns" then return 1 end
            return store:Get(key, ...)
        end,
    }, {
        __index = function(_, k)
            local v = store[k]
            if type(v) == "function" then
                return function(self, ...)
                    if self == p then return v(store, ...) end
                    return v(self, ...)
                end
            end
            return v
        end,
        __newindex = function(_, k, v) store[k] = v end,
    })
    proxies[store] = p
    return p
end

local function getStore(config, key, ...)
    local store = origGetStore(config, key, ...)
    if oneColumn and key == "bags" and type(store) == "table" and type(store.Get) == "function" then
        return proxyFor(store)
    end
    return store
end

---------------------------------------------------------- Section titles

local TIPS = {
    [JUNK_TITLE] = { "Destroy mode - junk",
        "Gray items, items you filed in Junk, and items in a section set to sell at vendors. Cheapest first, valued at vendor price only (they're getting vendored anyway). The title shows the first item's value." },
    [MID_TITLE] = { "Destroy mode - other",
        "Everything else, cheapest first: left to right, then down. Worth is the vendor price, or the auction house price after fees when that's more. The title shows the first item's value." },
    [LAST_TITLE] = { "Destroy mode - protected",
        "Sections set to Protected (Automate, on the section's settings card), your Core section, and anything with no sell value, cheapest first. Everything here asks before it is destroyed." },
}

local function decorate(self)
    if not (db.sections and self.destroyViewShown and self.sections) then return end
    local fb = FB()
    local Section = fb.Section
    local money = fb.Money or GetMoneyString or tostring
    for _, s in ipairs(self.sections) do
        local tip = TIPS[s.name]
        if tip then
            if Section and Section.SetHeaderTooltip then
                pcall(Section.SetHeaderTooltip, Section, s, "click one to destroy it", tip[1], tip[2])
            end
            if s.countText then
                local v = firstValue[s.name]
                if s.name ~= LAST_TITLE and v and v > 0 then
                    s.countText:SetText(money(v))
                    s.countText:SetTextColor(0.9, 0.9, 0.9)
                else
                    s.countText:SetText("")
                end
            end
            if Section and Section.FitHint then pcall(Section.FitHint, s) end
        end
    end
end

local function rebuild(self, ...)
    oneColumn = db.sections and db.singleColumn and self.DestroyView and self:DestroyView() and true or false
    local ok, err = pcall(origRebuild, self, ...)
    oneColumn = false
    if not ok then error(err, 0) end
    decorate(self)
end

----------------------------------------------------------------- Install

local function install()
    local fb = FB()
    if not fb then return end
    local D, W, IB = fb.Destroy, fb.Window, fb.ItemButton
    if not installed.value and D and type(D.ItemValue) == "function" then
        origItemValue = D.ItemValue
        D.ItemValue = itemValue
        installed.value = true
    end
    if not installed.asks and D and type(D.AsksFirstFor) == "function" then
        origAsksFirstFor = D.AsksFirstFor
        D.AsksFirstFor = asksFirstFor
        installed.asks = true
    end
    local AUT = fb.Automation
    if not installed.action and AUT and type(AUT.ACTIONS) == "table" then
        local have = false
        for _, a in ipairs(AUT.ACTIONS) do
            if a.key == PROTECTED then have = true end
        end
        if not have then table.insert(AUT.ACTIONS, PROTECTED_ACTION) end
        installed.action = true
    end
    if not installed.sections and W and type(W.CollectByValue) == "function" and D
        and D.ResetValues and D.StackValue and fb.Bags and fb.Bags.content and fb.Bags.CountsAsFree then
        origCollect = W.CollectByValue
        W.CollectByValue = collectByValue
        installed.sections = true
    end
    if not installed.desat and IB and type(IB.RefreshState) == "function" then
        hooksecurefunc(IB, "RefreshState", desaturateIfLast)
        installed.desat = true
    end
    if not installed.rebuild and W and type(W.Rebuild) == "function" then
        origRebuild = W.Rebuild
        W.Rebuild = rebuild
        installed.rebuild = true
    end
    local Config = _G.ForeverForge and _G.ForeverForge.Config
    if not installed.column and Config and type(Config.GetStore) == "function" then
        origGetStore = Config.GetStore
        Config.GetStore = getStore
        installed.column = true
    end
end

local function redraw()
    local fb = FB()
    if fb and fb.Destroy and fb.Destroy.ResetValues then pcall(fb.Destroy.ResetValues) end
    local bags = fb and fb.Container
    if bags and bags.Rebuild then pcall(bags.Rebuild, bags) end
end

install()

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        ForeverForge_Bags_DestroyPlusDB = ForeverForge_Bags_DestroyPlusDB or {}
        db = ForeverForge_Bags_DestroyPlusDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
    elseif event == "PLAYER_LOGIN" then
        install()
    end
end)

------------------------------------------------------------------- Debug

local function version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local v = get and get("ForeverForge_Bags", "Version")
    return v or (FB() and FB().VERSION) or "?"
end

local function onOff(v) return v and "on" or "off" end

local function debug()
    local fb = FB()
    Print("debug")
    local v = version()
    print(("  ForeverForge Bags %s%s"):format(tostring(v),
        v == TESTED_VERSION and "" or (" |cffffaa00(written against " .. TESTED_VERSION .. ")|r")))
    print(("  hooks: value %s, asks %s, dropdown %s, sections %s, desaturate %s, rebuild %s, single column %s"):format(
        tostring(installed.value), tostring(installed.asks), tostring(installed.action), tostring(installed.sections),
        tostring(installed.desat), tostring(installed.rebuild), tostring(installed.column)))
    local Config = _G.ForeverForge and _G.ForeverForge.Config
    print(("  still ours: ItemValue %s, AsksFirstFor %s, CollectByValue %s, Rebuild %s, GetStore %s"):format(
        tostring(fb and fb.Destroy and fb.Destroy.ItemValue == itemValue),
        tostring(fb and fb.Destroy and fb.Destroy.AsksFirstFor == asksFirstFor),
        tostring(fb and fb.Window and fb.Window.CollectByValue == collectByValue),
        tostring(fb and fb.Window and fb.Window.Rebuild == rebuild),
        tostring(Config and Config.GetStore == getStore)))
    print(("  settings: vendor price %s, sections %s, single column %s, desaturate %s, protected asks %s, quest items %s, core section \"%s\""):format(
        onOff(db.grayVendor), onOff(db.sections), onOff(db.singleColumn), onOff(db.desaturate), onOff(db.protectedAsks),
        tostring(db.quest), tostring(db.coreSection)))
    if not (fb and fb.Destroy and fb.Bags and fb.Container and origItemValue) then return end
    local D, B = fb.Destroy, fb.Bags
    local money = fb.Money or GetMoneyString or tostring
    D.ResetValues()
    local mid = 0
    for _, bag in ipairs(fb.Container:Bags()) do
        local content = B.content[bag]
        for slot = 1, (content and content.size or 0) do
            local d = content[slot]
            if d and d.link then
                local value, how = D.StackValue(d)
                local g, why = groupOf(d, value)
                if g == "mid" and not why then
                    mid = mid + 1
                else
                    local filed, automate = filedIn(d)
                    local orig = origItemValue(d) * math.max(1, tonumber(d.count) or 1)
                    local asks = D.AsksFirstFor and D.AsksFirstFor(d)
                    print(("  [%s] %s x%d: %s (%s) | original %s | q%s filed=%s automate=%s class=%s asks=%s"):format(
                        g, d.link, d.count or 1, money(value), tostring(how), money(orig), tostring(d.quality),
                        tostring(filed), tostring(automate), tostring(d.class), tostring(asks))
                        .. (why and (" - " .. why) or ""))
                end
            end
        end
    end
    print("  plus " .. mid .. " other stacks")
    D.ResetValues()
end

------------------------------------------------------------------- Slash

local function toggle(key, arg, label)
    if arg == "on" then db[key] = true elseif arg == "off" then db[key] = false else db[key] = not db[key] end
    Print(label .. ": " .. onOff(db[key]))
    redraw()
end

SLASH_FOREVERFORGEBAGSDESTROYPLUS1 = "/ffdp"
SlashCmdList.FOREVERFORGEBAGSDESTROYPLUS = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = lower(cmd) or ""
    local arg = lower(rest)
    if cmd == "vendor" then
        toggle("grayVendor", arg, "gray / Junk / vendor-section items valued at vendor price only")
    elseif cmd == "sections" then
        toggle("sections", arg, "Junk / Other / Protected sections")
    elseif cmd == "column" then
        toggle("singleColumn", arg, "Destroy view in a single column")
    elseif cmd == "ask" then
        toggle("protectedAsks", arg, "Protected items always ask before they're destroyed")
    elseif cmd == "desat" then
        toggle("desaturate", arg, "desaturate Protected icons")
    elseif cmd == "quest" then
        if arg == "hide" or arg == "other" then db.quest = arg end
        Print("quest items (not filed in Junk, a vendor section or Core): "
            .. (db.quest == "other" and "shown in Other" or "hidden"))
        redraw()
    elseif cmd == "core" then
        if arg == "none" then db.coreSection = "" elseif rest ~= "" then db.coreSection = rest end
        Print("section that always goes in Protected: \"" .. tostring(db.coreSection) .. "\"")
        redraw()
    elseif cmd == "debug" then
        debug()
    else
        Print("commands:")
        print("  /ffdp vendor [on|off] - vendor price only for gray / Junk / vendor-section items")
        print("  /ffdp sections [on|off] - split Destroy mode into Junk / Other / Protected")
        print("  /ffdp column [on|off] - stack the Destroy view in a single column")
        print("  /ffdp desat [on|off] - desaturate the Protected icons")
        print("  /ffdp ask [on|off] - Protected items always ask before they're destroyed")
        print("  /ffdp quest hide|other - leave quest items out, or show them in Other (now " .. tostring(db.quest) .. ")")
        print("  /ffdp core <section name>|none - a section that always counts as Protected (now \""
            .. tostring(db.coreSection) .. "\")")
        print("  /ffdp debug - hook status, and each Junk / Protected / quest item with its value and why")
    end
end
