-- Server-authoritative match loop:
--   Waiting -> Intro -> rounds of Preparation -> Combat -> Results -> MatchOver -> Waiting
-- One match runs at a time. HubService starts it (RoundService.startMatch) with the players who
-- queued on the hub's Play pad, or one player from the Practice pad; everyone else stays in the
-- hub until it ends. A single participant plays a practice match against the scripted enemy
-- boards. RoundService.onMatchEnded callbacks run once the final placements have been shown.
-- A Play-pad match with fewer than MatchConfig.botFillTo players gets bot opponents in the empty
-- seats (BotService; MatchConfig.botsEnabled). Once no human is left in it (all eliminated), the
-- match ends at once and the bots still in it are placed by HP (Match.finishNow).
--
-- Public match state, replicated to every client (server-to-client only):
--   ReplicatedStorage.MatchState attributes
--     Phase        string  current phase (see Shared.Phase)
--     PhaseEndsAt  number  workspace:GetServerTimeNow() when the phase ends (0 if untimed)
--     Round        number  current round (0 before the first)
--     Stage        number  stage of the current round
--     RoundKind    string  "Creep", "Boss" or "PvP" (Pve.Kind) for the current round
--     Winner       string  winner's name once the match is over, else ""
--     Practice     boolean the running match is a solo practice match its player may leave anytime
--   MatchState.Players: one Folder per participant, named by UserId, with attributes
--     UserId, DisplayName, IsBot, Health, Placement (0 until placed), Eliminated, Connected,
--     Opponent (name during Combat, else ""), LastResult (text shown at Results),
--     LastOutcome (Economy.Outcome of the round's fight, "" before Results; PvE fights are a Win
--     when the side won), LastDamage (HP lost this round, 0 if none),
--     LastGold (gold the round's PvE fight earned, shown at Results; 0 otherwise)
--
-- PvE rounds (Pve.roundKind) use the match's theme; round 1 has no Preparation, and every player
-- starts with PveConfig.startingUnits on the board. PvE rewards are paid at Results.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Items = require(ReplicatedStorage.Shared.Items)
local Match = require(ReplicatedStorage.Shared.Match)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local MatchRules = require(ReplicatedStorage.Shared.MatchRules)
local Phase = require(ReplicatedStorage.Shared.Phase)
local Pve = require(ReplicatedStorage.Shared.Pve)
local RemoteNames = require(ReplicatedStorage.Shared.RemoteNames)

local BotService = require(script.Parent.BotService)
local CombatService = require(script.Parent.CombatService)
local ErrorLog = require(script.Parent.ErrorLog)
local PlayerService = require(script.Parent.PlayerService)
local Remotes = require(script.Parent.Remotes)

local RoundService = {}

local matchState: Folder
local playersFolder: Folder
local currentMatch: Match.Match? = nil
local running = false -- from startMatch until the onMatchEnded callbacks have run
local practice = false -- the running match is a solo practice match (started from the Practice pad)
local stopRequested = false -- the practice player asked to leave: the match ends at once
local started = false
local seedRandom = Random.new()
local endedCallbacks: { ({ number }) -> () } = {}
-- The running or latest match, kept after it ends for the playtest feedback (RoundService.summaryOf).
local lastSync: { [number]: number } = {} -- UserId -> os.clock() of their last RequestMatchSync
local lastMatch: Match.Match? = nil
local lastMatchInfo = { id = 0, startedAt = 0, endedAt = 0, practice = false, bots = 0 }

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

-- Waits `seconds`, or less if the practice player asks to leave (RoundService.leavePractice).
local function pause(seconds: number)
	local endsAt = os.clock() + seconds
	while os.clock() < endsAt and not stopRequested do
		task.wait(math.min(0.1, endsAt - os.clock()))
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
		setPlayerAttribute(userId, "LastOutcome", "")
		setPlayerAttribute(userId, "LastDamage", 0)
		setPlayerAttribute(userId, "LastGold", 0)
	end

	-- Creep, boss or PvP (Pve.roundKind); PvE rounds can have their own Preparation time, and 0
	-- skips Preparation (round 1: the starting unit is already on the board).
	matchState:SetAttribute("RoundKind", Pve.roundKind(round))
	local preparation = Pve.preparationDuration(round)
	if preparation > 0 then
		setPhase(Phase.Preparation, preparation)
		PlayerService.beginPreparation()
		BotService.playPreparation()
		pause(preparation)
		if stopRequested then
			return
		end
	end

	-- Every fight is simulated instantly; the Combat phase lasts as long as the longest playback.
	local fights = Match.startRound(match)
	local combatDuration, results, opponents =
		CombatService.runRound(fights, PlayerService.lockBoards(), round, names, match.theme)
	for userId, opponentName in opponents do
		setPlayerAttribute(userId, "Opponent", opponentName)
	end
	setPhase(Phase.Combat, combatDuration)
	pause(combatDuration)
	if stopRequested then
		return
	end
	PlayerService.endCombat()

	local summary = Match.applyResults(match, results)
	PlayerService.recordOutcomes(summary.outcomes)
	PlayerService.grantTraitGold(summary.traitGold)
	for userId, outcome in summary.outcomes do
		local text = resultText(outcome, summary.damage[userId])
		local crewGold = summary.traitGold[userId]
		if crewGold then
			text ..= string.format(", +%d gold (Crew)", crewGold)
		end
		setPlayerAttribute(userId, "LastResult", text)
		setPlayerAttribute(userId, "LastOutcome", outcome)
		setPlayerAttribute(userId, "LastDamage", summary.damage[userId] or 0)
	end
	PlayerService.recordPve(summary.pve)
	local pveWinners = {}
	for _, result in results do
		if result.fight.pve and result.winner == 1 then
			pveWinners[result.fight.a] = true
		end
	end
	for userId, reward in summary.pve do
		local damage = summary.damage[userId]
		local text = Pve.resultText(reward) .. (if damage and damage > 0 then string.format(", -%d HP", damage) else "")
		setPlayerAttribute(userId, "LastResult", text)
		setPlayerAttribute(userId, "LastGold", reward.gold)
		setPlayerAttribute(
			userId,
			"LastOutcome",
			if pveWinners[userId] then Economy.Outcome.Win else Economy.Outcome.Loss
		)
		setPlayerAttribute(userId, "LastDamage", damage or 0)
	end
	for _, userId in summary.eliminated do
		PlayerService.eliminate(userId)
		local placement = match.players[userId].placement
		setPlayerAttribute(userId, "LastResult", string.format("Eliminated - #%d", placement or 0))
		print(string.format("[RoundService] %s eliminated, placement %d", names[userId], placement or 0))
	end
	publishPlayers(match)
	-- Item choices after the round-3 creep fight and every boss fight, won or not (ItemConfig.offers).
	local offer = Items.offerSize(round)
	if offer > 0 and not match.finished then
		PlayerService.offerItems(offer)
	end

	setPhase(Phase.Results, MatchConfig.resultsDuration)
	pause(MatchConfig.resultsDuration)
end

-- True while a human participant (not a bot) is still in the match, connected or not.
local function humanLeft(match: Match.Match): boolean
	for userId, player in match.players do
		if not player.eliminated and not BotService.isBot(userId) then
			return true
		end
	end
	return false
end

local function playMatch(participants: { number }, names: { [number]: string })
	local match = Match.new(participants, seedRandom:NextInteger(1, 2 ^ 31 - 2))
	currentMatch = match
	lastMatch = match
	local bots = 0
	for _, userId in participants do
		if BotService.isBot(userId) then
			bots += 1
		end
	end
	lastMatchInfo = { id = lastMatchInfo.id + 1, startedAt = os.time(), endedAt = 0, practice = practice, bots = bots }
	playersFolder:ClearAllChildren()
	for _, userId in participants do
		local folder = Instance.new("Folder")
		folder.Name = tostring(userId)
		folder:SetAttribute("UserId", userId)
		folder:SetAttribute("DisplayName", names[userId])
		folder:SetAttribute("IsBot", BotService.isBot(userId))
		folder:SetAttribute("Opponent", "")
		folder:SetAttribute("LastResult", "")
		folder:SetAttribute("LastOutcome", "")
		folder:SetAttribute("LastDamage", 0)
		folder:SetAttribute("LastGold", 0)
		folder.Parent = playersFolder
	end
	publishPlayers(match)
	matchState:SetAttribute("Winner", "")
	matchState:SetAttribute("Round", 0)
	matchState:SetAttribute("Stage", 1)
	PlayerService.startMatch(participants)
	print(string.format("[RoundService] Match started with %d player(s)", #participants))

	-- The intro: starting units are already on the boards; round 1 starts when it ends.
	setPhase(Phase.Intro, MatchConfig.introDuration)
	pause(MatchConfig.introDuration)

	while not match.finished and not stopRequested do
		playRound(match, names)
		if not match.finished and not stopRequested and not humanLeft(match) then
			Match.finishNow(match)
			publishPlayers(match)
			print("[RoundService] No human left in the match: the bots are placed by HP")
		end
	end
	PlayerService.closeRequests()
	lastMatchInfo.endedAt = os.time()

	if stopRequested then
		-- The practice player left: no final placements, straight back to waiting.
		print(string.format("[RoundService] Practice match left after %d rounds", match.round))
	else
		local winner = if match.winner then names[match.winner] else ""
		matchState:SetAttribute("Winner", winner)
		print(string.format("[RoundService] Match over after %d rounds; winner %s", match.round, winner))
		setPhase(Phase.MatchOver, MatchConfig.finalPlacementsDuration)
		task.wait(MatchConfig.finalPlacementsDuration)
	end

	currentMatch = nil
	PlayerService.endMatch()
	CombatService.clearRound()
	playersFolder:ClearAllChildren()
	matchState:SetAttribute("Round", 0)
	matchState:SetAttribute("Winner", "")
	setPhase(Phase.Waiting)
end

-- The playtest summary of `userId`'s running or latest match, or nil if they were not in it:
-- match id, placement (0 while still playing), rounds played, duration in seconds so far, whether
-- it was a practice match, how many bots and participants it had, and whether it is over.
function RoundService.summaryOf(userId: number): { [string]: any }?
	local match = lastMatch
	local player = match and match.players[userId]
	if not match or not player then
		return nil
	end
	local participants = 0
	for _ in match.players do
		participants += 1
	end
	local info = lastMatchInfo
	local endedAt = if info.endedAt > 0 then info.endedAt else os.time()
	return {
		matchId = info.id,
		placement = player.placement or 0,
		rounds = match.round,
		durationSeconds = endedAt - info.startedAt,
		practice = info.practice,
		bots = info.bots,
		participants = participants,
		over = match.finished,
	}
end

-- True from RoundService.startMatch until the match's onMatchEnded callbacks have run.
function RoundService.isRunning(): boolean
	return running
end

-- True if `userId` is in the running match and has been knocked out, or the match is decided
-- (final placements are showing): they may leave for the hub.
function RoundService.canLeave(userId: number): boolean
	local match = currentMatch
	if not match or not match.players[userId] then
		return false
	end
	return match.finished or match.players[userId].eliminated
end

-- True if `userId` is the player of the running practice match, which they may leave at any time.
-- Never true in a player match.
function RoundService.canLeavePractice(userId: number): boolean
	local match = currentMatch
	return practice and match ~= nil and match.players[userId] ~= nil and not stopRequested
end

-- Ends the running practice match at once if `userId` is its player (RoundService.canLeavePractice);
-- refused (false) otherwise, including from any player match. The match's onMatchEnded callbacks
-- run as usual right after.
function RoundService.leavePractice(userId: number): boolean
	if not RoundService.canLeavePractice(userId) then
		return false
	end
	stopRequested = true
	return true
end

-- Starts a match with these players (at most MatchConfig.maxPlayers; extra ones are left out).
-- `isPractice` marks a solo practice match from the Practice pad, which its player may leave at
-- any time (MatchState attribute Practice). Returns the participants' UserIds (bots included,
-- see BotService.isBot), or nil if a match is already running or nobody is given.
function RoundService.startMatch(players: { Player }, isPractice: boolean?): { number }?
	if running or #players == 0 then
		return nil
	end
	practice = isPractice == true
	stopRequested = false
	matchState:SetAttribute("Practice", practice)
	local participants = {}
	local names = {}
	for _, player in players do
		if #participants < MatchConfig.maxPlayers and not names[player.UserId] then
			table.insert(participants, player.UserId)
			names[player.UserId] = player.Name
		end
	end
	-- Bots fill the empty seats of a Play-pad match (never a practice match).
	local fillTo = math.min(MatchConfig.botFillTo, MatchConfig.maxPlayers)
	if MatchConfig.botsEnabled and not practice and #participants < fillTo then
		local botIds, botNames = BotService.create(fillTo - #participants)
		for _, botId in botIds do
			table.insert(participants, botId)
			names[botId] = botNames[botId]
		end
		print(string.format("[RoundService] %d bot(s) fill the empty seats", #botIds))
	else
		BotService.clear()
	end
	running = true
	task.spawn(function()
		local ok = ErrorLog.call("match loop", playMatch, participants, names)
		if not ok then
			-- Never leave players stuck out of the hub if the match loop fails.
			warn("[RoundService] Match ended with an error (see ErrorLog)")
			lastMatchInfo.endedAt = os.time()
			currentMatch = nil
			PlayerService.endMatch()
			CombatService.clearRound()
			playersFolder:ClearAllChildren()
			setPhase(Phase.Waiting)
		end
		BotService.clear()
		practice = false
		stopRequested = false
		matchState:SetAttribute("Practice", false)
		running = false
		for _, callback in endedCallbacks do
			task.spawn(callback, participants)
		end
	end)
	return participants
end

-- Calls `callback(participantUserIds)` after each match, once the final placements are over.
function RoundService.onMatchEnded(callback: ({ number }) -> ())
	table.insert(endedCallbacks, callback)
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
	matchState:SetAttribute("RoundKind", Pve.Kind.PvP)
	matchState:SetAttribute("Phase", Phase.Waiting)
	matchState:SetAttribute("PhaseEndsAt", 0)
	matchState:SetAttribute("Winner", "")
	matchState:SetAttribute("Practice", false)
	playersFolder = Instance.new("Folder")
	playersFolder.Name = "Players"
	playersFolder.Parent = matchState
	matchState.Parent = ReplicatedStorage

	Players.PlayerAdded:Connect(function(player)
		onConnectionChanged(player, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		onConnectionChanged(player, false)
		lastSync[player.UserId] = nil
	end)

	-- A client asks for its match state once it has started (RemoteNames.RequestMatchSync): a
	-- participant who rejoined gets their board and shop, and during Combat this round's fight.
	Remotes.create(RemoteNames.RequestMatchSync).OnServerEvent:Connect(function(player: Player)
		local match = currentMatch
		local now = os.clock()
		if not match or not match.players[player.UserId] or now - (lastSync[player.UserId] or -math.huge) < 2 then
			return
		end
		lastSync[player.UserId] = now
		PlayerService.resend(player.UserId)
		if matchState:GetAttribute("Phase") == Phase.Combat then
			CombatService.resend(player.UserId)
		end
	end)
end

return RoundService
