--!strict
-- The lobby's state machine, without any Roblox API: who is in which queue, the countdowns, and the parties
-- being launched. The Roblox adapter (Lobby.luau) feeds it events and the clock, and performs the teleports it
-- asks for. Pure, so every rule here is unit-tested in Lune.
--
-- Per queue: "waiting" (fewer than minPlayers) -> "counting" (minPlayers reached; resets to "waiting" if it
-- drops below) -> a launch when the countdown ends. Once the queue is full, the time left is cut to fullCountdown
-- (if that is sooner); a full queue that loses a player goes back to the normal countdown. A launch takes the
-- queued players out of the queue into a frozen party, so the queue can fill again while the party teleports.
-- Members of a launching party cannot join or leave queues until the adapter completes, aborts or releases them.
--
-- size = "host": the first player into an empty queue is its host; the queue is "creating" (closed to others)
-- until the host calls configure (party size, optionally a minimum, host options) or hostTimeout passes (then:
-- maxPlayers, first choice of each option). The queue then fills to that size. If the host leaves, the next
-- member becomes host; an empty queue resets.

local Config = require("./Config")

export type QueueView = {
	id: string,
	members: { number },
	capacity: number,
	minPlayers: number,
	phase: string, -- "waiting" | "counting" | "creating" (size = "host": the host is choosing)
	secondsLeft: number?, -- while counting
	host: number?, -- size = "host"
	options: { [string]: string }?, -- size = "host": the host's choices
}

export type Choice = { size: number, min: number?, options: { [string]: string }? }

export type Launch = {
	id: number,
	queueId: string,
	place: string,
	members: { number },
	options: { [string]: string }?,
	target: number?, -- size = "host": the chosen size and minimum, restored if the launch is aborted
	targetMin: number?,
}

type Queue = {
	spec: Config.QueueSpec,
	members: { number }, -- in join order
	countingSince: number?,
	fullSince: number?,
	host: number?,
	creatingSince: number?, -- the host is choosing
	target: number?, -- chosen size
	targetMin: number?,
	options: { [string]: string }?,
}

local LobbyState = {}
LobbyState.__index = LobbyState

export type LobbyState = typeof(setmetatable(
	{} :: {
		_queues: { [string]: Queue },
		_order: { string },
		_where: { [number]: string }, -- userId -> queueId, for queued players
		_launches: { [number]: Launch },
		_launchOf: { [number]: number }, -- userId -> launch id, for launching players
		_nextLaunch: number,
	},
	LobbyState
))

function LobbyState.new(queueSpecs: { Config.QueueSpec }): LobbyState
	local self = setmetatable({
		_queues = {},
		_order = {},
		_where = {},
		_launches = {},
		_launchOf = {},
		_nextLaunch = 1,
	}, LobbyState)
	for _, spec in queueSpecs do
		self._queues[spec.id] = { spec = spec, members = {}, countingSince = nil, fullSince = nil }
		table.insert(self._order, spec.id)
	end
	return self
end

local function maxOf(q: Queue): number
	return q.target or q.spec.maxPlayers
end

local function minOf(q: Queue): number
	return q.targetMin or q.spec.minPlayers
end

local function resetHost(q: Queue)
	q.host, q.creatingSince, q.target, q.targetMin, q.options = nil, nil, nil, nil, nil
end

local function updateCounting(q: Queue, now: number)
	if q.creatingSince ~= nil then
		q.countingSince, q.fullSince = nil, nil
		return
	end
	if #q.members >= minOf(q) then
		if q.countingSince == nil then
			q.countingSince = now
		end
	else
		q.countingSince = nil
	end
	if #q.members >= maxOf(q) then
		if q.fullSince == nil then
			q.fullSince = now
		end
	else
		q.fullSince = nil
	end
end

-- Seconds left before launch, or nil when not counting.
local function secondsLeft(q: Queue, now: number): number?
	if q.countingSince == nil then
		return nil
	end
	local left = q.spec.countdown - (now - q.countingSince)
	if q.fullSince ~= nil then
		left = math.min(left, q.spec.fullCountdown - (now - q.fullSince))
	end
	return math.max(0, left)
end

-- Returns (true) or (false, reason): "unknown-queue", "already-queued", "launching", "full", "creating".
function LobbyState.join(self: LobbyState, userId: number, queueId: string, now: number): (boolean, string?)
	local q = self._queues[queueId]
	if not q then
		return false, "unknown-queue"
	end
	if self._launchOf[userId] then
		return false, "launching"
	end
	if self._where[userId] then
		return false, "already-queued"
	end
	if q.creatingSince ~= nil then
		return false, "creating"
	end
	if #q.members >= maxOf(q) then
		return false, "full"
	end
	if q.spec.size == "host" and #q.members == 0 then
		resetHost(q)
		q.host = userId
		q.creatingSince = now
	end
	table.insert(q.members, userId)
	self._where[userId] = queueId
	updateCounting(q, now)
	return true, nil
end

-- A voluntary leave (button, walking away). Refused while the player's party is launching.
-- Returns (true, queueId) or (false, reason): "not-queued", "launching".
function LobbyState.leave(self: LobbyState, userId: number, now: number): (boolean, string?)
	if self._launchOf[userId] then
		return false, "launching"
	end
	local queueId = self._where[userId]
	if not queueId then
		return false, "not-queued"
	end
	local q = self._queues[queueId]
	local i = table.find(q.members, userId)
	if i then
		table.remove(q.members, i)
	end
	self._where[userId] = nil
	if #q.members == 0 then
		resetHost(q)
	elseif q.host == userId then
		q.host = q.members[1]
	end
	updateCounting(q, now)
	return true, queueId
end

local function applyChoice(q: Queue, choice: Choice): (boolean, string?)
	local spec = q.spec
	local size = choice.size
	if type(size) ~= "number" or size % 1 ~= 0 or size < 1 or size > spec.maxPlayers then
		return false, "bad-size"
	end
	local min = size
	if choice.min ~= nil then
		if not spec.hostMin then
			return false, "bad-min"
		end
		min = choice.min :: number
		if type(min) ~= "number" or min % 1 ~= 0 or min < 1 or min > size then
			return false, "bad-min"
		end
	end
	local given = choice.options or {}
	if type(given) ~= "table" then
		return false, "bad-option"
	end
	local known = {}
	local options = {}
	for _, o in spec.hostOptions do
		known[o.id] = true
		local v = given[o.id]
		if v == nil then
			options[o.id] = o.choices[1]
		elseif table.find(o.choices, v) then
			options[o.id] = v
		else
			return false, "bad-option"
		end
	end
	for k in given do
		if not known[k] then
			return false, "bad-option"
		end
	end
	q.target, q.targetMin, q.options, q.creatingSince = size, min, options, nil
	return true, nil
end

-- size = "host": the host's choice. Returns (true) or (false, reason): "unknown-queue", "not-host-mode",
-- "not-host", "not-creating", "bad-size", "bad-min", "bad-option".
function LobbyState.configure(
	self: LobbyState,
	userId: number,
	queueId: string,
	choice: Choice,
	now: number
): (boolean, string?)
	local q = self._queues[queueId]
	if not q then
		return false, "unknown-queue"
	end
	if q.spec.size ~= "host" then
		return false, "not-host-mode"
	end
	if q.host ~= userId then
		return false, "not-host"
	end
	if q.creatingSince == nil then
		return false, "not-creating"
	end
	if type(choice) ~= "table" then
		return false, "bad-size"
	end
	local ok, reason = applyChoice(q, choice)
	if ok then
		updateCounting(q, now)
	end
	return ok, reason
end

-- The player left the server (PlayerRemoving): removed from wherever they are, queue or launching party.
-- Returns "queue", "launch" or nil, and the queue or launch id.
function LobbyState.remove(self: LobbyState, userId: number, now: number): (string?, any)
	local launchId = self._launchOf[userId]
	if launchId then
		local l = self._launches[launchId]
		local i = table.find(l.members, userId)
		if i then
			table.remove(l.members, i)
		end
		self._launchOf[userId] = nil
		return "launch", launchId
	end
	if self._where[userId] then
		local _, queueId = self:leave(userId, now)
		return "queue", queueId
	end
	return nil, nil
end

-- Advances the clock. Returns the launches to perform now (possibly empty), in queue order.
function LobbyState.tick(self: LobbyState, now: number): { Launch }
	local out = {}
	for _, queueId in self._order do
		local q = self._queues[queueId]
		if q.creatingSince ~= nil and now - q.creatingSince >= q.spec.hostTimeout then
			applyChoice(q, { size = q.spec.maxPlayers })
		end
		updateCounting(q, now)
		local left = secondsLeft(q, now)
		if left ~= nil and left <= 0 then
			local launch: Launch = {
				id = self._nextLaunch,
				queueId = queueId,
				place = q.spec.place,
				members = q.members,
				options = q.options,
				target = q.target,
				targetMin = q.targetMin,
			}
			self._nextLaunch += 1
			self._launches[launch.id] = launch
			for _, userId in q.members do
				self._where[userId] = nil
				self._launchOf[userId] = launch.id
			end
			q.members = {}
			q.countingSince = nil
			q.fullSince = nil
			resetHost(q)
			table.insert(out, launch)
		end
	end
	return out
end

function LobbyState.getLaunch(self: LobbyState, launchId: number): Launch?
	return self._launches[launchId]
end

-- The member of a launch has been dealt with (teleported, or finally failed and released back to the lobby).
-- When the last member is settled the launch is forgotten. Returns true if the launch is now finished.
function LobbyState.settle(self: LobbyState, launchId: number, userId: number): boolean
	local l = self._launches[launchId]
	if not l then
		return true
	end
	local i = table.find(l.members, userId)
	if i then
		table.remove(l.members, i)
	end
	if self._launchOf[userId] == launchId then
		self._launchOf[userId] = nil
	end
	if #l.members == 0 then
		self._launches[launchId] = nil
		return true
	end
	return false
end

-- Cancel a launch before its teleport (e.g. leavers dropped it below minPlayers): its members go back to the
-- front of their queue, in their order, as far as capacity allows; the others are just freed.
-- Returns the user ids put back in the queue and the ones freed.
function LobbyState.abort(self: LobbyState, launchId: number, now: number): ({ number }, { number })
	local l = self._launches[launchId]
	if not l then
		return {}, {}
	end
	self._launches[launchId] = nil
	local q = self._queues[l.queueId]
	local requeued, freed = {}, {}
	local room = maxOf(q) - #q.members
	for _, userId in l.members do
		self._launchOf[userId] = nil
		if #requeued < room then
			table.insert(requeued, userId)
			self._where[userId] = l.queueId
		else
			table.insert(freed, userId)
		end
	end
	local members = table.clone(requeued)
	for _, userId in q.members do
		table.insert(members, userId)
	end
	q.members = members
	if q.spec.size == "host" and q.host == nil and #members > 0 then
		-- the queue was reset by the launch: give it back its host and choices
		q.host = members[1]
		q.options = l.options
		q.target = l.target
		q.targetMin = l.targetMin
	end
	-- the countdown starts again from now, it does not resume
	q.countingSince = nil
	q.fullSince = nil
	updateCounting(q, now)
	return requeued, freed
end

function LobbyState.queueOf(self: LobbyState, userId: number): string?
	return self._where[userId]
end

function LobbyState.isLaunching(self: LobbyState, userId: number): boolean
	return self._launchOf[userId] ~= nil
end

function LobbyState.view(self: LobbyState, queueId: string, now: number): QueueView?
	local q = self._queues[queueId]
	if not q then
		return nil
	end
	return {
		id = queueId,
		members = table.clone(q.members),
		capacity = maxOf(q),
		minPlayers = minOf(q),
		phase = if q.creatingSince ~= nil then "creating" elseif q.countingSince ~= nil then "counting" else "waiting",
		secondsLeft = secondsLeft(q, now),
		host = q.host,
		options = if q.options then table.clone(q.options) else nil,
	}
end

function LobbyState.queueIds(self: LobbyState): { string }
	return table.clone(self._order)
end

return LobbyState
