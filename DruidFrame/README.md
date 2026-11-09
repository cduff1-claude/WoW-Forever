# DruidFrame

A druid resource display for WoW Forever, with a range bar and mana tools. It replaces Blizzard's Personal
Resource Display (turn that off so there aren't two) and never touches it. It has three parts, each with its own
options page under Esc > Options > AddOns > DruidFrame:

| Page | Slash command | What it covers |
|---|---|---|
| DruidFrame | `/druidframe` | the resource display itself |
| DruidBar | `/druidbar` | shift-cost shading, Claw warning, 5-second rule, and optional Player Frame features |
| DruidRange | `/druidrange` | the range bar |

While any of the three pages is open, the display and the range bar are unlocked (highlighted) and left-drag moves
them; closing the options locks them, and left clicks then pass through to the world. Right-click either one to
open its page. In combat they ignore the mouse completely (the client won't open the options then).

DruidFrame was made from three addons: DruidBar, DruidRange and ForeverFiveSecondRule. Its saved variables are the
old ones (`DruidForeverManabarPlusDB`, `DruidRangeDB`), so settings carry over, except that the Player Frame
features start off (they can be turned back on on the DruidBar page) and the Personal Resource Display options are
gone. Disable or delete the old DruidBar and DruidRange folders.

## The display (DruidFrame page)

- Rows, all the same width: health, mana (in every form), then energy or rage in Cat/Bear, then combo points in
  Cat: Hide, Circles, or Bar (five bordered segments the size of a power bar, one filled per combo point,
  glowing gold when all five are full), shown only in combat (and while the options are open). The frame hangs from its top edge, so health and mana never move when you shift.
- In caster form, an optional cast bar takes the energy/rage row, with the spell's name and mana cost centred on it
  ("Healing Touch (55)"), a purple bar (the range bar's purple) with a spark riding its edge while casting and a flash when the spell goes off. Options (both
  on by default): keep the row in place (not just while casting), and show the last spell's name and cost for
  3 seconds after it goes off, instant spells included. Then the name fades, then the bar itself; an empty
  held row isn't drawn (except while unlocked). A new spell or a shift replaces it.
- Incoming heals: a teal bar on the health bar after your current health, like the Player Frame's (Midnight's heal prediction,
  with the older call as a fallback). `/druidframe debug` shows what the game reports for incoming heals.
- Energy bar in caster form: Never, In combat (default) or Always. Shown under the mana bar, above the cast
  bar, e.g. to watch Furor's energy regen.
- In Cat/Bear the cast bar shows (below the energy/rage bar) for anything with a cast time, like skinning,
  gathering or opening things, but not for instant abilities. Only spells that cost mana linger afterwards; the
  rest disappear as soon as they finish.
- Text: current amount centred (default), or current on the left and max on the right (energy and rage just
  current), current only, percent, current and percent, or none.
- Visibility: always, in combat, in combat or with a target, or hidden.
- Bar style: flat (a plain fill with a lighter top half, like Blizzard's display; the default) or shaded
  (Blizzard's classic bar texture).
- Size, bar width, health and power bar heights, padding (default 4) and opacity sliders.
- "Keep centred": dragging only moves it up and down, with a red line down the middle of the screen while you drag
  (like Edit Mode's snap). "Reset to default position" puts it back.
- Omen of Clarity (option, on): a pulsing gold glow around the mana and energy/rage bars while Clearcasting is
  up, stopping as soon as it's spent. Detected from the aura when the client shows it, otherwise from a known
  spell's cost dropping to 0. `/druidframe clearcasting` shows what each method sees.
- Colours: health green, mana blue, energy a warm gold, rage red, combo points a bold red. The combo bar's
  segments follow the bar style (flat or shaded) like the other bars.
- Buff reminders (option, on): out of combat, a Mark of the Wild button to the left of the health and mana
  bars while you don't have it (Gift of the Wild counts), and a Thorns button to the right. Each is as tall as
  both bars and the gap between them. Click to cast it on yourself (from a form too: it leaves the form first);
  the button fades out. While a buff is missing, out of combat, its button has the same gold glow as Omen of
  Clarity, pulsing at a third of the speed (a gentle reminder). Only checked out of combat, and only once the spell is learned. Both show while the
  options are open, so you can see where they go. Not shown in battlegrounds or arenas (buffs get purged
  there) unless "Also in battlegrounds and arenas" is ticked. Macro-clickable as `DruidFrameMarkButton` /
  `DruidFrameThornsButton`. `/druidframe buffs` shows what it sees.
- The DruidBar features below (shift shading, energy warning, 5-second rule) all show on its bars.

## Mana tools (DruidBar page)

Based on *Druid Forever Manabar* by antisnake.

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
- **Energy warning (Cat Form):** the energy bar turns orange while you can't afford your next ability, and stays
  its normal colour once you can, or while Clearcasting is up. Which ability:
  - **Ability:** Claw (default) or Shred.
  - **At full combo points:** Ferocious Bite (default), Rip or no override.
  - **In Prowl:** Ravage (default), Pounce or no override.
  
  An override only applies once its spell is learned (until then the ability counts; Shred unlearned falls back
  to Claw). Costs are read live from the game, so anything that changes them is included (Ferocity, and Forever's
  cheaper openers at full energy in stealth).
- **Rage warning (Bear Form):** in combat, the rage bar turns orange while you have less rage than Swipe costs
  (read live). Out of combat it stays red, so it doesn't nag while you get ready to pull. Its own tick box. The orange covers the whole fill,
  so while Blizzard's bar eases down after you spend energy, the part still catching up is orange too. Shown on DruidFrame's energy bar, and on the Player Frame's energy bar if
  that option is on.
- **5-second rule on Blizzard's bars** (this used to be the separate ForeverFiveSecondRule addon): a marker
  that sweeps along DruidFrame's mana bar (always) and the Player Frame mana bar (caster form, if ticked) for
  5 seconds after you spend mana, with an optional countdown number and a marker width slider (1-6).
- **Player Frame (off by default):** "Druid mana bar under the Player Frame" shows a small mana bar under the
  Player Frame while in Cat, Bear, Travel or Aquatic Form, and adds the shift shading and Claw warning to the Player
  Frame's own bars. Its text follows the Player Frame's Status Text setting (None / Numeric / Percentage / Both) and
  copies the Player Frame mana text's font, scaled down. Right-click that bar to open the page.

## Range bar (DruidRange page)

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
- Position: **Above DruidFrame** or **Below DruidFrame** (it moves with the display, follows its width, and its
  width slider is a percentage of that), or **Free** (the default when upgrading, so it stays where you had it).
  Free has "Keep centred" (on: dragging only moves it up and down, with the red centre line). While its options
  are open it shows (green) even with no target, so you can place it.
- Width, height and opacity sliders.

## Commands

- `/druidframe`, `/druidbar`, `/druidrange`: open their options pages.
- `/druidframe debug`: the display's settings and state. `/druidframe clearcasting`: Omen of Clarity detection.
  `/druidframe buffs`: the buff buttons' view of Mark of the Wild and Thorns.
- `/druidbar debug`: detected shift/travel costs, the energy warning's spells and costs, text format, font and
  overlay status.
- `/druidbar test`: shows the druid bar with a 5-second-rule test timer.
- `/druidbar testtravel <cost>` pretends Travel Form costs that much (for testing before level 30); `/druidbar testtravel off` clears it.
- `/druidbar formlog`: toggles a log of form-related readings with timings, for diagnosing shifts.
- `/druidrange debug`: prints what the game answers for each range spell.
