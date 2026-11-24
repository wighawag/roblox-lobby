-- Example lobby place, server. The package does the logic; this script only places two quick-start pads.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxLobby = require(ReplicatedStorage.Packages.RobloxLobby)
local config = require(ReplicatedStorage.LobbyConfig)

local lobby = RobloxLobby.Lobby.start(config, {
	teleportData = function(party)
		return { map = "classic", from = party.queueId }
	end,
})

RobloxLobby.Kit.pad(lobby, "duo", CFrame.new(-12, 0.5, -24))
RobloxLobby.Kit.pad(lobby, "four", CFrame.new(12, 0.5, -24), { theme = { color = Color3.fromRGB(80, 140, 255) } })
RobloxLobby.Pads.bind(lobby)

lobby.Launched:Connect(function(party)
	print(
		`[Example] party {party.id} launched from {party.queueId} with {#party.members} player(s), simulated={party.simulated}`
	)
end)
