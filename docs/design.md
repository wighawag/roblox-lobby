# roblox-lobby: design (proposal, 2026-11-24)

Status: AGREED by the operator on 2026-11-24 (decisions below), with one addition: the look and the placement of the lobby are the game's, not the package's (section 2b). Implementation: first version in progress; the exact API is documented in `docs/integration.md`, which wins where this launch snapshot differs.

## Operator decisions (2026-11-24)

1. Design OK to build. Addition: importing games must be able to customise the look completely and place the lobby areas wherever they want; the logic is shared, the look is unique per game. Folded into section 2b.
2. Distribution: vendored copy plus a flake package, AND the repo becomes public so the Wally option works too.
3. License: MIT, so proprietary games can use it (`LICENSE` replaced).
4. A small private test experience of the examples may be published under the operator's account, with his Studio session.
5. Open Cloud Luau Execution engine tests: wanted, once the operator has created the API key (how: section 6, "Engine tests in Roblox's cloud").
6. A second client for group tests: the operator can create a second Roblox account, or the kids can join; `docs/live-checklist.md` gives step-by-step instructions.

A reusable Roblox package for the lobby-to-game flow: players gather in a lobby place, join a queue, are grouped into a party, and the party is teleported together into a fresh reserved server of a game place, with data passed across and checked on arrival. Extracted from hips (commit 2adc334: `src/lobby/ServerScriptService/QueueServer/QueueHandler`, `src/game/ServerScriptService/TeleportData.luau`, the debug part of `GameConfig.luau` and `GameManager`). Two users: hips, and the kids' game-making agents on telemaque, who only have Roblox Studio and must get a correct multi-player flow by following the integration guide, without a live client.

## 0. Findings that shape the design

These were checked on 2026-11-24 against primary sources; they change some premises of the brief.

1. **Studio can now run teleports, with limits.** Since 2026-11-05, `TeleportAsync` works in Studio's Test and Team Test modes: the destination place opens as a new local test server, loaded from its latest SAVED cloud version ([announcement](https://devforum.roblox.com/t/test-teleports-in-studio/4977640), [docs: Test teleports in Studio](https://create.roblox.com/docs/projects/teleport#test-teleports-in-studio)). Limits that matter here: both places must be in the same experience as the starting place (same `game.GameId`, so a Rojo-built local `.rbxlx` with no experience cannot teleport), the destination runs its saved cloud version and not the local edits, `game.PrivateServerId` and `game.JobId` are empty in Test mode, and, per a user report in the same thread (2026-11-08 and 2026-11-16), it does NOT work in "Server & Clients" mode ("TeleportPartyAsync error: Doesn't support a guest"), so a GROUP teleport still cannot be exercised in Studio. Consequence: the debug fallback is still needed (local files, groups, kids who have not published), and the package gains a third Studio path, a real single-player teleport when the place is a cloud place.
2. **`ReserveServer` and `ReservedServerAccessCode` are deprecated.** The current way is `TeleportOptions.ReservedServerId = HttpService:GenerateGUID(false)`: the first teleport with a new id creates the reserved server, the same id routes later teleports to it, and in production the destination's `game.PrivateServerId` equals that id ([TeleportOptions](https://create.roblox.com/docs/reference/engine/classes/TeleportOptions), [Teleport to private servers](https://create.roblox.com/docs/projects/teleport-private-servers)). hips uses the deprecated pair today. A GUID per party also removes hips' "reserve the next server after the teleport" step and its pre-reserve at boot.
3. **Arrival data has a server-side guarantee.** `Player:GetJoinData()` (server only) returns `TeleportData`, `SourcePlaceId`, `SourceGameId` and `Members` (the user ids teleported together), and guarantees the data was sent by a Roblox server in the last 48 hours, with this player, from that source place and universe. The data is still client-visible, so nothing secret or valuable goes in it ([Player.GetJoinData in creator-docs](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/Player.yaml)).
4. **Failure handling, per the official guide.** Wrap `TeleportAsync` in `pcall` and retry (the guide's sample: 5 attempts, 1 s apart); a call that succeeds can still fail later per player, reported by `TeleportService.TeleportInitFailed(player, result, message, placeId, options)`: retry after 15 s on `Flooded`, after 1 s on `Failure`, and do not retry the others (`GameNotFound`, `GameEnded`, `GameFull`, `Unauthorized`, `IsTeleporting`) ([Handle failed teleports](https://create.roblox.com/docs/projects/teleport#handle-failed-teleports)). At most 50 players per call, groups only within one experience, server-only ([TeleportService.TeleportAsync](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/TeleportService.yaml)).
5. **The wrong-experience check needs no login.** `https://apis.roblox.com/universes/v1/places/<placeId>/universe` and `https://develop.roblox.com/v1/universes/<universeId>/places` answer without authentication (verified today: both hips places resolve to universe 9520747167, an unknown place returns `{"universeId":null}`), and `https://games.roblox.com/v1/games?universeIds=<id>` gives `rootPlaceId`, the start place.
6. **Headless Luau on Linux.** Lune 0.10.4 (standalone Luau runtime, [docs](https://lune-org.github.io/docs/)) and `luau` 0.725 are in nixpkgs; Lune can also read and write place files (`@lune/roblox`), so a built `.rbxlx` can be inspected in a test. Roblox-API emulators exist (lune-test, LuneTest, 2026, both young single-author projects: [lune-test](https://devforum.roblox.com/t/cli-lune-test-a-local-luau-test-runner-run-and-test-roblox-code-locally/4658410), [LuneTest](https://devforum.roblox.com/t/lunetest-test-your-roblox-game-from-the-terminal/4914875)). Jest Lua, Roblox's own framework, needs `run-in-roblox`, i.e. Studio, to run from the command line ([Jest Lua: Getting started](https://jsdotlua.github.io/jest-lua/)). The engine itself can run tests headlessly only in Roblox's cloud, through Open Cloud Luau Execution (API key, published place, 5 task creates per minute and a reported ~30 per hour) ([docs](https://create.roblox.com/docs/cloud/reference/features/luau-execution)). `StudioTestService:ExecuteMultiplayerTestAsync` (plugin security) scripts multi-client playtests inside Studio ([docs](https://create.roblox.com/docs/reference/engine/classes/StudioTestService)).
7. **Packaging practice.** Wally is still the default Roblox package manager for Rojo projects ([wally.run](https://wally.run/); `wally` 0.3.2 in nixpkgs), installing into a `Packages/` folder mapped to `ReplicatedStorage.Packages`. Its registry only takes public packages, and a Wally manifest cannot depend on a git repository. pesde ([pesde.dev](https://pesde.dev/)) can use the Wally registry and git repositories as sources. This repo was private, so a public registry was out; the operator has decided to make it public (decision 2).

## 1. Distribution

Proposal: **a self-contained source folder, vendored into the consuming project, laid out exactly where Wally would put it**, plus a Wally manifest kept ready.

- The package is one folder, `src/` in this repo, that Rojo turns into one ModuleScript tree, `RobloxLobby`. It has no dependencies.
- A consumer copies it to `Packages/RobloxLobby/` in its own repo and maps `Packages` to `ReplicatedStorage.Packages` in each `*.project.json` (both places). The copy carries a `VERSION` file. This is the lowest-friction path for a kid's agent: no package manager, no network access to a private repo, no submodule, and the place file the kid gets is self-contained. It is also the same location Wally uses, so moving to Wally later changes no `require` path.
- A script in this repo does the copy and checks it: `scripts/roblox-lobby vendor <project-dir>` (copy, write `VERSION`, print the project-file lines to add), and `scripts/roblox-lobby vendor --check <project-dir>` (is the copy identical to this version). The flake package installs it as `roblox-lobby`.
- How the kids' agents reach it is for the my-boxes side: the simplest is that this repo's flake exposes a package (`share/roblox-lobby/` with `src/`, a prebuilt `RobloxLobby.rbxm`, the integration guide and the skill), pinned as a flake input like roblox-player and put on the kids' toolchain with a `roblox-lobby vendor` command.
- hips can do the same (vendor at a tag), or use a git submodule at `Packages/RobloxLobby` since the operator has repo access. Vendoring is recommended there too, for one pattern everywhere.
- `wally.toml` is kept in the repo and the package is published to Wally (as `wighawag/roblox-lobby`) from each release once the repo is public. A project that already uses Wally then adds one line, `RobloxLobby = "wighawag/roblox-lobby@0.1"`, to its `wally.toml` and runs `wally install`, which fills the same `Packages/` folder. Wally, in one sentence for the operator: it is to Roblox projects what npm is to JavaScript, a registry plus a command that downloads a project's declared libraries into a folder that Rojo then syncs into the game.

Rejected: a git submodule for the kids (needs GitHub access from the kid account and git knowledge from the agent); Wally or pesde from a private git repository (needs a token in every kid account); a Roblox Creator Store model (needs a publish step under some account and is not versioned with the code).

## 2. API surface

One `LobbyConfig` ModuleScript per game, shared by both places (pure data, in `ReplicatedStorage`), so the place ids live in exactly one file and both places and the no-client check read the same values:

```lua
-- ReplicatedStorage/LobbyConfig.luau (pure data: also read by scripts/check-places.luau)
return {
	experienceId = 9520747167,          -- the universe; checked at runtime against game.GameId
	lobbyPlaceId = 74888767056358,      -- the start place
	places = {
		game = 106268450656854,         -- named destinations
	},
	queues = {
		{ id = "duo",  place = "game", minPlayers = 2, maxPlayers = 2, countdown = 10 },
		{ id = "four", place = "game", minPlayers = 2, maxPlayers = 4, countdown = 20, launchWhenFull = true },
	},
	arrival = { joinTimeout = 30 },
	studio = { joinWindow = 3, fakeMembers = 0 },
}
```

`Config.validate(config)` runs at startup in both places and fails loudly with every problem listed (missing ids, `minPlayers > maxPlayers`, `maxPlayers > 50`, an unknown `place` name, unknown keys, which catch typos).

**Lobby place, server:**

```lua
local RobloxLobby = require(ReplicatedStorage.Packages.RobloxLobby)
local lobby = RobloxLobby.Lobby.start(require(ReplicatedStorage.LobbyConfig), {
	teleportData = function(party) return { mode = "classic" } end,  -- optional game data, small and non-secret
})
lobby:join(player, "four")      -- from any trigger: a pad, a ProximityPrompt, a GUI button (through a remote the package provides)
lobby:leave(player)
lobby.Changed:Connect(function(queueId, state) end)    -- members, countdown, phase: drives the game's own UI
lobby.Launched:Connect(function(party) end)            -- party.id (the ReservedServerId), members, place
lobby.LaunchFailed:Connect(function(party, players, reason) end)
```

Joining is trigger-agnostic. The package ships an optional kit on top: `RobloxLobby.Pads` binds any Part tagged `RobloxLobbyQueue` with a `QueueId` attribute as a join pad, and `RobloxLobby.Client` shows a minimal status line and a Leave button. A game with its own UI (hips) uses only `Changed` and the remotes.

### 2b. Look and placement belong to the game

The package owns the logic (who is in which queue, the countdown, the launch, the teleport, the arrival) and NOTHING visual by default. Three levels, from most to least work for the game, all supported and documented:

1. **Headless (full control).** The game builds its own lobby areas, models, billboards, cameras and GUI anywhere in its world. It calls `lobby:join` and `lobby:leave` from its own triggers and draws everything from `lobby.Changed` (server) or from the replicated queue state on the client (`RobloxLobby.Client.observe(queueId, callback)` gives members, capacity, seconds left and phase, read-only). hips works this way: its existing pads, camera move and billboard stay hips' code.
2. **Tagged areas (placement free, look free, wiring done).** Any model or part the game builds, anywhere, becomes a queue area by tagging it `RobloxLobbyQueue` and setting a `QueueId` attribute. Optional children by name give behaviour, not look: an `Enter` part (touch to join; default: the tagged part itself), an `EnterPos` and `ExitPos` (where a joining or leaving player is moved; default: not moved), a `CamPos` (camera for queued players; default: unchanged). Every visual (shape, colour, signage, effects) is whatever the game modelled. Per-area options (`TouchToJoin`, `MovePlayer`, `ProximityPrompt`) are attributes, so a kid's agent can configure an area without code.
3. **Default kit (quick start).** `RobloxLobby.Kit` can create a plain pad with a billboard, and `RobloxLobby.Client.defaultUi()` a small status line and Leave button, for a first playtest. Its colours, fonts, texts and sizes come from a `theme` table, every text goes through a `format` function the game can override (wording, language), and each piece can be replaced by passing the game's own ScreenGui or BillboardGui template: the kit then only sets the `Text` of children with known names (`Players`, `Time`, `Status`) and toggles the `Leave` button. A game outgrows the kit by deleting it, with no change to its queue logic.

The same split holds on the game side: arrival has no UI; a waiting-for-players screen is the game's, fed by `arrival.Changed` (present, expected, seconds left). A custom teleport loading screen is a parameter (`teleportGui`, passed to `TeleportService:SetTeleportGui` on the clients of the party). Queue sizes and countdowns live in `LobbyConfig`; where and how the areas look lives in the game's world.

**Game place, server:**

```lua
local arrival = RobloxLobby.Arrival.start(require(ReplicatedStorage.LobbyConfig))
arrival.Ready:Connect(function(match)
	-- match.id, match.queueId, match.players (present), match.expected (user ids),
	-- match.missing, match.data (the game's own teleportData), match.fakeMembers, match.source ("teleport" | "studio")
end)
arrival.Rejected:Connect(function(player, reason) end)  -- no or invalid teleport data, wrong source place, not a member
arrival:returnToLobby(players)                           -- same retrying teleport, back to the lobby place
```

`Ready` fires once per server: when every expected member is present, or after `joinTimeout` with whoever came (`match.missing` lists the others). A party member arriving after `Ready` is accepted and reported by `arrival.PlayerJoined(player, { late = true })`; the game decides what to do with them. A player who is not part of the match (direct join, another party, bad data) fires `Rejected` and, by `onRejected`, is teleported back to the lobby (default; kicked with an explanation if that fails), kicked, or kept. In Studio, rejected players are only reported.

## 3. Teleport plumbing

All of it server-side; clients only ask to join or leave through a rate-limited remote, and the server decides.

- **Per queue state machine** (pure, unit-tested): `idle` > `counting` (when `minPlayers` are in; reset when below) > `launching` (at 0, or at once when full and `launchWhenFull`) > back to `idle`. One party per launch; a queue can open a new party while the previous one is still launching.
- **Party integrity.** At launch the party is frozen: its members cannot leave through the queue or join another, and are re-checked (still in `Players`, not already teleporting). If leavers drop it below `minPlayers`, the launch is cancelled and the rest go back to `counting`.
- **The teleport.** One `TeleportOptions` per party with `ReservedServerId = GenerateGUID(false)` (the party id) and the teleport data envelope; `TeleportAsync(placeId, members, options)` in `pcall`, retried up to 5 times with backoff on a thrown error. Never the deprecated `ReserveServer`, `ReservedServerAccessCode` or `TeleportPartyAsync`.
- **Per-player failures.** `TeleportInitFailed` for a party member: `Flooded` retried after 15 s, `Failure` after 1 s (at most 3 times per player), always to the SAME `ReservedServerId` with the same data so the player still joins their party; any other result is final: the player is released back to the lobby with a message, and `LaunchFailed` fires. A member still in the lobby server well after the launch (timeout, default 30 s) with no event is treated the same way.
- **Leaving mid-teleport.** `PlayerRemoving` of a launching member counts as departed (it is also what a successful teleport looks like on the origin side); the game side then sees that member as missing.
- **Teleport data envelope**, versioned: `{ rl = 1, matchId, queueId, lobbyPlaceId, members = { userIds }, sentAt, data = <the game's own table> }`. On arrival, from `GetJoinData()` only (never the client's copy): `SourceGameId == game.GameId`, `SourcePlaceId == lobbyPlaceId`, `rl` known, player in `members`, and `matchId` equal for everyone in the server; in production also `game.PrivateServerId == matchId` (not in Studio, where it is empty). A failed check is a `Rejected` with a reason, never a crash.
- **Runtime place guard.** Each place logs its `game.PlaceId` and `game.GameId` at startup and errors clearly when they do not match `LobbyConfig` (outside Studio), which turns the wrong-experience publish into one obvious log line.
- **Docs for the experience settings**: Access Control for Places "Secure within universe only" is recommended (players cannot join the game place directly), and the arrival check copes either way.

## 4. Studio fallback

The package detects the situation and logs which path it takes, so a playtest's Output says what was and was not exercised:

| situation | lobby side | game side |
| --- | --- | --- |
| local file (`game.GameId == 0`), any mode | SIMULATED launch: the party, the target place and the exact envelope are logged and `Launched` fires with `simulated = true`; the players are released after a few seconds | debug arrival: no teleport data, so after `studio.joinWindow` (3 s, Server & Clients joins clients about 1 to 2 s apart) a synthetic envelope is built with the same builder as the lobby's and passed through the same validator, and `Ready` fires with `source = "studio"` and `studio.fakeMembers` spare slots for the game's own bots |
| cloud place, solo Test mode | REAL teleport (Studio's new support): destination is its latest saved cloud version, so arrival data and validation run for real, for one player | real arrival path (`PrivateServerId` check skipped, it is empty in Test mode) |
| cloud place, Server & Clients | simulated, because Studio rejects guest teleports | debug arrival as above |

A `studio = { teleport = "auto" | "simulate" }` option forces the simulated path. Debug behaviour is only ever on when `RunService:IsStudio()`, so it cannot leak into a published server. Bots stay game-specific (hips' `FakePlayers`); the package only reports the spare slots.

## 5. No-client configuration check

`lune run scripts/check-places <path/to/LobbyConfig.luau>` (also wrapped as `roblox-lobby check` in the flake package) reads the same `LobbyConfig` and, through the public endpoints of finding 5: every place id resolves to `experienceId`; `lobbyPlaceId` is the experience's `rootPlaceId`; the destinations are places of that experience (with their names printed, so "HIPS" versus "HIPS_Lobby" is visible). Exit code non-zero with a one-line reason per failure. It runs in seconds, needs no Roblox account, and is the step the kids' guide puts right after every publish. Its HTTP part is behind a small interface so the tests run it against recorded responses, offline.

## 6. Testing

Three layers, the first one carrying most of the weight.

1. **Unit tests, headless, in CI and on any Linux box**: `lune run tests` (Lune from nixpkgs, in the flake's dev shell). The logic is written as pure modules with their effects injected (clock, teleport function, player list, HTTP), and the thin Roblox adapters take their services as parameters, so both are tested with plain fakes, no Roblox emulator: queue state machine (thresholds, countdown reset, full-launch, leave during count, leave during launch, two queues, re-entry), the retry policy per `TeleportResult`, the timeout of a silent failure, envelope build and validation (every rejection reason), config validation, arrival decisions (all present, timeout, late join, wrong match id), the Studio path selection, and the check script on recorded API answers. A small in-repo test harness (`describe`/`it`/`expect`), no third-party framework. Plus StyLua and Selene on every run.
2. **Build test**: `rojo build` the example places in `examples/` (a lobby and a game place using the package exactly as the guide says), then a Lune script opens the built `.rbxlx` files and asserts the structure (the package under `ReplicatedStorage.Packages`, the remotes, the config).
3. **Studio playtests on telemaque, the operator's loop** (hips `TESTING.md`), scripted with the shared driver: example lobby solo (simulated launch, log lines asserted), example game in Server & Clients with 2 clients (debug arrival, `Ready` with 2 players), and, once the example experience is published, a real solo teleport in Test mode (arrival validated for real).
4. **Live checklist, once per release, in Sober** (`docs/live-checklist.md`): `check-places` passes; one player queues, teleports, arrives with valid data; two players arrive in the SAME server (a second client: the operator's second Roblox account on another device, or a kid joining from their own PC, following the checklist's step-by-step instructions: open the test experience link, walk onto the named pad, say what the screen shows); leave during countdown; a member leaving during launch; joining the game place directly is rejected and sent to the lobby; a wrong place id gives the clear runtime error; return to lobby. Results recorded per release.

5. **Engine tests in Roblox's cloud** (operator decision 5). What it is: Roblox's Open Cloud "Luau Execution" lets a program on telemaque ask Roblox to start a real, headless Roblox game server for a given place, run a Luau script in it and return the output; no Studio, no client, no screen. A test run publishes the current build of a TEST place (in the private test experience of decision 4, never a real game), then runs the package's engine tests inside it (real `Instance`s, `TeleportOptions`, `HttpService:GenerateGUID`, `Players`, config and envelope checks against the engine's real types). It cannot test an actual teleport (there is no player in such a server), which stays with Studio and Sober. Limits: a task runs up to 5 minutes; about 5 task creations per minute and a reported ~30 per hour, so it is a per-release or per-merge check, not a per-save one.

   How the operator gets the key: sign in at [create.roblox.com/dashboard/credentials](https://create.roblox.com/dashboard/credentials) (Creator Dashboard > Open Cloud > API Keys) and click "Create API Key". Name it `roblox-lobby-tests`. Under Access Permissions add the API **Luau Execution Session** with the operation `universe.place.luau-execution-session:write`, and the API **Universe Places** (place publishing) with `universe-places:write`, both with "Restrict by Experience" ON and only the test experience selected, so the key cannot touch hips or anything else. Leave the IP restriction off (or set telemaque's public IP) and no expiration date; note that Roblox disables a key unused for 60 days (re-enable it with its toggle). Copy the secret once, and store it on telemaque in a file only the operator can read, e.g. `~/.config/roblox-lobby/api-key` (mode 600), never in the repo. The exact permission names are re-checked against the dashboard when the key is made ([API keys docs](https://create.roblox.com/docs/cloud/auth/api-keys), [Luau Execution](https://create.roblox.com/docs/cloud/reference/features/luau-execution)). Accepted risk to state: while the kids' sessions can reach the operator's wherever (kid-game-studios Accepted Risk 1), they could reach this file too; its scope (one test experience) bounds what it allows.

## 7. Agent-facing integration guide

`docs/integration.md`, written as numbered mechanical steps for an agent, also shipped as a skill (`skills/roblox-lobby/SKILL.md`):

1. `roblox-lobby vendor .` and add the two `Packages` lines to both project files.
2. Write `ReplicatedStorage/LobbyConfig.luau` from the template (place ids `0` until published).
3. Lobby place: a server script with `Lobby.start` (template), and either tagged pads or a button.
4. Game place: a server script with `Arrival.start` and the game's start logic inside `Ready` (template), never starting on `PlayerAdded` directly.
5. Playtest each place in Studio and look for the expected log lines (listed verbatim in the guide: the simulated launch line, the debug arrival line).
6. After publishing both places into ONE experience: fill in the ids, rebuild, republish, run `roblox-lobby check`, and only then tell the kid it is ready to try on their own PC.

It also lists the failure messages and what each means.

## 8. Migration plan for hips (the hips session's job, hips/studio-loop)

1. Vendor the package at a release tag into `Packages/RobloxLobby`, add `Packages` to both project files.
2. Add `ReplicatedStorage/LobbyConfig.luau` with HIPS_Lobby's ids (universe 9520747167, lobby 74888767056358, game 106268450656854), and the queue sizes from `Workspace/Queues` (`MaximumPlayers`, `MinimumPlayers`, `CountDownTime`, `InstantTeleport` map to `maxPlayers`, `minPlayers`, `countdown`, `launchWhenFull`).
3. Lobby: replace `QueueHandler` by `Lobby.start` plus a small hips adapter that keeps its pads, camera and billboard (Refs.Enter, EnterPos, ExitPos, CamPos, BillboardGui) driven by `Changed`; drop the deprecated `ReserveServer`.
4. Game: replace `TeleportData.luau` and the debug-join part of `GameManager` by `Arrival`; `Ready` gives `expectedPlayerCount` (`#match.expected`) and `fakeMembers` replaces `DebugFakePlayers` as the slot count, while `FakePlayers.luau` stays in hips.
5. Run `roblox-lobby check` on the config, the Studio loop, then the live checklist in Sober.

## Questions for the operator (answered 2026-11-24, see Operator decisions)

1. Is this design OK to build (scope, API shape, the three Studio paths)?
2. Distribution: vendored copy plus a flake package (proposed, works with a private repo), or make the repo public and publish to Wally?
3. License: the repo is AGPL-3.0. A game that embeds it and runs it on Roblox servers is "interacting with users over a network", so a MODIFIED copy obliges offering its source to players (AGPL section 13). Keep AGPL for the package, or use a permissive or file-level license (MIT, or MPL-2.0) so kids' and other games can embed it without that question?
4. May I (later, with your Studio session) publish a small private test experience of the examples under your account, for the Studio real-teleport test and the Sober checklist?
5. Open Cloud Luau Execution engine tests: wanted (you would create an API key), or not now?
6. The group part of the live checklist needs two real clients in the same experience at once (Sober plus another device or account). Is that available?
