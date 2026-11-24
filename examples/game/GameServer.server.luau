-- Example game place, server: waits for the party, then "starts" the match.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxLobby = require(ReplicatedStorage.Packages.RobloxLobby)
local config = require(ReplicatedStorage.LobbyConfig)

local arrival = RobloxLobby.Arrival.start(config, {
	studioData = function(_members)
		return { map = "classic", from = "studio" }
	end,
})

arrival.Changed:Connect(function(progress)
	print(`[Example] waiting: {progress.present}/{progress.expected or "?"} ({math.ceil(progress.secondsLeft)} s)`)
end)

arrival.Ready:Connect(function(match)
	local names = {}
	for _, p in match.players do
		table.insert(names, p.Name)
	end
	print(
		`[Example] MATCH READY source={match.source} players={table.concat(names, ",")} missing={#match.missing} map={match.data and match.data.map}`
	)
end)

arrival.Rejected:Connect(function(player, reason)
	print(`[Example] rejected {player.Name}: {reason}`)
end)
