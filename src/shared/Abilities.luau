-- Generic ability interpreter (docs/design/combat-and-roster.md section 2). An ability is data:
--
--   { name = "Iron Pulse", effects = { effect, effect, ... } }
--
-- Each effect has a `type` (one of Abilities.Effect) and names a target selector (one of
-- Abilities.Selector) in `target`, or in `center` for AREA_DAMAGE. Values that change with star
-- level are lists of three numbers ({ 1-star, 2-star, 3-star }); constants may be plain numbers.
--
--   DAMAGE       target, damageType (CombatMath.DamageType), amount
--   AREA_DAMAGE  center, radius, damageType, amount   -- every enemy within radius of the center hex
--   HEAL         target, amount
--   SHIELD       target, amount, duration
--   STUN         target, duration
--   BUFF         target, stat (AD, AP, AttackSpeed, Armor, MR, MoveSpeed), flat or percent, duration
--   DASH         target, distance, mode (OFFENSIVE or DEFENSIVE; OFFENSIVE if omitted)
--
-- Casting: when a unit's mana is full and it is free to act, it casts. Every selector the ability
-- uses is resolved once, before any effect, so effects naming the same selector share one target.
-- The effects then apply immediately, in listed order, and the unit cannot act for the cast time.
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
})

Abilities.Selector = table.freeze({
	Self = "SELF",
	CurrentTarget = "CURRENT_TARGET",
	LowestHpAlly = "LOWEST_HP_ALLY",
	NearestEnemy = "NEAREST_ENEMY",
	FarthestEnemy = "FARTHEST_ENEMY",
	HighestAdEnemy = "HIGHEST_AD_ENEMY",
})

Abilities.DashMode = table.freeze({
	Offensive = "OFFENSIVE",
	Defensive = "DEFENSIVE",
})

local Effect = Abilities.Effect
local Selector = Abilities.Selector

-- A per-star value: a list indexed by star level, or a constant.
local function valueAt(value: any, starLevel: number): number
	if type(value) == "table" then
		return value[starLevel]
	end
	return value
end

local function selectorOf(effect): string
	return effect.target or effect.center
end

-- Target selectors. Each returns a living unit or nil. Ties are broken by the battle's seeded random
-- generator.
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
		-- Lowest current health percentage; any living ally on the field, the caster included.
		return Battle.pickBest(battle, Battle.alliesOf(battle, caster), function(ally)
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

local function scaledAmount(battle, caster, effect, starLevel: number): number
	local listed = valueAt(effect.amount, starLevel)
	local scales = effect.type == Effect.Heal
		or effect.type == Effect.Shield
		or effect.damageType == CombatMath.DamageType.Magic
	if scales then
		return CombatMath.scaleByAbilityPower(listed, Battle.stat(battle, caster, "AP"))
	end
	return listed
end

local function alive(unit): boolean
	return unit ~= nil and not unit.dead
end

local APPLY = {
	[Effect.Damage] = function(battle, caster, effect, target, starLevel)
		if alive(target) then
			local amount = scaledAmount(battle, caster, effect, starLevel)
			Battle.damage(battle, caster, target, amount, effect.damageType, "Damage")
		end
	end,
	[Effect.AreaDamage] = function(battle, caster, effect, center, starLevel)
		-- Uses the center unit's hex even if that unit died earlier in this cast.
		if center == nil then
			return
		end
		local amount = scaledAmount(battle, caster, effect, starLevel)
		local radius = valueAt(effect.radius, starLevel)
		for _, enemy in Battle.enemiesOf(battle, caster) do
			if HexGrid.distance(center.column, center.row, enemy.column, enemy.row) <= radius then
				Battle.damage(battle, caster, enemy, amount, effect.damageType, "Damage")
			end
		end
	end,
	[Effect.Heal] = function(battle, caster, effect, target, starLevel)
		if alive(target) then
			Battle.heal(battle, caster, target, scaledAmount(battle, caster, effect, starLevel))
		end
	end,
	[Effect.Shield] = function(battle, caster, effect, target, starLevel)
		if alive(target) then
			local amount = scaledAmount(battle, caster, effect, starLevel)
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
			Battle.buff(battle, caster, target, effect.stat, flat, percent, valueAt(effect.duration, starLevel))
		end
	end,
	[Effect.Dash] = function(battle, caster, effect, target, starLevel)
		local mode = effect.mode or Abilities.DashMode.Offensive
		local column, row = dashDestination(battle, caster, target, valueAt(effect.distance, starLevel), mode)
		if column and row then
			Battle.relocate(battle, caster, column, row)
			Battle.emit(battle, { kind = "Dash", unit = caster.index, column = column, row = row })
		end
	end,
}

-- Checks that an ability uses only known effects, selectors and stats, and that every value it
-- needs exists for star levels 1-3. Returns true, or false and a reason.
function Abilities.validate(ability): (boolean, string?)
	if type(ability) ~= "table" or type(ability.name) ~= "string" or type(ability.effects) ~= "table" then
		return false, "an ability needs a name and a list of effects"
	end
	if #ability.effects == 0 then
		return false, ability.name .. " has no effects"
	end
	local required = {
		[Effect.Damage] = { "amount" },
		[Effect.AreaDamage] = { "amount", "radius" },
		[Effect.Heal] = { "amount" },
		[Effect.Shield] = { "amount", "duration" },
		[Effect.Stun] = { "duration" },
		[Effect.Buff] = { "duration" },
		[Effect.Dash] = { "distance" },
	}
	for index, effect in ability.effects do
		local where = string.format("%s effect %d", ability.name, index)
		if not APPLY[effect.type] then
			return false, where .. ": unknown effect " .. tostring(effect.type)
		end
		if not SELECTORS[selectorOf(effect)] then
			return false, where .. ": unknown target selector " .. tostring(selectorOf(effect))
		end
		local fields = table.clone(required[effect.type])
		if effect.type == Effect.Damage or effect.type == Effect.AreaDamage then
			local known = false
			for _, damageType in CombatMath.DamageType do
				known = known or effect.damageType == damageType
			end
			if not known then
				return false, where .. ": unknown damage type " .. tostring(effect.damageType)
			end
		elseif effect.type == Effect.Buff then
			if not Battle.StatFields[effect.stat] then
				return false, where .. ": unknown buff stat " .. tostring(effect.stat)
			end
			if effect.flat == nil and effect.percent == nil then
				return false, where .. ": a buff needs flat or percent"
			end
			table.insert(fields, if effect.flat ~= nil then "flat" else "percent")
		elseif effect.type == Effect.Dash and effect.mode ~= nil then
			if effect.mode ~= Abilities.DashMode.Offensive and effect.mode ~= Abilities.DashMode.Defensive then
				return false, where .. ": unknown dash mode " .. tostring(effect.mode)
			end
		end
		for _, field in fields do
			for starLevel = 1, 3 do
				if type(valueAt(effect[field], starLevel)) ~= "number" then
					return false, string.format("%s: %s missing for %d-star", where, field, starLevel)
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

	local chosen = {}
	for _, effect in ability.effects do
		local selector = selectorOf(effect)
		if chosen[selector] == nil then
			chosen[selector] = SELECTORS[selector](battle, caster) or false
		end
	end
	for _, effect in ability.effects do
		local target = chosen[selectorOf(effect)] or nil
		APPLY[effect.type](battle, caster, effect, target, caster.starLevel)
	end
end

return Abilities
