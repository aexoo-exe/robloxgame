-- PvE themes: each theme lists its creep and boss unit types (stats and looks), the creep lineup of
-- every opening round and the boss of every stage that has a boss round. A match picks one theme
-- at the start (Pve.pickTheme) and uses it for every PvE round, so a new theme is a new entry here.
-- docs/pve-rounds.md explains the fields.
--
-- Unit types use the UnitConfig stat fields and run through the same combat engine. Health is
-- before CombatConfig.globalHealthMultiplier (x1.16), like UnitConfig. They are never in UnitConfig,
-- so they never appear in the shop or the unit pool. Their ids must be unique across UnitConfig and
-- every theme. Creeps have no ability (no maxMana). `look` is what players see: name, body color
-- { r, g, b } and a size multiplier.
-- Lineups and bosses are in the enemy's own board coordinates (row 1 = back, row 4 = front).
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.

local function creep(health, ad, armor, mr, attackSpeed, range, move, look)
	return {
		kind = "creep",
		health = health,
		attackDamage = ad,
		abilityPower = 100,
		armor = armor,
		magicResist = mr,
		attacksPerSecond = attackSpeed,
		range = range,
		moveSpeed = move,
		startingMana = 0,
		look = look,
	}
end

-- A boss with the signature slam: physical damage to every enemy within 1 hex, then a short stun
-- on the same enemies (AREA_DAMAGE + AREA_STUN, both centered on the boss).
local function boss(health, ad, armor, mr, attackSpeed, maxMana, slamDamage, slamStun, look)
	return {
		kind = "boss",
		health = health,
		attackDamage = ad,
		abilityPower = 100,
		armor = armor,
		magicResist = mr,
		attacksPerSecond = attackSpeed,
		range = 1,
		moveSpeed = 0.8,
		startingMana = 0,
		maxMana = maxMana,
		ability = {
			name = "Boss Slam",
			effects = {
				{ type = "AREA_DAMAGE", center = "SELF", radius = 1, damageType = "PHYSICAL", amount = slamDamage },
				{ type = "AREA_STUN", center = "SELF", radius = 1, duration = slamStun },
			},
		},
		look = look,
	}
end

local function look(name: string, color: { number }, scale: number)
	return { name = name, color = color, scale = scale }
end

local function at(unitType: string, column: number, row: number)
	return { unitType = unitType, column = column, row = row }
end

local CREEP_LOOK = look("Creep", { 120, 150, 110 }, 0.8)
local BIG_CREEP_LOOK = look("Big creep", { 95, 125, 85 }, 1.0)
local BOSS_LOOK = look("Boss", { 170, 50, 50 }, 1.6)

local themes = {
	placeholder = {
		units = {
			-- creep(HP, AD, armor, MR, attack speed, range, move, look)
			placeholder_creep = creep(180, 12, 0, 0, 0.60, 1, 0.9, CREEP_LOOK),
			placeholder_creep_ranged = creep(140, 14, 0, 0, 0.60, 3, 0.9, CREEP_LOOK),
			placeholder_creep_big = creep(380, 22, 15, 10, 0.55, 1, 0.8, BIG_CREEP_LOOK),

			-- boss(HP, AD, armor, MR, attack speed, max mana, slam damage, slam stun seconds, look)
			placeholder_boss_stage2 = boss(3500, 55, 30, 30, 0.70, 150, 120, 0.75, BOSS_LOOK),
			placeholder_boss_stage3 = boss(6000, 80, 45, 45, 0.70, 150, 220, 1.0, BOSS_LOOK),
			placeholder_boss_stage4 = boss(10000, 110, 60, 60, 0.70, 150, 350, 1.0, BOSS_LOOK),
			placeholder_boss_stage5 = boss(15000, 145, 75, 75, 0.70, 150, 500, 1.25, BOSS_LOOK),
		},

		-- Opening creep rounds, by round number. Every player fights the same lineup.
		creepRounds = {
			-- Round 1: two weak melee creeps, for a single 1-cost unit.
			[1] = { at("placeholder_creep", 3, 4), at("placeholder_creep", 5, 4) },
			-- Round 2: one more, at range.
			[2] = {
				at("placeholder_creep", 3, 4),
				at("placeholder_creep", 5, 4),
				at("placeholder_creep_ranged", 4, 1),
			},
			-- Round 3: a big creep in front.
			[3] = {
				at("placeholder_creep", 3, 4),
				at("placeholder_creep_big", 4, 4),
				at("placeholder_creep", 5, 4),
				at("placeholder_creep_ranged", 4, 1),
			},
		},

		-- The boss of each stage that has a boss round (PveConfig.bossRounds), by stage number.
		bosses = {
			[2] = at("placeholder_boss_stage2", 4, 3),
			[3] = at("placeholder_boss_stage3", 4, 3),
			[4] = at("placeholder_boss_stage4", 4, 3),
			[5] = at("placeholder_boss_stage5", 4, 3),
		},
	},
}

local function freezeAll(value)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			freezeAll(child)
		end
		table.freeze(value)
	end
	return value
end

return freezeAll(themes)
