-- ForeverForge Bags Gray Value
-- Wraps ForeverForgeBags.Destroy.ItemValue so gray (quality 0) items are worth
-- their vendor price only. Everything else still goes to the original, so
-- updates to ForeverForge Bags keep working for non-gray items.

local ADDON = ...
local PREFIX = "|cff9d9d9dForeverForge Bags Gray Value|r: "

local db
local orig        -- ForeverForge Bags' own ItemValue
local hooked      -- the Destroy table we wrapped

local function Print(msg) print(PREFIX .. msg) end

local function enabled()
    return not db or db.enabled ~= false
end

local function qualityOf(d)
    if d.quality ~= nil then return d.quality end
    local CI = C_Item
    if CI and CI.GetItemQualityByID and d.itemId then
        local ok, q = pcall(CI.GetItemQualityByID, d.itemId)
        if ok then return q end
    end
    return nil
end

local function grayValue(self_or_d, maybe_d)
    -- D.ItemValue is called as a plain function (D.ItemValue(d)), but accept
    -- a method call too in case that ever changes.
    local d = maybe_d or self_or_d
    if enabled() and type(d) == "table" and d.itemId and qualityOf(d) == 0 then
        local vendor = tonumber(d.vendorPrice) or 0
        return vendor, vendor > 0 and "vendor" or nil
    end
    return orig(self_or_d, maybe_d)
end

local function install()
    local FB = _G.ForeverForgeBags
    local D = FB and FB.Destroy
    if not (D and type(D.ItemValue) == "function") then return false end
    if D.ItemValue == grayValue then return true end
    orig = D.ItemValue
    D.ItemValue = grayValue
    hooked = D
    -- Drop any values worked out before the wrap.
    if D.ResetValues then pcall(D.ResetValues) end
    return true
end

local function resetValues()
    if hooked and hooked.ResetValues then pcall(hooked.ResetValues) end
end

install()

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        ForeverForgeBagsGrayValueDB = ForeverForgeBagsGrayValueDB or {}
        db = ForeverForgeBagsGrayValueDB
        if db.enabled == nil then db.enabled = true end
    elseif event == "PLAYER_LOGIN" then
        db = ForeverForgeBagsGrayValueDB or db
        install()
        f:UnregisterEvent("ADDON_LOADED")
        return
    end
    if not hooked then install() end
end)

------------------------------------------------------------------ Debug

local function debug()
    local FB = _G.ForeverForgeBags
    local D = FB and FB.Destroy
    Print("debug")
    print("  ForeverForgeBags loaded: " .. tostring(FB ~= nil) .. ", Destroy table: " .. tostring(D ~= nil))
    print("  hooked: " .. tostring(D ~= nil and D.ItemValue == grayValue) .. ", enabled: " .. tostring(enabled()))
    if not (D and orig and C_Container) then return end
    local money = FB.Money or GetMoneyString or tostring
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    local shown = 0
    for bag = 0, lastBag do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink then
                local q = info.quality
                if q == nil and C_Item and C_Item.GetItemQualityByID then q = C_Item.GetItemQualityByID(info.itemID) end
                if q == 0 then
                    local sell = select(11, C_Item.GetItemInfo(info.hyperlink))
                    local d = { itemId = info.itemID, link = info.hyperlink, quality = q, count = info.stackCount,
                                bag = bag, slot = slot, vendorPrice = sell }
                    local ov, ohow = orig(d)
                    local nv, nhow = grayValue(d)
                    print(("  %s x%d: vendor %s | original %s (%s) | now %s (%s)"):format(info.hyperlink,
                        info.stackCount or 1, money(tonumber(sell) or 0), money(ov or 0), tostring(ohow),
                        money(nv or 0), tostring(nhow)))
                    shown = shown + 1
                end
            end
        end
    end
    if shown == 0 then print("  no gray items in your bags") end
    resetValues()
end

SLASH_FOREVERFORGEBAGSGRAYVALUE1 = "/ffgray"
SlashCmdList.FOREVERFORGEBAGSGRAYVALUE = function(msg)
    local cmd = strtrim((msg or ""):lower())
    if cmd == "on" or cmd == "off" then
        db = db or {}
        db.enabled = (cmd == "on")
        ForeverForgeBagsGrayValueDB = db
        resetValues()
        Print("gray items valued at vendor price only: " .. (db.enabled and "on" or "off")
            .. ". Reopen the bags to re-sort.")
    elseif cmd == "debug" then
        debug()
    else
        Print("/ffgray on|off - value gray items at vendor price only (now " .. (enabled() and "on" or "off") .. ")")
        Print("/ffgray debug - show whether the hook is in and each gray item's values")
    end
end
