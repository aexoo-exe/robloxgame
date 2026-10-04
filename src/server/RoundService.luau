-- Server-authoritative match loop:
--   Waiting -> Lobby countdown -> rounds of Preparation -> Combat -> Results -> MatchOver -> Lobby
-- Players present when the lobby countdown ends (up to MatchConfig.maxPlayers) are the match's
-- participants; later joiners spectate until the next match. A single participant plays a
-- practice match against the scripted enemy boards.
--
-- Public match state, replicated to every client (server-to-client only):
--   ReplicatedStorage.MatchState attributes
--     Phase        string  current phase (see Shared.Phase)
--     PhaseEndsAt  number  workspace:GetServerTimeNow() when the phase ends (0 if untimed)
--     Round        number  current round (0 before the first)
--     Stage        number  stage of the current round
--     Winner       string  winner's name once the match is over, else ""
--   MatchState.Players: one Folder per participant, named by UserId, with attributes
--     UserId, DisplayName, Health, Placement (0 until placed), Eliminated, Connected,
--     Opponent (name during Combat, else ""), LastResult (text shown at Results)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Match = require(ReplicatedStorage.Shared.Match)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local MatchRules = require(ReplicatedStorage.Shared.MatchRules)
local Phase = require(ReplicatedStorage.Shared.Phase)

local CombatService = require(script.Parent.CombatService)
local PlayerService = require(script.Parent.PlayerService)

local RoundService = {}

local matchState: Folder
local playersFolder: Folder
local currentMatch: Match.Match? = nil
local started = false
local seedRandom = Random.new()

local function setPhase(phase: string, duration: number?)
	local endsAt = if duration then workspace:GetServerTimeNow() + duration else 0
	matchState:SetAttribute("PhaseEndsAt", endsAt)
	matchState:SetAttribute("Phase", phase)
	print(string.format("[RoundService] Round %d: %s", matchState:GetAttribute("Round"), phase))
end

local function playerFolder(userId: number): Folder?
	return playersFolder:FindFirstChild(tostring(userId)) :: Folder?
end

-- Copies each participant's HP, placement and connection from the match into the public state.
local function publishPlayers(match: Match.Match)
	for userId, player in match.players do
		local folder = playerFolder(userId)
		if folder then
			folder:SetAttribute("Health", player.health)
			folder:SetAttribute("Placement", player.placement or 0)
			folder:SetAttribute("Eliminated", player.eliminated)
			folder:SetAttribute("Connected", player.connected)
		end
	end
end

local function setPlayerAttribute(userId: number, name: string, value: any)
	local folder = playerFolder(userId)
	if folder then
		folder:SetAttribute(name, value)
	end
end

local function hasEnoughPlayers(): boolean
	return #Players:GetPlayers() >= MatchConfig.minPlayersToStart
end

-- Waits until enough players are present and the lobby countdown completes without dropping
-- below the minimum.
local function runLobby()
	while true do
		if not hasEnoughPlayers() then
			setPhase(Phase.Waiting)
			repeat
				Players.PlayerAdded:Wait()
			until hasEnoughPlayers()
		end
		setPhase(Phase.Lobby, MatchConfig.lobbyCountdown)
		local endsAt = matchState:GetAttribute("PhaseEndsAt")
		while workspace:GetServerTimeNow() < endsAt and hasEnoughPlayers() do
			task.wait(0.25)
		end
		if hasEnoughPlayers() then
			return
		end
	end
end

local function resultText(outcome: string?, damage: number?): string
	if outcome == Economy.Outcome.Win then
		return "Won"
	elseif outcome == Economy.Outcome.Draw then
		return "Draw"
	elseif outcome == Economy.Outcome.Loss then
		return string.format("Lost, -%d HP", damage or 0)
	end
	return ""
end

local function playRound(match: Match.Match, names: { [number]: string })
	local round = match.round + 1
	matchState:SetAttribute("Round", round)
	matchState:SetAttribute("Stage", MatchRules.stage(round))
	for userId in match.players do
		setPlayerAttribute(userId, "Opponent", "")
		setPlayerAttribute(userId, "LastResult", "")
	end

	setPhase(Phase.Preparation, MatchConfig.preparationDuration)
	PlayerService.beginPreparation()
	task.wait(MatchConfig.preparationDuration)

	-- Every fight is simulated instantly; the Combat phase lasts as long as the longest playback.
	local fights = Match.startRound(match)
	local combatDuration, results, opponents = CombatService.runRound(fights, PlayerService.lockBoards(), round, names)
	for userId, opponentName in opponents do
		setPlayerAttribute(userId, "Opponent", opponentName)
	end
	setPhase(Phase.Combat, combatDuration)
	task.wait(combatDuration)

	local summary = Match.applyResults(match, results)
	PlayerService.recordOutcomes(summary.outcomes)
	for userId, outcome in summary.outcomes do
		setPlayerAttribute(userId, "LastResult", resultText(outcome, summary.damage[userId]))
	end
	for _, userId in summary.eliminated do
		PlayerService.eliminate(userId)
		local placement = match.players[userId].placement
		setPlayerAttribute(userId, "LastResult", string.format("Eliminated - #%d", placement or 0))
		print(string.format("[RoundService] %s eliminated, placement %d", names[userId], placement or 0))
	end
	publishPlayers(match)

	setPhase(Phase.Results, MatchConfig.resultsDuration)
	task.wait(MatchConfig.resultsDuration)
end

local function playMatch()
	local participants = {}
	local names = {}
	for _, player in Players:GetPlayers() do
		if #participants < MatchConfig.maxPlayers then
			table.insert(participants, player.UserId)
			names[player.UserId] = player.Name
		end
	end

	local match = Match.new(participants, seedRandom:NextInteger(1, 2 ^ 31 - 2))
	currentMatch = match
	playersFolder:ClearAllChildren()
	for _, userId in participants do
		local folder = Instance.new("Folder")
		folder.Name = tostring(userId)
		folder:SetAttribute("UserId", userId)
		folder:SetAttribute("DisplayName", names[userId])
		folder:SetAttribute("Opponent", "")
		folder:SetAttribute("LastResult", "")
		folder.Parent = playersFolder
	end
	publishPlayers(match)
	matchState:SetAttribute("Winner", "")
	matchState:SetAttribute("Round", 0)
	matchState:SetAttribute("Stage", 1)
	PlayerService.startMatch(participants)
	print(string.format("[RoundService] Match started with %d player(s)", #participants))

	while not match.finished do
		playRound(match, names)
	end

	local winner = if match.winner then names[match.winner] else ""
	matchState:SetAttribute("Winner", winner)
	print(string.format("[RoundService] Match over after %d rounds; winner %s", match.round, winner))
	setPhase(Phase.MatchOver, MatchConfig.finalPlacementsDuration)
	task.wait(MatchConfig.finalPlacementsDuration)

	currentMatch = nil
	PlayerService.endMatch()
	playersFolder:ClearAllChildren()
	matchState:SetAttribute("Round", 0)
	matchState:SetAttribute("Winner", "")
end

-- Tracks participants leaving and rejoining; the match keeps their state for the grace period.
local function onConnectionChanged(player: Player, connected: boolean)
	local match = currentMatch
	if match and match.players[player.UserId] then
		Match.setConnected(match, player.UserId, connected)
		setPlayerAttribute(player.UserId, "Connected", connected)
	end
end

function RoundService.start()
	assert(not started, "RoundService.start called more than once")
	started = true

	matchState = Instance.new("Folder")
	matchState.Name = "MatchState"
	matchState:SetAttribute("Round", 0)
	matchState:SetAttribute("Stage", 1)
	matchState:SetAttribute("Phase", Phase.Waiting)
	matchState:SetAttribute("PhaseEndsAt", 0)
	matchState:SetAttribute("Winner", "")
	playersFolder = Instance.new("Folder")
	playersFolder.Name = "Players"
	playersFolder.Parent = matchState
	matchState.Parent = ReplicatedStorage

	Players.PlayerAdded:Connect(function(player)
		onConnectionChanged(player, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		onConnectionChanged(player, false)
	end)

	task.spawn(function()
		while true do
			runLobby()
			playMatch()
		end
	end)
end

return RoundService
