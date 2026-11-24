--!strict
-- Lobby place, server side: turns the game's own models into queue areas. Placement and look stay the game's.
--
-- Tag any Part or Model "RobloxLobbyQueue" (CollectionService) and give it the attribute QueueId = "<queue id>".
-- Optional children (by name, anywhere inside), each a BasePart:
--   Enter    touching it joins the queue (default: the tagged Part itself, or every part of a tagged Model)
--   EnterPos where a joining player is moved (default: not moved)
--   ExitPos  where a leaving player is moved (default: not moved)
--   CamPos   the camera while queued (used by Client.defaultUi)
-- Optional attributes on the tagged instance:
--   TouchToJoin (bool, default true), Prompt (bool, default false: a ProximityPrompt on Enter to join or leave)
--
--   RobloxLobby.Pads.bind(lobby)   -- after Lobby.start, in the same server script

local Pads = {}

Pads.TAG = "RobloxLobbyQueue"

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
				if d:IsA("BasePart") and d.Name ~= "EnterPos" and d.Name ~= "ExitPos" and d.Name ~= "CamPos" then
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

	return {
		Disconnect = function()
			for _, c in conns do
				c:Disconnect()
			end
		end,
	}
end

return Pads
