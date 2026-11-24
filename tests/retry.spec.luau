--!strict
local RetryPolicy = require("../src/RetryPolicy")

return function(T)
	local it, expect = T.it, T.expect
	T.describe("RetryPolicy", function()
		it("backs off 1, 2, 4, 8, 8", function()
			local d = {}
			for n = 1, 5 do
				table.insert(d, RetryPolicy.callBackoff(n))
			end
			expect(d).toEqual({ 1, 2, 4, 8, 8 })
		end)
		it("retries Flooded after 15 s and Failure after 1 s", function()
			local a, d = RetryPolicy.onInitFailed("Flooded", 0)
			expect(a).toBe("retry")
			expect(d).toBe(15)
			local b, e = RetryPolicy.onInitFailed("Failure", 2)
			expect(b).toBe("retry")
			expect(e).toBe(1)
		end)
		it("gives up after PLAYER_RETRIES", function()
			local a, r = RetryPolicy.onInitFailed("Failure", RetryPolicy.PLAYER_RETRIES)
			expect(a).toBe("give-up")
			expect(r).toBe("retries-exhausted")
		end)
		it("treats HTTP 4xx and invalid-input errors from TeleportAsync as permanent", function()
			expect(RetryPolicy.isPermanentCallError("HTTP 400 (Bad Request)")).toBe(true)
			expect(RetryPolicy.isPermanentCallError("HTTP 403 (Forbidden)")).toBe(true)
			expect(RetryPolicy.isPermanentCallError("Invalid placeId")).toBe(true)
			expect(RetryPolicy.isPermanentCallError("HTTP 500 (Internal Server Error)")).toBe(false)
			expect(RetryPolicy.isPermanentCallError("HTTP 429 (Too Many Requests)")).toBe(false)
			expect(RetryPolicy.isPermanentCallError("timeout")).toBe(false)
		end)
		it("never retries final results", function()
			for _, name in { "GameNotFound", "GameEnded", "GameFull", "Unauthorized", "IsTeleporting", "SomethingNew" } do
				local a, r = RetryPolicy.onInitFailed(name, 0)
				expect(a).toBe("give-up")
				expect(r).toBe(name)
				expect(type(RetryPolicy.playerMessage(r))).toBe("string")
			end
		end)
	end)
end
