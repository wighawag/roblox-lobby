--!strict
-- The no-client configuration check: through Roblox's public web APIs (no login), confirms that every place id
-- in a LobbyConfig belongs to the intended experience. Catches the most common live failure (a place published
-- into the wrong experience, or a stale id) without starting Roblox. Pure: HTTP and JSON are injected, so it is
-- tested offline; scripts/check-places.luau runs it with Lune's net and serde.
--
-- Endpoints (unauthenticated, checked 2026-11-24):
--   https://apis.roblox.com/universes/v1/places/<placeId>/universe      -> {"universeId": n | null}
--   https://develop.roblox.com/v1/universes/<universeId>/places?limit=100 -> {"data": [{id, name, universeId}]}
--   https://games.roblox.com/v1/games?universeIds=<universeId>          -> {"data": [{rootPlaceId, name, creator}]}

local Config = require("./Config")

local PlaceCheck = {}

export type Http = (url: string) -> (boolean, any) -- (ok, decoded JSON body or error string)

export type Report = { ok: boolean, lines: { string } }

function PlaceCheck.run(rawConfig: any, http: Http): Report
	local lines = {}
	local okAll = true
	local function fail(s: string)
		okAll = false
		table.insert(lines, "FAIL  " .. s)
	end
	local function pass(s: string)
		table.insert(lines, "ok    " .. s)
	end

	local valid, config = Config.validate(rawConfig)
	if not valid then
		for _, p in config do
			fail("config: " .. p)
		end
		return { ok = false, lines = lines }
	end
	if not Config.isPublished(config) then
		fail(
			"some ids are still 0: publish both places into ONE experience, then fill in experienceId, lobbyPlaceId and places"
		)
		return { ok = false, lines = lines }
	end

	local exp = config.experienceId
	local okGame, game = http(`https://games.roblox.com/v1/games?universeIds={exp}`)
	local info = okGame and type(game) == "table" and type(game.data) == "table" and game.data[1] or nil
	if not info then
		fail(`experience {exp}: not found (is experienceId the universe id, not a place id?)`)
		return { ok = false, lines = lines }
	end
	pass(`experience {exp} is "{info.name}" by {info.creator and info.creator.name or "?"}`)

	local okPlaces, placesBody = http(`https://develop.roblox.com/v1/universes/{exp}/places?limit=100`)
	local names = {}
	if okPlaces and type(placesBody) == "table" and type(placesBody.data) == "table" then
		for _, p in placesBody.data do
			names[p.id] = p.name
		end
	end

	local function checkPlace(label: string, placeId: number)
		local ok, body = http(`https://apis.roblox.com/universes/v1/places/{placeId}/universe`)
		if not ok then
			fail(`{label} {placeId}: request failed ({tostring(body)})`)
			return
		end
		local universe = type(body) == "table" and body.universeId or nil
		if universe == nil then
			fail(`{label} {placeId}: no such place`)
		elseif universe ~= exp then
			fail(
				`{label} {placeId}: belongs to experience {universe}, NOT {exp} (published into the wrong experience?)`
			)
		else
			pass(`{label} {placeId} "{names[placeId] or "?"}" is in experience {exp}`)
		end
	end

	checkPlace("lobbyPlaceId", config.lobbyPlaceId)
	if info.rootPlaceId ~= config.lobbyPlaceId then
		fail(
			`lobbyPlaceId {config.lobbyPlaceId} is not the experience's start place ({info.rootPlaceId}): players joining the game would not land in the lobby`
		)
	else
		pass("lobbyPlaceId is the start place")
	end
	local placeNames = {}
	for name in config.places do
		table.insert(placeNames, name)
	end
	table.sort(placeNames)
	for _, name in placeNames do
		local id = config.places[name]
		if id == config.lobbyPlaceId then
			fail(`places.{name} is the lobby itself`)
		else
			checkPlace(`places.{name}`, id)
		end
	end
	return { ok = okAll, lines = lines }
end

return PlaceCheck
