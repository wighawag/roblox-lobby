# Live checklist (once per release, real Roblox client)

What Studio cannot test: group teleports, real reserved servers, `PrivateServerId`, failures from Roblox's servers. Run this on the published example experience (the private test experience under the operator's account, operator decision 4) with the release candidate vendored in, and record the result at the bottom.

## Before

1. On telemaque: `nix develop`, then `lune run tests` and `lune run scripts/build-check` pass.
2. Build both example places (`rojo build examples/lobby.project.json -o ...`, same for `game`), publish them into the test experience (lobby = start place, game = the other place), with the ids filled in `examples/shared/LobbyConfig.luau`.
3. `scripts/roblox-lobby check examples/shared/LobbyConfig.luau`: every line `ok`.
4. Player 1 is the operator in Sober on telemaque. Player 2 is a second account on another device: see "For the second player" below.

Driving Sober on telemaque (measured 2026-11-24, Sober 1.8.0): launch it straight into the lobby with `headless-display.sh launch sh -c "env -u WAYLAND_DISPLAY flatpak --user run org.vinegarhq.Sober -- 'roblox://experiences/start?placeId=<lobby place id>'"`. Do not use `headless-display.sh sober` (its `--nosocket=wayland` makes a configured Sober refuse to start with "Permission Update Required"); unsetting `WAYLAND_DISPLAY` keeps Sober on X11 without touching its permissions. Leave "Allow Controller Access" off in Sober's settings (it asks for `--device=input`). Clicks only register with the pointer hovering first and the button held about 0.1 to 0.3 s (`xdotool mousemove X Y; sleep 0.3; mousedown 1; sleep 0.3; mouseup 1`). Server output: F9 opens the developer console; its Client/Server dropdown opens a picker in the middle of the screen, "Server" at about (960, 127). The Sober log (`$XDG_RUNTIME_DIR/roblox-player-display/sober.log`) shows `Teleported.` and `Joining game ... place <id>` for each place change.

## Solo (player 1 only)

| # | do | expect |
| --- | --- | --- |
| S1 | join the experience, walk onto the "four" pad (minPlayers 1) | status line "Starting in 15 s (1/4)", then "Teleporting..." |
| S2 | wait | you arrive in the game place; its server log (Creator Dashboard > the place > Server logs, or the developer console F9 > Server) shows `MATCH READY source=teleport players=<you> missing=0 map=classic` |
| S3 | in the game place, F9 > Server | no `[RobloxLobby] rejected` and no `CONFIG PROBLEM` line |
| S4 | rejoin the lobby, step on the pad, press Leave during the countdown | the status line disappears, no teleport, you can join again |
| S5 | open the game place directly (Creator Dashboard > Places > game > Play, or its place URL) | you are sent back to the lobby (log: `rejected <you>: no-teleport-data`) |

## Group (players 1 and 2)

| # | do | expect |
| --- | --- | --- |
| G1 | both join the lobby; both walk into the GREEN "duo" booth | first "Waiting for 1 more player (1/2)", then "Starting in 5 s (2/2)" for both, then both are teleported |
| G2 | look around in the game place | you are in the SAME server (you see each other); log `MATCH READY ... players=P1,P2 missing=0` |
| G3 | player 1 waits in the GREEN booth; player 2 walks in and, at "Starting in 5 s", walks straight back out through the door | the countdown stops, back to "Waiting for 1 more player (1/2)", nobody is teleported |
| G4 | both in "duo"; player 2 closes Roblox at the very end of the countdown | player 1 arrives; log shows `missing=1` after 30 s at most (hard to time by hand; covered by the adapter tests) |
| G5 | both on "duo" twice in a row (two matches) | each match is its own server (different match ids in the log) |

## Failure path (operator, before restoring)

| # | do | expect |
| --- | --- | --- |
| F1 | set `places.game` to a wrong id (e.g. `1`), rebuild and publish the lobby only, step on a pad | `roblox-lobby check` FAILs first (`no such place`); in game: the server log shows `TeleportAsync to place 1 failed (attempt 1): HTTP 400 (Bad Request)` and `not retrying: this error is permanent`, the player sees "The game place could not be reached: its place id is probably wrong." and stays in the lobby, able to queue again |
| F2 | restore the right id, republish | S1 works again |

## For the second player (a kid, or the operator's second account)

You need: a Roblox account (the kid's own, or a new one made at roblox.com/signup), a device with Roblox (PC, tablet or phone), and the link the operator sends.

1. The operator shares the test experience with your account (Creator Dashboard > the experience > Collaborators, or makes it friends-only and you are friends). He sends you its link.
2. Open the link, press Play. You are in the lobby: a flat grey floor with two coloured pads.
3. When the operator says "duo", walk onto the GREEN pad (left). A line at the top says "Starting in 10 s (2/2)". Do nothing; you will be teleported.
4. Tell the operator what you see after the teleport: can you see his avatar? (Yes is what we want.)
5. When he says "four", walk onto the BLUE pad (right). When he says "leave", close Roblox completely.
6. That is all. Never type a password anywhere but Roblox's own sign-in, and do not accept anything you did not expect.

## Results

| release | date | S1-S5 | G1-G5 | F1-F2 | notes |
| --- | --- | --- | --- | --- | --- |
| 0.1.0-dev (f3521b6, then 85eb880 + booths) | 2026-11-24/25 | pass | G1 G2 G3 G5 pass, G4 not run | pass | Sober 1.8.0 on telemaque, account ronan7777777. S1-S3: real production teleport (`Teleported.`, joined game place 135477523707348), server log `match 59fbbad9... ready (teleport): 1 player(s), 0 missing` and `MATCH READY source=teleport ... map=classic`, no errors or warnings. S4: Leave during the countdown hid the status, moved the player to ExitPos, no teleport. S5: launching the game place directly sent the player back to the lobby place within 4 s. F1 (place id 1): `roblox-lobby check` failed with `no such place`; live, TeleportAsync threw `HTTP 400 (Bad Request)` five times (16 s of retries) before releasing the player, so permanent errors are no longer retried and get a place-id message (fixed after this run, unit-tested, not yet re-run live). F2: right id restored and republished, the teleport worked again. | Group run 2026-11-25 with breakout_bunny (Playtest access and Early tester on the test experience, which turned Team Create on): G1 first on flat pads (instant launch when full, then changed: `fullCountdown`, default 5 s), again in booths with "Starting in 2 s (2/2)" visible; G2: same game server, `match 46c78cee... ready (teleport): 2 player(s), 0 missing` and `MATCH READY ... players=ronan7777777,breakout_bunny ... map=classic`; G3 first FAILED (walking out of the booth took up to 2 s to register, the 3 s countdown won), fixed (Zone checked every 0.2 s, 0.3 s grace; fullCountdown 5 s), then passed twice: "Starting in 5 s, 4 s" then back to "Waiting for 1 more player (1/2)", no teleport; G5: each match had its own server and match id. Sober disconnects an idle player after 20 minutes (error 278): rejoin, or keep it busy. |
