--!strict
-- LobbyConfig validation and defaults. Pure Luau: used by both places at startup and by scripts/check-places.
--
-- A LobbyConfig is plain data (see docs/integration.md):
--   experienceId  number   the universe id both places belong to (0 = not published yet)
--   lobbyPlaceId  number   the start place (0 = not published yet)
--   places        { [name]: placeId }  the teleport destinations
--   queues        { QueueSpec }  see below
--   arrival       { joinTimeout: number? }
--   studio        { joinWindow: number?, fakeMembers: number?, teleport: "auto" | "simulate"? }

export type HostOption = { id: string, label: string, choices: { string } }

export type QueueSpec = {
	id: string,
	place: string,
	minPlayers: number,
	maxPlayers: number,
	countdown: number,
	fullCountdown: number,
	leave: string, -- "walk" | "button"
	size: string, -- "fixed" | "host"
	hostMin: boolean, -- size "host": the host also picks the minimum to start with
	hostTimeout: number, -- size "host": seconds the host has to choose
	hostOptions: { HostOption },
}

export type Config = {
	experienceId: number,
	lobbyPlaceId: number,
	places: { [string]: number },
	queues: { QueueSpec },
	arrival: { joinTimeout: number },
	studio: { joinWindow: number, fakeMembers: number, teleport: string },
}

local Config = {}

Config.MAX_PARTY = 50 -- TeleportAsync takes at most 50 players per call

local TOP_KEYS =
	{ experienceId = true, lobbyPlaceId = true, places = true, queues = true, arrival = true, studio = true }
local QUEUE_KEYS = {
	id = true,
	place = true,
	minPlayers = true,
	maxPlayers = true,
	countdown = true,
	fullCountdown = true,
	leave = true,
	size = true,
	hostMin = true,
	hostTimeout = true,
	hostOptions = true,
}
local ARRIVAL_KEYS = { joinTimeout = true }
local STUDIO_KEYS = { joinWindow = true, fakeMembers = true, teleport = true }

local function isId(v: any): boolean
	return type(v) == "number" and v >= 0 and v == math.floor(v)
end

local function isPositiveInt(v: any): boolean
	return type(v) == "number" and v >= 1 and v == math.floor(v)
end

local function unknownKeys(t: { [any]: any }, allowed: { [string]: boolean }, where: string, problems: { string })
	local extra = {}
	for k in t do
		if not allowed[k] then
			table.insert(extra, tostring(k))
		end
	end
	table.sort(extra)
	for _, k in extra do
		table.insert(problems, `{where}: unknown key "{k}" (typo?)`)
	end
end

-- Returns (true, normalizedConfig) or (false, { problem strings }). Never throws.
function Config.validate(raw: any): (boolean, any)
	local problems: { string } = {}
	if type(raw) ~= "table" then
		return false, { "config must be a table" }
	end
	unknownKeys(raw, TOP_KEYS, "config", problems)

	if not isId(raw.experienceId) then
		table.insert(problems, "experienceId must be a non-negative integer (0 until published)")
	end
	if not isId(raw.lobbyPlaceId) then
		table.insert(problems, "lobbyPlaceId must be a non-negative integer (0 until published)")
	end

	local places: { [string]: number } = {}
	if type(raw.places) ~= "table" or next(raw.places) == nil then
		table.insert(problems, "places must be a non-empty table of name = placeId")
	else
		for name, id in raw.places do
			if type(name) ~= "string" then
				table.insert(problems, "places: keys must be names (strings)")
			elseif not isId(id) then
				table.insert(problems, `places.{name} must be a non-negative integer (0 until published)`)
			else
				places[name] = id
			end
		end
	end

	local queues: { QueueSpec } = {}
	if type(raw.queues) ~= "table" or #raw.queues == 0 then
		table.insert(problems, "queues must be a non-empty list")
	else
		local seen = {}
		for i, q in raw.queues do
			local where = `queues[{i}]`
			if type(q) ~= "table" then
				table.insert(problems, where .. " must be a table")
				continue
			end
			unknownKeys(q, QUEUE_KEYS, where, problems)
			if type(q.id) ~= "string" or q.id == "" then
				table.insert(problems, where .. ".id must be a non-empty string")
			else
				where = `queue "{q.id}"`
				if seen[q.id] then
					table.insert(problems, where .. ": duplicate id")
				end
				seen[q.id] = true
			end
			if type(q.place) ~= "string" then
				table.insert(problems, where .. ".place must be the name of an entry in places")
			elseif type(raw.places) == "table" and raw.places[q.place] == nil then
				table.insert(problems, `{where}.place "{q.place}" is not in places`)
			end
			local maxP = q.maxPlayers
			local minP = if q.minPlayers == nil then maxP else q.minPlayers
			if not isPositiveInt(maxP) or maxP > Config.MAX_PARTY then
				table.insert(problems, `{where}.maxPlayers must be an integer from 1 to {Config.MAX_PARTY}`)
			end
			if not isPositiveInt(minP) then
				table.insert(problems, where .. ".minPlayers must be an integer of at least 1")
			elseif isPositiveInt(maxP) and minP > maxP then
				table.insert(problems, `{where}: minPlayers ({minP}) is greater than maxPlayers ({maxP})`)
			end
			local countdown = if q.countdown == nil then 15 else q.countdown
			if type(countdown) ~= "number" or countdown < 0 then
				table.insert(problems, where .. ".countdown must be a number of seconds, 0 or more")
			end
			local fullCountdown = if q.fullCountdown == nil then 5 else q.fullCountdown
			if type(fullCountdown) ~= "number" or fullCountdown < 0 then
				table.insert(problems, where .. ".fullCountdown must be a number of seconds, 0 or more")
			end
			local leave = if q.leave == nil then "walk" else q.leave
			if leave ~= "walk" and leave ~= "button" then
				table.insert(problems, where .. '.leave must be "walk" or "button"')
			end
			local size = if q.size == nil then "fixed" else q.size
			if size ~= "fixed" and size ~= "host" then
				table.insert(problems, where .. '.size must be "fixed" or "host"')
			end
			local hostMin = if q.hostMin == nil then false else q.hostMin
			if type(hostMin) ~= "boolean" then
				table.insert(problems, where .. ".hostMin must be true or false")
			end
			local hostTimeout = if q.hostTimeout == nil then 60 else q.hostTimeout
			if type(hostTimeout) ~= "number" or hostTimeout <= 0 then
				table.insert(problems, where .. ".hostTimeout must be a positive number of seconds")
			end
			local hostOptions = {}
			if q.hostOptions ~= nil then
				if type(q.hostOptions) ~= "table" then
					table.insert(problems, where .. ".hostOptions must be a list")
				else
					local seenOpt = {}
					for k, o in q.hostOptions do
						local ow = `{where}.hostOptions[{k}]`
						if type(o) ~= "table" or type(o.id) ~= "string" or o.id == "" then
							table.insert(problems, ow .. " needs an id (string)")
							continue
						end
						unknownKeys(o, { id = true, label = true, choices = true }, ow, problems)
						if seenOpt[o.id] then
							table.insert(problems, `{ow}: duplicate id "{o.id}"`)
						end
						seenOpt[o.id] = true
						local ok = type(o.choices) == "table" and #o.choices >= 1
						if ok then
							for _, c in o.choices do
								if type(c) ~= "string" then
									ok = false
								end
							end
						end
						if not ok then
							table.insert(problems, ow .. ".choices must be a non-empty list of strings")
							continue
						end
						table.insert(hostOptions, {
							id = o.id,
							label = if type(o.label) == "string" then o.label else o.id,
							choices = table.clone(o.choices),
						})
					end
				end
				if #hostOptions > 0 and size ~= "host" then
					table.insert(problems, where .. '.hostOptions needs size = "host"')
				end
			end
			table.insert(queues, {
				id = q.id,
				place = q.place,
				minPlayers = minP,
				maxPlayers = maxP,
				countdown = countdown,
				fullCountdown = fullCountdown,
				leave = leave,
				size = size,
				hostMin = hostMin,
				hostTimeout = hostTimeout,
				hostOptions = hostOptions,
			})
		end
	end

	local arrivalRaw = raw.arrival or {}
	local joinTimeout = 30
	if type(arrivalRaw) ~= "table" then
		table.insert(problems, "arrival must be a table")
	else
		unknownKeys(arrivalRaw, ARRIVAL_KEYS, "arrival", problems)
		if arrivalRaw.joinTimeout ~= nil then
			joinTimeout = arrivalRaw.joinTimeout
			if type(joinTimeout) ~= "number" or joinTimeout <= 0 then
				table.insert(problems, "arrival.joinTimeout must be a positive number of seconds")
			end
		end
	end

	local studioRaw = raw.studio or {}
	local studio = { joinWindow = 3, fakeMembers = 0, teleport = "auto" }
	if type(studioRaw) ~= "table" then
		table.insert(problems, "studio must be a table")
	else
		unknownKeys(studioRaw, STUDIO_KEYS, "studio", problems)
		if studioRaw.joinWindow ~= nil then
			studio.joinWindow = studioRaw.joinWindow
			if type(studio.joinWindow) ~= "number" or studio.joinWindow < 0 then
				table.insert(problems, "studio.joinWindow must be a number of seconds, 0 or more")
			end
		end
		if studioRaw.fakeMembers ~= nil then
			studio.fakeMembers = studioRaw.fakeMembers
			if type(studio.fakeMembers) ~= "number" or studio.fakeMembers < 0 or studio.fakeMembers % 1 ~= 0 then
				table.insert(problems, "studio.fakeMembers must be an integer, 0 or more")
			end
		end
		if studioRaw.teleport ~= nil then
			studio.teleport = studioRaw.teleport
			if studio.teleport ~= "auto" and studio.teleport ~= "simulate" then
				table.insert(problems, 'studio.teleport must be "auto" or "simulate"')
			end
		end
	end

	if #problems > 0 then
		return false, problems
	end
	return true,
		{
			experienceId = raw.experienceId,
			lobbyPlaceId = raw.lobbyPlaceId,
			places = places,
			queues = queues,
			arrival = { joinTimeout = joinTimeout },
			studio = studio,
		} :: Config
end

-- Like validate, but throws one error listing every problem. Use at startup.
function Config.assert(raw: any): Config
	local ok, result = Config.validate(raw)
	if not ok then
		error("[RobloxLobby] invalid LobbyConfig:\n  - " .. table.concat(result, "\n  - "), 2)
	end
	return result
end

-- True when every id is filled in (the experience has been published).
function Config.isPublished(config: Config): boolean
	if config.experienceId == 0 or config.lobbyPlaceId == 0 then
		return false
	end
	for _, id in config.places do
		if id == 0 then
			return false
		end
	end
	return true
end

-- The startup guard: problems with the running server's ids, given game.GameId and game.PlaceId.
-- Empty list = fine. role is "lobby" or "game". In Studio with an unpublished place (gameId 0), nothing is checked.
function Config.checkRunningPlace(config: Config, role: string, gameId: number, placeId: number): { string }
	local problems = {}
	if gameId == 0 then
		return problems
	end
	if config.experienceId ~= 0 and gameId ~= config.experienceId then
		table.insert(
			problems,
			`this server's experience is {gameId} but LobbyConfig.experienceId is {config.experienceId}: the place was published into the wrong experience, or the config is stale`
		)
	end
	if role == "lobby" then
		if config.lobbyPlaceId ~= 0 and placeId ~= config.lobbyPlaceId then
			table.insert(
				problems,
				`this lobby runs as place {placeId} but LobbyConfig.lobbyPlaceId is {config.lobbyPlaceId}`
			)
		end
	else
		local found = false
		for _, id in config.places do
			if id == placeId then
				found = true
			end
		end
		if not found then
			table.insert(problems, `this game place runs as place {placeId}, which is not in LobbyConfig.places`)
		end
	end
	return problems
end

return Config
