-- The post-match summary (MatchRewards from RetentionService), shown once the player is back in
-- the hub: the placement, the account XP gained with the bar filling (through every level reached,
-- each a "LEVEL N!" moment with its reward), coins, the quests that moved (a tick on a completed
-- one) and the units' mastery gains. CONTINUE closes it; it never blocks walking. A summary that
-- arrives during the match (knocked out early) waits for the hub. Presentation only: the server
-- granted everything already.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local UI = require(script.Parent.UI)

local PostMatchSummary = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local WIDTH = 380
local FILL_SECONDS = 0.6 -- per stretch of the XP bar
local MAX_QUESTS = 6
local MAX_MASTERY = 5

local function unitName(unitType: string): string
	local skin = SkinConfig[unitType]
	return if skin then skin.name else unitType
end

local function placementText(summary): string
	if summary.leftEarly then
		return "Left early"
	elseif summary.practice then
		return "Practice"
	elseif summary.placement and summary.placement > 0 then
		return string.format("#%d place", summary.placement)
	end
	return "Match over"
end

function PostMatchSummary.start()
	local localPlayer = Players.LocalPlayer
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local _, root = UI.screen("PostMatchSummary", 13, true)
	local panel = UI.panel(root, UDim2.fromOffset(WIDTH, 0))
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.45)
	panel.Visible = false
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	UI.padding(content, 14)
	UI.list(content, 8, Enum.HorizontalAlignment.Center)
	content.Parent = panel

	local title = UI.text(content, "", SIZES.textLarge + 6, FONTS.display, COLORS.gold)
	title.LayoutOrder = 1

	-- The XP bar: "Level N", the bar, "+X XP".
	local levelLabel = UI.text(content, "", SIZES.text + 2, FONTS.display)
	levelLabel.LayoutOrder = 2
	local bar = UI.bar(content, UDim2.fromOffset(WIDTH - 40, 12), COLORS.xp)
	bar.frame.LayoutOrder = 3
	local gainLabel = UI.text(content, "", SIZES.text, FONTS.number, COLORS.textDim)
	gainLabel.LayoutOrder = 4
	local levelUp = UI.text(content, "", SIZES.textLarge + 2, FONTS.display, COLORS.gold)
	levelUp.LayoutOrder = 5
	levelUp.Visible = false

	local lines = Instance.new("Frame")
	lines.LayoutOrder = 6
	lines.BackgroundTransparency = 1
	lines.Size = UDim2.fromOffset(WIDTH - 28, 0)
	lines.AutomaticSize = Enum.AutomaticSize.Y
	UI.list(lines, 3)
	lines.Parent = content

	local continueButton = UI.button(content, COLORS.buy, UDim2.fromOffset(160, UI.touchSize(42)))
	continueButton.LayoutOrder = 7
	local continueLabel = UI.text(continueButton, "CONTINUE", SIZES.text + 2, FONTS.display)
	continueLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	continueLabel.Position = UDim2.fromScale(0.5, 0.5)

	local function line(text: string, color: Color3?)
		local label = UI.text(lines, text, SIZES.textSmall + 1, FONTS.body, color or COLORS.text)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.fromScale(1, 0)
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = #lines:GetChildren()
	end

	local showing = 0 -- bumped per summary shown, so an old animation stops

	-- Fills the bar from the old level and XP to the new one, one level at a time.
	local function animateXp(summary, token: number)
		local level, xp = summary.before.level, summary.before.xp
		levelLabel.Text = "Level " .. level
		UI.setBar(bar, xp / Progression.xpToNext(level), false)
		local reached = {}
		for _, step in summary.levelsReached or {} do
			reached[step.level] = step
		end
		task.spawn(function()
			task.wait(0.3)
			while showing == token and level < summary.after.level do
				UI.setBar(bar, 1, true)
				task.wait(FILL_SECONDS)
				if showing ~= token then
					return
				end
				level += 1
				levelLabel.Text = "Level " .. level
				local step = reached[level]
				local rewards = {}
				if step then
					if step.coins and step.coins > 0 then
						table.insert(rewards, string.format("+%d coins", step.coins))
					end
					if step.title then
						table.insert(rewards, "title: " .. step.title)
					end
					if step.cosmetic then
						table.insert(rewards, "new cosmetic")
					end
				end
				levelUp.Text = string.format(
					"LEVEL %d!%s",
					level,
					if #rewards > 0 then "  " .. table.concat(rewards, ", ") else ""
				)
				levelUp.Visible = true
				UI.pop(levelUp, 1.3)
				UI.setBar(bar, 0, false)
			end
			if showing == token then
				UI.setBar(bar, summary.after.xp / Progression.xpToNext(summary.after.level), true)
			end
		end)
	end

	local function show(summary)
		showing += 1
		local token = showing
		for _, child in lines:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		title.Text = placementText(summary)
		gainLabel.Text = string.format(
			"+%d XP%s",
			summary.xp or 0,
			if (summary.coins or 0) > 0 then string.format("   +%d coins", summary.coins) else ""
		)
		levelUp.Visible = false
		for index, quest in summary.quests or {} do
			if index > MAX_QUESTS then
				break
			end
			if quest.completed then
				line(
					string.format("✓ %s  (%d/%d) - claim it in your profile", quest.text, quest.after, quest.target),
					COLORS.gold
				)
			else
				line(string.format("• %s  %d → %d/%d", quest.text, quest.before, quest.after, quest.target))
			end
		end
		for index, gain in summary.mastery or {} do
			if index > MAX_MASTERY then
				break
			end
			local up = gain.level > gain.levelBefore
			line(
				string.format(
					"%s  +%d mastery%s",
					unitName(gain.unit),
					gain.xp,
					if up then string.format("  MASTERY %d!", gain.level) else ""
				),
				if up then COLORS.gold else COLORS.textDim
			)
		end
		panel.Visible = true
		UI.pop(panel, 1.06)
		animateXp(summary, token)
	end

	local pending = nil
	local function inHub(): boolean
		return localPlayer:GetAttribute("InMatch") ~= true
	end
	remotes:WaitForChild(RemoteNames.MatchRewards).OnClientEvent:Connect(function(summary)
		if inHub() then
			show(summary)
		else
			pending = summary
		end
	end)
	localPlayer:GetAttributeChangedSignal("InMatch"):Connect(function()
		if inHub() and pending then
			local summary = pending
			pending = nil
			show(summary)
		elseif not inHub() then
			panel.Visible = false
		end
	end)
	continueButton.Activated:Connect(function()
		showing += 1
		panel.Visible = false
	end)
end

return PostMatchSummary
