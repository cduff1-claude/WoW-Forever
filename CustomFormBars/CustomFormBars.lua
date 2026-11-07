-- FormBars: pin the main action bar (ActionButton1-12) to a chosen page per form.
--
-- Blizzard's main bar picks its page from GetBonusBarOffset(), which can go stale
-- (caster bar while in cat/bear). Instead, a secure state driver keyed on the actual
-- shapeshift form writes the page into each button's "actionpage" attribute, which
-- Blizzard's buttons honour for both clicks and icons, so a stale bonus bar value
-- no longer matters. The page is rewritten whenever the form changes, even in combat.

local ADDON = ...

if select(2, UnitClass("player")) ~= "DRUID" then return end

-- Druid forms matched by spell ID, with their default main-bar page (nil = page 1).
local FORMS = {
	{ key = "cat",     ids = { 768 },        page = 7 },
	{ key = "bear",    ids = { 5487, 9634 }, page = 9 },
	{ key = "moonkin", ids = { 24858 },      page = 10 },
	{ key = "travel",  ids = { 783 } },
	{ key = "aquatic", ids = { 1066 } },
	-- Not a form: Cat Form while Prowling (the [stealth] conditional). Page 8 matches
	-- Blizzard's layout. Set it to Cat's page to keep one bar for both.
	{ key = "prowl",   stealthOf = "cat",    page = 8 },
}

local formBySpell, formByKey = {}, {}
for _, f in ipairs(FORMS) do
	formByKey[f.key] = f
	for _, id in ipairs(f.ids or {}) do formBySpell[id] = f end
end

local db -- FormBarsDB: { enabled = bool, pages = { [formKey] = page } }

local function PageFor(key)
	return db.pages[key] or formByKey[key].page or 1
end

local function Print(...) print("|cff66ccffFormBars|r:", ...) end

------------------------------------------------------------------------------
-- Secure header: owns the state driver and sets the page on the main bar.
------------------------------------------------------------------------------
local header = CreateFrame("Frame", "FormBarsHeader", UIParent, "SecureHandlerStateTemplate")
local buttons = {}
for i = 1, 12 do
	buttons[i] = _G["ActionButton" .. i]
	header:SetFrameRef("b" .. i, buttons[i])
end
header:Execute([[
	buttons = newtable()
	for i = 1, 12 do buttons[i] = self:GetFrameRef("b" .. i) end
]])
header:SetAttribute("setpage", [[
	local page = ...
	for i = 1, 12 do buttons[i]:SetAttribute("actionpage", page) end
]])

-- The server can take seconds to confirm a form change. A macro /click on a
-- FormBars<Form> button shows that form's page immediately, then ignores exactly
-- one drop to caster (the cancel half of a powershift) until the form comes back.
-- (No timers: GetTime isn't available to secure snippets on this client.)
--   optState "armed"   = clicked, expecting the drop to caster
--   optState "waiting" = drop ignored, expecting the form to return
--   curPage            = the page the driver currently says is correct
-- Driver states are page numbers, except caster, which is CASTER_STATE so it can't be
-- confused with another form that also uses page 1 (e.g. Travel).
local CASTER_STATE = 1001
header:SetAttribute("_onstate-page", [[
	local state = tonumber(newstate)
	local isCaster = state == 1001 -- CASTER_STATE (snippets can't see Lua locals)
	local page = isCaster and 1 or state
	curPage = page
	if optState == "armed" and isCaster and optPage ~= 1 then
		optState = "waiting"
		return
	end
	optState = nil
	self:RunAttribute("setpage", page)
]])
header:SetAttribute("instant", [[
	optPage = ...
	optState = "armed"
	self:RunAttribute("setpage", optPage)
]])

-- If the shift never happened, drop the hold 5s after the last click, once out of
-- combat. Only the newest timer counts, and leaving combat restarts it.
local holdTimer
local function ClearHoldLater()
	if holdTimer then holdTimer:Cancel() end
	holdTimer = C_Timer.NewTimer(5, function()
		holdTimer = nil
		if InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED restarts us
		header:Execute([[
			if optState then
				optState = nil
				self:RunAttribute("setpage", curPage)
			end
		]])
	end)
end

-- Macro /click targets: FormBarsCat, FormBarsBear, FormBarsMoonkin, ...
local clickButtons = {}
for _, f in ipairs(FORMS) do
	if not f.stealthOf then -- no button for Prowl: it isn't a form and switches quickly
		local btn = CreateFrame("Button", "FormBars" .. f.key:gsub("^%l", strupper), UIParent, "SecureActionButtonTemplate")
		btn:RegisterForClicks("AnyUp", "AnyDown")
		header:WrapScript(btn, "OnClick", [[
			local page = self:GetAttribute("fbpage")
			if page then owner:RunAttribute("instant", page) end
		]])
		btn:HookScript("OnClick", ClearHoldLater)
		clickButtons[f.key] = btn
	end
end

-- Refresh the icons whenever the page changes.
for _, b in ipairs(buttons) do
	b:HookScript("OnAttributeChanged", function(self, name)
		if name == "actionpage" then self:UpdateAction() end
	end)
end

------------------------------------------------------------------------------
-- State driver: macro conditionals that evaluate to the page number.
------------------------------------------------------------------------------
local function BuildDriver()
	local parts = {
		"[overridebar]" .. GetOverrideBarIndex(),
		"[vehicleui]" .. GetVehicleBarIndex(),
		"[shapeshift]" .. GetTempShapeshiftBarIndex(),
		"[bonusbar:5]11", -- possess / mind control
	}
	-- Manual paging (Shift+number, bar arrows) still works.
	for p = 2, 6 do parts[#parts + 1] = ("[bar:%d]%d"):format(p, p) end

	for i = 1, GetNumShapeshiftForms() do
		local _, _, _, spellID = GetShapeshiftFormInfo(i)
		local f = formBySpell[spellID]
		if f then
			-- Stealth variants (Prowl) go first so they win over the plain form.
			for _, s in ipairs(FORMS) do
				if s.stealthOf == f.key then
					parts[#parts + 1] = ("[form:%d,stealth]%d"):format(i, PageFor(s.key))
				end
			end
			parts[#parts + 1] = ("[form:%d]%d"):format(i, PageFor(f.key))
		end
	end

	parts[#parts + 1] = "[noform]" .. CASTER_STATE
	parts[#parts + 1] = "1" -- unrecognised form
	return table.concat(parts, ";")
end

local pending = false -- a change arrived during combat
local function Apply()
	if InCombatLockdown() then pending = true return end
	pending = false
	UnregisterStateDriver(header, "page")
	header:Execute([[ optState = nil ]])
	for key, btn in pairs(clickButtons) do
		btn:SetAttribute("fbpage", db.enabled and PageFor(key) or nil)
	end
	if db.enabled then
		-- Clear the old state so registering always counts as a change and the page
		-- gets written, even if the form didn't change (e.g. /fb off then on).
		header:SetAttribute("state-page", nil)
		RegisterStateDriver(header, "page", BuildDriver())
	else
		header:Execute([[ self:RunAttribute("setpage", nil) ]])
	end
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------
header:RegisterEvent("ADDON_LOADED")
header:RegisterEvent("PLAYER_LOGIN")
header:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
header:RegisterEvent("PLAYER_REGEN_ENABLED")
header:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		FormBarsDB = FormBarsDB or {}
		db = FormBarsDB
		db.pages = db.pages or {}
		if db.enabled == nil then db.enabled = true end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then Apply() end
		ClearHoldLater() -- a hold left over from a failed shift in combat
	elseif db then
		Apply()
	end
end)

------------------------------------------------------------------------------
-- /fb
------------------------------------------------------------------------------
local function ListSettings()
	Print(db.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r")
	for _, f in ipairs(FORMS) do
		Print(("  %s -> %d"):format(f.key, PageFor(f.key)))
	end
end

SLASH_FORMBARS1 = "/formbars"
SLASH_FORMBARS2 = "/fb"
SlashCmdList.FORMBARS = function(msg)
	local cmd, arg = strsplit(" ", strlower(strtrim(msg)), 2)
	if cmd == "" then
		ListSettings()
		Print("Usage: /fb <form> <page 1-10 | default>, /fb on|off, /fb status")
	elseif cmd == "on" or cmd == "off" then
		db.enabled = (cmd == "on")
		Apply()
		ListSettings()
	elseif cmd == "status" then
		Print(("form=%s bonusbar=%s page=%s"):format(GetShapeshiftForm(), GetBonusBarOffset(),
			tostring(ActionButton1:GetAttribute("actionpage"))))
	elseif formByKey[cmd] then
		local page = tonumber(arg)
		if arg == "default" then
			db.pages[cmd] = nil
		elseif page and page % 1 == 0 and page >= 1 and page <= 10 then
			db.pages[cmd] = page
		else
			Print("page must be 1-10 or 'default'")
			return
		end
		Apply()
		Print(("%s -> %d"):format(cmd, PageFor(cmd)))
	else
		Print("unknown form '" .. cmd .. "'. /fb to list forms.")
	end
	if pending then Print("will apply after combat") end
end
