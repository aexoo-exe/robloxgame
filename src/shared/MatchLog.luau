-- The playtest match log: what one match looked like for each player, in one compact record, and
-- per-unit totals across matches. The server fills it as a match runs (PlaytestAnalytics) and saves
-- the records to the PlaytestMatches DataStore; the headless sim (sim/LeanMatch.luau) fills the same
-- shape, so scripts/playtest-report.luau can be checked against sim output.
--
-- Record (MatchLog.finish), version 1:
--   { v, id, time (os.time at the end), durationSeconds, rounds, humans, bots, practice,
--     botDifficulty, players = { PlayerRecord } }
-- PlayerRecord (one per logged player; the server logs humans only):
--   { userId, placement (0: unknown), finalLevel, goldSpent, rerolls, xpBought, unitsBought,
--     unitsSold, picked = { unit ids bought, sorted }, fielded = { unit ids fielded in any fight,
--     sorted }, snapshots = { { round, units = { "unit_id:star", ... } } } (every SNAPSHOT_EVERY
--     rounds), finalBoard = { "unit_id:star", ... } (the last fight's board), traitsEnd =
--     { "Trait:level", ... } (active traits of that board), quit = { round, phase }? (left the game
--     while still in the match and did not come back) }
-- Unit totals (MatchLog.unitTotals / mergeUnitTotals): { [unit id] = { picked, fielded, top4 } }:
--   players who bought it, players who fielded it, and players who fielded it and placed top 4.
-- Pure Luau: no Roblox APIs, so it runs in Lune.

local MatchLog = {}

MatchLog.VERSION = 1
MatchLog.SNAPSHOT_EVERY = 5 -- rounds between board snapshots

-- The new-player funnel, in order (AnalyticsService onboarding steps 1..7, and the counts the server
-- keeps in PlaytestMatches/"funnel" keyed by name). Names are stable: the dashboards key on them.
MatchLog.FUNNEL = table.freeze({
	"joined",
	"intro_finished",
	"queued",
	"first_match_started",
	"round_5_reached",
	"match_finished",
	"feedback_sent",
})

export type PlayerLog = {
	userId: number,
	bot: boolean,
	placement: number,
	level: number,
	goldSpent: number,
	rerolls: number,
	xpBought: number,
	unitsBought: number,
	unitsSold: number,
	picked: { [string]: boolean },
	fielded: { [string]: boolean },
	snapshots: { { round: number, units: { string } } },
	board: { string },
	traits: { string },
	quit: { round: number, phase: string }?,
}

export type Log = {
	id: string,
	startedAt: number,
	players: { [number]: PlayerLog },
}

function MatchLog.new(id: string, startedAt: number): Log
	return { id = id, startedAt = startedAt, players = {} }
end

function MatchLog.addPlayer(log: Log, userId: number, isBot: boolean?)
	log.players[userId] = {
		userId = userId,
		bot = isBot == true,
		placement = 0,
		level = 0,
		goldSpent = 0,
		rerolls = 0,
		xpBought = 0,
		unitsBought = 0,
		unitsSold = 0,
		picked = {},
		fielded = {},
		snapshots = {},
		board = {},
		traits = {},
		quit = nil,
	}
end

local function playerOf(log: Log, userId: number): PlayerLog?
	return log.players[userId]
end

-- A unit bought from the shop for `gold`.
function MatchLog.bought(log: Log, userId: number, unitType: string, gold: number)
	local player = playerOf(log, userId)
	if player then
		player.unitsBought += 1
		player.goldSpent += gold
		player.picked[unitType] = true
	end
end

function MatchLog.sold(log: Log, userId: number)
	local player = playerOf(log, userId)
	if player then
		player.unitsSold += 1
	end
end

-- Gold spent on a reroll ("reroll") or on XP ("xp").
function MatchLog.spent(log: Log, userId: number, kind: string, gold: number)
	local player = playerOf(log, userId)
	if not player then
		return
	end
	player.goldSpent += gold
	if kind == "reroll" then
		player.rerolls += 1
	elseif kind == "xp" then
		player.xpBought += 1
	end
end

-- "unit_id:star" for a board unit ({ unitType, starLevel }), sorted lists of them.
local function boardStrings(units: { any }): { string }
	local list = {}
	for _, unit in units do
		table.insert(list, string.format("%s:%d", unit.unitType, unit.starLevel or 1))
	end
	table.sort(list)
	return list
end

-- The board a player fought with in `round` (their placed units { unitType, starLevel }), their
-- level, and its active traits as "Trait:level" strings.
function MatchLog.combat(log: Log, userId: number, round: number, level: number, units: { any }, traits: { string })
	local player = playerOf(log, userId)
	if not player then
		return
	end
	player.level = level
	for _, unit in units do
		player.fielded[unit.unitType] = true
	end
	player.board = boardStrings(units)
	player.traits = table.clone(traits)
	table.sort(player.traits)
	if round % MatchLog.SNAPSHOT_EVERY == 0 then
		table.insert(player.snapshots, { round = round, units = player.board })
	end
end

function MatchLog.setLevel(log: Log, userId: number, level: number)
	local player = playerOf(log, userId)
	if player then
		player.level = math.max(player.level, level)
	end
end

function MatchLog.placed(log: Log, userId: number, placement: number)
	local player = playerOf(log, userId)
	if player then
		player.placement = placement
	end
end

-- Left the game while still in the match (nil `phase` clears it: they came back).
function MatchLog.quit(log: Log, userId: number, round: number, phase: string?)
	local player = playerOf(log, userId)
	if player then
		player.quit = if phase then { round = round, phase = phase } else nil
	end
end

local function keys(set: { [string]: boolean }): { string }
	local list = {}
	for key in set do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

-- The finished record. `info`: endedAt, rounds, practice, botDifficulty; `includeBots` logs bot
-- players too (the sim logs every seat).
function MatchLog.finish(log: Log, info: { [string]: any }, includeBots: boolean?)
	local players, humans, bots = {}, 0, 0
	local ids = {}
	for userId in log.players do
		table.insert(ids, userId)
	end
	table.sort(ids)
	for _, userId in ids do
		local player = log.players[userId]
		if player.bot then
			bots += 1
		else
			humans += 1
		end
		if includeBots or not player.bot then
			table.insert(players, {
				userId = userId,
				bot = player.bot,
				placement = player.placement,
				finalLevel = player.level,
				goldSpent = player.goldSpent,
				rerolls = player.rerolls,
				xpBought = player.xpBought,
				unitsBought = player.unitsBought,
				unitsSold = player.unitsSold,
				picked = keys(player.picked),
				fielded = keys(player.fielded),
				snapshots = player.snapshots,
				finalBoard = player.board,
				traitsEnd = player.traits,
				quit = player.quit,
			})
		end
	end
	return {
		v = MatchLog.VERSION,
		id = log.id,
		time = info.endedAt,
		durationSeconds = info.endedAt - log.startedAt,
		rounds = info.rounds,
		humans = humans,
		bots = bots,
		practice = info.practice == true,
		botDifficulty = info.botDifficulty or "",
		players = players,
	}
end

-- Per-unit totals of one record (see the header).
function MatchLog.unitTotals(record): { [string]: { picked: number, fielded: number, top4: number } }
	local totals = {}
	local function entry(unitType: string)
		local found = totals[unitType]
		if not found then
			found = { picked = 0, fielded = 0, top4 = 0 }
			totals[unitType] = found
		end
		return found
	end
	for _, player in record.players do
		for _, unitType in player.picked do
			entry(unitType).picked += 1
		end
		for _, unitType in player.fielded do
			local found = entry(unitType)
			found.fielded += 1
			if player.placement > 0 and player.placement <= 4 then
				found.top4 += 1
			end
		end
	end
	return totals
end

-- Adds `add` (unitTotals) into `into` (both { [unit id] = { picked, fielded, top4 } }).
function MatchLog.mergeUnitTotals(into: { [string]: any }, add: { [string]: any })
	for unitType, counts in add do
		local found = into[unitType]
		if not found then
			found = { picked = 0, fielded = 0, top4 = 0 }
			into[unitType] = found
		end
		found.picked += counts.picked or 0
		found.fielded += counts.fielded or 0
		found.top4 += counts.top4 or 0
	end
	return into
end

return MatchLog
