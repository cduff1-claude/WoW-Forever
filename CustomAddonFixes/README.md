# CustomAddonFixes

Fixes for errors in other people's addons on Forever, kept in their own addon so the other addons' updates
don't undo them. Each fix only switches on if its addon is installed. `/caf` shows which fixes are in place and
how often each one has stepped in.

- **ExperiencePlus:** stops "attempt to index local 'msg' (a secret string value)" from `Stats.lua`. System
  messages can be secret on Forever (e.g. in battlegrounds); those are no longer passed to its handler.
- **ForeverForge:** stops "attempt to compare local 'msg' (a secret string value)" from `Core/Net.lua`, the same
  way for channel notices.
- **Account Wide Interface Settings** (AccWideUILayoutSelection): stops "ADDON_ACTION_BLOCKED ...
  JoinChannelByName()". Rejoining your saved chat channels is skipped when you load in combat or inside an
  instance (battlegrounds, dungeons); the server keeps the channels you're in anyway.

ExperiencePlus and ForeverForge keep their event handling private, so the fix finds each one's event frame by
the exact set of events it listens to, and only steps in if exactly one frame matches. If an update changes
those events, `/caf` shows "frame not found" and the error may come back: send it over.
