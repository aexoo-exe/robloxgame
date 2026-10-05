local Abilities = require("../src/shared/Abilities")
local Battle = require("../src/shared/Battle")
local HexGrid = require("../src/shared/HexGrid")
local UnitConfig = require("../src/shared/UnitConfig")

-- docs/design/roster-v0.1.md:
-- cost, HP, AD, AP, armor, MR, attack speed, range, move, starting mana, max mana.
local SPEC = {
	Kaien = { 1, 720, 48, 100, 40, 40, 0.60, 1, 1.0, 40, 90 },
	Mira = { 1, 540, 62, 100, 18, 18, 0.78, 4, 1.0, 20, 80 },
	Bren = { 1, 740, 46, 100, 38, 34, 0.58, 1, 0.9, 40, 90 },
	Lio = { 1, 590, 58, 100, 22, 20, 0.78, 1, 1.1, 20, 80 },
	Cera = { 1, 610, 44, 100, 20, 32, 0.64, 3, 1.0, 40, 100 },
	Sola = { 1, 550, 48, 100, 18, 24, 0.68, 4, 1.0, 20, 80 },
	Kes = { 1, 600, 64, 100, 22, 18, 0.76, 1, 1.1, 20, 80 },

	Rook = { 2, 850, 66, 100, 38, 32, 0.68, 1, 1.0, 30, 90 },
	Sena = { 2, 650, 48, 100, 25, 35, 0.70, 3, 1.0, 40, 100 },
	Tarek = { 2, 890, 54, 100, 45, 40, 0.58, 1, 0.9, 40, 100 },
	Ione = { 2, 650, 69, 100, 22, 22, 0.83, 4, 1.0, 20, 80 },
	Vela = { 2, 640, 58, 100, 24, 28, 0.76, 3, 1.1, 20, 90 },
	Marek = { 2, 720, 68, 100, 28, 24, 0.84, 1, 1.1, 20, 80 },

	Veyra = { 3, 720, 55, 100, 25, 30, 0.72, 4, 1.0, 20, 80 },
	Dax = { 3, 850, 76, 100, 35, 30, 0.85, 1, 1.1, 30, 90 },
	Calyx = { 3, 900, 54, 100, 42, 48, 0.65, 2, 0.9, 40, 110 },
	Solenne = { 3, 760, 78, 100, 24, 28, 0.88, 4, 1.0, 20, 90 },
	Vael = { 3, 820, 80, 100, 30, 25, 0.89, 1, 1.1, 20, 90 },

	Orin = { 4, 1180, 58, 100, 60, 60, 0.60, 1, 0.9, 50, 110 },
	Nyra = { 4, 820, 88, 100, 28, 28, 0.90, 4, 1.0, 20, 80 },
	Torra = { 4, 1100, 78, 100, 55, 45, 0.82, 1, 1.1, 30, 100 },
	Maelin = { 4, 900, 60, 100, 32, 55, 0.72, 3, 1.0, 40, 110 },

	Astra = { 5, 980, 75, 100, 38, 45, 0.85, 4, 1.0, 30, 100 },
	Kairo = { 5, 1250, 96, 100, 60, 50, 0.80, 1, 1.1, 40, 110 },
	Sevrin = { 5, 1050, 94, 100, 42, 42, 0.98, 2, 1.1, 30, 100 },
}

-- docs/design/roster-v0.1.md: full name, origin, classes.
local TRAITS = {
	Kaien = { "Kaien Vale", "Ironveil", { "Vanguard", "Warden" } },
	Mira = { "Mira Quill", "Starfall", { "Marksman" } },
	Bren = { "Bren Ashward", "Emberwake", { "Vanguard" } },
	Lio = { "Lio Veylan", "Stormcrest", { "Duelist" } },
	Cera = { "Cera Morn", "Tideglass", { "Mystic" } },
	Sola = { "Sola Aven", "Starfall", { "Arcanist" } },
	Kes = { "Kes Vanta", "Eclipse", { "Reaver" } },
	Rook = { "Rook Ember", "Emberwake", { "Vanguard", "Duelist" } },
	Sena = { "Sena Lume", "Tideglass", { "Mystic", "Warden" } },
	Tarek = { "Tarek Flint", "Ironveil", { "Vanguard", "Warden" } },
	Ione = { "Ione Gale", "Stormcrest", { "Marksman" } },
	Vela = { "Vela Nox", "Eclipse", { "Arcanist", "Reaver" } },
	Marek = { "Marek Sol", "Emberwake", { "Duelist" } },
	Veyra = { "Veyra Storm", "Stormcrest", { "Arcanist" } },
	Dax = { "Dax Ironwind", "Ironveil", { "Duelist", "Reaver" } },
	Calyx = { "Calyx Mere", "Tideglass", { "Mystic", "Warden" } },
	Solenne = { "Solenne Ray", "Starfall", { "Marksman", "Arcanist" } },
	Vael = { "Vael Noct", "Eclipse", { "Reaver", "Duelist" } },
	Orin = { "Orin Bastion", "Ironveil", { "Vanguard", "Warden" } },
	Nyra = { "Nyra Voss", "Eclipse", { "Marksman", "Reaver" } },
	Torra = { "Torra Gale", "Stormcrest", { "Vanguard", "Duelist" } },
	Maelin = { "Maelin Shore", "Tideglass", { "Mystic", "Arcanist" } },
	Astra = { "Astra Ren", "Starfall", { "Arcanist", "Mystic" } },
	Kairo = { "Kairo Zenith", "Emberwake", { "Vanguard", "Duelist" } },
	Sevrin = { "Sevrin Null", "Eclipse", { "Reaver", "Arcanist" } },
}

-- docs/design/world-and-traits.md: trait membership.
local ORIGIN_MEMBERS = {
	Ironveil = { "Kaien", "Tarek", "Dax", "Orin" },
	Emberwake = { "Bren", "Rook", "Marek", "Kairo" },
	Tideglass = { "Cera", "Sena", "Calyx", "Maelin" },
	Stormcrest = { "Lio", "Ione", "Veyra", "Torra" },
	Starfall = { "Sola", "Mira", "Solenne", "Astra" },
	Eclipse = { "Kes", "Vela", "Vael", "Nyra", "Sevrin" },
}
local CLASS_MEMBERS = {
	Vanguard = { "Kaien", "Bren", "Rook", "Tarek", "Orin", "Kairo", "Torra" },
	Warden = { "Kaien", "Sena", "Tarek", "Calyx", "Orin" },
	Duelist = { "Lio", "Rook", "Marek", "Dax", "Vael", "Torra", "Kairo" },
	Marksman = { "Mira", "Ione", "Solenne", "Nyra" },
	Arcanist = { "Sola", "Vela", "Veyra", "Solenne", "Maelin", "Astra", "Sevrin" },
	Mystic = { "Cera", "Sena", "Calyx", "Maelin", "Astra" },
	Reaver = { "Kes", "Dax", "Vela", "Vael", "Nyra", "Sevrin" },
}

-- docs/design/roster-v0.1.md abilities, written the way abilityText (below) describes the data.
-- Dashes toward FARTHEST_ENEMY or HIGHEST_AD_ENEMY make that enemy the current target ("retarget")
-- for the new characters and Dax; Kairo and Marek are as written.
local ABILITIES = {
	Kaien = "Iron Pulse: SHIELD SELF 180/300/500 5s; STUN CURRENT_TARGET 1/1.5/2.25s",
	Mira = "Starbolt: DAMAGE CURRENT_TARGET PHYSICAL 120/190/310; BUFF SELF AttackSpeed +20/30/45% 4s",
	Bren = "Furnace Guard: SHIELD SELF 150/240/400 5s; BUFF SELF Armor +15/25/40 5s",
	Lio = "Gale Edge: DAMAGE CURRENT_TARGET PHYSICAL 115/180/290; BUFF SELF AttackSpeed +15/25/40% 4s",
	Cera = "Quiet Current: HEAL LOWEST_HP_ALLY 110/175/280; BUFF LOWEST_HP_ALLY MR +15/25/40 5s",
	Sola = "Falling Spark: AREA_DAMAGE CURRENT_TARGET r1 MAGIC 150/240/390",
	Kes = "Shadecut: DASH FARTHEST_ENEMY 2 retarget; DAMAGE FARTHEST_ENEMY PHYSICAL 145/230/370",
	Rook = "Meteor Knuckle: DAMAGE CURRENT_TARGET PHYSICAL 180/290/470; AREA_DAMAGE CURRENT_TARGET r1 MAGIC 80/130/220",
	Sena = "Moonveil: SHIELD LOWEST_HP_ALLY 180/300/480 5s; HEAL LOWEST_HP_ALLY 100/160/260",
	Tarek = "Lockplate: SHIELD SELF 230/370/600 5s; STUN CURRENT_TARGET 0.75/1.25/1.75s",
	Ione = "Skyneedle: DAMAGE FARTHEST_ENEMY PHYSICAL 220/350/560; BUFF SELF AD +10/15/25% 5s",
	Vela = "Black Arc: AREA_DAMAGE CURRENT_TARGET r1 MAGIC 210/340/550; BUFF SELF AP +15/25/40 5s",
	Marek = "Burnrush: DASH CURRENT_TARGET 2; DAMAGE CURRENT_TARGET PHYSICAL 210/335/535; BUFF SELF AttackSpeed +25/40/60% 4s",
	Veyra = "Tempest Core: AREA_DAMAGE CURRENT_TARGET r1 MAGIC 260/420/680; STUN CURRENT_TARGET 1/1.5/2s",
	Dax = "Flashbreak: DASH FARTHEST_ENEMY 3 retarget; DAMAGE FARTHEST_ENEMY PHYSICAL 300/475/750; BUFF SELF AttackSpeed +30/45/65% 4s",
	Calyx = "Glass Sanctuary: SHIELD LOWEST_HP_ALLY 270/430/690 5s; HEAL LOWEST_HP_ALLY 170/270/430",
	Solenne = "Nova Lance: AREA_DAMAGE FARTHEST_ENEMY r1 MAGIC 300/480/780; BUFF SELF AP +20/35/55 5s",
	Vael = "Nightfall Step: DASH FARTHEST_ENEMY 3 retarget; DAMAGE FARTHEST_ENEMY PHYSICAL 340/540/860; BUFF SELF AttackSpeed +25/40/60% 4s",
	Orin = "Unbroken Citadel: SHIELD SELF 450/700/1100 6s; BUFF SELF Armor +30/45/70 6s; BUFF SELF MR +30/45/70 6s",
	Nyra = "Voidline Shot: DAMAGE FARTHEST_ENEMY PHYSICAL 320/500/800; STUN FARTHEST_ENEMY 1/1.5/2.25s",
	Torra = "Thunder Descent: DASH HIGHEST_AD_ENEMY 3 retarget; AREA_DAMAGE HIGHEST_AD_ENEMY r1 MAGIC 330/525/850; STUN HIGHEST_AD_ENEMY 1/1.5/2.25s",
	Maelin = "High Tide: HEAL LOWEST_HP_ALLY 330/530/860; SHIELD LOWEST_HP_ALLY 360/580/930 6s",
	Astra = "Falling Constellation: AREA_DAMAGE HIGHEST_AD_ENEMY r2 MAGIC 400/650/1050",
	Kairo = "Heavenbreaker: DASH HIGHEST_AD_ENEMY 3; AREA_DAMAGE SELF r1 MAGIC 400/650/1050; SHIELD SELF 300/500/800 5s",
	Sevrin = "Event Horizon: DASH FARTHEST_ENEMY 3 retarget; AREA_DAMAGE FARTHEST_ENEMY r1 MAGIC 520/850/1350; BUFF SELF AttackSpeed +30/45/70% 5s",
}

-- Formats a number the way the spec strings write it: 1, 0.75, 2.25.
local function number(value: number): string
	if value == math.floor(value) then
		return string.format("%d", value)
	end
	return string.format("%g", value)
end

-- A per-star list as "a/b/c", or a constant on its own.
local function perStar(value: any): string
	if type(value) ~= "table" then
		return number(value)
	end
	local parts = {}
	for _, each in value do
		table.insert(parts, number(each))
	end
	return table.concat(parts, "/")
end

-- Describes an ability's data in the spec strings' format.
local function abilityText(ability): string
	local effects = {}
	for _, effect in ability.effects do
		local parts = { effect.type, effect.target or effect.center }
		if effect.radius then
			table.insert(parts, "r" .. perStar(effect.radius))
		end
		if effect.damageType then
			table.insert(parts, effect.damageType)
		end
		if effect.distance then
			table.insert(parts, perStar(effect.distance))
		end
		if effect.setsCurrentTarget then
			table.insert(parts, "retarget")
		end
		if effect.stat then
			table.insert(parts, effect.stat)
		end
		if effect.amount then
			table.insert(parts, perStar(effect.amount))
		end
		if effect.flat then
			table.insert(parts, "+" .. perStar(effect.flat))
		end
		if effect.percent then
			table.insert(parts, "+" .. perStar(effect.percent) .. "%")
		end
		if effect.duration then
			table.insert(parts, perStar(effect.duration) .. "s")
		end
		table.insert(effects, table.concat(parts, " "))
	end
	return ability.name .. ": " .. table.concat(effects, "; ")
end
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
	name = "the roster is exactly the 25 characters with the spec's stats",
	run = function()
		local count = 0
		local perCost = {}
		for name, unit in UnitConfig do
			count += 1
			perCost[unit.cost] = (perCost[unit.cost] or 0) + 1
			local spec = SPEC[name]
			assert(spec, "unexpected unit " .. name)
			for i, field in FIELDS do
				assert(
					unit[field] == spec[i],
					string.format("%s %s = %s, spec says %s", name, field, tostring(unit[field]), tostring(spec[i]))
				)
			end
		end
		assert(count == 25, "expected 25 characters, found " .. count)
		for cost, expected in { 7, 6, 5, 4, 3 } do
			assert(
				perCost[cost] == expected,
				string.format("%d-cost: expected %d, found %s", cost, expected, tostring(perCost[cost]))
			)
		end
	end,
})

table.insert(tests, {
	name = "every ability matches the roster doc",
	run = function()
		for name, unit in UnitConfig do
			local text = abilityText(unit.ability)
			assert(
				text == ABILITIES[name],
				string.format("%s:\n  data: %s\n  spec: %s", name, text, tostring(ABILITIES[name]))
			)
		end
	end,
})

table.insert(tests, {
	name = "every character has its full name, exactly one origin and one or two classes",
	run = function()
		for name, unit in UnitConfig do
			local spec = TRAITS[name]
			assert(unit.displayName == spec[1], name .. ": wrong full name")
			assert(type(unit.origin) == "string" and unit.origin == spec[2], name .. ": wrong origin")
			assert(type(unit.classes) == "table", name .. ": classes must be a list")
			assert(#unit.classes >= 1 and #unit.classes <= 2, name .. ": needs one or two classes")
			for i, class in spec[3] do
				assert(unit.classes[i] == class, name .. ": wrong classes")
			end
			assert(#unit.classes == #spec[3], name .. ": wrong number of classes")
		end
	end,
})

table.insert(tests, {
	name = "trait membership matches the world doc",
	run = function()
		local function membersOf(field: string, trait: string): { string }
			local members = {}
			for name, unit in UnitConfig do
				local traits = if field == "origin" then { unit.origin } else unit.classes
				if table.find(traits, trait) then
					table.insert(members, name)
				end
			end
			table.sort(members)
			return members
		end
		for field, groups in { origin = ORIGIN_MEMBERS, classes = CLASS_MEMBERS } do
			for trait, expected in groups do
				local sorted = table.clone(expected)
				table.sort(sorted)
				local actual = membersOf(field, trait)
				assert(
					table.concat(actual, ",") == table.concat(sorted, ","),
					string.format(
						"%s: expected %s, got %s",
						trait,
						table.concat(sorted, ","),
						table.concat(actual, ",")
					)
				)
			end
		end
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

-- Runs `name` against an adjacent Kaien and a back-row Mira (the farthest enemy and the one with
-- the highest AD), with full mana and Kaien as its target, for `ticks` ticks. Returns the battle
-- and the diver, near and far units.
local function diveBattle(name: string, seed: number, ticks: number)
	local CombatSim = require("../src/shared/CombatSim")
	local battle = Battle.new({
		boards = {
			{ { id = "diver", unitType = name, column = 4, row = 4 } },
			{
				{ id = "near", unitType = "Kaien", column = 4, row = 4 }, -- adjacent to the diver
				{ id = "far", unitType = "Mira", column = 4, row = 1 }, -- back row
			},
		},
		columns = 7,
		rows = 4,
		unitTypes = UnitConfig,
		ticksPerSecond = 20,
		maxTicks = 1000,
		seed = seed,
	})
	local diver, near, far = battle.units[1], battle.units[2], battle.units[3]
	assert(Battle.distance(diver, near) == 1, "test setup: Kaien starts adjacent")
	assert(Battle.distance(diver, far) > 3, "test setup: Mira starts out of dash range for adjacency")
	diver.mana = diver.maxMana
	diver.target = near
	for _ = 1, ticks do
		CombatSim.step(battle)
	end
	return battle, diver, near, far
end

table.insert(tests, {
	name = "divers that retarget dive the far enemy, hit it, and keep attacking it",
	run = function()
		local divers = {}
		for name, unit in UnitConfig do
			for _, effect in unit.ability.effects do
				if effect.type == "DASH" and effect.setsCurrentTarget then
					table.insert(divers, name)
				end
			end
		end
		table.sort(divers)
		assert(
			table.concat(divers, ",") == "Dax,Kes,Sevrin,Torra,Vael",
			"unexpected divers: " .. table.concat(divers, ",")
		)

		-- Kes's 2-hex dash lands short of Mira (4 hexes away); see the next test.
		for _, name in { "Dax", "Sevrin", "Torra", "Vael" } do
			for seed = 1, 10 do
				local battle, diver, near, far = diveBattle(name, seed, 100)
				local dashed, abilityHit, attacksOnFar, attacksOnNear = false, false, 0, 0
				local casts = 0
				for _, event in battle.events do
					-- Once Mira is dead, or a second cast picks a new farthest enemy, the diver may go
					-- back to Kaien.
					if event.kind == "Death" and event.unit == far.index then
						break
					end
					if event.kind == "Cast" and event.unit == diver.index then
						casts += 1
						if casts > 1 then
							break
						end
					end
					if event.unit == diver.index then
						if event.kind == "Dash" then
							dashed = true
						elseif event.kind == "Damage" and event.target == far.index then
							abilityHit = true
						elseif event.kind == "Attack" and event.target == far.index then
							attacksOnFar += 1
						elseif event.kind == "Attack" and event.target == near.index then
							attacksOnNear += 1
						end
					end
				end
				local label = string.format("%s (seed %d)", name, seed)
				assert(dashed, label .. " did not dash")
				assert(abilityHit, label .. ": the ability did not hit the far enemy")
				assert(attacksOnFar > 0 and attacksOnNear == 0, label .. " should attack Mira after the dive")
			end
		end
	end,
})

table.insert(tests, {
	name = "a retargeting dash that lands out of range falls back to the nearest enemy (Kes)",
	run = function()
		-- The engine keeps a target only while it is in range (CombatSim step 2), so Kes's 2-hex dash
		-- toward a target 4 hexes away hits it with Shadecut but then goes back to the nearest enemy.
		local battle, kes, near, far = diveBattle("Kes", 1, 40)
		local landed, hitFar, attackedNear = nil, false, false
		for _, event in battle.events do
			if event.unit == kes.index then
				if event.kind == "Dash" then
					landed = event
				elseif event.kind == "Damage" and event.target == far.index then
					hitFar = true
				elseif event.kind == "Attack" and event.target == near.index then
					attackedNear = true
				end
			end
		end
		assert(landed, "Kes did not dash")
		assert(HexGrid.distance(landed.column, landed.row, far.column, far.row) > 1, "test setup: dash lands short")
		assert(hitFar, "Shadecut should still hit the farthest enemy")
		assert(attackedNear, "Kes should fall back to the nearest enemy")
	end,
})

table.insert(tests, {
	name = "Marek's dash moves him only when his current target is more than one hex away",
	run = function()
		-- Adjacent target: Burnrush hits it without moving.
		local battle, marek = diveBattle("Marek", 1, 1)
		for _, event in battle.events do
			assert(not (event.unit == marek.index and event.kind == "Dash"), "Marek dashed to an adjacent target")
		end

		-- Target three hexes away: he dashes toward it.
		battle, marek = diveBattle("Marek", 1, 0)
		local far = battle.units[3]
		Battle.relocate(battle, far, 4, 7)
		marek.target = far
		Abilities.cast(battle, marek)
		local dashed = false
		for _, event in battle.events do
			dashed = dashed or (event.unit == marek.index and event.kind == "Dash")
		end
		assert(dashed, "Marek did not dash toward a distant target")
	end,
})

return tests
