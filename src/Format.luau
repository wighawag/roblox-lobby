--!strict
-- Default texts for a queue's state. Pure. A game overrides any of them by passing its own `format` table
-- (same keys) to Kit.pad / Client.defaultUi: change the wording, the language, or return "" to hide a line.

export type View = {
	id: string,
	count: number,
	capacity: number,
	minPlayers: number,
	phase: string, -- "waiting" | "counting"
	secondsLeft: number?, -- nil unless counting
}

local Format = {}

-- "2/4"
function Format.players(v: View): string
	return `{v.count}/{v.capacity}`
end

-- "12 s", or "" while waiting
function Format.time(v: View): string
	if v.phase == "counting" and v.secondsLeft then
		return `{math.ceil(v.secondsLeft)} s`
	end
	return ""
end

-- One line for a status bar.
function Format.status(v: View): string
	if v.phase == "counting" and v.secondsLeft then
		local s = math.ceil(v.secondsLeft)
		if s <= 0 then
			return "Teleporting..."
		end
		return `Starting in {s} s ({v.count}/{v.capacity})`
	end
	local missing = v.minPlayers - v.count
	if missing > 0 then
		return `Waiting for {missing} more player{if missing == 1 then "" else "s"} ({v.count}/{v.capacity})`
	end
	return `{v.count}/{v.capacity}`
end

Format.leave = function(_: View): string
	return "Leave"
end

-- Merges a game's overrides over the defaults.
function Format.with(overrides: { [string]: any }?): { [string]: (View) -> string }
	local out: { [string]: any } = {}
	for k, fn in Format :: any do
		if type(fn) == "function" and k ~= "with" and k ~= "fromAttributes" then
			out[k] = fn
		end
	end
	for k, fn in overrides or {} do
		out[k] = fn
	end
	return out
end

-- Builds a View from the replicated attributes of a queue folder (RobloxLobbyRemotes.Queues.<id>).
function Format.fromAttributes(id: string, attrs: { [string]: any }): View
	local seconds = attrs.SecondsLeft
	return {
		id = id,
		count = attrs.Count or 0,
		capacity = attrs.Capacity or 0,
		minPlayers = attrs.MinPlayers or 0,
		phase = attrs.Phase or "waiting",
		secondsLeft = if type(seconds) == "number" and seconds >= 0 then seconds else nil,
	}
end

return Format
