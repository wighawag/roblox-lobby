--!strict
-- Lobby place, server side: the quick-start kit. Plain pads with a billboard, for a first playtest; a game
-- replaces them with its own models (tagged areas, see Pads) whenever it wants, with no change to its logic.
--
--   RobloxLobby.Kit.pad(lobby, "four", CFrame.new(0, 0.5, -20), { theme = { color = Color3.fromRGB(80, 160, 255) } })
--   RobloxLobby.Pads.bind(lobby)  -- binds kit pads like any tagged area
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

return Kit
