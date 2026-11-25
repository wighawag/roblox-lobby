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
--   Barrier  invisible parts (a doorway, a roof) that block only QUEUED players, so they cannot walk or jump out
--            of a booth whose queue has leave = "button"; everyone else passes through
-- With leave = "button" (LobbyConfig), leaving the Zone does not remove a player: they are put back at EnterPos,
-- and only the Leave button leaves.
-- Walls, floors and decorations can be any other parts: with an Enter part, only Enter joins.
-- Optional attributes on the tagged instance:
--   TouchToJoin (bool, default true), Prompt (bool, default false: a ProximityPrompt on Enter to join or leave)
--
--   RobloxLobby.Pads.bind(lobby)   -- after Lobby.start, in the same server script

local Lobby = require("./Lobby")

local Pads = {}

Pads.TAG = "RobloxLobbyQueue"
Pads.LEAVE_GRACE = 0.3 -- seconds outside the Zone before a queued player is removed (measured live: a slower
-- check let a player who walked out during a 3 s countdown be teleported anyway)
Pads.CHECK_INTERVAL = 0.2

local SPECIAL = { EnterPos = true, ExitPos = true, CamPos = true, Zone = true, Barrier = true }

Pads.QUEUED_GROUP = "RobloxLobbyQueued"
Pads.BARRIER_GROUP = "RobloxLobbyBarrier"

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
	local PhysicsService = g:GetService("PhysicsService")
	local areasByQueue: { [string]: { any } } = {}
	local leaveMode: { [string]: string } = {}
	for _, q in lobby.config.queues do
		leaveMode[q.id] = q.leave
	end
	-- barriers collide with queued players only
	pcall(function()
		PhysicsService:RegisterCollisionGroup(Pads.QUEUED_GROUP)
		PhysicsService:RegisterCollisionGroup(Pads.BARRIER_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(Pads.BARRIER_GROUP, "Default", false)
		PhysicsService:CollisionGroupSetCollidable(Pads.BARRIER_GROUP, Pads.QUEUED_GROUP, true)
	end)
	local function setGroup(player: any, group: string)
		local character = player.Character
		if not character then
			return
		end
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				d.CollisionGroup = group
			end
		end
	end
	local conns = {}
	local cooldown: { [number]: number } = {}

	local lastRefusal: { [number]: number } = {}
	local function tryJoin(player: any, queueId: string)
		local ok, reason = lobby:join(player, queueId)
		if not ok and reason ~= "already-queued" and reason ~= "launching" then
			-- tell the player why, at most every 3 s (Touched fires a lot)
			local now = os.clock()
			if (lastRefusal[player.UserId] or 0) + 3 < now then
				lastRefusal[player.UserId] = now
				lobby:notify(player, Lobby.explainJoin(reason))
			end
		end
	end

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
		for _, d in (if area:IsA("BasePart") then { area } else area:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Barrier" then
				d.CollisionGroup = Pads.BARRIER_GROUP
				d.CanCollide = true
			end
		end

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
							tryJoin(player, queueId)
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
						tryJoin(player, queueId)
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
			if leaveMode[queueId] == "button" then
				setGroup(player, Pads.QUEUED_GROUP)
			end
		end)
	)
	table.insert(
		conns,
		lobby.PlayerLeftQueue:Connect(function(player: any, queueId: string)
			-- no instant re-join for a player still standing on the pad (give areas an ExitPos to avoid this)
			cooldown[player.UserId] = os.clock() + 3
			setGroup(player, "Default")
			local area = (areasByQueue[queueId] or {})[1]
			if area and player.Parent then
				moveTo(player, find(area, "ExitPos"))
			end
		end)
	)

	table.insert(
		conns,
		lobby.Launched:Connect(function(party: any)
			for _, p in party.players or {} do
				setGroup(p, "Default")
			end
		end)
	)

	-- booths: a queued player who walks out of the Zone leaves the queue (or, with leave = "button", is put back)
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
								if leaveMode[queueId] == "button" then
									-- only the Leave button leaves: put them back inside
									moveTo(player, find(areas[1], "EnterPos") or zone)
								else
									lobby:leave(player)
								end
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
