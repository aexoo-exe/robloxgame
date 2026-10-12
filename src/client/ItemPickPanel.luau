-- The item choice screen: opens by itself the moment an item choice is offered (PlayerState view
-- `itemOffer`) and shows each offered item's icon, name and effect text with a Pick button. "Later"
-- folds it into a small "Pick an item" button so the board stays usable; still unpicked, it opens
-- again by itself when the next Preparation starts. The server takes the first item if none was
-- picked when Preparation ends. A picked item lands in the inventory strip, which highlights it.
-- The client only asks (RequestPickItem). Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Phase = require(Shared:WaitForChild("Phase"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local ItemIcon = require(script.Parent.ItemIcon)
local UI = require(script.Parent.UI)

local ItemPickPanel = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local CARD = Vector2.new(150, 168)
local ICON = 40

-- A label centered on a button.
local function label(button: GuiObject, text: string, size: number)
	local textLabel = UI.text(button, text, size, FONTS.display)
	textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	textLabel.Position = UDim2.fromScale(0.5, 0.5)
	return textLabel
end

function ItemPickPanel.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local requestPick = remotes:WaitForChild(RemoteNames.RequestPickItem)

	local _, root = UI.screen("ItemPickPanel", 8)
	local panel = UI.panel(root, UDim2.fromOffset(0, 0), true)
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.45)
	panel.Visible = false
	UI.padding(panel, 10)
	UI.list(panel, 8, Enum.HorizontalAlignment.Center)

	local title = UI.text(panel, "PICK AN ITEM", SIZES.textLarge, FONTS.display, COLORS.gold)
	title.LayoutOrder = 1
	local cards = UI.row(panel, 8)
	cards.LayoutOrder = 2
	local later = UI.button(panel, COLORS.panelLight, UDim2.fromOffset(120, 32))
	later.LayoutOrder = 3
	label(later, "LATER", SIZES.text)

	-- The folded state: a small button that opens the choice again.
	local reopen = UI.button(root, COLORS.buy, UDim2.fromOffset(140, 34))
	reopen.AnchorPoint = Vector2.new(0.5, 0)
	reopen.Position = UDim2.new(0.5, 0, 0, SIZES.topBarHeight + 8)
	reopen.Visible = false
	label(reopen, "PICK AN ITEM", SIZES.text)

	local offer: { string }? = nil
	local offerKey = "" -- the open offer's item ids, to tell a new offer from the same one resent
	local folded = false
	local pending = false -- a pick was sent; further clicks wait for the server's answer

	local function render()
		for _, child in cards:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		panel.Visible = offer ~= nil and not folded
		reopen.Visible = offer ~= nil and folded
		if not offer then
			return
		end
		for index, itemId in offer do
			local card = Instance.new("Frame")
			card.LayoutOrder = index
			card.Size = UDim2.fromOffset(CARD.X, CARD.Y)
			card.BackgroundColor3 = COLORS.panelLight
			card.BorderSizePixel = 0
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = card
			UI.padding(card, 6)
			UI.list(card, 4, Enum.HorizontalAlignment.Center)

			ItemIcon.new(itemId, ICON, card).LayoutOrder = 1
			local name = UI.text(card, ItemIcon.name(itemId), SIZES.text, FONTS.body, COLORS.gold)
			name.LayoutOrder = 2
			local text = UI.text(card, ItemIcon.text(itemId), SIZES.textSmall - 1, FONTS.body)
			text.LayoutOrder = 3
			text.AutomaticSize = Enum.AutomaticSize.None
			text.Size = UDim2.new(1, 0, 0, 70)
			text.TextWrapped = true
			text.TextYAlignment = Enum.TextYAlignment.Top

			local pick = UI.button(card, COLORS.buy, UDim2.new(1, 0, 0, 26))
			pick.LayoutOrder = 4
			label(pick, "PICK", SIZES.text)
			pick.Activated:Connect(function()
				if pending then
					return
				end
				pending = true
				requestPick:FireServer(index)
				-- A refused pick (full inventory) sends no new state; allow another try soon.
				task.delay(1, function()
					pending = false
				end)
			end)
			card.Parent = cards
		end
	end

	later.Activated:Connect(function()
		folded = true
		render()
	end)
	reopen.Activated:Connect(function()
		folded = false
		render()
	end)

	-- A new choice opens by itself the moment it is offered (also when it replaces an older one).
	remotes:WaitForChild(RemoteNames.PlayerStateUpdated).OnClientEvent:Connect(function(view)
		offer = view.itemOffer
		pending = false
		local key = if offer then table.concat(offer, ",") else ""
		local isNew = offer ~= nil and key ~= offerKey
		offerKey = key
		if isNew then
			folded = false
		end
		render()
		if isNew then
			UI.pop(panel, 1.06)
		end
	end)

	-- Still unpicked when the next Preparation starts: it opens again.
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	matchState:GetAttributeChangedSignal("Phase"):Connect(function()
		if matchState:GetAttribute("Phase") == Phase.Preparation and offer and folded then
			folded = false
			render()
			UI.pop(panel, 1.06)
		end
	end)
end

return ItemPickPanel
