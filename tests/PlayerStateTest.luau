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
	state.shop = { "cinder_arc", "spurshot", "cinder_arc", "snapfire", "final_argument" }
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
		assert(#units == 1 and units[1].unitType == "snapfire" and units[1].slot == 1, "unit not on the bench")
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
		expectEqual(state.shop[5], "final_argument", "refused buy emptied the slot")

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
	name = "reroll costs ShopConfig.rerollCost gold and is refused without it",
	run = function()
		assert(ShopConfig.rerollCost >= 1, "reroll cost must be at least 1 gold")
		local state = newPlayer(ShopConfig.rerollCost + 1)
		state.shop[1] = false
		assert(PlayerState.reroll(state), "reroll refused")
		expectEqual(state.gold, 1, "gold after reroll")
		for i = 1, ShopConfig.slots do
			assert(type(state.shop[i]) == "string", "slot " .. i .. " empty after reroll")
		end
		state.gold = ShopConfig.rerollCost - 1
		assert(not PlayerState.reroll(state), "rerolled without enough gold")
		expectEqual(state.gold, ShopConfig.rerollCost - 1, "gold after refused reroll")
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
		for _, unitType in { "cinder_arc", "spurshot", "flare_kick" } do
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

-- Shop during combat (PlayerState.startCombat / endCombat / startPreparation).

-- Buys `unitType` through shop slot 1 and returns the new unit's id.
local function buy(state, unitType: string): string
	local id = tostring(state.nextUnitId)
	state.shop[1] = unitType
	local bought, reason = PlayerState.buyUnit(state, 1)
	assert(bought, "buying " .. unitType .. " refused: " .. tostring(reason))
	return id
end

-- Unit names other than `except`, sorted, for filling the bench without merges.
local function otherUnits(except: string): { string }
	local names = {}
	for name in UnitConfig do
		if name ~= except then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

table.insert(tests, {
	name = "during combat the shop stays open: buying goes to the bench, rerolling and buying XP work",
	run = function()
		local state = newPlayer(100)
		PlayerState.startCombat(state)
		local id = buy(state, "spurshot")
		local unit = state.board.units[id]
		assert(unit and unit.slot ~= nil, "bought unit is not on the bench")
		expectEqual(state.gold, 99, "gold after buying during combat")
		assert(PlayerState.reroll(state), "reroll refused during combat")
		assert(PlayerState.buyXp(state), "buy XP refused during combat")
	end,
})

table.insert(tests, {
	name = "during combat the board is locked; bench units can be rearranged and sold",
	run = function()
		local state = newPlayer(100)
		local onBoard = buy(state, "cinder_arc")
		local benchA = buy(state, "spurshot")
		local benchB = buy(state, "flare_kick")
		assert(PlayerState.moveUnit(state, onBoard, { column = 1, row = 1 }), "placing before combat refused")
		PlayerState.startCombat(state)

		local moved, reason = PlayerState.moveUnit(state, onBoard, { slot = 5 })
		assert(not moved and reason == PlayerState.Refusal.BoardLocked, "a board unit moved during combat")
		moved, reason = PlayerState.moveUnit(state, benchA, { column = 2, row = 1 })
		assert(not moved and reason == PlayerState.Refusal.BoardLocked, "a bench unit moved onto the board")
		moved, reason = PlayerState.moveUnit(state, benchA, onBoard)
		assert(not moved, "a malformed target was accepted")

		assert(PlayerState.moveUnit(state, benchA, { slot = 6 }), "bench to bench refused")
		expectEqual(state.board.units[benchA].slot, 6, "bench unit's new slot")
		local benchBSlot = state.board.units[benchB].slot
		assert(PlayerState.moveUnit(state, benchA, { slot = benchBSlot }), "bench swap refused")
		expectEqual(state.board.units[benchB].slot, 6, "swapped bench unit's slot")

		local sold, sellReason = PlayerState.sellUnit(state, onBoard)
		assert(not sold and sellReason == PlayerState.Refusal.BoardLocked, "a board unit was sold during combat")
		local goldBefore = state.gold
		assert(PlayerState.sellUnit(state, benchB), "selling a bench unit refused")
		expectEqual(state.gold, goldBefore + UnitConfig.flare_kick.cost, "gold after selling a bench unit")

		-- Still locked at Results; unlocked at the next Preparation.
		PlayerState.endCombat(state)
		moved = PlayerState.moveUnit(state, benchA, { column = 2, row = 1 })
		assert(not moved, "a bench unit moved onto the board before Preparation")
		PlayerState.startPreparation(state)
		assert(PlayerState.moveUnit(state, benchA, { column = 2, row = 1 }), "placing refused at Preparation")
		assert(PlayerState.sellUnit(state, onBoard), "selling a board unit refused at Preparation")
	end,
})

table.insert(tests, {
	name = "during combat bench copies merge at once; a merge with a board copy waits until combat ends",
	run = function()
		local state = newPlayer(100)
		local onBoard = buy(state, "cinder_arc")
		assert(PlayerState.moveUnit(state, onBoard, { column = 1, row = 1 }))
		PlayerState.startCombat(state)

		-- Two more copies on the bench: with the board copy that makes three, but it must wait.
		buy(state, "cinder_arc")
		buy(state, "cinder_arc")
		local copies = 0
		for _, unit in state.board.units do
			if unit.unitType == "cinder_arc" then
				copies += 1
				expectEqual(unit.starLevel, 1, "cinder_arc star level during combat")
			end
		end
		expectEqual(copies, 3, "cinder_arc copies kept apart during combat")

		-- Three copies on the bench merge at once.
		local first = buy(state, "spurshot")
		buy(state, "spurshot")
		buy(state, "spurshot")
		local merged = state.board.units[first]
		assert(merged and merged.starLevel == 2 and merged.slot ~= nil, "bench copies did not merge during combat")

		-- When the fight ends the waiting merge happens, keeping the board copy's place.
		PlayerState.endCombat(state)
		local upgraded = state.board.units[onBoard]
		assert(upgraded and upgraded.starLevel == 2, "the waiting merge did not happen when combat ended")
		assert(upgraded.column == 1 and upgraded.row == 1, "the merged unit left its board cell")
	end,
})

table.insert(tests, {
	name = "during combat a full bench refuses a purchase unless it completes a bench-only merge",
	run = function()
		local state = newPlayer(200)
		local onBoard = buy(state, "cinder_arc")
		assert(PlayerState.moveUnit(state, onBoard, { column = 1, row = 1 }))
		buy(state, "cinder_arc") -- one bench copy
		local fillers = otherUnits("cinder_arc")
		for i = 1, BoardConfig.benchSlots - 1 do
			buy(state, fillers[i])
		end
		assert(not Board.hasBenchSpace(state.board), "test setup: the bench is not full")
		PlayerState.startCombat(state)

		-- Board copy + bench copy + this one would merge in Preparation, but not during combat.
		state.shop[1] = "cinder_arc"
		local bought, reason = PlayerState.buyUnit(state, 1)
		assert(not bought and reason == PlayerState.Refusal.BenchFull, "a full bench took a board-merge copy")

		-- With two copies on the full bench, the third merges there and needs no slot.
		local other = newPlayer(200)
		local firstCopy = buy(other, "cinder_arc")
		buy(other, "cinder_arc")
		for i = 1, BoardConfig.benchSlots - 2 do
			buy(other, fillers[i])
		end
		assert(not Board.hasBenchSpace(other.board), "test setup: the bench is not full")
		PlayerState.startCombat(other)
		other.shop[1] = "cinder_arc"
		assert(PlayerState.buyUnit(other, 1), "a full bench refused a copy that completes a bench merge")
		expectEqual(other.board.units[firstCopy].starLevel, 2, "bench merge on a full bench")
	end,
})

table.insert(tests, {
	name = "a higher unit cap from leveling during combat applies from the next Preparation",
	run = function()
		local state = newPlayer(100)
		local first = buy(state, "cinder_arc")
		local second = buy(state, "spurshot")
		local third = buy(state, "flare_kick")
		assert(PlayerState.moveUnit(state, first, { column = 1, row = 1 }))
		assert(PlayerState.moveUnit(state, second, { column = 2, row = 1 }))
		PlayerState.startCombat(state)
		assert(PlayerState.buyXp(state), "buy XP refused during combat")
		expectEqual(state.level, 3, "level after buying XP during combat")
		assert(not PlayerState.moveUnit(state, third, { column = 3, row = 1 }), "placed a third unit during combat")
		PlayerState.endCombat(state)
		PlayerState.startPreparation(state)
		assert(PlayerState.moveUnit(state, third, { column = 3, row = 1 }), "third unit refused at Preparation")
		expectEqual(Board.countPlaced(state.board), 3, "placed units at the new cap")
	end,
})

return tests
