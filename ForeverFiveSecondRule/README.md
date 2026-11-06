# ForeverFiveSecondRule

Draws the 5-second-rule marker on Blizzard's mana bars for any mana user:
- The Player Frame mana bar, while it shows mana (hidden e.g. in Druid Cat/Bear Form).
- The Personal Resource Display: its `PowerBar` when the primary power is mana, and for druids in Cat/Bear its
  `AlternatePowerBar` (the in-form mana bar).

Options (`/ffsr`, or Esc > Options > AddOns): tick boxes for the Player Frame and the Personal Resource Display,
and a marker width slider.

Other commands: `/ffsr help`, `/ffsr on|off`, `/ffsr player` / `/ffsr prd` (toggle each bar), `/ffsr text`
(countdown number), `/ffsr width <1-6>`, `/ffsr test`, `/ffsr debug`.
