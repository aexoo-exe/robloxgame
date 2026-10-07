-- PvE round rules (docs/pve-rounds.md): which rounds are creep or boss rounds, their preparation
-- time, the enemy boards and unit types a theme provides, and the gold a PvE fight earns. Numbers
-- are in PveConfig; themes in PveThemeConfig. The server (RoundService, CombatService), Match and
-- the headless sim all use this module, so they agree.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local MatchConfig = if script then require(script.Parent.MatchConfig) else require("./MatchConfig")
local MatchRules = if script then require(script.Parent.MatchRules) else require("./MatchRules")
local PveConfig = if script then require(script.Parent.PveConfig) else require("./PveConfig")
local PveThemeConfig = if script then require(script.Parent.PveThemeConfig) else require("./PveThemeConfig")
local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")
local UnitConfig = if script then require(script.Parent.UnitConfig) else require("./UnitConfig")

local Pve = {}

-- What a round is. Replicated to clients as the MatchState "RoundKind" attribute.
Pve.Kind = table.freeze({
	PvP = "PvP",
	Creep = "Creep",
	Boss = "Boss",
})

-- Gold a PvE fight earned, and why.
export type Reward = {
	kind: string, -- Pve.Kind.Creep or Pve.Kind.Boss
	gold: number,
	creepsKilled: number?, -- creep rounds
	creeps: number?,
	share: number?, -- boss rounds: fraction (0-1) of the boss's health removed
	bossKilled: boolean?,
}

local bossRoundSet = {}
for _, round in PveConfig.bossRounds do
	bossRoundSet[round] = true
end

function Pve.roundKind(round: number): string
	if round <= PveConfig.openingCreepRounds then
		return Pve.Kind.Creep
	elseif bossRoundSet[round] then
		return Pve.Kind.Boss
	end
	return Pve.Kind.PvP
end

function Pve.isPve(round: number): boolean
	return Pve.roundKind(round) ~= Pve.Kind.PvP
end

-- Seconds of Preparation before `round` (0: no Preparation phase).
function Pve.preparationDuration(round: number): number
	return PveConfig.preparationDurations[round] or MatchConfig.preparationDuration
end

-- Theme ids, sorted so a seed always picks the same theme.
function Pve.themeIds(): { string }
	local ids = {}
	for id in PveThemeConfig do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Picks the theme for a match.
function Pve.pickTheme(rng: SeededRandom.SeededRandom): string
	local ids = Pve.themeIds()
	return ids[SeededRandom.nextInt(rng, #ids)]
end

-- A PvE unit type (creep or boss) of any theme, or nil.
function Pve.pveUnitType(unitType: string): any?
	for _, theme in PveThemeConfig do
		if theme.units[unitType] then
			return theme.units[unitType]
		end
	end
	return nil
end

-- Stats of any unit type the combat engine can meet: a character or a PvE unit.
function Pve.unitType(unitType: string): any?
	return UnitConfig[unitType] or Pve.pveUnitType(unitType)
end

-- Every character plus the theme's creeps and bosses, for CombatSim's `unitTypes` in a PvE fight.
local mergedByTheme = {}
function Pve.unitTypes(themeId: string): { [string]: any }
	local merged = mergedByTheme[themeId]
	if not merged then
		merged = table.clone(UnitConfig)
		for id, unit in PveThemeConfig[themeId].units do
			merged[id] = unit
		end
		table.freeze(merged)
		mergedByTheme[themeId] = merged
	end
	return merged
end

-- The enemy board of a PvE round (CombatSim PlacedUnits in the enemy's own board coordinates):
-- the theme's creep lineup for a creep round, its stage boss for a boss round.
function Pve.enemyBoard(themeId: string, round: number): { any }
	local theme = PveThemeConfig[themeId]
	local kind = Pve.roundKind(round)
	local entries
	if kind == Pve.Kind.Creep then
		entries = theme.creepRounds[round]
	elseif kind == Pve.Kind.Boss then
		entries = { theme.bosses[MatchRules.stage(round)] }
	end
	assert(entries, string.format("theme %s has no enemies for round %d", themeId, round))
	local board = {}
	for i, entry in entries do
		table.insert(board, {
			id = "pve" .. i,
			unitType = entry.unitType,
			starLevel = 1,
			column = entry.column,
			row = entry.row,
		})
	end
	return board
end

-- Gold for a boss fight that removed `share` (0-1) of the boss's health.
function Pve.bossGold(share: number, killed: boolean): number
	local gold = 0
	for _, step in PveConfig.bossRewardSteps do
		-- The tolerance keeps exact boundaries (1 - 0.55 is 0.4499...) in the higher step.
		if share + 1e-9 >= step.minShare then
			gold = math.max(gold, step.gold)
		end
	end
	return gold + (if killed then PveConfig.bossKillBonus else 0)
end

-- The reward for one PvE fight in `round`, from its combat result (the player is side 1).
-- `survivors` and `healthPercent` are the CombatSim result fields.
function Pve.reward(themeId: string, round: number, survivors: { number }, healthPercent: { number }?): Reward
	local kind = Pve.roundKind(round)
	if kind == Pve.Kind.Creep then
		local creeps = #Pve.enemyBoard(themeId, round)
		local killed = math.clamp(creeps - survivors[2], 0, creeps)
		local gold = (PveConfig.creepRoundGold[round] or 0) * killed // creeps
		return { kind = kind, gold = gold, creepsKilled = killed, creeps = creeps }
	end
	local bossKilled = survivors[2] == 0
	local remaining = if bossKilled then 0 elseif healthPercent then healthPercent[2] else 1
	local share = math.clamp(1 - remaining, 0, 1)
	return { kind = kind, gold = Pve.bossGold(share, bossKilled), share = share, bossKilled = bossKilled }
end

-- Player HP lost for not winning a PvE fight of `kind`.
function Pve.healthLoss(kind: string): number
	return PveConfig.healthLoss[kind] or 0
end

-- Short result text for the player, e.g. "Creeps: 3/3 killed, +3 gold".
function Pve.resultText(reward: Reward): string
	if reward.kind == Pve.Kind.Creep then
		return string.format("Creeps: %d/%d killed, +%d gold", reward.creepsKilled, reward.creeps, reward.gold)
	elseif reward.bossKilled then
		return string.format("Boss defeated! +%d gold", reward.gold)
	end
	return string.format("Boss: %d%% damage dealt, +%d gold", math.floor((reward.share or 0) * 100), reward.gold)
end

return Pve
