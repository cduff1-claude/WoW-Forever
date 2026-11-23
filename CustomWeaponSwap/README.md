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
- **In combat:** the bar's buttons equip through `/equipslot`, which works in combat. `/ws` equips from addon code;
  if the game blocks that in combat, use `/click WS1` (`WS2`, `WS3`...) in the macro instead, which presses
  the bar's button (it works even with the bar hidden).
- **Options** (Esc > Options > AddOns > CustomWeaponSwap, or `/ws`): show the bar, swaps per set (1-6), bar size.
  While the options are open, drag the bar to move it (clicks don't swap then).
- `/ws debug` prints the current set, what's equipped, and each swap with its macro.
