--!strict
local Envelope = require("../src/Envelope")

local function env(): any
	return Envelope.build({
		matchId = "M1",
		queueId = "duo",
		lobbyPlaceId = 10,
		members = { 3, 1 },
		sentAt = 100,
		data = { mode = "classic" },
	})
end

local function ctx(over: any?): any
	local c = { userId = 1, gameId = 7, lobbyPlaceId = 10, privateServerId = "M1", isStudio = false }
	for k, v in over or {} do
		c[k] = v
	end
	return c
end

local function join(over: any?): any
	local j = { TeleportData = env(), SourceGameId = 7, SourcePlaceId = 10 }
	for k, v in over or {} do
		j[k] = v
	end
	return j
end

return function(T)
	local it, expect = T.it, T.expect
	T.describe("Envelope", function()
		it("builds a versioned envelope with sorted members", function()
			local e = env()
			expect(e.rl).toBe(1)
			expect(e.members).toEqual({ 1, 3 })
			expect(e.data.mode).toBe("classic")
		end)
		it("parses its own output", function()
			local ok, e = Envelope.parse(env())
			expect(ok).toBe(true)
			expect(e.matchId).toBe("M1")
		end)
		it("rejects malformed envelopes", function()
			local cases = {
				{ nil, "no-envelope" },
				{ "x", "no-envelope" },
				{ { foo = 1 }, "no-envelope" },
				{ { rl = 2 }, "unknown-version" },
				{
					{ rl = 1, matchId = "", queueId = "q", lobbyPlaceId = 1, sentAt = 1, members = { 1 } },
					"bad-envelope",
				},
				{
					{ rl = 1, matchId = "m", queueId = "q", lobbyPlaceId = 1, sentAt = 1, members = {} },
					"bad-envelope",
				},
				{
					{ rl = 1, matchId = "m", queueId = "q", lobbyPlaceId = 1, sentAt = 1, members = { "1" } },
					"bad-envelope",
				},
			}
			for _, case in cases do
				local ok, reason = Envelope.parse(case[1])
				expect(ok).toBe(false)
				expect(reason).toBe(case[2])
			end
		end)
	end)

	T.describe("Envelope.validateJoin", function()
		it("accepts a member arriving from the lobby into the right reserved server", function()
			local ok, e = Envelope.validateJoin(join(), ctx())
			expect(ok).toBe(true)
			expect(e.matchId).toBe("M1")
		end)
		it("rejects a direct join", function()
			local ok, reason = Envelope.validateJoin({}, ctx())
			expect(ok).toBe(false)
			expect(reason).toBe("no-teleport-data")
		end)
		it("rejects another experience and another place", function()
			local _, r1 = Envelope.validateJoin(join({ SourceGameId = 8 }), ctx())
			expect(r1).toBe("wrong-source-game")
			local _, r2 = Envelope.validateJoin(join({ SourcePlaceId = 11 }), ctx())
			expect(r2).toBe("wrong-source-place")
		end)
		it("does not check the source place while lobbyPlaceId is 0", function()
			local ok = Envelope.validateJoin(join({ SourcePlaceId = 11 }), ctx({ lobbyPlaceId = 0 }))
			expect(ok).toBe(true)
		end)
		it("rejects a player not in the party", function()
			local _, r = Envelope.validateJoin(join(), ctx({ userId = 2 }))
			expect(r).toBe("not-a-member")
		end)
		it("rejects the wrong server in production, not in Studio", function()
			local _, r = Envelope.validateJoin(join(), ctx({ privateServerId = "" }))
			expect(r).toBe("wrong-server")
			local ok = Envelope.validateJoin(join(), ctx({ privateServerId = "", isStudio = true }))
			expect(ok).toBe(true)
		end)
		it("explains every reason", function()
			for _, r in { "no-teleport-data", "wrong-source-game", "not-a-member", "wrong-match", "wrong-server" } do
				expect(Envelope.explain(r) ~= r).toBe(true)
			end
		end)
	end)
end
