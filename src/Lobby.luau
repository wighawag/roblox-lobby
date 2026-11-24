--!strict
-- The lobby place's server side: queues players, launches parties, teleports them into a fresh reserved server
-- of the game place, and handles every failure. It owns no visuals: the game draws its lobby from the Changed
-- signal (server) or from the replicated queue state (RobloxLobby.Client, on the client). See docs/integration.md.
--
--   local lobby = RobloxLobby.Lobby.start(require(ReplicatedStorage.LobbyConfig), {
--       teleportData = function(party) return { mode = "classic" } end, -- optional, small, non-secret
--   })
--   lobby:join(player, "four")  lobby:leave(player)
--   lobby.Changed / PlayerJoinedQueue / PlayerLeftQueue / Launched / LaunchFailed / Notice

local Config = require("./Config")
local Envelope = require("./Envelope")
local Env = require("./Env")
local LobbyState = require("./LobbyState")
local RetryPolicy = require("./RetryPolicy")
local Signal = require("./Signal")
local Teleport = require("./Teleport")

local Lobby = {}

Lobby.REMOTES_NAME = "RobloxLobbyRemotes"
Lobby.TICK = 0.2 -- seconds between state updates
Lobby.REQUEST_INTERVAL = 0.25 -- per-player rate limit of client join/leave requests
Lobby.SIMULATED_RELEASE = 3 -- seconds before a Studio-simulated party is released back into the lobby

export type Options = {
	teleportData: ((party: any) -> any)?,
	env: any?, -- tests only
}

local function viewEquals(a: any, b: any): boolean
	if a == nil or b == nil then
		return a == b
	end
	if a.phase ~= b.phase or #a.members ~= #b.members then
		return false
	end
	-- whole seconds only, so Changed fires about once per second while counting
	local sa = if a.secondsLeft then math.ceil(a.secondsLeft) else -1
	local sb = if b.secondsLeft then math.ceil(b.secondsLeft) else -1
	if sa ~= sb then
		return false
	end
	for i, m in a.members do
		if b.members[i] ~= m then
			return false
		end
	end
	return true
end

function Lobby.start(rawConfig: any, options: Options?)
	local opts: Options = options or {}
	local env = opts.env or Env.roblox()
	local config = Config.assert(rawConfig)
	local state = LobbyState.new(config.queues)
	local specs = {}
	for _, q in config.queues do
		specs[q.id] = q
	end

	for _, problem in Config.checkRunningPlace(config, "lobby", env.gameId, env.placeId) do
		env.warn("[RobloxLobby] CONFIG PROBLEM: " .. problem)
	end
	if env.isStudio then
		env.print(
			`[RobloxLobby] lobby started in Studio (experience {env.gameId}, place {env.placeId}); teleports: {if env.gameId
					== 0
				then "simulated (local file)"
				elseif config.studio.teleport == "simulate" then "simulated (studio.teleport)"
				else "real if Studio allows it (solo Test mode), else simulated"}`
		)
	end

	local self: any = {
		config = config,
		Changed = Signal.new(),
		PlayerJoinedQueue = Signal.new(),
		PlayerLeftQueue = Signal.new(),
		Launched = Signal.new(),
		LaunchFailed = Signal.new(),
		Notice = Signal.new(), -- (player, message): also sent to that client through the Notice remote
	}

	-- Remotes and replicated queue state (attributes replicate to every client by themselves)
	local remotes = env.newInstance("Folder")
	remotes.Name = Lobby.REMOTES_NAME
	local request = env.newInstance("RemoteEvent")
	request.Name = "Request"
	request.Parent = remotes
	local noticeRemote = env.newInstance("RemoteEvent")
	noticeRemote.Name = "Notice"
	noticeRemote.Parent = remotes
	local queuesFolder = env.newInstance("Folder")
	queuesFolder.Name = "Queues"
	queuesFolder.Parent = remotes
	local queueFolders = {}
	for _, q in config.queues do
		local f = env.newInstance("Folder")
		f.Name = q.id
		f:SetAttribute("Capacity", q.maxPlayers)
		f:SetAttribute("MinPlayers", q.minPlayers)
		f:SetAttribute("Count", 0)
		f:SetAttribute("Members", "")
		f:SetAttribute("Phase", "waiting")
		f:SetAttribute("SecondsLeft", -1)
		f.Parent = queuesFolder
		queueFolders[q.id] = f
	end
	remotes.Parent = env.ReplicatedStorage

	local function notify(player: any, message: string)
		self.Notice:Fire(player, message)
		pcall(function()
			noticeRemote:FireClient(player, message)
		end)
	end

	local lastViews: { [string]: any } = {}
	local function publish()
		local now = env.now()
		for _, queueId in state:queueIds() do
			local v = state:view(queueId, now)
			if not viewEquals(v, lastViews[queueId]) then
				lastViews[queueId] = v
				local f = queueFolders[queueId]
				local ids = {}
				for _, m in v.members do
					table.insert(ids, tostring(m))
				end
				f:SetAttribute("Count", #v.members)
				f:SetAttribute("Members", table.concat(ids, ","))
				f:SetAttribute("Phase", v.phase)
				f:SetAttribute("SecondsLeft", if v.secondsLeft then math.ceil(v.secondsLeft) else -1)
				self.Changed:Fire(queueId, v)
			end
		end
	end

	function self.join(_: any, player: any, queueId: string): (boolean, string?)
		local ok, reason = state:join(player.UserId, queueId, env.now())
		if ok then
			self.PlayerJoinedQueue:Fire(player, queueId)
			publish()
		end
		return ok, reason
	end

	function self.leave(_: any, player: any): (boolean, string?)
		local ok, queueIdOrReason = state:leave(player.UserId, env.now())
		if ok then
			self.PlayerLeftQueue:Fire(player, queueIdOrReason)
			publish()
		end
		return ok, queueIdOrReason
	end

	function self.queueOf(_: any, player: any): string?
		return state:queueOf(player.UserId)
	end

	function self.view(_: any, queueId: string): any
		return state:view(queueId, env.now())
	end

	-- Teleports in flight, per user id: { launchId, party, placeId, options, retries, since }
	local pending: { [number]: any } = {}

	local function release(userId: number, launchId: number, party: any, reason: string)
		pending[userId] = nil
		state:settle(launchId, userId)
		local player = env.Players:GetPlayerByUserId(userId)
		if player then
			notify(player, RetryPolicy.playerMessage(reason))
			self.LaunchFailed:Fire(party, { player }, reason)
		end
		publish()
	end

	local function simulate(launch: any, party: any, envelope: any, why: string)
		env.print(
			`[RobloxLobby] Studio: SIMULATED teleport ({why}) of party {party.id} from queue "{launch.queueId}" to place "{launch.place}" ({party.placeId}) with {#party.members} player(s); teleport data: {env.jsonEncode(
				envelope
			)}`
		)
		party.simulated = true
		self.Launched:Fire(party)
		for _, p in party.players do
			notify(p, "Studio: the teleport was simulated (see the Output). Test the game place on its own.")
		end
		env.delay(Lobby.SIMULATED_RELEASE, function()
			for _, userId in table.clone(launch.members) do
				state:settle(launch.id, userId)
			end
			publish()
		end)
	end

	local function performLaunch(launch: any)
		local spec = specs[launch.queueId]
		-- re-check the members: anyone gone since the countdown ended is dropped
		local players = {}
		for _, userId in table.clone(launch.members) do
			local p = env.Players:GetPlayerByUserId(userId)
			if p then
				table.insert(players, p)
			else
				state:remove(userId, env.now())
			end
		end
		if #players < spec.minPlayers then
			local requeued, freed = state:abort(launch.id, env.now())
			env.print(
				`[RobloxLobby] launch from queue "{launch.queueId}" cancelled: {#players} of {spec.minPlayers} players left; {#requeued} requeued`
			)
			for _, userId in freed do
				local p = env.Players:GetPlayerByUserId(userId)
				if p then
					notify(p, "Not enough players any more; please queue again.")
				end
			end
			publish()
			return
		end

		local placeId = config.places[launch.place]
		local matchId = env.HttpService:GenerateGUID(false)
		local userIds = {}
		for _, p in players do
			table.insert(userIds, p.UserId)
		end
		local party = {
			id = matchId,
			queueId = launch.queueId,
			place = launch.place,
			placeId = placeId,
			members = userIds,
			players = players,
			simulated = false,
		}
		local custom = nil
		if opts.teleportData then
			local ok, result = pcall(opts.teleportData, party)
			if ok then
				custom = result
			else
				env.warn("[RobloxLobby] teleportData function failed, sending none: " .. tostring(result))
			end
		end
		local envelope = Envelope.build({
			matchId = matchId,
			queueId = launch.queueId,
			lobbyPlaceId = config.lobbyPlaceId,
			members = userIds,
			sentAt = os.time(),
			data = custom,
		})
		party.envelope = envelope

		if env.isStudio and (env.gameId == 0 or placeId == 0 or config.studio.teleport == "simulate") then
			simulate(launch, party, envelope, if env.gameId == 0 then "local file" else "studio.teleport or place id 0")
			return
		end

		local teleportOptions = Teleport.options(env, matchId, envelope)
		local ok, err, permanent =
			Teleport.call(env, placeId, players, teleportOptions, if env.isStudio then 1 else nil)
		if not ok then
			if env.isStudio then
				simulate(launch, party, envelope, "Studio refused the real teleport: " .. tostring(err))
				return
			end
			env.warn(`[RobloxLobby] party {matchId} could not be teleported: {err}`)
			for _, userId in table.clone(launch.members) do
				release(userId, launch.id, party, if permanent then "permanent" else "call-failed")
			end
			return
		end
		local now = env.now()
		for _, p in players do
			pending[p.UserId] = {
				launchId = launch.id,
				party = party,
				placeId = placeId,
				options = teleportOptions,
				retries = 0,
				since = now,
			}
		end
		env.print(
			`[RobloxLobby] party {matchId} ({#players} player(s)) teleporting from queue "{launch.queueId}" to place {placeId}`
		)
		self.Launched:Fire(party)
	end

	-- TeleportInitFailed: a launched player's teleport failed after the call returned.
	local initFailedConn = env.TeleportService.TeleportInitFailed:Connect(
		function(player: any, result: any, message: string)
			local p = pending[player.UserId]
			if not p then
				return
			end
			local resultName = if type(result) == "string" then result else result.Name
			local action, arg = RetryPolicy.onInitFailed(resultName, p.retries)
			env.warn(`[RobloxLobby] teleport of {player.Name} failed ({resultName}: {message}); {action}`)
			if action == "retry" then
				p.retries += 1
				p.since = env.now() + arg
				env.delay(arg, function()
					if pending[player.UserId] ~= p or player.Parent == nil then
						return
					end
					-- same options: same ReservedServerId, so the player still joins their party's server
					local ok, err = Teleport.call(env, p.placeId, { player }, p.options)
					if not ok then
						release(player.UserId, p.launchId, p.party, "call-failed: " .. tostring(err))
					end
				end)
			else
				release(player.UserId, p.launchId, p.party, arg)
			end
		end
	)

	local lastRequest: { [number]: number } = {}
	local function onRequest(player: any, action: any, queueId: any)
		local last = lastRequest[player.UserId]
		local now = env.now()
		if last and now - last < Lobby.REQUEST_INTERVAL then
			return
		end
		lastRequest[player.UserId] = now
		if action == "join" and type(queueId) == "string" then
			local ok, reason = self:join(player, queueId)
			if not ok then
				notify(player, `Cannot join: {reason}`)
			end
		elseif action == "leave" then
			self:leave(player)
		end
	end
	local requestConn = request.OnServerEvent:Connect(onRequest)

	local removingConn = env.Players.PlayerRemoving:Connect(function(player: any)
		local userId = player.UserId
		lastRequest[userId] = nil
		local p = pending[userId]
		if p then
			-- what a successful teleport looks like from here (or the player quit mid-teleport)
			pending[userId] = nil
			state:settle(p.launchId, userId)
		else
			local where, id = state:remove(userId, env.now())
			if where == "queue" then
				self.PlayerLeftQueue:Fire(player, id)
			end
		end
		publish()
	end)

	function self._step(_: any)
		local now = env.now()
		for _, launch in state:tick(now) do
			env.spawn(function()
				performLaunch(launch)
			end)
		end
		-- a launched player still here long after the call, with no failure event: treat as failed
		for userId, p in pending do
			if now - p.since >= RetryPolicy.SILENT_TIMEOUT then
				local player = env.Players:GetPlayerByUserId(userId)
				if player then
					release(userId, p.launchId, p.party, "timeout")
				else
					pending[userId] = nil
					state:settle(p.launchId, userId)
				end
			end
		end
		publish()
	end

	local running = true
	function self.stop(_: any)
		running = false
		initFailedConn:Disconnect()
		requestConn:Disconnect()
		removingConn:Disconnect()
		remotes:Destroy()
	end

	if not opts.env then
		env.spawn(function()
			while running do
				env.wait(Lobby.TICK)
				self:_step()
			end
		end)
	end

	return self
end

return Lobby
