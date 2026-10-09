-- Every combat formula in one place (docs/design/combat-and-roster.md section 1): damage types and
-- resistances, rounding, crits, ability power scaling and mana gained from damage.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local CombatConfig = if script then require(script.Parent.CombatConfig) else require("./CombatConfig")

local CombatMath = {}

CombatMath.DamageType = table.freeze({
	Physical = "PHYSICAL", -- reduced by Armor
	Magic = "MAGIC", -- reduced by Magic Resistance
	True = "TRUE", -- reduced by neither
})

-- Fraction of damage taken through `resistance` (0 or more): 100 / (100 + resistance).
function CombatMath.resistanceMultiplier(resistance: number): number
	return 100 / (100 + resistance)
end

-- Final damage of a hit after resistance, rounded to the nearest integer, at least 1 for any hit
-- with positive raw damage.
function CombatMath.finalDamage(raw: number, damageType: string, armor: number, magicResist: number): number
	if raw <= 0 then
		return 0
	end
	local resistance = 0
	if damageType == CombatMath.DamageType.Physical then
		resistance = armor
	elseif damageType == CombatMath.DamageType.Magic then
		resistance = magicResist
	end
	return math.max(1, math.round(raw * CombatMath.resistanceMultiplier(resistance)))
end

-- Raw damage of a critical basic attack, with the attacker's crit damage multiplier
-- (CombatConfig.critDamage when omitted; traits can raise it).
function CombatMath.critRawDamage(raw: number, multiplier: number?): number
	return raw * (multiplier or CombatConfig.critDamage)
end

-- Listed magic damage, heal or shield value scaled by ability power.
function CombatMath.scaleByAbilityPower(listed: number, abilityPower: number): number
	return listed * abilityPower / CombatConfig.baseAbilityPower
end

-- Mana a unit gains from losing `healthLost` of its `maxHealth` in one damage event (shield
-- absorption does not count).
function CombatMath.manaFromDamage(healthLost: number, maxHealth: number): number
	if healthLost <= 0 then
		return 0
	end
	local fromDamage = CombatConfig.manaPerPercentHealthLost * healthLost / maxHealth * 100
	return math.min(CombatConfig.maxManaPerDamage, fromDamage)
end

return CombatMath
