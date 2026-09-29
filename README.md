# WoW Forever addons

Copy each folder into `World of Warcraft/_retail_/Interface/AddOns/` (or wherever your WoW Forever client keeps addons).

## DruidForeverManabarPlus
A copy of *Druid Forever Manabar* (by antisnake) with:
- A lighter shade over the part of the filled bar that a Cat/Bear shift would spend (cost / max mana, from the left).
  The cost is read live from `C_Spell.GetSpellPowerCost`, so talents (e.g. Natural Shapeshifter) and items are included.
- Colours: blue = enough for Bear/Cat; orange = Bear/Cat cost; red = Travel Form cost. Pale = the current
  cast will take you below that cost, bold/dark = already below it. Once below Bear cost, the shade splits into a
  Travel Form section and a Bear section.
- `/dfmp testtravel <cost>` pretends Travel Form costs that much (for testing before level 30); `/dfmp testtravel off` clears it.
- Optional white line at the shift cost (off by default).
- Shows in Cat, Bear, Travel and Aquatic Form (and caster form if enabled in options).
- Also draws the shift-cost line (and a lighter wash) on the standard Blizzard Player Frame mana bar whenever it is showing mana (caster form, Moonkin, etc.). Can be turned off in options.
- Settings now persist between sessions.

Slash command: `/dfmp` (options), `/dfmp debug` (shows the detected shift cost), `/dfmp test`.
Uses its own saved variables, so disable the original *Druid Forever Manabar* to avoid two bars.

## ForeverFiveSecondRule
Draws the 5-second-rule marker on the standard Blizzard Player Frame mana bar for any mana user.
Hidden while the Player Frame bar shows something other than mana (e.g. Druid Cat/Bear Form).

Slash command: `/ffsr` (help), `/ffsr on|off`, `/ffsr text`, `/ffsr width <1-6>`, `/ffsr test`, `/ffsr debug`.

## DruidRange
A druid-only take on *RangeBar*: one bar whose colour depends on form and target. Range is only ever the game's
yes/no answer for a spell, and unlearned spells give no answer, so each rule starts working once its spell is learned.
- Caster, Travel, Aquatic and Moonkin: enemy green/red on Wrath range; friendly teal/grey on Healing Touch range.
- Cat, Bear and Dire Bear, enemy (first match wins): green = melee (Bash in Bear, Claw in Cat, Growl until those are learned); brown = in Feral Charge
  range; yellow = in combat, the target has been in melee/charge range, and is now in neither but still in Faerie Fire
  range (i.e. inside charge's minimum range); purple = in Faerie Fire range; red = out of Faerie Fire range.
  Brown and yellow can be turned off. Faerie Fire's name is editable (Wrath is used until it answers).
- Cat, Bear and Dire Bear, friendly: teal/grey while the target is hurt or in combat, hidden otherwise
  (if neither can be read, behaves as in caster form).
- Hidden with no target, and on friendly NPCs unless you're in combat and the NPC can be healed.
- "Hide based on what?": None, Melee (5yd, same melee check) or Charge (8yd, needs Feral Charge learned; melee only until then).
  Applies in every form, except while stealthed if "Don't hide while stealthed" is ticked (default).
- Snap to the main-hand swing timer or unlock and drag; width, height and opacity sliders.

Slash command: `/druidrange` (options), `/druidrange debug` (prints what the game answers for each spell).
