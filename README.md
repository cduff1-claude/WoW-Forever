# WoW Forever addons

Copy each folder into `World of Warcraft/_retail_/Interface/AddOns/` (or wherever your WoW Forever client keeps addons).

## DruidForeverManabarPlus
A reworked copy of *Druid Forever Manabar* (by antisnake). It shows a druid mana bar with the 5-second rule
under the Player Frame while in Cat, Bear, Travel or Aquatic Form, and shades the mana a Cat/Bear shift would spend.

- **Shift shading:** covers cost / max mana from the left of the bar. The cost is read live from
  `C_Spell.GetSpellPowerCost`, so talents (e.g. Natural Shapeshifter) and items are included.
- **Colours:** blue = enough for Bear/Cat; orange = Bear/Cat cost; red = Travel/Aquatic Form cost (they cost the same; Travel is used if known, otherwise Aquatic). Pale = the current
  cast will take you below that cost, bold/dark = already below it. Once below Bear cost, the shade splits into a
  Travel/Aquatic section and a Bear section.
- **Where it shows:** the druid bar under the Player Frame (in form), the Player Frame's own mana bar (whenever it
  shows mana), and the Personal Resource Display's mana bar (`PowerBar` in caster form, `AlternatePowerBar` in Cat/Bear).
- **Settings (`/dfmp`, or right-click the druid bar):** two tick boxes, "Enable for player frame" (druid bar + Player
  Frame shading) and "Enable for Personal Resource Display".
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

## ForeverSequences
*Prototype.* Rows of spell icons, one row per sequence, stacked vertically. Each icon fills with colour
from left to right as you gain the mana to cast it **after** everything before it in its row:
- An icon you can afford (on top of the earlier ones) is in full colour. The next one is part colour, part grey,
  in proportion to how much of its cost you have. The rest are grey.
- When an icon becomes affordable it gets a pulsing gold border for 2 seconds.
- Costs come from `C_Spell.GetSpellPowerCost`, so talents and gear are included. The highest rank you know is used.
- **Regen and cast time:** "the mana to cast it" means the mana you need *now* to start the sequence and still have
  enough when each spell's cost is taken. Mana regained in the meantime counts. Each cost is taken when its cast ends
  (instants: straight away), and the next spell starts when that cast or the 1.5s global cooldown ends. Regen comes from
  `GetManaRegen()`, at the in-5-second-rule rate while the rule is running (from your last mana spell, or from earlier
  spells in the sequence) and the normal rate otherwise. Regen that would overflow full mana isn't counted.
- `/fseq regen ticks` (default) assumes mana arrives in 2-second ticks and takes the worst case for when they land,
  so it never shows a spell as affordable too early. `/fseq regen smooth` treats regen as a steady flow, and
  `/fseq regen off` ignores regen.
- Mana is secret on Forever, so the comparisons are done with hidden status bars and clipping, not in Lua.

**Sub-sequences.** Each sequence has a Primary and optional sub-sequences made from its spells:
- Normally the sequence has one row, showing the cheapest sequence you can't afford yet (the one you're working
  towards), and the Primary once you can afford everything.
- With *always show Primary*, the Primary keeps its row. Below it, smaller and indented, is the most complete
  sub-sequence you can afford (the cheapest if none), until you can afford the Primary. That space is always reserved,
  because Lua can't tell when the Primary is affordable.

**Cooldowns.** A spell on cooldown (not just the global cooldown) is greyed out with Blizzard's cooldown swipe. The
countdown numbers follow your "show numbers for cooldowns" setting. A sequence or sub-sequence set to *hide on cooldown*
drops out while one of its spells is on cooldown, and the next one shows instead. If the game won't say whether a spell
is on cooldown, it's never treated as on cooldown (Blizzard's swipe may still show).

The display is for reading only: locked, it ignores the mouse and clicks go through it.

Prototype sequences (the editor comes next):
1. *Bear out*: Regrowth > Rejuvenation > Bear Form, with subs Regrowth > Bear Form and Rejuvenation > Bear Form.
2. *Root and run* (always show Primary): Entangling Roots > Rejuvenation > Travel Form, with sub Entangling Roots >
   Travel Form.

Druids only. Commands:
- `/fseq unlock` (drag to move) / `/fseq lock`, `/fseq reset` (default position).
- `/fseq test`: fake mana sweeping from empty to full, to check the visuals and the row switching.
- `/fseq regen ticks|smooth|off`.
- Prototype toggles for every sequence at once: `/fseq primary` (always show Primary), `/fseq hidecd` (hide on
  cooldown). `/fseq cdtest [spell]` puts a fake 10s cooldown on that spell's icons (Rejuvenation by default).
  `/fseq defaults` restores the prototype sequences.
- `/fseq debug`: spell IDs, known ranks, costs, cast times, thresholds, each row's mana band and cooldown state, regen
  rates, time left on the 5-second rule, the gaps between recent mana updates, and which values read as secret.
