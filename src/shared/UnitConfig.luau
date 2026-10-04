-- The first real roster: ten characters, two per cost, with stats and abilities exactly as in
-- docs/design/combat-and-roster.md section 3. Abilities are pure data for the generic interpreter
-- in Abilities.luau; per-star values are { 1-star, 2-star, 3-star }.
--   cost              gold price and shop tier (1-5)
--   role              design role (display only)
--   health, attackDamage, abilityPower, armor, magicResist
--   attacksPerSecond  attack rate
--   range             attack range in hexes (1 = melee)
--   moveSpeed         movement scalar (x CombatConfig.baseMoveSpeed hexes per second)
--   startingMana, maxMana
-- Crit chance and crit damage are global (CombatConfig). Star level scales only health and attack
-- damage; ability values come from the per-star lists.

local function freezeAll(value)
	if type(value) == "table" then
		for _, child in value do
			freezeAll(child)
		end
		table.freeze(value)
	end
	return value
end

return freezeAll({
	Kaien = {
		displayName = "Kaien Vale",
		cost = 1,
		role = "Frontline",
		health = 720,
		attackDamage = 48,
		abilityPower = 100,
		armor = 40,
		magicResist = 40,
		attacksPerSecond = 0.6,
		range = 1,
		moveSpeed = 1.0,
		startingMana = 40,
		maxMana = 90,
		ability = {
			name = "Iron Pulse",
			effects = {
				{ type = "SHIELD", target = "SELF", amount = { 180, 300, 500 }, duration = 5 },
				{ type = "STUN", target = "CURRENT_TARGET", duration = { 1.0, 1.5, 2.25 } },
			},
		},
	},
	Mira = {
		displayName = "Mira Quill",
		cost = 1,
		role = "Ranged Carry",
		health = 540,
		attackDamage = 62,
		abilityPower = 100,
		armor = 18,
		magicResist = 18,
		attacksPerSecond = 0.78,
		range = 4,
		moveSpeed = 1.0,
		startingMana = 20,
		maxMana = 80,
		ability = {
			name = "Starbolt",
			effects = {
				-- docs/design/balance-pass-v0.2.md: 140/220/360 -> 120/190/310, +25/35/50% -> +20/30/45%.
				{ type = "DAMAGE", target = "CURRENT_TARGET", damageType = "PHYSICAL", amount = { 120, 190, 310 } },
				{ type = "BUFF", target = "SELF", stat = "AttackSpeed", percent = { 20, 30, 45 }, duration = 4 },
			},
		},
	},

	Rook = {
		displayName = "Rook Ember",
		cost = 2,
		role = "Bruiser",
		health = 850,
		attackDamage = 66,
		abilityPower = 100,
		armor = 38,
		magicResist = 32,
		attacksPerSecond = 0.68,
		range = 1,
		moveSpeed = 1.0,
		startingMana = 30,
		maxMana = 90,
		ability = {
			name = "Meteor Knuckle",
			effects = {
				{ type = "DAMAGE", target = "CURRENT_TARGET", damageType = "PHYSICAL", amount = { 180, 290, 470 } },
				-- The spec gives no center; the target of the punch is used.
				{
					type = "AREA_DAMAGE",
					center = "CURRENT_TARGET",
					radius = 1,
					damageType = "MAGIC",
					amount = { 80, 130, 220 },
				},
			},
		},
	},
	Sena = {
		displayName = "Sena Lume",
		cost = 2,
		role = "Support",
		health = 650,
		attackDamage = 48,
		abilityPower = 100,
		armor = 25,
		magicResist = 35,
		attacksPerSecond = 0.7,
		range = 3,
		moveSpeed = 1.0,
		startingMana = 40,
		maxMana = 100,
		ability = {
			name = "Moonveil",
			effects = {
				{ type = "SHIELD", target = "LOWEST_HP_ALLY", amount = { 180, 300, 480 }, duration = 5 },
				{ type = "HEAL", target = "LOWEST_HP_ALLY", amount = { 100, 160, 260 } },
			},
		},
	},

	Veyra = {
		displayName = "Veyra Storm",
		cost = 3,
		role = "Caster",
		health = 720,
		attackDamage = 55,
		abilityPower = 100,
		armor = 25,
		magicResist = 30,
		attacksPerSecond = 0.72,
		range = 4,
		moveSpeed = 1.0,
		startingMana = 20,
		maxMana = 80,
		ability = {
			name = "Tempest Core",
			effects = {
				{
					type = "AREA_DAMAGE",
					center = "CURRENT_TARGET",
					radius = 1,
					damageType = "MAGIC",
					amount = { 260, 420, 680 },
				},
				{ type = "STUN", target = "CURRENT_TARGET", duration = { 1.0, 1.5, 2.0 } },
			},
		},
	},
	Dax = {
		displayName = "Dax Ironwind",
		cost = 3,
		role = "Duelist",
		health = 850,
		attackDamage = 76,
		abilityPower = 100,
		armor = 35,
		magicResist = 30,
		attacksPerSecond = 0.85,
		range = 1,
		moveSpeed = 1.1,
		startingMana = 30,
		maxMana = 90,
		ability = {
			name = "Flashbreak",
			effects = {
				-- docs/design/balance-pass-v0.2.md: dives the farthest enemy (was CURRENT_TARGET, 2 hexes)
				-- and keeps attacking it; damage 240/380/600 -> 300/475/750.
				{
					type = "DASH",
					target = "FARTHEST_ENEMY",
					distance = 3,
					mode = "OFFENSIVE",
					setsCurrentTarget = true,
				},
				{ type = "DAMAGE", target = "FARTHEST_ENEMY", damageType = "PHYSICAL", amount = { 300, 475, 750 } },
				{ type = "BUFF", target = "SELF", stat = "AttackSpeed", percent = { 30, 45, 65 }, duration = 4 },
			},
		},
	},

	Orin = {
		displayName = "Orin Bastion",
		cost = 4,
		role = "Main Tank",
		health = 1180,
		attackDamage = 58,
		abilityPower = 100,
		armor = 60,
		magicResist = 60,
		attacksPerSecond = 0.6,
		range = 1,
		moveSpeed = 0.9,
		startingMana = 50,
		maxMana = 110,
		ability = {
			name = "Unbroken Citadel",
			effects = {
				{ type = "SHIELD", target = "SELF", amount = { 450, 700, 1100 }, duration = 6 },
				{ type = "BUFF", target = "SELF", stat = "Armor", flat = { 30, 45, 70 }, duration = 6 },
				{ type = "BUFF", target = "SELF", stat = "MR", flat = { 30, 45, 70 }, duration = 6 },
			},
		},
	},
	Nyra = {
		displayName = "Nyra Voss",
		cost = 4,
		role = "Ranged Carry",
		health = 820,
		attackDamage = 88,
		abilityPower = 100,
		armor = 28,
		magicResist = 28,
		attacksPerSecond = 0.9,
		range = 4,
		moveSpeed = 1.0,
		startingMana = 20,
		maxMana = 80,
		ability = {
			name = "Voidline Shot",
			effects = {
				-- docs/design/balance-pass-v0.2.md: 350/550/900 -> 320/500/800.
				{ type = "DAMAGE", target = "FARTHEST_ENEMY", damageType = "PHYSICAL", amount = { 320, 500, 800 } },
				{ type = "STUN", target = "FARTHEST_ENEMY", duration = { 1.0, 1.5, 2.25 } },
			},
		},
	},

	Astra = {
		displayName = "Astra Ren",
		cost = 5,
		role = "Mystic Carry",
		health = 980,
		attackDamage = 75,
		abilityPower = 100,
		armor = 38,
		magicResist = 45,
		attacksPerSecond = 0.85,
		range = 4,
		moveSpeed = 1.0,
		startingMana = 30,
		maxMana = 100,
		ability = {
			name = "Falling Constellation",
			effects = {
				{
					type = "AREA_DAMAGE",
					center = "HIGHEST_AD_ENEMY",
					radius = 2,
					damageType = "MAGIC",
					amount = { 400, 650, 1050 },
				},
			},
		},
	},
	Kairo = {
		displayName = "Kairo Zenith",
		cost = 5,
		role = "Vanguard Carry",
		health = 1250,
		attackDamage = 96,
		abilityPower = 100,
		armor = 60,
		magicResist = 50,
		attacksPerSecond = 0.8,
		range = 1,
		moveSpeed = 1.1,
		startingMana = 40,
		maxMana = 110,
		ability = {
			name = "Heavenbreaker",
			effects = {
				{ type = "DASH", target = "HIGHEST_AD_ENEMY", distance = 3, mode = "OFFENSIVE" },
				{
					type = "AREA_DAMAGE",
					center = "SELF",
					radius = 1,
					damageType = "MAGIC",
					amount = { 400, 650, 1050 },
				},
				{ type = "SHIELD", target = "SELF", amount = { 300, 500, 800 }, duration = 5 },
			},
		},
	},
})
