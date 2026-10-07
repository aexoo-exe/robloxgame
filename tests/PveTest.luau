-- PvE rounds (docs/pve-rounds.md): the round layout, themes, rewards, the starting unit, and that
-- creeps and bosses never reach the shop or the pool. Characters are named by internal id only.

local Abilities = require("../src/shared/Abilities")
local Board = require("../src/shared/Board")
local CombatConfig = require("../src/shared/CombatConfig")
local CombatSim = require("../src/shared/CombatSim")
local FormConfig = require("../src/shared/FormConfig")
local StarLevel = require("../src/shared/StarLevel")
local Economy = require("../src/shared/Economy")
local EconomyConfig = require("../src/shared/EconomyConfig")
local Match = require("../src/shared/Match")
local MatchConfig = require("../src/shared/MatchConfig")
local MatchRules = require("../src/shared/MatchRules")
local PlayerState = require("../src/shared/PlayerState")
local Pve = require("../src/shared/Pve")
local PveConfig = require("../src/shared/PveConfig")
local PveThemeConfig = require("../src/shared/PveThemeConfig")
local Shop = require("../src/shared/Shop")
local UnitConfig = require("../src/shared/UnitConfig")
local UnitPool = require("../src/shared/UnitPool")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

-- A fight's result as Match.applyResults takes it.
local function result(fight, winner, survivors, healthPercent)
	return { fight = fight, winner = winner, survivors = survivors, healthPercent = healthPercent }
end

local tests = {}

-- Layout ----------------------------------------------------------------------------------------

table.insert(tests, {
	name = "round layout: 1-3 creeps, then PvP, bosses on 8/12/16/20, no boss after 20",
	run = function()
		local expected = {
			"Creep",
			"Creep",
			"Creep",
			"PvP",
			"PvP",
			"PvP",
			"PvP",
			"Boss",
			"PvP",
			"PvP",
			"PvP",
			"Boss",
		}
		for round, kind in expected do
			expectEqual(Pve.roundKind(round), kind, "round " .. round)
		end
		expectEqual(Pve.roundKind(16), "Boss", "round 16")
		expectEqual(Pve.roundKind(20), "Boss", "round 20")
		for round = 21, 40 do
			expectEqual(Pve.roundKind(round), "PvP", "round " .. round)
		end
		-- Each boss round is the last round of its stage.
		for _, round in PveConfig.bossRounds do
			local label = "boss round " .. round .. " ends a stage"
			expectEqual(MatchRules.stage(round + 1), MatchRules.stage(round) + 1, label)
		end
	end,
})

table.insert(tests, {
	name = "preparation: none in round 1, 15s in rounds 2-3, the normal timer after",
	run = function()
		expectEqual(Pve.preparationDuration(1), 0, "round 1")
		expectEqual(Pve.preparationDuration(2), 15, "round 2")
		expectEqual(Pve.preparationDuration(3), 15, "round 3")
		for round = 4, 25 do
			expectEqual(Pve.preparationDuration(round), MatchConfig.preparationDuration, "round " .. round)
		end
	end,
})

-- Themes ----------------------------------------------------------------------------------------

table.insert(tests, {
	name = "themes are complete: lineups for every creep round, a boss for every boss round, valid units",
	run = function()
		assert(PveThemeConfig.placeholder, "the placeholder theme exists")
		local seenIds = {}
		local statFields =
			{ "health", "attackDamage", "armor", "magicResist", "attacksPerSecond", "range", "moveSpeed" }
		for themeId, theme in PveThemeConfig do
			for id, unit in theme.units do
				assert(UnitConfig[id] == nil, themeId .. ": " .. id .. " collides with a character id")
				assert(not seenIds[id], themeId .. ": " .. id .. " is used by another theme")
				seenIds[id] = true
				assert(unit.kind == "creep" or unit.kind == "boss", id .. " needs kind creep or boss")
				for _, field in statFields do
					assert(type(unit[field]) == "number", id .. " needs " .. field)
				end
				assert(unit.look and type(unit.look.name) == "string", id .. " needs a look with a name")
				assert(type(unit.look.color) == "table" and #unit.look.color == 3, id .. " look color")
				if unit.kind == "creep" then
					assert(unit.ability == nil and unit.maxMana == nil, id .. ": creeps have no ability")
				else
					local ok, reason = Abilities.validate(unit.ability)
					assert(ok, id .. ": " .. tostring(reason))
					assert(type(unit.maxMana) == "number", id .. " needs maxMana to cast")
				end
			end
			for round = 1, PveConfig.openingCreepRounds do
				local board = Pve.enemyBoard(themeId, round)
				assert(#board > 0, themeId .. " round " .. round .. " has no creeps")
				for _, placed in board do
					expectEqual(theme.units[placed.unitType].kind, "creep", "round " .. round .. " lineup")
				end
			end
			for _, round in PveConfig.bossRounds do
				local board = Pve.enemyBoard(themeId, round)
				expectEqual(#board, 1, themeId .. " round " .. round .. ": a single boss")
				expectEqual(theme.units[board[1].unitType].kind, "boss", "round " .. round .. " boss")
			end
		end
	end,
})

table.insert(tests, {
	name = "creep lineups ramp up and bosses get tougher every stage",
	run = function()
		local theme = PveThemeConfig.placeholder
		local function lineupHealth(round)
			local total = 0
			for _, placed in Pve.enemyBoard("placeholder", round) do
				total += theme.units[placed.unitType].health
			end
			return total
		end
		assert(lineupHealth(2) > lineupHealth(1), "round 2 is harder than round 1")
		assert(lineupHealth(3) > lineupHealth(2), "round 3 is harder than round 2")
		local previous = nil
		for _, round in PveConfig.bossRounds do
			local boss = theme.units[Pve.enemyBoard("placeholder", round)[1].unitType]
			if previous then
				assert(boss.health > previous.health and boss.attackDamage > previous.attackDamage, "round " .. round)
			end
			previous = boss
		end
	end,
})

table.insert(tests, {
	name = "creeps and bosses never appear in the shop or the unit pool",
	run = function()
		local pool = UnitPool.new()
		for id in pool.remaining do
			assert(Pve.pveUnitType(id) == nil, id .. " is in the pool")
		end
		for _, names in Shop.unitsByCost do
			for _, id in names do
				assert(Pve.pveUnitType(id) == nil, id .. " is in the shop tiers")
			end
		end
		local merged = Pve.unitTypes("placeholder")
		for id in UnitConfig do
			assert(merged[id] == UnitConfig[id], "merged unit types keep every character")
		end
	end,
})

table.insert(tests, {
	name = "a single 1-cost unit beats the round-1 creeps (every 1-cost, several seeds)",
	run = function()
		local enemies = Pve.enemyBoard("placeholder", 1)
		for _, id in Shop.unitsByCost[1] do
			for seed = 1, 5 do
				local fight = CombatSim.run({
					boards = { { { id = "u", unitType = id, column = 4, row = 4 } }, enemies },
					columns = 7,
					rows = 4,
					unitTypes = Pve.unitTypes("placeholder"),
					ticksPerSecond = 20,
					maxTicks = 20 * MatchConfig.combatMaxDuration,
					timeoutDrawMargin = 0.01,
					seed = seed,
				})
				expectEqual(fight.winner, 1, string.format("%s vs round-1 creeps, seed %d", id, seed))
			end
		end
	end,
})

table.insert(tests, {
	name = "the roster health dial scales characters and rider horses, never creeps or bosses",
	run = function()
		local dial = CombatConfig.globalHealthMultiplier
		local placed = { { id = "r", unitType = "spurshot", column = 4, row = 4 } }
		local fight = CombatSim.run({
			boards = { placed, Pve.enemyBoard("placeholder", 8) },
			columns = 7,
			rows = 4,
			unitTypes = Pve.unitTypes("placeholder"),
			ticksPerSecond = 20,
			maxTicks = 1,
			seed = 1,
		})
		local rider, boss = fight.units[1], fight.units[2]
		expectEqual(rider.maxHealth, math.round(UnitConfig.spurshot.health * dial), "character health x dial")
		expectEqual(
			rider.maxFormHealth,
			math.round(FormConfig.mount.horseHealth.spurshot * dial),
			"horse pool x dial"
		)
		local bossType = PveThemeConfig.placeholder.units[Pve.enemyBoard("placeholder", 8)[1].unitType]
		expectEqual(boss.maxHealth, bossType.health, "boss health is listed as final combat health")
		for id, unit in PveThemeConfig.placeholder.units do
			expectEqual(StarLevel.scaleStats(unit, 1).health, unit.health, id .. " is not scaled by the dial")
		end
	end,
})

-- Rewards ---------------------------------------------------------------------------------------

table.insert(tests, {
	name = "creep rewards: the round's gold (1/2/2) times the share of creeps killed, rounded down",
	run = function()
		expectEqual(PveConfig.creepRoundGold[1], 1, "round 1 gold")
		expectEqual(PveConfig.creepRoundGold[2], 2, "round 2 gold")
		expectEqual(PveConfig.creepRoundGold[3], 2, "round 3 gold")
		for round = 1, 3 do
			local creeps = #Pve.enemyBoard("placeholder", round)
			local full = PveConfig.creepRoundGold[round]
			local all = Pve.reward("placeholder", round, { 2, 0 }, { 0.5, 0 })
			expectEqual(all.gold, full, "round " .. round .. ": every creep killed")
			expectEqual(all.creepsKilled, creeps, "creeps killed")
			expectEqual(Pve.reward("placeholder", round, { 0, creeps }, { 0, 1 }).gold, 0, "none killed")
			for survivors = 0, creeps do
				local gold = Pve.reward("placeholder", round, { 1, survivors }, { 0.5, 0.5 }).gold
				expectEqual(gold, math.floor(full * (creeps - survivors) / creeps), "round " .. round .. " share")
			end
		end
		-- Round 3 has 4 creeps and pays 2: 3 killed -> 1.5 -> 1, 2 killed -> 1, 1 killed -> 0.
		expectEqual(Pve.reward("placeholder", 3, { 1, 1 }, nil).gold, 1, "3 of 4 killed")
		expectEqual(Pve.reward("placeholder", 3, { 1, 3 }, nil).gold, 0, "1 of 4 killed")
	end,
})

table.insert(tests, {
	name = "boss rewards: the highest share step reached, plus the kill bonus",
	run = function()
		local steps = PveConfig.bossRewardSteps
		-- Under 25%: 0. 25-44%: 1. 45-64%: 2. 65-84%: 3. 85%+: 4. Kill: +1.
		local cases = {
			{ 0.24, 0 },
			{ 0.25, 1 },
			{ 0.44, 1 },
			{ 0.45, 2 },
			{ 0.64, 2 },
			{ 0.65, 3 },
			{ 0.84, 3 },
			{ 0.85, 4 },
			{ 1, 4 },
		}
		for _, case in cases do
			expectEqual(Pve.bossGold(case[1], false), case[2], "share " .. case[1])
		end
		expectEqual(Pve.bossGold(1 - 0.55, false), 2, "an exact 45% computed as 1 - 0.55")
		expectEqual(PveConfig.bossKillBonus, 1, "kill bonus")
		expectEqual(Pve.bossGold(0, false), 0, "no damage")
		expectEqual(Pve.bossGold(steps[1].minShare - 0.01, false), 0, "below the first step")
		for _, step in steps do
			expectEqual(Pve.bossGold(step.minShare, false), step.gold, "share " .. step.minShare)
		end
		local top = steps[#steps].gold
		expectEqual(Pve.bossGold(1, true), top + PveConfig.bossKillBonus, "kill")

		local partial = Pve.reward("placeholder", 8, { 0, 1 }, { 0, 0.4 })
		expectEqual(partial.share, 0.6, "60% of the boss's health removed")
		expectEqual(partial.gold, Pve.bossGold(0.6, false), "partial reward")
		local kill = Pve.reward("placeholder", 8, { 3, 0 }, { 0.7, 0 })
		assert(kill.bossKilled, "boss killed")
		expectEqual(kill.gold, top + PveConfig.bossKillBonus, "kill reward")
	end,
})

-- Match flow -----------------------------------------------------------------------------------

table.insert(tests, {
	name = "PvE rounds: every player gets the same PvE fight, losing costs no HP, gold is reported",
	run = function()
		local match = Match.new({ 1, 2, 3, 4, 5 }, 11)
		assert(PveThemeConfig[match.theme], "the match picked a theme")
		local fights = Match.startRound(match)
		expectEqual(#fights, 5, "one creep fight per player")
		for _, fight in fights do
			expectEqual(fight.pve, "Creep", "round 1 fights are creep fights")
			assert(fight.b == nil and fight.ghostOf == nil, "no opponent player")
		end
		local results = {}
		for i, fight in fights do
			-- Players 1-2 win, the rest lose or time out.
			table.insert(results, result(fight, if i <= 2 then 1 elseif i == 3 then nil else 2, { 1, 1 }, { 0.5, 0.5 }))
		end
		local summary = Match.applyResults(match, results)
		for id, player in match.players do
			expectEqual(player.health, MatchConfig.startingHealth, "HP of player " .. id)
			assert(summary.pve[id], "reward for player " .. id)
			-- Round 1 pays 1 gold for both creeps; one of two killed is 0.5, rounded down to 0.
			expectEqual(summary.pve[id].gold, 0, "one of two creeps killed")
		end
		expectEqual(next(summary.outcomes), nil, "PvE rounds report no PvP outcomes")
		expectEqual(#summary.eliminated, 0, "nobody is eliminated")
	end,
})

table.insert(tests, {
	name = "a match plays creep rounds, then PvP, then a boss round on round 8",
	run = function()
		local match = Match.new({ 1, 2, 3, 4 }, 12)
		local kinds = {}
		for round = 1, 8 do
			local fights = Match.startRound(match)
			kinds[round] = fights[1].pve or "PvP"
			local results = {}
			for _, fight in fights do
				table.insert(results, result(fight, nil, { 1, 1 }, { 0.5, 0.5 }))
			end
			Match.applyResults(match, results)
		end
		expectEqual(table.concat(kinds, ","), "Creep,Creep,Creep,PvP,PvP,PvP,PvP,Boss", "round kinds")
	end,
})

table.insert(tests, {
	name = "a practice match also plays the PvE rounds",
	run = function()
		local match = Match.new({ 9 }, 13)
		local fights = Match.startRound(match)
		expectEqual(fights[1].pve, "Creep", "practice round 1")
		local summary = Match.applyResults(match, { result(fights[1], 2, { 0, 2 }, { 0, 1 }) })
		expectEqual(match.players[9].health, MatchConfig.startingHealth, "a lost creep round costs no HP")
		expectEqual(summary.pve[9].gold, 0, "no creeps killed")
		assert(not match.finished, "the practice match continues")
	end,
})

-- Player state ---------------------------------------------------------------------------------

table.insert(tests, {
	name = "every player starts with one random 1-cost unit from the shared pool, on the board",
	run = function()
		local pool = UnitPool.new()
		local before = 0
		for _, id in Shop.unitsByCost[1] do
			before += UnitPool.remaining(pool, id)
		end
		for seed = 1, 8 do
			local state = PlayerState.new(seed, pool)
			local granted = PlayerState.grantStartingUnits(state)
			expectEqual(#granted, PveConfig.startingUnits.count, "units granted")
			local placed = Board.getPlacedUnits(state.board)
			expectEqual(#placed, 1, "the unit is on the board")
			expectEqual(UnitConfig[placed[1].unitType].cost, PveConfig.startingUnits.cost, "a 1-cost unit")
			expectEqual(placed[1].column, PveConfig.startingUnits.cells[1].column, "placed on the first listed cell")
			expectEqual(placed[1].row, PveConfig.startingUnits.cells[1].row, "placed on the first listed cell")
			expectEqual(state.gold, EconomyConfig.startingGold, "the unit is free")
		end
		local after = 0
		for _, id in Shop.unitsByCost[1] do
			after += UnitPool.remaining(pool, id)
		end
		-- Each player's first shop also holds copies out; count only what the grants took.
		assert(before - after >= 8, "the 8 starting units came out of the shared pool")
	end,
})

table.insert(tests, {
	name = "PvE gold is paid at once; next income is normal but PvE leaves the streak and win bonus alone",
	run = function()
		local state = PlayerState.new(21)
		PlayerState.recordCombat(state, Economy.Outcome.Win)
		PlayerState.recordCombat(state, Economy.Outcome.Win)
		PlayerState.startPreparation(state)
		expectEqual(state.streak, 2, "two PvP wins")
		local gold = state.gold
		PlayerState.recordPve(state, 3)
		expectEqual(state.gold, gold + 3, "PvE gold paid at once")
		expectEqual(state.streak, 2, "PvE does not change the streak")
		local income = PlayerState.startPreparation(state)
		assert(income, "income is still paid after a PvE round")
		expectEqual(income.win, 0, "no win bonus after a PvE round")
		expectEqual(income.streak, Economy.streakBonus(2), "the streak bonus still counts the PvP streak")
		expectEqual(income.base, EconomyConfig.baseIncome, "base income unchanged")
	end,
})

return tests
