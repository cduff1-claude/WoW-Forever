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
- Regen modes: *smooth* (default, as Forever regens) or *off*.

**Library and windows.** Every sequence lives once in the library; windows (PvP, tanking, healing...) list the
sequences they show, so the same sequence can be in several windows and changing it changes it everywhere. *Copy*
makes an independent copy to change for another window. Each window is named, can be turned off, remembers its
position, and is one of three types (picked from a menu when you make the window, and changeable later; each type's own settings are kept
for switching back, but only the current type's are used):
- **Switching** (called *Dynamic* before): one row per sequence, showing the cheapest of its sequences you can't afford yet (the one you're
  working towards), and the Primary once you can afford everything. A sequence with nothing left to show (everything
  hidden on cooldown) closes up, and the rows below move up.
  *Skip sequences that would overheal* (switching windows only): a row (Primary or sub-sequence) is passed over
  while your health plus all its direct heals, at the low end, would go over your maximum, and the next one shows
  instead (as if it weren't there). Heals over time (Rejuvenation, Regrowth's over-time part, bandages) don't
  count; healing potions do. It follows your health as it changes, so rows come back as you take damage. With
  every row of a sequence overhealing, nothing shows for it. Health is secret, so each row is clipped by a chain
  of hidden status bars, one "mana or health" condition each: a few frames per row, none per icon.
- **Stacked:** every variation you include from its sequences (Primaries and sub-sequences alike), as one list of
  the ones you can afford, anchored at the top and filling downwards. With *costliest at the top* (the default) a
  newly affordable one takes the top row and the rest move down a row; without it they keep the window's order (each
  sequence's Primary, then its sub-sequences) with the gaps closed up. *Show the next one up* adds the cheapest one
  you can't afford yet, filling from grey (the top row, in cost order). Pick a sequence under the window to untick
  *include in this window* on any of its rows, or *pin Primary to the top* to keep that sequence's Primary always at
  the top, filling (one per window; its sub-sequences can still join the list). The same icons in the same order (a sub-sequence
  two sequences share, say) only go in once, the first one listed, even if both are ticked; the same icons in a
  different order are a separate row. Nothing actually moves: each row of
  the window holds every variation, each shown only over the band of mana where it belongs in that row (mana is
  secret, but the needs aren't, so each band's contents are known in advance). Rows below the number of variations
  that can show close up; blank rows above that stay, and let clicks through. Not clickable. Uses the same
  show-when options as Switching windows.
- **Fixed:** the Primary is always shown and, if the window's *click the Primary to cast* is ticked, can be clicked to cast (one icon per click; forms as `/cast !Form`, so
  they never shift you out; "best mana potion" uses the best one you have). Below it, smaller and indented, is the most
  complete sub-sequence you can afford (the cheapest if none), until you can afford the Primary. Nothing moves, since
  click-to-cast buttons can't move in combat, so that space is kept.
  - **Clicking through it:** once you cast the Primary's first icon (from the window or anywhere else) with the
    mana for the whole sequence, each icon is coloured while you can afford it and everything after it, from your
    mana now. (Cast it without enough and nothing changes: it carries on as usual. Mana is secret, so this is
    decided by a hidden status bar frozen as the sequence starts.) With enough for the whole
    sequence (twice over, say) nothing changes as you cast; below that the row greys from the left (each icon from
    its left edge), and regen fills it back towards the left. Before you start, it fills from the left as usual. It goes back to the start, dimming briefly as it does, when you cast
    the last icon, cast another spell from your spellbook, or don't cast the next icon in time (its cast time and
    the global cooldown after the last one, plus 5 seconds; 2 out of combat, so a heal or two after a kill still
    counts). Casting the first icon again starts again from it.
- *Only show in combat* (any window) hides it out of combat.
- Switching and stacked windows can also show only when you're low, and only for some targets:
  - *Mana*: below the costliest sequence's need plus a margin (e.g. +20%), so it appears as you get close to not
    affording it, and stays up for a few seconds (up to 10) after mana goes back above.
  - *Health*: below a percentage. With both ticked, the window shows when either is low.
  - *Fight against* (with *only show in combat*; greyed out without it): *PvP*, *PvE* or *All*. A fight starts
    from your target as combat begins, and is PvE unless that's a PvP unit (anything PvP-flagged, such as players,
    guards and other PvP NPCs, or anything a player controls: pets, totems, summons). In combat it only ever turns
    to PvP, when you target a PvP unit, and stays PvP until combat ends; friendly targets (yourself included) and
    targets dying don't change it, so windows don't flick on and off mid-fight. A fight that starts with no enemy
    targeted counts as PvE until a PvP target turns up, and a player hitting you without being targeted isn't
    noticed (that would need the combat log, which Midnight restricts). Useful for sequences with cooldowns or
    consumables you'd only spend in PvP. The window needs the right kind of fight *and* (if ticked) low mana or
    health.
  - Mana and health are secret, so this is done with hidden status bars too: the window is still there, just drawn
    empty.
- Icons that aren't click-to-cast let left clicks through. Right-click any icon to open the options.

**Sequences.** Each has a Primary and any number of sub-sequences (any spells or items, up to 8 each). The Primary is
always the variation you can cast that costs the most mana: variations with every spell learned come first, then the
costliest. They're re-sorted when you lock the sequence after editing it, when you learn a spell or rank, and when you switch profile, so adding a
spell to a sub-sequence (or learning a costlier rank) can make it the Primary, and on a character that hasn't learned
one of the Primary's spells the costliest variation it can cast takes its place until it does. Each variation keeps
its own *hide when unusable*.
- **Unusable icons:** an icon on cooldown (not just the global cooldown), an item you have none of, or a spell that
  only works on some creature types ("Only works on Beasts and Dragonkin": Hibernate) when your target isn't one of
  them (or you have no enemy target), or a bandage while you're Recently Bandaged, is greyed out; cooldowns get Blizzard's swipe, with countdown numbers following
  your "show numbers for cooldowns" setting. *Hide when unusable* (offered only where something can be unusable,
  and not for a fixed window's Primary) drops that sequence or sub-sequence out while that's true, and the next one
  shows.
- **Ranks:** a spell follows your highest rank, including ranks learned later. A pinned lower rank (dragged in, or set
  with shift-right-click / ctrl-click) shows "R3" on its icon.
- **Spells not learned yet** (on an alt, say): a sequence whose Primary has one is left out of its windows, and a
  sub-sequence with one is left out while the rest of the sequence works. They come in as soon as you learn the spell.
  The editor shows them greyed out and says what's missing instead of a mana cost. (Spells added before this version
  show a question mark until learned, since their icon wasn't saved.)

**Profiles.** Windows, sequences, window positions and options are saved in a profile, shared across your account and
tagged with its class. Each character uses one of its class's profiles (the button at the top of the options):
switch, make a copy, rename, delete, or *save this profile as the class default*. A character without a profile (a
new one, say) starts with its own copy of the class default, window positions included, so a level 1 alt needs no
setup, and editing it never changes the class default. To tidy up the class default itself (take out bag items,
say), switch to it, edit, and switch back.

**Options** (`/fseq`, right-click an icon, or Esc > Options > AddOns > Forever Sequences). Right-clicking an icon opens
them with its window selected. While they're open, every window is shown and can be dragged to move it, and clicking
a window selects it; they lock again when the options close.
- Left, top: windows and the sequences they show, in display order. Tick to show or hide (hidden ones take no space),
  arrows to reorder, drag a sequence onto another window or sequence to move it there. *Remove* takes a sequence out of
  a window (it stays in the library); *Delete* deletes a window.
- Left, bottom: the Sequence Library (with how many windows use each; arrows to reorder). Drag a sequence onto a
  window to show it there.
  New (also added to the selected window, and opened unlocked for editing), Copy, Delete (from the library and every
  window).
- Right: for a window, its name, type, *only show in combat*, and for switching and stacked windows the mana, health
  and target options (stacked: also *show the next one up* and *costliest at the top*). For a sequence picked under a
  window, a read-only view of it with *Edit in library* (under a stacked window, also the include and pin ticks). For a sequence
  picked in the library: its name, *hide when unusable* and which windows use it; the
  Primary and the sub-sequences (costliest first), each labelled "Mana cost: X (-Y gained)": X is its total cost, Y the
  mana regained before its last icon plus any potions or other restores in it (shown negative, as it comes off the
  cost), in a scrolling list.
- Beside it, while a sequence is unlocked: a scrolling list with a search box, in sections: *best mana potion*, your spells in spellbook order (one
  section per spellbook tab, with rank, cost and cast time; forms in their own section above Feral), and, with
  *Show all* only, usable items (trinkets, then bags). It lists what you'd spend mana on in combat: spells that cost mana or have a
  cooldown of their own, plus War Stomp, Shadowmeld, Bash, Feral Charge, Frenzied Regeneration and Innervate; not
  buffs and utility (Mark/Gift of the Wild, Thorns, Omen of Clarity, Teleport: Moonglade, Soothe Animal, tracking),
  anything that can't be cast in combat (Revive), or the rest of General and Feral. *Show all* lists every spell,
  plus the items section. Never listed, even then: passives, internal spells ("(DND)", "Shapeshift"), quest items,
  recipes, scrolls, items with no "Use:",
  hearthstones and anything you must remain seated for. Drag into a row, or click to add to the end of the Primary.
  The spellbook and bags work too. Escape closes the options, and the mouse wheel over them never reaches your
  key bindings.
- A sequence's rows start locked: press *Unlock* (below the sub-sequences) to change them. While unlocked, an empty
  sub-sequence waits at the bottom (another appears once you add to it; *Remove* shows only on rows with icons), and
  rows keep their places, so nothing jumps while you add to it. *Lock*, or picking another sequence or window, or
  closing the options, drops the empty rows and puts the variations back in order. A new library sequence starts
  unlocked, and so does one opened with *Edit in library*.
- Drag icons within a row to reorder them, onto another row to copy them (from the Primary onto a sub-sequence's "+"
  slot they go in Primary order), or off the window to remove them. Right-click also removes. Shift-right-click a
  spell to pin it one rank lower (stopping at rank 1), ctrl-click to go one rank higher; back at your highest rank the
  "R" label goes and it follows newly learned ranks again. A lower rank dragged in from the spellbook is pinned too.
- Bottom: the regen mode.
- Changes made in combat reach the windows when combat ends.
- It only works when something changes. Mana updates come from the game's mana events (at most 20 a second), and
  carry on for a couple of seconds after the last one (longer if a window's mana threshold keeps showing), and
  through the 5-second rule; at full mana with nothing going on it does nothing. Needs are only worked out again
  when regen, max mana, Clearcasting, cooldowns or spell data change, or as the 5-second rule runs out. Spell data
  (costs, cast times, descriptions) is read again on events (spells learned, gear, bags), while the options are
  open, and once a minute otherwise. Hidden windows (only-in-combat ones out of combat) aren't updated at all, and
  catch up when shown. In stacked windows each variation's needs are worked out once for all its copies.
- If something goes wrong while the windows update, the error is printed once in chat and updates pause for 5
  seconds, rather than repeating many times a second.

Druids only. A character with no class default yet starts with a switching "Main" window and a fixed "Clickable"
one. Other commands: `/fseq reset` (default window positions), `/fseq test` (fake mana sweeping from
empty to full), `/fseq cdtest [spell]` (a fake 10s cooldown on that spell's icons), `/fseq defaults` (restore the starting
windows and sequences), `/fseq perf` (milliseconds per second spent on mana updates, the once-a-second check and
events since the last `/fseq perf`), and `/fseq debug` (per window and icon: spell ID, rank, cost, cast/GCD/channel time, mana restored,
instant-cast and Clearcasting flags, thresholds and cooldown state; plus regen rates, 5-second rule, mana update gaps,
Clearcasting and the mana potions found; for stacked windows, each variation's need and the mana band it shows
over in each row).
