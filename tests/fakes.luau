--!strict
-- A fake Roblox world for adapter tests: a manual clock with a cooperative scheduler, Players, TeleportService,
-- HttpService, Instances with attributes, RemoteEvents. Only what Lobby.luau and Arrival.luau use.

local Signal = require("../src/Signal")

local Fakes = {}

local function newInstance(className: string): any
	local inst: any = { ClassName = className, Name = className, Parent = nil, _attrs = {}, _destroyed = false }
	function inst.SetAttribute(i: any, k: string, v: any)
		i._attrs[k] = v
	end
	function inst.GetAttribute(i: any, k: string)
		return i._attrs[k]
	end
	function inst.Destroy(i: any)
		i._destroyed = true
		i.Parent = nil
	end
	if className == "RemoteEvent" then
		inst.OnServerEvent = Signal.new(error)
		inst.sent = {}
		function inst.FireClient(i: any, player: any, ...)
			table.insert(i.sent, { player = player, args = { ... } })
		end
	elseif className == "TeleportOptions" then
		inst.ReservedServerId = ""
		function inst.SetTeleportData(i: any, d: any)
			i._data = d
		end
		function inst.GetTeleportData(i: any)
			return i._data
		end
	end
	return inst
end

function Fakes.world(over: any?)
	local o = over or {}
	local w: any = { time = 0, threads = {}, logs = {}, warnings = {}, teleports = {}, guid = 0, instances = {} }

	-- the last created instance with that Name (queue folders are named by queue id)
	function w.instance(name: string): any
		for i = #w.instances, 1, -1 do
			if w.instances[i].Name == name then
				return w.instances[i]
			end
		end
		return nil
	end

	-- scheduler: threads waiting until a time; advance() runs them in time order
	local function schedule(at: number, co: thread)
		table.insert(w.threads, { at = at, co = co })
	end
	local function resume(co: thread)
		local ok, err = coroutine.resume(co)
		if not ok then
			error(err, 0)
		end
	end
	function w.advance(seconds: number)
		local target = w.time + seconds
		while true do
			local best, bi = nil, nil
			for i, t in w.threads do
				if t.at <= target and (best == nil or t.at < best.at) then
					best, bi = t, i
				end
			end
			if not best then
				break
			end
			table.remove(w.threads, bi)
			w.time = math.max(w.time, best.at)
			resume(best.co)
		end
		w.time = target
	end

	-- Players
	local players: { any } = {}
	local Players: any = { PlayerAdded = Signal.new(error), PlayerRemoving = Signal.new(error) }
	function Players.GetPlayers(_: any)
		return table.clone(players)
	end
	function Players.GetPlayerByUserId(_: any, userId: number)
		for _, p in players do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end
	function w.addPlayer(userId: number, joinData: any?): any
		local p: any = { UserId = userId, Name = "P" .. userId, Parent = Players, kicked = nil, _attrs = {} }
		function p.GetJoinData(_: any)
			return joinData or {}
		end
		function p.Kick(self: any, msg: string)
			self.kicked = msg
		end
		table.insert(players, p)
		Players.PlayerAdded:Fire(p)
		return p
	end
	function w.removePlayer(p: any)
		local i = table.find(players, p)
		if i then
			table.remove(players, i)
		end
		Players.PlayerRemoving:Fire(p)
		p.Parent = nil
	end

	-- TeleportService: w.teleportBehaviour(placeId, players, options) may error to simulate a thrown failure;
	-- by default the call succeeds and nobody leaves (the test decides who "arrives").
	local TeleportService: any = { TeleportInitFailed = Signal.new(error) }
	w.teleportBehaviour = nil
	function TeleportService.TeleportAsync(_: any, placeId: number, list: { any }, options: any)
		table.insert(w.teleports, { placeId = placeId, players = table.clone(list), options = options })
		if w.teleportBehaviour then
			return w.teleportBehaviour(placeId, list, options)
		end
		return nil
	end
	function w.initFailed(player: any, resultName: string)
		TeleportService.TeleportInitFailed:Fire(player, { Name = resultName }, "test failure", 0, nil)
	end

	local HttpService: any = {}
	function HttpService.GenerateGUID(_: any, _wrap: boolean)
		w.guid += 1
		return "GUID-" .. w.guid
	end

	w.ReplicatedStorage = { Name = "ReplicatedStorage" }

	w.env = {
		Players = Players,
		TeleportService = TeleportService,
		HttpService = HttpService,
		ReplicatedStorage = w.ReplicatedStorage,
		isStudio = o.isStudio == true,
		gameId = o.gameId or 9520747167,
		placeId = o.placeId or 74888767056358,
		privateServerId = o.privateServerId or "",
		newInstance = function(className: string)
			local i = newInstance(className)
			table.insert(w.instances, i)
			return i
		end,
		now = function()
			return w.time
		end,
		wait = function(seconds: number)
			schedule(w.time + seconds, coroutine.running())
			coroutine.yield()
		end,
		spawn = function(fn: () -> ())
			resume(coroutine.create(fn))
		end,
		delay = function(seconds: number, fn: () -> ())
			schedule(w.time + seconds, coroutine.create(fn))
		end,
		print = function(...)
			table.insert(w.logs, table.concat({ ... }, " "))
		end,
		warn = function(...)
			table.insert(w.warnings, table.concat({ ... }, " "))
		end,
		jsonEncode = function(v: any)
			return tostring(v)
		end,
	}
	w.Players = Players
	w.TeleportService = TeleportService

	function w.logged(pattern: string): boolean
		for _, l in w.logs do
			if string.find(l, pattern, 1, true) then
				return true
			end
		end
		return false
	end
	function w.warned(pattern: string): boolean
		for _, l in w.warnings do
			if string.find(l, pattern, 1, true) then
				return true
			end
		end
		return false
	end

	return w
end

return Fakes
