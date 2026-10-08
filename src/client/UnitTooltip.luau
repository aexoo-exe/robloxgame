-- Hover tooltip for units on the field and bench (board and combat): the character's name, its
-- cost in the cost's color, and each trait's symbol with its name. Needs a mouse; touch players
-- read trait names on the shop cards. Presentation only.

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

local Arena = require(script.Parent.Arena)
local TraitIcon = require(script.Parent.TraitIcon)

local UnitTooltip = {}

local OFFSET = Vector2.new(16, 12) -- from the mouse to the tooltip's corner

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
		for order, traitId in TraitIcon.traitsOf(unit) do
			TraitIcon.labeled(traitId, 16, 13, frame).LayoutOrder = order
		end
	end

	RunService.RenderStepped:Connect(function()
		local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local hit = Arena.raycast(mouse)
		local unitType = if hit then hit.Instance:GetAttribute("UnitType") else nil
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
			frame.Position = UDim2.fromOffset(mouse.X + OFFSET.X, mouse.Y + OFFSET.Y)
		end
	end)

	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return UnitTooltip
