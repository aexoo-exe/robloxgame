-- Creates RemoteEvents under ReplicatedStorage.Remotes. Names come from Shared.RemoteNames.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

function Remotes.create(name: string): RemoteEvent
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

return Remotes
