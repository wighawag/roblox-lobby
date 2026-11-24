--!strict
-- The game place's server side: checks every arriving player's teleport data, gathers the party, and says when
-- the match can start. No visuals: a waiting screen is the game's, fed by `Changed`. See docs/integration.md.
--
--   local arrival = RobloxLobby.Arrival.start(require(ReplicatedStorage.LobbyConfig), {
--       studioData = function(members) return { mode = "classic" } end, -- what Studio playtests pretend was sent
--   })
--   arrival.Ready:Connect(function(match) ... start the game with match.players ... end)
--   arrival.Rejected / PlayerJoined / Changed;  arrival:returnToLobby(players)

local Config = require("./Config")
local Envelope = require("./Envelope")
local Env = require("./Env")
local ArrivalState = require("./ArrivalState")
local Signal = require("./Signal")
local Teleport = require("./Teleport")

local Arrival = {}

Arrival.TICK = 0.2

export type Options = {
	studioData: ((members: { number }) -> any)?,
	-- what to do with a rejected player: "lobby" (default: teleport them to the lobby, kick if that fails),
	-- "kick", or "keep" (only report it through Rejected). In Studio, rejected players are always kept.
	onRejected: string?,
	env: any?, -- tests only
}

function Arrival.start(rawConfig: any, options: Options?)
	local opts: Options = options or {}
	local env = opts.env or Env.roblox()
	local config = Config.assert(rawConfig)
	local onRejected = opts.onRejected or "lobby"
	assert(
		onRejected == "lobby" or onRejected == "kick" or onRejected == "keep",
		'[RobloxLobby] onRejected must be "lobby", "kick" or "keep"'
	)

	for _, problem in Config.checkRunningPlace(config, "game", env.gameId, env.placeId) do
		env.warn("[RobloxLobby] CONFIG PROBLEM: " .. problem)
	end

	local self: any = {
		config = config,
		Ready = Signal.new(), -- (match) once per server
		PlayerJoined = Signal.new(), -- (player, { late: boolean }) every accepted player
		Rejected = Signal.new(), -- (player, reason)
		Changed = Signal.new(), -- (progress) while waiting: { present, expected?, secondsLeft }
	}

	local state = ArrivalState.new({
		joinTimeout = config.arrival.joinTimeout,
		studio = env.isStudio,
		joinWindow = config.studio.joinWindow,
		makeStudioEnvelope = function(members: { number })
			local data = nil
			if opts.studioData then
				local ok, result = pcall(opts.studioData, members)
				if ok then
					data = result
				else
					env.warn("[RobloxLobby] studioData function failed, using none: " .. tostring(result))
				end
			end
			return Envelope.build({
				matchId = "studio-" .. env.HttpService:GenerateGUID(false),
				queueId = config.queues[1].id,
				lobbyPlaceId = config.lobbyPlaceId,
				members = members,
				sentAt = os.time(),
				data = data,
			})
		end,
	})

	if env.isStudio then
		env.print(
			`[RobloxLobby] game place started in Studio: players without teleport data are accepted; the match starts {config.studio.joinWindow}s after the first one ({config.studio.fakeMembers} fake member slot(s))`
		)
	end

	local function sendBack(player: any, reason: string)
		local text = "[RobloxLobby] " .. Envelope.explain(reason)
		if env.isStudio or onRejected == "keep" then
			return
		end
		if onRejected == "lobby" and config.lobbyPlaceId ~= 0 then
			env.spawn(function()
				local ok = Teleport.call(env, config.lobbyPlaceId, { player }, Teleport.options(env, nil, nil), 3)
				if not ok and player.Parent ~= nil then
					player:Kick(text)
				end
			end)
		else
			player:Kick(text)
		end
	end

	local function onPlayer(player: any)
		local okJoin, joinData = pcall(function()
			return player:GetJoinData()
		end)
		local ok, envOrReason = Envelope.validateJoin(if okJoin then joinData else nil, {
			userId = player.UserId,
			gameId = env.gameId,
			lobbyPlaceId = config.lobbyPlaceId,
			privateServerId = env.privateServerId,
			isStudio = env.isStudio,
		})
		local decision = state:arrive(player.UserId, ok, envOrReason, env.now())
		if decision.accept then
			self.PlayerJoined:Fire(player, { late = decision.late })
		else
			local reason = decision.reason or "rejected"
			env.warn(`[RobloxLobby] rejected {player.Name}: {reason} ({Envelope.explain(reason)})`)
			self.Rejected:Fire(player, reason)
			sendBack(player, reason)
		end
	end

	local addedConn = env.Players.PlayerAdded:Connect(onPlayer)
	for _, player in env.Players:GetPlayers() do
		onPlayer(player)
	end
	local removingConn = env.Players.PlayerRemoving:Connect(function(player: any)
		state:leave(player.UserId)
	end)

	local match: any = nil
	local lastProgress = nil
	function self._step(_: any)
		local now = env.now()
		local m = state:tick(now)
		if m then
			local players = {}
			for _, userId in m.present do
				local p = env.Players:GetPlayerByUserId(userId)
				if p then
					table.insert(players, p)
				end
			end
			match = table.clone(m)
			match.players = players
			match.fakeMembers = if env.isStudio then config.studio.fakeMembers else 0
			env.print(
				`[RobloxLobby] match {match.matchId} ready ({match.source}): {#players} player(s), {#match.missing} missing, {match.fakeMembers} fake slot(s)`
			)
			self.Ready:Fire(match)
			return
		end
		local progress = state:progress(now)
		if progress then
			local key = `{progress.present}/{progress.expected}/{math.ceil(progress.secondsLeft)}`
			if key ~= lastProgress then
				lastProgress = key
				self.Changed:Fire(progress)
			end
		end
	end

	function self.getMatch(_: any): any
		return match
	end

	-- Teleports players back to the lobby place (a public server). Yields. In Studio with a local file it only logs.
	-- Returns (true) or (false, error).
	function self.returnToLobby(_: any, players: { any }, data: any?): (boolean, any)
		if config.lobbyPlaceId == 0 or (env.isStudio and env.gameId == 0) then
			env.print(`[RobloxLobby] Studio: SIMULATED return of {#players} player(s) to the lobby`)
			return true, nil
		end
		return Teleport.call(env, config.lobbyPlaceId, players, Teleport.options(env, nil, data))
	end

	local running = true
	function self.stop(_: any)
		running = false
		addedConn:Disconnect()
		removingConn:Disconnect()
	end

	if not opts.env then
		env.spawn(function()
			while running and not state:isReady() do
				env.wait(Arrival.TICK)
				self:_step()
			end
		end)
	end

	return self
end

return Arrival
