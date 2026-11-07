# Buffwatch

*Buffwatch++* (by Pup, version 11.01), patched to run on WoW Forever. A window listing you, your party or raid
and pets, with each player's buffs as icons. Lock a row to keep watching those buffs: they grey out when they
expire. `/bfw help` lists the commands; `/bfw options` opens the options.

Forever changes:
- Secret values are guarded throughout (names, dead/offline state, aura data), so nothing errors in combat.
- **Buffs can't be read in combat.** Unlocked rows refresh when combat ends. Locked rows keep their icons as
  they are and refresh when combat ends, so a buff that drops mid-fight greys out only after the fight.
- Temporary enchant changes are only checked for the `player` unit (the event also fires for units like
  `targettarget`, whose identity is secret in combat).
- A row locks automatically on death, restoring the buffs it had just before they were stripped.
- `/bfw always [buff name]` lists, adds or removes buffs shown even when a filter would hide them (Well Fed by
  default). Right-clicking a buff off an unlocked row hides it from that row.
