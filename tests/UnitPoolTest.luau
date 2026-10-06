-- The shared unit pool: sizes, weighted rolls, shop holds, sell and elimination returns, and dry
-- tiers. PlayerState is used where the rule lives there (holding, selling, eliminating).

local PlayerState = require("../src/shared/PlayerState")
local SeededRandom = require("../src/shared/SeededRandom")
local Shop = require("../src/shared/Shop")
local ShopConfig = require("../src/shared/ShopConfig")
local StarLevel = require("../src/shared/StarLevel")
local UnitConfig = require("../src/shared/UnitConfig")
local UnitPool = require("../src/shared/UnitPool")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local function total(pool): number
	local sum = 0
	for _, count in pool.remaining do
		sum += count
	end
	return sum
end

local FULL = (function()
	local sum = 0
	for _, unit in UnitConfig do
		sum += ShopConfig.poolCopies[unit.cost]
	end
	return sum
end)()

-- Leaves only the given characters of a tier in the pool, with the given counts.
local function onlyInTier(pool, cost: number, counts: { [string]: number })
	for _, name in Shop.unitsByCost[cost] do
		pool.remaining[name] = counts[name] or 0
	end
end

-- Copies a player holds: units (by star level) and unbought shop slots.
local function held(state): number
	local sum = 0
	for _, unit in state.board.units do
		sum += StarLevel.copiesIn(unit.starLevel)
	end
	for _, unitType in state.shop do
		if unitType then
			sum += 1
		end
	end
	return sum
end

-- Buys one copy of `unitType` the honest way: the copy comes out of the pool into slot 1.
local function buyCopy(state, unitType: string)
	UnitPool.returnShop(state.pool, state.shop)
	state.shop = table.create(ShopConfig.slots, false)
	assert(UnitPool.take(state.pool, unitType), "pool has no " .. unitType)
	state.shop[1] = unitType
	state.gold = 100
	assert(PlayerState.buyUnit(state, 1), "could not buy " .. unitType)
end

local tests = {}

table.insert(tests, {
	name = "a new pool has 30/26/22/15/10 copies per character by cost",
	run = function()
		local pool = UnitPool.new()
		for name, unit in UnitConfig do
			expectEqual(UnitPool.remaining(pool, name), ({ 30, 26, 22, 15, 10 })[unit.cost], name)
		end
		for cost, perTier in { 9 * 30, 9 * 26, 10 * 22, 9 * 15, 5 * 10 } do
			expectEqual(UnitPool.tierRemaining(pool, cost), perTier, cost .. "-cost tier")
		end
		expectEqual(total(pool), 270 + 234 + 220 + 135 + 50, "whole pool")
	end,
})

table.insert(tests, {
	name = "characters are picked in proportion to the copies left in their tier",
	run = function()
		local pool = UnitPool.new()
		onlyInTier(pool, 1, { cinder_arc = 20, spurshot = 10, blooming_aid = 5 })
		local rng = SeededRandom.new(3)
		local counts = { cinder_arc = 0, spurshot = 0, blooming_aid = 0 }
		local rolls = 35000
		for _ = 1, rolls do
			local name = UnitPool.rollUnit(pool, rng, 2) -- level 2 rolls only 1-costs
			counts[name] += 1
			UnitPool.give(pool, name, 1)
		end
		for name, copies in { cinder_arc = 20, spurshot = 10, blooming_aid = 5 } do
			local share = counts[name] / rolls
			assert(
				math.abs(share - copies / 35) < 0.01,
				string.format("%s rolled %.3f of the time, expected %.3f", name, share, copies / 35)
			)
		end
		expectEqual(pool.dryRolls, 0, "dry rolls")
	end,
})

table.insert(tests, {
	name = "a character with no copies left is never rolled",
	run = function()
		local pool = UnitPool.new()
		pool.remaining.cinder_arc = 0
		local rng = SeededRandom.new(4)
		for _ = 1, 3000 do
			local name = UnitPool.rollUnit(pool, rng, 2)
			assert(name ~= "cinder_arc", "rolled a character with no copies")
			UnitPool.give(pool, name, 1)
		end
	end,
})

table.insert(tests, {
	name = "shown copies are held out of the pool and return on reroll and refresh",
	run = function()
		local pool = UnitPool.new()
		local state = PlayerState.new(1, pool)
		expectEqual(total(pool), FULL - ShopConfig.slots, "after the first shop")

		state.gold = 10
		assert(PlayerState.reroll(state), "reroll refused")
		expectEqual(total(pool), FULL - ShopConfig.slots, "after a reroll")

		PlayerState.startPreparation(state)
		expectEqual(total(pool), FULL - ShopConfig.slots, "after a refresh")
	end,
})

table.insert(tests, {
	name = "a bought copy stays out of the pool through rerolls",
	run = function()
		local pool = UnitPool.new()
		local state = PlayerState.new(2, pool)
		state.gold = 100
		local bought = state.shop[1]
		assert(PlayerState.buyUnit(state, 1), "buy refused")
		local before = UnitPool.remaining(pool, bought :: string)
		PlayerState.reroll(state)
		PlayerState.startPreparation(state)
		-- The 4 unbought copies came back; the bought one did not.
		expectEqual(total(pool), FULL - 1 - ShopConfig.slots, "pool after buying one and refreshing twice")
		assert(UnitPool.remaining(pool, bought :: string) <= before + 1, "bought copy returned")
	end,
})

table.insert(tests, {
	name = "selling returns 1, 3 or 9 copies by star level",
	run = function()
		for starLevel, copies in { 1, 3, 9 } do
			local pool = UnitPool.new()
			local state = PlayerState.new(3, pool)
			for _ = 1, copies do
				buyCopy(state, "cinder_arc")
			end
			local units = state.board.units
			local id, unit = next(units)
			expectEqual(unit.starLevel, starLevel, "merged star level")
			expectEqual(next(units, id), nil, "one unit after merging")

			local before = UnitPool.remaining(pool, "cinder_arc")
			assert(PlayerState.sellUnit(state, id), "sell refused")
			expectEqual(UnitPool.remaining(pool, "cinder_arc"), before + copies, starLevel .. "-star sell return")
		end
	end,
})

table.insert(tests, {
	name = "an eliminated player's units and shop all return to the pool",
	run = function()
		local pool = UnitPool.new()
		local state = PlayerState.new(4, pool)
		for _ = 1, 3 do
			buyCopy(state, "flare_kick") -- one 2-star Rook
		end
		buyCopy(state, "severing_temple")
		state.shop = UnitPool.rollShop(pool, state.rng, 8)
		assert(total(pool) < FULL, "test setup: the player holds copies")

		PlayerState.releaseAll(state)
		expectEqual(total(pool), FULL, "pool after elimination")
		expectEqual(next(state.board.units), nil, "units left")
		for slot = 1, ShopConfig.slots do
			expectEqual(state.shop[slot], false, "shop slot " .. slot)
		end
	end,
})

table.insert(tests, {
	name = "a dry tier is rolled again among tiers that still have copies, by the level odds",
	run = function()
		local pool = UnitPool.new()
		onlyInTier(pool, 1, {}) -- every 1-cost gone
		local rng = SeededRandom.new(5)
		local counts = { 0, 0, 0, 0, 0 }
		local rolls = 20000
		for _ = 1, rolls do
			local name = UnitPool.rollUnit(pool, rng, 4) -- level 4 odds: 55 / 30 / 15 / 0 / 0
			local cost = UnitConfig[name].cost
			counts[cost] += 1
			UnitPool.give(pool, name, 1)
		end
		expectEqual(counts[1], 0, "1-cost rolls")
		expectEqual(counts[4] + counts[5], 0, "rolls of tiers with 0% odds")
		-- Without 1-costs the remaining odds are 30 : 15, so 2-costs come up two thirds of the time.
		assert(math.abs(counts[2] / rolls - 2 / 3) < 0.015, string.format("2-cost share %.3f", counts[2] / rolls))
		assert(pool.dryRolls > rolls * 0.5, "dry rolls were not counted")
	end,
})

table.insert(tests, {
	name = "when no tier this level can roll has copies, the slot is empty",
	run = function()
		local pool = UnitPool.new()
		onlyInTier(pool, 1, {})
		local shop = UnitPool.rollShop(pool, SeededRandom.new(6), 2) -- level 2 rolls only 1-costs
		for slot = 1, ShopConfig.slots do
			expectEqual(shop[slot], false, "slot " .. slot)
		end
		-- Higher tiers are untouched.
		expectEqual(UnitPool.tierRemaining(pool, 2), 9 * 26, "2-cost tier")
	end,
})

table.insert(tests, {
	name = "the last copies of a tier are shared out until none are left",
	run = function()
		local pool = UnitPool.new()
		onlyInTier(pool, 1, { wolfstep = 3 })
		local shop = UnitPool.rollShop(pool, SeededRandom.new(7), 2)
		local shown = 0
		for _, unitType in shop do
			if unitType == "wolfstep" then
				shown += 1
			else
				expectEqual(unitType, false, "slot after the tier ran dry")
			end
		end
		expectEqual(shown, 3, "copies shown")
		expectEqual(UnitPool.remaining(pool, "wolfstep"), 0, "copies left")
	end,
})

table.insert(tests, {
	name = "copies are conserved across many players buying, selling, rerolling and leaving",
	run = function()
		local pool = UnitPool.new()
		local rng = SeededRandom.new(8)
		local states = {}
		for i = 1, 8 do
			states[i] = PlayerState.new(100 + i, pool)
			states[i].gold = 1000
			states[i].level = 8
		end
		local released = {}
		for step = 1, 3000 do
			local i = SeededRandom.nextInt(rng, 8)
			local state = states[i]
			if not released[i] then
				local action = SeededRandom.nextInt(rng, 10)
				if action <= 5 then
					PlayerState.buyUnit(state, SeededRandom.nextInt(rng, ShopConfig.slots))
				elseif action <= 7 then
					PlayerState.reroll(state)
				elseif action == 8 then
					local _, unit = next(state.board.units)
					if unit then
						PlayerState.sellUnit(state, unit.id)
					end
				elseif action == 9 then
					PlayerState.startPreparation(state)
				elseif step > 2000 then
					PlayerState.releaseAll(state)
					released[i] = true
				end
				state.gold = 1000
			end

			local sum = total(pool)
			for _, each in states do
				sum += held(each)
			end
			expectEqual(sum, FULL, "copies after step " .. step)
			for name, count in pool.remaining do
				assert(count >= 0, name .. " went below zero")
			end
		end
	end,
})

return tests
