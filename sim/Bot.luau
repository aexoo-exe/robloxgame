-- A simple scripted player for headless match simulations. It acts through the real PlayerState
-- rules (buying, selling, rerolling, buying XP) and then chooses which units to field.
--
-- Placement is simplified: the bot returns a list of placed units for CombatSim directly instead of
-- moving them on its Board one by one. It always fields its best `level` units: frontline in the
-- front row, ranged units in the back row, fast melee in between.

local Board = require("../src/shared/Board")
local PlayerState = require("../src/shared/PlayerState")
local UnitConfig = require("../src/shared/UnitConfig")

local Bot = {}

export type Policy = {
	name: string,
	keepGold: number, -- buys XP only with gold above this (interest saving)
	seeksCopies: boolean, -- buys copies of owned units to upgrade them
	rerollsFromLevel: number?, -- rerolls spare gold for copies from this level on
}

-- Strategies cycled across the bots in a match.
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

local ROW_ORDER = { 4, 3, 5, 2, 6, 1, 7 }

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

local function shopPass(state, policy: Policy)
	-- Most expensive offers first.
	local slots = {}
	for slot, unitType in state.shop do
		if unitType then
			table.insert(slots, slot)
		end
	end
	table.sort(slots, function(a, b)
		return UnitConfig[state.shop[a]].cost > UnitConfig[state.shop[b]].cost
	end)

	for _, slot in slots do
		local unitType = state.shop[slot]
		local cost = UnitConfig[unitType].cost
		local owned = Board.getUnits(state.board)
		local wanted = (policy.seeksCopies and ownsUpgradable(state, unitType)) or #owned < state.level
		if wanted then
			PlayerState.buyUnit(state, slot)
		else
			-- Replace the weakest unit when the offer is a clear upgrade.
			table.sort(owned, function(a, b)
				return strength(a) < strength(b)
			end)
			local weakest = owned[1]
			if weakest and strength(weakest) < cost and state.gold + strength(weakest) >= cost then
				PlayerState.sellUnit(state, weakest.id)
				PlayerState.buyUnit(state, slot)
			end
		end
	end
end

-- Sells extra units beyond what the bot can field, keeping copies it is collecting.
local function trimBench(state, policy: Policy)
	local owned = Board.getUnits(state.board)
	table.sort(owned, function(a, b)
		return strength(a) > strength(b)
	end)
	for index = state.level + 3, #owned do
		local unit = owned[index]
		if not (policy.seeksCopies and unit.starLevel < 3) or index > state.level + 6 then
			PlayerState.sellUnit(state, unit.id)
		end
	end
end

-- Plays one Preparation. Returns the units to field, in the player's own board coordinates.
function Bot.prepare(state, policy: Policy): { any }
	shopPass(state, policy)
	if policy.rerollsFromLevel and state.level >= policy.rerollsFromLevel then
		while state.gold >= policy.keepGold + 2 and PlayerState.reroll(state) do
			shopPass(state, policy)
		end
	end
	-- Buy XP down to the gold the policy wants to keep.
	while state.gold >= policy.keepGold + 4 do
		if not PlayerState.buyXp(state) then
			break
		end
	end
	trimBench(state, policy)

	local owned = Board.getUnits(state.board)
	table.sort(owned, function(a, b)
		return strength(a) > strength(b)
	end)
	local placed = {}
	local used = { [4] = 0, [3] = 0, [1] = 0 }
	for index = 1, math.min(state.level, #owned) do
		local unit = owned[index]
		local stats = UnitConfig[unit.unitType]
		local row = if stats.role == "Frontline" then 4 elseif stats.range > 1 then 1 else 3
		used[row] += 1
		if used[row] > #ROW_ORDER then
			row = 2 -- overflow row
			used[row] = (used[row] or 0) + 1
		end
		table.insert(placed, {
			id = unit.id,
			unitType = unit.unitType,
			starLevel = unit.starLevel,
			column = ROW_ORDER[used[row]],
			row = row,
		})
	end
	return placed
end

return Bot
