-- A short plain-language description of a unit's ability, generated from its data (UnitConfig
-- ability effects), since the game has no written ability descriptions yet. Per-star numbers show
-- as "1-star/2-star/3-star". Effects it does not know are left out. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UnitConfig"))

local AbilityText = {}

local TARGETS = {
	SELF = "itself",
	CURRENT_TARGET = "its target",
}

local function amount(value: any): string
	if type(value) == "table" then
		local parts = {}
		for _, entry in value do
			table.insert(parts, tostring(entry))
		end
		return table.concat(parts, "/")
	end
	return tostring(value)
end

local function words(value: any): string
	if type(value) ~= "string" then
		return "enemies"
	end
	return TARGETS[value] or string.lower((string.gsub(value, "_", " ")))
end

local function damageType(effect): string
	return if effect.damageType then string.lower(effect.damageType) .. " " else ""
end

local function seconds(value: any): string
	return if value then " for " .. amount(value) .. "s" else ""
end

local function describe(effect): string?
	local kind = effect.type
	if kind == "DAMAGE" then
		return string.format("Deals %s %sdamage to %s", amount(effect.amount), damageType(effect), words(effect.target))
	elseif kind == "AREA_DAMAGE" then
		local where = if effect.shape == "LINE"
			then "in a line"
			elseif effect.shape == "CONE" then "in a cone"
			else string.format("within %s hexes of %s", amount(effect.radius or 1), words(effect.center))
		return string.format("Deals %s %sdamage %s", amount(effect.amount), damageType(effect), where)
	elseif kind == "HEAL" then
		return string.format("Heals %s for %s", words(effect.target), amount(effect.amount))
	elseif kind == "SHIELD" then
		return string.format("Shields %s for %s%s", words(effect.target), amount(effect.amount), seconds(effect.duration))
	elseif kind == "STUN" then
		return string.format("Stuns %s%s", words(effect.target), seconds(effect.duration))
	elseif kind == "AREA_STUN" then
		return string.format("Stuns enemies within %s hexes%s", amount(effect.radius or 1), seconds(effect.duration))
	elseif kind == "BUFF" then
		local size = if effect.percent then "+" .. amount(effect.percent) .. "%" else "+" .. amount(effect.flat)
		return string.format("Gives %s %s %s%s", words(effect.target), size, words(effect.stat), seconds(effect.duration))
	elseif kind == "DEBUFF" then
		local size = if effect.percent then " (" .. amount(effect.percent) .. "%)" else ""
		return string.format("Applies %s to %s%s%s", words(effect.status), words(effect.target), size, seconds(effect.duration))
	elseif kind == "DASH" then
		return string.format("Dashes toward %s", words(effect.target))
	elseif kind == "BOUNCE" then
		return string.format("Bounces %s times for %s %sdamage", amount(effect.count), amount(effect.amount), damageType(effect))
	elseif kind == "DAMAGE_OVER_TIME" then
		return string.format("Deals %s %sdamage every second%s", amount(effect.amount), damageType(effect), seconds(effect.duration))
	elseif kind == "SUMMON" then
		return string.format("Summons %s helper%s", amount(effect.count or 1), if effect.count == 1 then "" else "s")
	elseif kind == "KNOCKBACK" then
		return string.format("Knocks back %s", words(effect.target))
	elseif kind == "PULL" then
		return string.format("Pulls %s", words(effect.target))
	end
	return nil
end

-- The description for a unit type: its ability's effects in order, then its forms, if any.
function AbilityText.of(unitType: string): string
	local unit = UnitConfig[unitType]
	if not unit then
		return ""
	end
	local sentences = {}
	local ability = unit.ability
	if ability then
		if ability.formOnly then
			table.insert(sentences, "Changes form")
		end
		for _, effect in ability.effects or {} do
			local sentence = describe(effect)
			if sentence then
				table.insert(sentences, sentence)
			end
		end
	end
	if unit.forms then
		local names = {}
		for _, form in unit.forms do
			table.insert(names, form.name)
		end
		table.insert(sentences, "Forms: " .. table.concat(names, " → "))
	end
	if #sentences == 0 then
		return "A special ability."
	end
	return table.concat(sentences, ". ") .. "."
end

return AbilityText
