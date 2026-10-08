-- The round result popup, shown when Results begins: a big win, loss or draw badge, then icons and
-- numbers for what changed (health lost, PvE gold earned, or the placement if you were knocked
-- out). A win throws confetti. It bounces in and hides itself after UITheme.motion.resultTime.
-- Presentation only: reads the LastOutcome, LastDamage, LastGold, Eliminated and Placement
-- attributes of the local player's MatchState.Players folder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Phase = require(Shared:WaitForChild("Phase"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local Celebrate = require(script.Parent.Celebrate)
local UI = require(script.Parent.UI)

local RoundResult = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local ICONS = UITheme.icons
local BADGE = 76

function RoundResult.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local playersFolder = matchState:WaitForChild("Players")
	local _, root = UI.screen("RoundResult", 8)

	local panel = UI.panel(root, UDim2.fromOffset(0, 0))
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.36)
	panel.Visible = false
	local content = UI.row(panel, 16)
	UI.padding(content, 14)

	local badge = Instance.new("Frame")
	badge.LayoutOrder = 1
	badge.Size = UDim2.fromOffset(BADGE, BADGE)
	badge.BorderSizePixel = 0
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge
	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = COLORS.outline
	badgeStroke.Thickness = 4
	badgeStroke.Parent = badge
	local badgeGlyph = UI.text(badge, "", SIZES.textHuge, FONTS.display)
	badgeGlyph.AutomaticSize = Enum.AutomaticSize.None
	badgeGlyph.Size = UDim2.fromScale(1, 1)
	badge.Parent = content

	local numbers = Instance.new("Frame")
	numbers.LayoutOrder = 2
	numbers.BackgroundTransparency = 1
	numbers.AutomaticSize = Enum.AutomaticSize.XY
	UI.list(numbers, 6)
	numbers.Parent = content

	local damageRow = UI.row(numbers, 6)
	damageRow.LayoutOrder = 1
	local damageLabel = UI.text(damageRow, "", SIZES.textHuge - 8, FONTS.number, COLORS.loss)
	damageLabel.LayoutOrder = 1
	UI.glyph(damageRow, ICONS.health, SIZES.textLarge, COLORS.loss).LayoutOrder = 2

	local goldRow = UI.row(numbers, 6)
	goldRow.LayoutOrder = 2
	local goldLabel = UI.text(goldRow, "", SIZES.textHuge - 8, FONTS.number, COLORS.gold)
	goldLabel.LayoutOrder = 1
	UI.coin(goldRow, 26).LayoutOrder = 2

	local placementLabel = UI.text(numbers, "", SIZES.textHuge - 8, FONTS.display, COLORS.gold)
	placementLabel.LayoutOrder = 3

	local shownCount = 0
	local function showResult()
		local own = playersFolder:FindFirstChild(tostring(Players.LocalPlayer.UserId))
		if not own then
			return
		end
		local outcome = own:GetAttribute("LastOutcome") or ""
		if outcome == "" then
			return
		end
		local damage = own:GetAttribute("LastDamage") or 0
		local gold = own:GetAttribute("LastGold") or 0
		local eliminated = own:GetAttribute("Eliminated") == true

		local won = outcome == Economy.Outcome.Win
		local drew = outcome == Economy.Outcome.Draw
		badge.BackgroundColor3 = if won then COLORS.win elseif drew then COLORS.draw else COLORS.loss
		badgeGlyph.Text = if won then ICONS.win elseif drew then ICONS.draw else ICONS.loss
		damageRow.Visible = damage > 0
		damageLabel.Text = "-" .. damage
		goldRow.Visible = gold > 0
		goldLabel.Text = "+" .. gold
		placementLabel.Visible = eliminated
		placementLabel.Text = "#" .. tostring(own:GetAttribute("Placement") or 0)
		numbers.Visible = damageRow.Visible or goldRow.Visible or placementLabel.Visible

		panel.Visible = true
		UI.pop(panel, 1.35)
		if won then
			Celebrate.confetti(root)
		end
		shownCount += 1
		local thisShow = shownCount
		task.delay(UITheme.motion.resultTime, function()
			if shownCount == thisShow then
				panel.Visible = false
			end
		end)
	end

	matchState:GetAttributeChangedSignal("Phase"):Connect(function()
		if matchState:GetAttribute("Phase") == Phase.Results then
			showResult()
		else
			panel.Visible = false
		end
	end)
end

return RoundResult
