-- Round pairing (docs/design/match-structure.md section 4). With an even number of players everyone
-- gets one opponent. With an odd number, one player fights a ghost: a copy of another active
-- player's board. The source player is unaffected by the ghost battle.
--
-- Every possible pairing is scored against these rules, most important first, and one of the
-- best-scoring pairings is picked at random:
--   1. Pairs who fought last round (an immediate rematch).
--   2. A ghost for a player who had a ghost last round.
--   3. A ghost copied from the recipient's opponent last round.
--   4. Pairs who fought in either of the last 2 rounds.
-- So each rule is only broken when every pairing breaks it. With at most 8 players there are at
-- most 630 pairings to score.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")

local Pairing = {}

-- One fight: `a` against `b`, or `a` against a ghost of `ghostOf`.
export type Fight = {
	a: number,
	b: number?,
	ghostOf: number?,
}

-- Per player: real opponents of the last 2 rounds (most recent first; 0 for a ghost battle) and
-- whether they fought a ghost last round.
export type History = { [number]: { recent: { number }, hadGhost: boolean } }

local NO_OPPONENT = 0

function Pairing.newHistory(): History
	return {}
end

local function entryFor(history: History, id: number)
	return history[id] or { recent = {}, hadGhost = false }
end

-- All ways to split `ids` into pairs, as lists of { a, b }.
local function perfectMatchings(ids: { number }): { { { number } } }
	if #ids == 0 then
		return { {} }
	end
	local first = ids[1]
	local result = {}
	for i = 2, #ids do
		local rest = {}
		for j = 2, #ids do
			if j ~= i then
				table.insert(rest, ids[j])
			end
		end
		for _, matching in perfectMatchings(rest) do
			local withPair = { { first, ids[i] } }
			for _, pair in matching do
				table.insert(withPair, pair)
			end
			table.insert(result, withPair)
		end
	end
	return result
end

-- Lower is better, compared rule by rule (see the header).
local function score(history: History, pairs: { { number } }, ghost: Fight?): { number }
	local rematches, recentRepeats = 0, 0
	for _, pair in pairs do
		-- Checked from both sides, so the score does not depend on which player is listed first.
		local recentA = entryFor(history, pair[1]).recent
		local recentB = entryFor(history, pair[2]).recent
		if recentA[1] == pair[2] or recentB[1] == pair[1] then
			rematches += 1
		end
		if table.find(recentA, pair[2]) or table.find(recentB, pair[1]) then
			recentRepeats += 1
		end
	end
	local repeatGhost, ghostOfLastOpponent = 0, 0
	if ghost then
		local entry = entryFor(history, ghost.a)
		if entry.hadGhost then
			repeatGhost = 1
		end
		if entry.recent[1] == ghost.ghostOf then
			ghostOfLastOpponent = 1
		end
	end
	return { rematches, repeatGhost, ghostOfLastOpponent, recentRepeats }
end

local function compareScores(a: { number }, b: { number }): number
	for i = 1, #a do
		if a[i] ~= b[i] then
			return if a[i] < b[i] then -1 else 1
		end
	end
	return 0
end

-- Pairs the active players `ids` (2 or more) for one round. Does not change `history`; call
-- recordRound with the result.
function Pairing.pair(ids: { number }, history: History, rng: SeededRandom.SeededRandom): { Fight }
	local sorted = table.clone(ids)
	table.sort(sorted)

	local candidates = {}
	local function consider(pairs: { { number } }, ghost: Fight?)
		table.insert(candidates, { pairs = pairs, ghost = ghost, score = score(history, pairs, ghost) })
	end

	if #sorted % 2 == 0 then
		for _, pairs in perfectMatchings(sorted) do
			consider(pairs, nil)
		end
	else
		for _, recipient in sorted do
			local others = {}
			for _, id in sorted do
				if id ~= recipient then
					table.insert(others, id)
				end
			end
			for _, pairs in perfectMatchings(others) do
				for _, source in others do
					consider(pairs, { a = recipient, ghostOf = source })
				end
			end
		end
	end

	local best = {}
	for _, candidate in candidates do
		local comparison = if #best == 0 then -1 else compareScores(candidate.score, best[1].score)
		if comparison < 0 then
			best = { candidate }
		elseif comparison == 0 then
			table.insert(best, candidate)
		end
	end
	local chosen = best[SeededRandom.nextInt(rng, #best)]

	local fights = {}
	for _, pair in chosen.pairs do
		table.insert(fights, { a = pair[1], b = pair[2] })
	end
	if chosen.ghost then
		table.insert(fights, chosen.ghost)
	end
	return fights
end

-- Records a round's fights in the opponent history.
function Pairing.recordRound(history: History, fights: { Fight })
	local function push(id: number, opponent: number, hadGhost: boolean)
		local entry = entryFor(history, id)
		table.insert(entry.recent, 1, opponent)
		entry.recent[3] = nil
		entry.hadGhost = hadGhost
		history[id] = entry
	end
	for _, fight in fights do
		if fight.b then
			push(fight.a, fight.b, false)
			push(fight.b, fight.a, false)
		else
			push(fight.a, NO_OPPONENT, fight.ghostOf ~= nil)
		end
	end
end

return Pairing
