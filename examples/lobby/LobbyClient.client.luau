-- Example lobby place, client: the quick-start status line and Leave button.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxLobby = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("RobloxLobby"))

RobloxLobby.Client.defaultUi()
