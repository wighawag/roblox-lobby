-- Example lobby place, server. The package does the logic; this script only places two quick-start booths.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxLobby = require(ReplicatedStorage.Packages.RobloxLobby)
local config = require(ReplicatedStorage.LobbyConfig)

local lobby = RobloxLobby.Lobby.start(config, {
	teleportData = function(party)
		return { map = "classic", from = party.queueId }
	end,
})

-- two walled booths, doors facing the spawn (a booth's door is on its local +Z side)
RobloxLobby.Kit.booth(lobby, "duo", CFrame.new(-14, 0, -28))
RobloxLobby.Kit.booth(lobby, "four", CFrame.new(14, 0, -28), { theme = { color = Color3.fromRGB(80, 140, 255) } })
RobloxLobby.Pads.bind(lobby)

lobby.Launched:Connect(function(party)
	print(
		`[Example] party {party.id} launched from {party.queueId} with {#party.members} player(s), simulated={party.simulated}`
	)
end)
