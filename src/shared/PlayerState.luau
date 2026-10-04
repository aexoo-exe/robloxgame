-- One player's match state: gold, XP, level, streak, shop and board, plus the rules for every
-- action they can request (buy, sell, reroll, buy XP, move). Action arguments may come straight
-- from a client, so every action validates them and returns false without changing anything when
-- the request is invalid. The phase check lives in the server.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local Board = if script then require(script.Parent.Board) else require("./Board")
local BoardConfig = if script then require(script.Parent.BoardConfig) else require("./BoardConfig")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local EconomyConfig = if script then require(script.Parent.EconomyConfig) else require("./EconomyConfig")
local LevelConfig = if script then require(script.Parent.LevelConfig) else require("./LevelConfig")
local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")
local Shop = if script then require(script.Parent.Shop) else require("./Shop")
local ShopConfig = if script then require(script.Parent.ShopConfig) else require("./ShopConfig")
local UnitConfig = if script then require(script.Parent.UnitConfig) else require("./UnitConfig")

local PlayerState = {}

export type PlayerState = {
	gold: number,
	level: number,
	xp: number,
	streak: number, -- positive: consecutive wins; negative: consecutive losses
	lastOutcome: string?,
	foughtSincePreparation: boolean, -- income and XP are owed at the next Preparation
	shop: { string | false }, -- false marks a slot that was bought
	board: Board.Board,
	rng: SeededRandom.SeededRandom,
	nextUnitId: number,
}

-- What the owning client is shown.
export type View = {
	gold: number,
	level: number,
	xp: number,
	xpToNextLevel: number, -- 0 at the maximum level
	shop: { string | false },
}

-- A new player: starting grant, starting level, no units, and a first shop.
function PlayerState.new(seed: number): PlayerState
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
	}
	state.shop = Shop.roll(state.rng, state.level)
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
	state.shop = Shop.roll(state.rng, state.level)
	return income
end

-- Records a fight's outcome (Economy.Outcome) for the streak and the next round's income.
function PlayerState.recordCombat(state: PlayerState, outcome: string)
	state.streak = Economy.nextStreak(state.streak, outcome)
	state.lastOutcome = outcome
	state.foughtSincePreparation = true
end

-- Buys the unit in a shop slot onto the bench. Refused if the slot is empty or invalid, the player
-- cannot afford it, or the bench is full.
function PlayerState.buyUnit(state: PlayerState, slotIndex: any): boolean
	local unitType = if type(slotIndex) == "number" then state.shop[slotIndex] else nil
	if type(unitType) ~= "string" then
		return false
	end
	local cost = UnitConfig[unitType].cost
	if state.gold < cost or not Board.hasBenchSpace(state.board) then
		return false
	end
	Board.addUnit(state.board, tostring(state.nextUnitId), unitType)
	state.nextUnitId += 1
	state.gold -= cost
	state.shop[slotIndex] = false
	return true
end

-- Sells one of the player's units from the board or bench for its full cost.
function PlayerState.sellUnit(state: PlayerState, unitId: any): boolean
	local unit = Board.removeUnit(state.board, unitId)
	if not unit then
		return false
	end
	state.gold += UnitConfig[unit.unitType].cost
	return true
end

function PlayerState.reroll(state: PlayerState): boolean
	if state.gold < ShopConfig.rerollCost then
		return false
	end
	state.gold -= ShopConfig.rerollCost
	state.shop = Shop.roll(state.rng, state.level)
	return true
end

function PlayerState.buyXp(state: PlayerState): boolean
	if state.level >= LevelConfig.maxLevel or state.gold < LevelConfig.buyXpCost then
		return false
	end
	state.gold -= LevelConfig.buyXpCost
	state.level, state.xp = Economy.addXp(state.level, state.xp, LevelConfig.buyXpAmount)
	return true
end

-- Moves or swaps a unit. The number of units on the board is capped at the player's level.
function PlayerState.moveUnit(state: PlayerState, unitId: any, target: any): boolean
	return Board.moveUnit(state.board, unitId, target, state.level)
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
