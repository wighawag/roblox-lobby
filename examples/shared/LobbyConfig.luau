-- The example's LobbyConfig: plain data, shared by both places and read by scripts/check-places.
-- Ids are 0 until the example experience is published; then fill them in, rebuild and republish.
return {
	experienceId = 0, -- the universe id of the ONE experience holding both places
	lobbyPlaceId = 0, -- its start place, built from lobby.project.json
	places = {
		game = 0, -- built from game.project.json
	},
	queues = {
		{ id = "duo", place = "game", minPlayers = 2, maxPlayers = 2, countdown = 10 },
		{ id = "four", place = "game", minPlayers = 1, maxPlayers = 4, countdown = 15, launchWhenFull = true },
	},
	arrival = { joinTimeout = 30 },
	studio = { joinWindow = 3, fakeMembers = 0 },
}
