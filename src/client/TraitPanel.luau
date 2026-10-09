-- The trait panel on the left edge: every origin (faction) and class among the units the player has
-- placed on the board (bench units do not count), with its symbol, how many different characters
-- with it are fielded, its name and one pip per breakpoint (TraitConfig; lit when reached). Active
-- traits are drawn bright, partial ones dim. Below them, every active bond (BondConfig: both
-- characters placed) shows both characters' names. Rows are sorted active first, then by count,
-- then origins before classes, then by name. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local TraitConfig = require(Shared:WaitForChild("TraitConfig"))
local TraitIconConfig = require(Shared:WaitForChild("TraitIconConfig"))
local Traits = require(Shared:WaitForChild("Traits"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local BoardController = require(script.Parent.BoardController)
local TraitIcon = require(script.Parent.TraitIcon)
local UI = require(script.Parent.UI)

local TraitPanel = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local ICON = SIZES.traitRow - 6
local PIP = 6
local PIP_GAP = 3
local BREAKPOINT_AREA = 3 * (PIP + PIP_GAP) -- room for up to three pips on each row's right
local INACTIVE_TRANSPARENCY = 0.45

-- The placed characters (bench units and anything that is not a character are left out).
local function placedUnits(units: { any }): { any }
	local placed = {}
	for _, unit in units do
		if unit.column and UnitConfig[unit.unitType] then
			table.insert(placed, unit)
		end
	end
	return placed
end

local function isOrigin(trait: string): boolean
	local entry = TraitIconConfig[trait]
	return entry ~= nil and entry.shape == "circle"
end

local function clearRows(panel: Instance)
	for _, child in panel:GetChildren() do
		if child:IsA("Frame") and (child.Name == "TraitRow" or child.Name == "BondRow") then
			child:Destroy()
		end
	end
end

local function rowFrame(name: string, order: number, height: number): Frame
	local row = Instance.new("Frame")
	row.Name = name
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, height)
	row.BackgroundColor3 = COLORS.panelLight
	row.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row
	return row
end

-- One pip per breakpoint of `trait`, lit up to the count reached.
local function breakpointPips(row: Frame, trait: string, count: number)
	local holder = Instance.new("Frame")
	holder.Name = "Breakpoints"
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -4, 0.5, 0)
	holder.Size = UDim2.fromOffset(BREAKPOINT_AREA, ICON)
	holder.BackgroundTransparency = 1
	holder.Parent = row
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, PIP_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	for index, breakpoint in TraitConfig[trait].breakpoints do
		local pip = Instance.new("Frame")
		pip.LayoutOrder = index
		pip.Size = UDim2.fromOffset(PIP, PIP)
		pip.Rotation = 45
		pip.BorderSizePixel = 0
		pip.BackgroundColor3 = if count >= breakpoint.count then COLORS.gold else COLORS.panel
		pip.Parent = holder
		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.goldDark
		stroke.Thickness = 1
		stroke.Parent = pip
	end
end

function TraitPanel.start()
	local _, root = UI.screen("TraitPanel", 3)
	local panel = UI.panel(root, UDim2.fromOffset(SIZES.traitPanelWidth, 0), false)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Position = UDim2.fromOffset(SIZES.margin, SIZES.topBarHeight + 14)
	UI.padding(panel, 6)
	UI.list(panel, 3)

	local function render(units: { any })
		clearRows(panel)
		local placed = placedUnits(units)
		local states = Traits.summary(placed)
		table.sort(states, function(a, b)
			if a.active ~= b.active then
				return a.active
			elseif a.count ~= b.count then
				return a.count > b.count
			elseif isOrigin(a.name) ~= isOrigin(b.name) then
				return isOrigin(a.name)
			end
			return a.name < b.name
		end)
		local bonds = Traits.bonds(placed)
		panel.Visible = #states > 0

		for order, state in states do
			local trait = state.name
			local row = rowFrame("TraitRow", order, SIZES.traitRow)
			row.BackgroundTransparency = if state.active then 0 else INACTIVE_TRANSPARENCY

			local icon = TraitIcon.new(trait, ICON, row)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 4, 0.5, 0)

			local count = UI.text(
				row,
				tostring(state.count),
				SIZES.text,
				FONTS.number,
				if state.active then COLORS.gold else COLORS.textDim
			)
			count.AnchorPoint = Vector2.new(0, 0.5)
			count.Position = UDim2.new(0, ICON + 8, 0.5, 0)

			local name = UI.text(row, TraitIcon.name(trait), SIZES.textSmall, FONTS.body)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.AnchorPoint = Vector2.new(0, 0.5)
			name.Position = UDim2.new(0, ICON + 26, 0.5, 0)
			name.Size = UDim2.new(1, -(ICON + 30 + BREAKPOINT_AREA), 0, SIZES.textSmall + 4)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			if not state.active then
				name.TextTransparency = INACTIVE_TRANSPARENCY
			end

			breakpointPips(row, trait, state.count)
			row.Parent = panel
		end

		-- Active bonds: both characters' names.
		for index, bond in bonds do
			local row = rowFrame("BondRow", #states + index, SIZES.traitRow)
			local first, second = SkinConfig[bond.units[1]], SkinConfig[bond.units[2]]
			local text =
				string.format("%s + %s", first and first.name or bond.units[1], second and second.name or bond.units[2])
			local label = UI.text(row, text, SIZES.textSmall, FONTS.body, COLORS.gold)
			label.AutomaticSize = Enum.AutomaticSize.None
			label.AnchorPoint = Vector2.new(0, 0.5)
			label.Position = UDim2.new(0, 6, 0.5, 0)
			label.Size = UDim2.new(1, -12, 0, SIZES.textSmall + 4)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextTruncate = Enum.TextTruncate.AtEnd
			row.Parent = panel
		end
	end

	BoardController.onUnitsChanged(render)
end

return TraitPanel
