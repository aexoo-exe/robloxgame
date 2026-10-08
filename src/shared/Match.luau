-- One match: each participant's HP, connection and placement, the round counter and the opponent
-- history (docs/design/match-structure.md sections 2-5 and 7). Players are identified by UserId, so
-- their state survives leaving and rejoining.
--
-- A match with a single participant is a practice match: every PvP round they fight a scripted
-- enemy (`fight.b` and `fight.ghostOf` both nil), take damage by the normal formula, and the match
-- ends when they are eliminated.
--
-- PvE rounds (Pve.roundKind: the opening creep rounds and the boss rounds) give every active player
-- the same PvE fight (`fight.pve` set to the round kind) from the match's theme, picked at the
-- start. They are not recorded in the pairing history, cost PveConfig.healthLoss HP when not won,
-- and earn the gold in Pve.reward; they report in `summary.pve`, not `summary.outcomes`, so they
-- leave streaks alone.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local MatchConfig = if script then require(script.Parent.MatchConfig) else require("./MatchConfig")
local MatchRules = if script then require(script.Parent.MatchRules) else require("./MatchRules")
local Pairing = if script then require(script.Parent.Pairing) else require("./Pairing")
local Pve = if script then require(script.Parent.Pve) else require("./Pve")
local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")

local Match = {}

export type MatchPlayer = {
	id: number,
	health: number,
	eliminated: boolean,
	placement: number?,
	connected: boolean,
	missedRounds: number, -- complete rounds missed while disconnected
	missingThisRound: boolean, -- disconnected when this round started
	lastSurvivors: number, -- own surviving units in the latest fight (elimination tie-break)
}

export type Match = {
	round: number,
	practice: boolean,
	theme: string, -- PvE theme (PveThemeConfig) for every PvE round of this match
	finished: boolean,
	winner: number?,
	players: { [number]: MatchPlayer },
	history: Pairing.History,
	rng: SeededRandom.SeededRandom,
}

-- Result of one fight. `winner` is 1 for `fight.a`, 2 for the other side (player, ghost or
-- practice enemy), nil for a draw. `survivors` counts living units per side at the end.
export type FightResult = {
	fight: Pairing.Fight,
	winner: number?,
	survivors: { number },
	healthPercent: { number }?, -- CombatSim healthPercent per side; boss rewards need it
}

export type RoundSummary = {
	damage: { [number]: number }, -- HP lost per player this round
	outcomes: { [number]: string }, -- Economy.Outcome per real player who fought a PvP fight
	pve: { [number]: Pve.Reward }, -- per player who fought a PvE fight: the gold it earned
	eliminated: { number }, -- players eliminated this round, best placement first
}

function Match.new(ids: { number }, seed: number): Match
	local players = {}
	for _, id in ids do
		players[id] = {
			id = id,
			health = MatchConfig.startingHealth,
			eliminated = false,
			placement = nil,
			connected = true,
			missedRounds = 0,
			missingThisRound = false,
			lastSurvivors = 0,
		}
	end
	return {
		round = 0,
		practice = #ids == 1,
		-- Its own generator, so the theme pick leaves the pairing sequence of `rng` unchanged.
		theme = Pve.pickTheme(SeededRandom.new(seed)),
		finished = false,
		winner = nil,
		players = players,
		history = Pairing.newHistory(),
		rng = SeededRandom.new(seed),
	}
end

-- Ids of players still in the match, sorted.
function Match.activeIds(match: Match): { number }
	local ids = {}
	for id, player in match.players do
		if not player.eliminated then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- Marks a player connected or disconnected. Reconnecting resets the missed-round count.
function Match.setConnected(match: Match, id: number, connected: boolean)
	local player = match.players[id]
	if not player then
		return
	end
	player.connected = connected
	if connected then
		player.missedRounds = 0
		player.missingThisRound = false
	end
end

-- Starts the next round and returns its fights.
function Match.startRound(match: Match): { Pairing.Fight }
	match.round += 1
	local active = Match.activeIds(match)
	for _, id in active do
		local player = match.players[id]
		player.missingThisRound = not player.connected
	end
	local kind = Pve.roundKind(match.round)
	if kind ~= Pve.Kind.PvP then
		local fights = {}
		for _, id in active do
			table.insert(fights, { a = id, pve = kind })
		end
		return fights
	end
	if match.practice then
		return { { a = active[1] } }
	end
	local fights = Pairing.pair(active, match.history, match.rng)
	Pairing.recordRound(match.history, fights)
	return fights
end

local function outcomeFor(winner: number?, side: number): string
	if winner == nil then
		return Economy.Outcome.Draw
	end
	return if winner == side then Economy.Outcome.Win else Economy.Outcome.Loss
end

-- Applies a round's fight results at Results: player damage, leaver HP loss, eliminations,
-- placements and the winner. Only real players take damage; ghost and practice opponents never do.
function Match.applyResults(match: Match, results: { FightResult }): RoundSummary
	local summary = { damage = {}, outcomes = {}, pve = {}, eliminated = {} }
	local active = Match.activeIds(match)
	local healthBefore = {}
	for _, id in active do
		healthBefore[id] = match.players[id].health
	end

	local function hurt(id: number, amount: number)
		match.players[id].health -= amount
		summary.damage[id] = (summary.damage[id] or 0) + amount
	end

	for _, result in results do
		local fight = result.fight
		local a = match.players[fight.a]
		a.lastSurvivors = result.survivors[1]
		if fight.pve then
			summary.pve[fight.a] = Pve.reward(match.theme, match.round, result.survivors, result.healthPercent)
			local loss = Pve.healthLoss(fight.pve)
			if result.winner ~= 1 and loss > 0 then
				hurt(fight.a, loss)
			end
			continue
		end
		summary.outcomes[fight.a] = outcomeFor(result.winner, 1)
		if result.winner == 2 then
			hurt(fight.a, MatchRules.playerDamage(match.round, result.survivors[2]))
		end
		if fight.b then
			match.players[fight.b].lastSurvivors = result.survivors[2]
			summary.outcomes[fight.b] = outcomeFor(result.winner, 2)
			if result.winner == 1 then
				hurt(fight.b, MatchRules.playerDamage(match.round, result.survivors[1]))
			end
		end
	end

	-- Leavers: a whole round missed counts; after the grace period their HP drops to 0.
	for _, id in active do
		local player = match.players[id]
		if not player.connected and player.missingThisRound then
			player.missedRounds += 1
			if player.missedRounds >= MatchConfig.leaverGraceRounds then
				player.health = math.min(player.health, 0)
			end
		end
	end

	local entries = {}
	for _, id in active do
		local player = match.players[id]
		if player.health <= 0 then
			table.insert(entries, {
				id = id,
				healthAfter = player.health,
				healthBefore = healthBefore[id],
				survivors = player.lastSurvivors,
			})
		end
	end
	local remaining = #active - #entries
	summary.eliminated = MatchRules.rankEliminated(entries, match.rng)
	for rank, id in summary.eliminated do
		local player = match.players[id]
		player.eliminated = true
		player.placement = remaining + rank
	end

	-- A normal match ends when one player is left (or none, if the last ones fell together; the best
	-- of them wins). A practice match ends when its only player is eliminated.
	local finished = if match.practice then remaining == 0 else remaining <= 1
	if finished then
		local winner = if remaining == 1 then Match.activeIds(match)[1] else summary.eliminated[1]
		match.players[winner].placement = 1
		match.winner = winner
		match.finished = true
	end
	return summary
end

return Match
