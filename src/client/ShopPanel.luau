-- Placeholder shop and economy panel on the right edge of the screen: gold, level, XP progress,
-- units on the board against the cap, five shop buttons, reroll, buy XP and sell. Buttons only send
-- requests; everything shown comes from the server's PlayerStateUpdated and BoardUpdated.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared:WaitForChild("LevelConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local BoardController = require(script.Parent.BoardController)

local ShopPanel = {}

local PANEL_WIDTH = 220

local function createButton(parent: Instance, order: number, height: number): TextButton
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, height)
	button.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.Parent = parent
	return button
end

function ShopPanel.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local requestBuyUnit = remotes:WaitForChild(RemoteNames.RequestBuyUnit)
	local requestSellUnit = remotes:WaitForChild(RemoteNames.RequestSellUnit)
	local requestReroll = remotes:WaitForChild(RemoteNames.RequestReroll)
	local requestBuyXp = remotes:WaitForChild(RemoteNames.RequestBuyXp)

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShopPanel"
	screenGui.ResetOnSpawn = false

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -8, 0.5, 0)
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.new(0, 0, 0)
	panel.BackgroundTransparency = 0.35
	panel.Parent = screenGui

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	local status = Instance.new("TextLabel")
	status.LayoutOrder = 0
	status.Size = UDim2.new(1, 0, 0, 72)
	status.BackgroundTransparency = 1
	status.TextColor3 = Color3.new(1, 1, 1)
	status.Font = Enum.Font.GothamBold
	status.TextSize = 16
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = "Waiting for server..."
	status.Parent = panel

	local shopButtons = {}
	for slot = 1, ShopConfig.slots do
		local button = createButton(panel, slot, 40)
		button.Activated:Connect(function()
			requestBuyUnit:FireServer(slot)
		end)
		shopButtons[slot] = button
	end

	local rerollButton = createButton(panel, 10, 32)
	rerollButton.Text = string.format("Reroll (%d gold)", ShopConfig.rerollCost)
	rerollButton.Activated:Connect(function()
		requestReroll:FireServer()
	end)

	local buyXpButton = createButton(panel, 11, 32)
	buyXpButton.Text = string.format("Buy %d XP (%d gold)", LevelConfig.buyXpAmount, LevelConfig.buyXpCost)
	buyXpButton.Activated:Connect(function()
		requestBuyXp:FireServer()
	end)

	local sellButton = createButton(panel, 12, 32)
	sellButton.Text = "Sell selected unit"
	sellButton.Activated:Connect(function()
		local unitId = BoardController.getSelectedUnitId()
		if unitId then
			requestSellUnit:FireServer(unitId)
		end
	end)

	local view = nil
	local placedCount = 0

	local function refresh()
		if not view then
			return
		end
		local xpText = if view.xpToNextLevel > 0 then string.format("%d/%d", view.xp, view.xpToNextLevel) else "MAX"
		status.Text = string.format(
			"Gold: %d\nLevel %d   XP %s\nBoard: %d/%d units",
			view.gold,
			view.level,
			xpText,
			placedCount,
			view.level
		)
		for slot, button in shopButtons do
			local unitType = view.shop[slot]
			if unitType then
				local unit = UnitConfig[unitType]
				button.Text = string.format("%s  (%d gold)\n%s", unitType, unit.cost, unit.role)
				button.AutoButtonColor = true
				button.BackgroundTransparency = 0
			else
				button.Text = "(bought)"
				button.AutoButtonColor = false
				button.BackgroundTransparency = 0.6
			end
		end
	end

	remotes:WaitForChild(RemoteNames.PlayerStateUpdated).OnClientEvent:Connect(function(newView)
		view = newView
		refresh()
	end)
	BoardController.onUnitsChanged(function(units)
		placedCount = 0
		for _, unit in units do
			if unit.column then
				placedCount += 1
			end
		end
		refresh()
	end)

	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return ShopPanel
