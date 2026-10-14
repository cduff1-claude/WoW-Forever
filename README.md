# WoW Forever addons

Copy each folder into `World of Warcraft/_retail_/Interface/AddOns/` (or wherever your WoW Forever client keeps addons).

## DruidForeverManabarPlus
A reworked copy of *Druid Forever Manabar* (by antisnake). It shows a druid mana bar with the 5-second rule
under the Player Frame while in Cat, Bear, Travel or Aquatic Form, and shades the mana a Cat/Bear shift would spend.

- **Shift shading:** covers cost / max mana from the left of the bar. The cost is read live from
  `C_Spell.GetSpellPowerCost`, so talents (e.g. Natural Shapeshifter) and items are included.
- **Colours:** the shade is split into a Travel section (up to the Travel/Aquatic cost) and a Bear section (up to the
  Bear/Cat cost). "After the cast" = current mana minus the cost of the spell being cast.

  | Situation | Travel section | Bear section |
  |---|---|---|
  | Enough for Bear, even after the cast | blue | blue |
  | Cast takes you below Bear (still above Travel) | blue | pale orange |
  | Cast takes you below Travel | pale red | unshaded |
  | Below Bear now, still above Travel after the cast | pale yellow | bold orange |
  | Below Bear now, cast takes you below Travel | grey | unshaded |
  | Below Travel now | dark red | (empty) |

  The Travel section only exists once Travel Form is learned, or Aquatic Form if "Use Aquatic Form's cost" is ticked
  (default on). Without it, the whole shade is blue / pale orange / bold orange.
- **Where it shows:** the druid bar under the Player Frame (in form), the Player Frame's own mana bar (whenever it
  shows mana), and the Personal Resource Display's mana bar (`PowerBar` in caster form, `AlternatePowerBar` in Cat/Bear).
- **Settings (`/dfmp`, or right-click the druid bar):** "Enable for player frame" (druid bar + Player Frame shading),
  "Enable for Personal Resource Display", and "Use Aquatic Form's cost for the travel section when Travel Form isn't learned".
- **Text:** the druid bar's mana text follows the Player Frame's Status Text setting (None / Numeric / Percentage /
  Both), and copies the Player Frame mana text's font, scaled down to the smaller bar.

Other commands:
- `/dfmp debug`: detected shift/travel costs, text format, font and overlay status.
- `/dfmp prd`: which Personal Resource Display bar is being shaded.
- `/dfmp test`: shows the druid bar with a 5-second-rule test timer.
- `/dfmp testtravel <cost>` pretends Travel Form costs that much (for testing before level 30); `/dfmp testtravel off` clears it.
- `/dfmp formlog`: toggles a log of form-related readings with timings, for diagnosing shifts.

Uses its own saved variables, so disable the original *Druid Forever Manabar* to avoid two bars.

## ForeverFiveSecondRule
Draws the 5-second-rule marker on Blizzard's mana bars for any mana user:
- The Player Frame mana bar, while it shows mana (hidden e.g. in Druid Cat/Bear Form).
- The Personal Resource Display: its `PowerBar` when the primary power is mana, and for druids in Cat/Bear its
  `AlternatePowerBar` (the in-form mana bar).

Options (`/ffsr`, or Esc > Options > AddOns): tick boxes for the Player Frame and the Personal Resource Display,
and a marker width slider.

Other commands: `/ffsr help`, `/ffsr on|off`, `/ffsr player` / `/ffsr prd` (toggle each bar), `/ffsr text`
(countdown number), `/ffsr width <1-6>`, `/ffsr test`, `/ffsr debug`.

## DruidRange
A druid-only take on *RangeBar*: one bar whose colour depends on form and target. Range is only ever the game's
yes/no answer for a spell, and unlearned spells give no answer, so each rule starts working once its spell is learned.
- Caster, Travel, Aquatic and Moonkin: enemy green/red on Wrath range; friendly teal/grey on Healing Touch range.
- Cat, Bear and Dire Bear, enemy (first match wins): green = melee (Growl in Bear, Claw in Cat); brown = in Feral Charge
  range; yellow = in combat, the target has been in melee/charge range, and is now in neither but still in Faerie Fire
  range (i.e. inside charge's minimum range); purple = in Faerie Fire range; red = out of Faerie Fire range.
  Brown and yellow can be turned off. Faerie Fire's name is editable (Wrath is used until it answers).
- Cat, Bear and Dire Bear, friendly: teal/grey while the target is hurt or in combat, hidden otherwise
  (if neither can be read, behaves as in caster form).
- Dead friendly targets: teal/grey on Revive range; hidden until Revive is learned.
- Hidden with no target, and on friendly NPCs unless you're in combat and the NPC can be healed.
- "Hide based on what?": None, Melee (5yd, same melee check) or Charge (8yd, needs Feral Charge learned; melee only until then).
  Applies in every form, except while stealthed if "Don't hide while stealthed" is ticked (default).
- Snap to the main-hand swing timer or unlock and drag; width, height and opacity sliders.

Slash command: `/druidrange` (options), `/druidrange debug` (prints what the game answers for each spell).

## Myslot
A copy of [*Myslot*](https://github.com/tg123/myslot) v6.2.1 (by Boshi Lian, Apache 2.0) with two WoW Forever changes. It
saves a character's action bars, macros and key bindings as a profile and imports them onto another character.

- **Macro placement fix:** macros are kept sorted by name, so creating one shifts the index of every macro that sorts
  after it. The original looked up the new character's macros once, then created and placed them one by one. If another
  addon had already made macros, those lookups went stale after the first create and macros landed in the wrong slots.
  The import now creates every missing macro first, then re-reads the macro list and places each one by name and body.
- **Level 1 default per class:** pick a saved profile per class. A character imports it automatically 5 seconds after
  its first login while it is level 1 (waiting out combat if needed). It happens once per character; a character seen
  past level 1 is marked done and never imports. Set it from the profile dropdown (*Set selected as level 1 default for
  my class*) or with commands.

Commands:
- `/myslot default <profile name>`: set this class's level 1 default (names may contain spaces).
- `/myslot default clear`: remove this class's default.
- `/myslot default now`: import this class's default right away.
- `/myslot default skip`: mark this character as done so it never auto-imports.
- `/myslot default reset`: let this character auto-import again at next login (if still level 1).
- `/myslot default`: debug: class, level, whether this character has already imported, the default and whether it
  exists, and every class's default.
- `/myslot load <profile name>` now accepts names with spaces too.

Existing level 1 characters that haven't imported yet will also get the default at their next login. To stop that on
a character, log in and run `/myslot default skip` before (or right after) setting a default.
