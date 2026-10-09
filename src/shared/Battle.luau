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
--
-- Engine pieces added for Overhaul 1 (docs/design/overhaul-1.md):
--   * statuses: buffs and damage over time can carry a status (Battle.Status); a debuff is a buff
--     with a negative percent and a status (Battle.debuff: SLOW, WEAKEN, CURSE)
--   * multiplier stats: DamageDealt, DamageTaken, MagicDamageTaken and HealPower start at 1 and
--     scale damage and healing; CritChance and CritDamage start at the battle's crit rules
--   * hooks: other modules (traits, bonds) listen to battle moments with Battle.addHook
--   * a scheduler for effects that land later (multi-hits, damage when a stun ends, follow-ups)
--   * knockback, summon recall, summons that last until killed, passive auras, attack stacks
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
-- The last six are not in UnitConfig; they start at STAT_DEFAULTS (CritChance at the battle's crit
-- chance) and are changed by percent (multipliers) or flat amounts (crit).
local STAT_FIELDS = table.freeze({
	AD = "attackDamage",
	AP = "abilityPower",
	AttackSpeed = "attacksPerSecond",
	Armor = "armor",
	MR = "magicResist",
	MoveSpeed = "moveSpeed",
	MaxHealth = "maxHealth",
	DamageDealt = "damageDealt", -- multiplies all damage the unit deals
	DamageTaken = "damageTaken", -- multiplies all damage the unit takes
	MagicDamageTaken = "magicDamageTaken", -- multiplies magic damage the unit takes
	HealPower = "healPower", -- multiplies the unit's ability heals and shields
	CritChance = "critChance", -- basic-attack crit chance (0-1)
	CritDamage = "critDamage", -- crit raw damage multiplier
})
Battle.StatFields = STAT_FIELDS

local STAT_DEFAULTS = table.freeze({
	AP = CombatConfig.baseAbilityPower,
	DamageDealt = 1,
	DamageTaken = 1,
	MagicDamageTaken = 1,
	HealPower = 1,
	CritDamage = CombatConfig.critDamage,
})

-- Statuses a buff or a damage over time can carry, so effects can check for them ("bonus against
-- a burning target") and clients can show them. STUN is the unit's stun.
Battle.Status = table.freeze({
	Stun = "STUN",
	Slow = "SLOW", -- attack speed and move speed down
	Weaken = "WEAKEN", -- damage dealt down
	Curse = "CURSE", -- damage dealt down (the Cursed trait's dummy)
	Burn = "BURN", -- damage over time
	Poison = "POISON", -- damage over time
})

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
	expiresTick: number?, -- summons: when it vanishes; nil lasts until killed
	manaPerHit: number?, -- summons: mana its summoner gains for each of its basic attacks
	passive: boolean?, -- never acts (the Cursed trait's dummy)
	flags: { [string]: boolean }, -- per-fight switches (bonds unlock form triggers with them)
	lastCastTick: number?, -- when it last cast (LAST_CASTER_ENEMY)
	casts: number?, -- casts this fight (CAST_CYCLE); set by Abilities.cast
	stacks: number, -- attack stacks (stats.attackStacks): basic attacks on one target build them
	stackTarget: Unit?, -- the target the stacks were built on
	followUp: any?, -- an active onTargetKilled follow-up (Abilities)
	nextAuraTick: number?, -- units with an aura: when it next pulses
	auraCount: number?, -- units with an aura: enemies inside at the last pulse
	untargetableUntilTick: number, -- while above the tick: no one can target or hit it, and it cannot act
	shieldSource: string?, -- the trait that gave the current shield (nil for ability shields)
	items: { string }, -- equipped item ids (ItemCombat applies them; summons carry none)
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
	status: string?, -- Battle.Status (BURN, POISON) or nil
}

-- Something that happens later (Battle.schedule): `run` is called at `tick` unless `owner` died.
export type Scheduled = { tick: number, order: number, owner: Unit, run: () -> () }

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
	scheduled: { Scheduled },
	scheduleCount: number,
	hooks: { [string]: { (...any) -> any } },
	sideState: { { [string]: any } }, -- per side, for traits and bonds
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
		scheduled = {},
		scheduleCount = 0,
		hooks = {},
		sideState = { {}, {} },
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
				flags = {},
				stacks = 0,
				untargetableUntilTick = 0,
				items = if placed.items then table.clone(placed.items) else {},
			}
			-- Units that cast at full attack stacks show their stacks as mana instead (see gainMana).
			if stats.attackStacks and stats.attackStacks.castAtMax then
				unit.mana = 0
			end
			if stats.aura then
				unit.nextAuraTick = Battle.seconds(battle, stats.aura.interval)
			end
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

-- True while `unit` cannot be targeted or hit (Battle.vanish).
function Battle.isUntargetable(battle: Battle, unit: Unit): boolean
	return battle.tick < unit.untargetableUntilTick
end

-- Living units on the other side that can be targeted, in index order. Every selector, area and
-- basic attack finds its enemies here.
function Battle.enemiesOf(battle: Battle, unit: Unit): { Unit }
	local result = {}
	for _, other in battle.units do
		if other.side ~= unit.side and not other.dead and battle.tick >= other.untargetableUntilTick then
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
-- (base + flat bonuses) x (1 + percent bonuses / 100), where the percent part never goes below 0
-- (debuffs can at most cancel a stat out).
-- `name` is a BUFF stat name (Battle.StatFields).
function Battle.stat(battle: Battle, unit: Unit, name: string): number
	local field = STAT_FIELDS[name]
	local base = unit.stats[field]
	if base == nil then
		if name == "CritChance" then
			base = battle.critChance
		else
			base = STAT_DEFAULTS[name] or 0
		end
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
	return (base + flat) * math.max(0, 1 + percent / 100)
end

-- The unit's attack range now (its form's, if the form sets one).
function Battle.range(unit: Unit): number
	return Forms.range(unit.stats, unit.form)
end

-- Lets another module (traits, bonds) react to a battle moment. Hooks run in the order added:
--   damageMultiplier(battle, source, target, damageType, kind) -> number  scales a hit's raw damage
--   attack(battle, attacker, target)          after a basic attack (and its splash) landed
--   cast(battle, caster)                      after an ability's effects applied
--   death(battle, victim, killer)             a unit died (killer: the unit whose hit killed it)
--   takedown(battle, killer, victim)          a board unit was killed by an enemy; `killer` is the
--                                             board unit credited (a summon's kill goes to its
--                                             summoner)
--   damaged(battle, unit, source)             a unit took a hit and survived it
--   shieldBroken(battle, unit)                damage used up a unit's whole shield
--   tick(battle)                              every tick, before units act
function Battle.addHook(battle: Battle, name: string, hook: (...any) -> any)
	battle.hooks[name] = battle.hooks[name] or {}
	table.insert(battle.hooks[name], hook)
end

function Battle.runHooks(battle: Battle, name: string, ...: any)
	local hooks = battle.hooks[name]
	if hooks then
		for _, hook in hooks do
			hook(battle, ...)
		end
	end
end

-- Schedules `run` for `ticks` ticks from now (at least 1). It is dropped if `owner` dies first.
-- Due entries run at the start of the tick (CombatSim.step), in the order they were scheduled.
function Battle.schedule(battle: Battle, ticks: number, owner: Unit, run: () -> ())
	battle.scheduleCount += 1
	table.insert(battle.scheduled, {
		tick = battle.tick + math.max(1, ticks),
		order = battle.scheduleCount,
		owner = owner,
		run = run,
	})
end

-- Runs every scheduled entry that is due, oldest first. Entries scheduled while running wait for a
-- later tick.
function Battle.runScheduled(battle: Battle)
	if #battle.scheduled == 0 then
		return
	end
	local due, waiting = {}, {}
	for _, entry in battle.scheduled do
		table.insert(if entry.tick <= battle.tick then due else waiting, entry)
	end
	if #due == 0 then
		return
	end
	battle.scheduled = waiting
	table.sort(due, function(a, b)
		if a.tick ~= b.tick then
			return a.tick < b.tick
		end
		return a.order < b.order
	end)
	for _, entry in due do
		if not entry.owner.dead then
			entry.run()
		end
	end
end

-- Adds mana (never above max; units without max mana, such as summons, gain none, and units that
-- cast at full attack stacks gain mana only from stacks). Returns the mana actually gained.
local function gainMana(unit: Unit, amount: number): number
	local attackStacks = unit.stats.attackStacks
	if attackStacks and attackStacks.castAtMax then
		return 0
	end
	if unit.maxMana and not unit.dead then
		local before = unit.mana
		unit.mana = math.min(unit.maxMana, unit.mana + amount)
		return unit.mana - before
	end
	return 0
end

-- The raw damage of a hit after damage multipliers: the source's DamageDealt, the target's
-- DamageTaken (and MagicDamageTaken for magic damage), and any damageMultiplier hooks (traits).
local function multipliedRaw(
	battle: Battle,
	source: Unit,
	target: Unit,
	raw: number,
	damageType: string,
	kind: string
): number
	local multiplier = Battle.stat(battle, source, "DamageDealt") * Battle.stat(battle, target, "DamageTaken")
	if damageType == CombatMath.DamageType.Magic then
		multiplier *= Battle.stat(battle, target, "MagicDamageTaken")
	end
	local hooks = battle.hooks.damageMultiplier
	if hooks then
		for _, hook in hooks do
			multiplier *= hook(battle, source, target, damageType, kind)
		end
	end
	return raw * multiplier
end

-- The board unit credited with a summon's actions (itself for board units).
function Battle.creditedUnit(unit: Unit): Unit
	if unit.summoned and unit.summoner then
		return unit.summoner
	end
	return unit
end

-- Handles a unit's death: frees its cell, emits the Death event, then follow-ups, form takedown
-- triggers and the death and takedown hooks.
local function die(battle: Battle, target: Unit, source: Unit)
	target.dead = true
	battle.occupied[Battle.cellKey(battle, target.column, target.row)] = nil
	Battle.emit(battle, { kind = "Death", unit = target.index })
	-- Follow-ups (Abilities, onTargetKilled): a unit whose current target just died repeats part of
	-- its ability on the next tick, while its follow-up window lasts.
	for _, unit in battle.units do
		local followUp = unit.followUp
		if
			followUp
			and not unit.dead
			and unit.target == target
			and battle.tick < followUp.untilTick
			and followUp.remaining > 0
		then
			followUp.remaining -= 1
			Battle.schedule(battle, 1, unit, followUp.run)
		end
	end
	if source.form and not target.summoned and source.side ~= target.side then
		Battle.checkForm(battle, source, Forms.Hook.Takedown)
	end
	Battle.runHooks(battle, "death", target, source)
	if not target.summoned and source.side ~= target.side then
		Battle.runHooks(battle, "takedown", Battle.creditedUnit(source), target)
	end
end

-- Applies one hit: multipliers, resistance, shield, health, mana for both sides, the event and any
-- death. `kind` is "Attack" for a basic attack (the attacker gains mana) or "Damage" for any other
-- hit (abilities, splash, auras, damage over time).
-- `manaCap` limits the mana the target gains from this hit (damage over time and auras use it).
-- `overTime` marks a damage-over-time tick. `tags` are extra fields for the event (splash, aura,
-- execute, ...). Damage events carry their damageType; Attack events are always physical.
--
-- A target whose form has a health pool takes the hit in the pool instead of its health; when the
-- pool runs out, the rest of that hit is discarded and the form's trigger moves it on. Whether
-- shields absorb first and whether damage over time reaches the pool are FormConfig rules.
-- Untargetable units (Battle.vanish) take no damage.
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
	overTime: boolean?,
	tags: { [string]: any }?
): (number, number)
	if target.dead or Battle.isUntargetable(battle, target) then
		return 0, 0
	end
	raw = multipliedRaw(battle, source, target, raw, damageType, kind)
	local armor = Battle.stat(battle, target, "Armor")
	local magicResist = Battle.stat(battle, target, "MR")
	local final = CombatMath.finalDamage(raw, damageType, armor, magicResist)

	local form = target.form
	local pooled = target.formHealth ~= nil
		and target.formHealth > 0
		and (not overTime or Forms.rule(form, "damageOverTimeHitsFormHealth"))
	local absorbed = 0
	local shieldBefore = target.shield
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
	local summonerMana = nil
	if kind == "Attack" then
		gainMana(source, CombatConfig.manaPerAttack)
		-- Summons that feed their summoner (SUMMON manaPerHit).
		if source.manaPerHit and source.summoner and not source.summoner.dead then
			gainMana(source.summoner, source.manaPerHit)
			summonerMana = source.summoner.mana
		end
	end

	local event = {
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
		damageType = if kind == "Attack" then nil else damageType,
		summonerMana = summonerMana,
	}
	for key, value in tags or {} do
		event[key] = value
	end
	Battle.emit(battle, event)

	if shieldBefore > 0 and target.shield <= 0 and absorbed > 0 then
		Battle.runHooks(battle, "shieldBroken", target)
	end
	if target.health <= 0 then
		die(battle, target, source)
	else
		if form then
			Battle.checkForm(battle, target, Forms.Hook.Damaged)
		end
		Battle.runHooks(battle, "damaged", target, source)
	end
	return final, manaGained
end

-- Kills `target` outright (an execute): a TRUE-damage hit for its remaining health and shield,
-- ignoring multipliers and form pools. The event is a Damage event marked `execute`.
function Battle.execute(battle: Battle, source: Unit, target: Unit)
	if target.dead or Battle.isUntargetable(battle, target) then
		return
	end
	local amount = target.health + target.shield
	target.shield = 0
	target.health = 0
	target.formHealth = if target.formHealth then 0 else nil
	Battle.emit(battle, {
		kind = "Damage",
		unit = source.index,
		target = target.index,
		damage = amount,
		health = 0,
		shield = 0,
		mana = source.mana,
		targetMana = target.mana,
		formHealth = target.formHealth,
		damageType = CombatMath.DamageType.True,
		execute = true,
	})
	die(battle, target, source)
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

-- Restores a form's health pool (a rider's horse), capped at its maximum. Does nothing without a
-- pool. The Heal event carries `pool = true`.
function Battle.healFormPool(battle: Battle, source: Unit, target: Unit, amount: number)
	if target.dead or not target.formHealth or not target.maxFormHealth then
		return
	end
	local healed = math.max(0, math.min(target.maxFormHealth - target.formHealth, math.round(amount)))
	target.formHealth += healed
	Battle.emit(battle, {
		kind = "Heal",
		unit = source.index,
		target = target.index,
		amount = healed,
		health = target.health,
		formHealth = target.formHealth,
		pool = true,
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
	target.shieldSource = nil -- set again by trait shields (applyStartBonus)
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
	if target.dead or Battle.isUntargetable(battle, target) then
		return
	end
	target.stunnedUntilTick = math.max(target.stunnedUntilTick, battle.tick + Battle.seconds(battle, seconds))
	Battle.emit(battle, { kind = "Stun", unit = source.index, target = target.index, duration = seconds })
end

-- True if `unit` has `status` (Battle.Status) right now: a stun, a debuff or a damage over time.
function Battle.hasStatus(battle: Battle, unit: Unit, status: string): boolean
	if status == Battle.Status.Stun then
		return battle.tick < unit.stunnedUntilTick
	end
	for _, buff in unit.buffs do
		if buff.status == status and battle.tick < buff.endsTick then
			return true
		end
	end
	for _, dot in battle.dots do
		if dot.target == unit and dot.status == status and not dot.cancelled and battle.tick < dot.endTick then
			return true
		end
	end
	return false
end

-- Makes `unit` untargetable for `seconds` (Battle.isUntargetable): enemies drop it as a target,
-- nothing can hit or stun it, and it does not act. Emits a Vanish event.
function Battle.vanish(battle: Battle, unit: Unit, seconds: number)
	if unit.dead then
		return
	end
	unit.untargetableUntilTick = battle.tick + Battle.seconds(battle, seconds)
	for _, other in battle.units do
		if other.target == unit then
			other.target = nil
		end
	end
	Battle.emit(battle, { kind = "Vanish", unit = unit.index, duration = seconds })
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

-- Options for Battle.buff.
export type BuffOptions = {
	key: string?, -- replaces the default key (source and stat), so unrelated buffs do not refresh each other
	status: string?, -- Battle.Status carried by the buff (debuffs)
	source: string?, -- a trait or bond name, copied to the event (nil for abilities)
	silent: boolean?, -- no Buff event (an aura refreshing an unchanged buff)
}

-- Buffs one stat for `seconds` (math.huge: the rest of the fight; the event then has no duration
-- and `permanent = true`). Buffs from the same source to the same stat refresh (replace) rather
-- than stack; buffs from different sources stack. Negative values are debuffs.
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
	maxStacks: number?,
	options: BuffOptions?
)
	if target.dead then
		return
	end
	local key = (options and options.key) or (source.index .. ":" .. stat)
	if options and options.status and not options.key then
		key = source.index .. ":" .. options.status .. ":" .. stat
	end
	local stacks = 1
	if stackPerCast then
		local existing = target.buffs[key]
		if existing and battle.tick < existing.endsTick then
			stacks = math.min((existing.stacks or 1) + 1, maxStacks or 1)
		end
	end
	local permanent = seconds == math.huge
	target.buffs[key] = {
		stat = stat,
		flat = flat * stacks,
		percent = percent * stacks,
		endsTick = if permanent then math.huge else battle.tick + Battle.seconds(battle, seconds),
		stacks = if stackPerCast then stacks else nil,
		status = options and options.status,
	}
	if not (options and options.silent) then
		Battle.emit(battle, {
			kind = "Buff",
			unit = source.index,
			target = target.index,
			stat = stat,
			flat = flat,
			percent = percent,
			duration = if permanent then nil else seconds,
			permanent = if permanent then true else nil,
			stacks = if stackPerCast then stacks else nil,
			status = options and options.status,
			source = options and options.source,
		})
	end
	if stat == "MaxHealth" then
		refreshMaxHealth(battle, target)
	end
end

-- Removes a buff by key (a bond bonus that ends when its partner dies). Emits nothing.
function Battle.removeBuff(battle: Battle, target: Unit, key: string)
	local buff = target.buffs[key]
	if buff then
		target.buffs[key] = nil
		if buff.stat == "MaxHealth" then
			refreshMaxHealth(battle, target)
		end
	end
end

-- The stats each debuff status lowers by its percent.
local DEBUFF_STATS = table.freeze({
	[Battle.Status.Slow] = { "AttackSpeed", "MoveSpeed" },
	[Battle.Status.Weaken] = { "DamageDealt" },
	[Battle.Status.Curse] = { "DamageDealt" },
})
Battle.DebuffStats = DEBUFF_STATS

-- Applies a debuff (Battle.DebuffStats): each listed stat goes down by `percent` for `seconds`.
-- The same source re-applying the same debuff refreshes it. Untargetable units are unaffected.
function Battle.debuff(
	battle: Battle,
	source: Unit,
	target: Unit,
	status: string,
	percent: number,
	seconds: number,
	traitSource: string?
)
	if target.dead or Battle.isUntargetable(battle, target) then
		return
	end
	for _, stat in DEBUFF_STATS[status] do
		Battle.buff(
			battle,
			source,
			target,
			stat,
			0,
			-percent,
			seconds,
			nil,
			nil,
			{ status = status, source = traitSource }
		)
	end
end

Battle.refreshMaxHealth = refreshMaxHealth

-- Gives `unit` mana outside a hit (a bond's reward) and emits a Mana event with its new mana.
function Battle.giveMana(battle: Battle, unit: Unit, amount: number)
	if gainMana(unit, amount) > 0 then
		Battle.emit(battle, { kind = "Mana", unit = unit.index, mana = unit.mana })
	end
end

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
	-- Starting mana (Arcane), before the first tick, so the unit summary shows it.
	if bonus.mana and bonus.mana > 0 then
		gainMana(unit, bonus.mana)
	end
	for _, shield in bonus.shields do
		local before = #battle.events
		local amount = CombatMath.scaleByAbilityPower(shield.amount, Battle.stat(battle, unit, "AP"))
		Battle.shield(battle, unit, unit, amount, shield.duration)
		if #battle.events > before then
			battle.events[#battle.events].source = shield.source
			unit.shieldSource = shield.source
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

-- Creates one summon for `summoner` on the free cell nearest it (or nearest `spec.near`, a
-- { column, row }), or returns nil (without error) when there is no free cell or the side already
-- has CombatConfig.maxEntitiesPerSide living units.
-- `spec` holds absolute values: health, attackDamage, armor, magicResist, attacksPerSecond, range,
-- moveSpeed and duration (seconds; nil: it lasts until killed or recalled). Optional: manaPerHit
-- (mana the summoner gains per basic attack of the summon), passive (it never acts: a dummy).
function Battle.summon(battle: Battle, summoner: Unit, spec): Unit?
	if Battle.livingCount(battle, summoner.side) >= CombatConfig.maxEntitiesPerSide then
		return nil
	end
	local nearColumn = if spec.near then spec.near[1] else summoner.column
	local nearRow = if spec.near then spec.near[2] else summoner.row
	local column, row = nearestFreeCell(battle, nearColumn, nearRow)
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
		expiresTick = if spec.duration then battle.tick + Battle.seconds(battle, spec.duration) else nil,
		manaPerHit = spec.manaPerHit,
		passive = spec.passive,
		flags = {},
		stacks = 0,
		untargetableUntilTick = 0,
		items = {},
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
		passive = spec.passive,
		source = spec.source, -- a trait name for trait summons (the Cursed dummy)
	})
	return unit
end

-- Living summons made by `summoner`.
function Battle.summonsOf(battle: Battle, summoner: Unit): { Unit }
	local result = {}
	for _, unit in battle.units do
		if unit.summoned and unit.summoner == summoner and not unit.dead then
			table.insert(result, unit)
		end
	end
	return result
end

-- Recalls (removes) every living summon of `summoner`; each gets a SummonEnd event with
-- `recalled = true`. Returns how many were recalled.
function Battle.recall(battle: Battle, summoner: Unit): number
	local summons = Battle.summonsOf(battle, summoner)
	for _, unit in summons do
		unit.dead = true
		battle.occupied[Battle.cellKey(battle, unit.column, unit.row)] = nil
		Battle.emit(battle, { kind = "SummonEnd", unit = unit.index, recalled = true })
	end
	return #summons
end

-- Knocks `target` one hex straight away from `source`, if that hex is on the field and free.
-- "Straight away" is the neighboring hex one step farther from the source whose direction best
-- matches the source-to-target direction (ties: the first neighbor in HexGrid order). Returns true
-- if it moved; emits a Knockback event.
function Battle.knockback(battle: Battle, source: Unit, target: Unit): boolean
	if target.dead or Battle.isUntargetable(battle, target) then
		return false
	end
	local distance = Battle.distance(source, target)
	if distance == 0 then
		return false
	end
	local sx, sy = HexGrid.point(source.column, source.row)
	local tx, ty = HexGrid.point(target.column, target.row)
	local dx, dy = tx - sx, ty - sy
	local bestColumn, bestRow, bestScore = nil, nil, -math.huge
	for _, cell in HexGrid.neighbors(target.column, target.row) do
		local column, row = cell[1], cell[2]
		if HexGrid.distance(source.column, source.row, column, row) == distance + 1 then
			local cx, cy = HexGrid.point(column, row)
			local score = (cx - tx) * dx + (cy - ty) * dy
			if score > bestScore + 1e-9 then
				bestColumn, bestRow, bestScore = column, row, score
			end
		end
	end
	if not bestColumn or not bestRow or not Battle.isFree(battle, bestColumn, bestRow) then
		return false
	end
	Battle.relocate(battle, target, bestColumn, bestRow)
	Battle.emit(battle, {
		kind = "Knockback",
		unit = source.index,
		target = target.index,
		column = bestColumn,
		row = bestRow,
	})
	return true
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
-- stronger tick, and resets the mana cap; the next tick stays where it was. `status` (BURN,
-- POISON) marks the application for Battle.hasStatus.
function Battle.damageOverTime(
	battle: Battle,
	source: Unit,
	target: Unit,
	key: string,
	amount: number,
	damageType: string,
	interval: number,
	seconds: number,
	status: string?
)
	if target.dead or Battle.isUntargetable(battle, target) then
		return
	end
	local endTick = battle.tick + Battle.seconds(battle, seconds)
	for _, dot in battle.dots do
		if dot.key == key and dot.target == target and battle.tick < dot.endTick and not dot.cancelled then
			dot.endTick = endTick
			dot.amount = math.max(dot.amount, amount)
			dot.manaLeft = CombatConfig.dotManaCap
			Battle.emit(battle, {
				kind = "Dot",
				unit = source.index,
				target = target.index,
				refreshed = true,
				status = status,
			})
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
		status = status,
	})
	Battle.emit(battle, {
		kind = "Dot",
		unit = source.index,
		target = target.index,
		damageType = damageType,
		status = status,
	})
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

-- A per-star value: a list indexed by star level, or a constant.
local function perStar(value: any, starLevel: number): any
	if type(value) == "table" then
		return value[starLevel]
	end
	return value
end

-- Passive auras (a unit type's `aura`; see Abilities.validateUnit): every `interval` seconds all
-- fight, each living enemy within `radius` of the unit takes `amount` damage (magic scales with the
-- unit's ability power; the victim gains at most CombatConfig.auraManaCap mana per pulse), and each
-- `buffs` entry gives the unit `flatPerEnemy` of its stat per enemy inside, until the next pulse.
-- Pulses keep going while the unit is stunned. Aura hits are Damage events marked dot and aura.
function Battle.tickAuras(battle: Battle)
	for _, unit in battle.units do
		local aura = unit.stats.aura
		if aura and not unit.dead and unit.nextAuraTick and battle.tick >= unit.nextAuraTick then
			local intervalTicks = math.max(1, Battle.seconds(battle, aura.interval))
			unit.nextAuraTick += intervalTicks
			local victims = {}
			for _, enemy in Battle.enemiesOf(battle, unit) do
				if Battle.distance(unit, enemy) <= aura.radius then
					table.insert(victims, enemy)
				end
			end
			local amount = perStar(aura.amount, unit.starLevel)
			if amount and amount > 0 then
				if aura.damageType == CombatMath.DamageType.Magic then
					amount = CombatMath.scaleByAbilityPower(amount, Battle.stat(battle, unit, "AP"))
				end
				for _, enemy in victims do
					Battle.damage(
						battle,
						unit,
						enemy,
						amount,
						aura.damageType,
						"Damage",
						nil,
						CombatConfig.auraManaCap,
						true,
						{ dot = true, aura = true }
					)
				end
			end
			local changed = unit.auraCount ~= #victims
			unit.auraCount = #victims
			for _, buff in aura.buffs or {} do
				local flat = (perStar(buff.flatPerEnemy, unit.starLevel) or 0) * #victims
				-- Lasts a little past the next pulse, which refreshes it.
				Battle.buff(
					battle,
					unit,
					unit,
					buff.stat,
					flat,
					0,
					aura.interval * 1.5,
					nil,
					nil,
					{ key = "aura:" .. buff.stat, silent = not changed }
				)
			end
		end
	end
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
