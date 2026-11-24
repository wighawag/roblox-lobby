--!strict
-- No-client configuration check. Usage: lune run scripts/check-places <path/to/LobbyConfig.luau>
-- Confirms through Roblox's public web APIs (no login) that every place id belongs to the configured experience.
-- Exit code 0 when everything matches, 1 otherwise.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local PlaceCheck = require("../src/PlaceCheck")

local path = process.args[1]
if not path or not fs.isFile(path) then
	print("usage: lune run scripts/check-places <path/to/LobbyConfig.luau>")
	process.exit(2)
end

-- LobbyConfig is plain data (`return { ... }`), so it is loaded without any Roblox API
local okLoad, config = pcall(function()
	return luau.load(fs.readFile(path), { debugName = path })()
end)
if not okLoad then
	print("FAIL  could not load " .. path .. ": " .. tostring(config))
	process.exit(1)
end

local function http(url: string): (boolean, any)
	local ok, res = pcall(net.request, { url = url, method = "GET" })
	if not ok then
		return false, res
	end
	if not res.ok then
		return false, `HTTP {res.statusCode}`
	end
	local okJson, body = pcall(serde.decode, "json", res.body)
	if not okJson then
		return false, "invalid JSON"
	end
	return true, body
end

local report = PlaceCheck.run(config, http)
for _, line in report.lines do
	print(line)
end
print(if report.ok then "All place ids belong to the configured experience." else "Place check FAILED.")
process.exit(if report.ok then 0 else 1)
