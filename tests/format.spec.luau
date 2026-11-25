--!strict
local Format = require("../src/Format")

local function view(over: any): any
	local v = { id = "q", count = 1, capacity = 4, minPlayers = 2, phase = "waiting", secondsLeft = nil }
	for k, x in over do
		v[k] = x
	end
	return v
end

return function(T)
	local it, expect = T.it, T.expect
	T.describe("Format", function()
		it("has readable defaults", function()
			expect(Format.players(view({}))).toBe("1/4")
			expect(Format.time(view({}))).toBe("")
			expect(Format.status(view({}))).toBe("Waiting for 1 more player (1/4)")
			expect(Format.status(view({ count = 0 }))).toBe("Waiting for 2 more players (0/4)")
			expect(Format.status(view({ count = 2, phase = "counting", secondsLeft = 4.2 }))).toBe(
				"Starting in 5 s (2/4)"
			)
			expect(Format.time(view({ phase = "counting", secondsLeft = 4.2 }))).toBe("5 s")
			expect(Format.status(view({ count = 2, phase = "counting", secondsLeft = 0 }))).toBe("Teleporting...")
			expect(Format.status(view({ phase = "creating" }))).toBe("Creating the party...")
			expect(Format.fromAttributes("q", { Host = 7 }).host).toBe(7)
			expect(Format.fromAttributes("q", { Host = 0 }).host).toBe(nil)
		end)
		it("lets a game override any text", function()
			local f = Format.with({
				players = function(v)
					return `{v.count} joueurs`
				end,
			})
			expect(f.players(view({}))).toBe("1 joueurs")
			expect(f.status(view({}))).toBe("Waiting for 1 more player (1/4)")
			expect(f.with).toBe(nil)
		end)
		it("reads the replicated attributes", function()
			local v = Format.fromAttributes(
				"q",
				{ Count = 2, Capacity = 4, MinPlayers = 2, Phase = "counting", SecondsLeft = 7 }
			)
			expect(v.secondsLeft).toBe(7)
			expect(Format.fromAttributes("q", { SecondsLeft = -1 }).secondsLeft).toBe(nil)
		end)
	end)
end
