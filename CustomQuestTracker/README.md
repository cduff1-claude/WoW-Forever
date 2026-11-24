# CustomQuestTracker

For the **EnhancedQuestTracker** addon: click the **Quests** title at the top of its window to minimise the
window to just that line. Click it again to put it back.

- Works with both of EnhancedQuestTracker's looks (the Questie-style title, or the Blizzard-style header bar;
  its own buttons on the bar keep working).
- It stays minimised after `/reload` or logging out, and when quests update.
- Quest-item buttons beside the list go away while it's minimised. They're protected in combat, so if you
  minimise mid-fight they disappear when combat ends.
- Without EnhancedQuestTracker it does nothing.

## Commands

- `/cqt`: toggle, same as clicking the title.
- `/cqt debug`: prints the window's state (found, minimised, heights).
- `/cqt mouse`: names the frame under the mouse pointer (and its parents). Hover something, then type it.
