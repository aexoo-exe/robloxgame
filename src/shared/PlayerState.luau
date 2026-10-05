-- One player's match state: gold, XP, level, streak, shop and board, plus the rules for every
-- action they can request (buy, sell, reroll, buy XP, move). Action arguments may come straight
-- from a client, so every action validates them and returns false without changing anything when
-- the request is invalid. A refusal the player should be told about also returns a reason from
-- PlayerState.Refusal; malformed requests return no reason. The phase check lives in the server.
--
-- Shops draw from the match's shared UnitPool: shown copies are held out of it, unbought ones go
-- back on reroll or refresh, selling returns every copy the unit contains, and releaseAll returns
-- everything when the player is eliminated.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local Board = if script then require(script.Parent.Board) else require("./Board")
local BoardConfig = if script then require(script.Parent.BoardConfig) else require("./BoardConfig")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local EconomyConfig = if script then require(script.Parent.EconomyConfig) else require("./EconomyConfig")
local LevelConfig = if script then require(script.Parent.LevelConfig) else require("./LevelConfig")
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
}

-- What the owning client is shown.
export type View = {
	gold: number,
	level: number,
	xp: number,
	xpToNextLevel: number, -- 0 at the maximum level
	shop: { string | false },
}

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
	}
	refreshShop(state)
	return state
end

-- Called at the start of every Preparation. If the player fought since the last one, pays round
-- income and the automatic XP. Always rolls a fresh shop. Returns the income paid, if any.
function PlayerState.startPreparation(state: PlayerState): Economy.Income?
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

-- Buys the unit in a shop slot onto the bench, then merges any completed set of copies. Refused if
-- the slot is empty or invalid, the player cannot afford it, or the bench is full (unless this copy
-- completes a merge, which needs no bench slot).
function PlayerState.buyUnit(state: PlayerState, slotIndex: any): (boolean, string?)
	local unitType = if type(slotIndex) == "number" then state.shop[slotIndex] else nil
	if type(unitType) ~= "string" then
		return false
	end
	if state.gold < UnitConfig[unitType].cost then
		return false, PlayerState.Refusal.NotEnoughGold
	end
	local benchFull = not Board.hasBenchSpace(state.board)
	if benchFull and not Board.completesMerge(state.board, unitType) then
		return false, PlayerState.Refusal.BenchFull
	end
	Board.addUnit(state.board, tostring(state.nextUnitId), unitType, benchFull)
	Board.mergeUnits(state.board)
	state.nextUnitId += 1
	state.gold -= UnitConfig[unitType].cost
	state.shop[slotIndex] = false
	return true
end

-- Sells one of the player's units from the board or bench for the total gold spent on it:
-- its cost times the copies it contains (1, 3 or 9). Those copies go back to the pool.
function PlayerState.sellUnit(state: PlayerState, unitId: any): boolean
	local unit = Board.removeUnit(state.board, unitId)
	if not unit then
		return false
	end
	state.gold += PlayerState.sellValue(unit.unitType, unit.starLevel)
	UnitPool.give(state.pool, unit.unitType, StarLevel.copiesIn(unit.starLevel))
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

-- Moves or swaps a unit. The number of units on the board is capped at the player's level.
function PlayerState.moveUnit(state: PlayerState, unitId: any, target: any): (boolean, string?)
	local moved, reason = Board.moveUnit(state.board, unitId, target, state.level)
	if reason == Board.CapReached then
		return false, PlayerState.Refusal.BoardFull
	end
	return moved
end

function PlayerState.getView(state: PlayerState): View
	return {
		gold = state.gold,
		level = state.level,
		xp = state.xp,
		xpToNextLevel = Economy.xpToNextLevel(state.level) or 0,
		shop = table.clone(state.shop),
	}
end

return PlayerState
