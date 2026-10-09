-- Deterministic combat simulation. Takes two boards and a seed, advances in fixed ticks, and
-- returns the units' starting state, a list of events, and the winner.
-- Pure Luau: no Roblox APIs, no task library, no wall-clock time. The same input always gives
-- the same output (crits and ties use the seeded random generator).
--
-- Field coordinates: side 1 keeps its own board coordinates (rows 1..rows). Side 2's board is
-- rotated half a turn into rows rows+1..rows*2, so both sides face each other.
--
-- The fight ends when one side has no units left. If both sides still have units at maxTicks, the
-- side with the higher remaining health percentage (sum of current health / sum of max health over
-- every unit that entered combat) wins; within `timeoutDrawMargin` of each other it is a draw.
--
-- Per tick, expired shields and buffs end, scheduled effects land, damage over time and auras
-- tick, then each living unit acts in a seeded random order:
--   0. A stunned, casting, untargetable (vanished) or passive unit does nothing.
--   1. With full mana and an ability, it casts (see Abilities).
--   2. Otherwise it keeps its target if alive, targetable and in range (its form's range, if the
--      form sets one), else targets the nearest enemy.
--   3. It attacks if the target is in range and its attack cooldown is ready (crits possible, at
--      its CritChance and CritDamage). Attack stacks build first; a form's splash and the attack
--      hooks (traits) follow the hit.
--   4. Otherwise it steps one cell along a shortest path of free cells toward a cell in range,
--      once its move cooldown is ready. Units never share a cell.
-- All damage goes through Battle.damage; the formulas are in CombatMath.

local Abilities = if script then require(script.Parent.Abilities) else require("./Abilities")
local Battle = if script then require(script.Parent.Battle) else require("./Battle")
local CombatConfig = if script then require(script.Parent.CombatConfig) else require("./CombatConfig")
local CombatMath = if script then require(script.Parent.CombatMath) else require("./CombatMath")
local HexGrid = if script then require(script.Parent.HexGrid) else require("./HexGrid")
local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")
local ItemCombat = if script then require(script.Parent.ItemCombat) else require("./ItemCombat")
local TraitCombat = if script then require(script.Parent.TraitCombat) else require("./TraitCombat")

local CombatSim = {}

-- A unit placed on a board, in that board's own coordinates.
export type PlacedUnit = {
	id: string,
	unitType: string,
	starLevel: number?, -- 1 if omitted
	column: number,
	row: number,
	items: { string }?, -- equipped item ids (ItemConfig); applied by ItemCombat at combat start
}

export type Params = {
	boards: { { PlacedUnit } }, -- exactly two: side 1 and side 2
	columns: number,
	rows: number, -- rows per side; the field has rows * 2
	unitTypes: { [string]: any }, -- UnitConfig entries; armor, magic resist, AP and mana are optional
	ticksPerSecond: number,
	maxTicks: number,
	timeoutDrawMargin: number?, -- see the header; 0 if omitted
	critChance: number?, -- overrides CombatConfig.critChance (tests use 0)
	seed: number,
	-- Combat-start bonuses (traits; see Traits.bonuses), per side, by unit id. Applied before the
	-- first tick and kept for the whole fight. Omitted or empty: no bonuses.
	startBonuses: { { [string]: any } }?,
	-- Trait and bond effects during the fight (Traits.fightSetup per side; TraitCombat). Omitted:
	-- none. Traits.combatParams builds both this and startBonuses.
	traits: { any }?,
}

-- Starting state of a unit, in field coordinates. `index` identifies the unit in events.
export type UnitSummary = {
	index: number,
	side: number,
	id: string,
	unitType: string,
	starLevel: number,
	column: number,
	row: number,
	maxHealth: number,
	mana: number,
	maxMana: number?,
	items: { string }, -- equipped item ids
	-- Units with forms only: the starting form and its health pool (nil without a pool).
	form: string?,
	formIndex: number?,
	formHealth: number?,
	maxFormHealth: number?,
}

-- Events, each with `tick`, `kind` and the acting `unit`:
--   Move      column, row
--   Dash      column, row
--   Attack    target, damage, health, shield (target's, after the hit), mana (attacker's),
--             targetMana, crit (true or nil), formHealth (the target's form health pool after the
--             hit; nil when it has none), summonerMana (a summon with manaPerHit: its summoner's
--             mana after the hit). Always physical.
--   Damage    same fields as Attack for every other hit (never crits), plus damageType. Marked:
--             dot = true for damage-over-time ticks and aura pulses (aura = true too; `unit` is the
--             source), splash = true for a form's attack splash, stunEnd = true for damage when a
--             stun ends, execute = true for an execute
--   Cast      ability (name); the caster's mana is now 0
--   FollowUp  ability (name): an onTargetKilled follow-up starts; its effects' events follow
--   Heal      target, amount, health, formHealth (as in Attack); pool = true for a form-pool heal
--   Shield    target, shield (new shield), duration (seconds), source (trait name, for shields
--             given at combat start by a trait; nil for ability shields)
--   ShieldEnd the unit's shield expired
--   Stun      target, duration (seconds)
--   Buff      target, stat, flat, percent (per stack; negative for debuffs), duration (seconds; nil
--             with permanent = true), stacks (stacking buffs), status (debuffs: Battle.Status),
--             source (trait or bond name, for their buffs)
--   Death     the unit died
--   MaxHealth the unit's maxHealth changed (MaxHealth bonus); health is its current health
--   Area      shape (CIRCLE, LINE, CONE), column, row (the center), radius (CIRCLE), cells (LINE
--             and CONE: the covered { column, row } cells), fromColumn, fromRow (LINE and CONE: the
--             caster's cell); an AREA_DAMAGE's hits follow
--   AreaStun  column, row, radius: an AREA_STUN centered there (Stun events follow per enemy)
--   Summon    summon (new unit index), column, row, maxHealth, range, moveSpeed, duration (nil:
--             until killed), passive (a dummy that never acts), source (trait name for trait
--             summons); the new unit is a summon on `unit`'s side and appears in no UnitSummary
--   SummonEnd the summon expired and vanished; recalled = true when its summoner recalled it
--   Pull      target, column, row: the target was pulled next to `unit`
--   Knockback target, column, row: the target was knocked one hex away from `unit`
--   Bounce    from, target (unit indexes): a bounce flies from one enemy to the next
--   Dot       target, damageType, status (BURN, POISON or nil), refreshed (true when an existing
--             application was refreshed)
--   Copy      target, ability (name of the copied ability); the copied effects' events follow
--   Form      the unit changed form (Battle.enterForm): form (name), formIndex, formHealth and
--             maxFormHealth (the new form's pool; nil without one), health (the unit's own),
--             cleansed (true when the change ended its stun and damage over time)
--   Vanish    duration: the unit is untargetable and does not act (Battle.vanish)
--   Immune    the unit ignored a stun (an item)
--   Events caused by an item (heals, shields, damage, damage over time ticks) carry `item`.
--   Trait events (TraitCombat): Mark (target), Meter (trait, value, max, phase), TraitSummon is a
--             Summon with source
export type Event = { [string]: any }

export type Result = {
	winner: number?, -- 1 or 2, or nil for a draw
	timedOut: boolean, -- true if the fight reached maxTicks
	survivors: { number }, -- living units per side at the end
	healthPercent: { number }, -- remaining health fraction (0-1) per side at the end
	endTick: number,
	ticksPerSecond: number,
	seed: number,
	units: { UnitSummary },
	events: { Event },
	-- What each side's traits did (TraitCombat.SideResult): Crew `gold` (paid after PvP fights),
	-- takedowns, marks, meter fills, vanishes, executes.
	traitResults: { any },
}

local function findNearestEnemy(battle, unit)
	return Battle.pickBest(battle, Battle.enemiesOf(battle, unit), function(enemy)
		return -Battle.distance(unit, enemy)
	end)
end

-- Breadth-first search over free cells for the shortest path to any cell within attack range of
-- the target. Returns the first step of that path, or nil if no such path exists.
local function findStep(battle, unit, target, range: number): (number?, number?)
	local visited = { [Battle.cellKey(battle, unit.column, unit.row)] = true }
	local queue = {}
	for _, neighbor in HexGrid.neighbors(unit.column, unit.row) do
		local column, row = neighbor[1], neighbor[2]
		if Battle.isFree(battle, column, row) then
			visited[Battle.cellKey(battle, column, row)] = true
			table.insert(queue, { column = column, row = row, firstColumn = column, firstRow = row })
		end
	end

	local head = 1
	while head <= #queue do
		local node = queue[head]
		head += 1
		if HexGrid.distance(node.column, node.row, target.column, target.row) <= range then
			return node.firstColumn, node.firstRow
		end
		for _, neighbor in HexGrid.neighbors(node.column, node.row) do
			local column, row = neighbor[1], neighbor[2]
			local key = Battle.cellKey(battle, column, row)
			if Battle.isFree(battle, column, row) and not visited[key] then
				visited[key] = true
				table.insert(
					queue,
					{ column = column, row = row, firstColumn = node.firstColumn, firstRow = node.firstRow }
				)
			end
		end
	end
	return nil, nil
end

-- Attack stacks (a unit type's `attackStacks`): an attack on the stacked target adds one, up to
-- max; an attack on another target starts over at one. Units that cast at max stacks show them as
-- mana, so their mana bar fills as the stacks build and they cast when it is full.
local function addAttackStack(unit, target)
	local attackStacks = unit.stats.attackStacks
	if not attackStacks then
		return
	end
	if unit.stackTarget ~= target then
		unit.stacks = 0
		unit.stackTarget = target
	end
	unit.stacks = math.min(attackStacks.max, unit.stacks + 1)
	if attackStacks.castAtMax and unit.maxMana then
		unit.mana = unit.maxMana * unit.stacks / attackStacks.max
	end
end

-- A form's basic-attack splash: every other enemy next to the target takes a share of the hit.
local function splash(battle, unit, target, raw: number)
	local form = unit.form
	if not (form and form.splash) then
		return
	end
	local amount = raw * form.splash.percent / 100
	for _, enemy in Battle.enemiesOf(battle, unit) do
		if enemy ~= target and HexGrid.distance(enemy.column, enemy.row, target.column, target.row) == 1 then
			Battle.damage(
				battle,
				unit,
				enemy,
				amount,
				CombatMath.DamageType.Physical,
				"Damage",
				nil,
				nil,
				nil,
				{ splash = true }
			)
		end
	end
end

local function act(battle, unit)
	unit.attackCooldown -= 1
	unit.moveCooldown -= 1
	if unit.passive or Battle.isUntargetable(battle, unit) then
		return
	end
	if battle.tick < unit.stunnedUntilTick or battle.tick < unit.castEndsTick then
		return
	end

	if unit.ability and unit.maxMana and unit.mana >= unit.maxMana then
		Abilities.cast(battle, unit)
		return
	end

	local range = Battle.range(unit)
	local target = unit.target
	if
		target == nil
		or target.dead
		or Battle.isUntargetable(battle, target)
		or Battle.distance(unit, target) > range
	then
		target = findNearestEnemy(battle, unit)
		unit.target = target
	end
	if target == nil then
		return
	end

	if Battle.distance(unit, target) <= range then
		if unit.attackCooldown <= 0 then
			local raw = Battle.stat(battle, unit, "AD")
			local critChance = Battle.stat(battle, unit, "CritChance")
			local crit = SeededRandom.nextInt(battle.rng, 1000000) <= critChance * 1000000
			if crit then
				raw = CombatMath.critRawDamage(raw, Battle.stat(battle, unit, "CritDamage"))
			end
			unit.attackCooldown =
				math.max(1, math.round(battle.ticksPerSecond / Battle.stat(battle, unit, "AttackSpeed")))
			addAttackStack(unit, target)
			Battle.damage(battle, unit, target, raw, CombatMath.DamageType.Physical, "Attack", crit)
			splash(battle, unit, target, raw)
			Battle.runHooks(battle, "attack", unit, target)
		end
	elseif unit.moveCooldown <= 0 then
		local column, row = findStep(battle, unit, target, range)
		if column and row then
			Battle.relocate(battle, unit, column, row)
			local cellsPerSecond = CombatConfig.baseMoveSpeed * Battle.stat(battle, unit, "MoveSpeed")
			unit.moveCooldown = math.max(1, math.round(battle.ticksPerSecond / cellsPerSecond))
			Battle.emit(battle, { kind = "Move", unit = unit.index, column = column, row = row })
		end
	end
end

-- True while a side has a living board unit. Summons alone do not keep a side in the fight.
local function sideAlive(battle, side: number): boolean
	for _, unit in battle.units do
		if unit.side == side and not unit.dead and not unit.summoned then
			return true
		end
	end
	return false
end

-- Advances the battle by one tick: expiries, scheduled effects that are due, damage-over-time
-- ticks, aura pulses and tick hooks (traits), then every unit acts.
function CombatSim.step(battle)
	battle.tick += 1
	Battle.expire(battle)
	Battle.runScheduled(battle)
	Battle.tickDots(battle)
	Battle.tickAuras(battle)
	Battle.runHooks(battle, "tick")
	local order = {}
	for _, unit in battle.units do
		if not unit.dead then
			table.insert(order, unit)
		end
	end
	SeededRandom.shuffle(battle.rng, order)
	for _, unit in order do
		if not unit.dead then
			act(battle, unit)
		end
	end
end

function CombatSim.run(params: Params): Result
	local battle = Battle.new(params)
	if params.startBonuses then
		for _, unit in battle.units do
			local bonus = params.startBonuses[unit.side] and params.startBonuses[unit.side][unit.id]
			if bonus then
				Battle.applyStartBonus(battle, unit, bonus)
			end
		end
	end
	-- Items: stats and effects, before the summaries so they show item health and mana.
	ItemCombat.setup(battle)
	local summaries = {}
	for _, unit in battle.units do
		table.insert(summaries, {
			index = unit.index,
			side = unit.side,
			id = unit.id,
			unitType = unit.unitType,
			starLevel = unit.starLevel,
			column = unit.column,
			row = unit.row,
			maxHealth = unit.maxHealth,
			mana = unit.mana,
			maxMana = unit.maxMana,
			form = if unit.form then unit.form.name else nil,
			formIndex = unit.formIndex,
			formHealth = unit.formHealth,
			maxFormHealth = unit.maxFormHealth,
			items = table.clone(unit.items),
		})
	end
	-- After the summaries: trait dummies are summons and appear as Summon events, not summaries.
	TraitCombat.setup(battle, params.traits)

	while battle.tick < params.maxTicks and sideAlive(battle, 1) and sideAlive(battle, 2) do
		CombatSim.step(battle)
	end

	-- Summons count for neither survivors nor the timeout health percentage.
	local survivors = { 0, 0 }
	local currentHealth = { 0, 0 }
	local maxHealth = { 0, 0 }
	for _, unit in battle.units do
		if not unit.summoned then
			currentHealth[unit.side] += unit.health
			maxHealth[unit.side] += unit.maxHealth
			if not unit.dead then
				survivors[unit.side] += 1
			end
		end
	end
	local healthPercent = {
		if maxHealth[1] > 0 then currentHealth[1] / maxHealth[1] else 0,
		if maxHealth[2] > 0 then currentHealth[2] / maxHealth[2] else 0,
	}

	local winner = nil
	local timedOut = survivors[1] > 0 and survivors[2] > 0
	if timedOut then
		local margin = params.timeoutDrawMargin or 0
		if healthPercent[1] - healthPercent[2] > margin then
			winner = 1
		elseif healthPercent[2] - healthPercent[1] > margin then
			winner = 2
		end
	elseif survivors[1] > 0 then
		winner = 1
	elseif survivors[2] > 0 then
		winner = 2
	end

	return {
		winner = winner,
		timedOut = timedOut,
		survivors = survivors,
		healthPercent = healthPercent,
		endTick = battle.tick,
		ticksPerSecond = params.ticksPerSecond,
		seed = params.seed,
		units = summaries,
		events = battle.events,
		traitResults = TraitCombat.results(battle),
	}
end

return CombatSim
