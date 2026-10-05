-- Traits: config against docs/design/world-and-traits.md, counting, breakpoints, stacking,
-- all-allies bonuses, Warden shields, and that boards without active traits fight as before.

local Battle = require("../src/shared/Battle")
local Board = require("../src/shared/Board")
local CombatSim = require("../src/shared/CombatSim")
local TraitConfig = require("../src/shared/TraitConfig")
local Traits = require("../src/shared/Traits")
local UnitConfig = require("../src/shared/UnitConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

-- docs/design/balance-pass-v0.4.md section 1, written the way traitText (below) describes the config.
local SPEC = {
	Ironveil = "origin | 2: MEMBERS Armor +14, MEMBERS MR +14 | 3: MEMBERS Armor +32, MEMBERS MR +32",
	Emberwake = "origin | 2: MEMBERS AD +14% | 3: MEMBERS AD +28%, MEMBERS AttackSpeed +18%",
	Tideglass = "origin | 2: MEMBERS AP +18, ALL_ALLIES MR +9 | 3: MEMBERS AP +40, ALL_ALLIES MR +20",
	Stormcrest = "origin | 2: MEMBERS AttackSpeed +18% | 3: MEMBERS AttackSpeed +40%, MEMBERS MoveSpeed +18%",
	Starfall = "origin | 2: MEMBERS AP +24 | 3: MEMBERS AP +52",
	Eclipse = "origin | 2: MEMBERS AD +12%, MEMBERS AP +12 | 3: MEMBERS AD +23%, MEMBERS AP +23 | 4: MEMBERS AD +38%, MEMBERS AP +45",
	Vanguard = "class | 2: MEMBERS Armor +12, MEMBERS MR +12 | 4: MEMBERS Armor +25, MEMBERS MR +25 | 5: MEMBERS Armor +42, MEMBERS MR +42",
	Warden = "class | 2: MEMBERS SHIELD 140 6s | 3: MEMBERS SHIELD 310 6s",
	Duelist = "class | 2: MEMBERS AttackSpeed +14% | 4: MEMBERS AttackSpeed +32% | 5: MEMBERS AttackSpeed +55%",
	Marksman = "class | 2: MEMBERS AD +14% | 3: MEMBERS AD +33%",
	Arcanist = "class | 2: MEMBERS AP +18 | 4: MEMBERS AP +40 | 5: MEMBERS AP +68",
	Mystic = "class | 2: ALL_ALLIES MR +12, MEMBERS AP +12 | 3: ALL_ALLIES MR +28, MEMBERS AP +30",
	Reaver = "class | 2: MEMBERS AD +12%, MEMBERS AttackSpeed +12% | 4: MEMBERS AD +23%, MEMBERS AttackSpeed +28% | 5: MEMBERS AD +38%, MEMBERS AttackSpeed +50%",
}

-- docs/design/world-and-traits.md membership lists.
local MEMBERS = {
	Ironveil = { "Kaien", "Tarek", "Dax", "Orin" },
	Emberwake = { "Bren", "Rook", "Marek", "Kairo" },
	Tideglass = { "Cera", "Sena", "Calyx", "Maelin" },
	Stormcrest = { "Lio", "Ione", "Veyra", "Torra" },
	Starfall = { "Sola", "Mira", "Solenne", "Astra" },
	Eclipse = { "Kes", "Vela", "Vael", "Nyra", "Sevrin" },
	Vanguard = { "Kaien", "Bren", "Rook", "Tarek", "Orin", "Kairo", "Torra" },
	Warden = { "Kaien", "Sena", "Tarek", "Calyx", "Orin" },
	Duelist = { "Lio", "Rook", "Marek", "Dax", "Vael", "Torra", "Kairo" },
	Marksman = { "Mira", "Ione", "Solenne", "Nyra" },
	Arcanist = { "Sola", "Vela", "Veyra", "Solenne", "Maelin", "Astra", "Sevrin" },
	Mystic = { "Cera", "Sena", "Calyx", "Maelin", "Astra" },
	Reaver = { "Kes", "Dax", "Vela", "Vael", "Nyra", "Sevrin" },
}

local function traitText(trait): string
	local parts = { trait.kind }
	for _, breakpoint in trait.breakpoints do
		local effects = {}
		for _, effect in breakpoint.effects do
			if effect.type == "BUFF" then
				local amount = if effect.percent then "+" .. effect.percent .. "%" else "+" .. effect.flat
				table.insert(effects, string.format("%s %s %s", effect.target, effect.stat, amount))
			else
				table.insert(
					effects,
					string.format("%s %s %d %ds", effect.target, effect.type, effect.amount, effect.duration)
				)
			end
		end
		table.insert(parts, breakpoint.count .. ": " .. table.concat(effects, ", "))
	end
	return table.concat(parts, " | ")
end

-- Placed units from a list of character names (ids are "1", "2", ...).
local function placed(names: { string }): { any }
	local units = {}
	for i, name in names do
		table.insert(units, { id = tostring(i), unitType = name })
	end
	return units
end

-- An independent statement of the rules, used as the oracle for every breakpoint.
local function expectedBonus(units, unitId: string)
	local unitType
	local distinct = {}
	for _, unit in units do
		distinct[unit.unitType] = true
		if unit.id == unitId then
			unitType = unit.unitType
		end
	end
	local stats, shields = {}, {}
	for traitName, trait in TraitConfig do
		local count = 0
		for name in distinct do
			if UnitConfig[name].origin == traitName or table.find(UnitConfig[name].classes, traitName) then
				count += 1
			end
		end
		local reached = nil
		for _, breakpoint in trait.breakpoints do
			if count >= breakpoint.count then
				reached = breakpoint
			end
		end
		local isMember = UnitConfig[unitType].origin == traitName or table.find(UnitConfig[unitType].classes, traitName)
		for _, effect in if reached then reached.effects else {} do
			if effect.target == "ALL_ALLIES" or isMember then
				if effect.type == "BUFF" then
					local stat = stats[effect.stat] or { flat = 0, percent = 0 }
					stat.flat += effect.flat or 0
					stat.percent += effect.percent or 0
					stats[effect.stat] = stat
				else
					table.insert(shields, effect.amount)
				end
			end
		end
	end
	return stats, shields
end

local function expectBonusMatches(units, unitId: string, label: string)
	local bonus = Traits.bonuses(units)[unitId] or { stats = {}, shields = {} }
	local stats, shields = expectedBonus(units, unitId)
	for stat, expected in stats do
		local actual = bonus.stats[stat] or { flat = 0, percent = 0 }
		expectEqual(actual.flat, expected.flat, label .. " " .. stat .. " flat")
		expectEqual(actual.percent, expected.percent, label .. " " .. stat .. " percent")
	end
	for stat in bonus.stats do
		assert(stats[stat], label .. ": unexpected bonus to " .. stat)
	end
	expectEqual(#bonus.shields, #shields, label .. " shields")
end

local function fight(boards, startBonuses, seed: number?)
	return CombatSim.run({
		boards = boards,
		columns = 7,
		rows = 4,
		unitTypes = UnitConfig,
		ticksPerSecond = 20,
		maxTicks = 1000,
		seed = seed or 1,
		startBonuses = startBonuses,
	})
end

local function onBoard(names: { string }): { any }
	local units = {}
	for i, name in names do
		table.insert(units, { id = tostring(i), unitType = name, column = i, row = 4 })
	end
	return units
end

local tests = {}

table.insert(tests, {
	name = "trait config matches the world doc",
	run = function()
		local count = 0
		for name, trait in TraitConfig do
			count += 1
			assert(SPEC[name], "unexpected trait " .. name)
			expectEqual(traitText(trait), SPEC[name], name)
			for _, breakpoint in trait.breakpoints do
				for _, effect in breakpoint.effects do
					if effect.type == "BUFF" then
						assert(Battle.StatFields[effect.stat], name .. ": unknown stat " .. tostring(effect.stat))
					end
				end
			end
		end
		expectEqual(count, 13, "traits")
	end,
})

table.insert(tests, {
	name = "membership derived from UnitConfig matches the world doc",
	run = function()
		for trait, expected in MEMBERS do
			local sorted = table.clone(expected)
			table.sort(sorted)
			expectEqual(table.concat(Traits.members[trait], ","), table.concat(sorted, ","), trait)
			assert(TraitConfig[trait], "no config for " .. trait)
		end
		for trait in Traits.members do
			assert(MEMBERS[trait], "a character has an unknown trait: " .. trait)
		end
	end,
})

table.insert(tests, {
	name = "counting: different characters only, and bench units never count",
	run = function()
		local counts = Traits.count(placed({ "Kaien", "Kaien", "Kaien", "Tarek" }))
		expectEqual(counts.Ironveil, 2, "two Kaien copies count once")
		expectEqual(counts.Vanguard, 2, "Vanguard")
		expectEqual(counts.Warden, 2, "Warden")

		local board = Board.new(7, 4, 9)
		Board.addUnit(board, "a", "Kaien")
		Board.addUnit(board, "b", "Tarek")
		Board.addUnit(board, "c", "Orin")
		Board.moveUnit(board, "a", { column = 1, row = 1 })
		Board.moveUnit(board, "b", { column = 2, row = 1 })
		-- Orin stays on the bench.
		counts = Traits.count(Board.getPlacedUnits(board))
		expectEqual(counts.Ironveil, 2, "Ironveil without the benched Orin")
		local summary = Traits.summary(Board.getPlacedUnits(board))
		for _, state in summary do
			assert(state.count <= 2, state.name .. " counted the bench")
		end
	end,
})

table.insert(tests, {
	name = "every breakpoint of every trait activates at its count and gives its exact bonus",
	run = function()
		for traitName, trait in TraitConfig do
			for level, breakpoint in trait.breakpoints do
				local names = table.move(Traits.members[traitName], 1, breakpoint.count, 1, {})
				local units = placed(names)
				local state
				for _, each in Traits.summary(units) do
					if each.name == traitName then
						state = each
					end
				end
				local label = string.format("%s at %d", traitName, breakpoint.count)
				expectEqual(state.level, level, label .. " level")
				expectEqual(state.active, true, label .. " active")
				-- One short of the breakpoint stays on the level below.
				local fewer = placed(table.move(names, 1, breakpoint.count - 1, 1, {}))
				expectEqual(
					Traits.levelFor(traitName, Traits.count(fewer)[traitName] or 0),
					level - 1,
					label .. " minus one"
				)
				for _, unit in units do
					expectBonusMatches(units, unit.id, label .. " " .. unit.unitType)
				end
			end
		end
	end,
})

table.insert(tests, {
	name = "a higher breakpoint replaces the lower one; different traits stack",
	run = function()
		-- Vanguard 4 (Kaien, Bren, Rook, Tarek): +25 armor, not +12 + +25.
		local units = placed({ "Kaien", "Bren", "Rook", "Tarek" })
		local bren = Traits.bonuses(units)["2"]
		expectEqual(bren.stats.Armor.flat, 25, "Bren armor at Vanguard 4")
		-- Kaien also has Ironveil 2 (Kaien, Tarek): +25 Vanguard + 14 Ironveil.
		local kaien = Traits.bonuses(units)["1"]
		expectEqual(kaien.stats.Armor.flat, 39, "Kaien armor from Vanguard 4 and Ironveil 2")
		expectEqual(kaien.stats.MR.flat, 39, "Kaien MR from Vanguard 4 and Ironveil 2")
		-- Percent bonuses add: Dax with Duelist 2 (Dax, Lio) and Reaver 2 (Dax, Kes).
		local dax = Traits.bonuses(placed({ "Dax", "Lio", "Kes" }))["1"]
		expectEqual(dax.stats.AttackSpeed.percent, 26, "Dax attack speed 14% + 12%")
		expectEqual(dax.stats.AD.percent, 12, "Dax AD from Reaver")
	end,
})

table.insert(tests, {
	name = "all-allies bonuses reach every unit on the board, members or not",
	run = function()
		-- Tideglass 2 (Cera, Sena): all allies +9 MR; Mystic 2 (Cera, Sena): all allies +12 MR.
		local bonuses = Traits.bonuses(placed({ "Cera", "Sena", "Kes", "Mira" }))
		for _, id in { "3", "4" } do
			expectEqual(bonuses[id].stats.MR.flat, 21, "non-member " .. id .. " MR")
			assert(bonuses[id].stats.AP == nil, "non-members get no member AP")
		end
		expectEqual(bonuses["1"].stats.AP.flat, 30, "Cera AP: Tideglass 18 + Mystic 12")
	end,
})

table.insert(tests, {
	name = "trait stat bonuses apply in combat; percent AD applies after star scaling",
	run = function()
		-- Rook (2-star) and Bren: Emberwake 2 gives +14% AD.
		local boards = {
			{
				{ id = "rook", unitType = "Rook", starLevel = 2, column = 4, row = 4 },
				{ id = "bren", unitType = "Bren", column = 3, row = 4 },
			},
			{},
		}
		local battle = Battle.new({
			boards = boards,
			columns = 7,
			rows = 4,
			unitTypes = UnitConfig,
			ticksPerSecond = 20,
			maxTicks = 10,
			seed = 1,
		})
		local bonuses = Traits.bonuses(boards[1])
		local rook = battle.units[1]
		Battle.applyStartBonus(battle, rook, bonuses.rook)
		-- 66 AD x 1.5 (2-star) = 99; x 1.14 = 112.86.
		assert(math.abs(Battle.stat(battle, rook, "AD") - 112.86) < 1e-9, "Rook AD " .. Battle.stat(battle, rook, "AD"))
		-- An ability buff stacks with it: +20% more makes 99 x 1.34.
		Battle.buff(battle, rook, rook, "AD", 0, 20, 4)
		assert(math.abs(Battle.stat(battle, rook, "AD") - 99 * 1.34) < 1e-9, "trait and ability buffs should add")
		-- The trait bonus never expires.
		battle.tick = 100000
		Battle.expire(battle)
		assert(math.abs(Battle.stat(battle, rook, "AD") - 112.86) < 1e-9, "trait bonus expired")
	end,
})

table.insert(tests, {
	name = "Warden shields are applied at combat start and scale with ability power",
	run = function()
		-- Kaien and Tarek: Warden 2 (140 for 6s). Sena with Calyx: Warden 2 as well, and Mystic 2
		-- (+12 AP) and Tideglass 2 (+18 AP) make their AP 130, so their shields are 182.
		for _, case in
			{
				{ names = { "Kaien", "Tarek" }, shield = 140 },
				{ names = { "Sena", "Calyx" }, shield = 182 },
				{ names = { "Kaien", "Tarek", "Sena", "Calyx" }, shield = nil },
			}
		do
			local board = onBoard(case.names)
			local result = fight({ board, {} }, { Traits.bonuses(board), {} })
			local shields = 0
			for _, event in result.events do
				if event.kind == "Shield" and event.tick == 0 then
					shields += 1
					expectEqual(event.source, "Warden", "shield source")
					expectEqual(event.unit, event.target, "shield on the Warden itself")
					expectEqual(event.duration, 6, "shield duration")
					if case.shield then
						expectEqual(event.shield, case.shield, table.concat(case.names, "+") .. " shield")
					end
				end
			end
			expectEqual(shields, #case.names, table.concat(case.names, "+") .. " shields at tick 0")
		end
		-- Warden 3 and above: 310 each (Kaien, Tarek and Orin get no AP bonus).
		local board = onBoard({ "Kaien", "Tarek", "Orin", "Sena" })
		local result = fight({ board, {} }, { Traits.bonuses(board), {} })
		for _, event in result.events do
			if event.kind == "Shield" and event.tick == 0 and result.units[event.target].unitType ~= "Sena" then
				expectEqual(event.shield, 310, "Warden 3+ shield")
			end
		end
	end,
})

table.insert(tests, {
	name = "a board with no active traits fights exactly as before",
	run = function()
		-- Six characters that share no trait with each other (one per origin), against another such board.
		local quiet = onBoard({ "Kaien", "Mira", "Veyra", "Cera", "Kes", "Marek" })
		for _, state in Traits.summary(quiet) do
			assert(not state.active, "test setup: " .. state.name .. " is active")
		end
		local enemy = onBoard({ "Bren", "Sola", "Ione", "Dax" })
		for _, state in Traits.summary(enemy) do
			assert(not state.active, "test setup: enemy " .. state.name .. " is active")
		end
		for seed = 1, 5 do
			local before = fight({ quiet, enemy }, nil, seed)
			local after = fight({ quiet, enemy }, { Traits.bonuses(quiet), Traits.bonuses(enemy) }, seed)
			expectEqual(#after.events, #before.events, "event count")
			for i, event in before.events do
				local other = after.events[i]
				for key, value in event do
					expectEqual(other[key], value, string.format("seed %d event %d %s", seed, i, key))
				end
			end
			expectEqual(after.winner, before.winner, "winner")
		end
	end,
})

return tests
