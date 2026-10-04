-- Shop rolls. Each slot picks a cost tier by ShopConfig.odds for the player's level, then a random
-- unit of that cost. The unit pool is unlimited for now.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")
local ShopConfig = if script then require(script.Parent.ShopConfig) else require("./ShopConfig")
local UnitConfig = if script then require(script.Parent.UnitConfig) else require("./UnitConfig")

local Shop = {}

-- Unit names per cost tier, sorted so a given seed always rolls the same shop.
local unitsByCost: { [number]: { string } } = {}
for name, unit in UnitConfig do
	unitsByCost[unit.cost] = unitsByCost[unit.cost] or {}
	table.insert(unitsByCost[unit.cost], name)
end
for _, names in unitsByCost do
	table.sort(names)
end
Shop.unitsByCost = unitsByCost

-- Picks a cost tier (1-5) using the odds for `level`.
function Shop.rollCost(rng: SeededRandom.SeededRandom, level: number): number
	local odds = ShopConfig.odds[level]
	local roll = SeededRandom.nextInt(rng, 100)
	local cumulative = 0
	for cost, chance in odds do
		cumulative += chance
		if roll <= cumulative then
			return cost
		end
	end
	error("ShopConfig.odds for level " .. level .. " do not sum to 100")
end

-- Rolls a full shop: a list of ShopConfig.slots unit names.
function Shop.roll(rng: SeededRandom.SeededRandom, level: number): { string }
	local slots = {}
	for _ = 1, ShopConfig.slots do
		local names = unitsByCost[Shop.rollCost(rng, level)]
		table.insert(slots, names[SeededRandom.nextInt(rng, #names)])
	end
	return slots
end

return Shop
