-- Reserved: the "pick 1 of 3" reward screen. Rewards do not exist yet, so nothing opens it. This
-- builds its layout hidden, so the space and the look are settled: a dimmed backdrop, a title row
-- and three empty choice cards in the middle of the screen, above the shop. A later task fills the
-- cards and calls RewardScreen.setVisible(true).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

local UI = require(script.Parent.UI)

local RewardScreen = {}

local CHOICES = 3
local CARD = Vector2.new(170, 220)

local screen: ScreenGui? = nil

function RewardScreen.start()
	local gui, root = UI.screen("RewardScreen", 9)
	gui.Enabled = false
	screen = gui

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Parent = root

	local panel = UI.panel(root, UDim2.fromOffset(0, 0))
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.45)
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.XY
	UI.padding(content, 14)
	UI.list(content, 10, Enum.HorizontalAlignment.Center)
	content.Parent = panel

	local title = UI.row(content, 8)
	title.Name = "Title"
	title.LayoutOrder = 1

	local cards = UI.row(content, 14)
	cards.Name = "Choices"
	cards.LayoutOrder = 2
	for i = 1, CHOICES do
		local card = UI.button(cards, UITheme.colors.panelLight, UDim2.fromOffset(CARD.X, CARD.Y))
		card.Name = "Choice" .. i
		card.LayoutOrder = i
	end
end

function RewardScreen.setVisible(visible: boolean)
	if screen then
		screen.Enabled = visible
	end
end

return RewardScreen
