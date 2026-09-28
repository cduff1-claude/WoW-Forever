# WoW Forever addons

Copy each folder into `World of Warcraft/_retail_/Interface/AddOns/` (or wherever your WoW Forever client keeps addons).

## DruidForeverManabarPlus
A copy of *Druid Forever Manabar* (by antisnake) with:
- A lighter shade over the part of the filled bar that a Cat/Bear shift would spend (cost / max mana, from the left).
  The cost is read live from `C_Spell.GetSpellPowerCost`, so talents (e.g. Natural Shapeshifter) and items are included.
- The shade turns pale red when current mana is below the shift cost, or when the spell being cast would take it below.
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
