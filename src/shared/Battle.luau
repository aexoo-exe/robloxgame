-- State of one fight and the primitive actions everything else uses: damage (the only place
-- damage is applied), heals, shields, stuns, buffs and relocation. Each primitive records an event
-- for client playback. CombatSim runs the tick loop; Abilities composes these primitives.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local CombatConfig = if script then require(script.Parent.CombatConfig) else require("./CombatConfig")
local CombatMath = if script then require(script.Parent.CombatMath) else require("./CombatMath")
local HexGrid = if script then require(script.Parent.HexGrid) else require("./HexGrid")
local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")
local StarLevel = if script then require(script.Parent.StarLevel) else require("./StarLevel")

local Battle = {}

-- Stats a BUFF can change, mapped to the unit stat field they modify.
local STAT_FIELDS = table.freeze({
	AD = "attackDamage",
	AP = "abilityPower",
	AttackSpeed = "attacksPerSecond",
	Armor = "armor",
	MR = "magicResist",
	MoveSpeed = "moveSpeed",
})
Battle.StatFields = STAT_FIELDS

-- A unit in combat. `stats` are the unit type's stats with star scaling applied.
export type Unit = {
	index: number,
	side: number,
	id: string,
	unitType: string,
	starLevel: number,
	stats: { [string]: any },
	ability: any?,
	column: number,
	row: number,
	health: number,
	maxHealth: number,
	mana: number,
	maxMana: number?, -- nil: the unit never casts
	shield: number,
	shieldEndsTick: number,
	stunnedUntilTick: number,
	castEndsTick: number,
	buffs: { [string]: { stat: string, flat: number, percent: number, endsTick: number } },
	attackCooldown: number,
	moveCooldown: number,
	target: Unit?,
	dead: boolean,
}

export type Battle = {
	tick: number,
	ticksPerSecond: number,
	columns: number,
	fieldRows: number,
	critChance: number,
	rng: SeededRandom.SeededRandom,
	units: { Unit },
	occupied: { [number]: Unit },
	events: { any },
}

-- Creates a battle. Side 2's units are rotated half a turn into the far half of the field.
-- `critChance` overrides CombatConfig.critChance (tests use 0 for exact damage).
function Battle.new(params): Battle
	local battle = {
		tick = 0,
		ticksPerSecond = params.ticksPerSecond,
		columns = params.columns,
		fieldRows = params.rows * 2,
		critChance = params.critChance or CombatConfig.critChance,
		rng = SeededRandom.new(params.seed),
		units = {},
		occupied = {},
		events = {},
	}
	for side = 1, 2 do
		for _, placed in params.boards[side] do
			local column, row = placed.column, placed.row
			if side == 2 then
				column, row = HexGrid.rotateHalfTurn(column, row, battle.columns, battle.fieldRows)
			end
			-- Star scaling is applied here, once, as the unit enters combat.
			local starLevel = placed.starLevel or 1
			local stats = StarLevel.scaleStats(params.unitTypes[placed.unitType], starLevel)
			local unit = {
				index = #battle.units + 1,
				side = side,
				id = placed.id,
				unitType = placed.unitType,
				starLevel = starLevel,
				stats = stats,
				ability = stats.ability,
				column = column,
				row = row,
				health = stats.health,
				maxHealth = stats.health,
				mana = stats.startingMana or 0,
				maxMana = stats.maxMana,
				shield = 0,
				shieldEndsTick = 0,
				stunnedUntilTick = 0,
				castEndsTick = 0,
				buffs = {},
				attackCooldown = 0,
				moveCooldown = 0,
				target = nil,
				dead = false,
			}
			table.insert(battle.units, unit)
			battle.occupied[Battle.cellKey(battle, column, row)] = unit
		end
	end
	return battle
end

function Battle.cellKey(battle: Battle, column: number, row: number): number
	return (row - 1) * battle.columns + column
end

function Battle.inBounds(battle: Battle, column: number, row: number): boolean
	return column >= 1 and column <= battle.columns and row >= 1 and row <= battle.fieldRows
end

function Battle.isFree(battle: Battle, column: number, row: number): boolean
	return Battle.inBounds(battle, column, row) and battle.occupied[Battle.cellKey(battle, column, row)] == nil
end

function Battle.distance(a: Unit, b: Unit): number
	return HexGrid.distance(a.column, a.row, b.column, b.row)
end

function Battle.seconds(battle: Battle, seconds: number): number
	return math.round(seconds * battle.ticksPerSecond)
end

function Battle.emit(battle: Battle, event)
	event.tick = battle.tick
	table.insert(battle.events, event)
end

-- Living units on the other side, in index order.
function Battle.enemiesOf(battle: Battle, unit: Unit): { Unit }
	local result = {}
	for _, other in battle.units do
		if other.side ~= unit.side and not other.dead then
			table.insert(result, other)
		end
	end
	return result
end

-- Living units on the same side, including `unit`, in index order.
function Battle.alliesOf(battle: Battle, unit: Unit): { Unit }
	local result = {}
	for _, other in battle.units do
		if other.side == unit.side and not other.dead then
			table.insert(result, other)
		end
	end
	return result
end

-- Picks one of the units that score best (highest `score`), breaking ties with the seeded random
-- generator. Returns nil for an empty list.
function Battle.pickBest(battle: Battle, candidates: { Unit }, score: (Unit) -> number): Unit?
	local best = {}
	local bestScore = -math.huge
	for _, unit in candidates do
		local value = score(unit)
		if value > bestScore then
			best = { unit }
			bestScore = value
		elseif value == bestScore then
			table.insert(best, unit)
		end
	end
	if #best == 0 then
		return nil
	end
	return best[SeededRandom.nextInt(battle.rng, #best)]
end

-- A stat with active buffs applied: (base + flat bonuses) x (1 + percent bonuses / 100).
-- `name` is a BUFF stat name (AD, AP, AttackSpeed, Armor, MR, MoveSpeed).
function Battle.stat(battle: Battle, unit: Unit, name: string): number
	local field = STAT_FIELDS[name]
	local base = unit.stats[field]
	if base == nil then
		base = if name == "AP" then CombatConfig.baseAbilityPower else 0
	end
	local flat, percent = 0, 0
	for _, buff in unit.buffs do
		if buff.stat == name and battle.tick < buff.endsTick then
			flat += buff.flat
			percent += buff.percent
		end
	end
	return (base + flat) * (1 + percent / 100)
end

local function gainMana(unit: Unit, amount: number)
	if unit.maxMana and not unit.dead then
		unit.mana = math.min(unit.maxMana, unit.mana + amount)
	end
end

-- Applies one hit: resistance, shield, health, mana for both sides, the event and any death.
-- `kind` is "Attack" for a basic attack (the attacker gains mana) or "Damage" for ability damage.
-- Returns the final damage after resistance.
function Battle.damage(
	battle: Battle,
	source: Unit,
	target: Unit,
	raw: number,
	damageType: string,
	kind: string,
	crit: boolean?
): number
	if target.dead then
		return 0
	end
	local armor = Battle.stat(battle, target, "Armor")
	local magicResist = Battle.stat(battle, target, "MR")
	local final = CombatMath.finalDamage(raw, damageType, armor, magicResist)

	local absorbed = math.min(target.shield, final)
	target.shield -= absorbed
	local healthLost = math.min(target.health, final - absorbed)
	target.health -= healthLost
	gainMana(target, CombatMath.manaFromDamage(healthLost, target.maxHealth))
	if kind == "Attack" then
		gainMana(source, CombatConfig.manaPerAttack)
	end

	Battle.emit(battle, {
		kind = kind,
		unit = source.index,
		target = target.index,
		damage = final,
		health = target.health,
		shield = target.shield,
		mana = source.mana,
		targetMana = target.mana,
		crit = if crit then true else nil,
	})

	if target.health <= 0 then
		target.dead = true
		battle.occupied[Battle.cellKey(battle, target.column, target.row)] = nil
		Battle.emit(battle, { kind = "Death", unit = target.index })
	end
	return final
end

-- Restores health, capped at max health. Amounts are rounded to whole numbers.
function Battle.heal(battle: Battle, source: Unit, target: Unit, amount: number)
	if target.dead then
		return
	end
	local healed = math.min(target.maxHealth - target.health, math.round(amount))
	target.health += healed
	Battle.emit(
		battle,
		{ kind = "Heal", unit = source.index, target = target.index, amount = healed, health = target.health }
	)
end

-- Gives a shield for `seconds`. Shields do not stack: the larger of the new shield and the
-- remaining one is kept (a new shield of equal size replaces the old one and its duration).
function Battle.shield(battle: Battle, source: Unit, target: Unit, amount: number, seconds: number)
	if target.dead then
		return
	end
	amount = math.round(amount)
	local remaining = if battle.tick < target.shieldEndsTick then target.shield else 0
	if amount < remaining then
		return
	end
	target.shield = amount
	target.shieldEndsTick = battle.tick + Battle.seconds(battle, seconds)
	Battle.emit(battle, {
		kind = "Shield",
		unit = source.index,
		target = target.index,
		shield = amount,
		duration = seconds,
	})
end

-- Stuns for `seconds`. Overlapping stuns do not add up; the later end time wins.
function Battle.stun(battle: Battle, source: Unit, target: Unit, seconds: number)
	if target.dead then
		return
	end
	target.stunnedUntilTick = math.max(target.stunnedUntilTick, battle.tick + Battle.seconds(battle, seconds))
	Battle.emit(battle, { kind = "Stun", unit = source.index, target = target.index, duration = seconds })
end

-- Buffs one stat for `seconds`. Buffs from the same source to the same stat refresh (replace)
-- rather than stack; buffs from different sources stack.
function Battle.buff(
	battle: Battle,
	source: Unit,
	target: Unit,
	stat: string,
	flat: number,
	percent: number,
	seconds: number
)
	if target.dead then
		return
	end
	target.buffs[source.index .. ":" .. stat] = {
		stat = stat,
		flat = flat,
		percent = percent,
		endsTick = battle.tick + Battle.seconds(battle, seconds),
	}
	Battle.emit(battle, {
		kind = "Buff",
		unit = source.index,
		target = target.index,
		stat = stat,
		flat = flat,
		percent = percent,
		duration = seconds,
	})
end

-- Moves a unit to a free cell.
function Battle.relocate(battle: Battle, unit: Unit, column: number, row: number)
	battle.occupied[Battle.cellKey(battle, unit.column, unit.row)] = nil
	battle.occupied[Battle.cellKey(battle, column, row)] = unit
	unit.column = column
	unit.row = row
end

-- Ends expired shields and buffs. Called at the start of every tick.
function Battle.expire(battle: Battle)
	for _, unit in battle.units do
		if not unit.dead then
			if unit.shield > 0 and battle.tick >= unit.shieldEndsTick then
				unit.shield = 0
				Battle.emit(battle, { kind = "ShieldEnd", unit = unit.index })
			end
			for key, buff in unit.buffs do
				if battle.tick >= buff.endsTick then
					unit.buffs[key] = nil
				end
			end
		end
	end
end

return Battle
