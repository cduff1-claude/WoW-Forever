# CustomXToLevel

*XToLevelNG* (by Bjarke Istrup Pedersen, version 12.1.0), patched for WoW Forever. Shows how many mobs, quests,
dungeons and battles you need until your next level. `/xtl` (or `/xtolevel`) opens its options.

Forever changes:
- Secret values are guarded (combat log, target GUIDs, mob names, tooltip widths), so it doesn't error in combat.
- Window positions are saved in its own settings (the client's memory of dragged frames doesn't survive a client
  restart on Forever).

Saved variables keep their original names (`XToLevelDB`, `sConfig`, `sData`).
