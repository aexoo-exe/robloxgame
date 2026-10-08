-- The unit info panel, on the right edge (over the player list while open): opens when a unit is
-- selected or tapped (BoardController.onInspect) and shows its name, cost, star level, traits with
-- names, combat stats at its star level (two columns of icon and number), its ability and three
-- item slots (reserved: items do not exist yet). For the player's own units it has a Sell button
-- showing the sell value. It closes when the unit is deselected, when you tap elsewhere, or with
-- its close button. Presentation only.
--
-- There is no ability description text in the game data, so the ability shows its display name
-- (SkinConfig) and mana cost only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local Phase = require(Shared:WaitForChild("Phase"))
local PlayerState = require(Shared:WaitForChild("PlayerState"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local StarConfig = require(Shared:WaitForChild("StarConfig"))
local StarLevel = require(Shared:WaitForChild("StarLevel"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local BoardController = require(script.Parent.BoardController)
local TraitIcon = require(script.Parent.TraitIcon)
local UI = require(script.Parent.UI)

local UnitInfoPanel = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local ICONS = UITheme.icons
local ITEM_SLOTS = 3
local ITEM_SIZE = 34
local CLOSE_SIZE = 30
local STAT_ROW = 20 -- height of a stat cell
local STAT_GAP = 3

-- Whether the inspected unit can be sold now: any of the player's units during Preparation; only
-- bench units during Combat and Results, while the board is locked.
local function canSell(info: BoardController.Inspected?, phase: string?): boolean
	if not info or not info.unitId then
		return false
	end
	if phase == Phase.Preparation then
		return true
	end
	return (phase == Phase.Combat or phase == Phase.Results) and info.onBench == true
end

-- Stats shown in the grid: icon, and the value for a unit type at a star level.
local STATS = {
	{
		icon = ICONS.health,
		value = function(unit, star)
			return tostring(StarLevel.scaleHealth(unit.health, star))
		end,
	},
	{
		icon = ICONS.attack,
		value = function(unit, star)
			return tostring(math.round(unit.attackDamage * StarConfig.attackDamageMultiplier[star]))
		end,
	},
	{
		icon = ICONS.abilityPower,
		value = function(unit)
			return tostring(unit.abilityPower or CombatConfig.baseAbilityPower)
		end,
	},
	{
		icon = ICONS.attackSpeed,
		value = function(unit)
			return string.format("%.2f", unit.attacksPerSecond)
		end,
	},
	{
		icon = ICONS.armor,
		value = function(unit)
			return tostring(unit.armor)
		end,
	},
	{
		icon = ICONS.magicResist,
		value = function(unit)
			return tostring(unit.magicResist)
		end,
	},
	{
		icon = ICONS.range,
		value = function(unit)
			return tostring(unit.range)
		end,
	},
	{
		icon = ICONS.mana,
		value = function(unit)
			return string.format("%d/%d", unit.startingMana, unit.maxMana or 0)
		end,
	},
}

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function UnitInfoPanel.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local requestSellUnit = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(RemoteNames.RequestSellUnit)

	local _, root = UI.screen("UnitInfoPanel", 6)
	-- On the right edge, over the player list while open.
	local panel = UI.panel(root, UDim2.fromOffset(SIZES.infoPanelWidth, 0), false)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -SIZES.margin, 0, SIZES.topBarHeight + 14)
	panel.Visible = false

	-- The cost color, as a band behind the header.
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 6)
	band.BorderSizePixel = 0
	local bandCorner = Instance.new("UICorner")
	bandCorner.CornerRadius = UDim.new(0, UITheme.corner)
	bandCorner.Parent = band
	band.Parent = panel

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	UI.padding(content, 8)
	UI.list(content, 5)
	content.Parent = panel

	local close = UI.button(panel, COLORS.sell, UDim2.fromOffset(CLOSE_SIZE, CLOSE_SIZE))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -4, 0, 4)
	local closeGlyph = UI.glyph(close, ICONS.close, SIZES.textSmall + 1)
	closeGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
	closeGlyph.Position = UDim2.fromScale(0.5, 0.5)
	close.Activated:Connect(function()
		panel.Visible = false
		BoardController.clearInspect()
	end)

	-- Header: name, then stars and price.
	local name = UI.text(content, "", SIZES.text + 4, FONTS.display)
	name.LayoutOrder = 1
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Size = UDim2.new(1, -(CLOSE_SIZE + 4), 0, SIZES.text + 6)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextScaled = true
	local subtitle = UI.row(content, 10)
	subtitle.LayoutOrder = 2
	local stars = UI.text(subtitle, "", SIZES.text, FONTS.body)
	stars.LayoutOrder = 1
	local price, priceLabel = UI.price(subtitle, 0, 14)
	price.LayoutOrder = 2

	local traits = Instance.new("Frame")
	traits.LayoutOrder = 3
	traits.BackgroundTransparency = 1
	traits.Size = UDim2.fromScale(1, 0)
	traits.AutomaticSize = Enum.AutomaticSize.Y
	local traitsLayout = UI.list(traits, 4)
	traitsLayout.FillDirection = Enum.FillDirection.Horizontal
	traitsLayout.Wraps = true
	traits.Parent = content

	-- Stats: two columns of icon and number, sized to fit their rows exactly.
	local rows = math.ceil(#STATS / 2)
	local grid = Instance.new("Frame")
	grid.LayoutOrder = 4
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, rows * (STAT_ROW + STAT_GAP) - STAT_GAP)
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -3, 0, STAT_ROW)
	gridLayout.CellPadding = UDim2.fromOffset(6, STAT_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	grid.Parent = content
	local statLabels = {}
	for order, stat in STATS do
		local cell = UI.row(grid, 4, UDim2.fromScale(0, 0))
		cell.LayoutOrder = order
		UI.glyph(cell, stat.icon, SIZES.textSmall + 1).LayoutOrder = 1
		local value = UI.text(cell, "", SIZES.text, FONTS.number)
		value.LayoutOrder = 2
		statLabels[order] = value
	end

	-- Ability: its name and mana cost.
	local ability = Instance.new("Frame")
	ability.LayoutOrder = 5
	ability.Size = UDim2.new(1, 0, 0, 28)
	ability.BackgroundColor3 = COLORS.panelLight
	ability.BorderSizePixel = 0
	local abilityCorner = Instance.new("UICorner")
	abilityCorner.CornerRadius = UDim.new(0, 8)
	abilityCorner.Parent = ability
	local abilityStroke = Instance.new("UIStroke")
	abilityStroke.Color = COLORS.goldDark
	abilityStroke.Thickness = 2
	abilityStroke.Parent = ability
	local abilityName = UI.text(ability, "", SIZES.textSmall + 1, FONTS.body, COLORS.gold)
	abilityName.AutomaticSize = Enum.AutomaticSize.None
	abilityName.AnchorPoint = Vector2.new(0, 0.5)
	abilityName.Position = UDim2.new(0, 8, 0.5, 0)
	abilityName.Size = UDim2.new(1, -60, 0, SIZES.textSmall + 4)
	abilityName.TextXAlignment = Enum.TextXAlignment.Left
	abilityName.TextTruncate = Enum.TextTruncate.AtEnd
	local abilityMana = UI.row(ability, 2)
	abilityMana.AnchorPoint = Vector2.new(1, 0.5)
	abilityMana.Position = UDim2.new(1, -8, 0.5, 0)
	UI.glyph(abilityMana, ICONS.mana, SIZES.textSmall).LayoutOrder = 1
	local abilityManaLabel = UI.text(abilityMana, "", SIZES.textSmall + 1, FONTS.number, COLORS.xp)
	abilityManaLabel.LayoutOrder = 2
	ability.Parent = content

	-- Item slots: reserved for items, empty for now.
	local items = UI.row(content, 6)
	items.LayoutOrder = 6
	for slot = 1, ITEM_SLOTS do
		local itemSlot = Instance.new("Frame")
		itemSlot.Name = "ItemSlot" .. slot
		itemSlot.LayoutOrder = slot
		itemSlot.Size = UDim2.fromOffset(ITEM_SIZE, ITEM_SIZE)
		itemSlot.BackgroundColor3 = COLORS.outline
		itemSlot.BackgroundTransparency = 0.3
		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 8)
		slotCorner.Parent = itemSlot
		local slotStroke = Instance.new("UIStroke")
		slotStroke.Color = COLORS.textDim
		slotStroke.Transparency = 0.5
		slotStroke.Thickness = 2
		slotStroke.Parent = itemSlot
		itemSlot.Parent = items
	end

	-- Sell (the player's own units).
	local sell = UI.button(content, COLORS.sell, UDim2.new(1, 0, 0, 36))
	sell.LayoutOrder = 7
	local sellRow = UI.row(sell, 8)
	sellRow.AnchorPoint = Vector2.new(0.5, 0.5)
	sellRow.Position = UDim2.fromScale(0.5, 0.5)
	UI.text(sellRow, "SELL", SIZES.text + 2, FONTS.display).LayoutOrder = 1
	local sellPrice, sellPriceLabel = UI.price(sellRow, 0, 15)
	sellPrice.LayoutOrder = 2

	local current: BoardController.Inspected? = nil
	sell.Activated:Connect(function()
		if current and canSell(current, matchState:GetAttribute("Phase")) then
			requestSellUnit:FireServer(current.unitId)
		end
	end)

	local function show(info: BoardController.Inspected?)
		current = info
		local unit = if info then UnitConfig[info.unitType] else nil
		if not info or not unit then
			panel.Visible = false
			return
		end
		local star = math.clamp(info.starLevel, 1, StarConfig.maxStarLevel)
		local costColor = RenderConfig.costColors[unit.cost]
		band.BackgroundColor3 = costColor
		panel:FindFirstChildOfClass("UIStroke").Color = costColor
		name.Text = SkinConfig[info.unitType].name
		stars.Text = string.rep(ICONS.star, star)
		stars.TextColor3 = RenderConfig.overhead.starColors[star]
		priceLabel.Text = tostring(unit.cost)

		clear(traits)
		for order, traitId in TraitIcon.traitsOf(unit) do
			TraitIcon.labeled(traitId, 18, SIZES.textSmall, traits).LayoutOrder = order
		end
		for order, stat in STATS do
			statLabels[order].Text = stat.value(unit, star)
		end
		abilityName.Text = SkinConfig[info.unitType].ability
		abilityManaLabel.Text = tostring(unit.maxMana or 0)

		sell.Visible = info.unitId ~= nil
		sellPriceLabel.Text = tostring(PlayerState.sellValue(info.unitType, star))
		UI.setEnabled(sell, canSell(info, matchState:GetAttribute("Phase")))

		if not panel.Visible then
			panel.Visible = true
			UI.pop(panel, 1.06)
		end
	end

	BoardController.onInspect(show)
	matchState:GetAttributeChangedSignal("Phase"):Connect(function()
		show(current)
	end)
end

return UnitInfoPanel
