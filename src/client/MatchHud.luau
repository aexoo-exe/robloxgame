-- Placeholder match UI, read from the public MatchState:
--   * a list of every participant with HP (left edge), eliminated players with their placement
--   * a message when you are eliminated, with your placement
--   * a final placements screen during MatchOver
-- Presentation only. It redraws a few times per second rather than tracking every attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Phase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Phase"))

local MatchHud = {}

local REFRESH_SECONDS = 0.25

local function createLabel(parent: Instance, size: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.Parent = parent
	return label
end

local function createPanel(parent: Instance): Frame
	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = Color3.new(0, 0, 0)
	panel.BackgroundTransparency = 0.35
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel
	return panel
end

-- Participants in display order: still playing by HP (highest first), then eliminated by placement.
local function sortedEntries(playersFolder: Instance)
	local entries = {}
	for _, folder in playersFolder:GetChildren() do
		table.insert(entries, {
			userId = folder:GetAttribute("UserId"),
			name = folder:GetAttribute("DisplayName") or folder.Name,
			health = folder:GetAttribute("Health") or 0,
			placement = folder:GetAttribute("Placement") or 0,
			eliminated = folder:GetAttribute("Eliminated") == true,
			connected = folder:GetAttribute("Connected") ~= false,
		})
	end
	table.sort(entries, function(a, b)
		if a.eliminated ~= b.eliminated then
			return not a.eliminated
		elseif a.eliminated then
			return a.placement < b.placement
		elseif a.health ~= b.health then
			return a.health > b.health
		end
		return a.name < b.name
	end)
	return entries
end

local function clearLabels(panel: Instance)
	for _, child in panel:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

function MatchHud.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local playersFolder = matchState:WaitForChild("Players")
	local localUserId = Players.LocalPlayer.UserId

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MatchHud"
	screenGui.ResetOnSpawn = false

	local playerList = createPanel(screenGui)
	playerList.AnchorPoint = Vector2.new(0, 0.5)
	playerList.Position = UDim2.new(0, 8, 0.5, 0)
	playerList.Size = UDim2.fromOffset(220, 0)

	local eliminatedMessage = createLabel(screenGui, UDim2.fromOffset(460, 48), 26)
	eliminatedMessage.AnchorPoint = Vector2.new(0.5, 0.5)
	eliminatedMessage.Position = UDim2.fromScale(0.5, 0.3)
	eliminatedMessage.BackgroundColor3 = Color3.fromRGB(110, 20, 20)
	eliminatedMessage.BackgroundTransparency = 0.2
	eliminatedMessage.Visible = false

	local finalScreen = createPanel(screenGui)
	finalScreen.AnchorPoint = Vector2.new(0.5, 0.5)
	finalScreen.Position = UDim2.fromScale(0.5, 0.5)
	finalScreen.Size = UDim2.fromOffset(360, 0)
	finalScreen.Visible = false

	local function refresh()
		local phase = matchState:GetAttribute("Phase")
		local entries = sortedEntries(playersFolder)

		clearLabels(playerList)
		playerList.Visible = #entries > 0
		for order, entry in entries do
			local text = if entry.eliminated
				then string.format("#%d  %s  (out)", entry.placement, entry.name)
				else string.format(
					"%s  %d HP%s",
					entry.name,
					entry.health,
					if entry.connected then "" else "  (away)"
				)
			local label = createLabel(playerList, UDim2.new(1, 0, 0, 20), 15)
			label.LayoutOrder = order
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Text = text
			label.TextTransparency = if entry.eliminated then 0.5 else 0
			if entry.userId == localUserId then
				label.TextColor3 = Color3.fromRGB(255, 220, 90)
			end
		end

		local own = playersFolder:FindFirstChild(tostring(localUserId))
		local ownEliminated = own and own:GetAttribute("Eliminated") == true
		eliminatedMessage.Visible = ownEliminated == true and phase ~= Phase.MatchOver
		if ownEliminated then
			eliminatedMessage.Text = string.format("You were eliminated - #%d place", own:GetAttribute("Placement"))
		end

		finalScreen.Visible = phase == Phase.MatchOver
		if finalScreen.Visible then
			clearLabels(finalScreen)
			local title = createLabel(finalScreen, UDim2.new(1, 0, 0, 32), 24)
			title.LayoutOrder = 0
			title.Text = "Final placements"
			table.sort(entries, function(a, b)
				return a.placement < b.placement
			end)
			for order, entry in entries do
				local label = createLabel(finalScreen, UDim2.new(1, 0, 0, 24), 18)
				label.LayoutOrder = order
				label.Text = string.format("#%d  %s", entry.placement, entry.name)
				if entry.userId == localUserId then
					label.TextColor3 = Color3.fromRGB(255, 220, 90)
				end
			end
		end
	end

	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return MatchHud
