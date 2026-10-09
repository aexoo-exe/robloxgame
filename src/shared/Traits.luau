-- Trait counting and bonuses. Membership is derived from each character's `origin` and `classes`
-- in UnitConfig; breakpoints and effects are in TraitConfig. Every function takes an optional
-- trait config (TraitConfig if omitted), so tests can use their own; only traits the config
-- defines are counted.
--   * A trait's count is the number of different characters with it among the units passed in
--     (callers pass only units placed on the board, never the bench). Copies count once.
--   * The highest breakpoint reached applies; lower ones are replaced, not added.
--   * Bonuses from different traits stack: flat bonuses add together and percent bonuses add
--     together, per stat. MEMBERS effects go to every placed unit with the trait (copies included),
--     ALL_ALLIES effects to every placed unit.
-- Bonuses are plain data; CombatSim applies them at combat start (Battle.applyStartBonus).
-- Effects during the fight (marks, takedown boosts, meters, dummies, bonds) come from
-- Traits.fightSetup, which CombatSim hands to TraitCombat.
-- Bonds (BondConfig) are active when both their characters are placed.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local BondConfig = if script then require(script.Parent.BondConfig) else require("./BondConfig")
local TraitConfig = if script then require(script.Parent.TraitConfig) else require("./TraitConfig")
local UnitConfig = if script then require(script.Parent.UnitConfig) else require("./UnitConfig")

local Traits = {}

-- A unit's combat-start bonus: summed stat changes, shields to apply and starting mana.
export type Bonus = {
	stats: { [string]: { flat: number, percent: number } },
	shields: { { amount: number, duration: number, source: string } },
	mana: number,
}

-- One side's traits and bonds for TraitCombat: each active trait's level, params and members (unit
-- ids), and each active bond with its members.
export type FightSetup = {
	traits: { [string]: { level: number, params: any?, members: { [string]: boolean } } },
	bonds: { { bond: any, members: { [string]: boolean } } },
}

-- One trait on a board, for display and reports.
export type TraitState = {
	name: string,
	kind: string, -- "origin" or "class"
	count: number, -- different characters with the trait
	level: number, -- index of the highest breakpoint reached (0 if none)
	reached: number?, -- member count of that breakpoint
	nextCount: number?, -- member count of the next breakpoint, nil at the top
	active: boolean,
}

-- Trait names of one character: its origin, then its classes. Unit types that are not
-- characters (creeps, bosses) have none.
function Traits.traitsOf(unitType: string): { string }
	local unit = UnitConfig[unitType]
	if not unit then
		return {}
	end
	local names = { unit.origin }
	for _, class in unit.classes do
		table.insert(names, class)
	end
	return names
end

-- Members of each trait, derived from UnitConfig: trait name -> sorted character names.
local members: { [string]: { string } } = {}
for name in UnitConfig do
	for _, trait in Traits.traitsOf(name) do
		members[trait] = members[trait] or {}
		table.insert(members[trait], name)
	end
end
for _, list in members do
	table.sort(list)
end
Traits.members = members

-- Different characters per configured trait among `units` (each with a unitType).
function Traits.count(units: { any }, config: { [string]: any }?): { [string]: number }
	config = config or TraitConfig
	local seen = {}
	local counts = {}
	for _, unit in units do
		if not seen[unit.unitType] then
			seen[unit.unitType] = true
			for _, trait in Traits.traitsOf(unit.unitType) do
				if (config :: any)[trait] then
					counts[trait] = (counts[trait] or 0) + 1
				end
			end
		end
	end
	return counts
end

-- Index of the highest breakpoint of `trait` reached with `count` members (0 if none).
function Traits.levelFor(trait: string, count: number, config: { [string]: any }?): number
	config = config or TraitConfig
	local level = 0
	for index, breakpoint in (config :: any)[trait].breakpoints do
		if count >= breakpoint.count then
			level = index
		end
	end
	return level
end

-- Every trait present among `units`: active ones first (most members first), then partial ones.
function Traits.summary(units: { any }, config: { [string]: any }?): { TraitState }
	config = config or TraitConfig
	local states = {}
	for trait, count in Traits.count(units, config) do
		local breakpoints = (config :: any)[trait].breakpoints
		local level = Traits.levelFor(trait, count, config)
		table.insert(states, {
			name = trait,
			kind = (config :: any)[trait].kind,
			count = count,
			level = level,
			reached = if level > 0 then breakpoints[level].count else nil,
			nextCount = if breakpoints[level + 1] then breakpoints[level + 1].count else nil,
			active = level > 0,
		})
	end
	table.sort(states, function(a, b)
		if a.active ~= b.active then
			return a.active
		end
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.name < b.name
	end)
	return states
end

local function newBonus(): Bonus
	return { stats = {}, shields = {}, mana = 0 }
end

-- True if an effect with `target` reaches a unit, given whether it has the trait.
local function reaches(target: string, member: boolean): boolean
	if target == "ALL_ALLIES" then
		return true
	elseif target == "NON_MEMBERS" then
		return not member
	end
	return member
end

-- Combat-start bonuses for `units` (each with an id and a unitType): unit id -> Bonus. Units with
-- no bonus are left out.
function Traits.bonuses(units: { any }, config: { [string]: any }?): { [string]: Bonus }
	config = config or TraitConfig
	local counts = Traits.count(units, config)
	local result = {}
	local traitNames = {}
	for trait in counts do
		table.insert(traitNames, trait)
	end
	table.sort(traitNames) -- a fixed order, so shields are applied the same way every time

	for _, trait in traitNames do
		local level = Traits.levelFor(trait, counts[trait], config)
		if level > 0 then
			for _, effect in (config :: any)[trait].breakpoints[level].effects do
				for _, unit in units do
					local member = table.find(Traits.traitsOf(unit.unitType), trait) ~= nil
					if reaches(effect.target, member) then
						local bonus = result[unit.id] or newBonus()
						result[unit.id] = bonus
						if effect.type == "BUFF" then
							local stat = bonus.stats[effect.stat] or { flat = 0, percent = 0 }
							stat.flat += effect.flat or 0
							stat.percent += effect.percent or 0
							bonus.stats[effect.stat] = stat
						elseif effect.type == "SHIELD" then
							table.insert(
								bonus.shields,
								{ amount = effect.amount, duration = effect.duration, source = trait }
							)
						elseif effect.type == "MANA" then
							bonus.mana += effect.amount
						end
					end
				end
			end
		end
	end
	return result
end

-- Bonds (BondConfig) active among `units`: both characters placed. Returns the bond entries.
function Traits.bonds(units: { any }, bondConfig: { any }?): { any }
	local placed = {}
	for _, unit in units do
		placed[unit.unitType] = true
	end
	local active = {}
	for _, bond in bondConfig or BondConfig do
		if placed[bond.units[1]] and placed[bond.units[2]] then
			table.insert(active, bond)
		end
	end
	return active
end

-- The fight setup of one side (Traits.FightSetup) for TraitCombat: active traits with their
-- breakpoint's params and their members' unit ids, and active bonds with their members (every copy
-- of the two characters).
function Traits.fightSetup(units: { any }, config: { [string]: any }?, bondConfig: { any }?): FightSetup
	config = config or TraitConfig
	local counts = Traits.count(units, config)
	local setup = { traits = {}, bonds = {} }
	for trait, count in counts do
		local level = Traits.levelFor(trait, count, config)
		if level > 0 then
			local memberIds = {}
			for _, unit in units do
				if table.find(Traits.traitsOf(unit.unitType), trait) then
					memberIds[unit.id] = true
				end
			end
			setup.traits[trait] = {
				level = level,
				params = (config :: any)[trait].breakpoints[level].params,
				members = memberIds,
			}
		end
	end
	for _, bond in Traits.bonds(units, bondConfig) do
		local memberIds = {}
		for _, unit in units do
			if unit.unitType == bond.units[1] or unit.unitType == bond.units[2] then
				memberIds[unit.id] = true
			end
		end
		table.insert(setup.bonds, { bond = bond, members = memberIds })
	end
	return setup
end

-- Everything CombatSim needs for traits on both sides of a fight: startBonuses and traits params.
-- `pveSide2` leaves side 2 without traits (creeps and bosses).
function Traits.combatParams(side1: { any }, side2: { any }, pveSide2: boolean?)
	return { Traits.bonuses(side1), if pveSide2 then {} else Traits.bonuses(side2) }, {
		Traits.fightSetup(side1),
		if pveSide2 then { traits = {}, bonds = {} } else Traits.fightSetup(side2),
	}
end

local EFFECT_TYPES = { BUFF = true, SHIELD = true, MANA = true }
local TARGETS = { MEMBERS = true, ALL_ALLIES = true, NON_MEMBERS = true }

-- Checks a trait config's shape: kinds, ascending whole breakpoint counts, and known effects and
-- targets. `statFields` (Battle.StatFields) checks buff stats when given. Returns true, or false
-- and a reason.
function Traits.validate(config: { [string]: any }, statFields: { [string]: any }?): (boolean, string?)
	for name, trait in config do
		if trait.kind ~= "origin" and trait.kind ~= "class" then
			return false, name .. ": kind must be origin or class"
		end
		if type(trait.breakpoints) ~= "table" or #trait.breakpoints == 0 then
			return false, name .. ": needs breakpoints"
		end
		local last = 0
		for index, breakpoint in trait.breakpoints do
			local where = string.format("%s breakpoint %d", name, index)
			local count = breakpoint.count
			if type(count) ~= "number" or count ~= math.floor(count) or count <= last then
				return false, where .. ": counts must be whole and ascending"
			end
			last = count
			for _, effect in breakpoint.effects or {} do
				if not EFFECT_TYPES[effect.type] or not TARGETS[effect.target] then
					return false, where .. ": unknown effect or target"
				end
				if effect.type == "BUFF" then
					if statFields and not statFields[effect.stat] then
						return false, where .. ": unknown stat " .. tostring(effect.stat)
					end
					if effect.flat == nil and effect.percent == nil then
						return false, where .. ": a buff needs flat or percent"
					end
				elseif type(effect.amount) ~= "number" then
					return false, where .. ": needs an amount"
				end
			end
		end
	end
	return true
end

return Traits
