-- The item tooltip for the icons over units (board, bench and combat; UnitView.itemAtScreen):
-- hovering an icon with the mouse, or tapping it, shows the item's icon, name and effect text next
-- to it. A tapped tooltip stays for a few seconds. Presentation only.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

local ItemIcon = require(script.Parent.ItemIcon)
local UnitView = require(script.Parent.UnitView)

local ItemBadgeTooltip = {}

local WIDTH = 230
local PINNED_SECONDS = 3
local OFFSET = Vector2.new(18, 10) -- from the icon to the tooltip's corner

function ItemBadgeTooltip.start()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ItemBadgeTooltip"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 12

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(WIDTH, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = UITheme.colors.panel
	frame.BackgroundTransparency = UITheme.colors.panelTransparency
	frame.Visible = false
	frame.Parent = screenGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = frame

	local header = Instance.new("Frame")
	header.LayoutOrder = 1
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 24)
	header.Parent = frame
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(30, 0)
	name.Size = UDim2.new(1, -30, 1, 0)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Font = UITheme.fonts.body
	name.TextSize = 15
	name.TextColor3 = UITheme.colors.gold
	name.Parent = header
	local text = Instance.new("TextLabel")
	text.LayoutOrder = 2
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Font = UITheme.fonts.body
	text.TextSize = 13
	text.TextColor3 = UITheme.colors.text
	text.Parent = frame

	local shownItem: string? = nil
	local icon: Frame? = nil
	local pinnedUntil = 0

	local function show(itemId: string?, at: Vector2?)
		if itemId ~= shownItem then
			shownItem = itemId
			if icon then
				icon:Destroy()
				icon = nil
			end
			if itemId then
				name.Text = ItemIcon.name(itemId)
				text.Text = ItemIcon.text(itemId)
				stroke.Color = ItemIcon.color(itemId)
				local newIcon = ItemIcon.new(itemId, 24, header)
				icon = newIcon
			end
		end
		frame.Visible = itemId ~= nil
		if itemId and at then
			-- Keep it on screen: flip to the left of the icon near the right edge.
			local viewport = screenGui.AbsoluteSize
			local x = at.X + OFFSET.X
			if x + WIDTH > viewport.X then
				x = at.X - OFFSET.X - WIDTH
			end
			local y = math.min(at.Y + OFFSET.Y, viewport.Y - frame.AbsoluteSize.Y - 4)
			frame.Position = UDim2.fromOffset(math.max(4, x), math.max(4, y))
		end
	end

	-- A tap or click on an icon pins its tooltip for a moment (touch has no hover).
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local itemId, at = UnitView.itemAtScreen(Vector2.new(input.Position.X, input.Position.Y))
		if itemId then
			pinnedUntil = os.clock() + PINNED_SECONDS
			show(itemId, at)
		elseif os.clock() < pinnedUntil then
			pinnedUntil = 0
			show(nil)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if os.clock() < pinnedUntil then
			return
		end
		if not UserInputService.MouseEnabled then
			if shownItem then
				show(nil)
			end
			return
		end
		local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local itemId, at = UnitView.itemAtScreen(mouse)
		show(itemId, at)
	end)

	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return ItemBadgeTooltip
