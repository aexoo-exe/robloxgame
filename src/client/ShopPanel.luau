-- Placeholder shop and economy panel on the right edge of the screen: gold, level, XP progress,
-- units on the board against the cap, five shop buttons (name, cost, origin and classes, with an
-- origin color stripe), reroll, buy XP and sell. Buttons only send
-- requests and are disabled outside Preparation; everything shown comes from the server's
-- PlayerStateUpdated and BoardUpdated.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared:WaitForChild("LevelConfig"))
local Phase = require(Shared:WaitForChild("Phase"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
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

-- Shows a button as usable or not. Disabled buttons also ignore clicks (see the handlers).
local function setUsable(button: TextButton, usable: boolean)
	button.AutoButtonColor = usable
	button.BackgroundTransparency = if usable then 0 else 0.6
	button.TextTransparency = if usable then 0 else 0.4
end

function ShopPanel.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local requestBuyUnit = remotes:WaitForChild(RemoteNames.RequestBuyUnit)
	local requestSellUnit = remotes:WaitForChild(RemoteNames.RequestSellUnit)
	local requestReroll = remotes:WaitForChild(RemoteNames.RequestReroll)
	local requestBuyXp = remotes:WaitForChild(RemoteNames.RequestBuyXp)

	local function isPreparation(): boolean
		return matchState:GetAttribute("Phase") == Phase.Preparation
	end

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

	local view = nil
	local placedCount = 0

	local shopButtons = {}
	local originStripes = {}
	for slot = 1, ShopConfig.slots do
		local button = createButton(panel, slot, 44)
		button.RichText = true
		-- A stripe in the character's origin color, matching its unit color on the board.
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 6, 1, 0)
		stripe.BorderSizePixel = 0
		stripe.Visible = false
		stripe.Parent = button
		originStripes[slot] = stripe
		button.Activated:Connect(function()
			if isPreparation() and view and view.shop[slot] then
				requestBuyUnit:FireServer(slot)
			end
		end)
		shopButtons[slot] = button
	end

	local rerollButton = createButton(panel, 10, 32)
	rerollButton.Text = string.format("Reroll (%d gold)", ShopConfig.rerollCost)
	rerollButton.Activated:Connect(function()
		if isPreparation() then
			requestReroll:FireServer()
		end
	end)

	local buyXpButton = createButton(panel, 11, 32)
	buyXpButton.Text = string.format("Buy %d XP (%d gold)", LevelConfig.buyXpAmount, LevelConfig.buyXpCost)
	buyXpButton.Activated:Connect(function()
		if isPreparation() then
			requestBuyXp:FireServer()
		end
	end)

	local sellButton = createButton(panel, 12, 32)
	sellButton.Text = "Sell selected unit"
	sellButton.Activated:Connect(function()
		local unitId = BoardController.getSelectedUnitId()
		if isPreparation() and unitId then
			requestSellUnit:FireServer(unitId)
		end
	end)

	local function refresh()
		local preparation = isPreparation()
		setUsable(rerollButton, preparation)
		setUsable(buyXpButton, preparation)
		setUsable(sellButton, preparation)
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
			local stripe = originStripes[slot]
			if unitType then
				local unit = UnitConfig[unitType]
				button.Text = string.format(
					'%s  (%d gold)\n<font size="12">%s · %s</font>',
					SkinConfig[unitType].name,
					unit.cost,
					unit.origin,
					table.concat(unit.classes, " / ")
				)
				stripe.BackgroundColor3 = RenderConfig.originColors[unit.origin]
				stripe.Visible = true
			else
				-- Bought, or nothing left in the shared pool to show.
				button.Text = "(empty)"
				stripe.Visible = false
			end
			setUsable(button, preparation and unitType ~= false)
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
	matchState:GetAttributeChangedSignal("Phase"):Connect(refresh)

	refresh()
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return ShopPanel
