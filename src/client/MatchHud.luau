-- Match-level screens, read from the public MatchState:
--   * a banner while you are knocked out, with your placement
--   * the final placements screen during MatchOver, the winner on top with confetti
--   * a "Back to hub" button with either of those (RequestLeaveMatch); everyone returns to the hub
--     anyway when the final placements end
--   * in a practice match only, a small "Leave" button (top left) with a "Leave practice?"
--     confirmation (RequestLeavePractice): ends the practice match and returns to the hub at once
-- The player list lives in PlayerList. Presentation only; redraws a few times per second.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Phase = require(Shared:WaitForChild("Phase"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local Celebrate = require(script.Parent.Celebrate)
local UI = require(script.Parent.UI)

local MatchHud = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local REFRESH_SECONDS = 0.25

function MatchHud.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local playersFolder = matchState:WaitForChild("Players")
	local localUserId = Players.LocalPlayer.UserId
	local _, root = UI.screen("MatchHud", 7)

	-- Knocked out: a red banner with your placement.
	local banner = UI.panel(root, UDim2.fromOffset(0, 0))
	banner.AutomaticSize = Enum.AutomaticSize.XY
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, SIZES.topBarHeight + 16)
	banner.BackgroundColor3 = COLORS.loss
	banner.Visible = false
	local bannerRow = UI.row(banner, 10)
	UI.padding(bannerRow, 10)
	UI.glyph(bannerRow, UITheme.icons.loss, SIZES.textHuge - 8).LayoutOrder = 1
	local bannerLabel = UI.text(bannerRow, "", SIZES.textHuge - 8, FONTS.display)
	bannerLabel.LayoutOrder = 2

	-- Final placements: a ranked list, the winner first.
	local final = UI.panel(root, UDim2.fromOffset(340, 0))
	final.AutomaticSize = Enum.AutomaticSize.Y
	final.AnchorPoint = Vector2.new(0.5, 0.5)
	final.Position = UDim2.fromScale(0.5, 0.5)
	final.Visible = false
	local finalList = Instance.new("Frame")
	finalList.BackgroundTransparency = 1
	finalList.Size = UDim2.fromScale(1, 0)
	finalList.AutomaticSize = Enum.AutomaticSize.Y
	UI.padding(finalList, 12)
	UI.list(finalList, 6)
	finalList.Parent = final

	-- Back to the hub: once knocked out, or while the final placements show (the server checks).
	local leave = UI.button(root, COLORS.buy, UDim2.fromOffset(200, 44))
	leave.AnchorPoint = Vector2.new(0.5, 1)
	leave.Position = UDim2.new(0.5, 0, 1, -(UITheme.boardInsets.bottom + 16))
	leave.Visible = false
	local leaveLabel = UI.text(leave, "BACK TO HUB", SIZES.textLarge, FONTS.display)
	leaveLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	leaveLabel.Position = UDim2.fromScale(0.5, 0.5)
	local requestLeave = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(RemoteNames.RequestLeaveMatch)
	leave.Activated:Connect(function()
		requestLeave:FireServer()
	end)

	-- Practice matches only (MatchState Practice): a small Leave button in the top-left corner, away
	-- from the board, shop and bench, that asks before leaving. The server ends the practice match
	-- and sends the player back to the hub; it refuses in a player match.
	local requestLeavePractice = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(RemoteNames.RequestLeavePractice)
	local practiceLeave = UI.button(root, COLORS.sell, UDim2.fromOffset(84, 32))
	practiceLeave.Position = UDim2.fromOffset(SIZES.margin, 6)
	practiceLeave.Visible = false
	local practiceLabel = UI.text(practiceLeave, "LEAVE", SIZES.text, FONTS.display)
	practiceLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	practiceLabel.Position = UDim2.fromScale(0.5, 0.5)

	-- The confirmation, on its own screen above the rest of the HUD. Its backdrop takes every press,
	-- so nothing behind it is touched while it is open.
	local _, dialogRoot = UI.screen("LeavePracticeDialog", 15)
	local backdrop = Instance.new("TextButton")
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Visible = false
	backdrop.Parent = dialogRoot
	local dialog = UI.panel(backdrop, UDim2.fromOffset(0, 0))
	dialog.AutomaticSize = Enum.AutomaticSize.XY
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	dialog.Position = UDim2.fromScale(0.5, 0.5)
	local dialogContent = Instance.new("Frame")
	dialogContent.BackgroundTransparency = 1
	dialogContent.AutomaticSize = Enum.AutomaticSize.XY
	UI.padding(dialogContent, 16)
	UI.list(dialogContent, 14, Enum.HorizontalAlignment.Center)
	dialogContent.Parent = dialog
	UI.text(dialogContent, "Leave practice?", SIZES.textLarge + 2, FONTS.display).LayoutOrder = 1
	local choices = UI.row(dialogContent, 12)
	choices.LayoutOrder = 2
	local function choice(text: string, color: Color3, order: number): TextButton
		local button = UI.button(choices, color, UDim2.fromOffset(120, 42))
		button.LayoutOrder = order
		local label = UI.text(button, text, SIZES.textLarge, FONTS.display)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		return button
	end
	local confirm = choice("LEAVE", COLORS.sell, 1)
	local cancel = choice("CANCEL", COLORS.panelLight, 2)

	local function setDialog(open: boolean)
		backdrop.Visible = open
		if open then
			UI.pop(dialog, 1.08)
		end
	end
	practiceLeave.Activated:Connect(function()
		setDialog(true)
	end)
	cancel.Activated:Connect(function()
		setDialog(false)
	end)
	confirm.Activated:Connect(function()
		setDialog(false)
		requestLeavePractice:FireServer()
	end)

	local wasOver = false
	local function refresh()
		local phase = matchState:GetAttribute("Phase")
		local own = playersFolder:FindFirstChild(tostring(localUserId))
		local knockedOut = own ~= nil and own:GetAttribute("Eliminated") == true and phase ~= Phase.MatchOver
		if knockedOut and not banner.Visible then
			UI.pop(banner)
		end
		banner.Visible = knockedOut
		leave.Visible = own ~= nil and (knockedOut or phase == Phase.MatchOver)
		local canLeavePractice = matchState:GetAttribute("Practice") == true
			and own ~= nil
			and not knockedOut
			and phase ~= Phase.MatchOver
			and phase ~= Phase.Waiting
		practiceLeave.Visible = canLeavePractice
		if not canLeavePractice and backdrop.Visible then
			setDialog(false)
		end
		if knockedOut then
			bannerLabel.Text = "#" .. tostring(own:GetAttribute("Placement") or 0)
		end

		local over = phase == Phase.MatchOver
		final.Visible = over
		if over and not wasOver then
			for _, child in finalList:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			local entries = {}
			for _, folder in playersFolder:GetChildren() do
				table.insert(entries, {
					userId = folder:GetAttribute("UserId"),
					name = folder:GetAttribute("DisplayName") or folder.Name,
					placement = folder:GetAttribute("Placement") or 0,
				})
			end
			table.sort(entries, function(a, b)
				return a.placement < b.placement
			end)
			for order, entry in entries do
				local row = UI.row(finalList, 10)
				row.LayoutOrder = order
				local first = entry.placement == 1
				local placeSize = if first then SIZES.textHuge - 6 else SIZES.textLarge
				local placeColor = if first then COLORS.gold else COLORS.textDim
				local place = UI.text(row, "#" .. entry.placement, placeSize, FONTS.display, placeColor)
				place.LayoutOrder = 1
				local nameSize = if first then SIZES.textLarge + 2 else SIZES.text
				local nameColor = if entry.userId == localUserId then COLORS.you else COLORS.text
				local name = UI.text(row, entry.name, nameSize, FONTS.body, nameColor)
				name.LayoutOrder = 2
			end
			UI.pop(final, 1.15)
			local winner = entries[1]
			if winner and winner.userId == localUserId then
				Celebrate.confetti(root)
			end
		end
		wasOver = over
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return MatchHud
