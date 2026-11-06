# DruidRange

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
