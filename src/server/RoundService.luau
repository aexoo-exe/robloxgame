-- Server-authoritative round loop: Preparation -> Combat -> Results -> repeat.
--
-- State is published as attributes on ReplicatedStorage.MatchState, which
-- replicate from server to client only:
--   Phase        string  current phase (see Shared.Phase)
--   PhaseEndsAt  number  workspace:GetServerTimeNow() when the phase ends (0 if untimed)
--   Round        number  current round, starting at 1
--   LastResult   string  result of the most recent combat

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Phase = require(ReplicatedStorage.Shared.Phase)

local RoundService = {}

local matchState: Folder
local started = false

local function setPhase(phase: string, duration: number?)
	local endsAt = if duration then workspace:GetServerTimeNow() + duration else 0
	matchState:SetAttribute("PhaseEndsAt", endsAt)
	matchState:SetAttribute("Phase", phase)
	print(string.format("[RoundService] Round %d: %s", matchState:GetAttribute("Round"), phase))
end

local function hasEnoughPlayers(): boolean
	return #Players:GetPlayers() >= MatchConfig.minPlayersToStart
end

-- Placeholder until units exist: combat always runs to the time limit and ends in a draw.
-- Real combat replaces this function and may return early once a winner is decided.
local function runCombat(): string
	task.wait(MatchConfig.combatMaxDuration)
	return "Draw"
end

local function runLoop()
	while true do
		if not hasEnoughPlayers() then
			setPhase(Phase.Waiting)
			repeat
				Players.PlayerAdded:Wait()
			until hasEnoughPlayers()
		end

		matchState:SetAttribute("Round", matchState:GetAttribute("Round") + 1)

		setPhase(Phase.Preparation, MatchConfig.preparationDuration)
		task.wait(MatchConfig.preparationDuration)

		setPhase(Phase.Combat, MatchConfig.combatMaxDuration)
		local result = runCombat()
		matchState:SetAttribute("LastResult", result)

		setPhase(Phase.Results, MatchConfig.resultsDuration)
		task.wait(MatchConfig.resultsDuration)
	end
end

function RoundService.start()
	assert(not started, "RoundService.start called more than once")
	started = true

	matchState = Instance.new("Folder")
	matchState.Name = "MatchState"
	matchState:SetAttribute("Round", 0)
	matchState:SetAttribute("Phase", Phase.Waiting)
	matchState:SetAttribute("PhaseEndsAt", 0)
	matchState.Parent = ReplicatedStorage

	task.spawn(runLoop)
end

return RoundService
