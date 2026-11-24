-- The example's LobbyConfig: plain data, shared by both places and read by scripts/check-places.
-- The ids are those of the private test experience "roblox-lobby test" (operator's account, created 2026-11-24
-- for docs/studio-playtests.md P6 and docs/live-checklist.md). A new game starts with 0s and fills them in after
-- publishing.
return {
	experienceId = 10778829653, -- the universe id of the ONE experience holding both places
	lobbyPlaceId = 138124848909436, -- its start place, built from lobby.project.json
	places = {
		game = 135477523707348, -- built from game.project.json
	},
	queues = {
		{ id = "duo", place = "game", minPlayers = 2, maxPlayers = 2, countdown = 10 },
		{ id = "four", place = "game", minPlayers = 1, maxPlayers = 4, countdown = 15, launchWhenFull = true },
	},
	arrival = { joinTimeout = 30 },
	studio = { joinWindow = 3, fakeMembers = 0 },
}
