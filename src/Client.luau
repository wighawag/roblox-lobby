--!strict
-- Lobby place, client side (LocalScript). Read-only view of the queues plus join/leave requests; the server
-- decides. Use it to drive your own UI, or call Client.defaultUi() for the quick-start kit.
--
--   local Client = require(ReplicatedStorage.Packages.RobloxLobby).Client
--   Client.observe("four", function(view) myLabel.Text = view.count .. "/" .. view.capacity end)
--   Client.join("four")  Client.leave()  Client.onNotice(function(message) ... end)
--   Client.onMyQueueChanged(function(queueIdOrNil) ... end)

local Format = require("./Format")

local Client = {}

local REMOTES_NAME = "RobloxLobbyRemotes"
local TAG = "RobloxLobbyQueue"

local function services()
	local g = game :: any
	return g:GetService("ReplicatedStorage"), g:GetService("Players")
end

local function remotes(): any
	local ReplicatedStorage = services()
	return ReplicatedStorage:WaitForChild(REMOTES_NAME)
end

function Client.join(queueId: string)
	remotes().Request:FireServer("join", queueId)
end

function Client.leave()
	remotes().Request:FireServer("leave")
end

function Client.onNotice(callback: (message: string) -> ()): any
	return remotes().Notice.OnClientEvent:Connect(callback)
end

-- size = "host": the host's choice for the party: { size = n, min = m?, options = { [id] = choice }? }.
function Client.createParty(queueId: string, choice: { size: number, min: number?, options: { [string]: string }? })
	remotes().Request:FireServer("configure", queueId, choice)
end

local function decode(s: any): any
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local HttpService = (game :: any):GetService("HttpService")
	local ok, v = pcall(HttpService.JSONDecode, HttpService, s)
	return if ok then v else nil
end

-- Calls callback(view) now and on every change. view: Format.View plus `members` (user ids), `sizeMode`
-- ("fixed" | "host"), `maxPlayers`, `hostMin`, `leave` ("walk" | "button"), `hostOptions` (the config's list of
-- { id, label, choices }) and `options` (the host's choices, once made).
-- Returns a connection-like object with :Disconnect().
function Client.observe(queueId: string, callback: (view: any) -> ()): any
	local folder = remotes():WaitForChild("Queues"):WaitForChild(queueId)
	local function fire()
		local view: any = Format.fromAttributes(queueId, folder:GetAttributes())
		local members = {}
		for id in string.gmatch(folder:GetAttribute("Members") or "", "%d+") do
			table.insert(members, tonumber(id))
		end
		view.members = members
		view.sizeMode = folder:GetAttribute("SizeMode") or "fixed"
		view.maxPlayers = folder:GetAttribute("MaxPlayers") or view.capacity
		view.hostMin = folder:GetAttribute("HostMin") == true
		view.leave = folder:GetAttribute("Leave") or "walk"
		view.hostOptions = decode(folder:GetAttribute("HostOptions")) or {}
		view.options = decode(folder:GetAttribute("Options"))
		callback(view)
	end
	fire()
	return folder.AttributeChanged:Connect(fire)
end

-- The queue the local player is in (nil if none), now and on every change.
function Client.onMyQueueChanged(callback: (queueId: string?) -> ()): any
	local _, Players = services()
	local me = Players.LocalPlayer.UserId
	local queues = remotes():WaitForChild("Queues")
	local current: string? = nil
	local function check()
		local found = nil
		for _, f in queues:GetChildren() do
			for id in string.gmatch(f:GetAttribute("Members") or "", "%d+") do
				if tonumber(id) == me then
					found = f.Name
				end
			end
		end
		if found ~= current then
			current = found
			callback(found)
		end
	end
	local conns = {}
	local function watch(f: any)
		table.insert(conns, f:GetAttributeChangedSignal("Members"):Connect(check))
	end
	for _, f in queues:GetChildren() do
		watch(f)
	end
	table.insert(conns, queues.ChildAdded:Connect(watch))
	check()
	return {
		Disconnect = function()
			for _, c in conns do
				c:Disconnect()
			end
		end,
	}
end

-- The default "Create Party" dialog for the host of a size = "host" queue: party size buttons, an optional
-- minimum row (hostMin), one row per host option (click to cycle its choices), and a Create button that calls
-- Client.createParty. Returns the Frame (destroy it to close). Used by defaultUi; a game can build its own dialog
-- from Client.observe (view.phase == "creating", view.host, view.maxPlayers, view.hostOptions) instead.
function Client.partyDialog(parent: any, queueId: string, view: any, theme: any?): any
	local t = theme or {}
	local font = t.font or Enum.Font.GothamBold
	local textColor = t.text or Color3.new(1, 1, 1)
	local accent = t.button or Color3.fromRGB(70, 170, 110)
	local idle = Color3.fromRGB(70, 70, 85)
	local maxPlayers = view.maxPlayers or view.capacity
	local size = maxPlayers
	local min = nil
	local choices = {}
	for _, o in view.hostOptions or {} do
		choices[o.id] = 1
	end

	local frame = Instance.new("Frame")
	frame.Name = "CreateParty"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.Size = UDim2.new(0, 460, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = t.background or Color3.fromRGB(20, 20, 28)
	frame.BackgroundTransparency = 0.1
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12)
	pad.Parent = frame

	local order = 0
	local function label(text: string, height: number)
		order += 1
		local l = Instance.new("TextLabel")
		l.LayoutOrder = order
		l.Size = UDim2.new(1, -24, 0, height)
		l.BackgroundTransparency = 1
		l.Text = text
		l.TextColor3 = textColor
		l.Font = font
		l.TextScaled = true
		l.Parent = frame
		return l
	end
	local function row()
		order += 1
		local r = Instance.new("Frame")
		r.LayoutOrder = order
		r.Size = UDim2.new(1, -24, 0, 44)
		r.BackgroundTransparency = 1
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.HorizontalAlignment = Enum.HorizontalAlignment.Center
		l.Padding = UDim.new(0, 6)
		l.Parent = r
		r.Parent = frame
		return r
	end
	local function button(container: any, text: string, width: number): any
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, width, 1, 0)
		b.BackgroundColor3 = idle
		b.Text = text
		b.TextColor3 = textColor
		b.Font = font
		b.TextScaled = true
		b.Parent = container
		return b
	end

	label("Create Party", 34)
	label("Party size", 24)
	local sizeRow = row()
	local sizeButtons = {}
	local minButtons = {}
	local function refresh()
		for n, b in sizeButtons do
			b.BackgroundColor3 = if n == size then accent else idle
		end
		for n, b in minButtons do
			b.BackgroundColor3 = if n == (min or size) then accent else idle
			b.Visible = n <= size
		end
	end
	for n = 1, maxPlayers do
		local b = button(sizeRow, tostring(n), 44)
		sizeButtons[n] = b
		b.Activated:Connect(function()
			size = n
			if min and min > size then
				min = size
			end
			refresh()
		end)
	end
	if view.hostMin then
		label("Start with at least", 22)
		local minRow = row()
		for n = 1, maxPlayers do
			local b = button(minRow, tostring(n), 44)
			minButtons[n] = b
			b.Activated:Connect(function()
				min = n
				refresh()
			end)
		end
	end
	for _, o in view.hostOptions or {} do
		local r = row()
		local name = button(r, o.label or o.id, 180)
		name.BackgroundTransparency = 1
		name.Active = false
		local value = button(r, o.choices[1], 200)
		value.Activated:Connect(function()
			choices[o.id] = choices[o.id] % #o.choices + 1
			value.Text = o.choices[choices[o.id]]
		end)
	end
	local createRow = row()
	local create = button(createRow, "Create", 220)
	create.BackgroundColor3 = accent
	create.Activated:Connect(function()
		local options = {}
		for _, o in view.hostOptions or {} do
			options[o.id] = o.choices[choices[o.id]]
		end
		Client.createParty(queueId, {
			size = size,
			min = if view.hostMin then (min or size) else nil,
			options = options,
		})
	end)
	refresh()
	frame.Parent = parent
	return frame
end

export type UiOptions = {
	-- your own ScreenGui to use instead of the default one; it may contain a TextLabel "Status" and a
	-- GuiButton "Leave" (both optional): the kit only sets Status.Text and toggles Leave.Visible
	template: any?,
	theme: {
		background: Color3?,
		text: Color3?,
		button: Color3?,
		font: any?, -- Enum.Font
		textSize: number?,
	}?,
	format: { [string]: (any) -> string }?, -- overrides of Format (status, leave)
	camera: boolean?, -- default true: while queued, look through the area's CamPos part if it has one
	partyDialog: boolean?, -- default true: show Client.partyDialog to the host of a size = "host" queue
}

-- The quick-start kit: a status line and a Leave button while the local player is queued, a notice line for the
-- server's messages, and the optional camera of the area. Returns the ScreenGui.
function Client.defaultUi(options: UiOptions?): any
	local opts: UiOptions = options or {}
	local _, Players = services()
	local g = game :: any
	local player = Players.LocalPlayer
	local fmt = Format.with(opts.format)
	local theme = opts.theme or {}

	local gui: any
	if opts.template then
		gui = opts.template:Clone()
	else
		gui = Instance.new("ScreenGui")
		gui.Name = "RobloxLobbyUi"
		gui.ResetOnSpawn = false
		local status = Instance.new("TextLabel")
		status.Name = "Status"
		status.AnchorPoint = Vector2.new(0.5, 0)
		status.Position = UDim2.new(0.5, 0, 0, 12)
		status.Size = UDim2.new(0, 360, 0, 36)
		status.BackgroundColor3 = theme.background or Color3.fromRGB(20, 20, 28)
		status.BackgroundTransparency = 0.2
		status.TextColor3 = theme.text or Color3.new(1, 1, 1)
		status.Font = theme.font or Enum.Font.GothamMedium
		status.TextSize = theme.textSize or 18
		status.Visible = false
		status.Parent = gui
		local leave = Instance.new("TextButton")
		leave.Name = "Leave"
		leave.AnchorPoint = Vector2.new(0.5, 0)
		leave.Position = UDim2.new(0.5, 0, 0, 54)
		leave.Size = UDim2.new(0, 120, 0, 32)
		leave.BackgroundColor3 = theme.button or Color3.fromRGB(200, 60, 60)
		leave.TextColor3 = theme.text or Color3.new(1, 1, 1)
		leave.Font = theme.font or Enum.Font.GothamMedium
		leave.TextSize = theme.textSize or 18
		leave.Visible = false
		leave.Parent = gui
		local notice = Instance.new("TextLabel")
		notice.Name = "Notice"
		notice.AnchorPoint = Vector2.new(0.5, 1)
		notice.Position = UDim2.new(0.5, 0, 1, -24)
		notice.Size = UDim2.new(0, 520, 0, 30)
		notice.BackgroundTransparency = 1
		notice.TextColor3 = theme.text or Color3.new(1, 1, 1)
		notice.TextStrokeTransparency = 0.5
		notice.Font = theme.font or Enum.Font.GothamMedium
		notice.TextSize = theme.textSize or 18
		notice.Text = ""
		notice.Parent = gui
	end
	gui.Parent = player:WaitForChild("PlayerGui")

	local status = gui:FindFirstChild("Status", true)
	local leave = gui:FindFirstChild("Leave", true)
	local notice = gui:FindFirstChild("Notice", true)

	if leave then
		leave.Activated:Connect(function()
			Client.leave()
		end)
	end
	Client.onNotice(function(message: string)
		if notice then
			notice.Text = message
			task.delay(5, function()
				if notice.Text == message then
					notice.Text = ""
				end
			end)
		end
	end)

	local observing: any = nil
	local dialog: any = nil
	local cameraSet = false
	local CollectionService = g:GetService("CollectionService")
	local function areaCam(queueId: string): any
		for _, area in CollectionService:GetTagged(TAG) do
			if area:GetAttribute("QueueId") == queueId then
				return area:FindFirstChild("CamPos", true)
			end
		end
		return nil
	end
	Client.onMyQueueChanged(function(queueId: string?)
		if observing then
			observing:Disconnect()
			observing = nil
		end
		if dialog then
			dialog:Destroy()
			dialog = nil
		end
		local camera = workspace.CurrentCamera
		if queueId then
			observing = Client.observe(queueId, function(view)
				if opts.partyDialog ~= false then
					local mine = view.phase == "creating" and view.host == player.UserId
					if mine and not dialog then
						dialog = Client.partyDialog(gui, queueId, view, theme)
					elseif not mine and dialog then
						dialog:Destroy()
						dialog = nil
					end
				end
				if status then
					status.Text = fmt.status(view)
					status.Visible = status.Text ~= ""
				end
				if leave then
					leave.Text = fmt.leave(view)
				end
			end)
			if leave then
				leave.Visible = true
			end
			local cam = if opts.camera == false then nil else areaCam(queueId)
			if cam then
				camera.CameraType = Enum.CameraType.Scriptable
				camera.CFrame = cam.CFrame
				cameraSet = true
			end
		else
			if status then
				status.Visible = false
			end
			if leave then
				leave.Visible = false
			end
			if cameraSet then
				camera.CameraType = Enum.CameraType.Custom
				cameraSet = false
			end
		end
	end)
	return gui
end

return Client
