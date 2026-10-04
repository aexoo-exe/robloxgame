local Economy = require("../src/shared/Economy")
local LevelConfig = require("../src/shared/LevelConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local tests = {}

table.insert(tests, {
	name = "interest at each bracket",
	run = function()
		local cases = {
			{ 0, 0 },
			{ 9, 0 },
			{ 10, 1 },
			{ 19, 1 },
			{ 20, 2 },
			{ 29, 2 },
			{ 30, 3 },
			{ 39, 3 },
			{ 40, 4 },
			{ 49, 4 },
			{ 50, 5 },
			{ 99, 5 },
			{ 500, 5 },
		}
		for _, case in cases do
			expectEqual(Economy.interest(case[1]), case[2], "interest on " .. case[1] .. " gold")
		end
	end,
})

table.insert(tests, {
	name = "streak bonuses for win and loss streaks",
	run = function()
		local cases = { { 0, 0 }, { 1, 0 }, { 2, 1 }, { 3, 1 }, { 4, 2 }, { 5, 3 }, { 9, 3 } }
		for _, case in cases do
			expectEqual(Economy.streakBonus(case[1]), case[2], "win streak " .. case[1])
			expectEqual(Economy.streakBonus(-case[1]), case[2], "loss streak " .. case[1])
		end
	end,
})

table.insert(tests, {
	name = "streaks grow, flip on the other outcome, and end on a draw",
	run = function()
		local Outcome = Economy.Outcome
		expectEqual(Economy.nextStreak(0, Outcome.Win), 1, "first win")
		expectEqual(Economy.nextStreak(3, Outcome.Win), 4, "fourth win")
		expectEqual(Economy.nextStreak(3, Outcome.Loss), -1, "loss after wins")
		expectEqual(Economy.nextStreak(-2, Outcome.Loss), -3, "third loss")
		expectEqual(Economy.nextStreak(-2, Outcome.Win), 1, "win after losses")
		expectEqual(Economy.nextStreak(5, Outcome.Draw), 0, "draw after wins")
		expectEqual(Economy.nextStreak(-5, Outcome.Draw), 0, "draw after losses")
	end,
})

table.insert(tests, {
	name = "round income adds base, interest, streak and win bonus",
	run = function()
		expectEqual(Economy.roundIncome(0, 0, false).total, 5, "base only")
		expectEqual(Economy.roundIncome(50, 0, false).total, 10, "maximum standard income")
		local income = Economy.roundIncome(23, 4, true)
		expectEqual(income.base, 5, "base")
		expectEqual(income.interest, 2, "interest")
		expectEqual(income.streak, 2, "streak")
		expectEqual(income.win, 1, "win bonus")
		expectEqual(income.total, 10, "total")
		expectEqual(Economy.roundIncome(23, -4, false).total, 9, "loss streak pays without win bonus")
	end,
})

table.insert(tests, {
	name = "level curve follows the spec XP table and caps at 10",
	run = function()
		local needed = { [2] = 2, [3] = 6, [4] = 10, [5] = 20, [6] = 36, [7] = 56, [8] = 68, [9] = 68 }
		for level = 2, 9 do
			expectEqual(Economy.xpToNextLevel(level), needed[level], "XP for level " .. level)
		end
		expectEqual(Economy.xpToNextLevel(10), nil, "XP at max level")

		-- Exactly enough XP walks from level 2 to 10.
		local level, xp = LevelConfig.startingLevel, 0
		for target = 3, 10 do
			level, xp = Economy.addXp(level, xp, needed[target - 1])
			expectEqual(level, target, "level after XP")
			expectEqual(xp, 0, "leftover XP")
		end
		level, xp = Economy.addXp(level, xp, 100)
		expectEqual(level, 10, "level past max")
		expectEqual(xp, 0, "XP at max level")
	end,
})

table.insert(tests, {
	name = "extra XP carries over and can skip levels",
	run = function()
		local level, xp = Economy.addXp(2, 0, 7)
		assert(level == 3 and xp == 5, "2 XP to level 3, then 5 of 6")
		level, xp = Economy.addXp(2, 0, 18)
		assert(level == 5 and xp == 0, "2 + 6 + 10 reaches level 5 exactly")
		level, xp = Economy.addXp(2, 1, 1)
		assert(level == 3 and xp == 0, "XP adds to existing progress")
	end,
})

return tests
