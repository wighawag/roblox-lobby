--!strict
local Signal = require("../src/Signal")

return function(T)
	local it, expect = T.it, T.expect
	T.describe("Signal", function()
		it("fires in order, disconnects, once", function()
			local s = Signal.new()
			local got = {}
			local c = s:Connect(function(v)
				table.insert(got, "a" .. v)
			end)
			s:Once(function(v)
				table.insert(got, "b" .. v)
			end)
			s:Fire(1)
			c:Disconnect()
			s:Fire(2)
			expect(got).toEqual({ "a1", "b1" })
		end)
		it("isolates a failing handler", function()
			local errors = {}
			local s = Signal.new(function(e)
				table.insert(errors, e)
			end)
			local ran = false
			s:Connect(function()
				error("boom")
			end)
			s:Connect(function()
				ran = true
			end)
			s:Fire()
			expect(ran).toBe(true)
			expect(#errors).toBe(1)
		end)
	end)
end
