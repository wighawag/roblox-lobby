# roblox-lobby

A reusable, well-tested lobby and teleport package for Roblox games: players gather in a lobby place, join queues, and are teleported together as a party into a fresh reserved server of a game place, with data passed across and checked on arrival. Extracted from hips (`wighawag/hips`), which will then use it instead of its own lobby code.

Goal: a game (including one written by a kid's agent) gets a correct multi-player lobby-to-game flow by depending on this package and following [docs/integration.md](docs/integration.md), without testing teleports in a live Roblox client itself. The package is tested once, properly, including live in the real client ([docs/live-checklist.md](docs/live-checklist.md)).

- Logic only: queues, countdowns, party launch, `TeleportAsync` with reserved servers, retries and `TeleportInitFailed`, players leaving mid-teleport, arrival validation from `Player:GetJoinData()`.
- The look and the placement of lobby areas belong to the game: its own tagged models, its own UI, or a themable quick-start kit.
- Studio: teleports are simulated (and logged) for local files, the game place gathers Studio clients into a debug match, and a real single-player teleport runs when Studio supports it.
- `roblox-lobby check LobbyConfig.luau` confirms through Roblox's public web APIs that every place id belongs to the intended experience, without a client.

Install: `roblox-lobby vendor <project>` (from the flake package: `nix run github:wighawag/roblox-lobby -- vendor .`), or with Wally `RobloxLobby = "wighawag/roblox-lobby@0.1"`.

Design and decisions: [docs/design.md](docs/design.md). Studio loop: [docs/studio-playtests.md](docs/studio-playtests.md). Agent skill: [skills/roblox-lobby/SKILL.md](skills/roblox-lobby/SKILL.md).

Development: `nix develop`, then `lune run tests` (unit and adapter tests, headless), `lune run scripts/build-check` (Rojo build of the examples, inspected), `stylua --check src tests scripts examples`, `selene src`. `nix flake check` runs all of them.

License: MIT (see `LICENSE`), so proprietary games can embed it.
