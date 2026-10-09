-- Generic ability interpreter (docs/design/combat-and-roster.md section 2, with the engine v2
-- building blocks from docs/design/revamp-structure.md and the Overhaul 1 pieces from
-- docs/design/overhaul-1.md). An ability is data:
--
--   { name = "Iron Pulse", effects = { effect, effect, ... } }
--
-- Each effect has a `type` (one of Abilities.Effect) and names a target selector (one of
-- Abilities.Selector) in `target`, or in `center` for area effects. SUMMON and RECALL need no
-- selector. Values that change with star level are lists of three numbers ({ 1-star, 2-star,
-- 3-star }); constants may be plain numbers.
--
--   DAMAGE            target, damageType (CombatMath.DamageType), amount; optional
--                     healPercentOfDamage (the caster heals that share of the damage dealt)
--   AREA_DAMAGE       center, damageType, amount, and a shape (default CIRCLE):
--                       CIRCLE  radius: every enemy within radius of the center hex
--                       LINE    the hexes on the straight line from the caster through the center,
--                               `length` hexes past it (omitted: to the board edge); with
--                               startAfterTarget = true, only the hexes past the center
--                       CONE    radius (length) and optional angle (half-width in degrees, default
--                               30): hexes toward the center within radius of the caster; damage
--                               falls by `falloff` percent per hex after the first
--                     optional healPerHit (the caster heals this much, scaled like a heal, per
--                     enemy hit), fixedCenter = true (a delayed area stays where the center stood
--                     when the cast began). Emits an Area event before its hits.
--   HEAL              target, amount; pool = true heals the target's form health pool instead
--   SHIELD            target, amount, duration
--   STUN              target, duration (at most CombatConfig.maxStunSeconds)
--   BUFF              target, stat (Battle.StatFields), flat or percent, duration (or permanent =
--                     true: the rest of the fight); optional stackPerCast = true with maxStacks =
--                     N: each cast adds one stack up to N and refreshes the duration (Battle.buff)
--   DEBUFF            target, status (SLOW, WEAKEN or CURSE: Battle.DebuffStats), percent,
--                     duration; with center and radius instead of target, every enemy in range
--   DASH              target, distance, mode (OFFENSIVE or DEFENSIVE; OFFENSIVE if omitted),
--                     setsCurrentTarget (optional; true makes the dash's target the caster's current
--                     target after the dash, whether or not the caster moved). An offensive dash
--                     moves only as far as needed: it stays put when already next to the target.
--   AREA_STUN         center, radius (1 or 2), duration (at most CombatConfig.maxStunSeconds): stuns
--                     every living enemy within radius of the center hex when it resolves; optional
--                     damageOnEnd = { damageType, amount, healPercentOfDamage? }: each stunned
--                     enemy takes that hit when its stun from this effect ends
--   SUMMON            count, duration, healthPercent, attackDamagePercent, armorPercent,
--                     magicResistPercent, attackSpeedPercent (of the caster's current stats), range,
--                     moveSpeed: places summons on the free cells nearest the caster (Battle.summon);
--                     ones that cannot be placed, or would pass CombatConfig.maxEntitiesPerSide, are
--                     skipped. Optional: permanent = true (no duration: they last until killed or
--                     recalled), manaPerHit (mana the caster gains per summon basic attack), refill =
--                     true (summons only enough to bring the caster's living summons back to count)
--   PULL              target: moves the enemy to the free cell next to the caster nearest it
--                     (Battle.pull); it becomes the caster's current target even if it could not move
--   DAMAGE_OVER_TIME  target, or center with radius; damageType, amount (per tick), interval,
--                     duration (seconds): Battle.damageOverTime on the target or on every enemy in
--                     the radius. Optional status (BURN or POISON) and weakenPercent (each victim is
--                     also WEAKENed by that much for the duration)
--   COPY              target: immediately applies the target's ability as if the caster had cast it
--                     (caster's stats and star level), with every damage, heal and shield amount
--                     multiplied by CombatConfig.copyPowerByCost for the copied unit's cost. A COPY
--                     inside a copied ability is ignored. COPY never selects a summon: if its
--                     selector would pick one, the same selector picks again among non-summoned
--                     enemies.
--   BOUNCE            target (where it bounces from; not hit again), count, damageType, amount: hits
--                     the nearest other enemy, then the nearest one not hit yet, `count` times
--   KNOCKBACK         target: pushes it one hex straight away from the caster if that hex is free
--   RECALL            (no selector): removes the caster's living summons; the number recalled is
--                     the RECALLED bonus of the cast's later effects
--
-- Every effect may also have:
--   delay      seconds (per star or constant): the effect lands that long after the cast, on the
--              target chosen at the cast (skipped if the caster dies first)
--   condition  { type, ..., negate? } (Abilities.Condition): the effect applies only if it holds
--              (or, with negate = true, only if it does not). KILLED is checked when the effect
--              lands; the others once, when the cast begins.
--                KILLED          an earlier hit of this cast killed its target
--                ALLY_BELOW      healthPercent: a living ally (the caster included) is below it
--                SUMMONS_ALIVE   atLeast: the caster has at least that many living summons
--                ENEMY_HAS_CAST  a living enemy has cast an ability this fight
--                CAST_CYCLE      every, at: this is cast number `at` of each cycle of `every` casts
--                                (casts 1..every, then the count starts over)
--   bonus      { type, percent, status? } (Abilities.Bonus): damage effects deal
--              amount x (1 + factor x percent / 100), with factor:
--                MISSING_HEALTH  the caster's missing health fraction (0 to 1)
--                TARGET_STATUS   1 if the victim has `status` (Battle.Status), else 0
--                STACKS          the caster's attack stacks when the cast began
--                RECALLED        summons recalled earlier in this cast
--                CASTS           the caster's earlier casts this fight (a bonus that grows with
--                                every cast, for the rest of the fight)
--
-- Ability-level options (all optional):
--   castTime          seconds the caster cannot act after casting (default CombatConfig.castTime;
--                     0 is an instant cast)
--   resetAttackTimer  true: the caster's next basic attack is ready at once
--   selfStun          seconds the caster is stunned after the cast
--   nearbyRange       hexes for LOWEST_HP_ENEMY_NEARBY (required when it is used)
--   clusterRadius     hexes for LARGEST_CLUSTER (default 2)
--   onTargetKilled    { window, maxRepeats, effects }: for `window` seconds after the cast, each
--                     time the caster's current target dies, `effects` run as a new cast on the
--                     next tick (fresh selectors), at most `maxRepeats` times per cast
--   formOnly          true: the ability has no effects; casting it only fires the form's ON_CAST
--                     trigger (Forms)
--
-- Selectors (Abilities.Selector) return one living unit or nil, except ALL_ALLIES,
-- LOWEST_HP_ALLIES and LOWEST_HP_OTHER_ALLIES, which select several (an effect `count` for the
-- last two). Ties are broken by the battle's seeded random generator. Ally selectors never pick
-- summons; enemy selectors skip untargetable units.
--   ATTACKER_OF_LOWEST_ALLY  the enemy attacking the caster's lowest-health other ally (fallback:
--                            CURRENT_TARGET)
--   LOWEST_HP_ENEMY_NEARBY   the lowest-health enemy within nearbyRange (fallback: CURRENT_TARGET)
--   LARGEST_CLUSTER          the enemy with the most enemies within clusterRadius of it
--   LAST_CASTER_ENEMY        the enemy that cast most recently (nil if none has cast)
--
-- Casting: when a unit's mana is full and it is free to act, it casts. Every selector the ability
-- uses is resolved once, before any effect, so effects naming the same selector share one target.
-- The effects then apply in listed order (delayed ones later), and the unit cannot act for the
-- cast time. Multi-target selectors work with HEAL, SHIELD and BUFF only.
-- Magic damage, heals and shields scale with the caster's ability power; heals and shields also
-- with its HealPower. Abilities cannot crit. Abilities have unlimited range.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local Battle = if script then require(script.Parent.Battle) else require("./Battle")
local CombatConfig = if script then require(script.Parent.CombatConfig) else require("./CombatConfig")
local CombatMath = if script then require(script.Parent.CombatMath) else require("./CombatMath")
local Forms = if script then require(script.Parent.Forms) else require("./Forms")
local HexGrid = if script then require(script.Parent.HexGrid) else require("./HexGrid")

local Abilities = {}

Abilities.Effect = table.freeze({
	Damage = "DAMAGE",
	AreaDamage = "AREA_DAMAGE",
	Heal = "HEAL",
	Shield = "SHIELD",
	Stun = "STUN",
	Buff = "BUFF",
	Dash = "DASH",
	AreaStun = "AREA_STUN",
	Summon = "SUMMON",
	Pull = "PULL",
	DamageOverTime = "DAMAGE_OVER_TIME",
	Copy = "COPY",
	Debuff = "DEBUFF",
	Bounce = "BOUNCE",
	Knockback = "KNOCKBACK",
	Recall = "RECALL",
})

Abilities.Selector = table.freeze({
	Self = "SELF",
	CurrentTarget = "CURRENT_TARGET",
	LowestHpAlly = "LOWEST_HP_ALLY",
	NearestEnemy = "NEAREST_ENEMY",
	FarthestEnemy = "FARTHEST_ENEMY",
	HighestAdEnemy = "HIGHEST_AD_ENEMY",
	AllAllies = "ALL_ALLIES",
	LowestHpOtherAlly = "LOWEST_HP_OTHER_ALLY",
	LowestHpAllies = "LOWEST_HP_ALLIES",
	LowestHpOtherAllies = "LOWEST_HP_OTHER_ALLIES",
	AttackerOfLowestAlly = "ATTACKER_OF_LOWEST_ALLY",
	LowestHpEnemyNearby = "LOWEST_HP_ENEMY_NEARBY",
	LargestCluster = "LARGEST_CLUSTER",
	LastCasterEnemy = "LAST_CASTER_ENEMY",
})

Abilities.DashMode = table.freeze({
	Offensive = "OFFENSIVE",
	Defensive = "DEFENSIVE",
})

Abilities.Shape = table.freeze({
	Circle = "CIRCLE",
	Line = "LINE",
	Cone = "CONE",
})

Abilities.Condition = table.freeze({
	Killed = "KILLED",
	AllyBelow = "ALLY_BELOW",
	SummonsAlive = "SUMMONS_ALIVE",
	EnemyHasCast = "ENEMY_HAS_CAST",
	CastCycle = "CAST_CYCLE",
})

Abilities.Bonus = table.freeze({
	MissingHealth = "MISSING_HEALTH",
	TargetStatus = "TARGET_STATUS",
	Stacks = "STACKS",
	Recalled = "RECALLED",
	Casts = "CASTS",
})

local Effect = Abilities.Effect
local Selector = Abilities.Selector
local Shape = Abilities.Shape
local Condition = Abilities.Condition
local Bonus = Abilities.Bonus

local DEFAULT_CLUSTER_RADIUS = 2
local DEFAULT_CONE_ANGLE = 30
-- Tags on the Damage events of AREA_DAMAGE hits (the Area event before them shows the area).
local AREA_HIT = table.freeze({ area = true })

-- Selectors that pick several units, and the effects that accept them.
local MULTI_SELECTORS = {
	[Selector.AllAllies] = true,
	[Selector.LowestHpAllies] = true,
	[Selector.LowestHpOtherAllies] = true,
}
local MULTI_TARGET_EFFECTS = { [Effect.Heal] = true, [Effect.Shield] = true, [Effect.Buff] = true }
-- Effects without a selector.
local NO_SELECTOR = { [Effect.Summon] = true, [Effect.Recall] = true }

-- A per-star value: a list indexed by star level, or a constant.
local function valueAt(value: any, starLevel: number): any
	if type(value) == "table" then
		return value[starLevel]
	end
	return value
end
Abilities.valueAt = valueAt

local function selectorOf(effect): string?
	return effect.target or effect.center
end

-- The key a selector's choice is stored under for one cast: multi-target selectors with a count
-- are resolved once per count.
local function selectorKey(effect): string?
	local selector = selectorOf(effect)
	if selector and MULTI_SELECTORS[selector] and effect.count then
		return selector .. "#" .. tostring(effect.count)
	end
	return selector
end

local function alive(unit): boolean
	return unit ~= nil and not unit.dead
end

-- Living board units (not summons) on the caster's side.
local function deployedAllies(battle, caster)
	local result = {}
	for _, ally in Battle.alliesOf(battle, caster) do
		if not ally.summoned then
			table.insert(result, ally)
		end
	end
	return result
end

-- Targetable living enemies of `caster`; with `noSummons`, only board units.
local function enemiesFor(battle, caster, noSummons: boolean?)
	local enemies = Battle.enemiesOf(battle, caster)
	if not noSummons then
		return enemies
	end
	local result = {}
	for _, enemy in enemies do
		if not enemy.summoned then
			table.insert(result, enemy)
		end
	end
	return result
end

local function healthFraction(unit): number
	return unit.health / unit.maxHealth
end

-- Up to `count` of `candidates` with the lowest health percentage, lowest first.
local function lowestHealth(battle, candidates, count: number)
	local remaining = table.clone(candidates)
	local picked = {}
	while #picked < count and #remaining > 0 do
		local best = Battle.pickBest(battle, remaining, function(unit)
			return -healthFraction(unit)
		end)
		table.insert(picked, best)
		table.remove(remaining, table.find(remaining, best))
	end
	return picked
end

local SELECTORS -- defined below; fallbacks call each other

-- Target selectors: (battle, caster, noSummons, ability, effect) -> unit, { many = units } or nil.
SELECTORS = {
	[Selector.Self] = function(_battle, caster)
		return caster
	end,
	[Selector.CurrentTarget] = function(battle, caster, noSummons)
		local current = caster.target
		if
			current
			and not current.dead
			and not Battle.isUntargetable(battle, current)
			and not (noSummons and current.summoned)
		then
			return current
		end
		local best = Battle.pickBest(battle, enemiesFor(battle, caster, noSummons), function(enemy)
			return -Battle.distance(caster, enemy)
		end)
		if not noSummons then
			caster.target = best
		end
		return best
	end,
	[Selector.LowestHpAlly] = function(battle, caster)
		-- Lowest current health percentage; any living deployed ally, the caster included.
		return Battle.pickBest(battle, deployedAllies(battle, caster), function(ally)
			return -ally.health / ally.maxHealth
		end)
	end,
	[Selector.NearestEnemy] = function(battle, caster, noSummons)
		return Battle.pickBest(battle, enemiesFor(battle, caster, noSummons), function(enemy)
			return -Battle.distance(caster, enemy)
		end)
	end,
	[Selector.FarthestEnemy] = function(battle, caster, noSummons)
		return Battle.pickBest(battle, enemiesFor(battle, caster, noSummons), function(enemy)
			return Battle.distance(caster, enemy)
		end)
	end,
	[Selector.HighestAdEnemy] = function(battle, caster, noSummons)
		-- Highest current attack damage; ties go to the nearer enemy.
		return Battle.pickBest(battle, enemiesFor(battle, caster, noSummons), function(enemy)
			return Battle.stat(battle, enemy, "AD") * 1000 - Battle.distance(caster, enemy)
		end)
	end,
	[Selector.AllAllies] = function(battle, caster)
		-- Every living deployed ally, the caster included.
		return { many = deployedAllies(battle, caster) }
	end,
	[Selector.LowestHpOtherAlly] = function(battle, caster)
		-- Like LOWEST_HP_ALLY without the caster; nil if it has no other living deployed ally.
		local others = {}
		for _, ally in deployedAllies(battle, caster) do
			if ally ~= caster then
				table.insert(others, ally)
			end
		end
		return Battle.pickBest(battle, others, function(ally)
			return -ally.health / ally.maxHealth
		end)
	end,
	[Selector.LowestHpAllies] = function(battle, caster, _noSummons, _ability, effect)
		-- The `count` living deployed allies (the caster included) with the lowest health percentage.
		return { many = lowestHealth(battle, deployedAllies(battle, caster), effect.count or 1) }
	end,
	[Selector.LowestHpOtherAllies] = function(battle, caster, _noSummons, _ability, effect)
		-- Like LOWEST_HP_ALLIES without the caster.
		local others = {}
		for _, ally in deployedAllies(battle, caster) do
			if ally ~= caster then
				table.insert(others, ally)
			end
		end
		return { many = lowestHealth(battle, others, effect.count or 1) }
	end,
	[Selector.AttackerOfLowestAlly] = function(battle, caster, noSummons, ability, effect)
		-- Among enemies whose current target is one of the caster's other deployed allies: the one
		-- attacking the ally with the lowest health percentage, the nearer one on ties.
		local attackers = {}
		for _, enemy in enemiesFor(battle, caster, noSummons) do
			local victim = enemy.target
			if
				victim
				and victim ~= caster
				and not victim.dead
				and not victim.summoned
				and victim.side == caster.side
			then
				table.insert(attackers, enemy)
			end
		end
		if #attackers == 0 then
			return SELECTORS[Selector.CurrentTarget](battle, caster, noSummons, ability, effect)
		end
		return Battle.pickBest(battle, attackers, function(enemy)
			return -healthFraction(enemy.target) * 1000 - Battle.distance(caster, enemy)
		end)
	end,
	[Selector.LowestHpEnemyNearby] = function(battle, caster, noSummons, ability, effect)
		-- The enemy with the lowest health percentage within the ability's nearbyRange; nearer on ties.
		local range = ability.nearbyRange or 0
		local nearby = {}
		for _, enemy in enemiesFor(battle, caster, noSummons) do
			if Battle.distance(caster, enemy) <= range then
				table.insert(nearby, enemy)
			end
		end
		if #nearby == 0 then
			return SELECTORS[Selector.CurrentTarget](battle, caster, noSummons, ability, effect)
		end
		return Battle.pickBest(battle, nearby, function(enemy)
			return -healthFraction(enemy) * 1000 - Battle.distance(caster, enemy)
		end)
	end,
	[Selector.LargestCluster] = function(battle, caster, noSummons, ability)
		-- The enemy with the most enemies (itself included) within clusterRadius; nearer on ties.
		local radius = ability.clusterRadius or DEFAULT_CLUSTER_RADIUS
		local enemies = enemiesFor(battle, caster, noSummons)
		return Battle.pickBest(battle, enemies, function(enemy)
			local around = 0
			for _, other in enemies do
				if Battle.distance(enemy, other) <= radius then
					around += 1
				end
			end
			return around * 1000 - Battle.distance(caster, enemy)
		end)
	end,
	[Selector.LastCasterEnemy] = function(battle, caster, noSummons)
		-- The enemy that cast most recently; nearer on ties; nil while no enemy has cast.
		local casters = {}
		for _, enemy in enemiesFor(battle, caster, noSummons) do
			if enemy.lastCastTick then
				table.insert(casters, enemy)
			end
		end
		return Battle.pickBest(battle, casters, function(enemy)
			return enemy.lastCastTick * 1000 - Battle.distance(caster, enemy)
		end)
	end,
}

-- Every cell of the field in a fixed order, as { column, row }.
local function allCells(battle)
	local cells = {}
	for row = 1, battle.fieldRows do
		for column = 1, battle.columns do
			table.insert(cells, { column, row })
		end
	end
	return cells
end

-- Chooses where a DASH lands, or nil to stay. Only free cells within `distance` hexes (straight
-- line; dashes pass over units) are valid.
--   OFFENSIVE: the valid cell adjacent to `target` nearest the caster. If no adjacent cell is in
--     reach, the valid cell nearest the target, if it is closer than where the caster stands.
--   DEFENSIVE: the valid cell farthest from the nearest enemy, if farther than where the caster
--     stands.
-- Ties go to the cell nearer the caster, then to the first cell in field order.
local function dashDestination(battle, caster, target, distance: number, mode: string): (number?, number?)
	local function fromCaster(cell)
		return HexGrid.distance(caster.column, caster.row, cell[1], cell[2])
	end
	local valid = {}
	for _, cell in allCells(battle) do
		local reach = fromCaster(cell)
		if reach >= 1 and reach <= distance and Battle.isFree(battle, cell[1], cell[2]) then
			table.insert(valid, cell)
		end
	end

	-- Picks the valid cell with the lowest `cost`, nearer the caster on ties.
	local function cheapest(cost: ({ number }) -> number): ({ number }?, number)
		local best, bestCost = nil, math.huge
		for _, cell in valid do
			local value = cost(cell) * 1000 + fromCaster(cell)
			if value < bestCost then
				best, bestCost = cell, value
			end
		end
		return best, bestCost
	end

	if mode == Abilities.DashMode.Defensive then
		local enemies = Battle.enemiesOf(battle, caster)
		local function nearestEnemyDistance(column, row)
			local nearest = math.huge
			for _, enemy in enemies do
				nearest = math.min(nearest, HexGrid.distance(column, row, enemy.column, enemy.row))
			end
			return nearest
		end
		local cell = cheapest(function(c)
			return -nearestEnemyDistance(c[1], c[2])
		end)
		if cell and nearestEnemyDistance(cell[1], cell[2]) > nearestEnemyDistance(caster.column, caster.row) then
			return cell[1], cell[2]
		end
		return nil, nil
	end

	if not target or target.dead or Battle.distance(caster, target) <= 1 then
		return nil, nil
	end
	local function fromTarget(cell)
		return HexGrid.distance(cell[1], cell[2], target.column, target.row)
	end
	local adjacent = cheapest(function(c)
		return if fromTarget(c) == 1 then 0 else math.huge
	end)
	if adjacent and fromTarget(adjacent) == 1 then
		return adjacent[1], adjacent[2]
	end
	local closer = cheapest(fromTarget)
	if closer and fromTarget(closer) < Battle.distance(caster, target) then
		return closer[1], closer[2]
	end
	return nil, nil
end

-- How the current ability is being applied:
--   power       multiplies amounts (COPY)
--   abilityName keys damage over time
--   nested      true inside a copied ability
--   stacks      the caster's attack stacks when the cast began (STACKS bonus)
--   recalled    summons recalled so far in this cast (RECALLED bonus)
--   killed      true once a hit of this cast killed its target (KILLED condition)
--   held        effect -> whether its cast-start condition held
type Context = {
	power: number,
	abilityName: string,
	nested: boolean,
	stacks: number,
	recalled: number,
	killed: boolean,
	held: { [any]: boolean },
}

local function newContext(power: number, abilityName: string, nested: boolean, stacks: number): Context
	return {
		power = power,
		abilityName = abilityName,
		nested = nested,
		stacks = stacks,
		recalled = 0,
		killed = false,
		held = {},
	}
end

-- An effect's listed amount for `starLevel`, scaled: magic damage, heals and shields by ability
-- power, heals and shields also by HealPower, and everything by the context's power (COPY).
-- `effect` may be a sub-effect without a type (damageOnEnd).
local function scaledAmount(battle, caster, effect, starLevel: number, context: Context): number
	local listed = valueAt(effect.amount, starLevel)
	local healing = effect.type == Effect.Heal or effect.type == Effect.Shield
	local scales = healing or effect.damageType == CombatMath.DamageType.Magic
	local amount = if scales then CombatMath.scaleByAbilityPower(listed, Battle.stat(battle, caster, "AP")) else listed
	if healing then
		amount *= Battle.stat(battle, caster, "HealPower")
	end
	return amount * context.power
end

-- The bonus multiplier of `effect` against `victim` (1 without a bonus).
local function bonusMultiplier(battle, caster, effect, victim, starLevel: number, context: Context): number
	local bonus = effect.bonus
	if not bonus then
		return 1
	end
	local factor = 0
	if bonus.type == Bonus.MissingHealth then
		factor = math.clamp(1 - caster.health / caster.maxHealth, 0, 1)
	elseif bonus.type == Bonus.TargetStatus then
		factor = if victim and Battle.hasStatus(battle, victim, bonus.status) then 1 else 0
	elseif bonus.type == Bonus.Stacks then
		factor = context.stacks
	elseif bonus.type == Bonus.Recalled then
		factor = context.recalled
	elseif bonus.type == Bonus.Casts then
		factor = math.max(0, (caster.casts or 1) - 1)
	end
	return 1 + factor * valueAt(bonus.percent, starLevel) / 100
end

-- One ability hit on `victim`: the bonus, Battle.damage, the KILLED flag and any lifesteal.
-- Returns the final damage.
local function hit(
	battle,
	caster,
	effect,
	victim,
	amount: number,
	damageType: string,
	starLevel: number,
	context: Context,
	tags
)
	if not alive(victim) then
		return 0
	end
	local raw = amount * bonusMultiplier(battle, caster, effect, victim, starLevel, context)
	local final = Battle.damage(battle, caster, victim, raw, damageType, "Damage", nil, nil, nil, tags)
	if victim.dead then
		context.killed = true
	end
	local lifesteal = valueAt(effect.healPercentOfDamage, starLevel)
	if lifesteal and lifesteal > 0 and final > 0 and not caster.dead then
		Battle.heal(battle, caster, caster, final * lifesteal / 100)
	end
	return final
end

-- Living enemies of `caster` within `radius` of `center`'s hex (the hex is used even if the center
-- unit died earlier in this cast; `center` may also be a fixed { column, row } cell).
local function enemiesWithin(battle, caster, center, radius: number)
	local result = {}
	for _, enemy in Battle.enemiesOf(battle, caster) do
		if HexGrid.distance(center.column, center.row, enemy.column, enemy.row) <= radius then
			table.insert(result, enemy)
		end
	end
	return result
end

-- The field cells an AREA_DAMAGE covers, as a set of cell keys and a list of { column, row }, and
-- each covered cell's damage multiplier (cone falloff).
local function areaCells(battle, caster, effect, center, starLevel: number)
	local shape = effect.shape or Shape.Circle
	local keys, list, multipliers = {}, {}, {}
	local function add(column: number, row: number, multiplier: number)
		if Battle.inBounds(battle, column, row) then
			local key = Battle.cellKey(battle, column, row)
			if not keys[key] then
				keys[key] = true
				multipliers[key] = multiplier
				table.insert(list, { column, row })
			end
		end
	end
	if shape == Shape.Line then
		local length = valueAt(effect.length, starLevel)
		local beyond = if length then length else battle.columns + battle.fieldRows
		local line = HexGrid.line(caster.column, caster.row, center.column, center.row, beyond)
		local skip = if effect.startAfterTarget
			then HexGrid.distance(caster.column, caster.row, center.column, center.row)
			else 0
		for index, cell in line do
			if index > skip then
				add(cell[1], cell[2], 1)
			end
		end
	elseif shape == Shape.Cone then
		local radius = valueAt(effect.radius, starLevel)
		local falloff = (valueAt(effect.falloff, starLevel) or 0) / 100
		local angle = effect.angle or DEFAULT_CONE_ANGLE
		for row = 1, battle.fieldRows do
			for column = 1, battle.columns do
				local distance = HexGrid.distance(caster.column, caster.row, column, row)
				if
					distance >= 1
					and distance <= radius
					and HexGrid.inCone(caster.column, caster.row, center.column, center.row, column, row, angle)
				then
					add(column, row, math.max(0, 1 - falloff * (distance - 1)))
				end
			end
		end
	end
	return keys, list, multipliers
end

local applyAbility -- defined below; COPY and follow-ups call it

local APPLY = {
	[Effect.Damage] = function(battle, caster, effect, target, starLevel, context)
		if alive(target) then
			local amount = scaledAmount(battle, caster, effect, starLevel, context)
			hit(battle, caster, effect, target, amount, effect.damageType, starLevel, context)
		end
	end,
	[Effect.AreaDamage] = function(battle, caster, effect, center, starLevel, context)
		if center == nil then
			return
		end
		local shape = effect.shape or Shape.Circle
		local amount = scaledAmount(battle, caster, effect, starLevel, context)
		local victims, multipliers = {}, {}
		local area = {
			kind = "Area",
			unit = caster.index,
			shape = shape,
			column = center.column,
			row = center.row,
		}
		if shape == Shape.Circle then
			local radius = valueAt(effect.radius, starLevel)
			area.radius = radius
			victims = enemiesWithin(battle, caster, center, radius)
		else
			local keys, list, cellMultipliers = areaCells(battle, caster, effect, center, starLevel)
			area.cells = list
			area.fromColumn, area.fromRow = caster.column, caster.row
			for _, enemy in Battle.enemiesOf(battle, caster) do
				local key = Battle.cellKey(battle, enemy.column, enemy.row)
				if keys[key] then
					table.insert(victims, enemy)
					multipliers[enemy] = cellMultipliers[key]
				end
			end
		end
		Battle.emit(battle, area)
		local hits = 0
		for _, enemy in victims do
			local final = hit(
				battle,
				caster,
				effect,
				enemy,
				amount * (multipliers[enemy] or 1),
				effect.damageType,
				starLevel,
				context,
				AREA_HIT
			)
			if final > 0 then
				hits += 1
			end
		end
		local healPerHit = valueAt(effect.healPerHit, starLevel)
		if healPerHit and hits > 0 and not caster.dead then
			local heal = scaledAmount(battle, caster, { type = Effect.Heal, amount = healPerHit }, starLevel, context)
			Battle.heal(battle, caster, caster, heal * hits)
		end
	end,
	[Effect.Heal] = function(battle, caster, effect, target, starLevel, context)
		if alive(target) then
			local amount = scaledAmount(battle, caster, effect, starLevel, context)
			if effect.pool then
				Battle.healFormPool(battle, caster, target, amount)
			else
				Battle.heal(battle, caster, target, amount)
			end
		end
	end,
	[Effect.Shield] = function(battle, caster, effect, target, starLevel, context)
		if alive(target) then
			local amount = scaledAmount(battle, caster, effect, starLevel, context)
			Battle.shield(battle, caster, target, amount, valueAt(effect.duration, starLevel))
		end
	end,
	[Effect.Stun] = function(battle, caster, effect, target, starLevel)
		if alive(target) then
			Battle.stun(battle, caster, target, valueAt(effect.duration, starLevel))
		end
	end,
	[Effect.Buff] = function(battle, caster, effect, target, starLevel)
		if alive(target) then
			local flat = valueAt(effect.flat, starLevel) or 0
			local percent = valueAt(effect.percent, starLevel) or 0
			Battle.buff(
				battle,
				caster,
				target,
				effect.stat,
				flat,
				percent,
				if effect.permanent then math.huge else valueAt(effect.duration, starLevel),
				effect.stackPerCast,
				effect.maxStacks
			)
		end
	end,
	[Effect.Debuff] = function(battle, caster, effect, target, starLevel)
		if target == nil then
			return
		end
		local victims
		if effect.radius then
			victims = enemiesWithin(battle, caster, target, valueAt(effect.radius, starLevel))
		else
			victims = if alive(target) then { target } else {}
		end
		for _, victim in victims do
			Battle.debuff(
				battle,
				caster,
				victim,
				effect.status,
				valueAt(effect.percent, starLevel),
				valueAt(effect.duration, starLevel)
			)
		end
	end,
	[Effect.Dash] = function(battle, caster, effect, target, starLevel)
		local mode = effect.mode or Abilities.DashMode.Offensive
		local column, row = dashDestination(battle, caster, target, valueAt(effect.distance, starLevel), mode)
		if column and row then
			Battle.relocate(battle, caster, column, row)
			Battle.emit(battle, { kind = "Dash", unit = caster.index, column = column, row = row })
		end
		if effect.setsCurrentTarget and alive(target) then
			caster.target = target
		end
	end,
	[Effect.AreaStun] = function(battle, caster, effect, center, starLevel, context)
		if center == nil then
			return
		end
		local radius = valueAt(effect.radius, starLevel)
		local duration = valueAt(effect.duration, starLevel)
		Battle.emit(battle, {
			kind = "AreaStun",
			unit = caster.index,
			column = center.column,
			row = center.row,
			radius = radius,
		})
		local onEnd = effect.damageOnEnd
		for _, enemy in enemiesWithin(battle, caster, center, radius) do
			Battle.stun(battle, caster, enemy, duration)
			if onEnd then
				-- The hit lands when this stun ends, on the enemy it stunned.
				Battle.schedule(battle, Battle.seconds(battle, duration), caster, function()
					local amount = scaledAmount(battle, caster, onEnd, starLevel, context)
					hit(battle, caster, onEnd, enemy, amount, onEnd.damageType, starLevel, context, { stunEnd = true })
				end)
			end
		end
	end,
	[Effect.Summon] = function(battle, caster, effect, _target, starLevel)
		-- Not scaled by COPY power: count and stats are structural. Stats come from the caster now.
		local function percentOf(value: number, field: string): number
			return value * valueAt(effect[field], starLevel) / 100
		end
		local spec = {
			health = percentOf(caster.maxHealth, "healthPercent"),
			attackDamage = percentOf(Battle.stat(battle, caster, "AD"), "attackDamagePercent"),
			armor = percentOf(Battle.stat(battle, caster, "Armor"), "armorPercent"),
			magicResist = percentOf(Battle.stat(battle, caster, "MR"), "magicResistPercent"),
			attacksPerSecond = percentOf(Battle.stat(battle, caster, "AttackSpeed"), "attackSpeedPercent"),
			range = valueAt(effect.range, starLevel),
			moveSpeed = valueAt(effect.moveSpeed, starLevel),
			duration = if effect.permanent then nil else valueAt(effect.duration, starLevel),
			manaPerHit = valueAt(effect.manaPerHit, starLevel),
		}
		local count = valueAt(effect.count, starLevel)
		if effect.refill then
			count -= #Battle.summonsOf(battle, caster)
		end
		for _ = 1, count do
			Battle.summon(battle, caster, spec)
		end
	end,
	[Effect.Recall] = function(battle, caster, _effect, _target, _starLevel, context)
		context.recalled += Battle.recall(battle, caster)
	end,
	[Effect.Pull] = function(battle, caster, _effect, target)
		if alive(target) then
			Battle.pull(battle, caster, target)
			caster.target = target
		end
	end,
	[Effect.Knockback] = function(battle, caster, _effect, target)
		if alive(target) then
			Battle.knockback(battle, caster, target)
		end
	end,
	[Effect.Bounce] = function(battle, caster, effect, target, starLevel, context)
		if target == nil then
			return
		end
		local amount = scaledAmount(battle, caster, effect, starLevel, context)
		local done = { [target] = true }
		local from = target
		for _ = 1, valueAt(effect.count, starLevel) do
			local candidates = {}
			for _, enemy in Battle.enemiesOf(battle, caster) do
				if not done[enemy] then
					table.insert(candidates, enemy)
				end
			end
			local nextTarget = Battle.pickBest(battle, candidates, function(enemy)
				return -HexGrid.distance(from.column, from.row, enemy.column, enemy.row)
			end)
			if not nextTarget then
				break
			end
			done[nextTarget] = true
			Battle.emit(battle, { kind = "Bounce", unit = caster.index, from = from.index, target = nextTarget.index })
			hit(battle, caster, effect, nextTarget, amount, effect.damageType, starLevel, context)
			from = nextTarget
		end
	end,
	[Effect.DamageOverTime] = function(battle, caster, effect, target, starLevel, context)
		if target == nil then
			return
		end
		local victims
		if effect.radius then
			victims = enemiesWithin(battle, caster, target, valueAt(effect.radius, starLevel))
		else
			victims = if alive(target) then { target } else {}
		end
		local amount = scaledAmount(battle, caster, effect, starLevel, context)
		local key = caster.index .. ":" .. context.abilityName
		local duration = valueAt(effect.duration, starLevel)
		local weaken = valueAt(effect.weakenPercent, starLevel)
		for _, victim in victims do
			Battle.damageOverTime(
				battle,
				caster,
				victim,
				key,
				amount,
				effect.damageType,
				valueAt(effect.interval, starLevel),
				duration,
				effect.status
			)
			if weaken and weaken > 0 then
				Battle.debuff(battle, caster, victim, Battle.Status.Weaken, weaken, duration)
			end
		end
	end,
	[Effect.Copy] = function(battle, caster, _effect, target, _starLevel, context)
		if context.nested or not alive(target) or not target.ability then
			return
		end
		local power = CombatConfig.copyPowerByCost[target.stats.cost] or 1
		Battle.emit(
			battle,
			{ kind = "Copy", unit = caster.index, target = target.index, ability = target.ability.name }
		)
		applyAbility(
			battle,
			caster,
			target.ability,
			caster.starLevel,
			newContext(context.power * power, target.ability.name, true, 0)
		)
	end,
}

-- True if `effect`'s cast-start condition holds now (KILLED is checked later, when it lands).
local function conditionAtStart(battle, caster, condition): boolean
	local kind = condition.type
	if kind == Condition.AllyBelow then
		for _, ally in deployedAllies(battle, caster) do
			if ally.health * 100 < ally.maxHealth * condition.healthPercent then
				return true
			end
		end
		return false
	elseif kind == Condition.SummonsAlive then
		return #Battle.summonsOf(battle, caster) >= condition.atLeast
	elseif kind == Condition.EnemyHasCast then
		for _, enemy in Battle.enemiesOf(battle, caster) do
			if enemy.lastCastTick then
				return true
			end
		end
		return false
	elseif kind == Condition.CastCycle then
		-- The caster's casts this fight, counted 1, 2, ..., every, then from 1 again.
		return ((caster.casts or 1) - 1) % condition.every + 1 == condition.at
	end
	return true
end

-- True if `effect` may apply now.
local function conditionHolds(effect, context: Context): boolean
	local condition = effect.condition
	if not condition then
		return true
	end
	local holds
	if condition.type == Condition.Killed then
		holds = context.killed
	else
		holds = context.held[effect] == true
	end
	if condition.negate then
		return not holds
	end
	return holds
end

-- Applies one effect to its chosen target (each of several, for multi-target selectors).
local function applyEffect(battle, caster, effect, target, starLevel: number, context: Context)
	if caster.dead or not conditionHolds(effect, context) then
		return
	end
	if target and target.many then
		for _, each in target.many do
			APPLY[effect.type](battle, caster, effect, each, starLevel, context)
		end
	else
		APPLY[effect.type](battle, caster, effect, target, starLevel, context)
	end
end

-- Resolves an ability's selectors and applies its effects for `caster`.
function applyAbility(battle, caster, ability, starLevel: number, context: Context)
	local chosen = {}
	for _, effect in ability.effects do
		local key = selectorKey(effect)
		if key and chosen[key] == nil then
			chosen[key] = SELECTORS[selectorOf(effect)](battle, caster, false, ability, effect) or false
		end
		if effect.condition and effect.condition.type ~= Condition.Killed then
			context.held[effect] = conditionAtStart(battle, caster, effect.condition)
		end
	end
	-- COPY never selects a summon: if its selector picked one, it picks again among board units.
	local copyTargets = {}
	for _, effect in ability.effects do
		local key = selectorKey(effect)
		if effect.type == Effect.Copy and key and copyTargets[key] == nil then
			local picked = chosen[key]
			if picked and picked.summoned then
				picked = SELECTORS[selectorOf(effect)](battle, caster, true, ability, effect)
			end
			copyTargets[key] = picked or false
		end
	end
	for _, effect in ability.effects do
		if not (context.nested and effect.type == Effect.Copy) then
			local key = selectorKey(effect)
			local target = if key then chosen[key] or nil else nil
			if effect.type == Effect.Copy and key then
				target = copyTargets[key] or nil
			end
			local delay = valueAt(effect.delay, starLevel)
			if delay and delay > 0 then
				-- A delayed area with a fixed center stays where its center stood now.
				if effect.fixedCenter and target and not target.many then
					target = { column = target.column, row = target.row }
				end
				local landing = target
				Battle.schedule(battle, Battle.seconds(battle, delay), caster, function()
					applyEffect(battle, caster, effect, landing, starLevel, context)
				end)
			else
				applyEffect(battle, caster, effect, target, starLevel, context)
			end
		end
	end
end

-- Required numeric fields per effect type (each must exist for star levels 1-3).
local REQUIRED = {
	[Effect.Damage] = { "amount" },
	[Effect.AreaDamage] = { "amount" },
	[Effect.Heal] = { "amount" },
	[Effect.Shield] = { "amount", "duration" },
	[Effect.Stun] = { "duration" },
	[Effect.Buff] = {},
	[Effect.Dash] = { "distance" },
	[Effect.AreaStun] = { "duration", "radius" },
	[Effect.Summon] = {
		"count",
		"healthPercent",
		"attackDamagePercent",
		"armorPercent",
		"magicResistPercent",
		"attackSpeedPercent",
		"range",
		"moveSpeed",
	},
	[Effect.Pull] = {},
	[Effect.DamageOverTime] = { "amount", "interval", "duration" },
	[Effect.Copy] = {},
	[Effect.Debuff] = { "percent", "duration" },
	[Effect.Bounce] = { "amount", "count" },
	[Effect.Knockback] = {},
	[Effect.Recall] = {},
}

-- Effects that deal damage and so need a known damage type.
local DAMAGING = {
	[Effect.Damage] = true,
	[Effect.AreaDamage] = true,
	[Effect.DamageOverTime] = true,
	[Effect.Bounce] = true,
}

local function knownDamageType(damageType): boolean
	for _, each in CombatMath.DamageType do
		if damageType == each then
			return true
		end
	end
	return false
end

local function known(set, value): boolean
	for _, each in set do
		if each == value then
			return true
		end
	end
	return false
end

-- Checks that `value` is a number for star levels 1-3 (a list of three, or a constant).
local function perStarNumber(value): boolean
	for starLevel = 1, 3 do
		if type(valueAt(value, starLevel)) ~= "number" then
			return false
		end
	end
	return true
end

local function isWhole(value): boolean
	return type(value) == "number" and value >= 1 and value == math.floor(value)
end

-- Checks the parts every effect may have: delay, condition and bonus.
local function validateCommon(effect, where: string): (boolean, string?)
	if effect.delay ~= nil then
		if not perStarNumber(effect.delay) then
			return false, where .. ": delay must be a number of seconds for each star level"
		end
		for starLevel = 1, 3 do
			if valueAt(effect.delay, starLevel) < 0 then
				return false, where .. ": delay cannot be negative"
			end
		end
	end
	local condition = effect.condition
	if condition ~= nil then
		if type(condition) ~= "table" or not known(Condition, condition.type) then
			return false, where .. ": unknown condition " .. tostring(condition and condition.type)
		end
		if condition.negate ~= nil and type(condition.negate) ~= "boolean" then
			return false, where .. ": condition negate must be true or false"
		end
		if condition.type == Condition.AllyBelow then
			local percent = condition.healthPercent
			if type(percent) ~= "number" or percent <= 0 or percent > 100 then
				return false, where .. ": ALLY_BELOW needs healthPercent above 0 and at most 100"
			end
		elseif condition.type == Condition.SummonsAlive and not isWhole(condition.atLeast) then
			return false, where .. ": SUMMONS_ALIVE needs a whole atLeast of at least 1"
		elseif condition.type == Condition.CastCycle then
			local every, at = condition.every, condition.at
			if not isWhole(every) or every < 2 or not isWhole(at) or at > every then
				return false, where .. ": CAST_CYCLE needs whole every (at least 2) and at (1 to every)"
			end
		end
	end
	local bonus = effect.bonus
	if bonus ~= nil then
		if not DAMAGING[effect.type] or effect.type == Effect.DamageOverTime then
			return false, where .. ": only DAMAGE, AREA_DAMAGE and BOUNCE take a bonus"
		end
		if type(bonus) ~= "table" or not known(Bonus, bonus.type) then
			return false, where .. ": unknown bonus " .. tostring(bonus and bonus.type)
		end
		if not perStarNumber(bonus.percent) then
			return false, where .. ": a bonus needs a percent for each star level"
		end
		if bonus.type == Bonus.TargetStatus and not known(Battle.Status, bonus.status) then
			return false, where .. ": TARGET_STATUS needs a known status"
		end
	end
	return true
end

-- Checks the fields specific to one effect type. `fields` collects the per-star numbers to check.
local function validateFields(effect, where: string, fields: { string }): (boolean, string?)
	local kind = effect.type
	if DAMAGING[kind] and not knownDamageType(effect.damageType) then
		return false, where .. ": unknown damage type " .. tostring(effect.damageType)
	end
	if kind == Effect.Damage then
		if effect.healPercentOfDamage ~= nil then
			table.insert(fields, "healPercentOfDamage")
		end
	elseif kind == Effect.AreaDamage then
		local shape = effect.shape or Shape.Circle
		if not known(Shape, shape) then
			return false, where .. ": unknown area shape " .. tostring(shape)
		end
		if shape == Shape.Circle or shape == Shape.Cone then
			table.insert(fields, "radius")
		end
		if shape == Shape.Cone then
			if effect.falloff ~= nil then
				table.insert(fields, "falloff")
			end
			if effect.angle ~= nil and (type(effect.angle) ~= "number" or effect.angle <= 0 or effect.angle > 90) then
				return false, where .. ": a cone angle must be above 0 and at most 90 degrees"
			end
		end
		if shape == Shape.Line and effect.length ~= nil then
			table.insert(fields, "length")
		end
		if effect.startAfterTarget ~= nil and shape ~= Shape.Line then
			return false, where .. ": startAfterTarget is only for a LINE"
		end
		if effect.healPerHit ~= nil then
			table.insert(fields, "healPerHit")
		end
	elseif kind == Effect.Heal then
		if effect.pool ~= nil and type(effect.pool) ~= "boolean" then
			return false, where .. ": pool must be true or false"
		end
	elseif kind == Effect.Buff then
		if not Battle.StatFields[effect.stat] then
			return false, where .. ": unknown buff stat " .. tostring(effect.stat)
		end
		if effect.flat == nil and effect.percent == nil then
			return false, where .. ": a buff needs flat or percent"
		end
		table.insert(fields, if effect.flat ~= nil then "flat" else "percent")
		if effect.permanent ~= nil and effect.permanent ~= true then
			return false, where .. ": permanent must be true or omitted"
		end
		if not effect.permanent then
			table.insert(fields, "duration")
		end
		if effect.stackPerCast ~= nil and effect.stackPerCast ~= true then
			return false, where .. ": stackPerCast must be true or omitted"
		end
		if effect.stackPerCast then
			if not isWhole(effect.maxStacks) then
				return false, where .. ": a stacking buff needs a whole maxStacks of at least 1"
			end
		elseif effect.maxStacks ~= nil then
			return false, where .. ": maxStacks needs stackPerCast"
		end
	elseif kind == Effect.Debuff then
		if not Battle.DebuffStats[effect.status] then
			return false, where .. ": unknown debuff status " .. tostring(effect.status)
		end
		if effect.radius ~= nil then
			table.insert(fields, "radius")
		end
	elseif kind == Effect.Dash then
		if
			effect.mode ~= nil
			and effect.mode ~= Abilities.DashMode.Offensive
			and effect.mode ~= Abilities.DashMode.Defensive
		then
			return false, where .. ": unknown dash mode " .. tostring(effect.mode)
		end
		if effect.setsCurrentTarget ~= nil and type(effect.setsCurrentTarget) ~= "boolean" then
			return false, where .. ": setsCurrentTarget must be true or false"
		end
	elseif kind == Effect.AreaStun then
		local onEnd = effect.damageOnEnd
		if onEnd ~= nil then
			if type(onEnd) ~= "table" or not knownDamageType(onEnd.damageType) or not perStarNumber(onEnd.amount) then
				return false, where .. ": damageOnEnd needs a damageType and an amount for each star level"
			end
			if onEnd.healPercentOfDamage ~= nil and not perStarNumber(onEnd.healPercentOfDamage) then
				return false, where .. ": damageOnEnd healPercentOfDamage must be a number for each star level"
			end
		end
	elseif kind == Effect.Summon then
		if effect.permanent ~= nil and effect.permanent ~= true then
			return false, where .. ": permanent must be true or omitted"
		end
		if not effect.permanent then
			table.insert(fields, "duration")
		end
		if effect.manaPerHit ~= nil then
			table.insert(fields, "manaPerHit")
		end
		if effect.refill ~= nil and type(effect.refill) ~= "boolean" then
			return false, where .. ": refill must be true or false"
		end
	elseif kind == Effect.DamageOverTime then
		if effect.radius ~= nil then
			table.insert(fields, "radius")
		end
		if effect.status ~= nil and effect.status ~= Battle.Status.Burn and effect.status ~= Battle.Status.Poison then
			return false, where .. ": a damage over time status must be BURN or POISON"
		end
		if effect.weakenPercent ~= nil then
			table.insert(fields, "weakenPercent")
		end
	end
	if effect.fixedCenter ~= nil and kind ~= Effect.AreaDamage and kind ~= Effect.AreaStun then
		return false, where .. ": fixedCenter is only for AREA_DAMAGE and AREA_STUN"
	end
	return true
end

-- Checks a list of effects (an ability's, or an onTargetKilled's).
local function validateEffects(name: string, effects, ability): (boolean, string?)
	for index, effect in effects do
		local where = string.format("%s effect %d", name, index)
		if type(effect) ~= "table" or not APPLY[effect.type] then
			return false, where .. ": unknown effect " .. tostring(effect and effect.type)
		end
		local selector = selectorOf(effect)
		if NO_SELECTOR[effect.type] then
			if selector ~= nil then
				return false, where .. ": " .. effect.type .. " takes no target selector"
			end
		elseif not SELECTORS[selector] then
			return false, where .. ": unknown target selector " .. tostring(selector)
		end
		if selector and MULTI_SELECTORS[selector] and not MULTI_TARGET_EFFECTS[effect.type] then
			return false, where .. ": " .. selector .. " only works with HEAL, SHIELD and BUFF"
		end
		if
			(selector == Selector.LowestHpAllies or selector == Selector.LowestHpOtherAllies)
			and not isWhole(effect.count)
		then
			return false, where .. ": " .. selector .. " needs a whole count of at least 1"
		end
		if selector == Selector.LowestHpEnemyNearby and not isWhole(ability.nearbyRange) then
			return false, where .. ": LOWEST_HP_ENEMY_NEARBY needs the ability's nearbyRange"
		end
		local fields = table.clone(REQUIRED[effect.type])
		local ok, reason = validateFields(effect, where, fields)
		if not ok then
			return false, reason
		end
		ok, reason = validateCommon(effect, where)
		if not ok then
			return false, reason
		end
		for _, field in fields do
			for starLevel = 1, 3 do
				if type(valueAt(effect[field], starLevel)) ~= "number" then
					return false, string.format("%s: %s missing for %d-star", where, field, starLevel)
				end
			end
		end
		for starLevel = 1, 3 do
			if effect.type == Effect.Stun or effect.type == Effect.AreaStun then
				local duration = valueAt(effect.duration, starLevel)
				if duration > CombatConfig.maxStunSeconds then
					return false,
						string.format(
							"%s: %d-star stun lasts %gs, more than the %gs limit",
							where,
							starLevel,
							duration,
							CombatConfig.maxStunSeconds
						)
				end
			end
			if effect.type == Effect.AreaStun then
				local radius = valueAt(effect.radius, starLevel)
				if radius ~= 1 and radius ~= 2 then
					return false, where .. ": an AREA_STUN radius must be 1 or 2"
				end
			end
		end
	end
	return true
end

-- Checks that an ability uses only known effects, selectors and stats, that every value it needs
-- exists for star levels 1-3, that no stun lasts longer than CombatConfig.maxStunSeconds, and its
-- ability-level options. Returns true, or false and a reason.
function Abilities.validate(ability): (boolean, string?)
	if type(ability) ~= "table" or type(ability.name) ~= "string" or type(ability.effects) ~= "table" then
		return false, "an ability needs a name and a list of effects"
	end
	local name = ability.name
	if ability.formOnly ~= nil and ability.formOnly ~= true then
		return false, name .. ": formOnly must be true or omitted"
	end
	if #ability.effects == 0 and not ability.formOnly then
		return false, name .. " has no effects"
	end
	if ability.formOnly and #ability.effects > 0 then
		return false, name .. ": a formOnly ability has no effects"
	end
	if ability.castTime ~= nil and (type(ability.castTime) ~= "number" or ability.castTime < 0) then
		return false, name .. ": castTime must be a number of seconds, 0 or more"
	end
	if ability.resetAttackTimer ~= nil and type(ability.resetAttackTimer) ~= "boolean" then
		return false, name .. ": resetAttackTimer must be true or false"
	end
	if ability.selfStun ~= nil then
		if not perStarNumber(ability.selfStun) then
			return false, name .. ": selfStun must be seconds for each star level"
		end
		for starLevel = 1, 3 do
			local seconds = valueAt(ability.selfStun, starLevel)
			if seconds <= 0 or seconds > CombatConfig.maxStunSeconds then
				return false, name .. ": selfStun must be above 0 and at most the stun limit"
			end
		end
	end
	if ability.nearbyRange ~= nil and not isWhole(ability.nearbyRange) then
		return false, name .. ": nearbyRange must be a whole number of at least 1"
	end
	if ability.clusterRadius ~= nil and not isWhole(ability.clusterRadius) then
		return false, name .. ": clusterRadius must be a whole number of at least 1"
	end
	local ok, reason = validateEffects(name, ability.effects, ability)
	if not ok then
		return false, reason
	end
	local followUp = ability.onTargetKilled
	if followUp ~= nil then
		if type(followUp) ~= "table" or type(followUp.effects) ~= "table" or #followUp.effects == 0 then
			return false, name .. ": onTargetKilled needs effects"
		end
		if not perStarNumber(followUp.window) then
			return false, name .. ": onTargetKilled needs a window in seconds for each star level"
		end
		if not isWhole(followUp.maxRepeats) then
			return false, name .. ": onTargetKilled needs a whole maxRepeats of at least 1"
		end
		ok, reason = validateEffects(name .. " follow-up", followUp.effects, ability)
		if not ok then
			return false, reason
		end
	end
	return true
end

-- Checks a unit type's passive data: `aura` and `attackStacks` (see Battle.tickAuras and
-- CombatSim). nil for either is fine. Returns true, or false and a reason.
--   aura          { radius, interval, damageType, amount (per tick, per star), buffs? = {
--                 { stat, flatPerEnemy (per star) } } }
--   attackStacks  { max, castAtMax? }: basic attacks on the same target build stacks up to max
--                 (a new target starts over); castAtMax = true casts at max stacks instead of on
--                 mana (the mana bar shows the stacks). Casting spends the stacks.
function Abilities.validateUnit(stats): (boolean, string?)
	local aura = stats.aura
	if aura ~= nil then
		if type(aura) ~= "table" or not isWhole(aura.radius) then
			return false, "aura needs a whole radius of at least 1"
		end
		if type(aura.interval) ~= "number" or aura.interval <= 0 then
			return false, "aura needs a positive interval"
		end
		if not knownDamageType(aura.damageType) or not perStarNumber(aura.amount) then
			return false, "aura needs a damageType and an amount for each star level"
		end
		for index, buff in aura.buffs or {} do
			if not Battle.StatFields[buff.stat] or not perStarNumber(buff.flatPerEnemy) then
				return false,
					string.format("aura buff %d needs a known stat and flatPerEnemy for each star level", index)
			end
		end
	end
	local stacks = stats.attackStacks
	if stacks ~= nil then
		if type(stacks) ~= "table" or not isWhole(stacks.max) then
			return false, "attackStacks needs a whole max of at least 1"
		end
		if stacks.castAtMax ~= nil and type(stacks.castAtMax) ~= "boolean" then
			return false, "attackStacks castAtMax must be true or false"
		end
		if stacks.castAtMax and not stats.maxMana then
			return false, "attackStacks castAtMax needs maxMana (the bar that shows the stacks)"
		end
	end
	return true
end

-- Casts `caster`'s ability: spends its mana (and attack stacks), resolves targets, applies the
-- effects in order and starts the cast time. Then the ability-level options apply (attack timer
-- reset, self-stun, follow-up window), the cast hooks run, and the caster's form may change
-- (ON_CAST trigger).
function Abilities.cast(battle, caster)
	local ability = caster.ability
	local starLevel = caster.starLevel
	caster.mana = 0
	caster.castEndsTick = battle.tick + Battle.seconds(battle, ability.castTime or CombatConfig.castTime)
	caster.lastCastTick = battle.tick
	caster.casts = (caster.casts or 0) + 1
	Battle.emit(battle, { kind = "Cast", unit = caster.index, ability = ability.name })
	local context = newContext(1, ability.name, false, caster.stacks or 0)
	applyAbility(battle, caster, ability, starLevel, context)
	if caster.stats.attackStacks then
		caster.stacks = 0
		caster.stackTarget = nil
	end
	if ability.resetAttackTimer then
		caster.attackCooldown = 0
	end
	if ability.selfStun and not caster.dead then
		Battle.stun(battle, caster, caster, valueAt(ability.selfStun, starLevel))
	end
	local followUp = ability.onTargetKilled
	if followUp then
		local repeat_ = {
			name = ability.name,
			effects = followUp.effects,
			nearbyRange = ability.nearbyRange,
			clusterRadius = ability.clusterRadius,
		}
		caster.followUp = {
			untilTick = battle.tick + Battle.seconds(battle, valueAt(followUp.window, starLevel)),
			remaining = followUp.maxRepeats,
			run = function()
				Battle.emit(battle, { kind = "FollowUp", unit = caster.index, ability = ability.name })
				applyAbility(battle, caster, repeat_, starLevel, newContext(1, ability.name, false, 0))
			end,
		}
	end
	Battle.runHooks(battle, "cast", caster)
	Battle.checkForm(battle, caster, Forms.Hook.Cast)
end

return Abilities
