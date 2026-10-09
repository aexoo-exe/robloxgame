-- A simple scripted player for headless match simulations. It acts through the real PlayerState
-- rules (buying, selling, rerolling, buying XP) and then chooses which units to field.
--
-- Placement is simplified: the bot returns a list of placed units for CombatSim directly instead of
-- moving them on its Board one by one. It always fields its best `level` units: melee units in
-- the front rows, units with range 4+ in the back rows, and shorter ranges in between.
--
-- Every bot buys copies of the units it fielded last round whenever it can afford them.
--
-- Standard bots also value traits and bonds: after buying XP, they spend gold above their keepGold
-- on units that would add to last round's board (Bot.traitGain: shared traits, the next
-- breakpoint of a trait, completing a bond), best gain first, while they hold fewer than level + 3
-- units; a unit that reaches a breakpoint or completes a bond may dip a little below keepGold. When
-- choosing what to field, shared traits break ties between equally strong units.
--
-- Rerolling bots (policies with `rerollCost`) chase 3-star units of one cost:
--   * Roll level: the level where that cost's shop odds are highest, among levels of at least
--     cost + 4 (1-cost: 5, 2-cost: 6, 3-cost: 7). Below it, the bot buys XP down to 30 gold.
--   * Targets: units of that cost not yet at 3 stars that can still reach it (copies held plus
--     copies left in the pool and its own shop: at least 9). They are ranked by the share of the
--     copies left that they still need ((9 - held) / left, lowest first, so units with more copies
--     left are preferred), then by copies held, then by name. It wants `targetCount` 3-stars (two
--     for 1- and 2-cost, one for 3-cost), chasing up to `targetsAtOnce` at a time (2-cost: one).
--   * Below the roll level the targets are re-picked every time. From the roll level on they are
--     locked: a target is only dropped when it reaches 3 stars or can no longer reach it.
--   * Rolling (at the roll level with a target left): no XP, keeps `rollFloor` gold (50, full
--     interest) and spends everything above that on rerolls. Before each roll it sells non-target
--     units it would not field; in the shop it buys target copies, and other units only while it
--     holds fewer units than its level. Target copies are never sold.
--   * Once all its targets are 3-star (or none can reach it) it levels like the balanced bot.
-- Passive XP still raises its level over time; PlayerState gives every player that.
-- Rerolling bots also count what happens while they roll (memory.stats) for the sim report.

local Board = require("../src/shared/Board")
local BondConfig = require("../src/shared/BondConfig")
local LevelConfig = require("../src/shared/LevelConfig")
local PlayerState = require("../src/shared/PlayerState")
local Shop = require("../src/shared/Shop")
local ShopConfig = require("../src/shared/ShopConfig")
local StarLevel = require("../src/shared/StarLevel")
local TraitConfig = require("../src/shared/TraitConfig")
local Traits = require("../src/shared/Traits")
local UnitConfig = require("../src/shared/UnitConfig")
local UnitPool = require("../src/shared/UnitPool")

local Bot = {}

export type Policy = {
	name: string,
	keepGold: number, -- buys XP only with gold above this (interest saving)
	seeksCopies: boolean, -- buys copies of owned units to upgrade them
	rerollsFromLevel: number?, -- rerolls spare gold for copies from this level on
	rerollCost: number?, -- rerolling strategy: the cost tier it chases 3-stars in
	targetCount: number?, -- rerolling strategy: how many 3-stars it wants
	targetsAtOnce: number?, -- rerolling strategy: targets chased at the same time (default: all)
	rollFloor: number?, -- rerolling strategy: rolls only with gold above this
}

-- Rerolling bots, counted while rolling (see the header), for the sim report.
export type RollStats = {
	offersSeen: number, -- shop slots showing a target
	offersBought: number,
	refusedBenchFull: number,
	refusedGold: number,
	nonTargetGold: number, -- gold spent on non-target units
	switches: number, -- locked targets dropped because they could no longer reach 3 stars
	targetCopiesSold: number, -- copies sold of any unit that was a locked target this match
	rollStartLevel: number?, -- level at the first roll
}

-- What a bot remembers between rounds, and what the simulation reports about it.
export type Memory = {
	fielded: { [string]: boolean }, -- unit types it fielded last round
	weakestFielded: number?, -- strength of the weakest unit it fielded last round
	completed: { [string]: boolean }, -- rerolling: targets that reached 3 stars
	targets: { string }, -- rerolling: current targets
	locked: boolean, -- rerolling: reached the roll level, so targets are locked
	everTargeted: { [string]: boolean }, -- rerolling: units that were a locked target
	rerollGold: number, -- gold spent on rerolls this match
	stats: RollStats,
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
	{ name = "reroll 1c", keepGold = 50, rollFloor = 50, seeksCopies = true, rerollCost = 1, targetCount = 2 },
	{
		name = "reroll 2c",
		keepGold = 50,
		rollFloor = 50,
		seeksCopies = true,
		rerollCost = 2,
		targetCount = 2,
		targetsAtOnce = 1,
	},
	{ name = "reroll 3c", keepGold = 50, rollFloor = 50, seeksCopies = true, rerollCost = 3, targetCount = 1 },
}

local LEVEL_UP_KEEP_GOLD = 30 -- rerolling bots below their roll level, and after finishing
-- Standard bots: fielding score per trait shared with another owned character. Strengths are whole
-- numbers and a character has at most three traits, so 0.3 (at most 0.9) only breaks ties between
-- equally strong units; a higher weight fielded weaker units for traits.
local TRAIT_SHARE_WEIGHT = 0.3

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
	return {
		fielded = {},
		completed = {},
		targets = {},
		locked = false,
		everTargeted = {},
		rerollGold = 0,
		stats = {
			offersSeen = 0,
			offersBought = 0,
			refusedBenchFull = 0,
			refusedGold = 0,
			nonTargetGold = 0,
			switches = 0,
			targetCopiesSold = 0,
			rollStartLevel = nil,
		},
	}
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

local THREE_STAR_COPIES = StarLevel.copiesIn(3)

local function completedCount(memory: Memory): number
	local completed = 0
	for _ in memory.completed do
		completed += 1
	end
	return completed
end

local function isRerolling(policy: Policy, memory: Memory): boolean
	if not policy.rerollCost then
		return false
	end
	return completedCount(memory) < (policy.targetCount or 1)
end

-- Targets to chase now: the 3-stars still wanted, at most `targetsAtOnce`.
local function targetsWanted(policy: Policy, memory: Memory): number
	local wanted = (policy.targetCount or 1) - completedCount(memory)
	return math.min(wanted, policy.targetsAtOnce or wanted)
end

-- Rolling: at the roll level (targets locked), with a target left to chase.
local function isRolling(policy: Policy, memory: Memory): boolean
	return memory.locked and isRerolling(policy, memory) and #memory.targets > 0
end

-- Copies of `unitType` the bot can still get: left in the pool, plus any in its own shop (shown
-- copies are held out of the pool).
local function copiesLeft(state, unitType: string): number
	local copies = UnitPool.remaining(state.pool, unitType)
	for _, offered in state.shop do
		if offered == unitType then
			copies += 1
		end
	end
	return copies
end

-- Marks finished targets, drops locked targets that can no longer reach 3 stars (a switch), and
-- fills the free target places with the best candidates (see the header). Below the roll level
-- (not locked) every target is re-picked.
local function updateTargets(state, policy: Policy, memory: Memory)
	if not policy.rerollCost then
		table.clear(memory.targets)
		return
	end
	for _, unit in Board.getUnits(state.board) do
		if unit.starLevel == 3 and UnitConfig[unit.unitType].cost == policy.rerollCost then
			memory.completed[unit.unitType] = true
		end
	end

	local kept = {}
	if memory.locked then
		for _, unitType in memory.targets do
			if not memory.completed[unitType] then
				if copiesHeld(state, unitType) + copiesLeft(state, unitType) >= THREE_STAR_COPIES then
					table.insert(kept, unitType)
				else
					memory.stats.switches += 1
				end
			end
		end
	end

	local needed, left = {}, {}
	local names = {}
	for _, name in Shop.unitsByCost[policy.rerollCost] or {} do
		if not memory.completed[name] and not table.find(kept, name) then
			local held = copiesHeld(state, name)
			needed[name] = THREE_STAR_COPIES - held
			left[name] = copiesLeft(state, name)
			if left[name] >= needed[name] then
				table.insert(names, name)
			end
		end
	end
	table.sort(names, function(a, b)
		local shareA, shareB = needed[a] / left[a], needed[b] / left[b]
		if shareA ~= shareB then
			return shareA < shareB
		end
		if needed[a] ~= needed[b] then
			return needed[a] < needed[b]
		end
		return a < b
	end)

	local wanted = targetsWanted(policy, memory)
	table.clear(memory.targets)
	for _, name in kept do
		table.insert(memory.targets, name)
	end
	for _, name in names do
		if #memory.targets >= wanted then
			break
		end
		table.insert(memory.targets, name)
	end
	if memory.locked then
		for _, name in memory.targets do
			memory.everTargeted[name] = true
		end
	end
end

local function isTarget(memory: Memory, unitType: string): boolean
	return table.find(memory.targets, unitType) ~= nil
end

-- Sells a unit, counting copies of units that were a locked target.
local function sell(state, memory: Memory, unit)
	if memory.everTargeted[unit.unitType] then
		memory.stats.targetCopiesSold += StarLevel.copiesIn(unit.starLevel)
	end
	PlayerState.sellUnit(state, unit.id)
end

local function prefersTraits(policy: Policy): boolean
	return policy.rerollCost == nil
end

-- How much `unitType` would add to the traits and bonds of the board the bot fielded last round:
-- 1 per trait it shares with a different fielded character, 2 more per trait whose next
-- breakpoint (TraitConfig) it would reach, and 2 per bond (BondConfig) it would complete.
-- 0 for a character already fielded (copies do not count toward traits).
local function traitGain(memory: Memory, unitType: string): number
	if memory.fielded[unitType] then
		return 0
	end
	local counts = {}
	for fielded in memory.fielded do
		for _, trait in Traits.traitsOf(fielded) do
			counts[trait] = (counts[trait] or 0) + 1
		end
	end
	local gain = 0
	for _, trait in Traits.traitsOf(unitType) do
		local count = counts[trait] or 0
		if count > 0 then
			gain += 1
			for _, breakpoint in (TraitConfig[trait] and TraitConfig[trait].breakpoints) or {} do
				if breakpoint.count == count + 1 then
					gain += 2
				end
			end
		end
	end
	for _, bond in BondConfig do
		local partner = if bond.units[1] == unitType
			then bond.units[2]
			elseif bond.units[2] == unitType then bond.units[1]
			else nil
		if partner and memory.fielded[partner] then
			gain += 2
		end
	end
	return gain
end
Bot.traitGain = traitGain

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

-- Rolling: buys target copies (counting offers and refusals), and other units only while the bot
-- holds fewer units than its level (to fill the board).
local function rollingShopPass(state, policy: Policy, memory: Memory)
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

	local stats = memory.stats
	for _, slot in slots do
		local unitType = state.shop[slot]
		if isTarget(memory, unitType) then
			stats.offersSeen += 1
			local bought, reason = PlayerState.buyUnit(state, slot)
			if bought then
				stats.offersBought += 1
				updateTargets(state, policy, memory)
			elseif reason == PlayerState.Refusal.BenchFull then
				stats.refusedBenchFull += 1
			elseif reason == PlayerState.Refusal.NotEnoughGold then
				stats.refusedGold += 1
			end
		elseif #Board.getUnits(state.board) < state.level then
			if PlayerState.buyUnit(state, slot) then
				stats.nonTargetGold += UnitConfig[unitType].cost
			end
		end
	end
end

-- Rolling: sells non-target units the bot would not field (beyond its best `level` units), so the
-- bench has room for target copies.
local function freeBench(state, memory: Memory)
	local owned = Board.getUnits(state.board)
	table.sort(owned, function(a, b)
		if strength(a) ~= strength(b) then
			return strength(a) > strength(b)
		end
		return a.id < b.id
	end)
	for index = state.level + 1, #owned do
		local unit = owned[index]
		if not isTarget(memory, unit.unitType) then
			sell(state, memory, unit)
		end
	end
end

local function shopPass(state, policy: Policy, memory: Memory)
	if isRolling(policy, memory) then
		rollingShopPass(state, policy, memory)
		return
	end
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
		local seedsTarget = rerolling and cost == policy.rerollCost and #memory.targets < targetsWanted(policy, memory)
		local wanted = isTarget(memory, unitType)
			or seedsTarget
			or fieldedCopy
			or (policy.seeksCopies and ownsUpgradable(state, unitType))
			or #owned < state.level
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
				sell(state, memory, weakest)
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
				sell(state, memory, unit)
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

-- Standard bots, after leveling: buy units that share a trait with last round's board, but only
-- with gold above the bot's keepGold, while it holds fewer than level + 3 units, and only units at
-- least as strong as the weakest unit it fielded (so they can make the board). Buying trait units
-- before leveling locked gold on the bench (trimBench keeps up to level + 3 units), so the bots
-- bought less XP and earned less interest; cheap trait units on the bench also drew copy purchases
-- in later rounds.
-- Offers are taken in order of trait gain (traitGain), highest first; an offer that reaches a
-- breakpoint or completes a bond (gain of 3 or more) may dip BREAKPOINT_DIP gold below keepGold.
local BREAKPOINT_DIP = 10
local function traitPass(state, policy: Policy, memory: Memory)
	if not prefersTraits(policy) or memory.weakestFielded == nil then
		return
	end
	local offers = {}
	for slot, unitType in state.shop do
		if unitType then
			local gain = traitGain(memory, unitType)
			if gain > 0 then
				table.insert(offers, { slot = slot, unitType = unitType, gain = gain })
			end
		end
	end
	table.sort(offers, function(a, b)
		if a.gain ~= b.gain then
			return a.gain > b.gain
		end
		return a.slot < b.slot
	end)
	for _, offer in offers do
		local cost = UnitConfig[offer.unitType].cost
		local floor = if offer.gain >= 3 then policy.keepGold - BREAKPOINT_DIP else policy.keepGold
		if
			state.shop[offer.slot] == offer.unitType
			and cost >= memory.weakestFielded
			and state.gold - cost >= floor
			and #Board.getUnits(state.board) < state.level + 3
		then
			PlayerState.buyUnit(state, offer.slot)
		end
	end
end

-- Plays one Preparation. Returns the units to field, in the player's own board coordinates.
function Bot.prepare(state, policy: Policy, memory: Memory): { any }
	if policy.rerollCost and state.level >= Bot.rollLevel(policy.rerollCost) then
		memory.locked = true
	end
	updateTargets(state, policy, memory)
	if isRolling(policy, memory) then
		freeBench(state, memory)
	end
	shopPass(state, policy, memory)

	if policy.rerollCost then
		if not isRolling(policy, memory) then
			buyXpDownTo(state, LEVEL_UP_KEEP_GOLD)
		else
			local floor = policy.rollFloor or policy.keepGold
			while isRolling(policy, memory) and state.gold >= floor + ShopConfig.rerollCost do
				freeBench(state, memory)
				if not reroll(state, memory) then
					break
				end
				memory.stats.rollStartLevel = memory.stats.rollStartLevel or state.level
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
		traitPass(state, policy, memory)
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
	memory.weakestFielded = nil
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
					memory.weakestFielded = math.min(memory.weakestFielded or math.huge, strength(unit))
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
