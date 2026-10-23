-- The playtest report's numbers and text, from match-log records (src/shared/MatchLog.luau), the
-- funnel counts and the per-unit totals the server saves in the PlaytestMatches DataStore. Pure:
-- no network or files, so tests/PlaytestReportTest.luau runs it on sim records.

local MatchLog = require("../../src/shared/MatchLog")

local PlaytestData = {}

export type Summary = {
	matches: number,
	players: number,
	avgDuration: number,
	avgRounds: number,
	avgHumans: number,
	avgBots: number,
	funnel: { { name: string, count: number, drop: number? } },
	quits: { phase: { [string]: number }, round: { [string]: number }, total: number },
	units: { { unit: string, picked: number, fielded: number, top4: number, pickRate: number, top4Rate: number? } },
	traits: { { trait: string, count: number } },
	boards: { { board: string, count: number, avgPlacement: number } },
}

local function sortedPairs(map: { [string]: number }): { { key: string, count: number } }
	local list = {}
	for key, count in map do
		table.insert(list, { key = key, count = count })
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.key < b.key
	end)
	return list
end

-- Round buckets for quit points.
local function roundBucket(round: number): string
	if round <= 3 then
		return "1-3"
	elseif round <= 7 then
		return "4-7"
	elseif round <= 12 then
		return "8-12"
	end
	return "13+"
end

-- `records`: match-log records. `funnel`: { [step name] = count } (optional). `unitTotals`: the
-- saved per-unit totals (optional; else totals are computed from the records).
function PlaytestData.summarize(
	records: { any },
	funnel: { [string]: number }?,
	unitTotals: { [string]: any }?
): Summary
	local summary: Summary = {
		matches = #records,
		players = 0,
		avgDuration = 0,
		avgRounds = 0,
		avgHumans = 0,
		avgBots = 0,
		funnel = {},
		quits = { phase = {}, round = {}, total = 0 },
		units = {},
		traits = {},
		boards = {},
	}
	local totals = {}
	local traitCounts, boardCounts, boardPlacements = {}, {}, {}
	for _, record in records do
		summary.avgDuration += record.durationSeconds or 0
		summary.avgRounds += record.rounds or 0
		summary.avgHumans += record.humans or 0
		summary.avgBots += record.bots or 0
		if not unitTotals then
			MatchLog.mergeUnitTotals(totals, MatchLog.unitTotals(record))
		end
		for _, player in record.players or {} do
			summary.players += 1
			if player.quit then
				summary.quits.total += 1
				local phase = tostring(player.quit.phase)
				summary.quits.phase[phase] = (summary.quits.phase[phase] or 0) + 1
				local bucket = roundBucket(player.quit.round or 0)
				summary.quits.round[bucket] = (summary.quits.round[bucket] or 0) + 1
			end
			for _, trait in player.traitsEnd or {} do
				local name = string.match(trait, "^[^:]+") or trait
				traitCounts[name] = (traitCounts[name] or 0) + 1
			end
			local board = {}
			for _, unit in player.finalBoard or {} do
				table.insert(board, string.match(unit, "^[^:]+") or unit)
			end
			if #board > 0 then
				table.sort(board)
				local key = table.concat(board, ", ")
				boardCounts[key] = (boardCounts[key] or 0) + 1
				boardPlacements[key] = (boardPlacements[key] or 0) + (player.placement or 0)
			end
		end
	end
	if #records > 0 then
		summary.avgDuration /= #records
		summary.avgRounds /= #records
		summary.avgHumans /= #records
		summary.avgBots /= #records
	end

	-- The funnel, each step's drop from the step before.
	local previous = nil
	for _, name in MatchLog.FUNNEL do
		local count = if funnel then funnel[name] or 0 else 0
		table.insert(summary.funnel, {
			name = name,
			count = count,
			drop = if previous and previous > 0 then 1 - count / previous else nil,
		})
		previous = count
	end

	for unit, counts in unitTotals or totals do
		table.insert(summary.units, {
			unit = unit,
			picked = counts.picked or 0,
			fielded = counts.fielded or 0,
			top4 = counts.top4 or 0,
			pickRate = if summary.players > 0 then (counts.picked or 0) / summary.players else 0,
			top4Rate = if (counts.fielded or 0) > 0 then (counts.top4 or 0) / counts.fielded else nil,
		})
	end
	table.sort(summary.units, function(a, b)
		if a.picked ~= b.picked then
			return a.picked > b.picked
		end
		return a.unit < b.unit
	end)
	for _, entry in sortedPairs(traitCounts) do
		table.insert(summary.traits, { trait = entry.key, count = entry.count })
	end
	for index, entry in sortedPairs(boardCounts) do
		if index > 5 then
			break
		end
		table.insert(summary.boards, {
			board = entry.key,
			count = entry.count,
			avgPlacement = boardPlacements[entry.key] / entry.count,
		})
	end
	return summary
end

local function percent(value: number?): string
	return if value then string.format("%d%%", math.round(value * 100)) else "-"
end

-- The readable report.
function PlaytestData.format(summary: Summary): string
	local lines = {}
	local function add(...)
		table.insert(lines, string.format(...))
	end
	add("== Matches ==")
	add(
		"%d matches, %d logged players; average %.0f s (%.1f min), %.1f rounds, %.1f humans + %.1f bots",
		summary.matches,
		summary.players,
		summary.avgDuration,
		summary.avgDuration / 60,
		summary.avgRounds,
		summary.avgHumans,
		summary.avgBots
	)
	add("")
	add("== New-player funnel ==")
	for index, step in summary.funnel do
		add("%d. %-20s %5d   drop %s", index, step.name, step.count, percent(step.drop))
	end
	add("")
	add("== Quit points (left while still in the match) ==")
	add("total %d", summary.quits.total)
	for _, entry in sortedPairs(summary.quits.phase) do
		add("  phase %-12s %d", entry.key, entry.count)
	end
	for _, entry in sortedPairs(summary.quits.round) do
		add("  rounds %-11s %d", entry.key, entry.count)
	end
	add("")
	add("== Units (picked = players who bought it; top 4 = of players who fielded it) ==")
	add("%-20s %7s %8s %8s %8s", "unit", "picked", "pick %", "fielded", "top 4 %")
	for _, unit in summary.units do
		add(
			"%-20s %7d %8s %8d %8s",
			unit.unit,
			unit.picked,
			percent(unit.pickRate),
			unit.fielded,
			percent(unit.top4Rate)
		)
	end
	add("")
	add("== Traits active at the end ==")
	for _, trait in summary.traits do
		add("%-16s %d", trait.trait, trait.count)
	end
	add("")
	add("== Most common final boards ==")
	for _, board in summary.boards do
		add("%dx (avg place %.1f): %s", board.count, board.avgPlacement, board.board)
	end
	return table.concat(lines, "\n")
end

local function csvRow(values: { any }): string
	local cells = {}
	for _, value in values do
		local text = tostring(value)
		if string.find(text, '[,"\n]') then
			text = '"' .. string.gsub(text, '"', '""') .. '"'
		end
		table.insert(cells, text)
	end
	return table.concat(cells, ",")
end

-- CSV files (name -> text): units, funnel, matches (one row per logged player).
function PlaytestData.csv(summary: Summary, records: { any }): { [string]: string }
	local units = { csvRow({ "unit", "picked", "pick_rate", "fielded", "top4", "top4_rate" }) }
	for _, unit in summary.units do
		table.insert(
			units,
			csvRow({ unit.unit, unit.picked, unit.pickRate, unit.fielded, unit.top4, unit.top4Rate or "" })
		)
	end
	local funnel = { csvRow({ "step", "name", "count", "drop" }) }
	for index, step in summary.funnel do
		table.insert(funnel, csvRow({ index, step.name, step.count, step.drop or "" }))
	end
	local players = {
		csvRow({
			"match",
			"time",
			"duration_s",
			"rounds",
			"humans",
			"bots",
			"user_id",
			"placement",
			"final_level",
			"gold_spent",
			"rerolls",
			"xp_bought",
			"quit_round",
			"quit_phase",
			"final_board",
			"traits_end",
		}),
	}
	for _, record in records do
		for _, player in record.players or {} do
			table.insert(
				players,
				csvRow({
					record.id,
					record.time,
					record.durationSeconds,
					record.rounds,
					record.humans,
					record.bots,
					player.userId,
					player.placement,
					player.finalLevel,
					player.goldSpent,
					player.rerolls,
					player.xpBought,
					if player.quit then player.quit.round else "",
					if player.quit then player.quit.phase else "",
					table.concat(player.finalBoard or {}, " "),
					table.concat(player.traitsEnd or {}, " "),
				})
			)
		end
	end
	return {
		["units.csv"] = table.concat(units, "\n") .. "\n",
		["funnel.csv"] = table.concat(funnel, "\n") .. "\n",
		["players.csv"] = table.concat(players, "\n") .. "\n",
	}
end

return PlaytestData
