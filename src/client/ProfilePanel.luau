-- The hub profile (ProfileUpdated from RetentionService): a "PROFILE" button in the hub's bottom-left
-- corner (with a "!" while a quest is ready to claim) that opens a panel with the account level and
-- XP, coins, the equipped title (tap to cycle through owned ones), the daily and weekly quests
-- (progress, CLAIM when complete, SWAP for one daily per UTC day) and the unit mastery list. Every
-- button only sends a request (RequestClaimQuest, RequestRerollQuest, RequestEquipTitle); the
-- server validates it and sends the new profile. Hub only. Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local UI = require(script.Parent.UI)

local ProfilePanel = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local WIDTH = 400

local function unitName(unitType: string): string
	local skin = SkinConfig[unitType]
	return if skin then skin.name else unitType
end

function ProfilePanel.start()
	local localPlayer = Players.LocalPlayer
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local requestProfile = remotes:WaitForChild(RemoteNames.RequestProfile)
	local requestClaim = remotes:WaitForChild(RemoteNames.RequestClaimQuest)
	local requestReroll = remotes:WaitForChild(RemoteNames.RequestRerollQuest)
	local requestTitle = remotes:WaitForChild(RemoteNames.RequestEquipTitle)

	local _, root = UI.screen("ProfilePanel", 9, true)

	-- The open button: bottom-left of the hub.
	local open = UI.button(root, COLORS.panelLight, UDim2.fromOffset(150, UI.touchSize(40)))
	open.AnchorPoint = Vector2.new(0, 1)
	open.Position = UDim2.new(0, SIZES.margin, 1, -SIZES.margin)
	local openLabel = UI.text(open, "PROFILE", SIZES.text + 2, FONTS.display)
	openLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	openLabel.Position = UDim2.fromScale(0.5, 0.5)
	local badge = UI.text(open, "!", SIZES.textLarge, FONTS.display, COLORS.gold)
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -6, 0, 6)
	badge.Visible = false

	-- The panel: a scrolling column so it fits small screens.
	local panel = UI.panel(root, UDim2.new(0, WIDTH, 0.82, 0))
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, SIZES.margin, 1, -(SIZES.margin + UI.touchSize(40) + 8))
	panel.Visible = false
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.Parent = panel
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -8, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	UI.padding(content, 12)
	UI.list(content, 6)
	content.Parent = scroll

	local view = nil
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function clear()
		order = 0
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
	local function label(text: string, size: number, font: Enum.Font, color: Color3?): TextLabel
		local item = UI.text(content, text, size, font, color)
		item.LayoutOrder = nextOrder()
		item.AutomaticSize = Enum.AutomaticSize.Y
		item.Size = UDim2.fromScale(1, 0)
		item.TextWrapped = true
		item.TextXAlignment = Enum.TextXAlignment.Left
		return item
	end
	local function smallButton(parent: Instance, text: string, color: Color3, onPress: () -> ()): TextButton
		local button = UI.button(parent, color, UDim2.fromOffset(78, UI.touchSize(30)))
		local text_ = UI.text(button, text, SIZES.textSmall + 1, FONTS.display)
		text_.AnchorPoint = Vector2.new(0.5, 0.5)
		text_.Position = UDim2.fromScale(0.5, 0.5)
		button.Activated:Connect(onPress)
		return button
	end

	-- One quest row: its text and progress, and CLAIM (complete) or SWAP (a daily, once a day).
	local function questRow(kind: string, quest)
		local row = Instance.new("Frame")
		row.LayoutOrder = nextOrder()
		row.BackgroundColor3 = COLORS.panelLight
		row.BackgroundTransparency = if quest.claimed then 0.6 else 0.2
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, UI.touchSize(44))
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row
		local text = UI.text(
			row,
			string.format("%s  %d/%d", quest.text, quest.progress, quest.target),
			SIZES.textSmall + 1,
			FONTS.body,
			if quest.claimed then COLORS.textDim else COLORS.text
		)
		text.AutomaticSize = Enum.AutomaticSize.None
		text.Position = UDim2.fromOffset(8, 2)
		text.Size = UDim2.new(1, -100, 0.6, 0)
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextWrapped = true
		local reward = UI.text(
			row,
			string.format("+%d XP  +%d coins", quest.xp, quest.coins),
			SIZES.textSmall,
			FONTS.body,
			COLORS.textDim
		)
		reward.AnchorPoint = Vector2.new(0, 1)
		reward.Position = UDim2.new(0, 8, 1, -2)
		local button = nil
		if quest.claimed then
			reward.Text = "claimed"
		elseif quest.complete then
			button = smallButton(row, "CLAIM", COLORS.buy, function()
				requestClaim:FireServer(kind, quest.index)
			end)
		elseif kind == "daily" and view and view.rerollAvailable then
			button = smallButton(row, "SWAP", COLORS.reroll, function()
				requestReroll:FireServer(quest.index)
			end)
		end
		if button then
			button.AnchorPoint = Vector2.new(1, 0.5)
			button.Position = UDim2.new(1, -6, 0.5, 0)
		end
		row.Parent = content
	end

	local function render()
		clear()
		if not view then
			label("Loading your profile...", SIZES.text, FONTS.body)
			return
		end
		label(string.format("Level %d", view.level), SIZES.textLarge + 4, FONTS.display, COLORS.gold)
		local bar = UI.bar(content, UDim2.new(1, 0, 0, 10), COLORS.xp)
		bar.frame.LayoutOrder = nextOrder()
		UI.setBar(bar, if view.xpToNext > 0 then view.xp / view.xpToNext else 1, false)
		label(
			string.format(
				"%d / %d XP    %d coins    %d days played",
				view.xp,
				view.xpToNext,
				view.coins,
				view.days.played
			),
			SIZES.textSmall + 1,
			FONTS.number,
			COLORS.textDim
		)
		if not view.saving then
			label("Your progress is not being saved this session.", SIZES.textSmall + 1, FONTS.body, COLORS.loss)
		end
		-- The title: tap to cycle through owned titles (and none).
		local titleRow = UI.row(content, 8)
		titleRow.LayoutOrder = nextOrder()
		UI.text(titleRow, "Title:", SIZES.text, FONTS.body).LayoutOrder = 1
		local titleButton = smallButton(
			titleRow,
			if view.titleText ~= "" then view.titleText else "none",
			COLORS.panelLight,
			function()
				local ids = { "" }
				for _, title in view.titles do
					table.insert(ids, title.id)
				end
				local index = table.find(ids, view.title) or 1
				requestTitle:FireServer(ids[index % #ids + 1])
			end
		)
		titleButton.Size = UDim2.fromOffset(150, UI.touchSize(30))
		titleButton.LayoutOrder = 2

		label("DAILY QUESTS", SIZES.text + 2, FONTS.display)
		for _, quest in view.quests.daily do
			questRow("daily", quest)
		end
		label("WEEKLY QUESTS", SIZES.text + 2, FONTS.display)
		for _, quest in view.quests.weekly do
			questRow("weekly", quest)
		end
		label("UNIT MASTERY", SIZES.text + 2, FONTS.display)
		if #view.mastery == 0 then
			label("Field units in matches to build their mastery.", SIZES.textSmall + 1, FONTS.body, COLORS.textDim)
		end
		for _, entry in view.mastery do
			label(
				string.format(
					"%s   Lv %d%s",
					unitName(entry.unit),
					entry.level,
					if entry.toNext > 0 then string.format("   (%d to next)", entry.toNext) else "   (max)"
				),
				SIZES.textSmall + 1,
				FONTS.body
			)
		end
	end

	local function claimable(): boolean
		if not view then
			return false
		end
		for _, kind in { "daily", "weekly" } do
			for _, quest in view.quests[kind] do
				if quest.complete and not quest.claimed then
					return true
				end
			end
		end
		return false
	end

	remotes:WaitForChild(RemoteNames.ProfileUpdated).OnClientEvent:Connect(function(newView)
		view = newView
		openLabel.Text = string.format("PROFILE  Lv %d", view.level)
		badge.Visible = claimable()
		if panel.Visible then
			render()
		end
	end)
	open.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			render()
			UI.pop(panel, 1.04)
			requestProfile:FireServer()
		end
	end)
	-- Hub only: hidden in a match.
	local function applyMode()
		local inMatch = localPlayer:GetAttribute("InMatch") == true
		root.Visible = not inMatch
		if inMatch then
			panel.Visible = false
		end
	end
	localPlayer:GetAttributeChangedSignal("InMatch"):Connect(applyMode)
	applyMode()
	requestProfile:FireServer()
end

return ProfilePanel
