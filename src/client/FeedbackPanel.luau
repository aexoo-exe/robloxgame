-- Playtest feedback: when the player is back in the hub after a match (InMatch turns false, at the
-- match end or after leaving once knocked out), a small panel asks for 1-5 stars and an optional
-- line of text ("what was confusing or fun?"). SEND fires RequestSendFeedback (PlaytestService
-- filters and logs it); NOT NOW closes it. It never blocks anything: the player can walk around
-- while it is open. Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local UI = require(script.Parent.UI)

local FeedbackPanel = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local WIDTH = 360
local MAX_TEXT = 300 -- the server caps it too
local THANKS_SECONDS = 1.5

function FeedbackPanel.start()
	local localPlayer = Players.LocalPlayer
	local requestSend = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(RemoteNames.RequestSendFeedback)

	local _, root = UI.screen("FeedbackPanel", 12, true)
	local panel = UI.panel(root, UDim2.fromOffset(WIDTH, 0))
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -24)
	panel.Visible = false
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	UI.padding(content, 14)
	UI.list(content, 10, Enum.HorizontalAlignment.Center)
	content.Parent = panel

	local title = UI.text(content, "How was that match?", SIZES.textLarge, FONTS.display)
	title.LayoutOrder = 1

	local starRow = UI.row(content, 6)
	starRow.LayoutOrder = 2
	local stars = 0
	local starLabels: { TextLabel } = {}
	local function drawStars()
		for index, label in starLabels do
			label.TextColor3 = if index <= stars then COLORS.gold else COLORS.textDim
		end
	end

	local box = Instance.new("TextBox")
	box.LayoutOrder = 3
	box.Size = UDim2.fromOffset(WIDTH - 28, 64)
	box.BackgroundColor3 = COLORS.panelLight
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.MultiLine = true
	box.TextWrapped = true
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.Font = FONTS.body
	box.TextSize = SIZES.text
	box.TextColor3 = COLORS.text
	box.PlaceholderText = "What was confusing or fun? (optional)"
	box.PlaceholderColor3 = COLORS.textDim
	box.Text = ""
	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 6)
	boxCorner.Parent = box
	local boxPadding = Instance.new("UIPadding")
	boxPadding.PaddingLeft = UDim.new(0, 6)
	boxPadding.PaddingRight = UDim.new(0, 6)
	boxPadding.PaddingTop = UDim.new(0, 4)
	boxPadding.Parent = box
	box.Parent = content
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > MAX_TEXT then
			box.Text = string.sub(box.Text, 1, MAX_TEXT)
		end
	end)

	local buttons = UI.row(content, 10)
	buttons.LayoutOrder = 4
	local function button(text: string, color: Color3, order: number): TextButton
		local instance = UI.button(buttons, color, UDim2.fromOffset(120, UI.touchSize(38)))
		instance.LayoutOrder = order
		local label = UI.text(instance, text, SIZES.text + 2, FONTS.display)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		return instance
	end
	local later = button("NOT NOW", COLORS.panelLight, 1)
	local send = button("SEND", COLORS.buy, 2)

	for index = 1, 5 do
		local starButton = UI.button(starRow, COLORS.panelLight, UDim2.fromOffset(UI.touchSize(40), UI.touchSize(40)))
		starButton.LayoutOrder = index
		local label = UI.text(starButton, "★", SIZES.textLarge + 2, FONTS.display, COLORS.textDim)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		starButton.Activated:Connect(function()
			stars = index
			drawStars()
			UI.setEnabled(send, true)
		end)
		starLabels[index] = label
	end

	local function open()
		stars = 0
		drawStars()
		box.Text = ""
		title.Text = "How was that match?"
		starRow.Visible = true
		box.Visible = true
		buttons.Visible = true
		UI.setEnabled(send, false)
		panel.Visible = true
		UI.pop(panel, 1.06)
	end
	local function close()
		panel.Visible = false
		box:ReleaseFocus()
	end

	later.Activated:Connect(close)
	send.Activated:Connect(function()
		if stars < 1 or not UI.isEnabled(send) then
			return
		end
		requestSend:FireServer(stars, box.Text)
		title.Text = "Thanks!"
		starRow.Visible = false
		box.Visible = false
		buttons.Visible = false
		task.delay(THANKS_SECONDS, close)
	end)

	-- Back in the hub after a match: ask once.
	local wasInMatch = localPlayer:GetAttribute("InMatch") == true
	localPlayer:GetAttributeChangedSignal("InMatch"):Connect(function()
		local inMatch = localPlayer:GetAttribute("InMatch") == true
		if wasInMatch and not inMatch then
			open()
		elseif inMatch then
			close()
		end
		wasInMatch = inMatch
	end)
end

return FeedbackPanel
