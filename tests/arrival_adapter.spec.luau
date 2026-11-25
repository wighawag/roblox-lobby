--!strict
local Envelope = require("../src/Envelope")
local Fakes = require("./fakes")
local Fixtures = require("./fixtures")
local Arrival = require("../src/Arrival")

local GAME, LOBBY, EXP = 106268450656854, 74888767056358, 9520747167

local function joinData(matchId: string, members: { number }): any
	return {
		SourceGameId = EXP,
		SourcePlaceId = LOBBY,
		TeleportData = Envelope.build({
			matchId = matchId,
			queueId = "duo",
			lobbyPlaceId = LOBBY,
			members = members,
			sentAt = 0,
			data = { mode = "classic" },
		}),
	}
end

local function setup(over: any?, options: any?, rawConfig: any?)
	local o = over or {}
	o.placeId = o.placeId or GAME
	if o.privateServerId == nil then
		o.privateServerId = "M"
	end
	local w = Fakes.world(o)
	local opts = options or {}
	opts.env = w.env
	local arrival = Arrival.start(rawConfig or Fixtures.config(), opts)
	local ev = { ready = {}, rejected = {}, joined = {}, changed = {} }
	arrival.Ready:Connect(function(m)
		table.insert(ev.ready, m)
	end)
	arrival.Rejected:Connect(function(p, r)
		table.insert(ev.rejected, { player = p, reason = r })
	end)
	arrival.PlayerJoined:Connect(function(p, info)
		table.insert(ev.joined, { player = p, late = info.late })
	end)
	arrival.Changed:Connect(function(progress)
		table.insert(ev.changed, progress)
	end)
	return w, arrival, ev
end

return function(T)
	local it, expect = T.it, T.expect
	T.describe("Arrival adapter", function()
		it("starts the match when the whole party is here", function()
			local w, arrival, ev = setup()
			local a = w.addPlayer(1, joinData("M", { 1, 2 }))
			arrival:_step()
			expect(#ev.ready).toBe(0)
			expect(ev.changed[1]).toEqual({ present = 1, expected = 2, secondsLeft = 30 })
			local b = w.addPlayer(2, joinData("M", { 1, 2 }))
			arrival:_step()
			expect(#ev.ready).toBe(1)
			local m = ev.ready[1]
			expect(m.source).toBe("teleport")
			expect(m.players).toEqual({ a, b })
			expect(m.data).toEqual({ mode = "classic" })
			expect(m.fakeMembers).toBe(0)
			expect(arrival:getMatch()).toBe(m)
			expect(#ev.joined).toBe(2)
		end)

		it("passes the host's options to the match", function()
			local w, arrival, ev = setup()
			local jd = joinData("M", { 1 })
			jd.TeleportData.options = { map = "Snow" }
			w.addPlayer(1, jd)
			arrival:_step()
			expect(ev.ready[1].hostOptions).toEqual({ map = "Snow" })
		end)

		it("starts after joinTimeout with missing members", function()
			local w, arrival, ev = setup()
			w.addPlayer(1, joinData("M", { 1, 2, 3 }))
			w.advance(29)
			arrival:_step()
			expect(#ev.ready).toBe(0)
			w.advance(1)
			arrival:_step()
			expect(ev.ready[1].missing).toEqual({ 2, 3 })
		end)

		it("sends a direct joiner back to the lobby", function()
			local w, _, ev = setup()
			local p = w.addPlayer(9, {})
			expect(ev.rejected[1].reason).toBe("no-teleport-data")
			expect(#w.teleports).toBe(1)
			expect(w.teleports[1].placeId).toBe(LOBBY)
			expect(w.teleports[1].options.ReservedServerId).toBe("")
			expect(p.kicked).toBe(nil)
		end)

		it("kicks with an explanation when the way back fails", function()
			local w = setup()
			w.teleportBehaviour = function()
				error("no")
			end
			local p = w.addPlayer(9, {})
			w.advance(10)
			expect(#w.teleports).toBe(3)
			expect(string.find(p.kicked, "directly", 1, true) ~= nil).toBe(true)
		end)

		it("can kick or keep instead", function()
			local w1 = setup(nil, { onRejected = "kick" })
			expect(w1.addPlayer(9, {}).kicked ~= nil).toBe(true)
			local w2, _, ev2 = setup(nil, { onRejected = "keep" })
			expect(w2.addPlayer(9, {}).kicked).toBe(nil)
			expect(#w2.teleports).toBe(0)
			expect(#ev2.rejected).toBe(1)
		end)

		it("rejects a player whose party is another reserved server", function()
			local w, _, ev = setup()
			w.addPlayer(1, joinData("M", { 1 }))
			w.addPlayer(6, joinData("OTHER", { 6 }))
			expect(#ev.rejected).toBe(1)
			expect(ev.rejected[1].reason).toBe("wrong-server")
		end)

		it("keeps two parties apart when the server id cannot tell (Studio)", function()
			local w, _, ev = setup({ isStudio = true, privateServerId = "" })
			w.addPlayer(1, joinData("M", { 1 }))
			w.addPlayer(6, joinData("OTHER", { 6 }))
			expect(ev.rejected[1].reason).toBe("wrong-match")
		end)

		it("accepts a late member after the start", function()
			local w, arrival, ev = setup()
			w.addPlayer(1, joinData("M", { 1, 2 }))
			w.advance(30)
			arrival:_step()
			w.addPlayer(2, joinData("M", { 1, 2 }))
			expect(ev.joined[2].late).toBe(true)
		end)

		it("checks players already present when it starts", function()
			local w = Fakes.world({ placeId = GAME, privateServerId = "M" })
			w.addPlayer(1, joinData("M", { 1 }))
			local arrival = Arrival.start(Fixtures.config(), { env = w.env })
			local ready = nil
			arrival.Ready:Connect(function(m)
				ready = m
			end)
			arrival:_step()
			expect(ready ~= nil).toBe(true)
		end)

		it("returns players to the lobby", function()
			local w, arrival = setup()
			local p = w.addPlayer(1, joinData("M", { 1 }))
			expect(arrival:returnToLobby({ p }, { won = true })).toBe(true)
			expect(w.teleports[1].placeId).toBe(LOBBY)
			expect(w.teleports[1].options:GetTeleportData()).toEqual({ won = true })
		end)

		it("warns when this place is not in the config", function()
			local w = setup({ placeId = 1 })
			expect(w.warned("not in LobbyConfig.places")).toBe(true)
		end)
	end)

	T.describe("Arrival adapter in Studio", function()
		it("gathers clients for joinWindow and starts a validated Studio match with fake slots", function()
			local raw = Fixtures.config()
			raw.studio = { joinWindow = 3, fakeMembers = 2 }
			local w, arrival, ev = setup({ isStudio = true, gameId = 0, placeId = 0, privateServerId = "" }, {
				studioData = function(members)
					return { mode = "studio", n = #members }
				end,
			}, raw)
			expect(w.logged("game place started in Studio")).toBe(true)
			w.addPlayer(1, {})
			w.advance(1)
			w.addPlayer(2, {})
			arrival:_step()
			expect(#ev.ready).toBe(0)
			w.advance(2)
			arrival:_step()
			local m = ev.ready[1]
			expect(m.source).toBe("studio")
			expect(m.expected).toEqual({ 1, 2 })
			expect(m.fakeMembers).toBe(2)
			expect(m.data).toEqual({ mode = "studio", n = 2 })
			expect(string.sub(m.matchId, 1, 7)).toBe("studio-")
			expect(#ev.rejected).toBe(0)
		end)

		it("uses real teleport data when a Studio Test-mode teleport brought it", function()
			local w, arrival, ev = setup({ isStudio = true, privateServerId = "" })
			w.addPlayer(1, joinData("M", { 1 }))
			arrival:_step()
			expect(ev.ready[1].source).toBe("teleport")
		end)

		it("never kicks or teleports rejected players in Studio", function()
			local w, _, ev = setup({ isStudio = true, privateServerId = "" })
			local bad = joinData("M", { 1 })
			bad.SourceGameId = 1
			local p = w.addPlayer(1, bad)
			expect(#ev.rejected).toBe(1)
			expect(p.kicked).toBe(nil)
			expect(#w.teleports).toBe(0)
		end)

		it("simulates the return to the lobby for a local file", function()
			local w, arrival = setup({ isStudio = true, gameId = 0, placeId = 0, privateServerId = "" })
			expect(arrival:returnToLobby({})).toBe(true)
			expect(#w.teleports).toBe(0)
			expect(w.logged("SIMULATED return")).toBe(true)
		end)
	end)
end
