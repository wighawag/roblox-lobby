--!strict
-- TeleportAsync with the retry rules of RetryPolicy. Yields: call it from a spawned thread.

local RetryPolicy = require("./RetryPolicy")

local Teleport = {}

-- Builds the TeleportOptions for a reserved server (matchId as ReservedServerId) or a public server (matchId nil).
function Teleport.options(env: any, matchId: string?, teleportData: any): any
	local options = env.newInstance("TeleportOptions")
	if matchId then
		options.ReservedServerId = matchId
	end
	if teleportData ~= nil then
		options:SetTeleportData(teleportData)
	end
	return options
end

-- Calls TeleportAsync, retrying a thrown error up to `attempts` (default RetryPolicy.CALL_ATTEMPTS) times with backoff.
-- Returns (true, result) or (false, lastError).
function Teleport.call(env: any, placeId: number, players: { any }, options: any, attempts: number?): (boolean, any)
	local lastErr
	local limit = attempts or RetryPolicy.CALL_ATTEMPTS
	for attempt = 1, limit do
		local ok, result = pcall(function()
			return env.TeleportService:TeleportAsync(placeId, players, options)
		end)
		if ok then
			return true, result
		end
		lastErr = result
		env.warn(`[RobloxLobby] TeleportAsync to place {placeId} failed (attempt {attempt}): {result}`)
		if attempt < limit then
			env.wait(RetryPolicy.callBackoff(attempt))
		end
	end
	return false, lastErr
end

return Teleport
