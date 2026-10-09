-- Items (docs/items.md): slots, inventory, equipping, moving, returning, selling, merging, the
-- combat lock and carrying items into combat. Item ids here are placeholders; the rules do not
-- depend on what an item does.

local Board = require("../src/shared/Board")
local CombatSim = require("../src/shared/CombatSim")
local ItemConfig = require("../src/shared/ItemConfig")
local PlayerState = require("../src/shared/PlayerState")
local UnitConfig = require("../src/shared/UnitConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local SLOTS = ItemConfig.rules.slotsPerUnit

-- A player with plenty of gold and a known shop, and helpers to buy and find units.
local function newPlayer()
	local state = PlayerState.new(7)
	state.gold = 200
	return state
end

local function buy(state, unitType: string): string
	state.shop[1] = unitType
	local id = tostring(state.nextUnitId)
	assert(PlayerState.buyUnit(state, 1), "test setup: buy " .. unitType)
	return id
end

local function unitsOf(state, unitType: string)
	local result = {}
	for _, unit in Board.getUnits(state.board) do
		if unit.unitType == unitType then
			table.insert(result, unit)
		end
	end
	return result
end

local tests = {}

table.insert(tests, {
	name = "items: equip from the inventory, up to three per unit, never two of the same",
	run = function()
		local state = newPlayer()
		local id = buy(state, "cinder_arc")
		state.inventory = { "a", "a", "b", "c", "d" }
		assert(PlayerState.equipItem(state, 1, id), "equip a")
		local ok, reason = PlayerState.equipItem(state, 1, id)
		assert(not ok and reason == PlayerState.Refusal.DuplicateItem, "a second copy is refused")
		assert(PlayerState.equipItem(state, 2, id), "equip b")
		assert(PlayerState.equipItem(state, 2, id), "equip c")
		ok, reason = PlayerState.equipItem(state, 2, id)
		assert(not ok and reason == PlayerState.Refusal.ItemSlotsFull, "a fourth item is refused")
		expectEqual(#state.board.units[id].items, SLOTS, "three equipped")
		expectEqual(table.concat(state.inventory, ","), "a,d", "inventory after equipping")
		assert(not PlayerState.equipItem(state, 99, id), "a bad inventory index is refused")
		assert(not PlayerState.equipItem(state, 1, "nope"), "an unknown unit is refused")
	end,
})

table.insert(tests, {
	name = "items: move between units and return to the inventory; nothing changes during combat",
	run = function()
		local state = newPlayer()
		local first = buy(state, "cinder_arc")
		local second = buy(state, "flashline")
		state.inventory = { "a", "b" }
		PlayerState.equipItem(state, 1, first)
		PlayerState.equipItem(state, 1, first)
		assert(PlayerState.moveItem(state, first, 1, second), "move a")
		expectEqual(state.board.units[second].items[1], "a", "moved")
		expectEqual(#state.board.units[first].items, 1, "one left")
		assert(PlayerState.unequipItem(state, first, 1), "return b")
		expectEqual(state.inventory[1], "b", "back in the inventory")

		PlayerState.startCombat(state)
		local ok, reason = PlayerState.equipItem(state, 1, first)
		assert(not ok and reason == PlayerState.Refusal.ItemsLocked, "equip locked in combat")
		ok, reason = PlayerState.moveItem(state, second, 1, first)
		assert(not ok and reason == PlayerState.Refusal.ItemsLocked, "move locked in combat")
		ok, reason = PlayerState.unequipItem(state, second, 1)
		assert(not ok and reason == PlayerState.Refusal.ItemsLocked, "return locked in combat")
		PlayerState.endCombat(state)
		ok = PlayerState.equipItem(state, 1, first)
		assert(not ok, "still locked at Results")
		PlayerState.startPreparation(state)
		assert(PlayerState.equipItem(state, 1, first), "unlocked at the next Preparation")
	end,
})

table.insert(tests, {
	name = "items: a full inventory refuses returns; selling a unit returns its items",
	run = function()
		local state = newPlayer()
		local id = buy(state, "cinder_arc")
		state.inventory = { "a" }
		PlayerState.equipItem(state, 1, id)
		for i = 1, ItemConfig.rules.inventoryCap do
			table.insert(state.inventory, "x" .. i)
		end
		local ok, reason = PlayerState.unequipItem(state, id, 1)
		assert(not ok and reason == PlayerState.Refusal.InventoryFull, "full inventory")
		assert(PlayerState.sellUnit(state, id), "sell")
		expectEqual(state.inventory[#state.inventory], "a", "the sold unit's item came back")
	end,
})

table.insert(tests, {
	name = "items: a merge moves the copies' items to the merged unit; extras return to the inventory",
	run = function()
		local state = newPlayer()
		local a = buy(state, "cinder_arc")
		local b = buy(state, "cinder_arc")
		state.inventory = { "x", "y", "z", "x", "w" }
		PlayerState.equipItem(state, 1, a) -- x on a
		PlayerState.equipItem(state, 1, a) -- y on a
		PlayerState.equipItem(state, 1, b) -- z on b
		PlayerState.equipItem(state, 1, b) -- x on b (a second copy of x, on another unit)
		PlayerState.equipItem(state, 1, b) -- w on b
		buy(state, "cinder_arc") -- completes the merge
		local merged = unitsOf(state, "cinder_arc")
		expectEqual(#merged, 1, "merged")
		expectEqual(merged[1].starLevel, 2, "2-star")
		expectEqual(#merged[1].items, SLOTS, "the merged unit holds three")
		local held = {}
		for _, item in merged[1].items do
			assert(not held[item], "no duplicates after a merge")
			held[item] = true
		end
		-- Five items went in; three stay on the unit and two return.
		expectEqual(#state.inventory, 2, "the rest returned")
	end,
})

table.insert(tests, {
	name = "items: units carry their items into combat; summons carry none",
	run = function()
		local result = CombatSim.run({
			boards = {
				{ { id = "a", unitType = "shade_pack", column = 4, row = 4, items = { "a", "b" } } },
				{ { id = "b", unitType = "cinder_arc", column = 4, row = 4 } },
			},
			columns = 7,
			rows = 4,
			unitTypes = UnitConfig,
			ticksPerSecond = 20,
			maxTicks = 20,
			seed = 1,
		})
		expectEqual(table.concat(result.units[1].items, ","), "a,b", "summary items")
		expectEqual(#result.units[2].items, 0, "no items")
	end,
})

-- Item choices -------------------------------------------------------------------------------------

local Items = require("../src/shared/Items")
local SeededRandom = require("../src/shared/SeededRandom")

table.insert(tests, {
	name = "item choices: rounds 3, 8, 12, 16 offer 3 items and round 20 offers 4",
	run = function()
		for round = 1, 25 do
			local expected = if round == 20
				then 4
				elseif round == 3 or round == 8 or round == 12 or round == 16 then 3
				else 0
			expectEqual(Items.offerSize(round), expected, "round " .. round)
		end
	end,
})

table.insert(tests, {
	name = "item choices: one offensive, one ability, one defensive, no duplicates, seeded",
	run = function()
		local Category = ItemConfig.Category
		for seed = 1, 50 do
			for _, count in { 3, 4 } do
				local offer = Items.rollOffer(SeededRandom.new(seed), count)
				expectEqual(#offer, count, "offer size")
				local seen = {}
				for i, id in offer do
					assert(Items.isItem(id), "unknown item " .. tostring(id))
					assert(not seen[id], "duplicate in an offer")
					seen[id] = true
					local wanted = ({ Category.Offensive, Category.Ability, Category.Defensive })[i]
					if wanted then
						expectEqual(ItemConfig.items[id].category, wanted, "slot " .. i .. " category")
					end
				end
				local again = Items.rollOffer(SeededRandom.new(seed), count)
				expectEqual(table.concat(again, ","), table.concat(offer, ","), "same seed, same offer")
			end
		end
		expectEqual(#Items.ids(), 15, "fifteen items")
	end,
})

table.insert(tests, {
	name = "item choices: pick one; unpicked, the first is taken when Preparation ends",
	run = function()
		local state = newPlayer()
		PlayerState.offerItems(state, 3)
		local offer = table.clone(state.itemOffer)
		assert(PlayerState.pickItem(state, 2), "pick the second")
		expectEqual(state.inventory[1], offer[2], "picked into the inventory")
		expectEqual(state.itemOffer, nil, "the choice closes")
		local ok, reason = PlayerState.pickItem(state, 1)
		assert(not ok and reason == PlayerState.Refusal.NoItemOffer, "nothing left to pick")

		PlayerState.offerItems(state, 3)
		local second = table.clone(state.itemOffer)
		expectEqual(PlayerState.getView(state).itemOffer[1], second[1], "the view shows the choice")
		PlayerState.startCombat(state)
		expectEqual(state.inventory[2], second[1], "the first item taken at the end of Preparation")
		expectEqual(state.itemOffer, nil, "closed")
	end,
})

table.insert(tests, {
	name = "item choices: a full inventory refuses the pick",
	run = function()
		local state = newPlayer()
		for i = 1, ItemConfig.rules.inventoryCap do
			state.inventory[i] = "x" .. i
		end
		PlayerState.offerItems(state, 3)
		local ok, reason = PlayerState.pickItem(state, 1)
		assert(not ok and reason == PlayerState.Refusal.InventoryFull, "full")
	end,
})

return tests
