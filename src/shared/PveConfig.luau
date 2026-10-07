-- PvE rounds: the opening creep phase and the end-of-stage boss rounds (docs/pve-rounds.md).
-- Creep lineups, boss stats and looks are per theme, in PveThemeConfig. Rules live in Pve.luau.
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.
return table.freeze({
	-- Rounds 1..openingCreepRounds are creep rounds; PvP starts after them.
	openingCreepRounds = 3,

	-- Boss rounds: the last round of stages 2-5 (StageConfig: stages are 4 rounds long). Stage 1 has
	-- no boss (its PvE is the creep phase) and the open-ended stage 6 has none.
	bossRounds = table.freeze({ 8, 12, 16, 20 }),

	-- Preparation seconds by round; rounds not listed use MatchConfig.preparationDuration (30).
	-- 0 skips the Preparation phase entirely, including that round's income, XP and shop refresh, so
	-- only use it for round 1 (nothing is owed before the first fight).
	preparationDurations = table.freeze({
		[1] = 0,
		[2] = 15,
		[3] = 15,
	}),

	-- Given to every player when the match starts: `count` random units of `cost`, drawn from the
	-- shared pool (weighted by copies left, like a shop roll), placed on the board at the first
	-- free cell of `cells` (board coordinates; row 4 is the front row).
	startingUnits = table.freeze({
		count = 1,
		cost = 1,
		cells = table.freeze({
			table.freeze({ column = 4, row = 4 }),
			table.freeze({ column = 3, row = 4 }),
			table.freeze({ column = 5, row = 4 }),
		}),
	}),

	-- Gold for each creep round, the same for every player: the round's amount times the share of
	-- its creeps killed, rounded down (all killed pays it in full).
	creepRoundGold = table.freeze({
		[1] = 1,
		[2] = 2,
		[3] = 2,
	}),

	-- Boss rewards by the share of the boss's health removed when the fight ends: the highest step
	-- reached pays its gold (under the first step: 0), plus bossKillBonus if the boss died.
	bossRewardSteps = table.freeze({
		table.freeze({ minShare = 0.25, gold = 1 }), -- 25-44%
		table.freeze({ minShare = 0.45, gold = 2 }), -- 45-64%
		table.freeze({ minShare = 0.65, gold = 3 }), -- 65-84%
		table.freeze({ minShare = 0.85, gold = 4 }), -- 85% or more
	}),
	bossKillBonus = 1,

	-- Player HP lost for not winning a PvE round (a loss or a timeout).
	healthLoss = table.freeze({
		Creep = 0,
		Boss = 0,
	}),

	-- Names shown as the opponent during PvE combat.
	opponentNames = table.freeze({
		Creep = "Creeps",
		Boss = "Boss",
	}),
})
