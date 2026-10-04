local UnitConfig = require("../src/shared/UnitConfig")

-- Stat bands by cost, copied from docs/design/unit-stats-economy.md section 2.
local BANDS = {
	[1] = { health = { 500, 750 }, attackDamage = { 40, 65 }, attacksPerSecond = { 0.55, 0.80 } },
	[2] = { health = { 600, 900 }, attackDamage = { 45, 70 }, attacksPerSecond = { 0.55, 0.85 } },
	[3] = { health = { 700, 1050 }, attackDamage = { 50, 80 }, attacksPerSecond = { 0.60, 0.90 } },
	[4] = { health = { 800, 1200 }, attackDamage = { 55, 90 }, attacksPerSecond = { 0.65, 0.95 } },
	[5] = { health = { 900, 1400 }, attackDamage = { 60, 100 }, attacksPerSecond = { 0.65, 1.00 } },
}

local tests = {}

table.insert(tests, {
	name = "every unit's stats are inside its cost band",
	run = function()
		for name, unit in UnitConfig do
			local band = BANDS[unit.cost]
			assert(band, name .. " has an invalid cost")
			for stat, range in band do
				local value = unit[stat]
				assert(
					value >= range[1] and value <= range[2],
					string.format("%s %s = %s is outside %s-%s", name, stat, tostring(value), range[1], range[2])
				)
			end
			assert(unit.range >= 1 and unit.moveSpeed > 0, name .. " has invalid range or move speed")
		end
	end,
})

table.insert(tests, {
	name = "two units per cost tier: one frontline and one damage dealer",
	run = function()
		local roles = {}
		for _, unit in UnitConfig do
			roles[unit.cost] = roles[unit.cost] or {}
			table.insert(roles[unit.cost], unit.role)
		end
		for cost = 1, 5 do
			local tier = roles[cost] or {}
			table.sort(tier)
			assert(
				#tier == 2 and tier[1] == "Damage" and tier[2] == "Frontline",
				"cost " .. cost .. " should have one Frontline and one Damage unit"
			)
		end
	end,
})

return tests
