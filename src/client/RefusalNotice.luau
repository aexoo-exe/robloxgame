-- Shows a short message near the top of the screen when the server refuses one of the player's
-- requests (RequestRefused), for example "Not enough gold". Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteNames"))
local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local RefusalNotice = {}

function RefusalNotice.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RefusalNotice"
	screenGui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 52) -- below the phase label
	label.Size = UDim2.fromOffset(320, 32)
	label.BackgroundColor3 = Color3.fromRGB(140, 30, 30)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.Visible = false
	label.Parent = screenGui

	-- Each message hides itself after a delay unless a newer message replaced it.
	local shownCount = 0
	remotes:WaitForChild(RemoteNames.RequestRefused).OnClientEvent:Connect(function(reason: string)
		shownCount += 1
		local thisMessage = shownCount
		label.Text = reason
		label.Visible = true
		task.delay(RenderConfig.refusalNoticeDuration, function()
			if shownCount == thisMessage then
				label.Visible = false
			end
		end)
	end)

	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return RefusalNotice
