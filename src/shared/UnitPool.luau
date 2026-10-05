-- A match's shared unit pool (docs/design/world-and-traits.md, Shared pool): a limited number of
-- copies of each character, by cost (ShopConfig.poolCopies). The server owns one per match.
--   * A shop roll picks a cost tier by the level odds, then a character of that tier weighted by
--     copies remaining, and takes that copy out of the pool while it is shown.
--   * If the rolled tier has no copies left, the tier is rolled again by the level odds among the
--     tiers that still have copies. If none of those has odds above 0 at this level, the slot is
--     empty (false, like a bought slot).
--   * Unbought shop copies go back when the shop is rerolled or refreshed; bought copies stay out
--     until the unit is sold or its owner is eliminated (see PlayerState).
-- Practice enemies and ghost boards never touch the pool.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")
local Shop = if script then require(script.Parent.Shop) else require("./Shop")
local ShopConfig = if script then require(script.Parent.ShopConfig) else require("./ShopConfig")
local UnitConfig = if script then require(script.Parent.UnitConfig) else require("./UnitConfig")

local UnitPool = {}

export type Pool = {
	remaining: { [string]: number }, -- copies left, by character
	dryRolls: number, -- shop rolls whose first tier had no copies left (for reports)
}

-- A full pool: ShopConfig.poolCopies copies of every character.
function UnitPool.new(): Pool
	local remaining = {}
	for name, unit in UnitConfig do
		remaining[name] = ShopConfig.poolCopies[unit.cost]
	end
	return { remaining = remaining, dryRolls = 0 }
end

function UnitPool.remaining(pool: Pool, unitType: string): number
	return pool.remaining[unitType] or 0
end

-- Copies left across every character of one cost.
function UnitPool.tierRemaining(pool: Pool, cost: number): number
	local total = 0
	for _, name in Shop.unitsByCost[cost] or {} do
		total += pool.remaining[name]
	end
	return total
end

-- Puts `count` copies of `unitType` back.
function UnitPool.give(pool: Pool, unitType: string, count: number)
	pool.remaining[unitType] += count
end

-- Takes one copy of `unitType` out. Returns false if none are left.
function UnitPool.take(pool: Pool, unitType: string): boolean
	if (pool.remaining[unitType] or 0) <= 0 then
		return false
	end
	pool.remaining[unitType] -= 1
	return true
end

-- Picks a cost tier for one shop slot, or nil if no tier with odds at this level has copies.
local function rollTier(pool: Pool, rng: SeededRandom.SeededRandom, level: number): number?
	local cost = Shop.rollCost(rng, level)
	if UnitPool.tierRemaining(pool, cost) > 0 then
		return cost
	end
	pool.dryRolls += 1

	local odds = ShopConfig.odds[level]
	local total = 0
	for tier, chance in odds do
		if UnitPool.tierRemaining(pool, tier) > 0 then
			total += chance
		end
	end
	if total == 0 then
		return nil
	end
	local roll = SeededRandom.nextInt(rng, total)
	for tier, chance in odds do
		if UnitPool.tierRemaining(pool, tier) > 0 then
			roll -= chance
			if roll <= 0 then
				return tier
			end
		end
	end
	return nil
end

-- Rolls one shop slot and takes the copy out of the pool. Returns the character, or nil if the
-- pool has nothing this level can roll.
function UnitPool.rollUnit(pool: Pool, rng: SeededRandom.SeededRandom, level: number): string?
	local cost = rollTier(pool, rng, level)
	if not cost then
		return nil
	end
	local names = Shop.unitsByCost[cost]
	local roll = SeededRandom.nextInt(rng, UnitPool.tierRemaining(pool, cost))
	for _, name in names do
		roll -= pool.remaining[name]
		if roll <= 0 then
			UnitPool.take(pool, name)
			return name
		end
	end
	return nil
end

-- Rolls a full shop (ShopConfig.slots entries; false marks an empty slot).
function UnitPool.rollShop(pool: Pool, rng: SeededRandom.SeededRandom, level: number): { string | false }
	local slots = {}
	for _ = 1, ShopConfig.slots do
		table.insert(slots, UnitPool.rollUnit(pool, rng, level) or false)
	end
	return slots
end

-- Returns a shop's unbought copies to the pool.
function UnitPool.returnShop(pool: Pool, shop: { string | false })
	for _, unitType in shop do
		if unitType then
			UnitPool.give(pool, unitType, 1)
		end
	end
end

return UnitPool
