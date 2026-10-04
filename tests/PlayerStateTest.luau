local Board = require("../src/shared/Board")
local BoardConfig = require("../src/shared/BoardConfig")
local Economy = require("../src/shared/Economy")
local LevelConfig = require("../src/shared/LevelConfig")
local PlayerState = require("../src/shared/PlayerState")
local ShopConfig = require("../src/shared/ShopConfig")
local UnitConfig = require("../src/shared/UnitConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

-- A player with a known shop: three 1-costs, a 3-cost and a 5-cost.
local function newPlayer(gold)
	local state = PlayerState.new(1)
	state.gold = gold or 10
	state.shop = { "Kaien", "Mira", "Kaien", "Veyra", "Kairo" }
	return state
end

local tests = {}

table.insert(tests, {
	name = "new players start at level 2 with 10 gold, 0 XP, no units and a full shop",
	run = function()
		local state = PlayerState.new(1)
		expectEqual(state.gold, 10, "gold")
		expectEqual(state.level, 2, "level")
		expectEqual(state.xp, 0, "xp")
		expectEqual(#Board.getUnits(state.board), 0, "units")
		expectEqual(#state.shop, ShopConfig.slots, "shop slots")
	end,
})

table.insert(tests, {
	name = "buying puts the unit on the bench, charges its cost and empties the slot",
	run = function()
		local state = newPlayer(10)
		assert(PlayerState.buyUnit(state, 4), "buy refused")
		expectEqual(state.gold, 7, "gold after buying a 3-cost")
		expectEqual(state.shop[4], false, "bought slot")
		local units = Board.getUnits(state.board)
		assert(#units == 1 and units[1].unitType == "Veyra" and units[1].slot == 1, "unit not on the bench")
		expectEqual(units[1].starLevel, 1, "star level")
		assert(not PlayerState.buyUnit(state, 4), "bought an empty slot")
		expectEqual(state.gold, 7, "gold after refused buy")
	end,
})

table.insert(tests, {
	name = "buy validation: bad slots, unaffordable units and a full bench are refused",
	run = function()
		local state = newPlayer(4)
		assert(not PlayerState.buyUnit(state, nil), "accepted a nil slot")
		for _, slot in { 0, 6, 1.5, "1", 0 / 0, {} } do
			assert(not PlayerState.buyUnit(state, slot), "accepted slot " .. tostring(slot))
		end
		assert(not PlayerState.buyUnit(state, 5), "bought a 5-cost with 4 gold")
		expectEqual(state.gold, 4, "gold after refused buys")
		expectEqual(state.shop[5], "Kairo", "refused buy emptied the slot")

		-- Fill the bench with different units so nothing merges, then buy one more.
		local names = {}
		for name in UnitConfig do
			table.insert(names, name)
		end
		table.sort(names)
		local rich = newPlayer(100)
		local spent = 0
		for i = 1, BoardConfig.benchSlots do
			rich.shop[1] = names[i]
			assert(PlayerState.buyUnit(rich, 1), "buy " .. i .. " refused")
			spent += UnitConfig[names[i]].cost
		end
		rich.shop[1] = names[BoardConfig.benchSlots + 1]
		local bought, reason = PlayerState.buyUnit(rich, 1)
		assert(not bought and reason == PlayerState.Refusal.BenchFull, "bought with a full bench")
		expectEqual(rich.gold, 100 - spent, "gold after full-bench refusal")

		local _, goldReason = PlayerState.buyUnit(newPlayer(0), 1)
		expectEqual(goldReason, PlayerState.Refusal.NotEnoughGold, "refusal reason without gold")
	end,
})

table.insert(tests, {
	name = "selling refunds the full cost from bench or board; unknown units are refused",
	run = function()
		local state = newPlayer(10)
		assert(PlayerState.buyUnit(state, 4))
		assert(PlayerState.buyUnit(state, 1))
		expectEqual(state.gold, 6, "gold after buying")
		assert(PlayerState.moveUnit(state, "2", { column = 1, row = 1 }))

		assert(PlayerState.sellUnit(state, "1"), "bench sell refused")
		expectEqual(state.gold, 9, "refund for a 3-cost")
		assert(PlayerState.sellUnit(state, "2"), "board sell refused")
		expectEqual(state.gold, 10, "refund for a 1-cost")
		expectEqual(Board.countPlaced(state.board), 0, "sold unit still on the board")

		assert(not PlayerState.sellUnit(state, nil), "sold a nil id")
		for _, id in { "1", "99", 1 } do
			assert(not PlayerState.sellUnit(state, id), "sold " .. tostring(id))
		end
		expectEqual(state.gold, 10, "gold after refused sells")
	end,
})

table.insert(tests, {
	name = "reroll costs 2 gold and is refused without it",
	run = function()
		local state = newPlayer(3)
		state.shop[1] = false
		assert(PlayerState.reroll(state), "reroll refused")
		expectEqual(state.gold, 1, "gold after reroll")
		for i = 1, ShopConfig.slots do
			assert(type(state.shop[i]) == "string", "slot " .. i .. " empty after reroll")
		end
		assert(not PlayerState.reroll(state), "rerolled with 1 gold")
		expectEqual(state.gold, 1, "gold after refused reroll")
	end,
})

table.insert(tests, {
	name = "buying XP costs 4 gold for 4 XP and is refused at max level or without gold",
	run = function()
		local state = newPlayer(8)
		assert(PlayerState.buyXp(state), "buy XP refused")
		-- 4 XP at level 2: 2 to reach level 3, then 2 of 6.
		assert(state.gold == 4 and state.level == 3 and state.xp == 2, "after buying XP")
		assert(PlayerState.buyXp(state))
		assert(not PlayerState.buyXp(state), "bought XP with 0 gold")

		local maxed = newPlayer(100)
		maxed.level = LevelConfig.maxLevel
		assert(not PlayerState.buyXp(maxed), "bought XP at max level")
		expectEqual(maxed.gold, 100, "gold at max level")
	end,
})

table.insert(tests, {
	name = "unit cap equals level and rises with it",
	run = function()
		local state = newPlayer(100)
		for _, unitType in { "Kaien", "Mira", "Rook" } do
			state.shop[1] = unitType
			assert(PlayerState.buyUnit(state, 1))
		end
		assert(PlayerState.moveUnit(state, "1", { column = 1, row = 1 }))
		assert(PlayerState.moveUnit(state, "2", { column = 2, row = 1 }))
		local moved, reason = PlayerState.moveUnit(state, "3", { column = 3, row = 1 })
		assert(not moved and reason == PlayerState.Refusal.BoardFull, "third unit placed at level 2")
		assert(PlayerState.moveUnit(state, "3", { column = 1, row = 1 }), "swap refused at the cap")
		assert(PlayerState.buyXp(state)) -- level 3
		assert(PlayerState.moveUnit(state, "1", { column = 3, row = 1 }), "third unit refused at level 3")
		expectEqual(Board.countPlaced(state.board), 3, "placed units")
	end,
})

table.insert(tests, {
	name = "first Preparation pays nothing; later ones pay income and 2 XP",
	run = function()
		local state = PlayerState.new(5)
		local firstShop = table.clone(state.shop)
		expectEqual(PlayerState.startPreparation(state), nil, "income before any fight")
		expectEqual(state.gold, 10, "gold before any fight")

		-- A win: base 5 + interest 1 (10 gold) + win bonus 1, and 2 XP takes level 2 -> 3.
		PlayerState.recordCombat(state, Economy.Outcome.Win)
		local income = PlayerState.startPreparation(state)
		expectEqual(income and income.total, 7, "income after a win")
		expectEqual(state.gold, 17, "gold after a win")
		assert(state.level == 3 and state.xp == 0, "level after automatic XP")

		-- A second win: streak of 2 pays +1.
		PlayerState.recordCombat(state, Economy.Outcome.Win)
		income = PlayerState.startPreparation(state)
		assert(income and income.streak == 1 and income.win == 1 and income.interest == 1, "second win income")
		expectEqual(state.gold, 25, "gold after two wins")

		-- No fight since the last Preparation: nothing is paid again.
		expectEqual(PlayerState.startPreparation(state), nil, "income without a fight")

		local changed = false
		for i = 1, ShopConfig.slots do
			changed = changed or state.shop[i] ~= firstShop[i]
		end
		assert(changed, "shop was not rerolled across Preparations")
	end,
})

return tests
