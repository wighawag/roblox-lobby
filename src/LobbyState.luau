--!strict
-- The lobby's state machine, without any Roblox API: who is in which queue, the countdowns, and the parties
-- being launched. The Roblox adapter (Lobby.luau) feeds it events and the clock, and performs the teleports it
-- asks for. Pure, so every rule here is unit-tested in Lune.
--
-- Per queue: "waiting" (fewer than minPlayers) -> "counting" (minPlayers reached; resets to "waiting" if it
-- drops below) -> a launch when the countdown ends, or at once when full and launchWhenFull. A launch takes the
-- queued players out of the queue into a frozen party, so the queue can fill again while the party teleports.
-- Members of a launching party cannot join or leave queues until the adapter completes, aborts or releases them.

local Config = require("./Config")

export type QueueView = {
	id: string,
	members: { number },
	capacity: number,
	minPlayers: number,
	phase: string, -- "waiting" | "counting"
	secondsLeft: number?, -- while counting
}

export type Launch = {
	id: number,
	queueId: string,
	place: string,
	members: { number },
}

type Queue = {
	spec: Config.QueueSpec,
	members: { number }, -- in join order
	countingSince: number?,
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
		self._queues[spec.id] = { spec = spec, members = {}, countingSince = nil }
		table.insert(self._order, spec.id)
	end
	return self
end

local function updateCounting(q: Queue, now: number)
	if #q.members >= q.spec.minPlayers then
		if q.countingSince == nil then
			q.countingSince = now
		end
	else
		q.countingSince = nil
	end
end

-- Returns (true) or (false, reason): "unknown-queue", "already-queued", "launching", "full".
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
	if #q.members >= q.spec.maxPlayers then
		return false, "full"
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
	updateCounting(q, now)
	return true, queueId
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
		updateCounting(q, now)
		local full = #q.members >= q.spec.maxPlayers
		local due = q.countingSince ~= nil and now - q.countingSince >= q.spec.countdown
		if (full and q.spec.launchWhenFull) or due then
			local launch: Launch = {
				id = self._nextLaunch,
				queueId = queueId,
				place = q.spec.place,
				members = q.members,
			}
			self._nextLaunch += 1
			self._launches[launch.id] = launch
			for _, userId in q.members do
				self._where[userId] = nil
				self._launchOf[userId] = launch.id
			end
			q.members = {}
			q.countingSince = nil
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
	local room = q.spec.maxPlayers - #q.members
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
	-- the countdown starts again from now, it does not resume
	q.countingSince = nil
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
	local secondsLeft = nil
	if q.countingSince ~= nil then
		secondsLeft = math.max(0, q.spec.countdown - (now - q.countingSince))
	end
	return {
		id = queueId,
		members = table.clone(q.members),
		capacity = q.spec.maxPlayers,
		minPlayers = q.spec.minPlayers,
		phase = if q.countingSince ~= nil then "counting" else "waiting",
		secondsLeft = secondsLeft,
	}
end

function LobbyState.queueIds(self: LobbyState): { string }
	return table.clone(self._order)
end

return LobbyState
