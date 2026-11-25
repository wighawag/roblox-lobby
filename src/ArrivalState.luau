--!strict
-- The game place's arrival logic, without any Roblox API: which arriving players belong to this server's match,
-- and when the match is ready to start. The adapter (Arrival.luau) feeds it each player's validated join data
-- (Envelope.validateJoin) and the clock. Pure, so it is unit-tested in Lune.
--
-- Teleport mode: the first valid envelope fixes the match (matchId, members). Ready when every member is
-- present, or joinTimeout seconds after the first arrival with whoever came (the rest are "missing").
-- Studio mode (only when enabled, i.e. RunService:IsStudio()): a player with no teleport data at all is accepted;
-- joinWindow seconds after the first one, the match is everyone present, described by a synthetic envelope that
-- goes through the same Envelope.parse as a real one.

local Envelope = require("./Envelope")

export type Match = {
	source: string, -- "teleport" | "studio"
	matchId: string,
	queueId: string,
	data: any,
	hostOptions: { [string]: string }?, -- size = "host": the host's choices
	expected: { number }, -- the party's user ids
	present: { number }, -- here when the match became ready
	missing: { number }, -- expected but not here
	envelope: Envelope.Envelope,
}

export type Options = {
	joinTimeout: number,
	studio: boolean,
	joinWindow: number,
	-- builds the synthetic envelope in Studio mode from the user ids present
	makeStudioEnvelope: (members: { number }) -> any,
}

export type Decision = { accept: boolean, reason: string?, late: boolean }

local ArrivalState = {}
ArrivalState.__index = ArrivalState

export type ArrivalState = typeof(setmetatable(
	{} :: {
		_opts: Options,
		_mode: string?,
		_envelope: any,
		_firstAt: number?,
		_present: { number },
		_ready: Match?,
	},
	ArrivalState
))

function ArrivalState.new(opts: Options): ArrivalState
	return setmetatable({
		_opts = opts,
		_mode = nil,
		_envelope = nil,
		_firstAt = nil,
		_present = {},
		_ready = nil,
	}, ArrivalState)
end

local function addPresent(self: ArrivalState, userId: number)
	if not table.find(self._present, userId) then
		table.insert(self._present, userId)
	end
end

-- ok and envOrReason are the two results of Envelope.validateJoin for this player.
function ArrivalState.arrive(self: ArrivalState, userId: number, ok: boolean, envOrReason: any, now: number): Decision
	local ready = self._ready
	if ready then
		-- after the start: only members of this match (who arrive late) are welcome
		if ready.source == "studio" then
			if not ok and envOrReason == "no-teleport-data" then
				addPresent(self, userId)
				return { accept = true, reason = nil, late = true }
			end
			return { accept = false, reason = if ok then "wrong-match" else envOrReason, late = true }
		end
		if not ok then
			return { accept = false, reason = envOrReason, late = true }
		end
		if envOrReason.matchId ~= ready.matchId then
			return { accept = false, reason = "wrong-match", late = true }
		end
		addPresent(self, userId)
		return { accept = true, reason = nil, late = true }
	end

	if not ok then
		if self._opts.studio and envOrReason == "no-teleport-data" and self._mode ~= "teleport" then
			self._mode = "studio"
			self._firstAt = self._firstAt or now
			addPresent(self, userId)
			return { accept = true, reason = nil, late = false }
		end
		return { accept = false, reason = envOrReason, late = false }
	end

	if self._mode == "studio" then
		-- a real teleport into a server already running a Studio debug match: keep the two apart
		return { accept = false, reason = "wrong-match", late = false }
	end
	if self._envelope == nil then
		self._mode = "teleport"
		self._envelope = envOrReason
		self._firstAt = now
	elseif envOrReason.matchId ~= self._envelope.matchId then
		return { accept = false, reason = "wrong-match", late = false }
	end
	addPresent(self, userId)
	return { accept = true, reason = nil, late = false }
end

function ArrivalState.leave(self: ArrivalState, userId: number)
	local i = table.find(self._present, userId)
	if i then
		table.remove(self._present, i)
	end
end

local function makeMatch(source: string, env: any, present: { number }): Match
	local missing = {}
	for _, userId in env.members do
		if not table.find(present, userId) then
			table.insert(missing, userId)
		end
	end
	return {
		source = source,
		matchId = env.matchId,
		queueId = env.queueId,
		data = env.data,
		hostOptions = env.options,
		expected = table.clone(env.members),
		present = table.clone(present),
		missing = missing,
		envelope = env,
	}
end

-- Returns the Match the first time it becomes ready, nil otherwise (including every later call).
function ArrivalState.tick(self: ArrivalState, now: number): Match?
	if self._ready or self._firstAt == nil or #self._present == 0 then
		return nil
	end
	if self._mode == "studio" then
		if now - self._firstAt < self._opts.joinWindow then
			return nil
		end
		local members = table.clone(self._present)
		table.sort(members)
		local ok, env = Envelope.parse(self._opts.makeStudioEnvelope(members))
		if not ok then
			error("[RobloxLobby] the Studio envelope is invalid (" .. tostring(env) .. "); this is a roblox-lobby bug")
		end
		self._ready = makeMatch("studio", env, self._present)
		return self._ready
	end
	local env = self._envelope
	local allHere = true
	for _, userId in env.members do
		if not table.find(self._present, userId) then
			allHere = false
			break
		end
	end
	if allHere or now - self._firstAt >= self._opts.joinTimeout then
		self._ready = makeMatch("teleport", env, self._present)
		return self._ready
	end
	return nil
end

-- While waiting: what a waiting screen shows. nil before the first arrival.
function ArrivalState.progress(
	self: ArrivalState,
	now: number
): { present: number, expected: number?, secondsLeft: number }?
	if self._firstAt == nil or self._ready then
		return nil
	end
	if self._mode == "studio" then
		return {
			present = #self._present,
			expected = nil,
			secondsLeft = math.max(0, self._opts.joinWindow - (now - self._firstAt)),
		}
	end
	return {
		present = #self._present,
		expected = #self._envelope.members,
		secondsLeft = math.max(0, self._opts.joinTimeout - (now - self._firstAt)),
	}
end

function ArrivalState.isReady(self: ArrivalState): boolean
	return self._ready ~= nil
end

return ArrivalState
