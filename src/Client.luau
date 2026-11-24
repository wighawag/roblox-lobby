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

-- Calls callback(view) now and on every change. view: Format.View plus `members` (user ids).
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
		local camera = workspace.CurrentCamera
		if queueId then
			observing = Client.observe(queueId, function(view)
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
