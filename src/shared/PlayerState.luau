-- One player's match state: gold, XP, level, streak, shop and board, plus the rules for every
-- action they can request (buy, sell, reroll, buy XP, move). Action arguments may come straight
-- from a client, so every action validates them and returns false without changing anything when
-- the request is invalid. A refusal the player should be told about also returns a reason from
-- PlayerState.Refusal; malformed requests return no reason. The phase check lives in the server.
--
-- Shops draw from the match's shared UnitPool: shown copies are held out of it, unbought ones go
-- back on reroll or refresh, selling returns every copy the unit contains, and releaseAll returns
-- everything when the player is eliminated.
--
-- Combat (PlayerState.startCombat .. endCombat .. startPreparation): the shop stays open (buying,
-- rerolling, buying XP), but the board is locked from the start of combat until the next
-- Preparation: units on the board cannot move or be sold, and nothing can move onto the board.
-- Bench units can be rearranged and sold. Bought units go to the bench (a full bench refuses, as
-- always). While the fight runs, copies on the bench merge at once, but a merge that needs a board
-- copy waits until the fight ends (endCombat). A higher unit cap from leveling only matters once
-- the board unlocks at the next Preparation.
--
-- Items (docs/items.md): the player holds an inventory of item ids (ItemConfig.rules.inventoryCap)
-- and every unit up to ItemConfig.rules.slotsPerUnit items. During Preparation items can be
-- equipped from the inventory, moved between units and returned; from the start of combat until
-- the next Preparation (boardLocked) nothing about items can change. Selling a unit returns its
-- items to the inventory; items a merge cannot keep (Board.looseItems) return too. Returned items
-- may take the inventory past its cap; only picking new items needs a free place.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local Board = if script then require(script.Parent.Board) else require("./Board")
local BoardConfig = if script then require(script.Parent.BoardConfig) else require("./BoardConfig")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local ItemConfig = if script then require(script.Parent.ItemConfig) else require("./ItemConfig")
local EconomyConfig = if script then require(script.Parent.EconomyConfig) else require("./EconomyConfig")
local LevelConfig = if script then require(script.Parent.LevelConfig) else require("./LevelConfig")
local PveConfig = if script then require(script.Parent.PveConfig) else require("./PveConfig")
local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")
local StarLevel = if script then require(script.Parent.StarLevel) else require("./StarLevel")
local ShopConfig = if script then require(script.Parent.ShopConfig) else require("./ShopConfig")
local UnitConfig = if script then require(script.Parent.UnitConfig) else require("./UnitConfig")
local UnitPool = if script then require(script.Parent.UnitPool) else require("./UnitPool")

local PlayerState = {}

-- Reasons shown to the player when a request is refused.
PlayerState.Refusal = table.freeze({
	NotEnoughGold = "Not enough gold",
	BenchFull = "Bench is full",
	BoardFull = "Board is full",
	MaxLevel = "Already at max level",
	BoardLocked = "Board is locked during combat",
	ItemsLocked = "Items can't change during combat",
	ItemSlotsFull = "That unit has no free item slot",
	DuplicateItem = "A unit can't hold two of the same item",
	InventoryFull = "Item inventory is full",
})

export type PlayerState = {
	gold: number,
	level: number,
	xp: number,
	streak: number, -- positive: consecutive wins; negative: consecutive losses
	lastOutcome: string?,
	foughtSincePreparation: boolean, -- income and XP are owed at the next Preparation
	shop: { string | false }, -- false marks a slot that was bought (or empty)
	board: Board.Board,
	rng: SeededRandom.SeededRandom,
	nextUnitId: number,
	pool: UnitPool.Pool, -- the match's shared pool
	boardLocked: boolean, -- from the start of combat until the next Preparation
	holdBoardMerges: boolean, -- while a fight runs: merges needing a board copy wait
	inventory: { string }, -- unequipped item ids
	itemOffer: { string }?, -- an open item choice (pick one), until picked or Preparation ends
	itemRng: SeededRandom.SeededRandom, -- item offers only, so the shop sequence is unchanged
}

-- What the owning client is shown.
export type View = {
	gold: number,
	level: number,
	xp: number,
	xpToNextLevel: number, -- 0 at the maximum level
	streak: number, -- positive: consecutive wins; negative: consecutive losses
	shop: { string | false },
	inventory: { string },
	itemOffer: { string }?,
}

-- Puts the items merges could not keep back in the inventory.
local function collectLooseItems(state)
	for _, item in Board.takeLooseItems(state.board) do
		table.insert(state.inventory, item)
	end
end

-- Merges every completed set of copies (Board.mergeUnits) and returns loose items to the inventory.
local function merge(state, benchOnly: boolean?): { Board.BoardUnit }
	local merges = Board.mergeUnits(state.board, benchOnly)
	collectLooseItems(state)
	return merges
end

-- Returns the shop's unbought copies to the pool and rolls a new shop.
local function refreshShop(state: PlayerState)
	UnitPool.returnShop(state.pool, state.shop)
	state.shop = UnitPool.rollShop(state.pool, state.rng, state.level)
end

-- A new player: starting grant, starting level, no units, and a first shop drawn from `pool` (the
-- match's shared pool; a private full pool if omitted).
function PlayerState.new(seed: number, pool: UnitPool.Pool?): PlayerState
	local state = {
		gold = EconomyConfig.startingGold,
		level = LevelConfig.startingLevel,
		xp = 0,
		streak = 0,
		lastOutcome = nil,
		foughtSincePreparation = false,
		shop = {},
		board = Board.new(BoardConfig.columns, BoardConfig.rows, BoardConfig.benchSlots),
		rng = SeededRandom.new(seed),
		nextUnitId = 1,
		pool = pool or UnitPool.new(),
		boardLocked = false,
		holdBoardMerges = false,
		inventory = {},
		itemOffer = nil,
		itemRng = SeededRandom.new(seed * 31 + 17),
	}
	refreshShop(state)
	return state
end

-- Combat starts: the board locks and merges needing a board copy wait.
function PlayerState.startCombat(state: PlayerState)
	state.boardLocked = true
	state.holdBoardMerges = true
end

-- The fight is over: waiting merges happen now. The board stays locked until the next Preparation.
-- Returns the merges (Board.mergeUnits).
function PlayerState.endCombat(state: PlayerState): { Board.BoardUnit }
	state.holdBoardMerges = false
	return merge(state)
end

-- Called at the start of every Preparation. Unlocks the board (finishing any waiting merge). If
-- the player fought since the last one, pays round income and the automatic XP. Always rolls a
-- fresh shop. Returns the income paid, if any.
function PlayerState.startPreparation(state: PlayerState): Economy.Income?
	if state.boardLocked or state.holdBoardMerges then
		state.boardLocked = false
		state.holdBoardMerges = false
		merge(state)
	end
	local income = nil
	if state.foughtSincePreparation then
		income = Economy.roundIncome(state.gold, state.streak, state.lastOutcome == Economy.Outcome.Win)
		state.gold += income.total
		state.level, state.xp = Economy.addXp(state.level, state.xp, LevelConfig.xpPerRound)
		state.foughtSincePreparation = false
	end
	refreshShop(state)
	return income
end

-- Records a fight's outcome (Economy.Outcome) for the streak and the next round's income.
function PlayerState.recordCombat(state: PlayerState, outcome: string)
	state.streak = Economy.nextStreak(state.streak, outcome)
	state.lastOutcome = outcome
	state.foughtSincePreparation = true
end

-- Pays trait gold (Crew takedowns after a PvP fight; Match.applyResults) now. It changes nothing
-- else: income, streaks and the next round are untouched.
function PlayerState.grantGold(state: PlayerState, gold: number)
	state.gold += math.max(0, math.floor(gold))
end

-- Records a PvE fight (creep or boss round): pays its reward gold now. The next Preparation still
-- pays round income and XP, but PvE leaves the win/loss streak unchanged and earns no win bonus.
function PlayerState.recordPve(state: PlayerState, gold: number)
	state.gold += gold
	state.lastOutcome = nil
	state.foughtSincePreparation = true
end

-- Gives the match-start units (PveConfig.startingUnits): random units of the configured cost drawn
-- from the shared pool, each placed on the first free listed cell (on the bench if none is free or
-- the board is at the level cap). Returns their unit types.
function PlayerState.grantStartingUnits(state: PlayerState): { string }
	local rule = PveConfig.startingUnits
	local granted = {}
	for _ = 1, rule.count do
		if not Board.hasBenchSpace(state.board) then
			break
		end
		local unitType = UnitPool.drawOfCost(state.pool, state.rng, rule.cost)
		if not unitType then
			break
		end
		local id = tostring(state.nextUnitId)
		state.nextUnitId += 1
		Board.addUnit(state.board, id, unitType)
		local taken = {}
		for _, unit in Board.getPlacedUnits(state.board) do
			taken[unit.column .. "," .. unit.row] = true
		end
		for _, cell in rule.cells do
			-- Moving onto an occupied cell would swap, so only free cells are tried.
			if not taken[cell.column .. "," .. cell.row] then
				if Board.moveUnit(state.board, id, { column = cell.column, row = cell.row }, state.level) then
					break
				end
			end
		end
		merge(state)
		table.insert(granted, unitType)
	end
	return granted
end

-- Buys the unit in a shop slot onto the bench, then merges any completed set of copies. Refused if
-- the slot is empty or invalid, the player cannot afford it, or the bench is full (unless this copy
-- completes a merge, which needs no bench slot). While a fight runs, only bench copies merge.
function PlayerState.buyUnit(state: PlayerState, slotIndex: any): (boolean, string?)
	local unitType = if type(slotIndex) == "number" then state.shop[slotIndex] else nil
	if type(unitType) ~= "string" then
		return false
	end
	if state.gold < UnitConfig[unitType].cost then
		return false, PlayerState.Refusal.NotEnoughGold
	end
	local benchFull = not Board.hasBenchSpace(state.board)
	if benchFull and not Board.completesMerge(state.board, unitType, state.holdBoardMerges) then
		return false, PlayerState.Refusal.BenchFull
	end
	Board.addUnit(state.board, tostring(state.nextUnitId), unitType, benchFull)
	merge(state, state.holdBoardMerges)
	state.nextUnitId += 1
	state.gold -= UnitConfig[unitType].cost
	state.shop[slotIndex] = false
	return true
end

-- Sells one of the player's units from the board or bench for the total gold spent on it:
-- its cost times the copies it contains (1, 3 or 9). Those copies go back to the pool. While the
-- board is locked, only bench units can be sold.
function PlayerState.sellUnit(state: PlayerState, unitId: any): (boolean, string?)
	local owned = if type(unitId) == "string" then state.board.units[unitId] else nil
	if not owned then
		return false
	end
	if state.boardLocked and owned.column then
		return false, PlayerState.Refusal.BoardLocked
	end
	local unit = Board.removeUnit(state.board, unitId)
	if not unit then
		return false
	end
	state.gold += PlayerState.sellValue(unit.unitType, unit.starLevel)
	UnitPool.give(state.pool, unit.unitType, StarLevel.copiesIn(unit.starLevel))
	-- Its items go back to the inventory.
	for _, item in unit.items or {} do
		table.insert(state.inventory, item)
	end
	return true
end

-- Returns every copy the player holds (units on the board and bench, and the shop) to the pool,
-- leaving them with no units and an empty shop. Called when the player is eliminated.
function PlayerState.releaseAll(state: PlayerState)
	for _, unit in Board.getUnits(state.board) do
		Board.removeUnit(state.board, unit.id)
		UnitPool.give(state.pool, unit.unitType, StarLevel.copiesIn(unit.starLevel))
	end
	UnitPool.returnShop(state.pool, state.shop)
	state.shop = table.create(ShopConfig.slots, false)
end

function PlayerState.sellValue(unitType: string, starLevel: number): number
	return UnitConfig[unitType].cost * StarLevel.copiesIn(starLevel)
end

function PlayerState.reroll(state: PlayerState): (boolean, string?)
	if state.gold < ShopConfig.rerollCost then
		return false, PlayerState.Refusal.NotEnoughGold
	end
	state.gold -= ShopConfig.rerollCost
	refreshShop(state)
	return true
end

function PlayerState.buyXp(state: PlayerState): (boolean, string?)
	if state.level >= LevelConfig.maxLevel then
		return false, PlayerState.Refusal.MaxLevel
	end
	if state.gold < LevelConfig.buyXpCost then
		return false, PlayerState.Refusal.NotEnoughGold
	end
	state.gold -= LevelConfig.buyXpCost
	state.level, state.xp = Economy.addXp(state.level, state.xp, LevelConfig.buyXpAmount)
	return true
end

-- Moves or swaps a unit. The number of units on the board is capped at the player's level. While
-- the board is locked, only bench units move, and only to bench slots.
function PlayerState.moveUnit(state: PlayerState, unitId: any, target: any): (boolean, string?)
	if state.boardLocked then
		local unit = if type(unitId) == "string" then state.board.units[unitId] else nil
		if not unit then
			return false
		end
		if not unit.slot or type(target) ~= "table" or target.slot == nil then
			return false, PlayerState.Refusal.BoardLocked
		end
	end
	local moved, reason = Board.moveUnit(state.board, unitId, target, state.level)
	if reason == Board.CapReached then
		return false, PlayerState.Refusal.BoardFull
	end
	return moved
end

-- Items ----------------------------------------------------------------------------------------

local function isIndex(value: any, size: number): boolean
	return type(value) == "number" and value == math.floor(value) and value >= 1 and value <= size
end

-- True if `unit` can take `item`: a free slot and no copy of it already.
local function canHold(unit, item: string): (boolean, string?)
	if #unit.items >= ItemConfig.rules.slotsPerUnit then
		return false, PlayerState.Refusal.ItemSlotsFull
	end
	if table.find(unit.items, item) then
		return false, PlayerState.Refusal.DuplicateItem
	end
	return true
end

-- Equips the inventory item at `inventoryIndex` onto one of the player's units (board or bench).
function PlayerState.equipItem(state: PlayerState, inventoryIndex: any, unitId: any): (boolean, string?)
	local unit = if type(unitId) == "string" then state.board.units[unitId] else nil
	if not unit or not isIndex(inventoryIndex, #state.inventory) then
		return false
	end
	if state.boardLocked then
		return false, PlayerState.Refusal.ItemsLocked
	end
	unit.items = unit.items or {}
	local item = state.inventory[inventoryIndex]
	local ok, reason = canHold(unit, item)
	if not ok then
		return false, reason
	end
	table.remove(state.inventory, inventoryIndex)
	table.insert(unit.items, item)
	return true
end

-- Returns the item in a unit's slot to the inventory (refused when the inventory is full).
function PlayerState.unequipItem(state: PlayerState, unitId: any, slotIndex: any): (boolean, string?)
	local unit = if type(unitId) == "string" then state.board.units[unitId] else nil
	if not unit or not isIndex(slotIndex, #(unit.items or {})) then
		return false
	end
	if state.boardLocked then
		return false, PlayerState.Refusal.ItemsLocked
	end
	if #state.inventory >= ItemConfig.rules.inventoryCap then
		return false, PlayerState.Refusal.InventoryFull
	end
	table.insert(state.inventory, table.remove(unit.items, slotIndex))
	return true
end

-- Moves the item in one unit's slot onto another of the player's units.
function PlayerState.moveItem(state: PlayerState, unitId: any, slotIndex: any, toUnitId: any): (boolean, string?)
	local from = if type(unitId) == "string" then state.board.units[unitId] else nil
	local to = if type(toUnitId) == "string" then state.board.units[toUnitId] else nil
	if not from or not to or from == to or not isIndex(slotIndex, #(from.items or {})) then
		return false
	end
	if state.boardLocked then
		return false, PlayerState.Refusal.ItemsLocked
	end
	to.items = to.items or {}
	local item = from.items[slotIndex]
	local ok, reason = canHold(to, item)
	if not ok then
		return false, reason
	end
	table.remove(from.items, slotIndex)
	table.insert(to.items, item)
	return true
end

function PlayerState.getView(state: PlayerState): View
	return {
		gold = state.gold,
		level = state.level,
		xp = state.xp,
		xpToNextLevel = Economy.xpToNextLevel(state.level) or 0,
		streak = state.streak,
		shop = table.clone(state.shop),
		inventory = table.clone(state.inventory),
		itemOffer = if state.itemOffer then table.clone(state.itemOffer) else nil,
	}
end

return PlayerState
