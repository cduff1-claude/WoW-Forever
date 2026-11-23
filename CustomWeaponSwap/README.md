# CustomWeaponSwap

Weapon swaps that follow the equipment manager. Each equipment set (or "(no set)" when none is in use) has its own
numbered swaps. A swap is a main hand weapon and an optional off hand (shield, off-hand item or second weapon), so a
staff on its own, or a mace and an off hand, are each one swap.

- **Setting up:** open the character screen. A row of swaps sits under it, headed with the current equipment set.
  Drag a weapon onto a swap's big slot (main hand) and, if you want, an off hand onto its small slot. Right-click a
  slot to empty it. Two-handers can't have an off hand; main-hand-only weapons can't go in the off hand.
- **Equipment sets:** switching sets with the equipment manager switches to that set's swaps. After a weapon swap the
  set no longer matches exactly, so the addon remembers the set you last equipped.
- **Swapping:** the swap bar (option, on) shows each swap's weapon (off hand in the corner) and highlights the one you
  have equipped in gold. Click one to equip it. Or use `/ws 1`, `/ws 2`... in a macro. A swap that's already
  equipped does nothing.
- **In combat:** clicking the bar works in combat. `/ws` only works out of combat (the game doesn't let addons
  equip in combat). For macros in combat use `/click WS1 X 1` (main hand) and, if the swap has an off hand,
  `/click WO1 X 1` too (`WS2`/`WO2` for swap 2, and so on). Keep the `X 1`: it sends a key press, and with
  "cast on key down" on (the default) a plain `/click WS1` does nothing. They work with the bar hidden. They're separate because,
  since patch 11.0.2, a `/click` from a macro is ignored if the button would run a macro, so these use the game's
  plain "use item" action (using a weapon equips it), which does one item per click. Using a one-handed weapon
  that can go in either hand puts it in the main hand.
- **Options** (Esc > Options > AddOns > CustomWeaponSwap, or `/ws`): show the bar, swaps per set (1-6), bar size.
  While the options are open, drag the bar to move it (clicks don't swap then).
- `/ws debug` prints the current set, what's equipped, and each swap with its macro.
