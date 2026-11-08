# CustomBuffwatch

*Buffwatch++* (by Pup, version 11.01), patched to run on WoW Forever. A window listing you, your party or raid
and pets, with each player's buffs as icons. Lock a row to keep watching those buffs: they grey out when they
expire. `/buffwatch help` lists the commands; `/buffwatch options` opens the options.

Forever changes:
- Secret values are guarded throughout (names, dead/offline state, aura data), so nothing errors in combat.
- **Buffs can't be read in combat.** Unlocked rows refresh when combat ends. Locked rows keep their icons as
  they are and refresh when combat ends, so a buff that drops mid-fight greys out only after the fight.
- Temporary enchant changes are only checked for the `player` unit (the event also fires for units like
  `targettarget`, whose identity is secret in combat).
- A row locks automatically on death, restoring the buffs it had just before they were stripped.
- `/buffwatch always [buff name]` lists, adds or removes buffs shown even when a filter would hide them (Well Fed by
  default). Right-clicking a buff off an unlocked row hides it from that row.
- **Party members in second row** (option): you alone on the top row, with party members (and pets) side by side
  on the row below, each with their own buffs.
- **Keep centred** (option): when the window grows or shrinks (buffs added or removed, people joining), it stays
  centred on the same point instead of expanding to the right.

  Both are applied out of combat only: the rows hold secure buttons, which can't move mid-fight, so a change during
  combat waits until it ends.
- After combat, rows whose buffs still can't be read are retried a second later (up to 10 times) instead of being
  re-run in the same loop, which froze the client ("script ran too long").
