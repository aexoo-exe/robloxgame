-- Bot difficulty check: plays 6-player matches (the server fills Play-pad matches to
-- MatchConfig.botFillTo) where seat 1 is the new-player stand-in (Bot.newPlayerPolicy) and the other
-- seats are bots of one difficulty, and reports how often the new player places in the top 4.
-- Target for easy bots: about 40-60%. Prints summaries only.
--   lune run sim/difficulty.luau [matches=60] [easy|normal|both|mixed]
-- "mixed" seats 3 easy and 2 normal bots with the new player, to compare easy and normal directly.
-- The match is played like sim/run.luau and the server (Match, PlayerState, CombatSim, traits, PvE).

local process = require("@lune/process")

local Bot = require("../src/shared/Bot")
local LeanMatch = require("./LeanMatch")

local MATCHES = tonumber(process.args[1]) or 60
local MODE = process.args[2] or "both"
local PLAYERS = 6

local function policyFor(mode: string, seat: number)
	if seat == 1 then
		return Bot.newPlayerPolicy
	end
	if mode == "mixed" then
		return if seat <= 4 then Bot.easyPolicies[seat % #Bot.easyPolicies + 1] else Bot.policies[seat]
	elseif mode == "easy" then
		return Bot.easyPolicies[seat % #Bot.easyPolicies + 1]
	end
	return if seat == 3 then Bot.traitPolicy else Bot.policies[(seat - 1) % #Bot.policies + 1]
end

-- Plays one match (LeanMatch); returns placements by seat and the number of rounds.
local function playMatch(mode: string, matchIndex: number): ({ [number]: number }, number)
	local placements, rounds = LeanMatch.play({
		players = PLAYERS,
		matchIndex = matchIndex,
		policyFor = function(seat)
			return policyFor(mode, seat)
		end,
	})
	return placements, rounds
end

local function report(mode: string)
	local top4, placementSum, rounds = 0, 0, 0
	local bySeat = {}
	for matchIndex = 1, MATCHES do
		local placements, matchRounds = playMatch(mode, matchIndex)
		rounds += matchRounds
		if placements[1] <= 4 then
			top4 += 1
		end
		placementSum += placements[1]
		for seat = 2, PLAYERS do
			local name = policyFor(mode, seat).name
			local entry = bySeat[name] or { count = 0, sum = 0 }
			entry.count += 1
			entry.sum += placements[seat]
			bySeat[name] = entry
		end
	end
	print(
		string.format(
			"%-6s new player: top 4 in %d%% (%d/%d), average place %.2f; %.1f rounds per match",
			mode,
			math.round(top4 / MATCHES * 100),
			top4,
			MATCHES,
			placementSum / MATCHES,
			rounds / MATCHES
		)
	)
	local names = {}
	for name in bySeat do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		print(string.format("         %-12s average place %.2f", name, bySeat[name].sum / bySeat[name].count))
	end
end

for _, mode in { "easy", "normal", "mixed" } do
	if MODE == mode or (MODE == "both" and mode ~= "mixed") then
		report(mode)
	end
end
