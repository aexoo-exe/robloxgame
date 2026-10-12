-- The info card for the hub's exhibits: walking up to a roster statue (a gallery plinth) shows the
-- unit's name, cost, faction and classes, and its ability with a description built from its data
-- (AbilityText); walking up to an item pedestal in the shrine shows the item's pictogram, name and
-- effect. The nearest exhibit within reach (HubConfig gallery/shrine infoDistance) wins. Only in
-- the hub (HubExhibits.setShown). Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HubConfig = require(Shared:WaitForChild("HubConfig"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local TraitIconConfig = require(Shared:WaitForChild("TraitIconConfig"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local AbilityText = require(script.Parent.AbilityText)
local ItemIcon = require(script.Parent.ItemIcon)
local UI = require(script.Parent.UI)

local HubExhibits = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local WIDTH = 440
local REFRESH_SECONDS = 0.15

local root: Frame? = nil
local shown = false

function HubExhibits.setShown(value: boolean)
	shown = value
	if root then
		root.Visible = value
	end
end

local function traitName(traitId: string): string
	local trait = TraitIconConfig[traitId]
	return if trait then trait.name else traitId
end

-- Wrapped text filling the card's width.
local function paragraph(parent: Instance, size: number, color: Color3, order: number): TextLabel
	local label = UI.text(parent, "", size, FONTS.body, color)
	label.LayoutOrder = order
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.fromOffset(WIDTH, 0)
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	return label
end

function HubExhibits.start()
	local player = Players.LocalPlayer
	local _, screenRoot = UI.screen("HubExhibits", 6, true)
	root = screenRoot
	screenRoot.Visible = shown

	local card = UI.panel(screenRoot, UDim2.fromOffset(0, 0), false)
	card.AutomaticSize = Enum.AutomaticSize.XY
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -24)
	card.Visible = false
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.XY
	UI.padding(content, 12)
	UI.list(content, 6)
	content.Parent = card

	local header = UI.row(content, 10)
	header.LayoutOrder = 1
	local iconSlot = Instance.new("Frame")
	iconSlot.LayoutOrder = 1
	iconSlot.BackgroundTransparency = 1
	iconSlot.Size = UDim2.fromOffset(40, 40)
	iconSlot.Parent = header
	local title = UI.text(header, "", SIZES.textLarge + 2, FONTS.display, COLORS.gold)
	title.LayoutOrder = 2
	local subtitle = paragraph(content, SIZES.text, COLORS.textDim, 2)
	local heading = paragraph(content, SIZES.text, COLORS.text, 3)
	heading.Font = FONTS.display
	local body = paragraph(content, SIZES.text - 1, COLORS.text, 4)

	local shownKey: string? = nil

	local function showUnit(unitType: string)
		local unit = UnitConfig[unitType]
		local skin = SkinConfig[unitType]
		for _, child in iconSlot:GetChildren() do
			child:Destroy()
		end
		iconSlot.Visible = false
		title.Text = skin.name
		local classes = {}
		for _, class in unit.classes do
			table.insert(classes, traitName(class))
		end
		subtitle.Text = string.format("%d-cost  ·  %s  ·  %s", unit.cost, traitName(unit.origin), table.concat(classes, ", "))
		subtitle.TextColor3 = RenderConfig.costColors[unit.cost] or COLORS.textDim
		heading.Text = string.format("%s  (%d mana)", skin.ability, unit.maxMana or 0)
		heading.Visible = true
		body.Text = AbilityText.of(unitType)
	end

	local function showItem(itemId: string)
		for _, child in iconSlot:GetChildren() do
			child:Destroy()
		end
		local icon = ItemIcon.new(itemId, 40, iconSlot)
		icon.Size = UDim2.fromScale(1, 1)
		iconSlot.Visible = true
		title.Text = ItemIcon.name(itemId)
		local category = ItemConfig.items[itemId].category
		subtitle.Text = string.upper(string.sub(category, 1, 1)) .. string.lower(string.sub(category, 2)) .. " item"
		subtitle.TextColor3 = ItemIcon.color(itemId)
		heading.Visible = false
		body.Text = ItemIcon.text(itemId)
	end

	-- The nearest exhibit in `folder` within `reach` studs (flat distance) of `position`.
	local function nearest(folder: Instance?, attribute: string, position: Vector3, reach: number): (string?, number)
		local best, bestDistance = nil, reach
		if not folder then
			return nil, math.huge
		end
		for _, exhibit in folder:GetChildren() do
			if exhibit:IsA("BasePart") then
				local offset = exhibit.Position - position
				local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
				local value = exhibit:GetAttribute(attribute)
				if distance <= bestDistance and type(value) == "string" and math.abs(offset.Y) < 12 then
					best, bestDistance = value, distance
				end
			end
		end
		return best, if best then bestDistance else math.huge
	end

	local function refresh()
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hub = workspace:FindFirstChild("Hub")
		local key: string? = nil
		if shown and rootPart and hub then
			local position = rootPart.Position
			local unitType, unitDistance = nearest(hub:FindFirstChild("Gallery"), "UnitType", position, HubConfig.gallery.infoDistance)
			local itemId, itemDistance = nearest(hub:FindFirstChild("Shrine"), "ItemId", position, HubConfig.shrine.infoDistance)
			if unitType and unitDistance <= itemDistance then
				key = "unit:" .. unitType
			elseif itemId then
				key = "item:" .. itemId
			end
		end
		if key == shownKey then
			return
		end
		shownKey = key
		card.Visible = key ~= nil
		if not key then
			return
		end
		local kind, id = string.match(key, "^(%a+):(.+)$")
		if kind == "unit" then
			showUnit(id :: string)
		else
			showItem(id :: string)
		end
		UI.pop(card, 1.05)
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return HubExhibits
