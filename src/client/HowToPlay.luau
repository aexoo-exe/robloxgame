-- How to play: a short intro of a few pages (shop, board and level cap, stars, traits, gold) shown
-- in the hub before a new player's first match, and a "?" button in the top-left corner of the
-- match HUD to open it again. In a match it docks at the left edge without a backdrop, so it never
-- blocks the board, bench or shop. Skippable at any page. The server remembers that it was seen (TutorialSeen player
-- attribute, RequestTutorialSeen; PlaytestService). Numbers come from the configs, so the text stays
-- right when they are tuned. Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared:WaitForChild("EconomyConfig"))
local LevelConfig = require(Shared:WaitForChild("LevelConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local UI = require(script.Parent.UI)

local HowToPlay = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local WIDTH = 420
-- How long to wait for the server to load TutorialSeen before showing the intro anyway.
local FLAG_WAIT_SECONDS = 5

local PAGES = {
	{
		title = "Welcome!",
		body = "Build a team of units. Each round your board fights another player's board on its own. "
			.. "Lose a fight and you lose HP. The last player standing wins.",
	},
	{
		title = "Buy units",
		body = string.format(
			"The shop at the bottom offers %d units. Click one to buy it with gold; it goes to your bench. "
				.. "Reroll (%d gold) for new offers.",
			ShopConfig.slots,
			ShopConfig.rerollCost
		),
	},
	{
		title = "Place them",
		body = "Drag units from the bench onto your board. Only units on the board fight. "
			.. "You can place as many units as your level.",
	},
	{
		title = "Stars and traits",
		body = "Three copies of the same unit combine into a stronger 2-star; three 2-stars make a 3-star. "
			.. "Units share traits: place enough units with the same trait to switch on its bonus (the trait "
			.. "list on the left).",
	},
	{
		title = "Gold and levels",
		body = string.format(
			"Every round pays %d gold, plus 1 per %d gold you save (up to +%d) and a bonus for win or loss "
				.. "streaks. Buy XP (%d gold) to level up: more units on the board and pricier units in the shop.",
			EconomyConfig.baseIncome,
			EconomyConfig.goldPerInterest,
			EconomyConfig.maxInterest,
			LevelConfig.buyXpCost
		),
	},
}

function HowToPlay.start()
	local localPlayer = Players.LocalPlayer
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local requestSeen = remotes:WaitForChild(RemoteNames.RequestTutorialSeen)

	-- The "?" button: next to the practice Leave button, top left.
	local _, buttonRoot = UI.screen("HowToPlayButton", 7)
	local help = UI.button(buttonRoot, COLORS.panelLight, UDim2.fromOffset(32, 32))
	help.Position = UDim2.fromOffset(SIZES.margin + 92, 6)
	local helpLabel = UI.text(help, "?", SIZES.textLarge, FONTS.display)
	helpLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	helpLabel.Position = UDim2.fromScale(0.5, 0.5)

	-- The pages, on their own screen (shown in the hub and in a match). In the hub the panel sits in
	-- the middle over a dim backdrop; in a match it docks at the left edge with no backdrop, so the
	-- board, bench and shop stay usable. Neither takes presses outside the panel's own buttons.
	local _, root = UI.screen("HowToPlay", 16, true)
	local backdrop = Instance.new("Frame")
	backdrop.Active = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.Parent = root
	local panel = UI.panel(root, UDim2.fromOffset(WIDTH, 0))
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Visible = false
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	UI.padding(content, 16)
	UI.list(content, 12, Enum.HorizontalAlignment.Center)
	content.Parent = panel

	local title = UI.text(content, "", SIZES.textLarge + 4, FONTS.display, COLORS.gold)
	title.LayoutOrder = 1
	local body = UI.text(content, "", SIZES.text, FONTS.body)
	body.LayoutOrder = 2
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Size = UDim2.fromOffset(WIDTH - 32, 0)
	body.TextWrapped = true
	local pageLabel = UI.text(content, "", SIZES.textSmall, FONTS.body, COLORS.textDim)
	pageLabel.LayoutOrder = 3

	local buttons = UI.row(content, 10)
	buttons.LayoutOrder = 4
	local function button(text: string, color: Color3, order: number): (TextButton, TextLabel)
		local instance = UI.button(buttons, color, UDim2.fromOffset(110, 44))
		instance.LayoutOrder = order
		local label = UI.text(instance, text, SIZES.text + 2, FONTS.display)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		return instance, label
	end
	local skip = button("SKIP", COLORS.panelLight, 1)
	local back = button("BACK", COLORS.panelLight, 2)
	local nextButton, nextLabel = button("NEXT", COLORS.buy, 3)

	local page = 1
	local isOpen = false
	local function show(index: number)
		page = index
		title.Text = PAGES[page].title
		body.Text = PAGES[page].body
		pageLabel.Text = string.format("%d / %d", page, #PAGES)
		back.Visible = page > 1
		nextLabel.Text = if page == #PAGES then "GOT IT" else "NEXT"
	end
	-- Middle of the screen with the backdrop in the hub; docked left (over the trait list) in a match.
	local function place()
		local inMatch = localPlayer:GetAttribute("InMatch") == true
		backdrop.Visible = isOpen and not inMatch
		panel.Visible = isOpen
		if inMatch then
			panel.AnchorPoint = Vector2.new(0, 0.5)
			panel.Position = UDim2.new(0, SIZES.margin, 0.5, 0)
		else
			panel.AnchorPoint = Vector2.new(0.5, 0.5)
			panel.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
	local function open()
		show(1)
		isOpen = true
		place()
		UI.pop(panel, 1.06)
	end
	local function close()
		isOpen = false
		place()
		if localPlayer:GetAttribute("TutorialSeen") ~= true then
			requestSeen:FireServer()
		end
	end

	help.Activated:Connect(function()
		if isOpen then
			close()
		else
			open()
		end
	end)
	skip.Activated:Connect(close)
	back.Activated:Connect(function()
		show(math.max(1, page - 1))
	end)
	nextButton.Activated:Connect(function()
		if page >= #PAGES then
			close()
		else
			show(page + 1)
		end
	end)

	-- A player who never closed it gets it in the hub, before their first match: once the server has
	-- loaded TutorialSeen (or after FLAG_WAIT_SECONDS), while they are in the hub. Once a session.
	local autoShown = false
	task.spawn(function()
		local waitUntil = os.clock() + FLAG_WAIT_SECONDS
		while localPlayer:GetAttribute("TutorialSeen") == nil and os.clock() < waitUntil do
			task.wait(0.2)
		end
		if localPlayer:GetAttribute("TutorialSeen") ~= true and localPlayer:GetAttribute("InMatch") ~= true then
			autoShown = true
			open()
		end
	end)
	localPlayer:GetAttributeChangedSignal("InMatch"):Connect(function()
		-- Still open when a match starts: it moves aside (docked, no backdrop) rather than blocking.
		place()
		-- Back in the hub without having closed it once: show it again there.
		if not autoShown and not isOpen and localPlayer:GetAttribute("InMatch") ~= true then
			if localPlayer:GetAttribute("TutorialSeen") == false then
				autoShown = true
				open()
			end
		end
	end)
end

return HowToPlay
