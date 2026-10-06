-- Generic ability interpreter (docs/design/combat-and-roster.md section 2, with the engine v2
-- building blocks from docs/design/revamp-structure.md). An ability is data:
--
--   { name = "Iron Pulse", effects = { effect, effect, ... } }
--
-- Each effect has a `type` (one of Abilities.Effect) and names a target selector (one of
-- Abilities.Selector) in `target`, or in `center` for area effects. SUMMON needs no selector.
-- Values that change with star level are lists of three numbers ({ 1-star, 2-star, 3-star });
-- constants may be plain numbers.
--
--   DAMAGE            target, damageType (CombatMath.DamageType), amount
--   AREA_DAMAGE       center, radius, damageType, amount   -- every enemy within radius of the center hex
--   HEAL              target, amount
--   SHIELD            target, amount, duration
--   STUN              target, duration (at most CombatConfig.maxStunSeconds)
--   BUFF              target, stat (AD, AP, AttackSpeed, Armor, MR, MoveSpeed, MaxHealth), flat or
--                     percent, duration; optional stackPerCast = true with maxStacks = N: each cast
--                     adds one stack up to N and refreshes the duration (Battle.buff)
--   DASH              target, distance, mode (OFFENSIVE or DEFENSIVE; OFFENSIVE if omitted),
--                     setsCurrentTarget (optional; true makes the dash's target the caster's current
--                     target after the dash, whether or not the caster moved)
--   AREA_STUN         center, radius (1 or 2), duration (at most CombatConfig.maxStunSeconds): stuns
--                     every living enemy within radius of the center hex when it resolves
--   SUMMON            count, duration, healthPercent, attackDamagePercent, armorPercent,
--                     magicResistPercent, attackSpeedPercent (of the caster's current stats), range,
--                     moveSpeed: places summons on the free cells nearest the caster (Battle.summon);
--                     ones that cannot be placed, or would pass CombatConfig.maxEntitiesPerSide, are
--                     skipped
--   PULL              target: moves the enemy to the free cell next to the caster nearest it
--                     (Battle.pull); it becomes the caster's current target even if it could not move
--   DAMAGE_OVER_TIME  target, or center with radius; damageType, amount (per tick), interval,
--                     duration (seconds): Battle.damageOverTime on the target or on every enemy in
--                     the radius
--   COPY              target: immediately applies the target's ability as if the caster had cast it
--                     (caster's stats and star level), with DAMAGE, AREA_DAMAGE, HEAL, SHIELD and
--                     DAMAGE_OVER_TIME amounts multiplied by CombatConfig.copyPowerByCost for the
--                     copied unit's cost. A COPY inside a copied ability is ignored. Copying a unit
--                     without an ability (a summon) does nothing.
--
-- Casting: when a unit's mana is full and it is free to act, it casts. Every selector the ability
-- uses is resolved once, before any effect, so effects naming the same selector share one target.
-- The effects then apply immediately, in listed order, and the unit cannot act for the cast time.
-- ALL_ALLIES selects several units; the effect applies to each (HEAL, SHIELD and BUFF only).
-- Magic damage, heals and shields scale with the caster's ability power; nothing else does.
-- Abilities cannot crit. Abilities have unlimited range.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local Battle = if script then require(script.Parent.Battle) else require("./Battle")
local CombatConfig = if script then require(script.Parent.CombatConfig) else require("./CombatConfig")
local CombatMath = if script then require(script.Parent.CombatMath) else require("./CombatMath")
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
})

Abilities.DashMode = table.freeze({
	Offensive = "OFFENSIVE",
	Defensive = "DEFENSIVE",
})

local Effect = Abilities.Effect
local Selector = Abilities.Selector

-- Selectors that pick several units, and the effects that accept them.
local MULTI_SELECTORS = { [Selector.AllAllies] = true }
local MULTI_TARGET_EFFECTS = { [Effect.Heal] = true, [Effect.Shield] = true, [Effect.Buff] = true }

-- A per-star value: a list indexed by star level, or a constant.
local function valueAt(value: any, starLevel: number): number
	if type(value) == "table" then
		return value[starLevel]
	end
	return value
end

local function selectorOf(effect): string?
	return effect.target or effect.center
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

-- Target selectors. Each returns a living unit or nil, except ALL_ALLIES, which returns
-- { many = { units } }. Ties are broken by the battle's seeded random generator. Ally selectors
-- never pick summons.
local SELECTORS = {
	[Selector.Self] = function(_battle, caster)
		return caster
	end,
	[Selector.CurrentTarget] = function(battle, caster)
		if caster.target and not caster.target.dead then
			return caster.target
		end
		caster.target = Battle.pickBest(battle, Battle.enemiesOf(battle, caster), function(enemy)
			return -Battle.distance(caster, enemy)
		end)
		return caster.target
	end,
	[Selector.LowestHpAlly] = function(battle, caster)
		-- Lowest current health percentage; any living deployed ally, the caster included.
		return Battle.pickBest(battle, deployedAllies(battle, caster), function(ally)
			return -ally.health / ally.maxHealth
		end)
	end,
	[Selector.NearestEnemy] = function(battle, caster)
		return Battle.pickBest(battle, Battle.enemiesOf(battle, caster), function(enemy)
			return -Battle.distance(caster, enemy)
		end)
	end,
	[Selector.FarthestEnemy] = function(battle, caster)
		return Battle.pickBest(battle, Battle.enemiesOf(battle, caster), function(enemy)
			return Battle.distance(caster, enemy)
		end)
	end,
	[Selector.HighestAdEnemy] = function(battle, caster)
		-- Highest current attack damage; ties go to the nearer enemy.
		return Battle.pickBest(battle, Battle.enemiesOf(battle, caster), function(enemy)
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

-- How the current ability is being applied: `power` multiplies amounts (COPY), `abilityName`
-- keys damage over time, and `nested` is true inside a copied ability.
type Context = { power: number, abilityName: string, nested: boolean }

local function scaledAmount(battle, caster, effect, starLevel: number, context: Context): number
	local listed = valueAt(effect.amount, starLevel)
	local scales = effect.type == Effect.Heal
		or effect.type == Effect.Shield
		or effect.damageType == CombatMath.DamageType.Magic
	local amount = if scales then CombatMath.scaleByAbilityPower(listed, Battle.stat(battle, caster, "AP")) else listed
	return amount * context.power
end

local function alive(unit): boolean
	return unit ~= nil and not unit.dead
end

-- Living enemies of `caster` within `radius` of `center`'s hex (the hex is used even if the center
-- unit died earlier in this cast).
local function enemiesWithin(battle, caster, center, radius: number)
	local result = {}
	for _, enemy in Battle.enemiesOf(battle, caster) do
		if HexGrid.distance(center.column, center.row, enemy.column, enemy.row) <= radius then
			table.insert(result, enemy)
		end
	end
	return result
end

local applyAbility -- defined below; COPY calls it

local APPLY = {
	[Effect.Damage] = function(battle, caster, effect, target, starLevel, context)
		if alive(target) then
			local amount = scaledAmount(battle, caster, effect, starLevel, context)
			Battle.damage(battle, caster, target, amount, effect.damageType, "Damage")
		end
	end,
	[Effect.AreaDamage] = function(battle, caster, effect, center, starLevel, context)
		if center == nil then
			return
		end
		local amount = scaledAmount(battle, caster, effect, starLevel, context)
		for _, enemy in enemiesWithin(battle, caster, center, valueAt(effect.radius, starLevel)) do
			Battle.damage(battle, caster, enemy, amount, effect.damageType, "Damage")
		end
	end,
	[Effect.Heal] = function(battle, caster, effect, target, starLevel, context)
		if alive(target) then
			Battle.heal(battle, caster, target, scaledAmount(battle, caster, effect, starLevel, context))
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
				valueAt(effect.duration, starLevel),
				effect.stackPerCast,
				effect.maxStacks
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
	[Effect.AreaStun] = function(battle, caster, effect, center, starLevel)
		if center == nil then
			return
		end
		local radius = valueAt(effect.radius, starLevel)
		Battle.emit(battle, {
			kind = "AreaStun",
			unit = caster.index,
			column = center.column,
			row = center.row,
			radius = radius,
		})
		for _, enemy in enemiesWithin(battle, caster, center, radius) do
			Battle.stun(battle, caster, enemy, valueAt(effect.duration, starLevel))
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
			duration = valueAt(effect.duration, starLevel),
		}
		for _ = 1, valueAt(effect.count, starLevel) do
			Battle.summon(battle, caster, spec)
		end
	end,
	[Effect.Pull] = function(battle, caster, _effect, target)
		if alive(target) then
			Battle.pull(battle, caster, target)
			caster.target = target
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
		for _, victim in victims do
			Battle.damageOverTime(
				battle,
				caster,
				victim,
				key,
				amount,
				effect.damageType,
				valueAt(effect.interval, starLevel),
				valueAt(effect.duration, starLevel)
			)
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
		applyAbility(battle, caster, target.ability, caster.starLevel, {
			power = context.power * power,
			abilityName = target.ability.name,
			nested = true,
		})
	end,
}

-- Resolves an ability's selectors and applies its effects for `caster`.
function applyAbility(battle, caster, ability, starLevel: number, context: Context)
	local chosen = {}
	for _, effect in ability.effects do
		local selector = selectorOf(effect)
		if selector and chosen[selector] == nil then
			chosen[selector] = SELECTORS[selector](battle, caster) or false
		end
	end
	for _, effect in ability.effects do
		if not (context.nested and effect.type == Effect.Copy) then
			local selector = selectorOf(effect)
			local target = if selector then chosen[selector] or nil else nil
			if target and target.many then
				for _, each in target.many do
					APPLY[effect.type](battle, caster, effect, each, starLevel, context)
				end
			else
				APPLY[effect.type](battle, caster, effect, target, starLevel, context)
			end
		end
	end
end

-- Required numeric fields per effect type (each must exist for star levels 1-3).
local REQUIRED = {
	[Effect.Damage] = { "amount" },
	[Effect.AreaDamage] = { "amount", "radius" },
	[Effect.Heal] = { "amount" },
	[Effect.Shield] = { "amount", "duration" },
	[Effect.Stun] = { "duration" },
	[Effect.Buff] = { "duration" },
	[Effect.Dash] = { "distance" },
	[Effect.AreaStun] = { "duration", "radius" },
	[Effect.Summon] = {
		"count",
		"duration",
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
}

local function knownDamageType(damageType): boolean
	for _, each in CombatMath.DamageType do
		if damageType == each then
			return true
		end
	end
	return false
end

-- Checks that an ability uses only known effects, selectors and stats, that every value it needs
-- exists for star levels 1-3, and that no stun lasts longer than CombatConfig.maxStunSeconds.
-- Returns true, or false and a reason.
function Abilities.validate(ability): (boolean, string?)
	if type(ability) ~= "table" or type(ability.name) ~= "string" or type(ability.effects) ~= "table" then
		return false, "an ability needs a name and a list of effects"
	end
	if #ability.effects == 0 then
		return false, ability.name .. " has no effects"
	end
	for index, effect in ability.effects do
		local where = string.format("%s effect %d", ability.name, index)
		if not APPLY[effect.type] then
			return false, where .. ": unknown effect " .. tostring(effect.type)
		end
		local selector = selectorOf(effect)
		if effect.type == Effect.Summon then
			if selector ~= nil then
				return false, where .. ": SUMMON takes no target selector"
			end
		elseif not SELECTORS[selector] then
			return false, where .. ": unknown target selector " .. tostring(selector)
		end
		if selector and MULTI_SELECTORS[selector] and not MULTI_TARGET_EFFECTS[effect.type] then
			return false, where .. ": " .. selector .. " only works with HEAL, SHIELD and BUFF"
		end
		local fields = table.clone(REQUIRED[effect.type])
		if effect.type == Effect.Damage or effect.type == Effect.AreaDamage or effect.type == Effect.DamageOverTime then
			if not knownDamageType(effect.damageType) then
				return false, where .. ": unknown damage type " .. tostring(effect.damageType)
			end
			if effect.type == Effect.DamageOverTime and effect.radius ~= nil then
				table.insert(fields, "radius")
			end
		elseif effect.type == Effect.Buff then
			if not Battle.StatFields[effect.stat] then
				return false, where .. ": unknown buff stat " .. tostring(effect.stat)
			end
			if effect.flat == nil and effect.percent == nil then
				return false, where .. ": a buff needs flat or percent"
			end
			table.insert(fields, if effect.flat ~= nil then "flat" else "percent")
			if effect.stackPerCast ~= nil and effect.stackPerCast ~= true then
				return false, where .. ": stackPerCast must be true or omitted"
			end
			if effect.stackPerCast then
				local maxStacks = effect.maxStacks
				if type(maxStacks) ~= "number" or maxStacks < 1 or maxStacks ~= math.floor(maxStacks) then
					return false, where .. ": a stacking buff needs a whole maxStacks of at least 1"
				end
			elseif effect.maxStacks ~= nil then
				return false, where .. ": maxStacks needs stackPerCast"
			end
		elseif effect.type == Effect.Dash then
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

-- Casts `caster`'s ability: spends its mana, resolves targets, applies the effects in order and
-- starts the cast time.
function Abilities.cast(battle, caster)
	local ability = caster.ability
	caster.mana = 0
	caster.castEndsTick = battle.tick + Battle.seconds(battle, CombatConfig.castTime)
	Battle.emit(battle, { kind = "Cast", unit = caster.index, ability = ability.name })
	applyAbility(battle, caster, ability, caster.starLevel, { power = 1, abilityName = ability.name, nested = false })
end

return Abilities
