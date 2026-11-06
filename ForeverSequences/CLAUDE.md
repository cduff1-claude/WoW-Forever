# ForeverSequences notes

- **Top-level locals:** `ForeverSequences.lua` is close to Lua's 200-locals limit (see the top-level
  `CLAUDE.md`). It keeps its constants in a `C` table, spell-description parsers in `Parse`, run-time state in
  `work`, and the overheal row helpers in `Terms`; add new things to those (or a new table) rather than as
  top-level locals.

## Before publishing

- Add a help button in the top right of the options window. (The user asked to be reminded.)
