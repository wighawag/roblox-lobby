--!strict
-- Everything the adapters (Lobby, Arrival) take from Roblox, in one table, so tests can pass a fake one.
-- Env.roblox() builds the real one; it is only called inside Roblox (Lune has no `game`).

export type Env = {
	Players: any,
	TeleportService: any,
	HttpService: any,
	ReplicatedStorage: any,
	isStudio: boolean,
	gameId: number,
	placeId: number,
	privateServerId: string,
	newInstance: (className: string) -> any,
	now: () -> number,
	wait: (seconds: number) -> (),
	spawn: (fn: () -> ()) -> (),
	delay: (seconds: number, fn: () -> ()) -> (),
	print: (...any) -> (),
	warn: (...any) -> (),
	jsonEncode: (value: any) -> string,
}

local Env = {}

function Env.roblox(): Env
	local g = game :: any
	local HttpService = g:GetService("HttpService")
	return {
		Players = g:GetService("Players"),
		TeleportService = g:GetService("TeleportService"),
		HttpService = HttpService,
		ReplicatedStorage = g:GetService("ReplicatedStorage"),
		isStudio = g:GetService("RunService"):IsStudio(),
		gameId = g.GameId,
		placeId = g.PlaceId,
		privateServerId = g.PrivateServerId,
		newInstance = function(className: string)
			return (Instance :: any).new(className)
		end,
		now = os.clock,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		spawn = function(fn: () -> ())
			task.spawn(fn)
		end,
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
		print = print,
		warn = warn,
		jsonEncode = function(value: any): string
			local ok, s = pcall(HttpService.JSONEncode, HttpService, value)
			return if ok then s else tostring(value)
		end,
	}
end

return Env
