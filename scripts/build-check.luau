--!strict
-- Build test: builds the example places and the package with Rojo, then opens the built files with Lune's
-- @lune/roblox and checks the structure an integrating game relies on. Usage: lune run scripts/build-check
-- (needs rojo on PATH, e.g. inside `nix develop`).

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local failures = 0
local function check(cond: boolean, what: string)
	print((if cond then "ok    " else "FAIL  ") .. what)
	if not cond then
		failures += 1
	end
end

local function rojo(project: string, out: string)
	local r = process.exec("rojo", { "build", project, "-o", out })
	if not r.ok then
		print(r.stderr)
		error("rojo build failed for " .. project)
	end
end

if not fs.isDir("build") then
	fs.writeDir("build")
end
rojo("examples/lobby.project.json", "build/lobby.rbxlx")
rojo("examples/game.project.json", "build/game.rbxlx")
rojo("default.project.json", "build/RobloxLobby.rbxm")

local EXPECTED_MODULES = {
	"Arrival",
	"ArrivalState",
	"Client",
	"Config",
	"Env",
	"Envelope",
	"Format",
	"Kit",
	"Lobby",
	"LobbyState",
	"Pads",
	"PlaceCheck",
	"RetryPolicy",
	"Signal",
	"Teleport",
}

local function checkPackage(pkg: any, where: string)
	check(pkg ~= nil and pkg.ClassName == "ModuleScript", where .. ": RobloxLobby is a ModuleScript")
	if not pkg then
		return
	end
	for _, name in EXPECTED_MODULES do
		local child = pkg:FindFirstChild(name)
		check(child ~= nil and child.ClassName == "ModuleScript", `{where}: RobloxLobby.{name} is a ModuleScript child`)
	end
end

for _, placeName in { "lobby", "game" } do
	local place = roblox.deserializePlace(fs.readFile(`build/{placeName}.rbxlx`))
	local rs = place:GetService("ReplicatedStorage")
	local packages = rs:FindFirstChild("Packages")
	checkPackage(packages and packages:FindFirstChild("RobloxLobby"), placeName)
	local cfg = rs:FindFirstChild("LobbyConfig")
	check(
		cfg ~= nil and cfg.ClassName == "ModuleScript",
		placeName .. ": ReplicatedStorage.LobbyConfig is a ModuleScript"
	)
	local sss = place:GetService("ServerScriptService")
	local server = sss:FindFirstChild(if placeName == "lobby" then "LobbyServer" else "GameServer")
	check(server ~= nil and server.ClassName == "Script", placeName .. ": its server Script exists")
end

local model = roblox.deserializeModel(fs.readFile("build/RobloxLobby.rbxm"))
checkPackage(model[1], "RobloxLobby.rbxm")

print(if failures == 0 then "Build check passed." else `Build check FAILED ({failures}).`)
process.exit(if failures == 0 then 0 else 1)
