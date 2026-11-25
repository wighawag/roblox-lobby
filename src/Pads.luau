--!strict
-- Lobby place, server side: turns the game's own models into queue areas. Placement and look stay the game's.
--
-- Tag any Part or Model "RobloxLobbyQueue" (CollectionService) and give it the attribute QueueId = "<queue id>".
-- Optional children (by name, anywhere inside), each a BasePart:
--   Enter    touching it joins the queue (default: the tagged Part itself, or every part of a tagged Model)
--   EnterPos where a joining player is moved (default: not moved)
--   ExitPos  where a leaving player is moved (default: not moved)
--   CamPos   the camera while queued (used by Client.defaultUi)
--   Zone     the inside of a booth (an invisible, non-colliding part): a queued player whose character stays
--            outside it for LEAVE_GRACE seconds leaves the queue, so walking out of a booth means leaving it
-- Walls, floors and decorations can be any other parts: with an Enter part, only Enter joins.
-- Optional attributes on the tagged instance:
--   TouchToJoin (bool, default true), Prompt (bool, default false: a ProximityPrompt on Enter to join or leave)
--
--   RobloxLobby.Pads.bind(lobby)   -- after Lobby.start, in the same server script

local Pads = {}

Pads.TAG = "RobloxLobbyQueue"
Pads.LEAVE_GRACE = 0.3 -- seconds outside the Zone before a queued player is removed (measured live: a slower
-- check let a player who walked out during a 3 s countdown be teleported anyway)
Pads.CHECK_INTERVAL = 0.2

local SPECIAL = { EnterPos = true, ExitPos = true, CamPos = true, Zone = true }

-- Pure: is a point, given in the zone part's local space, inside a box of that size?
function Pads.contains(size: { X: number, Y: number, Z: number }, p: { X: number, Y: number, Z: number }): boolean
	return math.abs(p.X) <= size.X / 2 and math.abs(p.Y) <= size.Y / 2 and math.abs(p.Z) <= size.Z / 2
end

local function find(area: any, name: string): any
	if area.Name == name then
		return area
	end
	return area:FindFirstChild(name, true)
end

local function moveTo(player: any, part: any)
	local character = player.Character
	if part and character and character.PrimaryPart then
		character:PivotTo(part.CFrame + Vector3.new(0, 3, 0))
	end
end

function Pads.bind(lobby: any): any
	local g = game :: any
	local CollectionService = g:GetService("CollectionService")
	local Players = g:GetService("Players")
	local areasByQueue: { [string]: { any } } = {}
	local conns = {}
	local cooldown: { [number]: number } = {}

	local function register(area: any)
		local queueId = area:GetAttribute("QueueId")
		if type(queueId) ~= "string" or lobby:view(queueId) == nil then
			warn(
				`[RobloxLobby] {area:GetFullName()} is tagged {Pads.TAG} but its QueueId attribute "{tostring(queueId)}" is not a queue of LobbyConfig`
			)
			return
		end
		areasByQueue[queueId] = areasByQueue[queueId] or {}
		table.insert(areasByQueue[queueId], area)

		local enter = find(area, "Enter")
		local touchParts = {}
		if enter and enter:IsA("BasePart") then
			table.insert(touchParts, enter)
		elseif area:IsA("BasePart") then
			table.insert(touchParts, area)
		else
			for _, d in area:GetDescendants() do
				if d:IsA("BasePart") and not SPECIAL[d.Name] then
					table.insert(touchParts, d)
				end
			end
		end

		if area:GetAttribute("TouchToJoin") ~= false then
			for _, part in touchParts do
				table.insert(
					conns,
					part.Touched:Connect(function(hit: any)
						local character = hit:FindFirstAncestorWhichIsA("Model")
						local player = character and Players:GetPlayerFromCharacter(character)
						if not player then
							return
						end
						local now = os.clock()
						if (cooldown[player.UserId] or 0) > now then
							return
						end
						cooldown[player.UserId] = now + 1
						if lobby:queueOf(player) == nil then
							lobby:join(player, queueId)
						end
					end)
				)
			end
		end

		if area:GetAttribute("Prompt") == true and touchParts[1] then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Join"
			prompt.ObjectText = queueId
			prompt.RequiresLineOfSight = false
			prompt.Parent = touchParts[1]
			table.insert(
				conns,
				prompt.Triggered:Connect(function(player: any)
					if lobby:queueOf(player) == queueId then
						lobby:leave(player)
					else
						lobby:join(player, queueId)
					end
				end)
			)
		end
	end

	for _, area in CollectionService:GetTagged(Pads.TAG) do
		register(area)
	end
	table.insert(conns, CollectionService:GetInstanceAddedSignal(Pads.TAG):Connect(register))

	-- move players to EnterPos / ExitPos of the first area of their queue
	table.insert(
		conns,
		lobby.PlayerJoinedQueue:Connect(function(player: any, queueId: string)
			local area = (areasByQueue[queueId] or {})[1]
			if area then
				moveTo(player, find(area, "EnterPos"))
			end
		end)
	)
	table.insert(
		conns,
		lobby.PlayerLeftQueue:Connect(function(player: any, queueId: string)
			-- no instant re-join for a player still standing on the pad (give areas an ExitPos to avoid this)
			cooldown[player.UserId] = os.clock() + 3
			local area = (areasByQueue[queueId] or {})[1]
			if area and player.Parent then
				moveTo(player, find(area, "ExitPos"))
			end
		end)
	)

	-- booths: a queued player who walks out of the Zone leaves the queue
	local running = true
	local outsideSince: { [number]: number } = {}
	task.spawn(function()
		while running do
			task.wait(Pads.CHECK_INTERVAL)
			local now = os.clock()
			for queueId, areas in areasByQueue do
				local zone = find(areas[1], "Zone")
				local view = zone and lobby:view(queueId)
				if view then
					for _, userId in view.members do
						local player = Players:GetPlayerByUserId(userId)
						local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if root then
							local inside = Pads.contains(zone.Size, zone.CFrame:PointToObjectSpace(root.Position))
							if inside then
								outsideSince[userId] = nil
							elseif outsideSince[userId] == nil then
								outsideSince[userId] = now
							elseif now - outsideSince[userId] >= Pads.LEAVE_GRACE then
								outsideSince[userId] = nil
								lobby:leave(player)
							end
						end
					end
				end
			end
		end
	end)

	return {
		Disconnect = function()
			running = false
			for _, c in conns do
				c:Disconnect()
			end
		end,
	}
end

return Pads
