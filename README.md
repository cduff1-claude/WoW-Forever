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
- Anything whose description says it raises "Mana regeneration by N%" for a time (Innervate, on yourself) raises the
  regen counted for everything after it in the sequence, including while casting if it says so.
- Regen modes: *smooth* (default, as Forever regens), *2s ticks* (worst tick timing), *off*.

**Library and windows.** Every sequence lives once in the library; windows (PvP, tanking, healing...) list the
sequences they show, so the same sequence can be in several windows and changing it changes it everywhere. *Copy*
makes an independent copy to change for another window. Each window is named, can be turned off, remembers its
position, and is one of:
- **Dynamic:** one row per sequence, showing the cheapest of its sequences you can't afford yet (the one you're
  working towards), and the Primary once you can afford everything. A sequence with nothing left to show (everything
  hidden on cooldown) closes up, and the rows below move up.
- **Fixed:** the Primary is always shown and can be clicked to cast (one icon per click; forms as `/cast !Form`, so
  they never shift you out; "best mana potion" uses the best one you have). Below it, smaller and indented, is the most
  complete sub-sequence you can afford (the cheapest if none), until you can afford the Primary. Nothing moves, since
  click-to-cast buttons can't move in combat, so that space is kept.
- *Only show in combat* (any window) hides it out of combat.
- Dynamic windows can also show only when you're low, and only for some targets:
  - *Mana*: below the dearest sequence's need plus a margin (e.g. +20%), so it appears as you get close to not
    affording it, and stays up for a few seconds (up to 10) after mana goes back above.
  - *Health*: below a percentage. With both ticked, the window shows when either is low.
  - *Targets*: what the fight is against, from your last living non-friendly target (hostile or neutral): *PvP*
    (anything PvP-flagged, such as players, guards and other PvP NPCs, or anything a player controls: pets, totems,
    summons), *NPCs*, or *none* (none yet, or it died). Friendly targets, yourself included, never change it, so
    healing yourself mid-fight keeps the window up. In combat it only ever moves towards PvP: once a PvP target turns
    up, the fight counts as PvP until combat ends, so re-targeting or a target dying doesn't flick windows on and
    off. When combat ends it starts again from your current target. Useful for sequences with cooldowns or
    consumables you'd only spend in PvP.
  - Mana and health are secret, so this is done with hidden status bars too: the window is still there, just drawn
    empty.
- Icons that aren't click-to-cast let left clicks through. Right-click any icon to open the options.

**Sequences.** Each has a Primary and any number of sub-sequences (any spells or items, up to 8 each).
- **Unusable icons:** an icon on cooldown (not just the global cooldown), an item you have none of, or a spell that
  only works on some creature types ("Only works on Beasts and Dragonkin": Hibernate) when your target isn't one of
  them (or you have no enemy target), is greyed out; cooldowns get Blizzard's swipe, with countdown numbers following
  your "show numbers for cooldowns" setting. *Hide when unusable* (offered only where something can be unusable,
  and not for a fixed window's Primary) drops that sequence or sub-sequence out while that's true, and the next one
  shows.
- **Ranks:** a spell follows your highest rank. A pinned lower rank shows "R3" on its icon.
- **Spells not learned yet** (on an alt, say): a sequence whose Primary has one is left out of its windows, and a
  sub-sequence with one is left out while the rest of the sequence works. They come in as soon as you learn the spell.
  The editor shows them greyed out and says what's missing instead of a mana cost. (Spells added before this version
  show a question mark until learned, since their icon wasn't saved.)

**Profiles.** Windows, sequences, window positions and options are saved in a profile, shared across your account and
tagged with its class. Each character uses one of its class's profiles (the button at the top of the options):
switch, make a copy, rename, delete, or *save this profile as the class default*. A character without a profile (a
new one, say) starts with its own copy of the class default, window positions included, so a level 1 alt needs no
setup, and editing it never changes the class default. To tidy up the class default itself (take out bag items,
say), switch to it, edit, and switch back. Settings from before profiles become a "Default" profile for the first
character to log in, with a copy as the class default.

**Options** (`/fseq`, right-click an icon, or Esc > Options > AddOns > Forever Sequences). While they're open, every
window is shown and can be dragged to move it; they lock again when the options close.
- Left, top: windows and the sequences they show, in display order. Tick to show or hide (hidden ones take no space),
  arrows to reorder, drag a sequence onto another window or sequence to move it there. *Remove* takes a sequence out of
  a window (it stays in the library); *Delete* deletes a window.
- Left, bottom: the library (with how many windows use each). Drag a sequence onto a window to show it there.
  New (also added to the selected window), Copy, Delete (from the library and every window).
- Right: for a window, its name, type, *only show in combat*, and for dynamic windows the mana, health and target
  options. For a sequence picked under a window, a read-only view of it with *Edit in library*. For a sequence
  picked in the library: its name, *hide when unusable* and which windows use it; the
  Primary and the sub-sequences, each labelled "Mana cost: X (Y gained)": X is its total cost, Y the mana regained
  before its last icon plus any potions or other restores in it. Sub-sequences are listed by mana cost, dearest
  first, each time the options open, in a scrolling list.
- Beside it: a scrolling list with a search box, in sections: *best mana potion*, your spells in spellbook order (one
  section per spellbook tab, with rank, cost and cast time; forms in their own section above Feral), then usable
  items (trinkets, then bags). It lists what you'd spend mana on in combat: spells that cost mana or have a
  cooldown of their own, plus War Stomp, Shadowmeld, Bash, Feral Charge, Frenzied Regeneration and Innervate; not
  buffs and utility (Mark/Gift of the Wild, Thorns, Omen of Clarity, Teleport: Moonglade, Soothe Animal, tracking),
  anything that can't be cast in combat (Revive), or the rest of General and Feral. *Show all* lists every spell.
  Never listed, even then: passives, internal spells ("(DND)", "Shapeshift"), quest items, items with no "Use:",
  hearthstones and anything you must remain seated for. Drag into a row, or click to add to the end of the Primary.
  The spellbook and bags work too. Escape closes the options, and the mouse wheel over them never reaches your
  key bindings.
- Drag icons within a row to reorder them, onto another row to copy them (from the Primary onto a sub-sequence's "+"
  slot they go in Primary order), or off the window to remove them. Right-click also removes. Shift-right-click a
  spell to step down through the ranks you know, and back round to your highest.
- Bottom: *click a fixed window's Primary to cast*, and the regen mode.
- Changes made in combat reach the windows when combat ends.

Druids only. Older settings move into a dynamic "Main" window, plus a fixed "Clickable" window for sequences that had
*always show Primary*. Other commands: `/fseq reset` (default window positions), `/fseq test` (fake mana sweeping from
empty to full), `/fseq cdtest [spell]` (a fake 10s cooldown on that spell's icons), `/fseq defaults` (restore the
starting windows), and `/fseq debug` (per window and icon: spell ID, rank, cost, cast/GCD/channel time, mana restored,
instant-cast and Clearcasting flags, thresholds and cooldown state; plus regen rates, 5-second rule, mana update gaps,
Clearcasting and the mana potions found).
