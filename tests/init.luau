--!strict
-- Test entry point: `lune run tests` runs every tests/**/*.spec.luau.

local fs = require("@lune/fs")
local process = require("@lune/process")
local Harness = require("@self/harness")

local function collect(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			collect(path, out)
		elseif string.sub(name, -10) == ".spec.luau" then
			table.insert(out, path)
		end
	end
end

local specs = {}
collect("tests", specs)
table.sort(specs)

for _, path in specs do
	-- each spec is a module returning function(Harness)
	local spec = (require :: any)("./" .. string.sub(path, 1, -6))
	spec(Harness)
end

process.exit(if Harness.run() == 0 then 0 else 1)
