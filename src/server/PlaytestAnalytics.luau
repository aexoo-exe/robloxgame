-- Playtest analytics (docs/playtest.md, "What gets tracked"). Two outputs:
--   * Roblox AnalyticsService (Creator Dashboard > Analytics), live servers only (skipped in
--     Studio), every call wrapped in pcall:
--       onboarding funnel  MatchLog.FUNNEL steps 1-7: joined, intro_finished, queued,
--                          first_match_started, round_5_reached, match_finished, feedback_sent
--       progression        path "Match": start at round 1, complete per round survived, fail at
--                          the round a player is knocked out
--       custom events      unit_bought, unit_sold, star_up (field 1: unit id, value: star),
--                          trait_active (field 1: trait, value: level; once per player, trait and
--                          level per match), reroll, level_up (value: level)
--   * Our own match log (MatchLog): one record per match with every human's numbers, saved to the
--     PlaytestMatches DataStore (key "recent", the newest MAX_MATCHES), with per-unit totals (key
--     "units") and first-time funnel counts (key "funnel"), batched every FLUSH_SECONDS and on
--     shutdown. Funnel steps count once per player ever: the steps a player has reached are kept on
--     their PlayerFlags entry ("funnel").
-- Humans only: bots are not logged. Nothing personal beyond the UserId; feedback text is filtered
-- by PlaytestService. Read it with scripts/playtest-report.luau.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local MatchLog = require(ReplicatedStorage.Shared.MatchLog)
local RemoteNames = require(ReplicatedStorage.Shared.RemoteNames)
local Traits = require(ReplicatedStorage.Shared.Traits)
local UnitConfig = require(ReplicatedStorage.Shared.UnitConfig)

local ErrorLog = require(script.Parent.ErrorLog)
local PlaytestStore = require(script.Parent.PlaytestStore)

local PlaytestAnalytics = {}

local MAX_MATCHES = 500
local FLUSH_SECONDS = 60
local PROGRESSION_PATH = "Match"
local LIVE = not RunService:IsStudio() -- AnalyticsService only on live servers

local FUNNEL_STEP: { [string]: number } = {}
for index, name in MatchLog.FUNNEL do
	FUNNEL_STEP[name] = index
end

-- Funnel steps each player has reached (loaded from PlayerFlags, then kept for the session).
local reached: { [number]: { [string]: boolean } } = {}
local log: MatchLog.Log? = nil
local logged: { [number]: boolean } = {} -- humans in the running match
local traitsSeen: { [number]: { [string]: boolean } } = {} -- "Trait:level" already reported
local pendingMatches: { any } = {}
local pendingUnits: { [string]: any } = {}
local pendingFunnel: { [string]: number } = {}
local started = false

local function flagKey(userId: number): string
	return "u" .. tostring(userId)
end

local function customFields(field1: string?): { [string]: any }?
	if not field1 then
		return nil
	end
	return { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = field1 }
end

-- Calls an AnalyticsService method for `userId` (live servers only, the player still here).
local function analytics(userId: number, method: string, ...: any)
	if not LIVE then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	local args = table.pack(...)
	local ok, err = pcall(function()
		(AnalyticsService :: any)[method](AnalyticsService, player, table.unpack(args, 1, args.n))
	end)
	if not ok then
		warn(string.format("[PlaytestAnalytics] %s failed: %s", method, tostring(err)))
	end
end

local function custom(userId: number, name: string, value: number?, field1: string?)
	analytics(userId, "LogCustomEvent", name, value or 1, customFields(field1))
end

-- A funnel step for `player`, counted once per player ever (PlayerFlags "funnel").
function PlaytestAnalytics.funnel(player: Player, name: string)
	local step = FUNNEL_STEP[name]
	local userId = player.UserId
	local steps = reached[userId] or {}
	reached[userId] = steps
	if not step or steps[name] then
		return
	end
	steps[name] = true
	analytics(userId, "LogOnboardingFunnelStepEvent", step, name)
	if userId <= 0 then
		return -- Studio's test players: not counted
	end
	task.spawn(function()
		local firstTime = false
		PlaytestStore.update(PlaytestStore.PLAYER_FLAGS, flagKey(userId), function(old)
			local flags = if type(old) == "table" then old else {}
			flags.funnel = if type(flags.funnel) == "table" then flags.funnel else {}
			firstTime = flags.funnel[name] ~= true
			if not firstTime then
				return nil
			end
			flags.funnel[name] = true
			return flags
		end)
		if firstTime then
			pendingFunnel[name] = (pendingFunnel[name] or 0) + 1
		end
	end)
end

local function funnelFor(userId: number, name: string)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		PlaytestAnalytics.funnel(player, name)
	end
end

-- What a request may change, taken before and after it (PlayerService).
export type Snapshot = {
	gold: number,
	level: number,
	shop: { string | false },
	units: { [string]: { unitType: string, starLevel: number } },
}
function PlaytestAnalytics.snapshot(state): Snapshot
	local units = {}
	for id, unit in state.board.units do
		units[id] = { unitType = unit.unitType, starLevel = unit.starLevel }
	end
	return { gold = state.gold, level = state.level, shop = table.clone(state.shop), units = units }
end

-- Star-ups among `after`'s units: a unit at 2+ stars that was lower (or not there) before.
local function starUps(userId: number, before: Snapshot, after: Snapshot)
	for id, unit in after.units do
		local was = before.units[id]
		if unit.starLevel >= 2 and (not was or was.starLevel < unit.starLevel) then
			custom(userId, "star_up", unit.starLevel, unit.unitType)
		end
	end
end

-- An accepted request (PlayerService): what it bought, sold or spent, star-ups, level-ups.
function PlaytestAnalytics.action(userId: number, remoteName: string, before: Snapshot, after: Snapshot, args: { any })
	if not logged[userId] then
		return
	end
	local current = log
	local spent = math.max(0, before.gold - after.gold)
	if remoteName == RemoteNames.RequestBuyUnit then
		local unitType = before.shop[args[1]]
		if type(unitType) == "string" then
			if current then
				MatchLog.bought(current, userId, unitType, spent)
			end
			custom(userId, "unit_bought", UnitConfig[unitType] and UnitConfig[unitType].cost or 1, unitType)
		end
	elseif remoteName == RemoteNames.RequestSellUnit then
		local unit = before.units[args[1]]
		if unit then
			if current then
				MatchLog.sold(current, userId)
			end
			custom(userId, "unit_sold", unit.starLevel, unit.unitType)
		end
	elseif remoteName == RemoteNames.RequestReroll then
		if current then
			MatchLog.spent(current, userId, "reroll", spent)
		end
		custom(userId, "reroll")
	elseif remoteName == RemoteNames.RequestBuyXp then
		if current then
			MatchLog.spent(current, userId, "xp", spent)
		end
	end
	starUps(userId, before, after)
	PlaytestAnalytics.levelChanged(userId, before.level, after.level)
end

-- Units that merged after a fight (PlayerService.endCombat): each is a star-up.
function PlaytestAnalytics.merged(userId: number, units: { any })
	if not logged[userId] then
		return
	end
	for _, unit in units do
		custom(userId, "star_up", unit.starLevel, unit.unitType)
	end
end

function PlaytestAnalytics.levelChanged(userId: number, from: number, to: number)
	if not logged[userId] or to <= from then
		return
	end
	if log then
		MatchLog.setLevel(log, userId, to)
	end
	custom(userId, "level_up", to)
end

-- A match starts (RoundService): `participants` by UserId, `isBot(userId)`.
function PlaytestAnalytics.matchStarted(id: string, participants: { number }, isBot: (number) -> boolean)
	local current = MatchLog.new(id, os.time())
	log = current
	table.clear(logged)
	table.clear(traitsSeen)
	for _, userId in participants do
		if not isBot(userId) then
			MatchLog.addPlayer(current, userId, false)
			logged[userId] = true
			traitsSeen[userId] = {}
			funnelFor(userId, "first_match_started")
			analytics(userId, "LogProgressionStartEvent", PROGRESSION_PATH, 1, "Round 1")
		end
	end
end

-- A round starts with these players still in it.
function PlaytestAnalytics.roundStarted(round: number, active: { number })
	if round ~= 5 then
		return
	end
	for _, userId in active do
		if logged[userId] then
			funnelFor(userId, "round_5_reached")
		end
	end
end

-- The boards that fight this round (PlayerService.lockBoards) and each player's level.
function PlaytestAnalytics.combat(round: number, boards: { [number]: { any } }, levels: { [number]: number })
	local current = log
	if not current then
		return
	end
	for userId, units in boards do
		if logged[userId] then
			local active = {}
			for _, state in Traits.summary(units) do
				if state.active then
					local key = string.format("%s:%d", state.name, state.level)
					table.insert(active, key)
					if not traitsSeen[userId][key] then
						traitsSeen[userId][key] = true
						custom(userId, "trait_active", state.level, state.name)
					end
				end
			end
			MatchLog.combat(current, userId, round, levels[userId] or 0, units, active)
		end
	end
end

-- Players still in after a round's Results.
function PlaytestAnalytics.roundSurvived(round: number, active: { number })
	for _, userId in active do
		if logged[userId] then
			analytics(userId, "LogProgressionCompleteEvent", PROGRESSION_PATH, round, "Round " .. round)
		end
	end
end

function PlaytestAnalytics.eliminated(userId: number, round: number, placement: number)
	if not logged[userId] then
		return
	end
	if log then
		MatchLog.placed(log, userId, placement)
	end
	analytics(userId, "LogProgressionFailEvent", PROGRESSION_PATH, round, "Round " .. round)
end

-- Left the game while still in the match (or came back: `phase` nil).
function PlaytestAnalytics.left(userId: number, round: number, phase: string?)
	if logged[userId] and log then
		MatchLog.quit(log, userId, round, phase)
	end
end

-- The match is over (RoundService): final placements by UserId, and the match's facts.
function PlaytestAnalytics.matchEnded(placements: { [number]: number }, info: { [string]: any })
	local current = log
	log = nil
	if not current then
		return
	end
	for userId, placement in placements do
		if logged[userId] then
			MatchLog.placed(current, userId, placement)
			if info.finished then
				funnelFor(userId, "match_finished")
			end
		end
	end
	local record = MatchLog.finish(current, {
		endedAt = os.time(),
		rounds = info.rounds,
		practice = info.practice,
		botDifficulty = MatchConfig.botDifficulty,
	})
	record.studio = RunService:IsStudio()
	record.server = game.JobId
	table.insert(pendingMatches, record)
	MatchLog.mergeUnitTotals(pendingUnits, MatchLog.unitTotals(record))
	table.clear(logged)
	print(
		string.format(
			"[PlaytestAnalytics] match %s logged: %d humans, %d rounds",
			record.id,
			record.humans,
			record.rounds
		)
	)
end

local function flush()
	if #pendingMatches > 0 then
		local batch = pendingMatches
		pendingMatches = {}
		PlaytestStore.append(PlaytestStore.MATCHES, batch, MAX_MATCHES)
	end
	if next(pendingUnits) then
		local units = pendingUnits
		pendingUnits = {}
		PlaytestStore.update(PlaytestStore.MATCHES, "units", function(old)
			return MatchLog.mergeUnitTotals(if type(old) == "table" then old else {}, units)
		end)
	end
	if next(pendingFunnel) then
		local counts = pendingFunnel
		pendingFunnel = {}
		PlaytestStore.update(PlaytestStore.MATCHES, "funnel", function(old)
			local funnel = if type(old) == "table" then old else {}
			for name, count in counts do
				funnel[name] = (funnel[name] or 0) + count
			end
			return funnel
		end)
	end
end

local function onPlayer(player: Player)
	local userId = player.UserId
	reached[userId] = reached[userId] or {}
	-- The steps reached in earlier sessions, so this session counts nothing twice.
	local ok, flags = PlaytestStore.get(PlaytestStore.PLAYER_FLAGS, flagKey(userId))
	if ok and type(flags) == "table" and type(flags.funnel) == "table" then
		for name in flags.funnel do
			reached[userId][name] = true
		end
	end
	if player.Parent then
		PlaytestAnalytics.funnel(player, "joined")
	end
end

function PlaytestAnalytics.start()
	assert(not started, "PlaytestAnalytics.start called more than once")
	started = true
	Players.PlayerAdded:Connect(function(player)
		ErrorLog.call("analytics join", onPlayer, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(ErrorLog.call, "analytics join", onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		reached[player.UserId] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			ErrorLog.call("analytics flush", flush)
		end
	end)
	game:BindToClose(flush)
end

return PlaytestAnalytics
