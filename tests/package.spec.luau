--!strict
local fs = require("@lune/fs")
local RobloxLobby = require("../src")

return function(T)
	local it, expect = T.it, T.expect
	T.describe("package", function()
		it("VERSION file and RobloxLobby.VERSION agree", function()
			local v = string.gsub(fs.readFile("VERSION"), "%s+$", "")
			expect(RobloxLobby.VERSION).toBe(v)
		end)
		it("exposes its modules lazily", function()
			for _, name in { "Lobby", "Arrival", "Config", "Envelope", "Signal", "Format", "PlaceCheck" } do
				expect(type(RobloxLobby[name])).toBe("table")
			end
			expect(RobloxLobby.Nope).toBe(nil)
		end)
	end)
end
