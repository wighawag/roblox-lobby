--!strict
-- When and how to retry a teleport. Pure Luau; follows Roblox's guide "Handle failed teleports"
-- (https://create.roblox.com/docs/projects/teleport#handle-failed-teleports).
--
-- Two kinds of failure:
--   1. TeleportAsync throws (bad input, network): retried CALL_ATTEMPTS times with backoff, then the party fails.
--   2. TeleportAsync returned but a player's teleport failed later: TeleportService.TeleportInitFailed, per player,
--      with an Enum.TeleportResult. Flooded and Failure are retried (to the same reserved server); the rest are final.

local RetryPolicy = {}

RetryPolicy.CALL_ATTEMPTS = 5
RetryPolicy.PLAYER_RETRIES = 3 -- per player, after TeleportInitFailed
RetryPolicy.FLOOD_DELAY = 15
RetryPolicy.FAILURE_DELAY = 1
-- A launched player still in the lobby server this long after the call, with no failure event, counts as failed.
RetryPolicy.SILENT_TIMEOUT = 30

-- Delay in seconds before call attempt n+1, after attempt n (n >= 1) threw: 1, 2, 4, 8 (capped).
function RetryPolicy.callBackoff(attempt: number): number
	return math.min(8, 2 ^ (attempt - 1))
end

-- For a TeleportInitFailed result name (Enum.TeleportResult.X.Name) and how many retries this player had:
-- returns ("retry", delaySeconds) or ("give-up", reason).
function RetryPolicy.onInitFailed(resultName: string, retriesSoFar: number): (string, any)
	if resultName == "Flooded" or resultName == "Failure" then
		if retriesSoFar >= RetryPolicy.PLAYER_RETRIES then
			return "give-up", "retries-exhausted"
		end
		return "retry", if resultName == "Flooded" then RetryPolicy.FLOOD_DELAY else RetryPolicy.FAILURE_DELAY
	end
	-- GameNotFound, GameEnded, GameFull, Unauthorized, IsTeleporting, or anything new: retrying will not help
	return "give-up", resultName
end

-- A thrown TeleportAsync error that retrying cannot fix: invalid input, or an HTTP 4xx answer other than 429
-- (measured live 2026-11-24: a nonexistent place id answers "HTTP 400 (Bad Request)").
function RetryPolicy.isPermanentCallError(err: any): boolean
	local s = tostring(err)
	local code = string.match(s, "HTTP (%d%d%d)")
	if code then
		local n = tonumber(code) :: number
		return n >= 400 and n < 500 and n ~= 429
	end
	return string.find(s, "Invalid placeId", 1, true) ~= nil
		or string.find(s, "Players empty", 1, true) ~= nil
		or string.find(s, "Incompatible Parameters", 1, true) ~= nil
end

-- What to tell the player whose teleport finally failed (they stay in the lobby).
function RetryPolicy.playerMessage(reason: string): string
	if reason == "Unauthorized" then
		return "The game place refused the teleport (it may not be published in this experience)."
	elseif reason == "GameNotFound" then
		return "The game place was not found. Its place id in LobbyConfig may be wrong."
	elseif reason == "GameFull" or reason == "GameEnded" then
		return "That match is no longer available. Please queue again."
	elseif reason == "permanent" then
		return "The game place could not be reached: its place id is probably wrong."
	elseif reason == "IsTeleporting" then
		return "You are already being teleported."
	end
	return "The teleport failed. Please queue again."
end

return RetryPolicy
