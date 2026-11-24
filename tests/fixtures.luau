--!strict
-- Shared test data.
local Fixtures = {}

function Fixtures.config(): any
	return {
		experienceId = 9520747167,
		lobbyPlaceId = 74888767056358,
		places = { game = 106268450656854 },
		queues = {
			{ id = "duo", place = "game", minPlayers = 2, maxPlayers = 2, countdown = 10 },
			{ id = "four", place = "game", minPlayers = 2, maxPlayers = 4, countdown = 20, launchWhenFull = true },
		},
	}
end

return Fixtures
