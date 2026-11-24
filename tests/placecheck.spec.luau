--!strict
-- PlaceCheck against answers recorded from the real endpoints on 2026-11-24 (hips' HIPS_Lobby experience).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local PlaceCheck = require("../src/PlaceCheck")
local Fixtures = require("./fixtures")

local function recorded(url: string): (boolean, any)
	local file
	local u = string.match(url, "universes/v1/places/(%d+)/universe")
	if u then
		file = "universe-" .. u
	elseif string.match(url, "universes/(%d+)/places") then
		file = "places-" .. string.match(url, "universes/(%d+)/places")
	elseif string.match(url, "develop.roblox.com/v1/universes/(%d+)$") then
		file = "universeinfo-" .. string.match(url, "universes/(%d+)$")
	end
	local path = "tests/recorded/" .. tostring(file) .. ".json"
	if not file or not fs.isFile(path) then
		return false, "HTTP 400" -- what the API answers for an unknown universe
	end
	return true, serde.decode("json", fs.readFile(path))
end

local function joined(r: any): string
	return table.concat(r.lines, "\n")
end

return function(T)
	local it, expect = T.it, T.expect
	T.describe("PlaceCheck", function()
		it("passes for hips' real ids", function()
			local r = PlaceCheck.run(Fixtures.config(), recorded)
			expect(r.ok).toBe(true)
			expect(string.find(joined(r), '"HIPS_Game" is in experience 9520747167', 1, true) ~= nil).toBe(true)
		end)
		it("passes for a PRIVATE experience (the roblox-lobby test experience)", function()
			local c = Fixtures.config()
			c.experienceId, c.lobbyPlaceId, c.places.game = 10778829653, 138124848909436, 135477523707348
			local r = PlaceCheck.run(c, recorded)
			expect(r.ok).toBe(true)
			expect(string.find(joined(r), "(Private)", 1, true) ~= nil).toBe(true)
		end)
		it("flags a place of another experience", function()
			local c = Fixtures.config()
			c.places.game = 555
			local r = PlaceCheck.run(c, recorded)
			expect(r.ok).toBe(false)
			expect(string.find(joined(r), "belongs to experience 111, NOT 9520747167", 1, true) ~= nil).toBe(true)
		end)
		it("flags an unknown place", function()
			local c = Fixtures.config()
			c.places.game = 1
			expect(string.find(joined(PlaceCheck.run(c, recorded)), "no such place", 1, true) ~= nil).toBe(true)
		end)
		it("flags a lobby that is not the start place", function()
			local c = Fixtures.config()
			c.lobbyPlaceId, c.places.game = 106268450656854, 74888767056358
			local r = PlaceCheck.run(c, recorded)
			expect(string.find(joined(r), "is not the experience's start place", 1, true) ~= nil).toBe(true)
		end)
		it("flags an unknown experience and unpublished ids", function()
			local c = Fixtures.config()
			c.experienceId = 99999999999999
			expect(
				string.find(joined(PlaceCheck.run(c, recorded)), "experience 99999999999999: not found", 1, true) ~= nil
			).toBe(true)
			c = Fixtures.config()
			c.places.game = 0
			expect(string.find(joined(PlaceCheck.run(c, recorded)), "still 0", 1, true) ~= nil).toBe(true)
		end)
		it("reports an invalid config instead of calling the network", function()
			local called = false
			local r = PlaceCheck.run({}, function()
				called = true
				return false, "no"
			end)
			expect(r.ok).toBe(false)
			expect(called).toBe(false)
		end)
	end)
end
