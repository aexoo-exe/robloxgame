-- Combat simulation settings. The combat time limit is MatchConfig.combatMaxDuration.

local function unit(unitType: string, column: number, row: number, starLevel: number?)
	return table.freeze({ unitType = unitType, column = column, row = row, starLevel = starLevel or 1 })
end

return table.freeze({
	-- Fixed simulation rate. Attack and move intervals are rounded to whole ticks.
	ticksPerSecond = 20,

	-- Seconds the Combat phase continues after the fight ends, so the last animations can finish.
	endPadding = 1.5,

	-- A fight that reaches the time limit is a draw when both sides' remaining health percentages are
	-- within this fraction (1 percentage point) of each other. docs/design/match-structure.md section 6.
	timeoutDrawMargin = 0.01,

	-- The roster health dial. Every roster unit's combat health is its UnitConfig health times this
	-- (and its star multiplier), and so is every form health pool (rider horses, FormConfig); see
	-- StarLevel. Creeps and bosses (PveThemeConfig) list final health and are not scaled by it.
	-- Summons follow it through their summoner's health. UnitConfig keeps the design docs' base
	-- values. Player health and player damage are separate and unaffected.
	-- docs/design/revamp-structure.md: 1.16. A 12% increase is 1.16 x 1.12 = 1.2992.
	globalHealthMultiplier = 1.16,

	-- Global combat rules from docs/design/combat-and-roster.md section 1. Every unit uses these.
	critChance = 0.25, -- per basic attack; abilities cannot crit
	critDamage = 1.4, -- multiplier on the raw basic-attack damage
	baseAbilityPower = 100, -- magic ability damage, heals and shields scale by AP / this
	manaPerAttack = 10, -- gained by the attacker for each completed basic attack
	manaPerPercentHealthLost = 5, -- gained per 1% of max health lost to post-mitigation damage
	maxManaPerDamage = 10, -- cap on mana gained from one damage event
	castTime = 0.75, -- seconds a caster cannot act after casting
	baseMoveSpeed = 1, -- hexes per second at a unit's move speed scalar of 1.0

	-- Engine v2 building blocks (docs/design/revamp-structure.md, Building blocks).
	maxStunSeconds = 2.0, -- no STUN or AREA_STUN may last longer; enforced by Abilities.validate
	maxEntitiesPerSide = 12, -- living board units plus summons on one side; SUMMON stops at this
	dotManaCap = 10, -- most mana a victim gains from one DAMAGE_OVER_TIME application, over all its ticks
	-- COPY magnitude multiplier, by the copied unit's cost (1-5). Scales DAMAGE, AREA_DAMAGE, HEAL,
	-- SHIELD and DAMAGE_OVER_TIME amounts only.
	copyPowerByCost = table.freeze({ 0.80, 0.80, 0.80, 0.60, 0.45 }),

	-- Opponents for a player who is alone, by round. Round n uses entry n; rounds past the end of
	-- the list reuse the last entry. Positions are in the enemy's own board coordinates
	-- (row 1 = back row, BoardConfig.rows = front row); the optional 4th argument is the star level.
	-- Unit counts roughly track the player's unit cap (= level), and from round 9 the boards add
	-- 2-star units. Costs, star levels, counts and positions were tuned for the old placeholder
	-- roster (docs/star-upgrades-plan.md); each unit was then swapped for a roster v1.1 character of
	-- the same cost and a similar role. They are not retuned.
	-- Practice enemies never draw from the shared pool.
	enemyBoardsByRound = table.freeze({
		-- Round 1: player is level 2 (2 units)
		table.freeze({ unit("iron_rush", 4, 4), unit("blooming_aid", 4, 1) }),
		-- Round 2: level 3
		table.freeze({ unit("cinder_arc", 4, 4), unit("spurshot", 3, 1), unit("blooming_aid", 5, 1) }),
		-- Round 3
		table.freeze({ unit("iron_rush", 3, 4), unit("flare_kick", 4, 4), unit("spurshot", 4, 1) }),
		-- Round 4
		table.freeze({ unit("marsh_fortress", 4, 4), unit("field_medic", 3, 4), unit("orbit_breaker", 4, 1) }),
		-- Round 5: level 4
		table.freeze({
			unit("flare_kick", 3, 4),
			unit("redline_cut", 5, 4),
			unit("field_medic", 4, 3),
			unit("spurshot", 4, 1),
		}),
		-- Round 6: level 5
		table.freeze({
			unit("flare_kick", 3, 4),
			unit("marsh_fortress", 5, 4),
			unit("burst_vector", 4, 3),
			unit("spurshot", 3, 1),
			unit("blooming_aid", 5, 1),
		}),
		-- Round 7
		table.freeze({
			unit("volt_spear", 4, 4),
			unit("flare_kick", 3, 4),
			unit("field_medic", 5, 3),
			unit("snapfire", 4, 1),
			unit("skyboulder", 2, 1),
		}),
		-- Round 8: level 6
		table.freeze({
			unit("thunder_nest", 4, 4),
			unit("flare_kick", 3, 4),
			unit("marsh_fortress", 5, 4),
			unit("burst_vector", 6, 3),
			unit("snapfire", 4, 1),
			unit("skyboulder", 2, 1),
		}),
		-- Round 9: first 2-star
		table.freeze({
			unit("thunder_nest", 4, 4),
			unit("flare_kick", 3, 4, 2),
			unit("redline_cut", 5, 4),
			unit("field_medic", 6, 3),
			unit("snapfire", 4, 1),
			unit("skyboulder", 2, 1),
		}),
		-- Round 10
		table.freeze({
			unit("volt_spear", 4, 4),
			unit("flare_kick", 3, 4, 2),
			unit("marsh_fortress", 5, 4),
			unit("field_medic", 6, 3, 2),
			unit("snapfire", 4, 1),
			unit("skyboulder", 2, 1),
		}),
		-- Round 11
		table.freeze({
			unit("thunder_nest", 4, 4),
			unit("flare_kick", 3, 4, 2),
			unit("frozen_moment", 5, 4),
			unit("field_medic", 6, 3, 2),
			unit("snapfire", 4, 1),
			unit("skyboulder", 2, 1),
		}),
		-- Round 12 onwards
		table.freeze({
			unit("thunder_nest", 4, 4, 2),
			unit("flare_kick", 3, 4, 2),
			unit("elastic_wardrum", 5, 4),
			unit("burst_vector", 6, 3, 2),
			unit("snapfire", 4, 1),
			unit("skyboulder", 2, 1),
		}),
	}),
})
