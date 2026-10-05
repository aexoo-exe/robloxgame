-- A simple scripted player for headless match simulations. It acts through the real PlayerState
-- rules (buying, selling, rerolling, buying XP) and then chooses which units to field.
--
-- Placement is simplified: the bot returns a list of placed units for CombatSim directly instead of
-- moving them on its Board one by one. It always fields its best `level` units: melee units in
-- the front rows, units with range 4+ in the back rows, and shorter ranges in between.
--
-- Every bot buys copies of the units it fielded last round whenever it can afford them.
--
-- Standard bots also prefer traits: they buy a unit that shares a trait with one they fielded last
-- round while they hold fewer than level + 3 units, and when choosing what to field each unit
-- scores its strength plus TRAIT_SHARE_WEIGHT per trait it shares with another character they own.
--
-- Rerolling bots (policies with `rerollCost`) chase 3-star units of one cost:
--   * Roll level: the level where that cost's shop odds are highest, among levels of at least
--     cost + 4 (1-cost: 5, 2-cost: 6, 3-cost: 7). Below it, the bot buys XP down to 30 gold.
--   * Targets: among units of that cost not yet at 3 stars, the ones it holds the most copies of
--     (ties by name). It wants `targetCount` 3-stars: two for 1- and 2-cost, one for 3-cost.
--   * At the roll level it buys no XP, keeps 50 gold (full interest) and spends everything above
--     that on rerolls, buying target copies first. Target copies are never sold.
--   * Once all its targets are 3-star it stops rerolling and levels like the balanced bot.
-- Passive XP still raises its level over time; PlayerState gives every player that.

local Board = require("../src/shared/Board")
local LevelConfig = require("../src/shared/LevelConfig")
local PlayerState = require("../src/shared/PlayerState")
local ShopConfig = require("../src/shared/ShopConfig")
local StarLevel = require("../src/shared/StarLevel")
local Traits = require("../src/shared/Traits")
local UnitConfig = require("../src/shared/UnitConfig")

local Bot = {}

export type Policy = {
	name: string,
	keepGold: number, -- buys XP only with gold above this (interest saving)
	seeksCopies: boolean, -- buys copies of owned units to upgrade them
	rerollsFromLevel: number?, -- rerolls spare gold for copies from this level on
	rerollCost: number?, -- rerolling strategy: the cost tier it chases 3-stars in
	targetCount: number?, -- rerolling strategy: how many 3-stars it wants
}

-- What a bot remembers between rounds, and what the simulation reports about it.
export type Memory = {
	fielded: { [string]: boolean }, -- unit types it fielded last round
	completed: { [string]: boolean }, -- rerolling: targets that reached 3 stars
	targets: { string }, -- rerolling: current targets
	rerollGold: number, -- gold spent on rerolls this match
}

-- Standard strategies, cycled across the standard bots in a match.
Bot.policies = {
	{ name = "fast level", keepGold = 20, seeksCopies = true },
	{ name = "balanced", keepGold = 30, seeksCopies = true, rerollsFromLevel = 7 },
	{ name = "greedy", keepGold = 50, seeksCopies = true, rerollsFromLevel = 8 },
	{ name = "no copies", keepGold = 20, seeksCopies = false },
	{ name = "reroll", keepGold = 30, seeksCopies = true, rerollsFromLevel = 5 },
	{ name = "balanced", keepGold = 30, seeksCopies = true, rerollsFromLevel = 7 },
	{ name = "fast level", keepGold = 20, seeksCopies = true },
	{ name = "greedy", keepGold = 50, seeksCopies = false },
}

-- Rerolling strategies, by the cost they chase.
Bot.rerollPolicies = {
	{ name = "reroll 1c", keepGold = 50, seeksCopies = true, rerollCost = 1, targetCount = 2 },
	{ name = "reroll 2c", keepGold = 50, seeksCopies = true, rerollCost = 2, targetCount = 2 },
	{ name = "reroll 3c", keepGold = 50, seeksCopies = true, rerollCost = 3, targetCount = 1 },
}

local LEVEL_UP_KEEP_GOLD = 30 -- rerolling bots below their roll level, and after finishing
local TRAIT_SHARE_WEIGHT = 0.75 -- standard bots: fielding score per trait shared with another owned character

-- The level a rerolling bot rolls at for `cost`: highest odds for that cost at levels >= cost + 4.
function Bot.rollLevel(cost: number): number
	local best, bestOdds = cost + 4, -1
	for level = cost + 4, LevelConfig.maxLevel do
		local odds = ShopConfig.odds[level][cost]
		if odds > bestOdds then
			best, bestOdds = level, odds
		end
	end
	return best
end

function Bot.newMemory(): Memory
	return { fielded = {}, completed = {}, targets = {}, rerollGold = 0 }
end

local COLUMN_ORDER = { 4, 3, 5, 2, 6, 1, 7 }

-- Rows to fill, in order, by attack range.
local function rowsFor(range: number): { number }
	if range <= 1 then
		return { 4, 3, 2, 1 }
	elseif range >= 4 then
		return { 1, 2, 3, 4 }
	end
	return { 2, 1, 3, 4 }
end

local function strength(unit): number
	return UnitConfig[unit.unitType].cost * 3 ^ (unit.starLevel - 1)
end

local function ownsUpgradable(state, unitType: string): boolean
	for _, unit in Board.getUnits(state.board) do
		if unit.unitType == unitType and unit.starLevel < 3 then
			return true
		end
	end
	return false
end

-- 1-star copies held of `unitType`, and whether one of them is already 3-star.
local function copiesHeld(state, unitType: string): (number, boolean)
	local copies, hasThreeStar = 0, false
	for _, unit in Board.getUnits(state.board) do
		if unit.unitType == unitType then
			copies += StarLevel.copiesIn(unit.starLevel)
			hasThreeStar = hasThreeStar or unit.starLevel == 3
		end
	end
	return copies, hasThreeStar
end
Bot.copiesHeld = copiesHeld

local function isRerolling(policy: Policy, memory: Memory): boolean
	if not policy.rerollCost then
		return false
	end
	local completed = 0
	for _ in memory.completed do
		completed += 1
	end
	return completed < (policy.targetCount or 1)
end

-- Marks finished targets and picks the current ones: the target-cost units held in the most copies.
local function updateTargets(state, policy: Policy, memory: Memory)
	table.clear(memory.targets)
	if not policy.rerollCost then
		return
	end
	local candidates = {}
	for _, unit in Board.getUnits(state.board) do
		if UnitConfig[unit.unitType].cost == policy.rerollCost and not candidates[unit.unitType] then
			local copies, hasThreeStar = copiesHeld(state, unit.unitType)
			if hasThreeStar then
				memory.completed[unit.unitType] = true
			else
				candidates[unit.unitType] = copies
			end
		end
	end
	local names = {}
	for name in candidates do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		return candidates[a] > candidates[b] or (candidates[a] == candidates[b] and a < b)
	end)
	local completed = 0
	for _ in memory.completed do
		completed += 1
	end
	for i = 1, math.max(0, (policy.targetCount or 1) - completed) do
		if names[i] then
			table.insert(memory.targets, names[i])
		end
	end
end

local function isTarget(memory: Memory, unitType: string): boolean
	return table.find(memory.targets, unitType) ~= nil
end

local function prefersTraits(policy: Policy): boolean
	return policy.rerollCost == nil
end

-- True if `unitType` shares a trait with a different character the bot fielded last round.
local function sharesFieldedTrait(memory: Memory, unitType: string): boolean
	for _, trait in Traits.traitsOf(unitType) do
		for fielded in memory.fielded do
			if fielded ~= unitType and table.find(Traits.traitsOf(fielded), trait) then
				return true
			end
		end
	end
	return false
end

-- Traits `unitType` shares with other characters among `owned`.
local function sharedTraitCount(owned, unitType: string): number
	local shared = 0
	for _, trait in Traits.traitsOf(unitType) do
		for _, other in owned do
			if other.unitType ~= unitType and table.find(Traits.traitsOf(other.unitType), trait) then
				shared += 1
				break
			end
		end
	end
	return shared
end

local function shopPass(state, policy: Policy, memory: Memory)
	local rerolling = isRerolling(policy, memory)
	-- Targets first, then the most expensive offers.
	local slots = {}
	for slot, unitType in state.shop do
		if unitType then
			table.insert(slots, slot)
		end
	end
	local function priority(slot: number): number
		local unitType = state.shop[slot]
		return (if isTarget(memory, unitType) then 100 else 0) + UnitConfig[unitType].cost
	end
	table.sort(slots, function(a, b)
		return priority(a) > priority(b)
	end)

	for _, slot in slots do
		local unitType = state.shop[slot]
		local cost = UnitConfig[unitType].cost
		local owned = Board.getUnits(state.board)
		local fieldedCopy = memory.fielded[unitType] and ownsUpgradable(state, unitType)
		-- While a rerolling bot still needs targets, any unit of its cost may become one.
		local seedsTarget = rerolling and cost == policy.rerollCost and #memory.targets < (policy.targetCount or 1)
		local traitPick = prefersTraits(policy) and #owned < state.level + 3 and sharesFieldedTrait(memory, unitType)
		local wanted = isTarget(memory, unitType)
			or seedsTarget
			or fieldedCopy
			or (policy.seeksCopies and ownsUpgradable(state, unitType))
			or #owned < state.level
			or traitPick
		if wanted then
			if PlayerState.buyUnit(state, slot) then
				updateTargets(state, policy, memory)
			end
		else
			-- Replace the weakest unit when the offer is a clear upgrade (never a target copy).
			table.sort(owned, function(a, b)
				return strength(a) < strength(b)
			end)
			local weakest = nil
			for _, unit in owned do
				if not isTarget(memory, unit.unitType) then
					weakest = unit
					break
				end
			end
			if weakest and strength(weakest) < cost and state.gold + strength(weakest) >= cost then
				PlayerState.sellUnit(state, weakest.id)
				PlayerState.buyUnit(state, slot)
			end
		end
	end
end

-- Sells extra units beyond what the bot can field, keeping copies it is collecting and targets.
local function trimBench(state, policy: Policy, memory: Memory)
	local owned = Board.getUnits(state.board)
	table.sort(owned, function(a, b)
		return strength(a) > strength(b)
	end)
	for index = state.level + 3, #owned do
		local unit = owned[index]
		if not isTarget(memory, unit.unitType) then
			if not (policy.seeksCopies and unit.starLevel < 3) or index > state.level + 6 then
				PlayerState.sellUnit(state, unit.id)
			end
		end
	end
end

local function reroll(state, memory: Memory): boolean
	if PlayerState.reroll(state) then
		memory.rerollGold += ShopConfig.rerollCost
		return true
	end
	return false
end

local function buyXpDownTo(state, keepGold: number)
	while state.gold >= keepGold + LevelConfig.buyXpCost do
		if not PlayerState.buyXp(state) then
			break
		end
	end
end

-- Plays one Preparation. Returns the units to field, in the player's own board coordinates.
function Bot.prepare(state, policy: Policy, memory: Memory): { any }
	updateTargets(state, policy, memory)
	shopPass(state, policy, memory)

	if policy.rerollCost then
		if not isRerolling(policy, memory) or state.level < Bot.rollLevel(policy.rerollCost) then
			buyXpDownTo(state, LEVEL_UP_KEEP_GOLD)
		else
			while isRerolling(policy, memory) and state.gold >= policy.keepGold + ShopConfig.rerollCost do
				if not reroll(state, memory) then
					break
				end
				shopPass(state, policy, memory)
			end
		end
	else
		if policy.rerollsFromLevel and state.level >= policy.rerollsFromLevel then
			while state.gold >= policy.keepGold + ShopConfig.rerollCost and reroll(state, memory) do
				shopPass(state, policy, memory)
			end
		end
		buyXpDownTo(state, policy.keepGold)
	end
	trimBench(state, policy, memory)

	local owned = Board.getUnits(state.board)
	local score = {}
	for _, unit in owned do
		score[unit.id] = strength(unit)
			+ (if prefersTraits(policy) then TRAIT_SHARE_WEIGHT * sharedTraitCount(owned, unit.unitType) else 0)
	end
	table.sort(owned, function(a, b)
		if score[a.id] ~= score[b.id] then
			return score[a.id] > score[b.id]
		end
		return a.id < b.id
	end)
	local placed = {}
	local taken = {}
	table.clear(memory.fielded)
	for index = 1, math.min(state.level, #owned) do
		local unit = owned[index]
		local found = false
		for _, row in rowsFor(UnitConfig[unit.unitType].range) do
			for _, column in COLUMN_ORDER do
				local key = row * 10 + column
				if not found and not taken[key] then
					taken[key] = true
					found = true
					memory.fielded[unit.unitType] = true
					table.insert(placed, {
						id = unit.id,
						unitType = unit.unitType,
						starLevel = unit.starLevel,
						column = column,
						row = row,
					})
				end
			end
		end
	end
	return placed
end

return Bot
