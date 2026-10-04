local SeededRandom = require("../src/shared/SeededRandom")
local Shop = require("../src/shared/Shop")
local ShopConfig = require("../src/shared/ShopConfig")
local UnitConfig = require("../src/shared/UnitConfig")

local tests = {}

table.insert(tests, {
	name = "odds rows sum to 100 for levels 2-10 and every tier has units",
	run = function()
		for level = 2, 10 do
			local sum = 0
			for _, chance in ShopConfig.odds[level] do
				sum += chance
			end
			assert(sum == 100, "odds for level " .. level .. " sum to " .. sum)
		end
		for cost = 1, 5 do
			assert(#Shop.unitsByCost[cost] > 0, "no units of cost " .. cost)
		end
	end,
})

table.insert(tests, {
	name = "a shop has five slots of known units",
	run = function()
		local slots = Shop.roll(SeededRandom.new(1), 7)
		assert(#slots == ShopConfig.slots, "expected " .. ShopConfig.slots .. " slots")
		for _, unitType in slots do
			assert(UnitConfig[unitType], "unknown unit " .. tostring(unitType))
		end
	end,
})

table.insert(tests, {
	name = "level 2 shops contain only 1-cost units",
	run = function()
		local rng = SeededRandom.new(42)
		for _ = 1, 2000 do
			for _, unitType in Shop.roll(rng, 2) do
				assert(UnitConfig[unitType].cost == 1, "level 2 rolled a " .. unitType)
			end
		end
	end,
})

table.insert(tests, {
	name = "tiers with 0% odds never appear",
	run = function()
		local rng = SeededRandom.new(7)
		for level = 2, 10 do
			for _ = 1, 2000 do
				local cost = Shop.rollCost(rng, level)
				assert(ShopConfig.odds[level][cost] > 0, string.format("level %d rolled cost %d", level, cost))
			end
		end
	end,
})

table.insert(tests, {
	name = "roll frequencies match the odds table",
	run = function()
		local rng = SeededRandom.new(123)
		local rolls = 50000
		for level = 3, 10 do
			local counts = { 0, 0, 0, 0, 0 }
			for _ = 1, rolls do
				local cost = Shop.rollCost(rng, level)
				counts[cost] += 1
			end
			for cost = 1, 5 do
				local percent = counts[cost] / rolls * 100
				local expected = ShopConfig.odds[level][cost]
				assert(
					math.abs(percent - expected) < 1,
					string.format("level %d cost %d: %.2f%% rolled, %d%% expected", level, cost, percent, expected)
				)
			end
		end
	end,
})

table.insert(tests, {
	name = "the same seed rolls the same shop",
	run = function()
		local a = Shop.roll(SeededRandom.new(99), 8)
		local b = Shop.roll(SeededRandom.new(99), 8)
		for i = 1, ShopConfig.slots do
			assert(a[i] == b[i], "slot " .. i .. " differs")
		end
	end,
})

return tests
