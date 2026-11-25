--!strict
-- The teleport data envelope: built by the lobby, checked by the game place. Pure Luau.
--
-- Teleport data is visible to (and alterable by) the client: put nothing secret or valuable in `data`.
-- What CAN be trusted on arrival comes from Player:GetJoinData() on the server, which Roblox guarantees was
-- sent by a Roblox server, with this player, from SourcePlaceId / SourceGameId.

export type Envelope = {
	rl: number, -- format version
	matchId: string, -- the party id, also the TeleportOptions.ReservedServerId
	queueId: string,
	lobbyPlaceId: number,
	members: { number }, -- user ids of the whole party
	sentAt: number, -- os.time() on the lobby server
	data: any, -- the game's own table (or nil)
	options: { [string]: string }?, -- size = "host": the host's choices (validated by the lobby)
}

local Envelope = {}

Envelope.VERSION = 1

function Envelope.build(fields: {
	matchId: string,
	queueId: string,
	lobbyPlaceId: number,
	members: { number },
	sentAt: number,
	data: any?,
	options: { [string]: string }?,
}): Envelope
	local members = table.clone(fields.members)
	table.sort(members)
	return {
		rl = Envelope.VERSION,
		matchId = fields.matchId,
		queueId = fields.queueId,
		lobbyPlaceId = fields.lobbyPlaceId,
		members = members,
		sentAt = fields.sentAt,
		data = fields.data,
		options = fields.options,
	}
end

-- Shape check only. Returns (true, envelope) or (false, reason).
function Envelope.parse(value: any): (boolean, any)
	if type(value) ~= "table" then
		return false, "no-envelope"
	end
	if value.rl == nil then
		return false, "no-envelope"
	end
	if value.rl ~= Envelope.VERSION then
		return false, "unknown-version"
	end
	if type(value.matchId) ~= "string" or value.matchId == "" then
		return false, "bad-envelope"
	end
	if type(value.queueId) ~= "string" then
		return false, "bad-envelope"
	end
	if type(value.lobbyPlaceId) ~= "number" or type(value.sentAt) ~= "number" then
		return false, "bad-envelope"
	end
	if type(value.members) ~= "table" or #value.members == 0 then
		return false, "bad-envelope"
	end
	for _, m in value.members do
		if type(m) ~= "number" then
			return false, "bad-envelope"
		end
	end
	if value.options ~= nil then
		if type(value.options) ~= "table" then
			return false, "bad-envelope"
		end
		for k, v in value.options do
			if type(k) ~= "string" or type(v) ~= "string" then
				return false, "bad-envelope"
			end
		end
	end
	return true, value
end

export type ArrivalContext = {
	userId: number,
	gameId: number, -- game.GameId of this server
	lobbyPlaceId: number, -- from LobbyConfig
	privateServerId: string, -- game.PrivateServerId ("" in Studio Test mode)
	isStudio: boolean,
}

-- Full arrival check on the server, from Player:GetJoinData(). Returns (true, envelope) or (false, reason).
-- Reasons: no-teleport-data, wrong-source-game, wrong-source-place, no-envelope, unknown-version, bad-envelope,
-- not-a-member, wrong-server.
function Envelope.validateJoin(joinData: any, ctx: ArrivalContext): (boolean, any)
	if type(joinData) ~= "table" or joinData.TeleportData == nil then
		return false, "no-teleport-data"
	end
	if joinData.SourceGameId ~= ctx.gameId then
		return false, "wrong-source-game"
	end
	if ctx.lobbyPlaceId ~= 0 and joinData.SourcePlaceId ~= ctx.lobbyPlaceId then
		return false, "wrong-source-place"
	end
	local ok, env = Envelope.parse(joinData.TeleportData)
	if not ok then
		return false, env
	end
	if not table.find(env.members, ctx.userId) then
		return false, "not-a-member"
	end
	-- In production a reserved server's PrivateServerId equals the ReservedServerId we chose (the matchId).
	-- Studio Test mode leaves it empty, and Team Test makes it differ, so Studio skips this check.
	if not ctx.isStudio and ctx.privateServerId ~= env.matchId then
		return false, "wrong-server"
	end
	return true, env
end

-- Human-readable explanation of a rejection reason, for logs and for the player's kick message.
local EXPLAIN = {
	["no-teleport-data"] = "you joined this place directly; matches start from the lobby",
	["wrong-source-game"] = "the teleport came from another experience",
	["wrong-source-place"] = "the teleport did not come from this game's lobby place",
	["no-envelope"] = "the teleport carried no lobby data",
	["unknown-version"] = "the lobby and this place run different roblox-lobby versions; publish both places again",
	["bad-envelope"] = "the teleport data is malformed",
	["not-a-member"] = "you are not part of the party this server was made for",
	["wrong-server"] = "this server is not the reserved server of your party",
	["wrong-match"] = "this server already hosts another party",
}

function Envelope.explain(reason: string): string
	return EXPLAIN[reason] or reason
end

return Envelope
