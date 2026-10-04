local MatchRules = require("../src/shared/MatchRules")
local SeededRandom = require("../src/shared/SeededRandom")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local tests = {}

table.insert(tests, {
	name = "stages and base damage follow the spec table",
	run = function()
		-- { round, stage, base damage } at each boundary.
		local cases = {
			{ 1, 1, 2 },
			{ 4, 1, 2 },
			{ 5, 2, 4 },
			{ 8, 2, 4 },
			{ 9, 3, 6 },
			{ 12, 3, 6 },
			{ 13, 4, 8 },
			{ 16, 4, 8 },
			{ 17, 5, 11 },
			{ 20, 5, 11 },
			{ 21, 6, 15 },
			{ 40, 6, 15 },
		}
		for _, case in cases do
			expectEqual(MatchRules.stage(case[1]), case[2], "stage of round " .. case[1])
			expectEqual(MatchRules.baseDamage(case[1]), case[3], "base damage of round " .. case[1])
		end
	end,
})

table.insert(tests, {
	name = "player damage is base damage plus 1 per surviving enemy unit",
	run = function()
		expectEqual(MatchRules.playerDamage(14, 4), 12, "spec example: stage 4 loss with 4 survivors")
		expectEqual(MatchRules.playerDamage(1, 0), 2, "stage 1 with no survivors")
		expectEqual(MatchRules.playerDamage(22, 9), 24, "stage 6 with 9 survivors")
	end,
})

local function entry(id, after, before, survivors)
	return { id = id, healthAfter = after, healthBefore = before, survivors = survivors }
end

table.insert(tests, {
	name = "tie-break 1: higher HP after damage ranks higher",
	run = function()
		local ranked = MatchRules.rankEliminated({ entry(1, -8, 10, 5), entry(2, -2, 3, 0) }, SeededRandom.new(1))
		assert(ranked[1] == 2 and ranked[2] == 1, "-2 should beat -8")
	end,
})

table.insert(tests, {
	name = "tie-break 2: then higher HP entering the round",
	run = function()
		local ranked = MatchRules.rankEliminated({ entry(1, -3, 5, 9), entry(2, -3, 8, 0) }, SeededRandom.new(1))
		assert(ranked[1] == 2, "8 HP entering should beat 5")
	end,
})

table.insert(tests, {
	name = "tie-break 3: then more surviving units in the final combat",
	run = function()
		local ranked = MatchRules.rankEliminated({ entry(1, -3, 5, 1), entry(2, -3, 5, 4) }, SeededRandom.new(1))
		assert(ranked[1] == 2, "4 survivors should beat 1")
	end,
})

table.insert(tests, {
	name = "tie-break 4: then a seeded random order",
	run = function()
		local firsts = {}
		for seed = 1, 40 do
			local entries = { entry(1, 0, 5, 2), entry(2, 0, 5, 2), entry(3, 0, 5, 2) }
			local ranked = MatchRules.rankEliminated(entries, SeededRandom.new(seed))
			expectEqual(#ranked, 3, "ranked count")
			firsts[ranked[1]] = true
			local again = MatchRules.rankEliminated(entries, SeededRandom.new(seed))
			assert(again[1] == ranked[1] and again[3] == ranked[3], "same seed gave a different order")
		end
		assert(firsts[1] and firsts[2] and firsts[3], "random tie-break never picked some players first")
	end,
})

return tests
