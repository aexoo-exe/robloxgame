-- Hover tooltip for units on the field and bench (board and combat) and for shop cards
-- (UnitTooltip.setCardHover, from ShopPanel): the character's name, its cost in the cost's color,
-- each trait's symbol with its name, its role (front or back line, from its range) and a one-line
-- description of its ability (AbilityText). Needs a mouse; on touch, a shop card's info button
-- opens the unit info panel instead. Presentation only.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local AbilityText = require(script.Parent.AbilityText)
local Arena = require(script.Parent.Arena)
local TraitIcon = require(script.Parent.TraitIcon)

local UnitTooltip = {}

local OFFSET = Vector2.new(16, 12) -- from the mouse to the tooltip's corner
local TEXT_WIDTH = 240 -- the role and ability lines wrap at this width
local MAX_ABILITY = 110 -- characters of the ability line

local cardType: string? = nil -- the shop card under the mouse, if any

-- Shows the tooltip for a shop card's character while the mouse is over it (nil: none).
function UnitTooltip.setCardHover(unitType: string?)
	cardType = unitType
end

-- "Front line (melee)" or "Back line (range 4)".
local function roleOf(unit): string
	if unit.range <= 1 then
		return "Front line (melee)"
	end
	return string.format("Back line (range %d)", unit.range)
end

-- The first sentence of the ability description, capped.
local function abilityLine(unitType: string): string
	local text = AbilityText.of(unitType)
	local first = string.match(text, "^(.-%.)%s") or text
	if #first > MAX_ABILITY then
		first = string.sub(first, 1, MAX_ABILITY - 3) .. "..."
	end
	return first
end

local function line(parent: Instance, order: number, text: string, color: Color3)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.fromOffset(TEXT_WIDTH, 0)
	label.BackgroundTransparency = 1
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.TextColor3 = color
	label.Font = UITheme.fonts.body
	label.TextSize = 13
	label.Parent = parent
end

function UnitTooltip.start()
	if not UserInputService.MouseEnabled then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "UnitTooltip"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 11

	local frame = Instance.new("Frame")
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.BackgroundColor3 = UITheme.colors.panel
	frame.BackgroundTransparency = UITheme.colors.panelTransparency
	frame.Visible = false
	frame.Parent = screenGui
	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 8)
	frameCorner.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = frame

	local shownType: string? = nil

	local function show(unitType: string)
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local unit = UnitConfig[unitType]
		local costColor = RenderConfig.costColors[unit.cost]
		stroke.Color = costColor

		local title = Instance.new("TextLabel")
		title.LayoutOrder = 0
		title.AutomaticSize = Enum.AutomaticSize.XY
		title.BackgroundTransparency = 1
		title.RichText = true
		local name = SkinConfig[unitType].name
		title.Text = string.format('%s  <font color="#%s">%d-cost</font>', name, costColor:ToHex(), unit.cost)
		title.TextColor3 = UITheme.colors.text
		title.Font = UITheme.fonts.body
		title.TextSize = 14
		title.Parent = frame
		local traits = TraitIcon.traitsOf(unit)
		for order, traitId in traits do
			TraitIcon.labeled(traitId, 16, 13, frame).LayoutOrder = order
		end
		line(frame, #traits + 1, roleOf(unit), UITheme.colors.textDim)
		line(frame, #traits + 2, "Ultimate: " .. abilityLine(unitType), UITheme.colors.gold)
	end

	RunService.RenderStepped:Connect(function()
		local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local unitType = cardType
		if not unitType then
			local hit = Arena.raycast(mouse)
			unitType = if hit then hit.Instance:GetAttribute("UnitType") else nil
		end
		if unitType ~= nil and UnitConfig[unitType] == nil then
			unitType = nil
		end
		if unitType ~= shownType then
			shownType = unitType
			if unitType then
				show(unitType)
			end
			frame.Visible = unitType ~= nil
		end
		if unitType then
			-- Above the mouse over the shop (at the bottom of the screen), below it elsewhere.
			if cardType then
				frame.AnchorPoint = Vector2.new(0, 1)
				frame.Position = UDim2.fromOffset(mouse.X + OFFSET.X, mouse.Y - OFFSET.Y)
			else
				frame.AnchorPoint = Vector2.zero
				frame.Position = UDim2.fromOffset(mouse.X + OFFSET.X, mouse.Y + OFFSET.Y)
			end
		end
	end)

	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return UnitTooltip
