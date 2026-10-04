-- Placeholder unit types, keyed by name. All values are placeholders for a later design pass,
-- roughly in the range of TFT low-cost units.
--   health            hit points
--   attackDamage      damage dealt per attack
--   attacksPerSecond  attack rate
--   range             attack range in hex cells (1 = melee)
--   moveSpeed         cells moved per second
return table.freeze({
	-- Melee tank
	Guardian = table.freeze({
		health = 950,
		attackDamage = 45,
		attacksPerSecond = 0.6,
		range = 1,
		moveSpeed = 1,
	}),

	-- Melee fighter
	Brawler = table.freeze({
		health = 700,
		attackDamage = 60,
		attacksPerSecond = 0.75,
		range = 1,
		moveSpeed = 1.2,
	}),

	-- Ranged attacker
	Archer = table.freeze({
		health = 500,
		attackDamage = 55,
		attacksPerSecond = 0.7,
		range = 4,
		moveSpeed = 1,
	}),

	-- Fast melee unit
	Striker = table.freeze({
		health = 550,
		attackDamage = 45,
		attacksPerSecond = 1,
		range = 1,
		moveSpeed = 2,
	}),
})
