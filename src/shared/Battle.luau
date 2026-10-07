-- State of one fight and the primitive actions everything else uses: damage (the only place
-- damage is applied), heals, shields, stuns, buffs, relocation, pulls, summons and damage over
-- time. Each primitive records an event for client playback. CombatSim runs the tick loop;
-- Abilities composes these primitives.
--
-- Summons are units with `summoned` set: they attack and move, never gain mana or cast, get no
-- trait bonuses, vanish when they die or expire, and are left out of the timeout health
-- percentage and surviving-unit counts (see CombatSim). Their damage events carry their own index;
-- `summoner` links them to the unit that made them.
--
-- Units whose type lists `forms` start in the first form and change form when its trigger fires
-- (Battle.checkForm; data rules in Forms). While a form has a health pool, hits go to the pool
-- instead of the unit's health (Battle.damage). Units without forms never touch any of this.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local CombatConfig = if script then require(script.Parent.CombatConfig) else require("./CombatConfig")
local CombatMath = if script then require(script.Parent.CombatMath) else require("./CombatMath")
local Forms = if script then require(script.Parent.Forms) else require("./Forms")
local HexGrid = if script then require(script.Parent.HexGrid) else require("./HexGrid")
local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")
local StarLevel = if script then require(script.Parent.StarLevel) else require("./StarLevel")

local Battle = {}

-- Stats a BUFF can change, mapped to the unit stat field they modify. MaxHealth is special: it
-- changes `maxHealth` directly (see refreshMaxHealth) rather than being read through Battle.stat.
local STAT_FIELDS = table.freeze({
	AD = "attackDamage",
	AP = "abilityPower",
	AttackSpeed = "attacksPerSecond",
	Armor = "armor",
	MR = "magicResist",
	MoveSpeed = "moveSpeed",
	MaxHealth = "maxHealth",
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
	baseMaxHealth: number, -- max health at fight start; MaxHealth bonuses are a percentage of this
	mana: number,
	maxMana: number?, -- nil: the unit never casts
	shield: number,
	shieldEndsTick: number,
	stunnedUntilTick: number,
	castEndsTick: number,
	buffs: { [string]: { stat: string, flat: number, percent: number, endsTick: number, stacks: number? } },
	attackCooldown: number,
	moveCooldown: number,
	target: Unit?,
	dead: boolean,
	summoned: boolean?, -- true for summons
	summoner: Unit?, -- summons: the unit that made it
	expiresTick: number?, -- summons: when it vanishes
	-- Forms (units whose type lists `forms` only; all nil otherwise):
	form: any?, -- the current form (Forms data)
	formIndex: number?,
	formHealth: number?, -- the current form's health pool, if it has one
	maxFormHealth: number?,
	formUses: { [number]: number }?, -- times each form's trigger has fired this fight
}

-- A running DAMAGE_OVER_TIME application on one victim.
export type Dot = {
	key: string, -- source, ability and victim; a new application with the same key refreshes it
	source: Unit,
	target: Unit,
	amount: number, -- raw damage per tick
	damageType: string,
	intervalTicks: number,
	nextTick: number,
	endTick: number,
	manaLeft: number, -- mana the victim can still gain from this application
	cancelled: boolean?, -- ended early by a form change (FormConfig.rules.statusEffectsCarryThrough)
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
	dots: { Dot },
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
		dots = {},
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
				baseMaxHealth = stats.health,
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
			if stats.forms then
				unit.formUses = {}
				Battle.enterForm(battle, unit, 1, nil, true)
			end
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

-- A stat with active buffs and the current form's change applied:
-- (base + flat bonuses) x (1 + percent bonuses / 100).
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
	if unit.form then
		local formFlat, formPercent = Forms.modifier(unit.form, name)
		flat += formFlat
		percent += formPercent
	end
	return (base + flat) * (1 + percent / 100)
end

-- Adds mana (never above max; units without max mana, such as summons, gain none). Returns the
-- mana actually gained.
local function gainMana(unit: Unit, amount: number): number
	if unit.maxMana and not unit.dead then
		local before = unit.mana
		unit.mana = math.min(unit.maxMana, unit.mana + amount)
		return unit.mana - before
	end
	return 0
end

-- Applies one hit: resistance, shield, health, mana for both sides, the event and any death.
-- `kind` is "Attack" for a basic attack (the attacker gains mana) or "Damage" for ability damage.
-- `manaCap` limits the mana the target gains from this hit (damage over time uses it).
-- `overTime` marks a damage-over-time tick.
--
-- A target whose form has a health pool takes the hit in the pool instead of its health; when the
-- pool runs out, the rest of that hit is discarded and the form's trigger moves it on. Whether
-- shields absorb first and whether damage over time reaches the pool are FormConfig rules.
-- Returns the final damage after resistance and the mana the target gained.
function Battle.damage(
	battle: Battle,
	source: Unit,
	target: Unit,
	raw: number,
	damageType: string,
	kind: string,
	crit: boolean?,
	manaCap: number?,
	overTime: boolean?
): (number, number)
	if target.dead then
		return 0, 0
	end
	local armor = Battle.stat(battle, target, "Armor")
	local magicResist = Battle.stat(battle, target, "MR")
	local final = CombatMath.finalDamage(raw, damageType, armor, magicResist)

	local form = target.form
	local pooled = target.formHealth ~= nil
		and target.formHealth > 0
		and (not overTime or Forms.rule(form, "damageOverTimeHitsFormHealth"))
	local absorbed = 0
	if not pooled or Forms.rule(form, "shieldsAbsorbBeforeFormHealth") then
		absorbed = math.min(target.shield, final)
		target.shield -= absorbed
	end
	local healthLost, poolLost = 0, 0
	if pooled then
		poolLost = math.min(target.formHealth, final - absorbed)
		target.formHealth -= poolLost
	else
		healthLost = math.min(target.health, final - absorbed)
		target.health -= healthLost
	end
	local lost = healthLost
	if poolLost > 0 and Forms.rule(form, "formHealthDamageGivesMana") then
		lost += poolLost
	end
	local mana = CombatMath.manaFromDamage(lost, target.maxHealth)
	if manaCap then
		mana = math.min(mana, manaCap)
	end
	local manaGained = gainMana(target, mana)
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
		formHealth = target.formHealth,
	})

	if target.health <= 0 then
		target.dead = true
		battle.occupied[Battle.cellKey(battle, target.column, target.row)] = nil
		Battle.emit(battle, { kind = "Death", unit = target.index })
		if source.form and not target.summoned and source.side ~= target.side then
			Battle.checkForm(battle, source, Forms.Hook.Takedown)
		end
	elseif form then
		Battle.checkForm(battle, target, Forms.Hook.Damaged)
	end
	return final, manaGained
end

-- Restores health, capped at max health. Amounts are rounded to whole numbers. Form health pools
-- are not healed unless FormConfig.rules.healingRestoresFormHealth allows it: then healing beyond
-- the unit's missing health refills the pool.
function Battle.heal(battle: Battle, source: Unit, target: Unit, amount: number)
	if target.dead then
		return
	end
	local rounded = math.round(amount)
	local healed = math.min(target.maxHealth - target.health, rounded)
	target.health += healed
	if target.formHealth and target.maxFormHealth and Forms.rule(target.form, "healingRestoresFormHealth") then
		local refill = math.max(0, math.min(target.maxFormHealth - target.formHealth, rounded - healed))
		target.formHealth += refill
		healed += refill
	end
	Battle.emit(battle, {
		kind = "Heal",
		unit = source.index,
		target = target.index,
		amount = healed,
		health = target.health,
		formHealth = target.formHealth,
	})
end

-- Puts `unit` into its form `index`: the form's stats and ability apply from now on, and a form
-- with a health pool starts it at `healthPercent` (100 if nil) of full. Emits a Form event unless
-- `silent` (the starting form, which the fight's unit summary reports instead). When the form being
-- left does not let status effects carry through, the unit's stun and damage over time end.
function Battle.enterForm(battle: Battle, unit: Unit, index: number, healthPercent: number?, silent: boolean?)
	local form = unit.stats.forms[index]
	local previous = unit.form
	unit.form = form
	unit.formIndex = index
	unit.ability = form.ability or unit.stats.ability
	if form.health then
		local full = StarLevel.scaleHealth(form.health, unit.starLevel)
		unit.maxFormHealth = full
		unit.formHealth = math.max(1, math.round(full * (healthPercent or 100) / 100))
	else
		unit.maxFormHealth = nil
		unit.formHealth = nil
	end
	local cleansed = false
	if previous and not Forms.rule(previous, "statusEffectsCarryThrough") then
		unit.stunnedUntilTick = math.min(unit.stunnedUntilTick, battle.tick)
		for _, dot in battle.dots do
			if dot.target == unit then
				dot.cancelled = true
			end
		end
		cleansed = true
	end
	if not silent then
		Battle.emit(battle, {
			kind = "Form",
			unit = unit.index,
			form = form.name,
			formIndex = index,
			formHealth = unit.formHealth,
			maxFormHealth = unit.maxFormHealth,
			health = unit.health,
			cleansed = if cleansed then true else nil,
		})
	end
end

-- Asks `unit`'s current form whether its trigger fires at `hook` (Forms.Hook), and if so moves the
-- unit to the trigger's destination form. A trigger with maxUses stops firing after that many times
-- in the fight.
function Battle.checkForm(battle: Battle, unit: Unit, hook: string)
	local form = unit.form
	if not form or unit.dead or not Forms.fires(form, unit, hook) then
		return
	end
	local trigger = form.trigger
	local uses = unit.formUses or {}
	local used = uses[unit.formIndex] or 0
	if trigger.maxUses and used >= trigger.maxUses then
		return
	end
	local destination = Forms.destination(unit.stats.forms, unit.formIndex, trigger)
	if not destination then
		return
	end
	uses[unit.formIndex] = used + 1
	unit.formUses = uses
	Battle.enterForm(battle, unit, destination, trigger.healthPercent)
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

-- Recomputes a unit's max health from its MaxHealth buffs: base x (1 + percents / 100) + flats,
-- rounded. A rise also raises current health by the same amount; a fall only caps current health.
local function refreshMaxHealth(battle: Battle, unit: Unit)
	local flat, percent = 0, 0
	for _, buff in unit.buffs do
		if buff.stat == "MaxHealth" and battle.tick < buff.endsTick then
			flat += buff.flat
			percent += buff.percent
		end
	end
	local newMax = math.round(unit.baseMaxHealth * (1 + percent / 100) + flat)
	local change = newMax - unit.maxHealth
	if change == 0 then
		return
	end
	unit.maxHealth = newMax
	unit.health = if change > 0 then unit.health + change else math.min(unit.health, newMax)
	Battle.emit(battle, { kind = "MaxHealth", unit = unit.index, maxHealth = newMax, health = unit.health })
end

-- Buffs one stat for `seconds`. Buffs from the same source to the same stat refresh (replace)
-- rather than stack; buffs from different sources stack.
-- With `stackPerCast`, each application instead adds one stack of `flat`/`percent` up to
-- `maxStacks`; every application (including one at the cap) refreshes the duration of all stacks.
function Battle.buff(
	battle: Battle,
	source: Unit,
	target: Unit,
	stat: string,
	flat: number,
	percent: number,
	seconds: number,
	stackPerCast: boolean?,
	maxStacks: number?
)
	if target.dead then
		return
	end
	local key = source.index .. ":" .. stat
	local stacks = 1
	if stackPerCast then
		local existing = target.buffs[key]
		if existing and battle.tick < existing.endsTick then
			stacks = math.min((existing.stacks or 1) + 1, maxStacks or 1)
		end
	end
	target.buffs[key] = {
		stat = stat,
		flat = flat * stacks,
		percent = percent * stacks,
		endsTick = battle.tick + Battle.seconds(battle, seconds),
		stacks = if stackPerCast then stacks else nil,
	}
	Battle.emit(battle, {
		kind = "Buff",
		unit = source.index,
		target = target.index,
		stat = stat,
		flat = flat,
		percent = percent,
		duration = seconds,
		stacks = if stackPerCast then stacks else nil,
	})
	if stat == "MaxHealth" then
		refreshMaxHealth(battle, target)
	end
end

Battle.refreshMaxHealth = refreshMaxHealth

-- Applies a combat-start bonus (Traits.Bonus) that lasts the whole fight. Stat changes become one
-- permanent buff per stat, separate from ability buffs and stacking with them (Battle.stat adds
-- every buff's flat and percent changes). Shields come after, so they scale with the unit's ability
-- power including its bonus, like any other shield; their Shield events carry `source`.
function Battle.applyStartBonus(battle: Battle, unit: Unit, bonus)
	local statNames = {}
	for stat in bonus.stats do
		table.insert(statNames, stat)
	end
	table.sort(statNames)
	for _, stat in statNames do
		local change = bonus.stats[stat]
		unit.buffs["start:" .. stat] = {
			stat = stat,
			flat = change.flat,
			percent = change.percent,
			endsTick = math.huge,
		}
	end
	if bonus.stats.MaxHealth then
		refreshMaxHealth(battle, unit)
	end
	for _, shield in bonus.shields do
		local before = #battle.events
		local amount = CombatMath.scaleByAbilityPower(shield.amount, Battle.stat(battle, unit, "AP"))
		Battle.shield(battle, unit, unit, amount, shield.duration)
		if #battle.events > before then
			battle.events[#battle.events].source = shield.source
		end
	end
end

-- Moves a unit to a free cell.
function Battle.relocate(battle: Battle, unit: Unit, column: number, row: number)
	battle.occupied[Battle.cellKey(battle, unit.column, unit.row)] = nil
	battle.occupied[Battle.cellKey(battle, column, row)] = unit
	unit.column = column
	unit.row = row
end

-- Living units (board units and summons) on one side.
function Battle.livingCount(battle: Battle, side: number): number
	local count = 0
	for _, unit in battle.units do
		if unit.side == side and not unit.dead then
			count += 1
		end
	end
	return count
end

-- The free cell nearest `column`, `row` (by hex distance; ties go to the first cell in field order:
-- row, then column). `filter` can restrict the candidates. Returns nil if there is none.
local function nearestFreeCell(
	battle: Battle,
	column: number,
	row: number,
	filter: ((number, number) -> boolean)?
): (number?, number?)
	local bestColumn, bestRow, bestDistance = nil, nil, math.huge
	for r = 1, battle.fieldRows do
		for c = 1, battle.columns do
			if Battle.isFree(battle, c, r) and (filter == nil or filter(c, r)) then
				local distance = HexGrid.distance(column, row, c, r)
				if distance < bestDistance then
					bestColumn, bestRow, bestDistance = c, r, distance
				end
			end
		end
	end
	return bestColumn, bestRow
end

-- Creates one summon for `summoner` on the free cell nearest it, or returns nil (without error)
-- when there is no free cell or the side already has CombatConfig.maxEntitiesPerSide living units.
-- `spec` holds absolute values: health, attackDamage, armor, magicResist, attacksPerSecond, range,
-- moveSpeed and duration (seconds).
function Battle.summon(battle: Battle, summoner: Unit, spec): Unit?
	if Battle.livingCount(battle, summoner.side) >= CombatConfig.maxEntitiesPerSide then
		return nil
	end
	local column, row = nearestFreeCell(battle, summoner.column, summoner.row)
	if not column or not row then
		return nil
	end
	local health = math.max(1, math.round(spec.health))
	local index = #battle.units + 1
	local unit = {
		index = index,
		side = summoner.side,
		id = summoner.id .. "~" .. index,
		unitType = summoner.unitType,
		starLevel = summoner.starLevel,
		stats = {
			health = health,
			attackDamage = spec.attackDamage,
			armor = spec.armor,
			magicResist = spec.magicResist,
			attacksPerSecond = spec.attacksPerSecond,
			range = spec.range,
			moveSpeed = spec.moveSpeed,
		},
		ability = nil,
		column = column,
		row = row,
		health = health,
		maxHealth = health,
		baseMaxHealth = health,
		mana = 0,
		maxMana = nil,
		shield = 0,
		shieldEndsTick = 0,
		stunnedUntilTick = 0,
		castEndsTick = 0,
		buffs = {},
		attackCooldown = 0,
		moveCooldown = 0,
		target = nil,
		dead = false,
		summoned = true,
		summoner = summoner,
		expiresTick = battle.tick + Battle.seconds(battle, spec.duration),
	}
	table.insert(battle.units, unit)
	battle.occupied[Battle.cellKey(battle, column, row)] = unit
	Battle.emit(battle, {
		kind = "Summon",
		unit = summoner.index,
		summon = index,
		column = column,
		row = row,
		maxHealth = health,
		range = spec.range,
		moveSpeed = spec.moveSpeed,
		duration = spec.duration,
	})
	return unit
end

-- Pulls `target` to the free cell adjacent to `caster` nearest the target's current cell. If the
-- target is already adjacent it stays; if no adjacent cell is free it does not move. Returns true
-- if it moved.
function Battle.pull(battle: Battle, caster: Unit, target: Unit): boolean
	if target.dead or Battle.distance(caster, target) <= 1 then
		return false
	end
	local column, row = nearestFreeCell(battle, target.column, target.row, function(c, r)
		return HexGrid.distance(caster.column, caster.row, c, r) == 1
	end)
	if not column or not row then
		return false
	end
	Battle.relocate(battle, target, column, row)
	Battle.emit(battle, { kind = "Pull", unit = caster.index, target = target.index, column = column, row = row })
	return true
end

-- Starts damage over time on `target`: `amount` raw damage of `damageType` every `interval`
-- seconds for `seconds`, the first tick one interval from now. Applications from different
-- sources (or abilities) stack. Re-applying the same `key` refreshes the duration, keeps the
-- stronger tick, and resets the mana cap; the next tick stays where it was.
function Battle.damageOverTime(
	battle: Battle,
	source: Unit,
	target: Unit,
	key: string,
	amount: number,
	damageType: string,
	interval: number,
	seconds: number
)
	if target.dead then
		return
	end
	local endTick = battle.tick + Battle.seconds(battle, seconds)
	for _, dot in battle.dots do
		if dot.key == key and dot.target == target and battle.tick < dot.endTick and not dot.cancelled then
			dot.endTick = endTick
			dot.amount = math.max(dot.amount, amount)
			dot.manaLeft = CombatConfig.dotManaCap
			Battle.emit(battle, { kind = "Dot", unit = source.index, target = target.index, refreshed = true })
			return
		end
	end
	local intervalTicks = math.max(1, Battle.seconds(battle, interval))
	table.insert(battle.dots, {
		key = key,
		source = source,
		target = target,
		amount = amount,
		damageType = damageType,
		intervalTicks = intervalTicks,
		nextTick = battle.tick + intervalTicks,
		endTick = endTick,
		manaLeft = CombatConfig.dotManaCap,
	})
	Battle.emit(battle, { kind = "Dot", unit = source.index, target = target.index, damageType = damageType })
end

-- Deals every damage-over-time tick that is due, in application order, and drops finished ones.
-- Tick damage events are "Damage" events marked `dot = true`, with their `damageType`.
function Battle.tickDots(battle: Battle)
	if #battle.dots == 0 then
		return
	end
	local remaining = {}
	for _, dot in table.clone(battle.dots) do
		local due = battle.tick >= dot.nextTick and dot.nextTick <= dot.endTick
		if due and not dot.cancelled and not dot.target.dead then
			local before = #battle.events
			local _, gained = Battle.damage(
				battle,
				dot.source,
				dot.target,
				dot.amount,
				dot.damageType,
				"Damage",
				nil,
				dot.manaLeft,
				true
			)
			dot.manaLeft -= gained
			local event = battle.events[before + 1]
			if event then
				event.dot = true
				event.damageType = dot.damageType
			end
			dot.nextTick += dot.intervalTicks
		end
		if not dot.cancelled and not dot.target.dead and dot.nextTick <= dot.endTick then
			table.insert(remaining, dot)
		end
	end
	battle.dots = remaining
end

-- Ends expired shields, buffs and summons. Called at the start of every tick.
function Battle.expire(battle: Battle)
	for _, unit in battle.units do
		if not unit.dead then
			if unit.summoned and unit.expiresTick and battle.tick >= unit.expiresTick then
				unit.dead = true
				battle.occupied[Battle.cellKey(battle, unit.column, unit.row)] = nil
				Battle.emit(battle, { kind = "SummonEnd", unit = unit.index })
			else
				if unit.shield > 0 and battle.tick >= unit.shieldEndsTick then
					unit.shield = 0
					Battle.emit(battle, { kind = "ShieldEnd", unit = unit.index })
				end
				local maxHealthChanged = false
				for key, buff in unit.buffs do
					if battle.tick >= buff.endsTick then
						unit.buffs[key] = nil
						maxHealthChanged = maxHealthChanged or buff.stat == "MaxHealth"
					end
				end
				if maxHealthChanged then
					refreshMaxHealth(battle, unit)
				end
			end
		end
	end
end

return Battle
