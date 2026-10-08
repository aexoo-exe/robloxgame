-- The trait panel on the left edge: every origin and class among the units the player has placed on
-- the board (bench units do not count), with its symbol, its name and how many different
-- characters with it are fielded. Trait bonuses do not exist yet (TraitConfig is empty), so rows
-- show counts only; each row keeps an empty area on its right for breakpoints later. Rows are
-- sorted by count, then origins before classes, then by name. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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
local BREAKPOINT_AREA = 30 -- reserved on each row's right for breakpoint pips

-- Different characters per trait among the placed units: trait -> count.
local function boardCounts(units: { any }): { [string]: number }
	local seen = {}
	local counts = {}
	for _, unit in units do
		if unit.column and not seen[unit.unitType] and UnitConfig[unit.unitType] then
			seen[unit.unitType] = true
			for _, trait in Traits.traitsOf(unit.unitType) do
				counts[trait] = (counts[trait] or 0) + 1
			end
		end
	end
	return counts
end

local function isOrigin(trait: string): boolean
	local entry = TraitIconConfig[trait]
	return entry ~= nil and entry.shape == "circle"
end

function TraitPanel.start()
	local _, root = UI.screen("TraitPanel", 3)
	local panel = UI.panel(root, UDim2.fromOffset(SIZES.traitPanelWidth, 0), false)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Position = UDim2.fromOffset(SIZES.margin, SIZES.topBarHeight + 14)
	UI.padding(panel, 6)
	UI.list(panel, 3)

	local function render(units: { any })
		for _, child in panel:GetChildren() do
			if child:IsA("Frame") and child.Name == "TraitRow" then
				child:Destroy()
			end
		end
		local counts = boardCounts(units)
		local traits = {}
		for trait in counts do
			table.insert(traits, trait)
		end
		table.sort(traits, function(a, b)
			if counts[a] ~= counts[b] then
				return counts[a] > counts[b]
			elseif isOrigin(a) ~= isOrigin(b) then
				return isOrigin(a)
			end
			return a < b
		end)
		panel.Visible = #traits > 0

		for order, trait in traits do
			local row = Instance.new("Frame")
			row.Name = "TraitRow"
			row.LayoutOrder = order
			row.Size = UDim2.new(1, 0, 0, SIZES.traitRow)
			row.BackgroundColor3 = COLORS.panelLight
			row.BorderSizePixel = 0
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = row

			local icon = TraitIcon.new(trait, ICON, row)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 4, 0.5, 0)

			local count = UI.text(row, tostring(counts[trait]), SIZES.text, FONTS.number, COLORS.gold)
			count.AnchorPoint = Vector2.new(0, 0.5)
			count.Position = UDim2.new(0, ICON + 8, 0.5, 0)

			local name = UI.text(row, TraitIcon.name(trait), SIZES.textSmall, FONTS.body)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.AnchorPoint = Vector2.new(0, 0.5)
			name.Position = UDim2.new(0, ICON + 26, 0.5, 0)
			name.Size = UDim2.new(1, -(ICON + 30 + BREAKPOINT_AREA), 0, SIZES.textSmall + 4)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd

			-- Room for breakpoint pips once traits have bonuses.
			local breakpoints = Instance.new("Frame")
			breakpoints.Name = "Breakpoints"
			breakpoints.AnchorPoint = Vector2.new(1, 0.5)
			breakpoints.Position = UDim2.new(1, -4, 0.5, 0)
			breakpoints.Size = UDim2.fromOffset(BREAKPOINT_AREA, ICON)
			breakpoints.BackgroundTransparency = 1
			breakpoints.Parent = row

			row.Parent = panel
		end
	end

	BoardController.onUnitsChanged(render)
end

return TraitPanel
