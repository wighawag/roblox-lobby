# Integrating roblox-lobby into a game (for agents)

Follow these steps in order. They give a game a lobby place where players queue, and a game place where the party arrives together, with the teleport, its failures and the arrival checks handled by the package. The package owns the logic only: where the lobby areas are and what they look like is the game's.

Vocabulary: an **experience** (Roblox calls it a universe) holds several **places**. The **lobby place** is its start place; the **game place** is where matches run. Both must be in the SAME experience: this is the most common live failure, and step 7 checks it.

## 1. Two places, one Rojo project each

A game with a lobby has two Rojo project files, e.g. `lobby.project.json` and `game.project.json`, each building one place. Code shared by both goes under `ReplicatedStorage` in both.

## 2. Add the package

```
roblox-lobby vendor .
```

This copies the package to `Packages/RobloxLobby/` (with a `VERSION` file). Then in EACH project file, under `"ReplicatedStorage"`, add:

```json
"Packages": { "$className": "Folder", "RobloxLobby": { "$path": "Packages/RobloxLobby" } },
```

Commit `Packages/RobloxLobby/` with the game: the built place file then contains everything. To update later, run `roblox-lobby vendor .` again; `roblox-lobby vendor --check .` tells whether the copy is current. (A project that uses Wally can instead add `RobloxLobby = "wighawag/roblox-lobby@0.1"` under `[dependencies]` in `wally.toml` and run `wally install`: same folder, same `require`.)

## 3. Write the LobbyConfig (shared by both places)

Create `src/shared/LobbyConfig.luau` (any path) and map it as `ReplicatedStorage.LobbyConfig` in BOTH project files:

```json
"LobbyConfig": { "$path": "src/shared/LobbyConfig.luau" },
```

```lua
-- Plain data only: no require, no Roblox API (the check in step 7 reads this file outside Roblox).
return {
	experienceId = 0, -- fill in after publishing (step 6)
	lobbyPlaceId = 0,
	places = {
		game = 0,
	},
	queues = {
		-- id: your name for it; place: a key of `places`
		-- minPlayers: needed to start the countdown; maxPlayers: party size (at most 50)
		-- countdown: seconds once minPlayers are in (default 15)
		-- fullCountdown: once the queue is full, the time left is cut to this (default 5; 0 = go at once)
		{ id = "duo", place = "game", minPlayers = 2, maxPlayers = 2, countdown = 10 },
		{ id = "squad", place = "game", minPlayers = 2, maxPlayers = 4, countdown = 20 },
	},
	arrival = { joinTimeout = 30 }, -- game place: start at most this long after the first player arrives
	studio = { joinWindow = 3, fakeMembers = 0 }, -- Studio playtests only, see step 5
}
```

A mistake in this file stops the server with a message listing every problem (a typo such as `maxPlayer` is reported as an unknown key).

## 4. The lobby place

Server script, e.g. `ServerScriptService/Lobby.server.luau`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxLobby = require(ReplicatedStorage.Packages.RobloxLobby)

local lobby = RobloxLobby.Lobby.start(require(ReplicatedStorage.LobbyConfig), {
	-- optional: data the game place receives. Small, and NOTHING secret or valuable (players can see and alter it).
	teleportData = function(party)
		return { mode = "classic" }
	end,
})
RobloxLobby.Pads.bind(lobby)
```

Then give each queue a place in the world. Pick ONE of:

- **Your own models (recommended).** Build each lobby area however the game looks, anywhere. On the area (a Part or a Model) add the tag `RobloxLobbyQueue` and the attribute `QueueId` set to a queue id from the config. Optional parts inside the area, by name:
  - `Enter`: the part whose touch joins (with it, only `Enter` joins, so walls and decorations never do; without it, any part of the area joins).
  - `EnterPos`: where a joining player is placed.
  - `ExitPos`: where a leaving player is placed (add one; otherwise a player who presses Leave stays on the pad).
  - `CamPos`: the camera while queued (used by `Client.defaultUi`).
  - `Zone`: the inside of a booth, an invisible non-colliding part: a queued player who walks out of it leaves the queue within about half a second.

  A walled booth, the HIPS pattern, is: walls and a floor (any names), an invisible non-colliding `Enter` across the doorway, `EnterPos` inside, `ExitPos` outside the door, `CamPos` looking in, and a `Zone` covering the inside. Optional attributes: `TouchToJoin = false` (no touch), `Prompt = true` (a "Join" ProximityPrompt). In a Rojo project file: `"DuoBooth": { "$className": "Model", "$properties": { "Tags": ["RobloxLobbyQueue"] }, "$attributes": { "QueueId": "duo" }, ...parts... }` (checked with Rojo 7.6.1).
- **Quick-start booths or pads**, for a first playtest: in the server script, before `Pads.bind`, `RobloxLobby.Kit.booth(lobby, "duo", CFrame.new(-14, 0, -28))` (a walled booth with all the parts above, door on its local +Z side) or `RobloxLobby.Kit.pad(lobby, "duo", CFrame.new(-12, 0.5, -24))` (a flat pad). Options: `theme = { color, floorColor, material, size, textColor, font }`, `format = { players = function(view) ... end, time = ... }`, `billboard = <your BillboardGui>` (the kit only sets the `Text` of its descendants named `Players` and `Time`).
- **Your own triggers** (buttons, menus, NPCs): call `lobby:join(player, "duo")` and `lobby:leave(player)` from the server, or `RobloxLobby.Client.join("duo")` / `Client.leave()` from the client.

Client script, e.g. `StarterPlayer/StarterPlayerScripts/Lobby.client.luau`. Either the quick-start UI:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxLobby = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("RobloxLobby"))
RobloxLobby.Client.defaultUi() -- options: theme, format, template (your ScreenGui with "Status" and "Leave"), camera
```

or your own UI, fed by `Client.observe(queueId, function(view) ... end)` (`view.count`, `view.capacity`, `view.minPlayers`, `view.phase` = "waiting" or "counting", `view.secondsLeft`, `view.members`), `Client.onMyQueueChanged(function(queueIdOrNil) ... end)` and `Client.onNotice(function(message) ... end)` (messages from the server, e.g. a failed teleport).

Server-side signals, for logs or the game's own effects: `lobby.Changed(queueId, view)`, `lobby.PlayerJoinedQueue(player, queueId)`, `lobby.PlayerLeftQueue(player, queueId)`, `lobby.Launched(party)` (`party.id`, `party.members`, `party.simulated`), `lobby.LaunchFailed(party, players, reason)`.

## 5. The game place

Server script, e.g. `ServerScriptService/Match.server.luau`. Start the game from `Ready`, NEVER from `Players.PlayerAdded`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxLobby = require(ReplicatedStorage.Packages.RobloxLobby)

local arrival = RobloxLobby.Arrival.start(require(ReplicatedStorage.LobbyConfig), {
	-- what a Studio playtest pretends the lobby sent (same shape as teleportData in step 4)
	studioData = function(members)
		return { mode = "classic" }
	end,
})

arrival.Ready:Connect(function(match)
	-- match.players: the players to play with (present now)
	-- match.data: the lobby's teleportData; match.expected / match.missing: user ids
	-- match.fakeMembers: in Studio, extra slots the game may fill with bots (studio.fakeMembers), 0 live
	-- match.source: "teleport" (real) or "studio" (debug playtest)
	startGame(match.players, match.data)
end)

arrival.PlayerJoined:Connect(function(player, info)
	if info.late then
		-- a party member who arrived after the start: add them, or not
	end
end)
```

Optional: `arrival.Changed(progress)` for a waiting screen (`progress.present`, `progress.expected`, `progress.secondsLeft`), `arrival.Rejected(player, reason)`, and `arrival:returnToLobby(players)` at the end of a match. Players who join the game place directly, or with bad data, are sent back to the lobby (option `onRejected = "lobby" | "kick" | "keep"`).

## 6. Playtest in Studio

Teleports do not happen in a Studio playtest of a local place file, so the package switches to a debug path and says so in the Output. Check for these lines:

- Lobby place, Play (solo): walk onto a pad. With `minPlayers = 1` or a Server & Clients test with enough clients, at the end of the countdown: `[RobloxLobby] Studio: SIMULATED teleport (local file) of party ...` followed by the teleport data that would be sent. The players are released into the lobby after 3 seconds.
- Game place, Play, or Server & Clients with N clients: `[RobloxLobby] game place started in Studio`, then after `studio.joinWindow` seconds `[RobloxLobby] match studio-... ready (studio): N player(s)`, and your `Ready` code runs.

Any `[RobloxLobby] CONFIG PROBLEM` or `invalid LobbyConfig` line must be fixed before going further.

Once both places are published (step 7), a solo Play of the lobby opened from Roblox (File > Open from Roblox, not the local file) can do a REAL teleport into the game place's last published version: the log then says `party ... teleporting` instead of SIMULATED. Group teleports cannot be tested in Studio.

## 7. Publish, fill in the ids, check

1. Publish the lobby place as a NEW experience: open the lobby's place file, File > Publish As > "Create new experience...", give it a name, Next. It becomes the experience's start place. Then open the game's place file, File > Publish As, click the tile of THAT experience, choose "Add as a new place", Create. Never pick another experience with a similar name. To publish an update later, the same dialog: the experience tile, then the place to overwrite, then Overwrite.
2. Find the ids: in Studio, `print(game.GameId, game.PlaceId)` in the command bar of each published place, or the Creator Dashboard. `GameId` is the experience id.
3. Fill in `experienceId`, `lobbyPlaceId` and `places` in `LobbyConfig.luau`, rebuild BOTH places, publish both again.
4. Run the check (no Roblox login needed):

```
roblox-lobby check src/shared/LobbyConfig.luau
```

Every line must start with `ok`. A `FAIL` line names the wrong id and why (e.g. `belongs to experience X, NOT Y`).

5. Only then is the game ready to try with real players (on a real Roblox client, e.g. the kid's own PC: Play the experience, walk onto a pad with a friend).

## Messages and what they mean

| message | meaning | fix |
| --- | --- | --- |
| `invalid LobbyConfig: ...` | the config has the listed problems | fix them |
| `CONFIG PROBLEM: this server's experience is X but LobbyConfig.experienceId is Y` | the place was published into the wrong experience, or the config is stale | republish into the right experience, or fix the ids |
| `CONFIG PROBLEM: ... not in LobbyConfig.places` | this game place's id is not configured | fill in `places` |
| `Studio: SIMULATED teleport` | normal in Studio | nothing |
| `Studio refused the real teleport` | normal in Server & Clients mode | nothing |
| `TeleportAsync to place ... failed (attempt n)` | a teleport call failed; it is retried | if it keeps failing: run `roblox-lobby check` |
| player sees `The game place refused the teleport` | Roblox answered Unauthorized: usually a place of another experience | `roblox-lobby check` |
| player sees `The game place was not found` | the place id is wrong | `roblox-lobby check` |
| player sees `The game place could not be reached: its place id is probably wrong.` (log: `HTTP 400 (Bad Request)`, `not retrying: this error is permanent`) | the place id does not exist | `roblox-lobby check` |
| `rejected <name>: no-teleport-data` | someone joined the game place directly | normal; they are sent to the lobby |
| `rejected <name>: unknown-version` | the two places run different roblox-lobby versions | vendor the same version, publish both |
| `rejected <name>: wrong-source-place` / `wrong-source-game` | the teleport did not come from this game's lobby | check the ids |

## Rules

- Teleports are started by the server only. Never call `TeleportService` from a LocalScript, and never call `TeleportService` yourself for the lobby flow: use the package.
- Teleport data is visible to players: never put coins, items or anything valuable in it. Save those with DataStores.
- Keep both places on the same roblox-lobby version: vendor once, build and publish both.
