--!strict
local ArrivalState = require("../src/ArrivalState")
local Envelope = require("../src/Envelope")

local function env(matchId: string, members: { number }): any
	return Envelope.build({
		matchId = matchId,
		queueId = "duo",
		lobbyPlaceId = 1,
		members = members,
		sentAt = 0,
		data = { x = 1 },
	})
end

local function newState(studio: boolean?): any
	return ArrivalState.new({
		joinTimeout = 30,
		studio = studio == true,
		joinWindow = 3,
		makeStudioEnvelope = function(members)
			return Envelope.build({
				matchId = "studio",
				queueId = "duo",
				lobbyPlaceId = 0,
				members = members,
				sentAt = 0,
				data = { fake = true },
			})
		end,
	})
end

return function(T)
	local it, expect = T.it, T.expect
	T.describe("ArrivalState, teleport mode", function()
		it("is ready as soon as every member is present", function()
			local s = newState()
			expect(s:arrive(1, true, env("M", { 1, 2 }), 0).accept).toBe(true)
			expect(s:tick(1)).toBe(nil)
			expect(s:progress(1)).toEqual({ present = 1, expected = 2, secondsLeft = 29 })
			s:arrive(2, true, env("M", { 1, 2 }), 2)
			local m = s:tick(2)
			expect(m.source).toBe("teleport")
			expect(m.present).toEqual({ 1, 2 })
			expect(m.missing).toEqual({})
			expect(m.data.x).toBe(1)
			expect(s:tick(3)).toBe(nil) -- only once
		end)
		it("starts after joinTimeout with whoever came", function()
			local s = newState()
			s:arrive(1, true, env("M", { 1, 2, 3 }), 0)
			expect(s:tick(29)).toBe(nil)
			local m = s:tick(30)
			expect(m.missing).toEqual({ 2, 3 })
		end)
		it("rejects invalid arrivals with their reason", function()
			local s = newState()
			local d = s:arrive(1, false, "no-teleport-data", 0)
			expect(d.accept).toBe(false)
			expect(d.reason).toBe("no-teleport-data")
			expect(s:tick(100)).toBe(nil)
		end)
		it("keeps a second party out", function()
			local s = newState()
			s:arrive(1, true, env("M", { 1, 2 }), 0)
			local d = s:arrive(5, true, env("OTHER", { 5 }), 1)
			expect(d.accept).toBe(false)
			expect(d.reason).toBe("wrong-match")
		end)
		it("accepts a late member after the start and flags it", function()
			local s = newState()
			s:arrive(1, true, env("M", { 1, 2 }), 0)
			s:tick(30)
			local d = s:arrive(2, true, env("M", { 1, 2 }), 40)
			expect(d.accept).toBe(true)
			expect(d.late).toBe(true)
			expect(s:arrive(9, true, env("X", { 9 }), 41).accept).toBe(false)
		end)
		it("does not start a match whose players all left", function()
			local s = newState()
			s:arrive(1, true, env("M", { 1, 2 }), 0)
			s:leave(1)
			expect(s:tick(60)).toBe(nil)
		end)
		it("refuses players without data even in Studio once a real teleport fixed the match", function()
			local s = newState(true)
			s:arrive(1, true, env("M", { 1, 2 }), 0)
			expect(s:arrive(2, false, "no-teleport-data", 1).accept).toBe(false)
		end)
	end)

	T.describe("ArrivalState, Studio mode", function()
		it("is off unless enabled: no data means rejected", function()
			expect(newState(false):arrive(1, false, "no-teleport-data", 0).accept).toBe(false)
		end)
		it("collects players for joinWindow, then builds a validated synthetic match", function()
			local s = newState(true)
			expect(s:arrive(2, false, "no-teleport-data", 0).accept).toBe(true)
			s:arrive(1, false, "no-teleport-data", 1)
			expect(s:tick(2.9)).toBe(nil)
			expect(s:progress(1).expected).toBe(nil)
			local m = s:tick(3)
			expect(m.source).toBe("studio")
			expect(m.expected).toEqual({ 1, 2 })
			expect(m.data.fake).toBe(true)
		end)
		it("still rejects other failures in Studio", function()
			expect(newState(true):arrive(1, false, "wrong-source-game", 0).accept).toBe(false)
		end)
		it("accepts later Studio clients as late", function()
			local s = newState(true)
			s:arrive(1, false, "no-teleport-data", 0)
			s:tick(3)
			local d = s:arrive(2, false, "no-teleport-data", 5)
			expect(d.accept).toBe(true)
			expect(d.late).toBe(true)
		end)
		it("reports a broken synthetic envelope loudly", function()
			local s = ArrivalState.new({
				joinTimeout = 30,
				studio = true,
				joinWindow = 0,
				makeStudioEnvelope = function()
					return {}
				end,
			})
			s:arrive(1, false, "no-teleport-data", 0)
			expect(function()
				s:tick(0)
			end).toThrow("Studio envelope is invalid")
		end)
	end)
end
