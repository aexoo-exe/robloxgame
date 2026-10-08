-- The top bar: stage and round ("2-3"), a tracker of the current stage's rounds (an icon per round
-- for creep, player and boss fights, the current one highlighted and past ones dimmed), the phase
-- and a countdown. Presentation only: reads the server-owned MatchState attributes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchRules = require(Shared:WaitForChild("MatchRules"))
local Phase = require(Shared:WaitForChild("Phase"))
local Pve = require(Shared:WaitForChild("Pve"))
local StageConfig = require(Shared:WaitForChild("StageConfig"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local UI = require(script.Parent.UI)

local TopBar = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local ICON_SIZE = 30
local OPEN_STAGE_ROUNDS = 4 -- rounds shown for the last, open-ended stage

-- The rounds of the stage that contains `round`.
local function stageRounds(round: number): { number }
	local stage = MatchRules.stage(round)
	local first = StageConfig.stages[stage].firstRound
	local nextStage = StageConfig.stages[stage + 1]
	local last = if nextStage then nextStage.firstRound - 1 else first + OPEN_STAGE_ROUNDS - 1
	local rounds = {}
	for r = first, last do
		table.insert(rounds, r)
	end
	return rounds
end

function TopBar.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local _, root = UI.screen("TopBar", 5)

	local bar = UI.panel(root, UDim2.fromOffset(0, SIZES.topBarHeight))
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 4)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 36)
	padding.Parent = bar
	local content = UI.row(bar, 12, UDim2.fromScale(0, 1))
	content.AutomaticSize = Enum.AutomaticSize.X

	local stageLabel = UI.text(content, "", SIZES.textLarge, FONTS.display, COLORS.gold)
	stageLabel.LayoutOrder = 1

	local tracker = UI.row(content, 4)
	tracker.LayoutOrder = 2

	local phaseChip = Instance.new("Frame")
	phaseChip.LayoutOrder = 3
	phaseChip.Size = UDim2.fromOffset(0, 32)
	phaseChip.AutomaticSize = Enum.AutomaticSize.X
	phaseChip.BorderSizePixel = 0
	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(0, 8)
	chipCorner.Parent = phaseChip
	local chipPadding = Instance.new("UIPadding")
	chipPadding.PaddingLeft = UDim.new(0, 10)
	chipPadding.PaddingRight = UDim.new(0, 10)
	chipPadding.Parent = phaseChip
	local phaseLabel = UI.text(phaseChip, "", SIZES.text + 2, FONTS.display)
	phaseLabel.Size = UDim2.fromScale(0, 1)
	phaseChip.Parent = content

	local timerRow = UI.row(content, 4)
	timerRow.LayoutOrder = 4
	UI.glyph(timerRow, UITheme.icons.timer, SIZES.text).LayoutOrder = 1
	local timerLabel = UI.text(timerRow, "", SIZES.textLarge, FONTS.number)
	timerLabel.LayoutOrder = 2

	local shownRound = -1
	local shownPhase = nil
	local shownSeconds = -1

	local function rebuildTracker(round: number)
		for _, child in tracker:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if round <= 0 then
			return
		end
		for order, r in stageRounds(round) do
			local kind = UITheme.roundKinds[Pve.roundKind(r)]
			local icon = Instance.new("Frame")
			icon.LayoutOrder = order
			icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
			icon.BackgroundColor3 = kind.color
			icon.BackgroundTransparency = if r < round then 0.6 else 0
			icon.BorderSizePixel = 0
			local iconCorner = Instance.new("UICorner")
			iconCorner.CornerRadius = UDim.new(0, 8)
			iconCorner.Parent = icon
			local iconStroke = Instance.new("UIStroke")
			iconStroke.Color = if r == round then COLORS.gold else COLORS.outline
			iconStroke.Thickness = if r == round then 3 else 2
			iconStroke.Parent = icon
			local glyph = UI.glyph(icon, kind.glyph, 16)
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.5)
			glyph.TextTransparency = if r < round then 0.5 else 0
			icon.Parent = tracker
			if r == round then
				UI.pop(icon)
			end
		end
	end

	RunService.RenderStepped:Connect(function()
		local phase = matchState:GetAttribute("Phase") or Phase.Waiting
		local round = matchState:GetAttribute("Round") or 0
		if round ~= shownRound then
			shownRound = round
			rebuildTracker(round)
			stageLabel.Text = if round > 0 then string.format("%d-%d", matchState:GetAttribute("Stage"), round) else ""
			stageLabel.Visible = round > 0
		end
		if phase ~= shownPhase then
			shownPhase = phase
			local style = UITheme.phases[phase] or UITheme.phases.Waiting
			phaseLabel.Text = style.text
			phaseChip.BackgroundColor3 = style.color
			UI.pop(phaseChip)
		end
		local endsAt = matchState:GetAttribute("PhaseEndsAt") or 0
		local seconds = if endsAt > 0 then math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow())) else -1
		if seconds ~= shownSeconds then
			shownSeconds = seconds
			timerRow.Visible = seconds >= 0
			timerLabel.Text = tostring(seconds)
			timerLabel.TextColor3 = if seconds <= 5 and seconds >= 0 then COLORS.loss else COLORS.text
		end
	end)
end

return TopBar
