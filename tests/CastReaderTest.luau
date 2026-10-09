-- CastReader recovers damage types and area centers from the event list alone. Checked against
-- real fights: Battle.damage is wrapped to record the true damage type of every hit.

local Battle = require("../src/shared/Battle")
local CastReader = require("../src/client/CastReader")
local CombatSim = require("../src/shared/CombatSim")
local SeededRandom = require("../src/shared/SeededRandom")
local UnitConfig = require("../src/shared/UnitConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local UNIT_TYPES = {}
for name in UnitConfig do
	table.insert(UNIT_TYPES, name)
end
table.sort(UNIT_TYPES)

-- Runs a seeded random full-roster fight and returns the result and the true damage type of each
-- damage event, by event index.
local function recordedFight(seed: number)
	local rng = SeededRandom.new(seed)
	local boards = { {}, {} }
	for side = 1, 2 do
		local used = {}
		for i = 1, 7 do
			local column, row
			repeat
				column, row = SeededRandom.nextInt(rng, 7), SeededRandom.nextInt(rng, 4)
			until not used[column .. "," .. row]
			used[column .. "," .. row] = true
			table.insert(boards[side], {
				id = side .. ":" .. i,
				unitType = UNIT_TYPES[SeededRandom.nextInt(rng, #UNIT_TYPES)],
				starLevel = SeededRandom.nextInt(rng, 3),
				column = column,
				row = row,
			})
		end
	end

	local trueTypes = {}
	local original = Battle.damage
	Battle.damage = function(battle, source, target, raw, damageType, kind, crit, manaCap, overTime, tags)
		local before = #battle.events
		local final, manaGained = original(battle, source, target, raw, damageType, kind, crit, manaCap, overTime, tags)
		if #battle.events > before then
			trueTypes[before + 1] = damageType
		end
		return final, manaGained
	end
	local ok, result = pcall(CombatSim.run, {
		boards = boards,
		columns = 7,
		rows = 4,
		unitTypes = UnitConfig,
		ticksPerSecond = 20,
		maxTicks = 20 * 50,
		seed = seed,
	})
	Battle.damage = original
	assert(ok, result)
	return result, trueTypes
end

local function read(result)
	local unitsByIndex = {}
	for _, unit in result.units do
		unitsByIndex[unit.index] = unit
	end
	return CastReader.read(result.units, result.events, function(index)
		return UnitConfig[unitsByIndex[index].unitType].ability
	end)
end

local tests = {}

table.insert(tests, {
	name = "every hit's damage type matches the simulation",
	run = function()
		local checked = 0
		local seen = {}
		for seed = 1, 40 do
			local result, trueTypes = recordedFight(seed)
			local reading = read(result)
			for index, event in result.events do
				if event.kind == "Attack" or event.kind == "Damage" then
					checked += 1
					seen[trueTypes[index]] = true
					assert(
						reading.damageTypes[index] == trueTypes[index],
						string.format(
							"seed %d event %d (%s): read %s, was %s",
							seed,
							index,
							event.kind,
							tostring(reading.damageTypes[index]),
							tostring(trueTypes[index])
						)
					)
				end
			end
		end
		assert(checked > 500, "too few hits checked: " .. checked)
		assert(seen.PHYSICAL and seen.MAGIC, "expected both physical and magic hits")
	end,
})

table.insert(tests, {
	name = "every area hit lies within the area of the Area event before it, and the reading has it",
	run = function()
		local areaCount = 0
		for seed = 1, 40 do
			local result = recordedFight(seed)
			local reading = read(result)
			local cells = {}
			for _, unit in result.units do
				cells[unit.index] = { unit.column, unit.row }
			end
			local lastArea = {} -- unit index -> the area of its latest Area event
			for index, event in result.events do
				if event.kind == "Area" then
					areaCount += 1
					lastArea[event.unit] = reading.areaEvents[index]
					assert(lastArea[event.unit], string.format("seed %d event %d: Area event not read", seed, index))
				elseif event.kind == "Damage" and event.area then
					local area = lastArea[event.unit]
					local cell = cells[event.target]
					assert(area, string.format("seed %d event %d: area hit without an Area event", seed, index))
					assert(
						CastReader.contains(area, cell[1], cell[2]),
						string.format("seed %d event %d: hit outside its area", seed, index)
					)
				end
				if event.kind == "Move" or event.kind == "Dash" then
					cells[event.unit] = { event.column, event.row }
				elseif event.kind == "Summon" then
					cells[event.summon] = { event.column, event.row }
				elseif event.kind == "Pull" or event.kind == "Knockback" then
					cells[event.target] = { event.column, event.row }
				end
			end
		end
		assert(areaCount > 20, "too few areas read: " .. areaCount)
	end,
})

table.insert(tests, {
	name = "a SELF area is centered on the caster after its dash",
	run = function()
		local units = {
			{ index = 1, side = 1, column = 1, row = 1, starLevel = 2 },
			{ index = 2, side = 2, column = 4, row = 6, starLevel = 1 },
		}
		local events = {
			{ tick = 5, kind = "Cast", unit = 1, ability = "thunder_nest" },
			{ tick = 5, kind = "Dash", unit = 1, column = 4, row = 5 },
			{ tick = 5, kind = "Damage", unit = 1, target = 2, damage = 500, health = 1, shield = 0 },
			{ tick = 5, kind = "Shield", unit = 1, target = 1, shield = 500, duration = 5 },
			{ tick = 5, kind = "Move", unit = 2, column = 3, row = 6 },
		}
		local reading = CastReader.read(units, events, function()
			return UnitConfig.thunder_nest.ability
		end)
		local area = reading.areas[1][1]
		assert(area.column == 4 and area.row == 5 and area.radius == 1, "wrong area center or radius")
		assert(reading.damageTypes[3] == "MAGIC", "the self-centered area deals magic damage")
	end,
})

table.insert(tests, {
	name = "a punch is physical and its area is magic, centered on the punched unit",
	run = function()
		local units = {
			{ index = 1, side = 1, column = 3, row = 4, starLevel = 1 },
			{ index = 2, side = 2, column = 3, row = 5, starLevel = 1 },
			{ index = 3, side = 2, column = 4, row = 5, starLevel = 1 },
		}
		local events = {
			{ tick = 9, kind = "Cast", unit = 1, ability = "cinder_arc" },
			{ tick = 9, kind = "Damage", unit = 1, target = 2, damage = 180, health = 0, shield = 0 },
			{ tick = 9, kind = "Death", unit = 2 },
			{ tick = 9, kind = "Damage", unit = 1, target = 3, damage = 80, health = 500, shield = 0 },
		}
		local reading = CastReader.read(units, events, function()
			return UnitConfig.cinder_arc.ability
		end)
		assert(reading.damageTypes[2] == "PHYSICAL", "the punch is physical")
		assert(reading.damageTypes[4] == "MAGIC", "the area is magic")
		local area = reading.areas[1][1]
		assert(area.column == 3 and area.row == 5, "the area is centered where the punched unit stood")
	end,
})

table.insert(tests, {
	name = "a COPY is read with the copied ability's effects; damage-over-time ticks keep their own type",
	run = function()
		local copier = { name = "Mirror", effects = { { type = "COPY", target = "NEAREST_ENEMY" } } }
		local units = {
			{ index = 1, side = 1, column = 3, row = 4, starLevel = 1 },
			{ index = 2, side = 2, column = 3, row = 5, starLevel = 1 },
			{ index = 3, side = 2, column = 4, row = 5, starLevel = 1 },
		}
		local events = {
			{ tick = 9, kind = "Cast", unit = 1, ability = "Mirror" },
			{ tick = 9, kind = "Copy", unit = 1, target = 2, ability = "cinder_arc" },
			{ tick = 9, kind = "Damage", unit = 1, target = 2, damage = 144, health = 500, shield = 0 },
			{ tick = 9, kind = "Damage", unit = 1, target = 3, damage = 64, health = 500, shield = 0 },
			{
				tick = 30,
				kind = "Damage",
				unit = 1,
				target = 2,
				damage = 20,
				health = 480,
				shield = 0,
				dot = true,
				damageType = "MAGIC",
			},
		}
		local reading = CastReader.read(units, events, function(index)
			return if index == 1 then copier else UnitConfig.cinder_arc.ability
		end)
		expectEqual(reading.damageTypes[3], "PHYSICAL", "copied punch")
		expectEqual(reading.damageTypes[4], "MAGIC", "copied area")
		local area = reading.areas[1] and reading.areas[1][1]
		assert(area and area.column == 3 and area.row == 5, "the copied area is centered on the punched unit")
		expectEqual(reading.damageTypes[5], "MAGIC", "damage-over-time tick")
	end,
})

table.insert(tests, {
	name = "a hit that changes its target's form (a dismount) does not end the cast's reading",
	run = function()
		local units = {
			{ index = 1, side = 1, column = 3, row = 4, starLevel = 1 },
			{ index = 2, side = 2, column = 3, row = 5, starLevel = 1, form = "Mounted", formIndex = 1 },
			{ index = 3, side = 2, column = 4, row = 5, starLevel = 1 },
		}
		local events = {
			{ tick = 9, kind = "Cast", unit = 1, ability = "cinder_arc" },
			{ tick = 9, kind = "Damage", unit = 1, target = 2, damage = 180, health = 700, shield = 0, formHealth = 0 },
			{ tick = 9, kind = "Form", unit = 2, form = "Dismounted", formIndex = 2, health = 700 },
			{ tick = 9, kind = "Damage", unit = 1, target = 3, damage = 80, health = 500, shield = 0 },
		}
		local reading = CastReader.read(units, events, function()
			return UnitConfig.cinder_arc.ability
		end)
		expectEqual(reading.damageTypes[2], "PHYSICAL", "the punch")
		expectEqual(reading.damageTypes[4], "MAGIC", "the area after the dismount")
	end,
})

return tests
