-- Placeholder roster: two units per cost tier, one frontline and one damage dealer.
-- Health, attack damage and attack speed are authored by hand inside the cost bands of
-- docs/design/unit-stats-economy.md (section 2); role decides where the budget goes (section 3).
-- Range and move speed follow the baseline archetypes: frontline (range 1, speed 1),
-- ranged damage (range 4, speed 1) and fast melee damage (range 1, speed 2).
--   cost              gold price and shop tier (1-5)
--   role              "Frontline" or "Damage"
--   health            hit points
--   attackDamage      damage dealt per attack
--   attacksPerSecond  attack rate
--   range             attack range in hex cells (1 = melee)
--   moveSpeed         cells moved per second
return table.freeze({
	Tank1 = table.freeze({
		cost = 1,
		role = "Frontline",
		health = 700,
		attackDamage = 45,
		attacksPerSecond = 0.6,
		range = 1,
		moveSpeed = 1,
	}),
	Archer1 = table.freeze({
		cost = 1,
		role = "Damage",
		health = 520,
		attackDamage = 55,
		attacksPerSecond = 0.75,
		range = 4,
		moveSpeed = 1,
	}),

	Tank2 = table.freeze({
		cost = 2,
		role = "Frontline",
		health = 850,
		attackDamage = 50,
		attacksPerSecond = 0.6,
		range = 1,
		moveSpeed = 1,
	}),
	Striker2 = table.freeze({
		cost = 2,
		role = "Damage",
		health = 650,
		attackDamage = 60,
		attacksPerSecond = 0.8,
		range = 1,
		moveSpeed = 2,
	}),

	Tank3 = table.freeze({
		cost = 3,
		role = "Frontline",
		health = 1000,
		attackDamage = 55,
		attacksPerSecond = 0.65,
		range = 1,
		moveSpeed = 1,
	}),
	Archer3 = table.freeze({
		cost = 3,
		role = "Damage",
		health = 720,
		attackDamage = 72,
		attacksPerSecond = 0.8,
		range = 4,
		moveSpeed = 1,
	}),

	Tank4 = table.freeze({
		cost = 4,
		role = "Frontline",
		health = 1150,
		attackDamage = 60,
		attacksPerSecond = 0.65,
		range = 1,
		moveSpeed = 1,
	}),
	Striker4 = table.freeze({
		cost = 4,
		role = "Damage",
		health = 820,
		attackDamage = 85,
		attacksPerSecond = 0.9,
		range = 1,
		moveSpeed = 2,
	}),

	Tank5 = table.freeze({
		cost = 5,
		role = "Frontline",
		health = 1350,
		attackDamage = 70,
		attacksPerSecond = 0.7,
		range = 1,
		moveSpeed = 1,
	}),
	Archer5 = table.freeze({
		cost = 5,
		role = "Damage",
		health = 920,
		attackDamage = 95,
		attacksPerSecond = 0.95,
		range = 4,
		moveSpeed = 1,
	}),
})
