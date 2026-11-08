-- DruidFrame's options pages and slash commands. Loaded last, once every file has made its
-- page: DruidFrame is the top page (Esc > Options > AddOns), with DruidBar and DruidRange
-- under it. /druidframe, /druidbar and /druidrange open their own page.

local _, ns = ...

ns.categories = {}

if Settings and Settings.RegisterCanvasLayoutCategory and ns.panels and ns.panels.frame then
    local main = Settings.RegisterCanvasLayoutCategory(ns.panels.frame, "DruidFrame")
    Settings.RegisterAddOnCategory(main)
    ns.categories.frame = main
    for _, page in ipairs({ { key = "bar", name = "DruidBar" }, { key = "range", name = "DruidRange" } }) do
        local panel = ns.panels[page.key]
        if panel then
            if Settings.RegisterCanvasLayoutSubcategory then
                ns.categories[page.key] = Settings.RegisterCanvasLayoutSubcategory(main, panel, page.name)
            else
                local category = Settings.RegisterCanvasLayoutCategory(panel, page.name)
                Settings.RegisterAddOnCategory(category)
                ns.categories[page.key] = category
            end
        end
    end
end

-- which: "frame", "bar" or "range".
function ns.OpenOptions(which)
    local category = ns.categories[which] or ns.categories.frame
    if not (Settings and Settings.OpenToCategory and category) then
        return
    end
    local ok = pcall(Settings.OpenToCategory, category:GetID())
    if not ok then
        pcall(Settings.OpenToCategory, category)
    end
end

-- The display and the range bar are unlocked (draggable) while any DruidFrame page is open.
-- Counted, because moving between pages hides one and shows the next in either order.
local pagesOpen = 0
function ns.PageShown(shown)
    pagesOpen = math.max(0, pagesOpen + (shown and 1 or -1))
    local unlocked = pagesOpen > 0
    if ns.Resource and ns.Resource.SetUnlocked then
        ns.Resource.SetUnlocked(unlocked)
    end
    if ns.Range and ns.Range.SetUnlocked then
        ns.Range.SetUnlocked(unlocked)
    end
end

SLASH_DRUIDFRAME1 = "/druidframe"
SlashCmdList["DRUIDFRAME"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "debug" and ns.Resource then
        ns.Resource.Debug()
    elseif msg == "clearcasting" and ns.Resource then
        ns.Resource.DebugClearcasting()
    elseif msg == "buffs" and ns.Buffs then
        ns.Buffs.Debug()
    elseif msg == "rage" and ns.RageDecay then
        ns.RageDecay.Debug()
    else
        ns.OpenOptions("frame")
    end
end
