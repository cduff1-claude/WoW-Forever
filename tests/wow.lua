-- A small fake of the WoW client, for running addon code outside the game.
--
-- Frames keep real geometry (size and anchors), so tests can check where things end up:
-- GetLeft/GetRight/GetTop/GetBottom/GetCenter follow a frame's anchors back to UIParent.
-- Anything not modelled here is a no-op that returns nil, so code that only *calls* an API
-- (fonts, textures, backdrops...) runs without each one being written out.
--
-- It can't model what only the real client knows: drawing, taint and blocked actions,
-- secret values (beyond what a test sets up), or Forever's own quirks. Use /<addon> debug
-- in game for those.

local W = {}
W.time = 1000
W.combat = false
W.class = "DRUID"
W.powerType = 0          -- 0 mana, 3 energy, 1 rage
W.formID = nil           -- GetShapeshiftFormID()
W.power = { [0] = 1000, [1] = 0, [3] = 100 }
W.powerMax = { [0] = 2000, [1] = 100, [3] = 100 }
W.cursor = { 0, 0 }
W.frames = {}            -- every frame made, in order
W.printed = {}

----------------------------------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------------------------------

local Frame = {}
local FrameMT = {}

local function noop() end

ACTION_PREFIXES = { "Set", "Enable", "Disable", "Register", "Unregister", "Lock", "Unlock", "Start",
    "Stop", "Hook", "Clear", "Add", "Raise", "Lower", "Play", "Fade", "Highlight", "Unhighlight", "Clamp",
    "Ignore", "Reset", "Refresh", "Update", "Shrink", "Grow", "Mark", "Show", "Hide" }

FrameMT.__index = function(_, key)
    local method = Frame[key]
    if method then
        return method
    end
    -- Unknown action methods (SetBackdrop, EnableMouse, RegisterForDrag...) do nothing.
    -- Anything else is an unknown field, which is nil on a real frame too.
    if type(key) == "string" then
        for _, prefix in ipairs(ACTION_PREFIXES) do
            if key:sub(1, #prefix) == prefix then
                return noop
            end
        end
    end
    return nil
end

local function NewObject(kind, name, parent)
    local f = setmetatable({
        _kind = kind, _name = name, _parent = parent, _children = {}, _regions = {},
        _points = {}, _w = 0, _h = 0, _shown = true, _scripts = {}, _events = {},
        _attrs = {}, _level = 1,
    }, FrameMT)
    if parent and parent._children then
        table.insert(parent._children, f)
    end
    return f
end

local function Resolve(rel)
    if type(rel) == "string" then
        return _G[rel]
    end
    return rel
end

function Frame:GetName() return self._name end
function Frame:GetObjectType() return self._kind end
function Frame:GetParent() return self._parent end
function Frame:SetParent(p) self._parent = p end
function Frame:GetChildren() return unpack(self._children) end
function Frame:GetRegions() return unpack(self._regions) end

function Frame:SetWidth(w) self._w = w end
function Frame:SetHeight(h) self._h = h end
function Frame:SetSize(w, h) self._w, self._h = w, h or w end
function Frame:GetSize() return self:GetWidth(), self:GetHeight() end

-- Width/height: explicit size, or the span between two anchors (e.g. SetAllPoints).
function Frame:GetWidth()
    if #self._points >= 2 then
        local l, r = self:GetLeft(), self:GetRight()
        if l and r then return r - l end
    end
    return self._w
end
function Frame:GetHeight()
    if #self._points >= 2 then
        local t, b = self:GetTop(), self:GetBottom()
        if t and b then return t - b end
    end
    return self._h
end

function Frame:ClearAllPoints() self._points = {} end

-- SetPoint(point [, relativeTo [, relativePoint]] [, x, y])
function Frame:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y
    if type(a) == "number" then
        rel, relPoint, x, y = nil, point, a, b
    elseif type(b) == "number" then
        rel, relPoint, x, y = a, point, b, c
    else
        rel, relPoint, x, y = a, b or point, c, d
    end
    rel = Resolve(rel) or self._parent or _G.UIParent
    for i, p in ipairs(self._points) do
        if p[1] == point then
            table.remove(self._points, i)
            break
        end
    end
    table.insert(self._points, { point, rel, relPoint, x or 0, y or 0 })
end

function Frame:SetAllPoints(rel)
    rel = Resolve(rel) or self._parent
    self._points = {}
    self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end

function Frame:GetNumPoints() return #self._points end
function Frame:GetPoint(i)
    local p = self._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end

-- Where a named point of a frame sits, in screen coordinates (y up from the bottom).
local function PointXY(f, point)
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and r and t and b) then return nil end
    local x = point:find("LEFT") and l or point:find("RIGHT") and r or (l + r) / 2
    local y = point:find("TOP") and t or point:find("BOTTOM") and b or (t + b) / 2
    return x, y
end

-- Anchor positions resolved to screen coordinates: { [point] = {x, y} }.
local function Anchored(f)
    if f._root then return nil end
    local out = {}
    for _, p in ipairs(f._points) do
        local rx, ry = PointXY(p[2], p[3])
        if rx then out[p[1]] = { rx + p[4], ry + p[5] } end
    end
    return out
end

local function Edge(f, axis, side)
    if f._root then
        if axis == "x" then return side == "min" and 0 or f._w end
        return side == "min" and 0 or f._h
    end
    if f._busy then return nil end -- anchor loop
    f._busy = true
    local a = Anchored(f)
    f._busy = nil
    if not a or not next(a) then return nil end
    local size = axis == "x" and f._w or f._h
    if f._fillOf and axis == "x" then
        -- A status bar's fill texture: as wide as the bar times how full it is.
        local bar = f._fillOf
        local lo, hi, v = bar._min or 0, bar._max or 1, bar._value or 0
        local fraction = hi > lo and (v - lo) / (hi - lo) or 0
        size = math.max(0, math.min(1, fraction)) * bar:GetWidth()
    end
    local minName = axis == "x" and "LEFT" or "BOTTOM"
    local maxName = axis == "x" and "RIGHT" or "TOP"
    local lo, hi, mid
    for point, xy in pairs(a) do
        local v = axis == "x" and xy[1] or xy[2]
        if point:find(minName) then lo = v
        elseif point:find(maxName) then hi = v
        else mid = v end
    end
    if lo and hi then return side == "min" and lo or hi end
    if lo then return side == "min" and lo or lo + size end
    if hi then return side == "min" and hi - size or hi end
    if mid then return side == "min" and mid - size / 2 or mid + size / 2 end
end

function Frame:GetLeft() return Edge(self, "x", "min") end
function Frame:GetRight() return Edge(self, "x", "max") end
function Frame:GetBottom() return Edge(self, "y", "min") end
function Frame:GetTop() return Edge(self, "y", "max") end
function Frame:GetCenter()
    local l, r, t, b = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
    if l and r and t and b then return (l + r) / 2, (t + b) / 2 end
end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetScale() return 1 end

function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:SetShown(v) self._shown = v and true or false end
function Frame:IsShown() return self._shown end
function Frame:IsVisible()
    local f = self
    while f do
        if not f._shown then return false end
        f = f._parent
    end
    return true
end

function Frame:SetScript(name, fn) self._scripts[name] = fn end
function Frame:GetScript(name) return self._scripts[name] end
function Frame:HookScript(name, fn)
    local old = self._scripts[name]
    self._scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function Frame:RegisterEvent(e) self._events[e] = true end
function Frame:UnregisterEvent(e) self._events[e] = nil end
function Frame:UnregisterAllEvents() self._events = {} end
function Frame:IsEventRegistered(e) return self._events[e] == true end

function Frame:SetFrameLevel(n) self._level = n end
function Frame:SetAlpha(a) self._alpha = a end
function Frame:GetAlpha() return self._alpha or 1 end
function Frame:GetFrameLevel() return self._level end
function Frame:GetFrameStrata() return self._strata or "MEDIUM" end
function Frame:SetFrameStrata(s) self._strata = s end
function Frame:IsMovable() return self._movable end
function Frame:SetMovable(v) self._movable = v end

function Frame:SetAttribute(k, v) self._attrs[k] = v end
function Frame:GetAttribute(k) return self._attrs[k] end

function Frame:SetChecked(v) self._checked = v and true or false end
function Frame:GetChecked() return self._checked end
function Frame:Click(button) local fn = self._scripts.OnClick if fn then fn(self, button or "LeftButton", false) end end

-- Status bars
function Frame:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function Frame:GetMinMaxValues() return self._min or 0, self._max or 1 end
function Frame:SetValue(v, interpolation) self._value, self._interp = v, interpolation end
function Frame:GetValue() return self._value end
function Frame:GetStatusBarTexture()
    if not self._barTexture then
        self._barTexture = self:CreateTexture()
        self._barTexture._fillOf = self
        self._barTexture:SetPoint("TOPLEFT", self, "TOPLEFT")
        self._barTexture:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT")
    end
    return self._barTexture
end
function Frame:SetStatusBarTexture(t)
    local tex = self:GetStatusBarTexture()
    if type(t) == "string" or type(t) == "number" then tex:SetTexture(t) end
    return tex
end
function Frame:SetStatusBarColor(r, g, b, a) self:GetStatusBarTexture()._color = { r, g, b, a or 1 } end
function Frame:GetStatusBarColor()
    local c = self:GetStatusBarTexture()._color or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end
function Frame:SetClipsChildren(v) self._clips = v and true or false end

-- Animation groups: record whether they're playing; their animations accept any setting.
local function Anything()
    return setmetatable({}, { __index = function() return noop end })
end
function Frame:CreateAnimationGroup()
    local group = { _playing = false, _anims = {}, _plays = 0 }
    function group:Play() self._playing = true; self._plays = (self._plays or 0) + 1 end
    function group:Stop() self._playing = false end
    function group:IsPlaying() return self._playing end
    function group:CreateAnimation(kind)
        local a = Anything()
        table.insert(self._anims, a)
        return a
    end
    return setmetatable(group, { __index = function() return noop end })
end

-- Regions (textures, font strings) share the frame methods.
function Frame:CreateTexture(name)
    local t = NewObject("Texture", name, self)
    table.remove(self._children) -- regions aren't child frames
    table.insert(self._regions, t)
    if name then _G[name] = t end
    return t
end
function Frame:CreateFontString(name)
    local t = self:CreateTexture(name)
    t._kind = "FontString"
    return t
end
function Frame:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function Frame:SetVertexColor(r, g, b, a) self._color = { r, g, b, a } end
function Frame:SetTexture(t) self._texture, self._atlas = t, nil end
function Frame:GetTexture() return self._texture end
function Frame:SetAtlas(a) self._atlas, self._texture = a, nil end
function Frame:GetAtlas() return self._atlas end
function Frame:SetText(t) self._text = t end
function Frame:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function Frame:GetText() return self._text end
function Frame:GetStringWidth() return #(tostring(self._text or "")) * 6 end
function Frame:GetFont() return "Fonts\\ARIALN.TTF", 10, "" end

function CreateFrame(kind, name, parent, template)
    local f = NewObject(kind or "Frame", name, parent)
    f._template = template
    if name then _G[name] = f end
    -- Named parts Blizzard's templates create, which addons look up by name.
    if name and type(template) == "string" then
        if template:find("CheckButton") then
            f.Text = f:CreateFontString(name .. "Text")
        elseif template:find("Slider") then
            f:CreateFontString(name .. "Low")
            f:CreateFontString(name .. "High")
            f.Text = f:CreateFontString(name .. "Text")
        end
    end
    table.insert(W.frames, f)
    return f
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent._root = true
UIParent:SetSize(1920, 1080)

Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetSize(140, 140)
Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)

GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)

----------------------------------------------------------------------------------------------
-- Events and time
----------------------------------------------------------------------------------------------

-- Fire an event at every frame registered for it.
function W.Fire(event, ...)
    for _, f in ipairs(W.frames) do
        if f._events[event] and f._scripts.OnEvent then
            f._scripts.OnEvent(f, event, ...)
        end
    end
end

W.timers = {}
C_Timer = {
    After = function(delay, fn) table.insert(W.timers, { due = W.time + delay, fn = fn }) end,
}
C_Texture = { GetAtlasInfo = function(name) return { file = name } end }

local function RunTimers()
    local i = 1
    while i <= #W.timers do
        local t = W.timers[i]
        if t.due <= W.time + 1e-9 then
            table.remove(W.timers, i)
            t.fn()
        else
            i = i + 1
        end
    end
end

-- Move time on, running OnUpdate scripts and C_Timer callbacks in small steps as the client would.
function W.Advance(seconds, step)
    step = step or 0.05
    local done = 0
    while done < seconds - 1e-9 do
        local dt = math.min(step, seconds - done)
        W.time = W.time + dt
        done = done + dt
        for _, f in ipairs(W.frames) do
            local fn = f._scripts.OnUpdate
            if fn then fn(f, dt) end
        end
        RunTimers()
    end
end

----------------------------------------------------------------------------------------------
-- API
----------------------------------------------------------------------------------------------

function GetTime() return W.time end
function InCombatLockdown() return W.combat end
function UnitAffectingCombat() return W.combat end
function UnitClass() return W.class:sub(1, 1) .. W.class:sub(2):lower(), W.class end
function UnitName(unit) return unit == "player" and "Roam" or unit end
function UnitPowerType() return W.powerType, ({ [0] = "MANA", [1] = "RAGE", [3] = "ENERGY" })[W.powerType] end
function UnitPower(_, t) return W.power[t or W.powerType] end
function UnitPowerMax(_, t) return W.powerMax[t or W.powerType] end
function UnitIsUnit(a, b) return a == b end
W.health, W.healthMax = 989, 989
W.target = false
W.casting, W.channel = nil, nil -- { name=, startMS=, endMS= }
function UnitExists(unit) if unit == "target" then return W.target end return true end
function UnitHealth() return W.health end
function UnitHealthMax() return W.healthMax end
-- The target: W.target is true/false; W.enemy picks hostile or friendly; W.range[spell] is the
-- game's range answer (true / false / nil) for that spell name on the target.
W.enemy, W.targetDead, W.range = true, false, {}
function UnitIsDead(unit) return unit == "target" and W.targetDead or false end
function UnitIsDeadOrGhost(unit) return unit == "target" and W.targetDead or false end
function UnitCanAttack(_, unit) return unit == "target" and W.target and W.enemy or false end
function UnitIsFriend(_, unit) return unit == "target" and W.target and not W.enemy or false end
function UnitCanAssist(_, unit) return unit == "target" and W.target and not W.enemy or false end
function UnitPlayerControlled() return false end
function UnitCastingInfo() local c = W.casting if c then return c.name, c.name, 136085, c.startMS, c.endMS end end
function UnitChannelInfo() local c = W.channel if c then return c.name, c.name, 136085, c.startMS, c.endMS end end
function GetShapeshiftFormID() return W.formID end
function GetShapeshiftForm() return 0 end
function GetNumShapeshiftForms() return 0 end
function GetCursorPosition() return W.cursor[1], W.cursor[2] end
function GetMinimapShape() return "ROUND" end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
function GetRealmName() return "Test Realm" end
function IsStealthed() return false end
function IsPlayerSpell() return true end
function IsSpellKnown() return true end
function GetCVar() return "0" end
function GetCVarBool() return false end
function hooksecurefunc(a, b, c)
    local t, name, fn = a, b, c
    if type(a) == "string" then t, name, fn = _G, a, b end
    local old = t[name]
    t[name] = function(...)
        local r = { old(...) }
        fn(...)
        return unpack(r)
    end
end
issecretvalue = function() return false end

Enum = { PowerType = { Mana = 0, Rage = 1, Energy = 3 },
    StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 } }

-- Spell costs: tests fill W.spellCosts[spellID or name] = { {type=0, name="MANA", cost=50} }
W.spellCosts = {}
C_Spell = {
    GetSpellPowerCost = function(id) return W.spellCosts[id] end,
    GetSpellName = function(id) return "Spell " .. tostring(id) end,
    IsSpellInRange = function(spell) return W.range[spell] end,
    GetSpellInfo = function(spell) return { name = spell, spellID = 1 } end,
}
C_UnitAuras = {}
C_AddOns = { GetAddOnMetadata = function() return nil end }

Settings = {
    RegisterCanvasLayoutCategory = function(_, name) return { GetID = function() return name end } end,
    RegisterAddOnCategory = noop,
    RegisterCanvasLayoutSubcategory = function(_, _, name) return { GetID = function() return name end } end,
    OpenToCategory = noop,
}

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(W.printed, table.concat(parts, " "))
end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
function CopyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
    return c
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s, n)
    local out, start = {}, 1
    while true do
        if n and #out == n - 1 then break end
        local i, j = s:find(sep, start, true)
        if not i then break end
        out[#out + 1] = s:sub(start, i - 1)
        start = j + 1
    end
    out[#out + 1] = s:sub(start)
    return unpack(out)
end
strlower, strupper, strfind, strsub, format = string.lower, string.upper, string.find, string.sub, string.format
tinsert, tremove = table.insert, table.remove
SlashCmdList = {}
StaticPopupDialogs = {}

-- Blizzard's old dropdown menus: tests can open one with W.OpenDropdown(frame) and pick from W.menu.
W.menu = {}
function UIDropDownMenu_Initialize(frame, init) frame._init = init end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) table.insert(W.menu, info) end
function UIDropDownMenu_SetText(frame, text) frame._ddText = text end
function UIDropDownMenu_GetText(frame) return frame._ddText end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue(frame, v) frame._ddValue = v end
function W.OpenDropdown(frame)
    W.menu = {}
    frame._init(frame, 1)
    return W.menu
end
function W.Pick(frame, value)
    for _, info in ipairs(W.OpenDropdown(frame)) do
        if info.value == value then info.func(info) return true end
    end
    return false
end
function StaticPopup_Show() end
function StaticPopup_Hide() end
UISpecialFrames = {}
SOUNDKIT = {}
function PlaySound() end
function PlaySoundFile() end

----------------------------------------------------------------------------------------------
-- Loading addon files
----------------------------------------------------------------------------------------------

-- Run one addon file the way the client does: with (addonName, namespace) as its "...".
-- `extra` is appended to the file's source, so a test can reach the file's local variables.
function W.Load(path, addonName, ns, extra)
    local fh = assert(io.open(path, "rb"))
    local src = fh:read("*a"):gsub("\r\n", "\n"):gsub("^\239\187\191", "")
    fh:close()
    if extra then src = src .. "\n" .. extra end
    local chunk = assert(loadstring(src, "@" .. path))
    chunk(addonName, ns)
    return ns
end

-- Run a slash command as if typed, e.g. W.Slash("/fseq minimap").
function W.Slash(text)
    local cmd, rest = text:match("^(%S+)%s*(.-)$")
    for key, fn in pairs(SlashCmdList) do
        for i = 1, 9 do
            local alias = _G["SLASH_" .. key .. i]
            if alias and alias:lower() == cmd:lower() then
                return fn(rest)
            end
        end
    end
    error("no slash command " .. cmd)
end

----------------------------------------------------------------------------------------------
-- Checks
----------------------------------------------------------------------------------------------

-- Width of a region that is actually drawn: its own span, cut down by every ancestor
-- that clips its children. 0 if it or an ancestor is hidden, or fully transparent.
function W.VisibleWidth(region)
    local l, r = region:GetLeft(), region:GetRight()
    if not (l and r) or not region:IsVisible() then return 0 end
    if region._color and region._color[4] == 0 then return 0 end
    local p = region._parent
    while p do
        if p._clips then
            local pl, pr = p:GetLeft(), p:GetRight()
            if not (pl and pr) then return 0 end
            l, r = math.max(l, pl), math.min(r, pr)
        end
        p = p._parent
    end
    return math.max(0, r - l)
end

-- Every texture under a frame, however deep.
function W.Textures(frame, out)
    out = out or {}
    for _, r in ipairs(frame._regions) do table.insert(out, r) end
    for _, c in ipairs(frame._children) do W.Textures(c, out) end
    return out
end

W.passed, W.failed = 0, 0

function W.Check(ok, label)
    if ok then
        W.passed = W.passed + 1
        io.write("  ok    ", label, "\n")
    else
        W.failed = W.failed + 1
        io.write("  FAIL  ", label, "\n")
    end
end

function W.Near(a, b, label, tolerance)
    local ok = type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tolerance or 0.01)
    W.Check(ok, string.format("%s (got %s, want %s)", label, tostring(a), tostring(b)))
end

function W.Done()
    io.write(string.format("%d passed, %d failed\n", W.passed, W.failed))
    os.exit(W.failed == 0 and 0 or 1)
end

return W
