# WoW Forever addons

Copy each folder into `World of Warcraft/_retail_/Interface/AddOns/` (or wherever your WoW Forever client keeps addons).

## DruidForeverManabarPlus
A copy of *Druid Forever Manabar* (by antisnake) with:
- A lighter shade over the part of the filled bar that a Cat/Bear shift would spend (cost / max mana, from the left).
  The cost is read live from `C_Spell.GetSpellPowerCost`, so talents (e.g. Natural Shapeshifter) and items are included.
- Colours: blue = enough for Bear/Cat; orange = Bear/Cat cost; red = Travel Form cost. Pale = the current
  cast will take you below that cost, bold/dark = already below it. Once below Bear cost, the shade splits into a
  Travel Form section and a Bear section.
- `/dfmp formlog` toggles a log of form-related readings (form ID, stance, bonus bar, power type, form aura) with timings, for diagnosing shifts.
- `/dfmp testtravel <cost>` pretends Travel Form costs that much (for testing before level 30); `/dfmp testtravel off` clears it.
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

## ForeverForge_Bags_DestroyPlus
An add-on for *ForeverForge Bags* (needs the `ForeverForge_Bags` folder). It changes no ForeverForge files, so it survives
ForeverForge Bags updates. Written against ForeverForge Bags 0.21.0.
- **Vendor price only** for anything headed to a vendor: gray items (wherever they're filed), items filed in Junk, and items
  in a section automated to sell at vendors. Other items still use the higher of vendor and auction house (after fees).
- **Destroy mode's cheapest-first view is split into three sections**, stacked in a single column (whatever the bags'
  section-column setting), each cheapest first:
  - *Junk*: gray items, Junk, vendor-automated sections. Title shows the first item's value.
  - *Other*: everything else. Title shows the first item's value.
  - *Protected* (icons desaturated): sections whose **Automate** dropdown is set to **Protected (Destroy mode)** (the add-on
    adds that choice), your `Core` section, and anything with no sell value. These **always ask** before they're destroyed,
    whatever the rarity setting says (`/ffdp ask off` to follow the rarity setting instead).
  - Quest items are left out, unless filed in Junk, a vendor section or Core (`/ffdp quest other` shows them in Other).
  Precedence: Protected / Core, then filed in Junk / a vendor section, then quest, then gray, then no sell value.
- How it works: wraps `ForeverForgeBags.Destroy.ItemValue`, `Destroy.AsksFirstFor` and `ForeverForgeBags.Window.Rebuild`,
  adds an entry to `ForeverForgeBags.Automation.ACTIONS`, replaces
  `ForeverForgeBags.Window.CollectByValue`, hooks `ItemButton.RefreshState` (desaturating), and while the Destroy view is
  drawn makes `ForeverForge.Config:GetStore("bags")` answer 1 for `layout.sectionColumns`. If ForeverForge Bags changes,
  `/ffdp debug` shows the version mismatch and whether each hook is still in place.

Slash command: `/ffdp` (help), `/ffdp vendor|sections|column|desat|ask [on|off]`, `/ffdp quest hide|other`,
`/ffdp core <section name>|none` (default `Core`), `/ffdp debug` (hook status, then each item outside Other with its value,
original value, quality, filed section and why).

## ForeverForge_Bags_KeepUncategorized
An add-on for *ForeverForge Bags* (needs the `ForeverForge_Bags` folder; changes no ForeverForge files). Written against
ForeverForge Bags 0.21.0. In **Manual** sorting, the *Uncategorized* section stays in the bag window as an empty title when
it has no items, instead of disappearing (which reshuffled the section columns). It sits where it would with items in it,
and you can still drag items onto it. Bags only (not the bank). Wraps `ForeverForgeBags.Window.CollectBySection`.

Slash command: `/ffku on|off`, `/ffku debug` (hook status, Manual mode, whether the last redraw added the empty section).
