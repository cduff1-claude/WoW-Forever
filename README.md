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
Rows of spell icons, one row per sequence, stacked vertically. Each icon fills with colour from left to right as you
gain the mana to cast it **after** everything before it in its row:
- An icon you can afford (on top of the earlier ones) is in full colour. The next one is part colour, part grey,
  in proportion to how much of its cost you have. The rest are grey.
- When an icon becomes affordable it gets a pulsing gold border for 2 seconds.
- Mana is secret on Forever, so the comparisons are done with hidden status bars and clipping, not in Lua.

**What counts.** "The mana to cast it" means the mana you need *now* to start the sequence and still have enough when
each cost is taken. Everything is read from the game, not hard-coded:
- Costs from `C_Spell.GetSpellPowerCost` (talents and gear included), cast times from the spell data, and whether
  something triggers the global cooldown from `GetSpellBaseCooldown` (so War Stomp, Nature's Swiftness, potions and
  trinkets each take the time they really take). Channels: a "Channeled" tooltip and "over N sec" in the description.
- Regen from `GetManaRegen()`, at the in-5-second-rule rate while the rule is running (from your last mana spell, or
  from earlier spells in the sequence). Regen or restores that would overflow full mana aren't counted.
- Anything whose description says "Restores X to Y mana" (potions, runes, gems, engineering items) adds the low figure
  when used; "... over N sec" spreads it over that time.
- Anything whose description says the next spell "becomes an instant cast" (Nature's Swiftness) makes the next cast
  in the sequence instant.
- While you have Clearcasting (Omen of Clarity), the first spell in each sequence that would use it is free. Forms,
  items and Wrath don't use it.
- Regen modes: *ticks* (default) assumes 2-second mana ticks with the worst timing, so it's never too early;
  *smooth* treats regen as a steady flow; *off* ignores it.

**Sequences.** Each sequence has a Primary and optional sub-sequences (any spells or items, up to 8 each, up to 4 subs):
- Normally the sequence has one row, showing the cheapest sequence you can't afford yet (the one you're working
  towards), and the Primary once you can afford everything.
- With *always show Primary*, the Primary keeps its row. Below it, smaller and indented, is the most complete
  sub-sequence you can afford (the cheapest if none), until you can afford the Primary. That space is always reserved,
  because Lua can't tell when the Primary is affordable.
- **Cooldowns:** an icon on cooldown (not just the global cooldown), or an item you have none of, is greyed out with
  Blizzard's cooldown swipe; the countdown numbers follow your "show numbers for cooldowns" setting. A sequence or
  sub-sequence set to *hide on cooldown* drops out while that's true, and the next one shows.
- **Ranks:** a spell follows your highest rank. A pinned lower rank shows "R3" on its icon.
- **Clicking:** an always-shown Primary can be clicked to cast, one icon per click (forms as `/cast !Form`, so they
  never shift you out; "best mana potion" uses the best one you have). Other rows are for reading only: left clicks go
  through them. Right-click any icon to open the options.

**Editor** (`/fseq`, right-click the display, or Esc > Options > AddOns > Forever Sequences):
- Left: your sequences in display order. Tick to show or hide (hidden ones take no space), arrows to reorder,
  New / Delete.
- Right: the selected sequence's name, *always show Primary*, *hide when on cooldown*, the Primary row and the
  sub-sequences (each with its own *hide on cooldown*).
- Drag spells from the spellbook (or action bars) and items from your bags onto a row; the "+" slot adds at the end.
  Drag the *best mana potion* tile into a row for "whichever is best in my bags".
- Drag icons within a row to reorder them, onto another row to copy them (from the Primary onto a sub-sequence's "+"
  slot they go in Primary order), or off the window to remove them. Shift-right-click also removes.
- Right-click a spell to step down through the ranks you know, and back round to your highest. Dragging in a lower
  rank from the spellbook pins that rank.
- Bottom: *lock display* (unlocked, drag it to move), *click always-shown Primary to cast*, and the regen mode.
- Changes made in combat reach the display when combat ends.

Druids only. Other commands: `/fseq lock` / `unlock`, `/fseq reset` (default position), `/fseq test` (fake mana
sweeping from empty to full), `/fseq cdtest [spell]` (a fake 10s cooldown on that spell's icons), `/fseq defaults`
(restore the starting sequences), and `/fseq debug` (for every icon: spell ID, rank, cost, cast/GCD/channel time,
mana restored, instant-cast and Clearcasting flags, thresholds and cooldown state; plus regen rates, 5-second rule,
mana update gaps, Clearcasting and the mana potions found).
