# Tests

Simulations that run the addons' real Lua outside the game, against `wow.lua`, a small fake of the WoW
client. Frames keep real sizes and anchors, so tests can check where things end up on screen; events,
time (`OnUpdate`) and the API calls the addons use are faked too.

Run everything from the repo root with `sh tests/run.sh`. It syntax-checks every addon file with the real
Lua 5.1 compiler, then runs each `*_test.lua`.

What they can't check: how things look, taint and actions blocked in combat, secret values (beyond what a
test sets up), or anything Forever does differently. Those still need the game and each addon's
`/<command> debug`.
