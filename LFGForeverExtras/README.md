# LFGForeverExtras

Additions to **LFG Forever** (by Artefius), kept in their own addon so LFG Forever's updates don't overwrite them.
Nothing in LFG Forever's own files is changed. Needs LFG Forever installed and enabled.

- **Member locations:** hovering a group in LFG Forever adds a panel under the tooltip listing each member
  (class-coloured, the leader marked) with the zone they're in, and their guild when it's known.
- **Guilds by /who:** left-click a group row (LFG Forever gives left-click no job) to /who the next member whose
  guild isn't known yet. The result is printed to chat and shown in the panel. /who needs a real click, and the
  server limits how often it answers, so it's one member per click.
- **Remembered guilds:** guilds are also picked up from anyone you mouse over or target, and saved, so known
  players show their guild without a /who.
- **%dungeon% in Ask to Join:** LFG Forever only fills %dungeon% in for its Invite whisper. Here it also works in
  the Ask to Join message, as the clicked group's dungeon(s). Your saved message keeps the %dungeon% tag.

Commands: `/lfgextras` shows what it's hooked and the last hovered group's members, zones and guilds;
`/lfgextras forget` clears the remembered guilds.

How it attaches: LFG Forever's window is the global `LFGForeverFrame` and its rows carry `.resultID` and
`.LFGFAskToJoin`; its group tooltip is Blizzard's, shown through `LFGBrowseSearchEntryTooltip_UpdateAndShow`, which is
hooked with `hooksecurefunc`. If an LFG Forever update renames those, this addon stops doing its part, but nothing
breaks.
