--!strict
-- RobloxLobby: a lobby and teleport package for Roblox games. See docs/integration.md.
--
--   Lobby place, server:  RobloxLobby.Lobby.start(require(ReplicatedStorage.LobbyConfig), options)
--   Game place, server:   RobloxLobby.Arrival.start(require(ReplicatedStorage.LobbyConfig), options)
--   Lobby place, client:  RobloxLobby.Client (observe, join, leave, defaultUi)
--   Look and placement:   RobloxLobby.Pads (your tagged models), RobloxLobby.Kit (quick-start pads), Format
--
-- Modules are loaded on first use, so requiring the package from a client does not load server code.

local RobloxLobby = {}

RobloxLobby.VERSION = "0.2.0"

local loaders: { [string]: () -> any } = {
	Lobby = function()
		return require("@self/Lobby")
	end,
	Arrival = function()
		return require("@self/Arrival")
	end,
	Client = function()
		return require("@self/Client")
	end,
	Pads = function()
		return require("@self/Pads")
	end,
	Kit = function()
		return require("@self/Kit")
	end,
	Format = function()
		return require("@self/Format")
	end,
	PlaceCheck = function()
		return require("@self/PlaceCheck")
	end,
	Config = function()
		return require("@self/Config")
	end,
	Envelope = function()
		return require("@self/Envelope")
	end,
	Signal = function()
		return require("@self/Signal")
	end,
}

return setmetatable(RobloxLobby, {
	__index = function(t: any, key: string)
		local load = loaders[key]
		if load then
			local m = load()
			rawset(t, key, m)
			return m
		end
		return nil
	end,
}) :: any
