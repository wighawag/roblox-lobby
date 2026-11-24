# Live checklist (once per release, real Roblox client)

What Studio cannot test: group teleports, real reserved servers, `PrivateServerId`, failures from Roblox's servers. Run this on the published example experience (the private test experience under the operator's account, operator decision 4) with the release candidate vendored in, and record the result at the bottom.

## Before

1. On telemaque: `nix develop`, then `lune run tests` and `lune run scripts/build-check` pass.
2. Build both example places (`rojo build examples/lobby.project.json -o ...`, same for `game`), publish them into the test experience (lobby = start place, game = the other place), with the ids filled in `examples/shared/LobbyConfig.luau`.
3. `scripts/roblox-lobby check examples/shared/LobbyConfig.luau`: every line `ok`.
4. Player 1 is the operator in Sober on telemaque (`roblox-studio sober` or roblox-player's `headless-display.sh sober`). Player 2 is a second account on another device: see "For the second player" below.

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
| G1 | both join the lobby; both step on the "duo" pad | "Starting in 10 s (2/2)" for both, then both are teleported |
| G2 | look around in the game place | you are in the SAME server (you see each other); log `MATCH READY ... players=P1,P2 missing=0` |
| G3 | both step on "four", player 2 leaves the game entirely (closes Roblox) during the countdown | player 1 still goes alone at the end of the countdown (minPlayers 1) |
| G4 | both on "duo"; player 2 closes Roblox at "Teleporting..." | player 1 arrives; log shows `missing=1` after 30 s at most |
| G5 | both on "duo" twice in a row (two matches) | each match is its own server (different match ids in the log) |

## Failure path (operator, before restoring)

| # | do | expect |
| --- | --- | --- |
| F1 | set `places.game` to a place of ANOTHER experience, rebuild and publish the lobby only, step on a pad | `roblox-lobby check` FAILs first; in game: the message "The game place refused the teleport" and you stay in the lobby, able to queue again |
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
| | | | | | |
