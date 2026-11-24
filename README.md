# roblox-lobby

A reusable, well-tested lobby and teleport package for Roblox games: players gather in a lobby place, get queued and grouped, and are teleported together to a game place. Extracted from hips (`wighawag/hips`), which will then use it instead of its own lobby code.

Goal: a game (including one written by a kid's agent) gets a correct multi-player lobby-to-game flow by depending on this package, without having to test teleports in a live Roblox client itself. The package is tested once, properly, including live in the real client.

Status: design proposed (`docs/design.md`), waiting for the operator's OK; only scaffolding exists.

Development: `nix develop`, then `lune run tests` (unit tests), `stylua --check src tests`, `selene src`.

License: MIT (see `LICENSE`), so proprietary games can embed it.
