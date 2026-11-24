-- CustomQuestTracker: click the "Quests" title of EnhancedQuestTracker's window to minimise the
-- window to that line, and click it again to restore it.
--
-- EnhancedQuestTracker (a separate addon) draws EnhancedQuestTrackerFrame: a title ("Quests (16)",
-- f.title) or, with its Blizzard look, a header bar (f.header), above a scroll area (f.scroll) of
-- zones and quests. Its own code is private, so this works on the frame from outside:
--   * minimise: hide the scroll area and set the window's height to just the title line, and keep
--     it there when EnhancedQuestTracker refits the window (a hook on SetHeight);
--   * restore: show the scroll area and run the window's own OnSizeChanged with a width it hasn't
--     laid out for, which makes it lay itself out again at its proper height.
-- Its quest-item buttons only show for rows inside the scroll area, so they go away when it's
-- minimised (after combat, if minimised in combat: they're secure).

local ADDON = ...
local PREFIX = "|cff66ccffCustomQuestTracker|r"
local addon = {}
CustomQuestTracker = addon

local PADDING = 8 -- EnhancedQuestTracker's frame padding
local db

local function Frame() return EnhancedQuestTrackerFrame end

-- The title line in the current look: the header bar (Blizzard look) or the title text.
function addon.Line(f)
    f = f or Frame()
    if not f then return end
    if f.header and f.header:IsShown() then return f.header, "header" end
    return f.title, "title"
end

-- Height of the window with just the title line.
function addon.MiniHeight(f)
    local line, kind = addon.Line(f)
    if kind == "header" then return math.floor(line:GetHeight() + 0.5) end
    local h = line and line.GetStringHeight and line:GetStringHeight() or 12
    return math.floor(PADDING + h + PADDING + 0.5)
end

function addon.Apply()
    local f = Frame()
    if not f then return end
    if db.minimised then
        f.scroll:Hide()
        addon.setting = true
        f:SetHeight(addon.MiniHeight(f))
        addon.setting = false
    else
        f.scroll:Show()
        -- Let EnhancedQuestTracker lay out again (its OnSizeChanged re-lays out on a new width).
        local onSize = f:GetScript("OnSizeChanged")
        if onSize then onSize(f, -1) end
    end
    if addon.click then addon.click:SetShown(addon.Line(f) == f.title and f.title:IsShown()) end
end

function addon.Toggle()
    if not Frame() then
        print(PREFIX, "EnhancedQuestTracker's window isn't there.")
        return
    end
    db.minimised = not db.minimised
    addon.Apply()
end

-- Hook the window once it exists.
function addon.Hook()
    local f = Frame()
    if not f or addon.hooked then return addon.hooked end
    addon.hooked = true

    -- The title is a font string, which can't take clicks: put a button over it.
    local click = CreateFrame("Button", "CustomQuestTrackerTitleButton", f)
    click:SetPoint("TOPLEFT", f.title, "TOPLEFT", -2, 2)
    click:SetPoint("BOTTOMRIGHT", f.title, "BOTTOMRIGHT", 2, -2)
    click:SetFrameLevel(f:GetFrameLevel() + 10)
    click:RegisterForClicks("LeftButtonUp")
    click:SetScript("OnClick", addon.Toggle)
    addon.click = click

    -- The Blizzard look's header bar: clicks on the bar itself (its own buttons keep theirs).
    if f.header then
        f.header:EnableMouse(true)
        f.header:HookScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then addon.Toggle() end
        end)
    end

    -- Keep it minimised when EnhancedQuestTracker refits the window.
    hooksecurefunc(f, "SetHeight", function(self)
        if db.minimised and not addon.setting then
            addon.setting = true
            self:SetHeight(addon.MiniHeight(self))
            addon.setting = false
        end
    end)

    if db.minimised then addon.Apply() end
    return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        CustomQuestTrackerDB = CustomQuestTrackerDB or {}
        db = CustomQuestTrackerDB
    elseif (event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD") and db then
        if not addon.Hook() then C_Timer.After(2, addon.Hook) end
    end
end)

SLASH_CUSTOMQUESTTRACKER1 = "/cqt"
SlashCmdList.CUSTOMQUESTTRACKER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "mouse" then
        -- What's under the pointer: each frame and its parents.
        local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
        if #foci == 0 then print(PREFIX, "nothing under the mouse") end
        for i, f in ipairs(foci) do
            local chain, cur, depth = {}, f, 0
            while cur and depth < 8 do
                local name = (cur.GetDebugName and cur:GetDebugName()) or (cur.GetName and cur:GetName()) or "?"
                chain[#chain + 1] = name .. " [" .. (cur.GetObjectType and cur:GetObjectType() or "?") .. "]"
                cur = cur.GetParent and cur:GetParent()
                depth = depth + 1
            end
            print(PREFIX, "under mouse " .. i .. ":", table.concat(chain, " < "))
        end
        return
    end
    if msg == "debug" then
        local f = Frame()
        local line, kind = addon.Line(f)
        print(PREFIX, "window:", tostring(f ~= nil), "| shown:", tostring(f and f:IsShown()),
            "| minimised:", tostring(db and db.minimised), "| hooked:", tostring(addon.hooked),
            "| in combat:", tostring(InCombatLockdown()))
        if f then
            print("  line:", tostring(kind), "| text:", tostring(f.title and f.title:GetText()),
                "| height:", math.floor(f:GetHeight() + 0.5), "| mini height:", addon.MiniHeight(f),
                "| list shown:", tostring(f.scroll and f.scroll:IsShown()),
                "| click button:", tostring(addon.click and addon.click:IsShown()))
        end
        return
    end
    if db then addon.Toggle() end
end
