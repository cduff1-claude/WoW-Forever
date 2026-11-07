# CustomFormBars

A small druid addon for **WoW Forever**. It keeps your main action bar on the right page for each form, so you never end up looking at your caster bar in Cat or Bear Form.

## Why

The default UI decides which bar to show from the game's "bonus bar" value, and sometimes that value goes stale: you shift into Cat and your caster bar stays up. FormBars picks the bar from the form you're actually in instead, so a stale bonus bar value no longer matters. It sets the bar every time your form changes, including in combat.

It can also switch the bar **the instant you press your shift macro**, instead of waiting for the server to confirm the shift (which can take a second or more). This keeps powershifting smooth.

## Install

1. Copy the `CustomFormBars` folder into `World of Warcraft\<your Forever folder>\Interface\AddOns\`.
2. Restart the game (or `/reload` if it was already running when you copied it in).
3. Make sure **CustomFormBars** is enabled in the AddOns list on the character select screen.

It only loads on druids. Your existing bars stay where they are, because the defaults match Blizzard's layout:

| Form            | Bar page      |
|-----------------|---------------|
| Caster          | 1 (normal)    |
| Cat             | 7             |
| Cat + Prowl     | 8             |
| Bear / Dire Bear| 9             |
| Moonkin         | 10            |
| Travel, Aquatic | 1 (normal)    |

Shift+number and the bar arrows still page your bar like normal.

**Prowl:** the bar switches to page 8 while you're Prowling in Cat Form and back to 7 when Prowl ends. If you haven't set up page 8 yet it will look empty: put your stealth abilities on it while prowled, or run `/fb prowl 7` to keep your normal Cat bar while prowling.

## Instant bar switching (powershift macro)

Add a `/click` line **above** your shift line. For example, a one-button powershift for Bear and Cat:

```
#showtooltip
/click [form:1] FormBarsBear; [form:3] FormBarsCat
/cast [form:1] !Bear Form; [form:3] !Cat Form
```

Give the `/click` line the **same conditions as the `/cast` line**, so it clicks the button for the form you're about to shift into.

Buttons available: `FormBarsCat`, `FormBarsBear`, `FormBarsMoonkin`, `FormBarsTravel`, `FormBarsAquatic`.

### Finding your form numbers

`[form:N]` is the form's position on your stance bar, counting from the left. It depends on which forms you've learned, so check yours. A level-60 druid with every form usually has:

| N | Form            |
|---|-----------------|
| 1 | Bear / Dire Bear|
| 2 | Aquatic         |
| 3 | Cat             |
| 4 | Travel          |
| 5 | Moonkin         |

If you learn a new form, the numbers can shift, so update your macro. The addon itself doesn't use these numbers and adjusts on its own.

## Commands

| Command                | What it does                                          |
|------------------------|-------------------------------------------------------|
| `/fb`                  | Show your current form → page settings                |
| `/fb <form> <page>`    | Put a form on a different bar page (1–10), e.g. `/fb bear 8`. `prowl` is also accepted here |
| `/fb <form> default`   | Reset that form to its default page                   |
| `/fb on` / `/fb off`   | Turn FormBars on or off (off = normal Blizzard behaviour) |
| `/fb status`           | Show your current form, the game's bonus bar value, and the page being shown |

`/formbars` works too. Settings are saved per character. Changes made in combat apply as soon as combat ends.

## Limitations

- **Blizzard's main bar only.** If you use Bartender, Dominos, ElvUI, or MoveAny's option that replaces the action bars, FormBars won't affect those bars. Those addons handle form paging themselves.
- **A failed shift in combat.** If you press the macro but the shift doesn't happen at all (on cooldown, out of mana), FormBars still expects a drop to caster. If you really do drop to caster during that fight, the bar may stay on your Cat/Bear page until your form changes again. It always clears 5 seconds after your last macro press, or 5 seconds after combat ends.

## Troubleshooting

- **Bar is wrong or not switching:** run `/fb status` and check that `page=` matches your form. `/fb off` puts things back to the default UI.
- **Lua errors:** turn on error popups with `/console scriptErrors 1`, then report the full error text.
