local Abilities = require("../src/shared/Abilities")
local Battle = require("../src/shared/Battle")
local UnitConfig = require("../src/shared/UnitConfig")

-- docs/design/combat-and-roster.md section 3:
-- cost, HP, AD, AP, armor, MR, attack speed, range, move, starting mana, max mana.
local SPEC = {
	Kaien = { 1, 720, 48, 100, 40, 40, 0.60, 1, 1.0, 40, 90 },
	Mira = { 1, 540, 62, 100, 18, 18, 0.78, 4, 1.0, 20, 80 },
	Rook = { 2, 850, 66, 100, 38, 32, 0.68, 1, 1.0, 30, 90 },
	Sena = { 2, 650, 48, 100, 25, 35, 0.70, 3, 1.0, 40, 100 },
	Veyra = { 3, 720, 55, 100, 25, 30, 0.72, 4, 1.0, 20, 80 },
	Dax = { 3, 850, 76, 100, 35, 30, 0.85, 1, 1.1, 30, 90 },
	Orin = { 4, 1180, 58, 100, 60, 60, 0.60, 1, 0.9, 50, 110 },
	Nyra = { 4, 820, 88, 100, 28, 28, 0.90, 4, 1.0, 20, 80 },
	Astra = { 5, 980, 75, 100, 38, 45, 0.85, 4, 1.0, 30, 100 },
	Kairo = { 5, 1250, 96, 100, 60, 50, 0.80, 1, 1.1, 40, 110 },
}
local FIELDS = {
	"cost",
	"health",
	"attackDamage",
	"abilityPower",
	"armor",
	"magicResist",
	"attacksPerSecond",
	"range",
	"moveSpeed",
	"startingMana",
	"maxMana",
}

-- The event each effect type produces.
local EVENT_FOR_EFFECT = {
	DAMAGE = "Damage",
	AREA_DAMAGE = "Damage",
	HEAL = "Heal",
	SHIELD = "Shield",
	STUN = "Stun",
	BUFF = "Buff",
	DASH = "Dash",
}

local tests = {}

table.insert(tests, {
	name = "the roster is exactly the ten characters with the spec's stats",
	run = function()
		local count = 0
		for name, unit in UnitConfig do
			count += 1
			local spec = SPEC[name]
			assert(spec, "unexpected unit " .. name)
			for i, field in FIELDS do
				assert(
					unit[field] == spec[i],
					string.format("%s %s = %s, spec says %s", name, field, tostring(unit[field]), tostring(spec[i]))
				)
			end
		end
		assert(count == 10, "expected 10 characters, found " .. count)
	end,
})

table.insert(tests, {
	name = "every ability is valid data for the generic interpreter",
	run = function()
		for name, unit in UnitConfig do
			local ok, reason = Abilities.validate(unit.ability)
			assert(ok, name .. ": " .. tostring(reason))
		end
	end,
})

table.insert(tests, {
	name = "every ability runs through the interpreter at 1, 2 and 3 stars and applies each effect",
	run = function()
		for name, unit in UnitConfig do
			for starLevel = 1, 3 do
				-- The caster stands back with a hurt ally beside it, facing three enemies 3+ hexes
				-- away (so dashes have somewhere to go).
				local battle = Battle.new({
					boards = {
						{
							{ id = "caster", unitType = name, starLevel = starLevel, column = 4, row = 2 },
							{ id = "ally", unitType = "Orin", column = 3, row = 2 },
						},
						{
							{ id = "e1", unitType = "Kaien", column = 4, row = 3 },
							{ id = "e2", unitType = "Nyra", column = 3, row = 1 },
							{ id = "e3", unitType = "Rook", column = 5, row = 4 },
						},
					},
					columns = 7,
					rows = 4,
					unitTypes = UnitConfig,
					ticksPerSecond = 20,
					maxTicks = 1000,
					seed = starLevel,
				})
				local caster, ally = battle.units[1], battle.units[2]
				ally.health = ally.maxHealth // 2
				caster.target = battle.units[3]

				local ok, err = pcall(Abilities.cast, battle, caster)
				assert(ok, string.format("%s %d-star cast failed: %s", name, starLevel, tostring(err)))

				local seen = {}
				for _, event in battle.events do
					seen[event.kind] = true
				end
				assert(seen.Cast, name .. ": no Cast event")
				for index, effect in unit.ability.effects do
					local kind = EVENT_FOR_EFFECT[effect.type]
					assert(
						seen[kind],
						string.format(
							"%s %d-star effect %d (%s) produced no %s event",
							name,
							starLevel,
							index,
							effect.type,
							kind
						)
					)
				end
				assert(caster.mana == 0, name .. ": mana should be 0 after casting")
			end
		end
	end,
})

return tests
