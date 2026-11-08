-- DruidFrame: rage decay marker. After you leave combat in Bear Form, a marker sweeps along the
-- rage bar from right to left (the 5-second-rule marker in reverse) and reaches the left edge
-- when rage starts to decay.
--
-- How long that takes isn't something the client tells us, and rage is secret, so the delay is
-- measured: after combat ends, the first rage change (UNIT_POWER_FREQUENT) is the decay
-- starting. Each measurement is saved and blended into the delay used next time.

local _, ns = ...

local D = {}
ns.RageDecay = D

local GUESS = 2           -- seconds, until the first measurement
local MIN_DELAY, MAX_DELAY = 0.3, 20
local IGNORE_FIRST = 0.25 -- rage events right as combat ends aren't the decay
local UPDATE_INTERVAL = 0.03

local function DB()
    return DruidForeverManabarPlusDB or {}
end

function D.Delay()
    local delay = DB().rageDecayDelay
    if type(delay) == "number" and delay >= MIN_DELAY then
        return delay
    end
    return GUESS
end

-- DruidFrame's rage bar, while it's shown.
function D.Bar()
    local R = ns.Resource
    if not (R and R.frame and R.frame:IsShown() and R.power and R.power:IsShown()) then
        return nil
    end
    local _, token = UnitPowerType("player")
    if token == "RAGE" then
        return R.power
    end
end

function D.Ensure(bar)
    if D.frame then
        return
    end
    local frame = CreateFrame("Frame", nil, bar)
    frame:SetAllPoints(bar)
    frame:Hide()
    local marker = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    marker:SetColorTexture(1, 1, 1, 0.95)
    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\ARIALN.TTF", 10, "")
    text:SetTextColor(1, 1, 1, 1)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    text:SetPoint("LEFT", frame, "RIGHT", 3, 0)
    D.frame, D.marker, D.text = frame, marker, text
end

function D.Stop()
    D.endTime = nil
    if D.ticker then
        D.ticker:SetScript("OnUpdate", nil)
    end
    if D.frame then
        D.frame:Hide()
    end
end

function D.Update()
    local db = DB()
    local bar = D.Bar()
    local remaining = D.endTime and (D.endTime - GetTime()) or 0
    if not (db.rageDecay and bar and remaining > 0) then
        if D.frame then
            D.frame:Hide()
        end
        if remaining <= 0 then
            D.Stop()
        end
        return
    end
    D.Ensure(bar)
    local frame = D.frame
    frame:SetFrameStrata(bar:GetFrameStrata())
    frame:SetFrameLevel(bar:GetFrameLevel() + 10)
    frame:Show()
    local width = db.fsrWidth or 2
    local progress = math.min(1, math.max(0, remaining / D.duration))
    D.marker:SetWidth(width)
    D.marker:SetHeight(frame:GetHeight() + 4)
    D.marker:ClearAllPoints()
    D.marker:SetPoint("CENTER", frame, "LEFT", (width / 2) + progress * math.max(0, frame:GetWidth() - width), 0)
    if db.fsrText then
        D.text:SetText(string.format("%.1f", remaining))
        D.text:Show()
    else
        D.text:Hide()
    end
end

function D.Start()
    D.duration = D.Delay()
    D.endTime = GetTime() + D.duration
    D.ticker = D.ticker or CreateFrame("Frame")
    local elapsed = 0
    D.ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= UPDATE_INTERVAL then
            elapsed = 0
            D.Update()
        end
    end)
    D.Update()
end

-- The first rage change after combat: decay has started. Save how long it took.
function D.RageChanged()
    if not D.combatEnded then
        return
    end
    local t = GetTime() - D.combatEnded
    if t < IGNORE_FIRST then
        return
    end
    D.combatEnded = nil
    if t <= MAX_DELAY then
        local db = DB()
        local old = db.rageDecayDelay
        local measured = math.max(MIN_DELAY, t)
        if type(old) == "number" and old >= MIN_DELAY then
            db.rageDecayDelay = (old + measured) / 2
        else
            db.rageDecayDelay = measured
        end
        D.lastMeasured = t
    end
    D.Stop()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_POWER_FREQUENT",
    "UPDATE_SHAPESHIFT_FORM" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, unit, powerToken)
    if event == "PLAYER_REGEN_ENABLED" then
        if D.Bar() then
            D.combatEnded = GetTime()
            if DB().rageDecay then
                D.Start()
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        D.combatEnded = nil
        D.Stop()
    elseif event == "UNIT_POWER_FREQUENT" then
        if unit == "player" and powerToken == "RAGE" then
            D.RageChanged()
        end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        -- Out of Bear Form there's no rage to decay (and nothing to measure).
        if D.endTime and not D.Bar() then
            D.combatEnded = nil
            D.Stop()
        end
    end
end)

function D.Debug()
    local db = DB()
    print("|cff55ff55DruidFrame rage decay|r on:", tostring(db.rageDecay),
        "| delay used:", string.format("%.2fs", D.Delay()),
        type(db.rageDecayDelay) == "number" and db.rageDecayDelay >= MIN_DELAY and "(measured)" or "(a guess, not measured yet)",
        "| last measured:", D.lastMeasured and string.format("%.2fs", D.lastMeasured) or "none this session",
        "| waiting for decay:", tostring(D.combatEnded ~= nil))
end
