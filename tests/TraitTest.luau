-- The trait system. The real TraitConfig is empty until the new traits are built, so the rules
-- are tested with a test-only trait config over the new origins and classes: counting, every
-- breakpoint, replacement, stacking, all-allies bonuses, combat-start shields, max health bonuses,
-- and that boards without active traits fight exactly as before.

local Battle = require("../src/shared/Battle")
local Board = require("../src/shared/Board")
local CombatSim = require("../src/shared/CombatSim")
local TraitConfig = require("../src/shared/TraitConfig")
local Traits = require("../src/shared/Traits")
local UnitConfig = require("../src/shared/UnitConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local function buff(stat: string, amount: number, percent: boolean?, target: string?)
	return {
		type = "BUFF",
		target = target or "MEMBERS",
		stat = stat,
		flat = if percent then nil else amount,
		percent = if percent then amount else nil,
	}
end

-- Test-only traits (numbers are arbitrary but distinct).
local TEST_TRAITS = {
	Hunters = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("AD", 10, true) } },
			{ count = 4, effects = { buff("AD", 20, true), buff("AttackSpeed", 22, true) } },
			{ count = 5, effects = { buff("AD", 30, true), buff("AttackSpeed", 36, true) } },
		},
	},
	Titans = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { { type = "SHIELD", target = "MEMBERS", amount = 140, duration = 6 } } },
			{ count = 3, effects = { buff("MaxHealth", 28, true), buff("Armor", 25) } },
		},
	},
	Guardian = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("Armor", 18), buff("MR", 18) } },
			{ count = 4, effects = { buff("Armor", 38), buff("MR", 38), buff("MaxHealth", 12, true) } },
		},
	},
	Support = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("AP", 20), buff("MR", 8, false, "ALL_ALLIES") } },
			{ count = 4, effects = { buff("AP", 42), buff("Armor", 18, false, "ALL_ALLIES") } },
		},
	},
}

-- Membership sizes from docs/design/revamp-structure.md (origins and classes), with the
-- Overhaul 1 faction and class changes.
local MEMBER_COUNTS = {
	Shinobi = 5,
	Cursed = 6,
	Crew = 4,
	Titans = 4,
	Corps = 4,
	Spirit = 5,
	Heroes = 5,
	Hunters = 5,
	Arcane = 4,
	Blade = 10,
	Brawler = 11,
	Caster = 11,
	Marksman = 6,
	Assassin = 9,
	Guardian = 8,
	Support = 5,
}

-- Placed units from a list of character ids (unit ids are "1", "2", ...).
local function placed(ids: { string }): { any }
	local units = {}
	for i, unitType in ids do
		table.insert(units, { id = tostring(i), unitType = unitType })
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
	local function hasTrait(id, traitName)
		return UnitConfig[id].origin == traitName or table.find(UnitConfig[id].classes, traitName) ~= nil
	end
	local stats, shields = {}, {}
	for traitName, trait in TEST_TRAITS do
		local count = 0
		for id in distinct do
			if hasTrait(id, traitName) then
				count += 1
			end
		end
		local reached = nil
		for _, breakpoint in trait.breakpoints do
			if count >= breakpoint.count then
				reached = breakpoint
			end
		end
		for _, effect in if reached then reached.effects else {} do
			if effect.target == "ALL_ALLIES" or hasTrait(unitType, traitName) then
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
	local bonus = Traits.bonuses(units, TEST_TRAITS)[unitId] or { stats = {}, shields = {} }
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

local function onBoard(ids: { string }): { any }
	local units = {}
	for i, unitType in ids do
		table.insert(units, { id = tostring(i), unitType = unitType, column = i, row = 4 })
	end
	return units
end

local tests = {}

table.insert(tests, {
	name = "the real trait config is empty, so no trait counts and no bonus applies",
	run = function()
		expectEqual(next(TraitConfig), nil, "TraitConfig entries")
		local board = placed({ "flashline", "cinder_arc", "thunder_nest", "iron_rush", "titanheart" })
		expectEqual(#Traits.summary(board), 0, "traits listed")
		expectEqual(next(Traits.bonuses(board)), nil, "bonuses")
	end,
})

table.insert(tests, {
	name = "membership derived from UnitConfig has the sizes listed in Block 1",
	run = function()
		for trait, size in MEMBER_COUNTS do
			expectEqual(#(Traits.members[trait] or {}), size, trait .. " members")
		end
		for trait in Traits.members do
			assert(MEMBER_COUNTS[trait], "unexpected trait " .. trait)
		end
	end,
})

table.insert(tests, {
	name = "counting: different characters only, only configured traits, and bench units never count",
	run = function()
		local counts = Traits.count(placed({ "iron_rush", "iron_rush", "iron_rush", "titanheart" }), TEST_TRAITS)
		expectEqual(counts.Titans, 2, "copies count once")
		expectEqual(counts.Guardian, 2, "Guardian")
		expectEqual(counts.Blade, nil, "traits outside the config are not counted")

		local board = Board.new(7, 4, 9)
		Board.addUnit(board, "a", "iron_rush")
		Board.addUnit(board, "b", "titanheart")
		Board.addUnit(board, "c", "skyboulder")
		Board.moveUnit(board, "a", { column = 1, row = 1 })
		Board.moveUnit(board, "b", { column = 2, row = 1 })
		-- skyboulder stays on the bench.
		expectEqual(Traits.count(Board.getPlacedUnits(board), TEST_TRAITS).Titans, 2, "Titans without the bench")
	end,
})

table.insert(tests, {
	name = "every breakpoint of every test trait activates at its count and gives its exact bonus",
	run = function()
		for traitName, trait in TEST_TRAITS do
			for level, breakpoint in trait.breakpoints do
				local ids = table.move(Traits.members[traitName], 1, breakpoint.count, 1, {})
				local units = placed(ids)
				local state
				for _, each in Traits.summary(units, TEST_TRAITS) do
					if each.name == traitName then
						state = each
					end
				end
				local label = string.format("%s at %d", traitName, breakpoint.count)
				expectEqual(state.level, level, label .. " level")
				expectEqual(state.active, true, label .. " active")
				local fewer = placed(table.move(ids, 1, breakpoint.count - 1, 1, {}))
				expectEqual(
					Traits.levelFor(traitName, Traits.count(fewer, TEST_TRAITS)[traitName] or 0, TEST_TRAITS),
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
		-- Guardian 4: +38 armor, not +18 + +38. iron_rush is also Titans 2 (with titanheart).
		local units = placed({ "iron_rush", "marsh_fortress", "titanheart", "elastic_wardrum" })
		local bonuses = Traits.bonuses(units, TEST_TRAITS)
		expectEqual(bonuses["2"].stats.Armor.flat, 38, "marsh_fortress armor at Guardian 4")
		expectEqual(bonuses["2"].stats.MaxHealth.percent, 12, "marsh_fortress max health at Guardian 4")
		expectEqual(#bonuses["1"].shields, 1, "iron_rush also gets the Titans 2 shield")
		-- Percent bonuses add: a Hunters 4 board where one member is also Support... use Titans 3 + Guardian 4.
		local stacked =
			Traits.bonuses(placed({ "iron_rush", "titanheart", "boiling_crown", "marsh_fortress" }), TEST_TRAITS)
		expectEqual(stacked["1"].stats.Armor.flat, 25 + 38, "Titans 3 armor + Guardian 4 armor")
		expectEqual(stacked["1"].stats.MaxHealth.percent, 28 + 12, "Titans 3 + Guardian 4 max health")
	end,
})

table.insert(tests, {
	name = "all-allies bonuses reach every placed unit, members or not",
	run = function()
		local bonuses = Traits.bonuses(placed({ "bitter_vapor", "blooming_aid", "flashline", "spurshot" }), TEST_TRAITS)
		for _, id in { "3", "4" } do
			expectEqual(bonuses[id].stats.MR.flat, 8, "non-member " .. id .. " MR")
			assert(bonuses[id].stats.AP == nil, "non-members get no member AP")
		end
		expectEqual(bonuses["1"].stats.AP.flat, 20, "member AP")
	end,
})

table.insert(tests, {
	name = "trait shields apply at combat start and scale with ability power",
	run = function()
		local board = onBoard({ "iron_rush", "titanheart" })
		local result = fight({ board, {} }, { Traits.bonuses(board, TEST_TRAITS), {} })
		local shields = 0
		for _, event in result.events do
			if event.kind == "Shield" and event.tick == 0 then
				shields += 1
				expectEqual(event.source, "Titans", "shield source")
				expectEqual(event.shield, 140, "shield at 100 AP")
				expectEqual(event.duration, 6, "shield duration")
			end
		end
		expectEqual(shields, 2, "shields at tick 0")

		-- With +20 AP (Support 2 on a member), a shield of 140 would be 168: check the scaling path.
		local battle = Battle.new({
			boards = { onBoard({ "iron_rush" }), {} },
			columns = 7,
			rows = 4,
			unitTypes = UnitConfig,
			ticksPerSecond = 20,
			maxTicks = 10,
			seed = 1,
		})
		Battle.applyStartBonus(battle, battle.units[1], {
			stats = { AP = { flat = 20, percent = 0 } },
			shields = { { amount = 140, duration = 6, source = "Test" } },
		})
		expectEqual(battle.units[1].shield, 168, "shield scaled by 120 AP")
	end,
})

table.insert(tests, {
	name = "a max health trait bonus raises max and current health at combat start",
	run = function()
		local board = onBoard({ "iron_rush", "titanheart", "skyboulder" }) -- Titans 3: +28% max health
		local plain = fight({ board, {} }, nil)
		local bonused = fight({ board, {} }, { Traits.bonuses(board, TEST_TRAITS), {} })
		for i = 1, 3 do
			local base = plain.units[i].maxHealth
			expectEqual(bonused.units[i].maxHealth, math.round(base * 1.28), "unit " .. i .. " max health")
		end
	end,
})

table.insert(tests, {
	name = "a board with no active traits fights exactly as before",
	run = function()
		-- One unit per origin, sharing no configured test trait.
		local quiet = onBoard({ "flashline", "iron_rush", "bitter_vapor", "wolfstep", "spurshot" })
		for _, state in Traits.summary(quiet, TEST_TRAITS) do
			assert(not state.active, "test setup: " .. state.name .. " is active")
		end
		local enemy = onBoard({ "cinder_arc", "titanheart", "null_edge", "orbit_breaker" })
		for _, state in Traits.summary(enemy, TEST_TRAITS) do
			assert(not state.active, "test setup: enemy " .. state.name .. " is active")
		end
		for seed = 1, 5 do
			local before = fight({ quiet, enemy }, nil, seed)
			local after = fight(
				{ quiet, enemy },
				{ Traits.bonuses(quiet, TEST_TRAITS), Traits.bonuses(enemy, TEST_TRAITS) },
				seed
			)
			expectEqual(#after.events, #before.events, "event count")
			for i, event in before.events do
				for key, value in event do
					expectEqual(after.events[i][key], value, string.format("seed %d event %d %s", seed, i, key))
				end
			end
			expectEqual(after.winner, before.winner, "winner")
		end
	end,
})

return tests
