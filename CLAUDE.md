# WoW Forever addons

Personal World of Warcraft addons for **WoW Forever**. Each addon lives in its own top-level folder
(`<Name>/<Name>.toc` + `<Name>.lua`) and has a section in `README.md`.

## What WoW Forever is

- A reimplementation of **Classic (vanilla) gameplay inside the current Retail client/server**, with some
  changes of its own. `/dump GetBuildInfo()` returns `1.60.1`, build `70009`.
- **The addon API is Retail's, including the Midnight expansion's restrictions.** Write against Retail/Midnight
  behaviour. Don't rely on Classic-client addon behaviour or APIs where Retail is known to differ.
- Abilities, ranges and levels mostly match Classic values. Forever's own changes found so far:
  - Faerie Fire is a single ability; the Feral version is not a separate talent.
  - Druids get a Cat Form charge as well as the Bear Feral Charge.
  - Druids have an out-of-combat resurrection called **Revive**, with the same range as heals.
  - Growl has the same range as Bash (melee).
  
  Check with the user before relying on any other Classic value that matters.

## Addon behaviour learned on Forever

- **TOC:** always `## Interface: 99999`, so the client never flags these personal addons as out of date.
  Give each addon its own `SavedVariables`.
- **Secret values (Midnight):** some values come back "secret" and can't be compared or used in maths in Lua.
  - Always guard with `issecretvalue and issecretvalue(v)` before comparing, and have a fallback.
  - Player mana (`UnitPower`) is secret, but `UnitPowerMax` and `UnitPowerType("player")` are readable.
  - `C_Spell.GetSpellPowerCost(spellID)` returns a **readable** cost that already includes talent/gear
    modifiers, so thresholds can be built from spell costs even though mana itself is secret.
  - The mana cost of the spell being cast: take the spellID from `UNIT_SPELLCAST_START`
    (unit, castGUID, spellID) and look it up with `GetSpellPowerCost`. Clear it on
    STOP / FAILED / INTERRUPTED / SUCCEEDED, but only when the castGUID matches.
  - `StatusBar` widgets accept secret values, so do comparisons visually with status bars and anchoring,
    not in Lua (confirmed working in game; see `DruidForeverManabarPlus.lua`):
    - A hidden `StatusBar` with range `[threshold - 1, threshold]` and the secret value as its value is a
      binary switch: its fill is either empty or full width.
    - Frames with `SetClipsChildren(true)`, anchored to `GetStatusBarTexture()` edges, turn that switch into
      visible regions. Nested clips intersect.
    - Keep colour layers mutually exclusive. A translucent layer stacked over another lets the lower one
      show through.
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
- **Spell IDs** are Classic's (e.g. Bear Form 5487, Cat 768, Travel 783).
- **Player Frame mana bar:**
  - Path: `PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar`, falling back to
    `PlayerFrameManaBar`. Child frames of it work fine.
  - Re-anchor to its `GetStatusBarTexture()` when the power type changes; Blizzard may swap the texture.
  - Translucent overlays blend with Blizzard's blue texture and look washed out. Use stronger colours and
    higher alpha than expected: around 0.75 for pale colours and 0.9 for bold ones.
- **SavedVariables** load *after* the addon's Lua runs. Re-read the settings table at `PLAYER_LOGIN`, and
  refresh options-panel widgets in the panel's `OnShow`. Otherwise settings never persist.
- **Frame positions:** the client's own memory of dragged frames (layout cache / `SetUserPlaced`) survives
  `/reload` but **not a client restart**. Save `frame:GetPoint(1)` to SavedVariables on drag stop, call
  `SetUserPlaced(false)`, and restore with `SetPoint(..., UIParent, ...)` once settings are loaded.
- **Shapeshift forms:** use `GetShapeshiftFormID()`, not the stance-bar index (the index shifts with learned
  forms). Cat = 1, Travel = 3, Aquatic = 4, Bear/Dire Bear = 5.
- **Form state can lag.** Re-casting the current form (e.g. `/cast !Cat Form` in Cat, to break roots) drops to
  caster and straight back. The client's form reading can lag the server by a few seconds, and the last
  `UPDATE_SHAPESHIFT_FORM` may fire while it still reports caster, with no event when it settles. Don't rely
  on form events alone: also poll `GetShapeshiftFormID()` / `UnitPowerType("player")` (~0.1s) and refresh
  on change. The default action bar suffers the same bug. The user runs the FormBars addon for that, with a
  `/click FormBars<Form>` line before the cast in their shift macros.
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
- Hand the zip over from the scratchpad, not the repo folder. A zip left in the repo trips the
  "untracked files" stop hook.
- The dev container has no Lua interpreter preinstalled. Syntax-check with either:
  - `apt-get install -y lua5.1` then `luac -p X.lua`. This is a real Lua 5.1 parser, the same version
    WoW uses.
  - `pip install luaparser` then `python3 -c "from luaparser import ast; ast.parse(open('X.lua').read())"`.
