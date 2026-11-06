-- Forever Quest Complete Sound
-- Plays a sound (and shows a message) when a quest's objectives are done and it is ready to turn in.
-- Rewrite of Drash_QuestCompleteSound for the Retail quest log API (C_QuestLog) used by WoW Forever.

local ADDON_NAME = "ForeverQuestCompleteSound"
local SOUND_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\sound\\"
local PREFIX = "|cffcdb38bQuestCompleteSound:|r "

local SOUNDS = {
    horde = SOUND_PATH .. "Owrkdone.mp3",
    alliance = SOUND_PATH .. "Peasant_work_done.mp3",
    sheep = SOUND_PATH .. "sheep.ogg",
}

-- Seconds after a loading screen during which newly seen complete quests are recorded silently,
-- because the quest log can fill in over several updates after login or a zone change.
local LOGIN_QUIET_TIME = 5
local SCAN_DELAY = 0.2

ForeverQuestCompleteSoundDB = ForeverQuestCompleteSoundDB or {}

local DEFAULTS = {
    enabled = true,
    sound = "faction",      -- faction, horde, alliance, sheep, a file name in the sound folder, or a SoundKit ID
    channel = "Master",     -- Master, SFX, Music, Ambience, Dialog
    output = "raid",        -- raid, error, chat, none
    ignoreOnAccept = true,  -- stay quiet for quests that are already complete when accepted
}

local function EnsureDB()
    for key, value in pairs(DEFAULTS) do
        if ForeverQuestCompleteSoundDB[key] == nil then
            ForeverQuestCompleteSoundDB[key] = value
        end
    end
    return ForeverQuestCompleteSoundDB
end

local db = EnsureDB()

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value) or false
end

local function Readable(value)
    if IsSecretValue(value) then
        return nil
    end
    return value
end

-- Quest state --------------------------------------------------------------

local knownComplete = {}  -- questID -> true for quests already seen as complete
local justAccepted = {}   -- questID -> true until the quest's first scan after QUEST_ACCEPTED
local quietUntil = 0
local scanPending = false

local function CallQuestAPI(name, questID)
    local fn = C_QuestLog and C_QuestLog[name]
    if not fn then
        return nil
    end
    local ok, result = pcall(fn, questID)
    if not ok then
        return nil
    end
    return result
end

local function IsQuestReady(questID)
    local ready = Readable(CallQuestAPI("ReadyForTurnIn", questID))
    local complete = Readable(CallQuestAPI("IsComplete", questID))
    return ready == true or complete == true
end

-- Returns a list of { questID, title, level } for every real quest in the log.
local function ReadQuestLog()
    local quests = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
        return quests
    end

    local numEntries = Readable(C_QuestLog.GetNumQuestLogEntries()) or 0
    for index = 1, numEntries do
        local info = C_QuestLog.GetInfo(index)
        local questID = info and Readable(info.questID)
        if questID and questID ~= 0 and not info.isHeader and not info.isHidden then
            quests[#quests + 1] = {
                questID = questID,
                title = Readable(info.title) or ("Quest " .. questID),
                level = Readable(info.level) or 0,
            }
        end
    end
    return quests
end

-- Sound and message --------------------------------------------------------

local function GetSoundSetting()
    local setting = db.sound
    if setting == "faction" then
        local faction = UnitFactionGroup("player")
        return (faction == "Horde") and "horde" or "alliance"
    end
    return setting
end

-- Plays the configured sound. Returns willPlay, a description of what was played.
local function PlayConfiguredSound()
    local setting = GetSoundSetting()
    local kitID = tonumber(setting)

    if kitID then
        local willPlay = PlaySound(kitID, db.channel)
        return willPlay, "SoundKit " .. kitID
    end

    local file = SOUNDS[setting] or (SOUND_PATH .. setting)
    local willPlay = PlaySoundFile(file, db.channel)
    return willPlay, file
end

local function FormatQuestName(title, level)
    local r, g, b = 1, 0.82, 0
    if GetQuestDifficultyColor and level and level > 0 then
        local ok, color = pcall(GetQuestDifficultyColor, level)
        if ok and type(color) == "table" and color.r then
            r, g, b = color.r, color.g, color.b
        end
    end
    local levelText = (level and level > 0) and ("[" .. level .. "] ") or ""
    return string.format("|cff%02x%02x%02x%s%s|r",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), levelText, title)
end

local function ShowMessage(text)
    if db.output == "raid" and RaidNotice_AddMessage and RaidBossEmoteFrame then
        RaidNotice_AddMessage(RaidBossEmoteFrame, text, ChatTypeInfo["SYSTEM"])
    elseif db.output == "error" and UIErrorsFrame then
        UIErrorsFrame:AddMessage(text, 1, 1, 0, 1)
    elseif db.output == "chat" then
        print(PREFIX .. text)
    end
end

local function ShowQuestMessage(title, level)
    ShowMessage(string.format(ERR_QUEST_COMPLETE_S or "%s completed.", FormatQuestName(title, level)))
end

local function Announce(title, level)
    PlayConfiguredSound()
    ShowQuestMessage(title, level)
end

-- Scanning -----------------------------------------------------------------

local function ScanQuestLog()
    scanPending = false
    local quiet = GetTime() < quietUntil
    local nowComplete = {}

    for _, quest in ipairs(ReadQuestLog()) do
        local questID = quest.questID
        if IsQuestReady(questID) then
            nowComplete[questID] = true
            local skip = quiet or not db.enabled or (db.ignoreOnAccept and justAccepted[questID])
            if not knownComplete[questID] and not skip then
                Announce(quest.title, quest.level)
            end
        end
        justAccepted[questID] = nil
    end

    -- Quests that were turned in, abandoned, or became incomplete again (e.g. items dropped)
    -- fall out of the set, so they announce again if they complete later.
    knownComplete = nowComplete
end

local function QueueScan()
    if scanPending then
        return
    end
    scanPending = true
    C_Timer.After(SCAN_DELAY, ScanQuestLog)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("QUEST_ACCEPTED")

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        -- SavedVariables are loaded after this file runs, so re-read them here.
        db = EnsureDB()
    elseif event == "PLAYER_ENTERING_WORLD" then
        quietUntil = GetTime() + LOGIN_QUIET_TIME
        QueueScan()
    elseif event == "QUEST_ACCEPTED" then
        -- Retail passes (questID); older clients passed (questLogIndex, questID).
        local questID = Readable(arg2 or arg1)
        if questID then
            justAccepted[questID] = true
        end
        QueueScan()
    elseif event == "QUEST_LOG_UPDATE" then
        QueueScan()
    end
end)

-- Slash commands -----------------------------------------------------------

local function PrintSoundResult(willPlay, description)
    print(PREFIX .. "sound '" .. tostring(db.sound) .. "' -> " .. tostring(description)
        .. " on " .. tostring(db.channel) .. ", willPlay: " .. tostring(willPlay))
    if not willPlay then
        print(PREFIX .. "the game refused to play it (missing file, bad SoundKit ID, or that channel is muted).")
    end
end

local function PrintDebugInfo()
    local version, build = GetBuildInfo()
    print("|cff55ff55ForeverQuestCompleteSound debug|r")
    print("Client:", tostring(version), "build", tostring(build))
    print("Enabled:", tostring(db.enabled), "output:", tostring(db.output),
        "ignoreOnAccept:", tostring(db.ignoreOnAccept))
    print("APIs: C_QuestLog", tostring(C_QuestLog ~= nil),
        "GetInfo", tostring(C_QuestLog and C_QuestLog.GetInfo ~= nil),
        "IsComplete", tostring(C_QuestLog and C_QuestLog.IsComplete ~= nil),
        "ReadyForTurnIn", tostring(C_QuestLog and C_QuestLog.ReadyForTurnIn ~= nil))

    local numEntries, numQuests = nil, nil
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        numEntries, numQuests = C_QuestLog.GetNumQuestLogEntries()
    end
    print("Log entries:", tostring(numEntries), "quests:", tostring(numQuests),
        "secret:", tostring(IsSecretValue(numEntries)))

    for _, quest in ipairs(ReadQuestLog()) do
        local questID = quest.questID
        local complete = CallQuestAPI("IsComplete", questID)
        local ready = CallQuestAPI("ReadyForTurnIn", questID)
        local secret = IsSecretValue(complete) or IsSecretValue(ready)
        print(string.format("  %d [%s] %s  IsComplete=%s ReadyForTurnIn=%s known=%s%s",
            questID, tostring(quest.level), quest.title,
            secret and "?" or tostring(complete), secret and "?" or tostring(ready),
            tostring(knownComplete[questID] == true), secret and " (secret)" or ""))
    end

    PrintSoundResult(PlayConfiguredSound())
end

local function PrintHelp()
    print("|cff55ff55ForeverQuestCompleteSound|r commands:")
    print("  /qcs on | off         - enable or disable")
    print("  /qcs sound <choice>   - faction, horde, alliance, sheep, a file in the sound folder, or a SoundKit ID")
    print("  /qcs channel <name>   - Master, SFX, Music, Ambience or Dialog")
    print("  /qcs out <where>      - raid, error, chat or none")
    print("  /qcs accept           - toggle staying quiet for quests already complete when accepted")
    print("  /qcs test             - play the sound and show a sample message")
    print("  /qcs debug            - print quest log values and play the sound")
    print("Current: sound " .. tostring(db.sound) .. ", channel " .. tostring(db.channel)
        .. ", output " .. tostring(db.output) .. ", " .. (db.enabled and "enabled" or "disabled"))
end

local CHANNELS = { master = "Master", sfx = "SFX", music = "Music", ambience = "Ambience", dialog = "Dialog" }
local OUTPUTS = { raid = true, error = true, chat = true, none = true }

SLASH_FOREVERQUESTCOMPLETESOUND1 = "/qcs"
SlashCmdList["FOREVERQUESTCOMPLETESOUND"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "on" or cmd == "off" then
        db.enabled = (cmd == "on")
        print(PREFIX .. (db.enabled and "enabled." or "disabled."))
    elseif cmd == "sound" and arg ~= "" then
        -- Keep custom file names as typed; built-in names are lower case.
        local lower = arg:lower()
        if lower == "faction" or SOUNDS[lower] then
            arg = lower
        end
        db.sound = arg
        PrintSoundResult(PlayConfiguredSound())
    elseif cmd == "channel" and CHANNELS[arg:lower()] then
        db.channel = CHANNELS[arg:lower()]
        PrintSoundResult(PlayConfiguredSound())
    elseif cmd == "out" and OUTPUTS[arg:lower()] then
        db.output = arg:lower()
        print(PREFIX .. "output set to " .. db.output .. ".")
        ShowQuestMessage("Test Quest", UnitLevel("player"))
    elseif cmd == "accept" then
        db.ignoreOnAccept = not db.ignoreOnAccept
        print(PREFIX .. (db.ignoreOnAccept
            and "quests already complete when accepted will stay quiet."
            or "quests already complete when accepted will play the sound."))
    elseif cmd == "test" then
        PrintSoundResult(PlayConfiguredSound())
        ShowQuestMessage("Test Quest", UnitLevel("player"))
    elseif cmd == "debug" then
        PrintDebugInfo()
    else
        PrintHelp()
    end
end
