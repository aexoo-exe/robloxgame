local CombatSim = require("../src/shared/CombatSim")
local StarLevel = require("../src/shared/StarLevel")
local UnitConfig = require("../src/shared/UnitConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local tests = {}

table.insert(tests, {
	name = "stat scaling: health x1.8 / x3.24 and attack damage x1.5 / x2.25; nothing else",
	run = function()
		local base = UnitConfig.Tank1 -- 700 health, 45 attack damage
		local two = StarLevel.scaleStats(base, 2)
		local three = StarLevel.scaleStats(base, 3)
		expectEqual(StarLevel.scaleStats(base, 1).health, 700, "1-star health")
		expectEqual(two.health, 1260, "2-star health")
		expectEqual(three.health, 2268, "3-star health")
		expectEqual(two.attackDamage, 68, "2-star attack damage (67.5 rounded)")
		expectEqual(three.attackDamage, 101, "3-star attack damage (101.25 rounded)")
		for _, stat in { "attacksPerSecond", "range", "moveSpeed", "cost", "role" } do
			expectEqual(three[stat], base[stat], "3-star " .. stat)
		end
		expectEqual(base.health, 700, "base stats were changed")
	end,
})

table.insert(tests, {
	name = "copies per star level are 1, 3 and 9",
	run = function()
		expectEqual(StarLevel.copiesIn(1), 1, "1-star")
		expectEqual(StarLevel.copiesIn(2), 3, "2-star")
		expectEqual(StarLevel.copiesIn(3), 9, "3-star")
	end,
})

table.insert(tests, {
	name = "combat applies star scaling to health and damage",
	run = function()
		local result = CombatSim.run({
			boards = {
				{ { id = "a", unitType = "Tank1", starLevel = 2, column = 4, row = 4 } },
				{ { id = "b", unitType = "Tank1", column = 4, row = 4 } },
			},
			columns = 7,
			rows = 4,
			unitTypes = UnitConfig,
			ticksPerSecond = 20,
			maxTicks = 900,
			seed = 1,
		})
		expectEqual(result.units[1].maxHealth, 1260, "2-star max health")
		expectEqual(result.units[1].starLevel, 2, "2-star summary")
		expectEqual(result.units[2].maxHealth, 700, "1-star max health (star level omitted)")
		for _, event in result.events do
			if event.kind == "Attack" then
				local expected = if event.unit == 1 then 68 else 45
				expectEqual(event.damage, expected, "damage by unit " .. event.unit)
			end
		end
		expectEqual(result.winner, 1, "the 2-star should win")
	end,
})

return tests
