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
Windows of spell icons, one row per sequence. Each icon fills with colour from left to right as you gain the mana to
cast it **after** everything before it in its row:
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
- Regen modes: *smooth* (default, as Forever regens), *2s ticks* (worst tick timing), *off*.

**Windows.** Make as many as you like (PvP, tanking, healing...); each is named, can be turned off, and remembers its
position. Each window is one of:
- **Dynamic:** one row per sequence, showing the cheapest of its sequences you can't afford yet (the one you're
  working towards), and the Primary once you can afford everything. A sequence with nothing left to show (everything
  hidden on cooldown) closes up, and the rows below move up.
- **Fixed:** the Primary is always shown and can be clicked to cast (one icon per click; forms as `/cast !Form`, so
  they never shift you out; "best mana potion" uses the best one you have). Below it, smaller and indented, is the most
  complete sub-sequence you can afford (the cheapest if none), until you can afford the Primary. Nothing moves, since
  click-to-cast buttons can't move in combat, so that space is kept.
- *Only show in combat* hides the window out of combat.
- Icons that aren't click-to-cast let left clicks through. Right-click any icon to open the options.

**Sequences.** Each has a Primary and up to 4 sub-sequences (any spells or items, up to 8 each).
- **Cooldowns:** an icon on cooldown (not just the global cooldown), or an item you have none of, is greyed out with
  Blizzard's cooldown swipe; the countdown numbers follow your "show numbers for cooldowns" setting. *Hide when on
  cooldown* (offered only where a spell or item has a cooldown of its own, and not for a fixed window's Primary) drops
  that sequence or sub-sequence out while that's true, and the next one shows.
- **Ranks:** a spell follows your highest rank. A pinned lower rank shows "R3" on its icon.

**Options** (`/fseq`, right-click an icon, or Esc > Options > AddOns > Forever Sequences). While they're open, every
window is shown and can be dragged to move it; they lock again when the options close.
- Left: windows and their sequences, in display order. Tick to show or hide (hidden ones take no space), arrows to
  reorder, drag a sequence onto another window or sequence to move it there. New window / New sequence / Delete.
- Right: the window's name, type and *only show in combat*; the sequence's name and *hide when on cooldown*; the
  Primary and the sub-sequences, each labelled "Mana cost: X (Y gained)": X is its total cost, Y the mana regained
  before its last icon plus any potions or other restores in it. Sub-sequences are listed by mana cost, dearest
  first, each time the options open.
- Beside it: a scrolling list with a search box, in sections: *best mana potion*, your spells in spellbook order (one
  section per spellbook tab, with rank, cost and cast time), then usable items (trinkets, then bags; not hearthstones
  or anything you must remain seated for). Drag them into a row, or click to add to the end of the Primary. The
  spellbook and bags work too. Escape closes the options.
- Drag icons within a row to reorder them, onto another row to copy them (from the Primary onto a sub-sequence's "+"
  slot they go in Primary order), or off the window to remove them. Shift-right-click also removes. Right-click a
  spell to step down through the ranks you know, and back round to your highest.
- Bottom: *click a fixed window's Primary to cast*, and the regen mode.
- Changes made in combat reach the windows when combat ends.

Druids only. Older settings move into a dynamic "Main" window, plus a fixed "Clickable" window for sequences that had
*always show Primary*. Other commands: `/fseq reset` (default window positions), `/fseq test` (fake mana sweeping from
empty to full), `/fseq cdtest [spell]` (a fake 10s cooldown on that spell's icons), `/fseq defaults` (restore the
starting windows), and `/fseq debug` (per window and icon: spell ID, rank, cost, cast/GCD/channel time, mana restored,
instant-cast and Clearcasting flags, thresholds and cooldown state; plus regen rates, 5-second rule, mana update gaps,
Clearcasting and the mana potions found).
