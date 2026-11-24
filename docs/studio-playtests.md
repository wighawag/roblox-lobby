# Studio playtests on telemaque (the operator's loop)

The headless Studio loop itself (virtual screen, Vinegar, xdotool, reading the Studio log) is described in hips' `TESTING.md` and roblox-player's `docs/headless-linux.md`; on the declared setup it becomes `roblox-studio start/open/stop`. Studio uses 2 to 3 GB and the operator's signed-in account: ask before starting it, and stop it afterwards. Below, `P` is the prefix folder Studio can see (`roblox-studio status` prints it; on the hand-made path `~/.var/app/org.vinegarhq.Vinegar/data/vinegar/prefixes/studio/drive_c/users/$USER/roblox-lobby`).

Build the example places into it:

```
nix develop -c rojo build examples/lobby.project.json -o "$P/lobby.rbxlx"
nix develop -c rojo build examples/game.project.json -o "$P/game.rbxlx"
```

Read the Output with `grep -a 'FLog::Creator' <newest Studio log> | tr -d '\r'`.

| # | place, mode | do | expected Output lines |
| --- | --- | --- | --- |
| P1 | lobby, Play (solo) | nothing | `[RobloxLobby] lobby started in Studio (experience 0, place 0); teleports: simulated (local file)`; no `CONFIG PROBLEM`, no error |
| P2 | lobby, Play (solo) | walk onto the blue "four" pad (W key, or a roblox-player routine) | status line "Starting in 15 s (1/4)"; after 15 s `SIMULATED teleport (local file) of party ... from queue "four" ... with 1 player(s)` and `[Example] party ... simulated=true`; 3 s later the pad accepts you again |
| P3 | lobby, Server & Clients, 2 clients | both clients onto the green "duo" pad | after 10 s one `SIMULATED teleport` line with 2 players |
| P4 | game, Play (solo) | nothing | `game place started in Studio`, then `match studio-... ready (studio): 1 player(s)` and `[Example] MATCH READY source=studio players=... map=classic` |
| P5 | game, Server & Clients, 2 clients | nothing | one `MATCH READY source=studio` with both players (both joined within `joinWindow`) |
| P6 | lobby opened from Roblox (published test experience), Play (solo) | walk onto "four" | `party ... teleporting`, then the game place opens as a new test server and its Output shows `MATCH READY source=teleport` (Studio's teleport testing, 2026-11-05; the destination runs its last PUBLISHED or saved version) |

P1 to P5 need no publishing. P6 needs the test experience (operator decision 4) and confirms the real arrival path for one player; groups stay with the live checklist.
