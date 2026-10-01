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
- Enemy (all forms): green = melee (Growl in Bear/caster, Claw in Cat); purple = within 30 yd (Faerie Fire, Wrath until
  it's learned); grey = out of range. In Cat/Bear also: yellow = in Feral Charge range (8-25 yd), and green inside
  charge's minimum range (in combat, once the target has been in melee/charge range; needs Feral Charge learned).
  The yellow/minimum-range colours can be turned off.
- Friendly (all forms): purple = within 30 yd (Mark of the Wild / Thorns); teal = within 40 yd (Healing Touch);
  grey = out of range. In Cat/Bear only while the target is hurt or in combat (always, if neither can be read).
- Dead friendly targets: purple in Revive range (30 yd), grey out of it; hidden until Revive is learned.
- Hidden with no target, and on friendly NPCs unless you're in combat and the NPC can be healed.
- "Hide based on what?": None, Melee (5yd) or Charge (8yd, needs Feral Charge learned; melee only until then).
  Checked before the colour, so the bar never flashes before hiding. Applies in every form, except while stealthed
  if "Don't hide while stealthed" is ticked (default).
- Snap to the main-hand swing timer or unlock and drag; width, height and opacity sliders.

Slash command: `/druidrange` (options), `/druidrange debug` (prints what the game answers for each spell).
