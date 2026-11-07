-- DruidSequence minimap button: click to open the settings (the editor), drag to move it
-- around the minimap. Its angle and whether it's hidden are kept in ForeverSequencesDB.minimap
-- (account-wide). /fseq minimap shows or hides it.

local _, ns = ...

local ICON = "Interface\\AddOns\\DruidSequence\\MinimapIcon"
local DEFAULT_ANGLE = 200 -- degrees, counter-clockwise from the right (lower left of the minimap)

local button

local function GetSettings()
    ForeverSequencesDB = ForeverSequencesDB or {}
    local s = ForeverSequencesDB.minimap
    if type(s) ~= "table" then
        s = {}
        ForeverSequencesDB.minimap = s
    end
    if type(s.angle) ~= "number" then
        s.angle = DEFAULT_ANGLE
    end
    return s
end

local function Place()
    local angle = math.rad(GetSettings().angle)
    -- Sit just outside a round minimap's edge. For a square minimap (some addons make it
    -- square), push towards the corners so the button stays on the frame's edge.
    local radius = (Minimap:GetWidth() / 2) + 5
    local x, y = math.cos(angle), math.sin(angle)
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local scale = 1 / math.max(math.abs(x), math.abs(y))
        x, y = x * scale, y * scale
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    GetSettings().angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    Place()
end

local function Create()
    button = CreateFrame("Button", "DruidSequenceMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function()
        if ns.ToggleEditor then
            ns.ToggleEditor()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", DragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("DruidSequence")
        GameTooltip:AddLine("Click to open the settings.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move this button.", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function Refresh()
    if not button then
        return
    end
    if GetSettings().hide then
        button:Hide()
    else
        Place()
        button:Show()
    end
end

-- Called by /fseq minimap.
function ns.ToggleMinimapButton()
    local s = GetSettings()
    s.hide = not s.hide
    Refresh()
    return not s.hide
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    -- Saved variables are loaded by now. The rest of the addon only runs for druids.
    local _, class = UnitClass("player")
    if class ~= "DRUID" then
        return
    end
    Create()
    Refresh()
end)
