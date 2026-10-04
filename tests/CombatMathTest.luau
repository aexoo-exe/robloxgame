local CombatMath = require("../src/shared/CombatMath")

local DamageType = CombatMath.DamageType

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local function expectNear(actual, expected, label)
	assert(math.abs(actual - expected) < 0.001, string.format("%s: expected %.4f, got %.4f", label, expected, actual))
end

local tests = {}

table.insert(tests, {
	name = "resistance multiplier at the spec's example values",
	run = function()
		expectNear(CombatMath.resistanceMultiplier(0), 1, "0 resistance")
		expectNear(CombatMath.resistanceMultiplier(20), 0.8333, "20 resistance")
		expectNear(CombatMath.resistanceMultiplier(50), 0.6667, "50 resistance")
		expectNear(CombatMath.resistanceMultiplier(100), 0.5, "100 resistance")
		expectNear(CombatMath.resistanceMultiplier(200), 0.3333, "200 resistance")
	end,
})

table.insert(tests, {
	name = "damage types use the right resistance; true damage ignores both",
	run = function()
		expectEqual(CombatMath.finalDamage(300, DamageType.Physical, 50, 100), 200, "physical uses armor")
		expectEqual(CombatMath.finalDamage(300, DamageType.Magic, 50, 100), 150, "magic uses magic resist")
		expectEqual(CombatMath.finalDamage(300, DamageType.True, 50, 100), 300, "true ignores both")
	end,
})

table.insert(tests, {
	name = "damage rounds to the nearest integer with a minimum of 1",
	run = function()
		expectEqual(CombatMath.finalDamage(100, DamageType.Physical, 20, 0), 83, "83.33 rounds down")
		expectEqual(CombatMath.finalDamage(100, DamageType.Physical, 60, 0), 63, "62.5 rounds up")
		expectEqual(CombatMath.finalDamage(1, DamageType.Physical, 200, 0), 1, "0.33 becomes the minimum 1")
		expectEqual(CombatMath.finalDamage(0, DamageType.Physical, 0, 0), 0, "no raw damage is no hit")
	end,
})

table.insert(tests, {
	name = "crits deal 140% of the raw basic-attack damage",
	run = function()
		expectNear(CombatMath.critRawDamage(100), 140, "crit raw damage")
		expectEqual(
			CombatMath.finalDamage(CombatMath.critRawDamage(50), DamageType.Physical, 40, 0),
			50,
			"crit 70 raw vs 40 armor"
		)
	end,
})

table.insert(tests, {
	name = "ability power scales listed values (300 at 125 AP is 375)",
	run = function()
		expectNear(CombatMath.scaleByAbilityPower(300, 125), 375, "spec example")
		expectNear(CombatMath.scaleByAbilityPower(180, 100), 180, "base AP")
	end,
})

table.insert(tests, {
	name = "mana from damage: 5 per 1% of max health, capped at 10 per event",
	run = function()
		expectNear(CombatMath.manaFromDamage(10, 1000), 5, "1% of max health")
		expectNear(CombatMath.manaFromDamage(5, 1000), 2.5, "0.5% of max health")
		expectNear(CombatMath.manaFromDamage(20, 1000), 10, "2% of max health")
		expectNear(CombatMath.manaFromDamage(500, 1000), 10, "capped at 10")
		expectEqual(CombatMath.manaFromDamage(0, 1000), 0, "no health lost")
	end,
})

return tests
