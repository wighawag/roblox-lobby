--!strict
-- Minimal test harness for Lune: describe / it / expect. No third-party framework.

local Harness = {}

type Test = { name: string, fn: () -> () }

local tests: { Test } = {}
local prefix: { string } = {}

function Harness.describe(name: string, body: () -> ())
	table.insert(prefix, name)
	body()
	table.remove(prefix)
end

function Harness.it(name: string, fn: () -> ())
	local full = table.concat(prefix, " > ")
	table.insert(tests, { name = if full == "" then name else full .. " > " .. name, fn = fn })
end

local function fmt(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function Harness.expect(actual: any)
	local e = {}
	function e.toBe(expected: any)
		if actual ~= expected then
			error(`expected {fmt(expected)}, got {fmt(actual)}`, 2)
		end
	end
	function e.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error(`expected deep equality with {fmt(expected)}, got {fmt(actual)}`, 2)
		end
	end
	function e.toThrow(pattern: string?)
		local ok, err = pcall(actual)
		if ok then
			error("expected function to throw", 2)
		end
		if pattern and not string.find(tostring(err), pattern, 1, true) then
			error(`expected error containing {fmt(pattern)}, got {fmt(tostring(err))}`, 2)
		end
	end
	return e
end

-- Runs every registered test, prints one line each, returns the number of failures.
function Harness.run(): number
	local failed = 0
	for _, t in tests do
		local ok, err = pcall(t.fn)
		if ok then
			print(`PASS  {t.name}`)
		else
			failed += 1
			print(`FAIL  {t.name}\n      {err}`)
		end
	end
	print(`{#tests - failed} passed, {failed} failed`)
	table.clear(tests)
	return failed
end

return Harness
