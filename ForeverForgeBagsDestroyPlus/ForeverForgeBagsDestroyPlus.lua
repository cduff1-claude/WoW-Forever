-- ForeverForge Bags Destroy Plus
-- Changes ForeverForge Bags' Destroy mode without touching its files:
--   * Gray items, and anything headed for a vendor (filed in Junk, or in a
--     section automated to sell at vendors), are valued at vendor price only.
--   * The cheapest-first view is split into three sections:
--       Junk           - grays, Junk, vendor-automated sections
--       Everything else
--       Keep last      - your "Core" section, quest items, no sell value
--     each cheapest first, with the bottom section's icons desaturated.
-- Written against ForeverForge Bags 0.21.0. It replaces
-- ForeverForgeBags.Window.CollectByValue and wraps
-- ForeverForgeBags.Destroy.ItemValue; everything else is hooked, not replaced.

local ADDON = ...
local PREFIX = "|cffe04848ForeverForge Bags Destroy Plus|r: "
local TESTED_VERSION = "0.21.0"

local DEFAULTS = { grayVendor = true, sections = true, desaturate = true, coreSection = "Core" }

local db = {}
for k, v in pairs(DEFAULTS) do db[k] = v end

local origItemValue, origCollect
local installed = { value = false, sections = false, desat = false, tooltips = false }

-- Section titles in the Destroy view.
local JUNK_TITLE = "Junk"
local MID_TITLE = "Everything else"
local LAST_TITLE = "Keep last"

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

--- "junk", "mid" or "last", and why.
local function groupOf(d, value)
    local filed, automate = filedIn(d)
    if isCore(filed) then return "last", "in " .. tostring(filed) end
    -- Filed for selling beats the quest check: you said so by hand.
    if automate == "vendor" or (filed ~= nil and filed == junkName()) then
        return "junk", select(2, isVendorJunk(d, filed, automate))
    end
    if isQuest(d, filed) then return "last", "quest item" end
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

------------------------------------------------------------- Sections

-- slotData -> itemId, for the bottom section of the last Destroy view drawn.
local lastSlots = {}

local function byValue(a, b)
    if a.worthless ~= b.worthless then return b.worthless end
    if a.value ~= b.value then return a.value < b.value end
    local an, bn = a.slotData.name or "", b.slotData.name or ""
    if an ~= bn then return an < bn end
    if a.slotData.bag ~= b.slotData.bag then return a.slotData.bag < b.slotData.bag end
    return a.slotData.slot < b.slotData.slot
end

local function collectByValue(self, ...)
    if not db.sections then
        wipe(lastSlots)
        return origCollect(self, ...)
    end
    local fb = FB()
    local D, B = fb.Destroy, fb.Bags
    D.ResetValues()
    wipe(lastSlots)
    local groups = { junk = {}, mid = {}, last = {} }
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
            blocks[#blocks + 1] = { name = g[2], kind = "destroy", entries = list, fgDestroyPlus = g[1] }
        end
    end
    -- Bags with nothing in them still show one (empty) section, as before.
    if #blocks == 0 then
        blocks[1] = { name = MID_TITLE, kind = "destroy", entries = {}, fgDestroyPlus = "mid" }
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

---------------------------------------------------------- Header tooltips

local TIPS = {
    [JUNK_TITLE] = { "Destroy mode - junk",
        "Gray items, items you filed in Junk, and items in a section set to sell at vendors. Cheapest first, valued at vendor price only (they're getting vendored anyway)." },
    [MID_TITLE] = { "Destroy mode - cheapest first",
        "Everything else, cheapest first: left to right, then down. Worth is the vendor price, or the auction house price after fees when that's more." },
    [LAST_TITLE] = { "Destroy mode - keep last",
        "Your Core section, quest items, and anything with no sell value, cheapest first. Anything with no sell value always asks before it is destroyed." },
}

local function afterRebuild(self)
    if not (db.sections and self.destroyViewShown and self.sections) then return end
    local Section = FB().Section
    if not (Section and Section.SetHeaderTooltip) then return end
    for _, s in ipairs(self.sections) do
        local tip = TIPS[s.name]
        if tip then pcall(Section.SetHeaderTooltip, Section, s, "click one to destroy it", tip[1], tip[2]) end
    end
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
    if not installed.tooltips and W and type(W.Rebuild) == "function" then
        hooksecurefunc(W, "Rebuild", afterRebuild)
        installed.tooltips = true
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
        ForeverForgeBagsDestroyPlusDB = ForeverForgeBagsDestroyPlusDB or {}
        db = ForeverForgeBagsDestroyPlusDB
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

local function debug()
    local fb = FB()
    Print("debug")
    local v = version()
    print(("  ForeverForge Bags %s%s"):format(tostring(v),
        v == TESTED_VERSION and "" or (" |cffffaa00(written against " .. TESTED_VERSION .. ")|r")))
    print(("  hooks: value %s, sections %s, desaturate %s, tooltips %s"):format(tostring(installed.value),
        tostring(installed.sections), tostring(installed.desat), tostring(installed.tooltips)))
    print(("  still ours: ItemValue %s, CollectByValue %s"):format(
        tostring(fb and fb.Destroy and fb.Destroy.ItemValue == itemValue),
        tostring(fb and fb.Window and fb.Window.CollectByValue == collectByValue)))
    print(("  settings: vendor price %s, sections %s, desaturate %s, core section \"%s\""):format(
        db.grayVendor and "on" or "off", db.sections and "on" or "off", db.desaturate and "on" or "off",
        tostring(db.coreSection)))
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
                if g == "mid" then
                    mid = mid + 1
                else
                    local filed = filedIn(d)
                    local orig = origItemValue(d) * math.max(1, tonumber(d.count) or 1)
                    print(("  [%s] %s x%d: %s (%s) | original %s | q%s filed=%s class=%s"):format(
                        g, d.link, d.count or 1, money(value), tostring(how), money(orig), tostring(d.quality),
                        tostring(filed), tostring(d.class)) .. (why and (" - " .. why) or ""))
                end
            end
        end
    end
    print("  " .. mid .. " stacks in Everything else")
    D.ResetValues()
end

------------------------------------------------------------------- Slash

local function onOff(key, arg, label)
    if arg == "on" then db[key] = true elseif arg == "off" then db[key] = false else db[key] = not db[key] end
    Print(label .. ": " .. (db[key] and "on" or "off"))
    redraw()
end

SLASH_FOREVERFORGEBAGSDESTROYPLUS1 = "/ffdp"
SlashCmdList.FOREVERFORGEBAGSDESTROYPLUS = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = lower(cmd) or ""
    local arg = lower(rest)
    if cmd == "vendor" then
        onOff("grayVendor", arg, "gray / junk / vendor-section items valued at vendor price only")
    elseif cmd == "sections" then
        onOff("sections", arg, "Junk / Everything else / Keep last sections")
    elseif cmd == "desat" then
        onOff("desaturate", arg, "desaturate Keep last icons")
    elseif cmd == "core" then
        if rest ~= "" then db.coreSection = rest end
        Print("section that always goes in Keep last: \"" .. tostring(db.coreSection) .. "\"")
        redraw()
    elseif cmd == "debug" then
        debug()
    else
        Print("commands:")
        print("  /ffdp vendor [on|off] - vendor price only for gray / Junk / vendor-section items")
        print("  /ffdp sections [on|off] - split Destroy mode into Junk / Everything else / Keep last")
        print("  /ffdp desat [on|off] - desaturate the Keep last icons")
        print("  /ffdp core <section name> - your section that always goes in Keep last (now \""
            .. tostring(db.coreSection) .. "\")")
        print("  /ffdp debug - hook status, and each non-middle item with its group, value and why")
    end
end
