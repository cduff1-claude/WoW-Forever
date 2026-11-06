# ForeverQuestCompleteSound

A rewrite of *Drash_QuestCompleteSound* (by Drashnar) for the Retail quest log API. Plays a sound and shows
"<quest> completed." when a quest's objectives are done and it's ready to turn in.
- Default sound follows your faction: Horde peon "Work complete!", Alliance peasant "Job's done!". Also `sheep`,
  any file you drop into the addon's `sound` folder (`/qcs sound myfile.ogg`), or a numeric SoundKit ID.
- Plays on the Master channel by default, so it's heard even with sound effects muted.
- Message goes to the raid-warning area by default; can be the error area, chat, or off.
- Stays quiet for quests that are already complete the moment you accept them (toggle with `/qcs accept`),
  and for the first few seconds after a loading screen while the quest log fills in.
- A quest that becomes incomplete again (e.g. you drop quest items) announces again when it completes.

Slash command: `/qcs` (help), `/qcs on|off`, `/qcs sound <choice>`, `/qcs channel <name>`, `/qcs out <where>`,
`/qcs accept`, `/qcs test` (plays the sound and shows a sample message), `/qcs debug` (prints each quest's
`IsComplete` / `ReadyForTurnIn` answers and plays the sound, reporting whether the game accepted it).
Disable the original *Drash_QuestCompleteSound* if it's still installed.
