-- The shop along the bottom of the screen, with the player's stats above it:
--   * stats strip: level badge with an XP progress bar, gold (a coin and a number that counts up
--     and pops when it rises), and the win or loss streak
--   * five shop cards: name, price, cost color and trait symbols (a trait's name shows on hover
--     or when its symbol is tapped; tapping the rest of the card buys it)
--   * Buy XP and Reroll buttons showing their price
--   * while a unit is dragged, the shop turns into a sell zone showing the unit's sell value
--     (BoardController.setSellZone)
-- Buttons only send requests; everything shown comes from the server's PlayerStateUpdated and
-- BoardUpdated. Buying, rerolling and buying XP are open whenever the server takes requests
-- (Preparation only, until the shop opens during combat).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared:WaitForChild("LevelConfig"))
local Phase = require(Shared:WaitForChild("Phase"))
local PlayerState = require(Shared:WaitForChild("PlayerState"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local BoardController = require(script.Parent.BoardController)
local TraitIcon = require(script.Parent.TraitIcon)
local UI = require(script.Parent.UI)

local ShopPanel = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local TRAIT_ICON = 22
local TRAIT_NAME_SECONDS = 1.5

-- Phases in which the server accepts shop requests.
local SHOP_PHASES = { [Phase.Preparation] = true }

type Card = {
	button: TextButton,
	band: Frame,
	stroke: UIStroke,
	name: TextLabel,
	price: Frame,
	priceLabel: TextLabel,
	traits: Frame,
	shown: string | false | nil,
}

-- A small label above a trait symbol with the trait's name.
local function traitTip(parent: Instance): TextLabel
	local tip = UI.text(parent, "", SIZES.textSmall, FONTS.body)
	tip.AnchorPoint = Vector2.new(0.5, 1)
	tip.Position = UDim2.new(0.5, 0, 0, -4)
	tip.BackgroundColor3 = COLORS.panel
	tip.BackgroundTransparency = 0
	tip.ZIndex = 20
	tip.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = tip
	UI.padding(tip, 3)
	return tip
end

local function createCard(parent: Instance, order: number, onBuy: () -> ()): Card
	local button = UI.button(parent, COLORS.panelLight, UDim2.fromOffset(SIZES.shopCard.X, SIZES.shopCard.Y))
	button.LayoutOrder = order
	local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = 3

	-- The cost color: a band across the top and the card's outline.
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 8)
	band.BorderSizePixel = 0
	local bandCorner = Instance.new("UICorner")
	bandCorner.CornerRadius = UDim.new(0, UITheme.buttonCorner)
	bandCorner.Parent = band
	band.Parent = button

	local name = UI.text(button, "", SIZES.text, FONTS.body)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Position = UDim2.fromOffset(6, 14)
	name.Size = UDim2.new(1, -12, 0, 36)
	name.TextWrapped = true
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextYAlignment = Enum.TextYAlignment.Top
	local nameSize = Instance.new("UITextSizeConstraint")
	nameSize.MaxTextSize = SIZES.text
	nameSize.MinTextSize = 9
	nameSize.Parent = name

	local traits = UI.row(button, 3)
	traits.AnchorPoint = Vector2.new(0, 1)
	traits.Position = UDim2.new(0, 6, 1, -6)

	local price, priceLabel = UI.price(button, 0, 16)
	price.AnchorPoint = Vector2.new(1, 1)
	price.Position = UDim2.new(1, -6, 1, -6)

	button.Activated:Connect(onBuy)
	return {
		button = button,
		band = band,
		stroke = stroke,
		name = name,
		price = price,
		priceLabel = priceLabel,
		traits = traits,
		shown = nil,
	}
end

-- Trait symbols on a card. Each is its own button, so tapping it shows the trait's name instead
-- of buying; hovering shows it too.
local function fillTraits(card: Card, unitType: string)
	for _, child in card.traits:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for order, traitId in TraitIcon.traitsOf(UnitConfig[unitType]) do
		local holder = Instance.new("TextButton")
		holder.LayoutOrder = order
		holder.Text = ""
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromOffset(TRAIT_ICON, TRAIT_ICON)
		TraitIcon.new(traitId, TRAIT_ICON, holder)
		local tip = traitTip(holder)
		tip.Text = TraitIcon.name(traitId)
		local shownAt = 0
		local function show()
			shownAt = os.clock()
			tip.Visible = true
		end
		holder.MouseEnter:Connect(show)
		holder.MouseLeave:Connect(function()
			tip.Visible = false
		end)
		holder.Activated:Connect(function()
			show()
			local at = shownAt
			task.delay(TRAIT_NAME_SECONDS, function()
				if shownAt == at then
					tip.Visible = false
				end
			end)
		end)
		holder.Parent = card.traits
	end
end

-- An action button with a big label and its price under it.
local function actionButton(parent: Instance, order: number, color: Color3, label: string, cost: number): TextButton
	local button = UI.button(parent, color, UDim2.fromOffset(SIZES.shopButton.X, SIZES.shopButton.Y))
	button.LayoutOrder = order
	local column = Instance.new("Frame")
	column.BackgroundTransparency = 1
	column.Size = UDim2.fromScale(1, 1)
	UI.list(column, 4, Enum.HorizontalAlignment.Center).VerticalAlignment = Enum.VerticalAlignment.Center
	UI.text(column, label, SIZES.textLarge, FONTS.display).LayoutOrder = 1
	local price = UI.price(column, cost, 18)
	price.LayoutOrder = 2
	column.Parent = button
	return button
end

function ShopPanel.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local requestBuyUnit = remotes:WaitForChild(RemoteNames.RequestBuyUnit)
	local requestReroll = remotes:WaitForChild(RemoteNames.RequestReroll)
	local requestBuyXp = remotes:WaitForChild(RemoteNames.RequestBuyXp)

	local function shopOpen(): boolean
		return SHOP_PHASES[matchState:GetAttribute("Phase")] == true
	end

	local _, root = UI.screen("ShopPanel", 4)
	local panel = UI.panel(root, UDim2.fromOffset(0, 0))
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -6)
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.XY
	UI.padding(content, 8)
	UI.list(content, 6, Enum.HorizontalAlignment.Center)
	content.Parent = panel

	-- Stats strip: level and XP, gold, streak.
	local strip = UI.row(content, 18)
	strip.LayoutOrder = 1

	local levelRow = UI.row(strip, 6)
	levelRow.LayoutOrder = 1
	local levelBadge = Instance.new("Frame")
	levelBadge.Size = UDim2.fromOffset(46, SIZES.shopStrip)
	levelBadge.BackgroundColor3 = COLORS.levelUp
	levelBadge.BorderSizePixel = 0
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 8)
	badgeCorner.Parent = levelBadge
	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = COLORS.outline
	badgeStroke.Thickness = 2
	badgeStroke.Parent = levelBadge
	local levelLabel = UI.text(levelBadge, "", SIZES.textLarge, FONTS.display)
	levelLabel.AutomaticSize = Enum.AutomaticSize.None
	levelLabel.Size = UDim2.fromScale(1, 1)
	levelBadge.Parent = levelRow
	local xpColumn = Instance.new("Frame")
	xpColumn.LayoutOrder = 2
	xpColumn.BackgroundTransparency = 1
	xpColumn.Size = UDim2.fromOffset(120, SIZES.shopStrip)
	local xpBar = UI.bar(xpColumn, UDim2.new(1, 0, 0, 12), COLORS.xp)
	xpBar.frame.AnchorPoint = Vector2.new(0, 1)
	xpBar.frame.Position = UDim2.fromScale(0, 1)
	local xpLabel = UI.text(xpColumn, "", SIZES.textSmall, FONTS.number, COLORS.textDim)
	xpColumn.Parent = levelRow

	local goldRow = UI.row(strip, 6)
	goldRow.LayoutOrder = 2
	UI.coin(goldRow, 28).LayoutOrder = 1
	local goldLabel = UI.text(goldRow, "0", SIZES.textHuge - 8, FONTS.number, COLORS.gold)
	goldLabel.LayoutOrder = 2

	local streakRow = UI.row(strip, 4)
	streakRow.LayoutOrder = 3
	local streakIcon = UI.glyph(streakRow, UITheme.icons.winStreak, SIZES.textLarge)
	streakIcon.LayoutOrder = 1
	local streakLabel = UI.text(streakRow, "", SIZES.textLarge, FONTS.number)
	streakLabel.LayoutOrder = 2

	-- Buy XP, the cards, Reroll.
	local actions = UI.row(content, 8)
	actions.LayoutOrder = 2
	local xpButton = actionButton(actions, 1, COLORS.levelUp, "XP", LevelConfig.buyXpCost)
	local cardRow = UI.row(actions, 8)
	cardRow.LayoutOrder = 2
	local rerollButton = actionButton(actions, 3, COLORS.reroll, "REROLL", ShopConfig.rerollCost)

	local view = nil
	local cards: { Card } = {}
	for slot = 1, ShopConfig.slots do
		cards[slot] = createCard(cardRow, slot, function()
			if shopOpen() and view and view.shop[slot] then
				requestBuyUnit:FireServer(slot)
			end
		end)
	end
	xpButton.Activated:Connect(function()
		if shopOpen() and UI.isEnabled(xpButton) then
			requestBuyXp:FireServer()
		end
	end)
	rerollButton.Activated:Connect(function()
		if shopOpen() and UI.isEnabled(rerollButton) then
			requestReroll:FireServer()
		end
	end)

	-- Sell zone: while a unit is dragged, a red overlay over the shop shows what it sells for.
	local sellOverlay = Instance.new("Frame")
	sellOverlay.Size = UDim2.fromScale(1, 1)
	sellOverlay.BackgroundColor3 = COLORS.sell
	sellOverlay.BackgroundTransparency = 0.25
	sellOverlay.ZIndex = 30
	sellOverlay.Visible = false
	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, UITheme.corner)
	overlayCorner.Parent = sellOverlay
	local overlayContent = UI.row(sellOverlay, 10)
	overlayContent.AnchorPoint = Vector2.new(0.5, 0.5)
	overlayContent.Position = UDim2.fromScale(0.5, 0.5)
	local sellLabel = UI.text(overlayContent, "SELL", SIZES.textHuge, FONTS.display)
	sellLabel.LayoutOrder = 1
	sellLabel.ZIndex = 31
	local sellPrice, sellPriceLabel = UI.price(overlayContent, 0, 30)
	sellPrice.LayoutOrder = 2
	for _, child in sellPrice:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex = 31
		end
	end
	sellPriceLabel.ZIndex = 31
	sellOverlay.Parent = panel
	BoardController.setSellZone(panel)

	local unitsById = {}
	BoardController.onUnitsChanged(function(units)
		table.clear(unitsById)
		for _, unit in units do
			unitsById[unit.id] = unit
		end
	end)
	BoardController.onDragChanged(function(unitId, overZone)
		local unit = if unitId then unitsById[unitId] else nil
		sellOverlay.Visible = unit ~= nil
		if unit then
			sellPriceLabel.Text = tostring(PlayerState.sellValue(unit.unitType, unit.starLevel))
			sellOverlay.BackgroundTransparency = if overZone then 0.05 else 0.35
			if overZone then
				UI.pop(overlayContent, 1.1)
			end
		end
	end)

	local shownLevel = nil
	local function refresh()
		local open = shopOpen()
		if not view then
			return
		end
		UI.setEnabled(xpButton, open and view.xpToNextLevel > 0 and view.gold >= LevelConfig.buyXpCost)
		UI.setEnabled(rerollButton, open and view.gold >= ShopConfig.rerollCost)

		levelLabel.Text = tostring(view.level)
		if shownLevel and view.level > shownLevel then
			UI.pop(levelBadge, 1.4)
		end
		shownLevel = view.level
		if view.xpToNextLevel > 0 then
			xpLabel.Text = string.format("%d/%d", view.xp, view.xpToNextLevel)
			UI.setBar(xpBar, view.xp / view.xpToNextLevel, true)
		else
			xpLabel.Text = "MAX"
			UI.setBar(xpBar, 1, true)
		end

		local previousGold = goldLabel:GetAttribute("Value")
		UI.countTo(goldLabel, view.gold)
		if type(previousGold) == "number" and view.gold > previousGold then
			UI.floatUp(goldLabel, "+" .. (view.gold - previousGold), COLORS.gold)
		end

		local streak = view.streak or 0
		streakRow.Visible = math.abs(streak) >= 2
		streakIcon.Text = if streak > 0 then UITheme.icons.winStreak else UITheme.icons.lossStreak
		streakLabel.Text = tostring(math.abs(streak))
		streakLabel.TextColor3 = if streak > 0 then COLORS.win else COLORS.xp

		for slot, card in cards do
			local unitType = view.shop[slot]
			if unitType ~= card.shown then
				card.shown = unitType
				if unitType then
					local unit = UnitConfig[unitType]
					local costColor = RenderConfig.costColors[unit.cost]
					card.name.Text = SkinConfig[unitType].name
					card.band.BackgroundColor3 = costColor
					card.band.Visible = true
					card.stroke.Color = costColor
					card.priceLabel.Text = tostring(unit.cost)
					card.price.Visible = true
					fillTraits(card, unitType)
					card.traits.Visible = true
					UI.pop(card.button, 1.08)
				else
					-- Bought, or nothing left in the shared pool to show.
					card.name.Text = ""
					card.band.Visible = false
					card.stroke.Color = COLORS.outline
					card.price.Visible = false
					card.traits.Visible = false
				end
			end
			-- A card fades while it cannot be bought now; it keeps its colors so it stays readable.
			local buyable = open and unitType and view.gold >= UnitConfig[unitType].cost
			local fade = if buyable then 0 else 0.45
			card.button.BackgroundColor3 = if unitType then COLORS.panelLight else COLORS.panel
			card.button.BackgroundTransparency = if unitType then fade * 0.6 else 0.6
			card.name.TextTransparency = fade
			card.priceLabel.TextTransparency = fade
		end
	end

	remotes:WaitForChild(RemoteNames.PlayerStateUpdated).OnClientEvent:Connect(function(newView)
		view = newView
		refresh()
	end)
	matchState:GetAttributeChangedSignal("Phase"):Connect(refresh)
	refresh()
end

return ShopPanel
