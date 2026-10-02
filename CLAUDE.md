# WoW Forever addons

Personal World of Warcraft addons for **WoW Forever**. Each addon lives in its own top-level folder
(`<Name>/<Name>.toc` + `<Name>.lua`) and has a section in `README.md`.

## What WoW Forever is

- A reimplementation of **Classic (vanilla) gameplay inside the current Retail client/server**, with some
  changes of its own. `/dump GetBuildInfo()` returns `1.60.1`, build `70009`.
- **The addon API is Retail's, including the Midnight expansion's restrictions.** Write against Retail/Midnight
  behaviour. Don't rely on Classic-client addon behaviour or APIs where Retail is known to differ.
- Abilities, ranges and levels mostly match Classic values. Forever's own changes found so far:
  - Faerie Fire is a single ability (no separate Feral talent), 30 yd in and out of forms.
  - Druids get a Cat Form charge as well as the Bear one; both are called **Feral Charge** (8-25 yd).
  - Druids have an out-of-combat resurrection called **Revive**, 30 yd.
  - Growl has the same range as Bash (melee).
  
  Check with the user before relying on any other Classic value that matters.

## Addon behaviour learned on Forever

- **TOC:** use the client's real interface number, currently `## Interface: 16001`. A beta update started
  marking addons with the old "always newer" `99999` as *Incompatible* (which can't be overridden).
  - If addons show as incompatible after a patch, ask the user to run `/dump select(4, GetBuildInfo())` in
    game and use that number.
  - Some `.toc` files in the repo may still say `99999`. Change them to the current number whenever you next
    edit that addon (the user has already fixed their installed copies).
  - Give each addon its own `SavedVariables`.
- **Secret values (Midnight):** some values come back "secret" and can't be compared or used in maths in Lua.
  - Always guard with `issecretvalue and issecretvalue(v)` before comparing, and have a fallback.
  - Player mana is secret. `StatusBar` widgets accept secret values, so do comparisons visually with status
    bars and anchoring (see `DruidForeverManabarPlus.lua`), not in Lua.
  - `UnitAffectingCombat("player")` is readable.
  - Whether a friendly unit's health or combat state is readable is unconfirmed; guard it.
- **Range checks** (`C_Spell.IsSpellInRange`) return `true` / `false` / `nil`:
  - `nil` means no answer. Treat it as "unknown", never as "in range".
  - Spells the character **hasn't learned return `nil`**, even if they'd be in range. Spells from other
    classes also return `nil`. So range rules only start working once the spell is learned.
  - On-next-swing abilities (e.g. **Maul**, and by extension Heroic Strike, Raptor Strike, Cleave) can report
    "in range" at any distance. Never use them for range checks; use a normal melee attack (Bash, Claw,
    Growl, ...).
  - There is no API for the actual distance to a target. Retail blocks `CheckInteractDistance` and item range
    checks on hostile units in combat, so range logic has to be built from spell yes/no answers.
- **Shapeshift forms:** use `GetShapeshiftFormID()`, not the stance-bar index (the index shifts with learned
  forms). Cat = 1, Travel = 3, Aquatic = 4, Bear/Dire Bear = 5.
- **Stealth / combat:** `IsStealthed()` and `PLAYER_REGEN_ENABLED` / `PLAYER_REGEN_DISABLED` are available.
- **Options panels:**
  - Register with `Settings.RegisterCanvasLayoutCategory(panel, name)` + `Settings.RegisterAddOnCategory`.
  - Open from a slash command with `pcall(Settings.OpenToCategory, category:GetID())`. See the existing addons.
  - `UICheckButtonTemplate`, `OptionsSliderTemplate`, `InputBoxTemplate` and `BackdropTemplate` all work.

## Working conventions

- The user tests in game and reports back. Give every addon a `/<command> debug` that prints the raw values
  the logic depends on (range answers, form ID, secret/readable flags). That makes unknown Forever
  behaviour quick to confirm.
- Hand the user the finished addon as a zip of its folder, and update `README.md` alongside code changes.
- The dev container has no Lua interpreter. Syntax-check with Python instead:
  `pip install luaparser` then `python3 -c "from luaparser import ast; ast.parse(open('X.lua').read())"`.
