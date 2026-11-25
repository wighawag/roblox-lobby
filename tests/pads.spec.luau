--!strict
local Pads = require("../src/Pads")

return function(T)
	local it, expect = T.it, T.expect
	T.describe("Pads.contains (booth Zone)", function()
		local size = { X = 12, Y = 12, Z = 12 }
		it("is true inside and on the edge", function()
			expect(Pads.contains(size, { X = 0, Y = 0, Z = 0 })).toBe(true)
			expect(Pads.contains(size, { X = 6, Y = -6, Z = 5.9 })).toBe(true)
		end)
		it("is false outside on any axis", function()
			expect(Pads.contains(size, { X = 6.1, Y = 0, Z = 0 })).toBe(false)
			expect(Pads.contains(size, { X = 0, Y = 7, Z = 0 })).toBe(false)
			expect(Pads.contains(size, { X = 0, Y = 0, Z = -8 })).toBe(false)
		end)
	end)
end
