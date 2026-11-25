--!strict
local Config = require("../src/Config")
local LobbyState = require("../src/LobbyState")
local Fixtures = require("./fixtures")

local function hostState(over: any?): any
	local raw = Fixtures.config()
	local q = {
		id = "party",
		place = "game",
		minPlayers = 1,
		maxPlayers = 5,
		countdown = 15,
		size = "host",
		hostOptions = { { id = "map", choices = { "Random", "Snow", "Jungle" } } },
	}
	for k, v in over or {} do
		q[k] = v
	end
	raw.queues = { q }
	return LobbyState.new(Config.assert(raw).queues)
end

return function(T)
	local it, expect = T.it, T.expect
	T.describe("LobbyState, size = host", function()
		it("makes the first player host and locks the booth while they choose", function()
			local s = hostState()
			expect(s:join(1, "party", 0)).toBe(true)
			local v = s:view("party", 0)
			expect(v.phase).toBe("creating")
			expect(v.host).toBe(1)
			local ok, reason = s:join(2, "party", 1)
			expect(ok).toBe(false)
			expect(reason).toBe("creating")
			expect(#s:tick(19)).toBe(0) -- no countdown while creating
		end)

		it("fills to exactly the chosen size, then launches on the full countdown with the options", function()
			local s = hostState()
			s:join(1, "party", 0)
			expect(s:configure(1, "party", { size = 3, options = { map = "Snow" } }, 1)).toBe(true)
			local v = s:view("party", 1)
			expect(v.phase).toBe("waiting")
			expect(v.capacity).toBe(3)
			expect(v.minPlayers).toBe(3)
			expect(v.options).toEqual({ map = "Snow" })
			s:join(2, "party", 2)
			expect(#s:tick(30)).toBe(0) -- 2/3: waits, however long
			s:join(3, "party", 30)
			local _, r = s:join(4, "party", 30)
			expect(r).toBe("full")
			expect(s:view("party", 30).secondsLeft).toBe(5)
			local l = s:tick(35)
			expect(#l).toBe(1)
			expect(l[1].members).toEqual({ 1, 2, 3 })
			expect(l[1].options).toEqual({ map = "Snow" })
			-- the booth is fresh again
			s:join(9, "party", 36)
			expect(s:view("party", 36).phase).toBe("creating")
		end)

		it("a party of one launches after the full countdown", function()
			local s = hostState()
			s:join(1, "party", 0)
			s:configure(1, "party", { size = 1 }, 0)
			expect(#s:tick(4)).toBe(0)
			expect(#s:tick(5)).toBe(1)
		end)

		it("validates the host's choice", function()
			local s = hostState()
			s:join(1, "party", 0)
			s:join(2, "other", 0)
			local function reason(userId, choice)
				local _, r = s:configure(userId, "party", choice, 0)
				return r
			end
			expect(reason(2, { size = 2 })).toBe("not-host")
			expect(reason(1, { size = 0 })).toBe("bad-size")
			expect(reason(1, { size = 6 })).toBe("bad-size")
			expect(reason(1, { size = 2.5 })).toBe("bad-size")
			expect(reason(1, { size = 2, options = { map = "Moon" } })).toBe("bad-option")
			expect(reason(1, { size = 2, options = { color = "Red" } })).toBe("bad-option")
			expect(reason(1, { size = 2, min = 1 })).toBe("bad-min") -- hostMin is off
			expect(s:configure(1, "party", { size = 2 }, 0)).toBe(true)
			expect(s:view("party", 0).options).toEqual({ map = "Random" }) -- first choice by default
			expect(reason(1, { size = 3 })).toBe("not-creating")
		end)

		it("lets the host pick a minimum when hostMin is on", function()
			local s = hostState({ hostMin = true })
			s:join(1, "party", 0)
			expect(s:configure(1, "party", { size = 4, min = 2 }, 0)).toBe(true)
			s:join(2, "party", 1)
			expect(s:view("party", 1).phase).toBe("counting")
			expect(s:view("party", 1).secondsLeft).toBe(15)
			local _, r = s:configure(1, "party", { size = 4, min = 5 }, 0)
			expect(r).toBe("not-creating")
		end)

		it("chooses the maximum size when the host does not answer in time", function()
			local s = hostState({ hostTimeout = 20 })
			s:join(1, "party", 0)
			s:tick(19)
			expect(s:view("party", 19).phase).toBe("creating")
			s:tick(20)
			local v = s:view("party", 20)
			expect(v.phase).toBe("waiting")
			expect(v.capacity).toBe(5)
			expect(v.options).toEqual({ map = "Random" })
		end)

		it("passes the host role on when the host leaves, and resets an empty booth", function()
			local s = hostState()
			s:join(1, "party", 0)
			s:configure(1, "party", { size = 3, options = { map = "Jungle" } }, 0)
			s:join(2, "party", 1)
			s:leave(1, 2)
			local v = s:view("party", 2)
			expect(v.host).toBe(2)
			expect(v.capacity).toBe(3)
			expect(v.options).toEqual({ map = "Jungle" })
			s:remove(2, 3)
			v = s:view("party", 3)
			expect(v.host).toBe(nil)
			expect(v.capacity).toBe(5)
			s:join(7, "party", 4)
			expect(s:view("party", 4).phase).toBe("creating")
		end)

		it("a host who leaves while choosing frees the booth", function()
			local s = hostState()
			s:join(1, "party", 0)
			s:leave(1, 1)
			expect(s:join(2, "party", 1)).toBe(true)
			expect(s:view("party", 1).host).toBe(2)
		end)

		it("an aborted host party gets its host and choices back", function()
			local s = hostState()
			s:join(1, "party", 0)
			s:configure(1, "party", { size = 2, options = { map = "Snow" } }, 0)
			s:join(2, "party", 0)
			local l = s:tick(5)[1]
			s:abort(l.id, 6)
			local v = s:view("party", 6)
			expect(v.host).toBe(1)
			expect(v.capacity).toBe(2)
			expect(v.options).toEqual({ map = "Snow" })
		end)

		it("fixed-size queues are unchanged and refuse configure", function()
			local s = LobbyState.new(Config.assert(Fixtures.config()).queues)
			s:join(1, "duo", 0)
			local v = s:view("duo", 0)
			expect(v.phase).toBe("waiting")
			expect(v.host).toBe(nil)
			local _, r = s:configure(1, "duo", { size = 1 }, 0)
			expect(r).toBe("not-host-mode")
		end)
	end)
end
