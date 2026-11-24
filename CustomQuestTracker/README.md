# CustomQuestTracker

Click the **Quests** line at the top of Blizzard's quest tracker to minimise the tracker to just that line.
Click it again to put it back the way it was.

- Minimising remembers which tracker sections (Quests and any others) were open or collapsed, then collapses
  them all. Restoring puts each one back as it was. Blizzard's own collapse buttons still work as before.
- It stays minimised after `/reload` or logging out.
- In combat the game could block the tracker's quest-item buttons if an addon moved them, so a click in
  combat waits until combat ends (click again to cancel).

## Commands

- `/cqt`: toggle, same as clicking the line.
- `/cqt debug`: prints the tracker's sections, their headers and collapsed states.
- `/cqt mouse`: names the frame under the mouse pointer (and its parents). Hover something, then type it.
