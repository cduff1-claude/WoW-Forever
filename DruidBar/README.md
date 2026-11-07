# DruidBar

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
- **Claw warning (Cat Form):** the energy bar turns orange while you have less energy than Claw costs (read live,
  so Ferocity is included), and is left as Blizzard's yellow once you can afford it. The orange covers the whole fill,
  so while Blizzard's bar eases down after you spend energy, the part still catching up is orange too. Shown on the Player Frame's
  energy bar and the Personal Resource Display's `PowerBar`, each only if that bar is enabled below.
- **5-second rule on Blizzard's bars** (this used to be the separate ForeverFiveSecondRule addon): a marker
  that sweeps along the Player Frame mana bar (caster form) and the Personal Resource Display's mana bar (any form)
  for 5 seconds after you spend mana, with an optional countdown number. Settings: the two "Show on…" ticks,
  "Show the countdown number", and a marker width slider (1-6).
- **Personal Resource Display colours** (option "Match the Personal Resource Display's colours to the Player
  Frame", on by default): Blizzard draws the PRD's bars in flat, bright colours. With this on, the PRD's bars keep
  their own full-size texture but are tinted to the Player Frame's colours, measured in game: health green, energy
  a paler yellow (the colour the old Claw wash gave), rage red (an estimate: only seen at 10%), and mana blue (the power bar in caster form, the in-form mana
  bar in Cat/Bear). `/druidbar colours` prints each bar's texture and colour. Turning the option off
  puts Blizzard's colours back.
- **Where it shows:** the druid bar under the Player Frame (in form), the Player Frame's own mana bar (whenever it
  shows mana), and the Personal Resource Display's mana bar (`PowerBar` in caster form, `AlternatePowerBar` in Cat/Bear).
- **Settings (`/druidbar`, or right-click the druid bar):** "Enable for player frame" (druid bar + Player Frame shading),
  "Enable for Personal Resource Display", "Use Aquatic Form's cost for the travel section when Travel Form isn't learned",
  and "Shade the energy Claw costs in Cat Form".
- **Text:** the druid bar's mana text follows the Player Frame's Status Text setting (None / Numeric / Percentage /
  Both), and copies the Player Frame mana text's font, scaled down to the smaller bar.

Other commands:
- `/druidbar debug`: detected shift/travel/Claw costs, text format, font and overlay status.
- `/druidbar prd`: which Personal Resource Display bar is being shaded.
- `/druidbar test`: shows the druid bar with a 5-second-rule test timer.
- `/druidbar testtravel <cost>` pretends Travel Form costs that much (for testing before level 30); `/druidbar testtravel off` clears it.
- `/druidbar formlog`: toggles a log of form-related readings with timings, for diagnosing shifts.

Uses its own saved variables, so disable the original *Druid Forever Manabar* to avoid two bars.
