-- LFGForeverExtras: additions to LFG Forever (someone else's addon) kept in their own addon, so
-- LFG Forever's updates don't overwrite them. Nothing in LFG Forever's files is changed.
--
--   * Group tooltips get a panel underneath listing each member with their zone, and their
--     guild when it's known.
--   * Left-clicking a group row (LFG Forever gives left-click no job) runs /who on the next
--     member whose guild isn't known yet. The answer goes to chat and into the panel. /who
--     needs a real click, so it's one member per click.
--   * Guilds are also remembered from anyone you mouse over or target.
--   * %dungeon% works in the Ask to Join whisper (LFG Forever only fills it in for Invite):
--     it becomes the clicked group's dungeon(s).
--
-- How it reaches LFG Forever: its namespace is private, but its window is the global
-- "LFGForeverFrame", its rows carry .resultID, and their Ask to Join button is row.LFGFAskToJoin.
-- Its group tooltip is Blizzard's, shown with LFGBrowseSearchEntryTooltip_UpdateAndShow,
-- which is hooked here (hooksecurefunc, so Blizzard's code isn't tainted).

local E = {}
_G.LFGForeverExtras = E

local PREFIX = "|cff55ff55LFG Forever Extras|r:"
local WHO_TIMEOUT = 4
local GUILD_KEEP_DAYS = 3 -- people change guilds, so remembered guilds are forgotten after this

-------------------------------------------------------------------------------
-- Secret-safe reads
-------------------------------------------------------------------------------

local function Readable(v)
    if v == nil then
        return false
    end
    if canaccessvalue and not canaccessvalue(v) then
        return false
    end
    if issecretvalue and issecretvalue(v) then
        return false
    end
    return true
end

local function ShortName(name)
    return (name:match("^([^%-]+)") or name)
end

local function Key(name)
    return ShortName(name):lower()
end

-------------------------------------------------------------------------------
-- Guild memory (saved)
-------------------------------------------------------------------------------

local function DB()
    LFGForeverExtrasDB = LFGForeverExtrasDB or {}
    LFGForeverExtrasDB.guilds = LFGForeverExtrasDB.guilds or {}
    return LFGForeverExtrasDB
end

-- guild: the name, or "" for someone known to have no guild. area: where /who last saw them.
function E.RememberGuild(name, guild, area)
    if not (Readable(name) and type(name) == "string" and name ~= "") then
        return
    end
    if not Readable(guild) then
        return
    end
    local old = DB().guilds[Key(name)]
    local entry = { guild = guild or "", seen = time(), area = old and old.area, areaSeen = old and old.areaSeen }
    if area and Readable(area) and area ~= "" then
        entry.area, entry.areaSeen = area, GetTime()
    end
    DB().guilds[Key(name)] = entry
end

-- Where /who last saw them, this session (zones go stale fast, so not across sessions).
function E.WhoArea(name)
    local entry = DB().guilds[Key(name)]
    if entry and entry.area then
        return entry.area
    end
end

-- The guild name, "" for none, or nil when unknown.
function E.Guild(name)
    local entry = DB().guilds[Key(name)]
    if entry and (entry.seen or 0) < time() - GUILD_KEEP_DAYS * 86400 then
        return nil
    end
    return entry and entry.guild
end

local function RememberUnit(unit)
    if not (UnitExists(unit) and UnitIsPlayer(unit)) then
        return
    end
    local ok, name = pcall(UnitName, unit)
    if not ok or not Readable(name) then
        return
    end
    local okGuild, guild = pcall(GetGuildInfo, unit)
    if okGuild and Readable(guild) then
        E.RememberGuild(name, guild or "")
    end
end

-------------------------------------------------------------------------------
-- A listing's members and dungeons
-------------------------------------------------------------------------------

function E.Members(resultID)
    local members = {}
    local info = resultID and C_LFGList.GetSearchResultInfo(resultID)
    if not info then
        return members
    end
    local count = info.numMembers
    if not Readable(count) then
        return members
    end
    for i = 1, count do
        local ok, player = pcall(C_LFGList.GetSearchResultPlayerInfo, resultID, i)
        if ok and type(player) == "table" and Readable(player.name) then
            members[#members + 1] = {
                name = player.name,
                area = Readable(player.areaName) and player.areaName or nil,
                class = Readable(player.classFilename) and player.classFilename or nil,
                level = Readable(player.level) and player.level or nil,
                leader = Readable(info.leaderName) and player.name == info.leaderName,
            }
        end
    end
    return members
end

-- LFG Forever's filter panel: the frame in its window with SelectedActivityIDs().
function E.FilterPanel()
    if E.filterPanel then
        return E.filterPanel
    end
    local function Find(frame, depth)
        if depth > 10 then return nil end
        for _, child in ipairs({ frame:GetChildren() }) do
            if type(child.SelectedActivityIDs) == "function" then
                return child
            end
            local found = Find(child, depth + 1)
            if found then return found end
        end
    end
    local window = _G.LFGForeverFrame
    E.filterPanel = window and Find(window, 0)
    return E.filterPanel
end

-- The activities ticked in LFG Forever's search dropdown.
function E.SelectedActivityIDs()
    local filter = E.FilterPanel()
    local ok, ids = pcall(function() return filter and filter:SelectedActivityIDs() end)
    return ok and type(ids) == "table" and ids or {}
end

-- For %dungeon%: the dungeon(s) you searched for that this group lists; if it lists none of
-- them, the ones you searched for; with nothing ticked, the group's own.
function E.DungeonIDs(resultID)
    local info = resultID and C_LFGList.GetSearchResultInfo(resultID)
    local groupIDs = info and info.activityIDs
    if not Readable(groupIDs) or type(groupIDs) ~= "table" then
        local single = info and info.activityID
        groupIDs = Readable(single) and { single } or {}
    end
    local selected = E.SelectedActivityIDs()
    if #selected == 0 then
        return groupIDs
    end
    local wanted, both = {}, {}
    for _, id in ipairs(selected) do wanted[id] = true end
    for _, id in ipairs(groupIDs) do
        if wanted[id] then both[#both + 1] = id end
    end
    return #both > 0 and both or selected
end

function E.DungeonNames(resultID)
    local ids = E.DungeonIDs(resultID)
    local names = {}
    for _, id in ipairs(ids) do
        local activity = C_LFGList.GetActivityInfoTable(id)
        local name = activity and (activity.fullName or activity.shortName)
        if name and Readable(name) and name ~= "" then
            names[#names + 1] = name
        end
    end
    return table.concat(names, ", ")
end

-------------------------------------------------------------------------------
-- The panel under the group tooltip
-------------------------------------------------------------------------------

local panel, lines = nil, {}

local function EnsurePanel()
    if panel then
        return panel
    end
    panel = CreateFrame("Frame", "LFGForeverExtrasPanel", UIParent, "BackdropTemplate")
    panel:SetFrameStrata("TOOLTIP")
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.9)
    panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    panel:Hide()
    return panel
end

local function Line(i)
    local line = lines[i]
    if not line then
        line = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        line:SetJustifyH("LEFT")
        if i == 1 then
            line:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -9)
        else
            line:SetPoint("TOPLEFT", lines[i - 1], "BOTTOMLEFT", 0, -3)
        end
        lines[i] = line
    end
    return line
end

local function ClassColour(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and c.colorStr or "ffffffff"
end

function E.ShowPanel(tooltip, resultID)
    local members = E.Members(resultID)
    EnsurePanel()
    if #members < 2 then
        -- Solo listings already show their zone on the row.
        panel:Hide()
        return
    end
    local texts = { "|cffffd100Members|r" }
    local unknown = false
    for _, m in ipairs(members) do
        local text = "|c" .. ClassColour(m.class) .. ShortName(m.name) .. "|r"
        local guild = E.Guild(m.name)
        if guild == nil or not (m.area or E.WhoArea(m.name)) then
            unknown = true
        end
        if guild == nil then
        elseif guild ~= "" then
            text = text .. " |cff40ff40<" .. guild .. ">|r"
        end
        if m.leader then
            text = text .. " |cffaaaaaa(leader)|r"
        end
        text = text .. "  |cffaaaaaa" .. (m.area or E.WhoArea(m.name) or "zone unknown") .. "|r"
        texts[#texts + 1] = text
    end
    if unknown then
        texts[#texts + 1] = "|cff888888Click the group to /who the next member for their guild and zone.|r"
    end
    local width = 0
    for i, text in ipairs(texts) do
        local line = Line(i)
        line:SetText(text)
        line:Show()
        local w = line:GetStringWidth()
        if Readable(w) and w > width then
            width = w
        end
    end
    for i = #texts + 1, #lines do
        lines[i]:Hide()
    end
    local height = 0
    for i = 1, #texts do
        local h = lines[i]:GetStringHeight()
        height = height + (Readable(h) and h or 12) + (i > 1 and 3 or 0)
    end
    panel:SetSize(width + 20, height + 18)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, 2)
    panel.resultID = resultID
    panel:Show()
end

function E.RefreshPanel()
    local tooltip = LFGBrowseSearchEntryTooltip
    if panel and panel:IsShown() and tooltip and tooltip:IsShown() and panel.resultID then
        E.ShowPanel(tooltip, panel.resultID)
    end
end

-------------------------------------------------------------------------------
-- /who on a click
-------------------------------------------------------------------------------

local asked = {} -- key -> GetTime() of the last /who sent for them

function E.WhoNext(resultID)
    local members = E.Members(resultID)
    if #members == 0 then
        print(PREFIX, "can't read this group's members.")
        return
    end
    local pick
    for _, m in ipairs(members) do
        if (E.Guild(m.name) == nil or (not m.area and not E.WhoArea(m.name))) and not (asked[Key(m.name)] and GetTime() - asked[Key(m.name)] < 30) then
            pick = m
            break
        end
    end
    if not pick then
        -- Everyone known (or just asked): refresh them in turn instead.
        E.cycle = (E.cycle or 0) % #members + 1
        pick = members[E.cycle]
    end
    local name = ShortName(pick.name)
    asked[Key(pick.name)] = GetTime()
    E.pending = { name = name, key = Key(pick.name), sent = GetTime() }
    local ok = pcall(C_FriendList.SendWho, 'n-"' .. name .. '"')
    if not ok then
        print(PREFIX, "/who was refused.")
        E.pending = nil
        return
    end
    print(PREFIX, "looking up " .. name .. "...")
    C_Timer.After(WHO_TIMEOUT, function()
        local pending = E.pending
        if pending and pending.key == Key(pick.name) and GetTime() - pending.sent >= WHO_TIMEOUT - 0.1 then
            E.pending = nil
            print(PREFIX, "no answer for " .. name .. " (offline, or the server only allows a /who every few seconds).")
        end
    end)
end

function E.ReadWho()
    local count = C_FriendList.GetNumWhoResults and C_FriendList.GetNumWhoResults()
    if not Readable(count) or count == 0 then
        return
    end
    local found
    for i = 1, count do
        local info = C_FriendList.GetWhoInfo(i)
        if info and Readable(info.fullName) then
            E.RememberGuild(info.fullName, Readable(info.fullGuildName) and info.fullGuildName or "",
                Readable(info.area) and info.area or nil)
            if E.pending and Key(info.fullName) == E.pending.key then
                found = info
            end
        end
    end
    if found then
        E.pending = nil
        local guild = Readable(found.fullGuildName) and found.fullGuildName or ""
        print(PREFIX, ShortName(found.fullName) .. (guild ~= "" and (" <" .. guild .. ">") or " (no guild)")
            .. (Readable(found.area) and found.area and (" - " .. found.area) or ""))
        E.RefreshPanel()
    end
end

-------------------------------------------------------------------------------
-- %dungeon% in the Ask to Join whisper
-------------------------------------------------------------------------------
-- LFG Forever reads the message from LFGForeverCharDB.askToJoinMessage at click time. Just
-- before its click runs, %dungeon% there is swapped for the group's dungeons; straight after,
-- the saved text is put back.

local function AskPreClick(button)
    local row = button:GetParent()
    local charDB = LFGForeverCharDB
    local template = charDB and charDB.askToJoinMessage
    if type(template) ~= "string" or not template:find("%dungeon%", 1, true) or not (row and row.resultID) then
        return
    end
    local names = E.DungeonNames(row.resultID)
    if names == "" then
        names = "your group"
    end
    E.savedTemplate = template
    charDB.askToJoinMessage = template:gsub("%%dungeon%%", function() return names end)
    -- Put it back even if the click errors before PostClick.
    C_Timer.After(0, E.RestoreTemplate)
end

function E.RestoreTemplate()
    if E.savedTemplate and LFGForeverCharDB then
        LFGForeverCharDB.askToJoinMessage = E.savedTemplate
    end
    E.savedTemplate = nil
end

-------------------------------------------------------------------------------
-- Finding LFG Forever's rows
-------------------------------------------------------------------------------

local hookedRows = setmetatable({}, { __mode = "k" })

local function HookRow(row)
    if hookedRows[row] then
        return
    end
    hookedRows[row] = true
    if row.HookScript and row:GetScript("OnClick") then
        row:HookScript("OnClick", function(self, mouseButton)
            -- LFG Forever: right-click opens the menu, left-click does nothing.
            if mouseButton == "LeftButton" and self.resultID and not self.isDelisted then
                E.WhoNext(self.resultID)
            end
        end)
    end
    local ask = row.LFGFAskToJoin
    if ask and ask.HookScript then
        ask:HookScript("PreClick", AskPreClick)
        ask:HookScript("PostClick", E.RestoreTemplate)
    end
end

local function Walk(frame, depth)
    if depth > 12 then
        return
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child.LFGFAskToJoin or (child.resultID ~= nil and child.HookScript) then
            HookRow(child)
        else
            Walk(child, depth + 1)
        end
    end
end

function E.ScanRows()
    local window = _G.LFGForeverFrame
    if window then
        Walk(window, 0)
    end
end

-------------------------------------------------------------------------------
-- Hooks and events
-------------------------------------------------------------------------------

local function TryHookTooltip()
    if E.tooltipHooked or type(LFGBrowseSearchEntryTooltip_UpdateAndShow) ~= "function" then
        return
    end
    E.tooltipHooked = true
    hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", function(tooltip, resultID)
        E.ScanRows()
        -- Only for LFG Forever's window, not Blizzard's own Group Finder.
        local window = _G.LFGForeverFrame
        if window and window:IsShown() then
            E.ShowPanel(tooltip, resultID)
        end
    end)
    if LFGBrowseSearchEntryTooltip then
        LFGBrowseSearchEntryTooltip:HookScript("OnHide", function()
            if panel then panel:Hide() end
        end)
    end
end

local function TryHookWindow()
    local window = _G.LFGForeverFrame
    if E.windowHooked or not window then
        return
    end
    E.windowHooked = true
    window:HookScript("OnShow", function()
        E.ScanRows()
        C_Timer.After(1, E.ScanRows)
    end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "WHO_LIST_UPDATE", "CHAT_MSG_SYSTEM",
    "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Zones from earlier sessions are out of date, and guilds after a few days.
        local guilds = DB().guilds
        local cutoff = time() - GUILD_KEEP_DAYS * 86400
        for key, entry in pairs(guilds) do
            if (entry.seen or 0) < cutoff then
                guilds[key] = nil
            else
                entry.area, entry.areaSeen = nil, nil
            end
        end
    end
    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
        DB()
        TryHookTooltip()
        TryHookWindow()
    elseif event == "WHO_LIST_UPDATE" then
        E.ReadWho()
    elseif event == "CHAT_MSG_SYSTEM" then
        -- With a single result the game prints it to chat; the list is filled in too.
        if E.pending then
            C_Timer.After(0.1, E.ReadWho)
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        RememberUnit("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        RememberUnit("target")
    end
end)

SLASH_LFGFOREVEREXTRAS1 = "/lfgextras"
SlashCmdList.LFGFOREVEREXTRAS = function(msg)
    msg = (msg or ""):lower()
    if msg == "forget" then
        DB().guilds = {}
        print(PREFIX, "remembered guilds cleared.")
        return
    end
    local count = 0
    for _ in pairs(DB().guilds) do count = count + 1 end
    print(PREFIX, "tooltip hooked:", tostring(E.tooltipHooked), "| window hooked:", tostring(E.windowHooked),
        "| rows hooked:", (function() local n = 0 for _ in pairs(hookedRows) do n = n + 1 end return n end)(),
        "| guilds remembered:", count)
    local resultID = panel and panel.resultID
    if resultID then
        print("Last group hovered (" .. tostring(resultID) .. "), dungeons: " .. E.DungeonNames(resultID))
        for i, m in ipairs(E.Members(resultID)) do
            print(i, m.name, "zone:", tostring(m.area), "guild:", tostring(E.Guild(m.name)))
        end
    end
    print("/lfgextras forget: clear remembered guilds.")
end
