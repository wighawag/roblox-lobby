--!strict
local Config = require("../src/Config")
local Fixtures = require("./fixtures")

local function problemsOf(raw: any): string
	local ok, result = Config.validate(raw)
	assert(not ok, "expected the config to be invalid")
	return table.concat(result, "\n")
end

return function(T)
	local it, expect = T.it, T.expect
	T.describe("Config.validate", function()
		it("accepts the fixture and fills defaults", function()
			local ok, c = Config.validate(Fixtures.config())
			expect(ok).toBe(true)
			expect(c.arrival.joinTimeout).toBe(30)
			expect(c.studio).toEqual({ joinWindow = 3, fakeMembers = 0, teleport = "auto" })
			expect(c.queues[1].fullCountdown).toBe(5)
			expect(c.queues[2].fullCountdown).toBe(0)
		end)
		it("defaults minPlayers to maxPlayers and countdown to 15", function()
			local raw = Fixtures.config()
			raw.queues = { { id = "q", place = "game", maxPlayers = 3 } }
			local _, c = Config.validate(raw)
			expect(c.queues[1].minPlayers).toBe(3)
			expect(c.queues[1].countdown).toBe(15)
		end)
		it("accepts zero ids before publishing", function()
			local raw = Fixtures.config()
			raw.experienceId, raw.lobbyPlaceId, raw.places.game = 0, 0, 0
			local ok, c = Config.validate(raw)
			expect(ok).toBe(true)
			expect(Config.isPublished(c)).toBe(false)
		end)
		it("lists every problem at once", function()
			local raw = Fixtures.config()
			raw.experienceId = "x"
			raw.queues[1].minPlayers = 5
			raw.queues[2].place = "nope"
			local p = problemsOf(raw)
			expect(string.find(p, "experienceId", 1, true) ~= nil).toBe(true)
			expect(string.find(p, "minPlayers (5) is greater than maxPlayers (2)", 1, true) ~= nil).toBe(true)
			expect(string.find(p, 'place "nope" is not in places', 1, true) ~= nil).toBe(true)
		end)
		it("catches typos as unknown keys", function()
			local raw = Fixtures.config()
			raw.queues[1].maxPlayer = 3
			raw.studio = { joinWindoww = 1 }
			local p = problemsOf(raw)
			expect(string.find(p, 'unknown key "maxPlayer"', 1, true) ~= nil).toBe(true)
			expect(string.find(p, 'unknown key "joinWindoww"', 1, true) ~= nil).toBe(true)
		end)
		it("rejects parties above 50, duplicate ids, empty queues", function()
			local raw = Fixtures.config()
			raw.queues[1].maxPlayers = 51
			raw.queues[2].id = "duo"
			local p = problemsOf(raw)
			expect(string.find(p, "from 1 to 50", 1, true) ~= nil).toBe(true)
			expect(string.find(p, "duplicate id", 1, true) ~= nil).toBe(true)
			raw = Fixtures.config()
			raw.queues = {}
			expect(string.find(problemsOf(raw), "non-empty list", 1, true) ~= nil).toBe(true)
		end)
		it("rejects a negative fullCountdown and the removed launchWhenFull", function()
			local raw = Fixtures.config()
			raw.queues[1].fullCountdown = -1
			raw.queues[2].launchWhenFull = true
			local p = problemsOf(raw)
			expect(string.find(p, "fullCountdown", 1, true) ~= nil).toBe(true)
			expect(string.find(p, 'unknown key "launchWhenFull"', 1, true) ~= nil).toBe(true)
		end)
		it("defaults leave, size and host settings", function()
			local _, c = Config.validate(Fixtures.config())
			local q = c.queues[1]
			expect(q.leave).toBe("walk")
			expect(q.size).toBe("fixed")
			expect(q.hostMin).toBe(false)
			expect(q.hostTimeout).toBe(20)
			expect(q.hostOptions).toEqual({})
		end)
		it("accepts a host party queue with options", function()
			local raw = Fixtures.config()
			raw.queues[2].size = "host"
			raw.queues[2].leave = "button"
			raw.queues[2].hostOptions = { { id = "map", label = "Map", choices = { "Snow", "Jungle" } } }
			local ok, c = Config.validate(raw)
			expect(ok).toBe(true)
			expect(c.queues[2].hostOptions[1].choices).toEqual({ "Snow", "Jungle" })
		end)
		it("rejects bad leave, size and host options", function()
			local raw = Fixtures.config()
			raw.queues[1].leave = "jump"
			raw.queues[1].size = "any"
			raw.queues[2].hostOptions = { { id = "map", choices = {} } }
			local p = problemsOf(raw)
			expect(string.find(p, ".leave must be", 1, true) ~= nil).toBe(true)
			expect(string.find(p, ".size must be", 1, true) ~= nil).toBe(true)
			expect(string.find(p, "choices must be a non-empty list", 1, true) ~= nil).toBe(true)
			raw = Fixtures.config()
			raw.queues[1].hostOptions = { { id = "map", choices = { "A" } } }
			expect(string.find(problemsOf(raw), 'needs size = "host"', 1, true) ~= nil).toBe(true)
		end)
		it("rejects bad studio options", function()
			local raw = Fixtures.config()
			raw.studio = { teleport = "real", fakeMembers = 1.5 }
			local p = problemsOf(raw)
			expect(string.find(p, "studio.teleport", 1, true) ~= nil).toBe(true)
			expect(string.find(p, "studio.fakeMembers", 1, true) ~= nil).toBe(true)
		end)
		it("assert throws with the whole list", function()
			expect(function()
				Config.assert({})
			end).toThrow("invalid LobbyConfig")
		end)
	end)

	T.describe("Config.checkRunningPlace", function()
		local c = Config.assert(Fixtures.config())
		it("is silent for the right ids", function()
			expect(#Config.checkRunningPlace(c, "lobby", 9520747167, 74888767056358)).toBe(0)
			expect(#Config.checkRunningPlace(c, "game", 9520747167, 106268450656854)).toBe(0)
		end)
		it("skips unpublished Studio places", function()
			expect(#Config.checkRunningPlace(c, "lobby", 0, 0)).toBe(0)
		end)
		it("names the wrong-experience publish", function()
			local p = Config.checkRunningPlace(c, "game", 111, 106268450656854)
			expect(#p).toBe(1)
			expect(string.find(p[1], "wrong experience", 1, true) ~= nil).toBe(true)
		end)
		it("names a place that is not configured", function()
			expect(#Config.checkRunningPlace(c, "lobby", 9520747167, 5)).toBe(1)
			expect(#Config.checkRunningPlace(c, "game", 9520747167, 74888767056358)).toBe(1)
		end)
	end)
end
