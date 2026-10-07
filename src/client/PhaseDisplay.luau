-- Top-of-screen label: stage, round, phase and countdown, plus the opponent's name during Combat and
-- your result during Results. Creep and boss rounds are tagged and tinted; their Results text
-- includes the gold the fight earned. Presentation only: reads the server-owned MatchState
-- attributes and never writes them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Phase = require(Shared:WaitForChild("Phase"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))

local PhaseDisplay = {}

local function formatState(matchState: Instance): string
	local phase = matchState:GetAttribute("Phase")
	if phase == nil or phase == Phase.Waiting then
		return "Waiting for players..."
	end
	local remaining = math.max(0, math.ceil(matchState:GetAttribute("PhaseEndsAt") - workspace:GetServerTimeNow()))
	if phase == Phase.Lobby then
		return string.format("Match starts in %ds", remaining)
	elseif phase == Phase.MatchOver then
		return string.format("Winner: %s | next match in %ds", tostring(matchState:GetAttribute("Winner")), remaining)
	end

	local label = string.upper(phase)
	local own = matchState.Players:FindFirstChild(tostring(Players.LocalPlayer.UserId))
	if own and phase == Phase.Combat and own:GetAttribute("Opponent") ~= "" then
		label ..= " vs " .. tostring(own:GetAttribute("Opponent"))
	elseif own and phase == Phase.Results and own:GetAttribute("LastResult") ~= "" then
		label ..= ": " .. tostring(own:GetAttribute("LastResult"))
	end
	local kind = matchState:GetAttribute("RoundKind")
	local tag = if kind == "Creep" then " CREEP ROUND |" elseif kind == "Boss" then " BOSS ROUND |" else ""
	return string.format(
		"Stage %d - Round %d |%s %s | %ds",
		matchState:GetAttribute("Stage"),
		matchState:GetAttribute("Round"),
		tag,
		label,
		remaining
	)
end

-- Background tint: PvE rounds stand out from PvP rounds.
local function backgroundFor(matchState: Instance): Color3
	local kind = matchState:GetAttribute("RoundKind")
	local phase = matchState:GetAttribute("Phase")
	local inMatch = phase == Phase.Preparation or phase == Phase.Combat or phase == Phase.Results
	if inMatch and kind == "Creep" then
		return RenderConfig.creepRoundColor
	elseif inMatch and kind == "Boss" then
		return RenderConfig.bossRoundColor
	end
	return Color3.new(0, 0, 0)
end

function PhaseDisplay.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	matchState:WaitForChild("Players")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PhaseDisplay"
	screenGui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 8)
	label.Size = UDim2.fromOffset(680, 36)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.Parent = screenGui

	screenGui.Parent = playerGui

	RunService.RenderStepped:Connect(function()
		label.Text = formatState(matchState)
		label.BackgroundColor3 = backgroundFor(matchState)
	end)
end

return PhaseDisplay
