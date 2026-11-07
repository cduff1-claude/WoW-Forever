---
-- Contains definitions for the Average Information windows
-- @file XToLevel.Average.lua
-- @release 12.1.0-20260813-1
-- @author Atli Þór (r4d1o4ct1v3v3@gmail.com)
---
XToLevel.Average =
{
    activeAPI = "Blocky",
    knownAPIs = {
        [1] = "Blocky",
        [2] = "Classic"
    }
}

---
-- Initialize the Average control methods. This basically just sets
-- which API should be used.
function XToLevel.Average:Initialize()
    self.activeAPI = self.knownAPIs[XToLevel.db.profile.averageDisplay.mode]
    for index, name in ipairs(self.knownAPIs) do
        XToLevel.AverageFrameAPI[name]:Initialize()
    end
    self:RestorePositions()
    
    self:Update()
end

---
-- Window positions are kept in the profile. The client's own memory of
-- dragged frames (layout cache) does not survive a client restart on
-- WoW Forever, so it can't be relied on.
XToLevel.Average.frameNames = {
    Blocky = "XToLevel_AverageFrame_Blocky_PlayerFrame",
    Classic = "XToLevel_AverageFrame_Classic",
}

function XToLevel.Average:SavePosition(apiName)
    local frame = _G[self.frameNames[apiName]]
    if not frame then return end
    -- Take the frame back from the client's layout cache so the two don't fight.
    if frame.SetUserPlaced and frame:IsMovable() then frame:SetUserPlaced(false) end
    local point, _, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    if not point then return end
    local display = XToLevel.db.profile.averageDisplay
    display.positions = display.positions or {}
    display.positions[apiName] = { point, relativePoint, xOfs, yOfs }
end

function XToLevel.Average:RestorePositions()
    local positions = XToLevel.db.profile.averageDisplay.positions
    if not positions then return end
    for apiName, frameName in pairs(self.frameNames) do
        local frame, pos = _G[frameName], positions[apiName]
        if frame and pos then
            frame:ClearAllPoints()
            frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        end
    end
end

---
-- Updates the active AverageFrame window.
function XToLevel.Average:Update()
    if XToLevel.Player.level < XToLevel.Player:GetMaxLevel() then
        if self.activeAPI ~= self.knownAPIs[XToLevel.db.profile.averageDisplay.mode] then
            for index, name in ipairs(self.knownAPIs) do
                XToLevel.AverageFrameAPI[name]:Update()
            end
            if self.knownAPIs[XToLevel.db.profile.averageDisplay.mode] ~= nil then
                self:AlignBoxes(self.activeAPI, self.knownAPIs[XToLevel.db.profile.averageDisplay.mode])
                self.activeAPI = self.knownAPIs[XToLevel.db.profile.averageDisplay.mode]
            end
        end
        if self.knownAPIs[XToLevel.db.profile.averageDisplay.mode] ~= nil then
            if XToLevel.Player.isActive then
                XToLevel.AverageFrameAPI[self.activeAPI]:SetKills       (XToLevel.Player:GetAverageKillsRemaining() or nil)
                XToLevel.AverageFrameAPI[self.activeAPI]:SetQuests      (XToLevel.Player:GetAverageQuestsRemaining() or nil)
                XToLevel.AverageFrameAPI[self.activeAPI]:SetPetBattles  (XToLevel.Player:GetAveragePetBattlesRemaining() or nil)
                XToLevel.AverageFrameAPI[self.activeAPI]:SetDungeons    (XToLevel.Player:GetAverageDungeonsRemaining() or nil)
                XToLevel.AverageFrameAPI[self.activeAPI]:SetBattles     (XToLevel.Player:GetAverageBGsRemaining() or nil)
                XToLevel.AverageFrameAPI[self.activeAPI]:SetObjectives  (XToLevel.Player:GetAverageBGObjectivesRemaining() or nil)
                XToLevel.AverageFrameAPI[self.activeAPI]:SetProgress    (XToLevel.Lib:round((XToLevel.Player.currentXP or 0) / (XToLevel.Player.maxXP or 1) * 100, 1))
                XToLevel.AverageFrameAPI[self.activeAPI]:SetGathering   (XToLevel.Player:GetGatheringRequired())
                
                if XToLevel.db.profile.averageDisplay.archaeologyAsSites then
                    XToLevel.AverageFrameAPI[self.activeAPI]:SetDigs    (XToLevel.Player:GetDigsitesRequired() or nil)
                else
                    XToLevel.AverageFrameAPI[self.activeAPI]:SetDigs    (XToLevel.Player:GetDigsRequired() or nil)
                end

                if XToLevel.db.profile.averageDisplay.guildProgressType == 1 then
                    XToLevel.AverageFrameAPI[self.activeAPI]:SetGuildProgress (XToLevel.Player:GetGuildProgressAsPercentage(1))
                else
                    XToLevel.AverageFrameAPI[self.activeAPI]:SetGuildProgress (XToLevel.Player:GetGuildDailyProgressAsPercentage(1))
                end

                XToLevel.Player:UpdateTimer()
            end
            XToLevel.AverageFrameAPI[self.activeAPI]:Update()
        end
    elseif XToLevel.AverageFrameAPI[self.activeAPI] ~= nil then
        XToLevel.AverageFrameAPI[self.activeAPI]:Hide()
    end
end

do
	local function formatSeconds(seconds)
		return ("%ds"):format(seconds)
	end
	local function formatMinutes(seconds)
		local m = math.floor(seconds / 60 + 0.5)
		return ("%dm"):format(m)
	end
	local function formatHours(seconds)
		local h = math.floor(seconds / 3600 + 0.5)
		return ("%dh"):format(h)
	end
	local function formatDays(seconds)
		local d = math.floor(seconds / 86400 + 0.5)
		return ("%dd"):format(d)
	end
	function XToLevel.Average:UpdateTimer(secondsToLevel)
		if self.knownAPIs[XToLevel.db.profile.averageDisplay.mode] ~= nil then
			local short, long = "N/A", "N/A"
			if type(secondsToLevel) == "number" and secondsToLevel > 0 and secondsToLevel ~= math.huge then
				if secondsToLevel < 60 then
					short = formatSeconds(secondsToLevel)
					long = short
				elseif secondsToLevel < 3600 then
					short = formatMinutes(secondsToLevel)
					long = short.." "..formatSeconds(math.fmod(secondsToLevel, 60))
				elseif secondsToLevel < 86400 then
					short = formatHours(secondsToLevel)
					long = short.." "..formatMinutes(math.fmod(secondsToLevel, 3600))
				else
					short = formatDays(secondsToLevel)
					long = short.." "..formatHours(math.fmod(secondsToLevel, 86400))
				end
			end
			XToLevel.AverageFrameAPI[self.activeAPI]:SetTimer(short, long)
		end
	end
end

---
-- Aligns the boxes, placing the "child" on top of the "parent"
-- @param parent The box that marks where the child should be placed.
-- @param child The box that should be moved.
function XToLevel.Average:AlignBoxes(parent, child)
    if parent ~= child and parent ~= nil and child ~= nil then
	    local parentAPI = XToLevel.AverageFrameAPI[parent]
	    local childAPI = XToLevel.AverageFrameAPI[child]
	    childAPI:AlignTo(parentAPI)
	    self:SavePosition(child)
    end
end
