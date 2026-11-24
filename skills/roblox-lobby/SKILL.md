---
name: roblox-lobby
description: Add a multi-player lobby to a Roblox game: players queue in a lobby place and are teleported together into a game place, using the roblox-lobby package. Use when a Roblox game needs a lobby, matchmaking queues, party teleports between places, or passing data from one place to another.
---

# roblox-lobby

Use the package; never write lobby or teleport code with `TeleportService` yourself. The package handles queues, countdowns, reserved servers, retries, players who leave, and checks the data on arrival. The game keeps full control of how the lobby looks and where its areas are.

Follow the integration guide step by step: `share/roblox-lobby/docs/integration.md` in the installed package (`roblox-lobby version` prints the version; the guide is next to the `src/` folder it vendors). In short:

1. `roblox-lobby vendor .`, then add the `Packages` mapping it prints to BOTH project files (lobby and game).
2. Write `LobbyConfig.luau` (plain data: ids 0 until published, the queues), mapped as `ReplicatedStorage.LobbyConfig` in both places.
3. Lobby place: a server script with `RobloxLobby.Lobby.start(config, ...)` and `RobloxLobby.Pads.bind(lobby)`; lobby areas are the game's own models tagged `RobloxLobbyQueue` with a `QueueId` attribute (or `RobloxLobby.Kit.pad` for a first test); a client script with `RobloxLobby.Client.defaultUi()` or the game's own UI.
4. Game place: a server script with `RobloxLobby.Arrival.start(config, ...)`; start the match in `arrival.Ready`, never in `Players.PlayerAdded`.
5. Playtest each place in Studio and look for the `[RobloxLobby]` lines the guide lists (teleports are SIMULATED in Studio: that is expected).
6. After publishing both places into ONE experience: fill in the ids, rebuild, republish, and run `roblox-lobby check path/to/LobbyConfig.luau`. Every line must say `ok` before telling anyone the game is ready to play with friends.

Never put anything valuable (coins, items) in teleport data: players can see and change it.
