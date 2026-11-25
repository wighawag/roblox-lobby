--!strict
-- Lobby place, server side: the quick-start kit. Plain pads with a billboard, for a first playtest; a game
-- replaces them with its own models (tagged areas, see Pads) whenever it wants, with no change to its logic.
--
--   RobloxLobby.Kit.pad(lobby, "four", CFrame.new(0, 0.5, -20), { theme = { color = Color3.fromRGB(80, 160, 255) } })
--   RobloxLobby.Pads.bind(lobby)  -- binds kit pads like any tagged area
--
--   RobloxLobby.Kit.booth(lobby, "duo", CFrame.new(-14, 0, -26))  -- a walled booth, door facing +Z (local)
--
-- Options: theme { color, material, size (Vector3), textColor, font }, format (overrides of Format: players, time),
-- billboard (your own BillboardGui template; the kit only sets the Text of descendants named Players and Time),
-- parent (default workspace).

local Format = require("./Format")

local Kit = {}

function Kit.pad(lobby: any, queueId: string, cframe: CFrame, options: any?): any
	local opts = options or {}
	local theme = opts.theme or {}
	local fmt = Format.with(opts.format)
	local size = theme.size or Vector3.new(12, 1, 12)

	local model = Instance.new("Model")
	model.Name = "Queue_" .. queueId
	model:SetAttribute("QueueId", queueId)

	local pad = Instance.new("Part")
	pad.Name = "Enter"
	pad.Anchored = true
	pad.Size = size
	pad.CFrame = cframe
	pad.Color = theme.color or Color3.fromRGB(70, 170, 110)
	pad.Material = theme.material or Enum.Material.Neon
	pad.Parent = model

	local exit = Instance.new("Part")
	exit.Name = "ExitPos"
	exit.Anchored = true
	exit.CanCollide = false
	exit.CanTouch = false
	exit.Transparency = 1
	exit.Size = Vector3.new(1, 1, 1)
	exit.CFrame = cframe * CFrame.new(0, 0, size.Z / 2 + 6)
	exit.Parent = model

	local billboard: any
	if opts.billboard then
		billboard = opts.billboard:Clone()
	else
		billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 200, 0, 70)
		billboard.StudsOffset = Vector3.new(0, 6, 0)
		billboard.AlwaysOnTop = true
		local players = Instance.new("TextLabel")
		players.Name = "Players"
		players.Size = UDim2.new(1, 0, 0.6, 0)
		players.BackgroundTransparency = 1
		players.TextScaled = true
		players.TextColor3 = theme.textColor or Color3.new(1, 1, 1)
		players.Font = theme.font or Enum.Font.GothamBold
		players.Parent = billboard
		local time = Instance.new("TextLabel")
		time.Name = "Time"
		time.Position = UDim2.new(0, 0, 0.6, 0)
		time.Size = UDim2.new(1, 0, 0.4, 0)
		time.BackgroundTransparency = 1
		time.TextScaled = true
		time.TextColor3 = theme.textColor or Color3.new(1, 1, 1)
		time.Font = theme.font or Enum.Font.GothamMedium
		time.Parent = billboard
	end
	billboard.Adornee = pad
	billboard.Parent = pad

	local playersLabel = billboard:FindFirstChild("Players", true)
	local timeLabel = billboard:FindFirstChild("Time", true)
	local function render(view: any)
		local v = {
			id = queueId,
			count = #view.members,
			capacity = view.capacity,
			minPlayers = view.minPlayers,
			phase = view.phase,
			secondsLeft = view.secondsLeft,
		}
		if playersLabel then
			playersLabel.Text = fmt.players(v)
		end
		if timeLabel then
			timeLabel.Text = fmt.time(v)
		end
	end
	render(lobby:view(queueId))
	lobby.Changed:Connect(function(id: string, view: any)
		if id == queueId then
			render(view)
		end
	end)

	model.Parent = opts.parent or workspace
	-- tag last, so Pads.bind sees a complete model
	model:AddTag("RobloxLobbyQueue")
	return model
end

local function part(model: any, name: string, size: Vector3, cframe: CFrame, props: { [string]: any }?): any
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	p.Parent = model
	return p
end

local HIDDEN = { Transparency = 1, CanCollide = false, CanQuery = false }

-- A walled booth, the same pattern as HIPS' queue rooms: walls on three sides and a doorway on the local +Z side.
-- Walking through the doorway (the invisible Enter part) joins; the player is placed inside (EnterPos) and the
-- camera looks in from above the door (CamPos); walking back out of the booth (the invisible Zone) or pressing
-- Leave leaves the queue and puts the player outside (ExitPos). cframe is the centre of the floor.
-- Options: theme { color (walls), floorColor, material, size (Vector3: inner width, wall height, inner depth),
-- textColor, font }, format, billboard, parent (as Kit.pad).
function Kit.booth(lobby: any, queueId: string, cframe: CFrame, options: any?): any
	local opts = options or {}
	local theme = opts.theme or {}
	local fmt = Format.with(opts.format)
	local size = theme.size or Vector3.new(12, 8, 12)
	local w, h, d = size.X, size.Y, size.Z
	local t = 1 -- wall thickness
	local door = math.min(5, w - 2)
	local wallProps = {
		Color = theme.color or Color3.fromRGB(70, 170, 110),
		Material = theme.material or Enum.Material.SmoothPlastic,
	}

	local model = Instance.new("Model")
	model.Name = "Booth_" .. queueId
	model:SetAttribute("QueueId", queueId)

	part(model, "Floor", Vector3.new(w + 2 * t, 1, d + 2 * t), cframe * CFrame.new(0, 0.5, 0), {
		Color = theme.floorColor or Color3.fromRGB(235, 235, 235),
		Material = Enum.Material.SmoothPlastic,
	})
	local y = 1 + h / 2
	part(model, "WallBack", Vector3.new(w + 2 * t, h, t), cframe * CFrame.new(0, y, -(d + t) / 2), wallProps)
	part(model, "WallLeft", Vector3.new(t, h, d), cframe * CFrame.new(-(w + t) / 2, y, 0), wallProps)
	part(model, "WallRight", Vector3.new(t, h, d), cframe * CFrame.new((w + t) / 2, y, 0), wallProps)
	local side = (w + 2 * t - door) / 2
	part(
		model,
		"WallFrontLeft",
		Vector3.new(side, h, t),
		cframe * CFrame.new(-(door + side) / 2, y, (d + t) / 2),
		wallProps
	)
	part(
		model,
		"WallFrontRight",
		Vector3.new(side, h, t),
		cframe * CFrame.new((door + side) / 2, y, (d + t) / 2),
		wallProps
	)
	local enter = part(model, "Enter", Vector3.new(door, h, t), cframe * CFrame.new(0, y, (d + t) / 2), HIDDEN)
	enter.CanTouch = true
	part(model, "Zone", Vector3.new(w, h + 4, d), cframe * CFrame.new(0, 1 + (h + 4) / 2, 0), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	part(model, "EnterPos", Vector3.new(1, 1, 1), cframe * CFrame.new(0, 1.5, -d / 4), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	part(model, "ExitPos", Vector3.new(1, 1, 1), cframe * CFrame.new(0, 1.5, d / 2 + 8), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local camAt = (cframe * CFrame.new(0, h + 10, d / 2 + 14)).Position
	part(model, "CamPos", Vector3.new(1, 1, 1), CFrame.lookAt(camAt, (cframe * CFrame.new(0, 2, 0)).Position), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})

	local billboard: any
	if opts.billboard then
		billboard = opts.billboard:Clone()
	else
		billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 200, 0, 70)
		billboard.StudsOffset = Vector3.new(0, h / 2 + 3, 0)
		billboard.AlwaysOnTop = true
		for i, name in { "Players", "Time" } do
			local label = Instance.new("TextLabel")
			label.Name = name
			label.Position = UDim2.new(0, 0, if i == 1 then 0 else 0.6, 0)
			label.Size = UDim2.new(1, 0, if i == 1 then 0.6 else 0.4, 0)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.TextColor3 = theme.textColor or Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.4
			label.Font = theme.font or Enum.Font.GothamBold
			label.Parent = billboard
		end
	end
	billboard.Adornee = enter
	billboard.Parent = enter
	local playersLabel = billboard:FindFirstChild("Players", true)
	local timeLabel = billboard:FindFirstChild("Time", true)
	local function render(view: any)
		local v = {
			id = queueId,
			count = #view.members,
			capacity = view.capacity,
			minPlayers = view.minPlayers,
			phase = view.phase,
			secondsLeft = view.secondsLeft,
		}
		if playersLabel then
			playersLabel.Text = fmt.players(v)
		end
		if timeLabel then
			timeLabel.Text = fmt.time(v)
		end
	end
	render(lobby:view(queueId))
	lobby.Changed:Connect(function(id: string, view: any)
		if id == queueId then
			render(view)
		end
	end)

	model.Parent = opts.parent or workspace
	model:AddTag("RobloxLobbyQueue")
	return model
end

return Kit
