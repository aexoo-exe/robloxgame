-- Trait counting and bonuses (docs/design/world-and-traits.md). Membership is derived from each
-- character's `origin` and `classes` in UnitConfig; breakpoints and effects are in TraitConfig.
--   * A trait's count is the number of different characters with it among the units passed in
--     (callers pass only units placed on the board, never the bench). Copies count once.
--   * The highest breakpoint reached applies; lower ones are replaced, not added.
--   * Bonuses from different traits stack: flat bonuses add together and percent bonuses add
--     together, per stat. MEMBERS effects go to every placed unit with the trait (copies included),
--     ALL_ALLIES effects to every placed unit.
-- Bonuses are plain data; CombatSim applies them at combat start (Battle.applyStartBonus).
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local TraitConfig = if script then require(script.Parent.TraitConfig) else require("./TraitConfig")
local UnitConfig = if script then require(script.Parent.UnitConfig) else require("./UnitConfig")

local Traits = {}

-- A unit's combat-start bonus: summed stat changes, and shields to apply.
export type Bonus = {
	stats: { [string]: { flat: number, percent: number } },
	shields: { { amount: number, duration: number, source: string } },
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

-- Trait names of one character: its origin, then its classes.
function Traits.traitsOf(unitType: string): { string }
	local unit = UnitConfig[unitType]
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

-- Different characters per trait among `units` (each with a unitType).
function Traits.count(units: { any }): { [string]: number }
	local seen = {}
	local counts = {}
	for _, unit in units do
		if not seen[unit.unitType] then
			seen[unit.unitType] = true
			for _, trait in Traits.traitsOf(unit.unitType) do
				counts[trait] = (counts[trait] or 0) + 1
			end
		end
	end
	return counts
end

-- Index of the highest breakpoint of `trait` reached with `count` members (0 if none).
function Traits.levelFor(trait: string, count: number): number
	local level = 0
	for index, breakpoint in TraitConfig[trait].breakpoints do
		if count >= breakpoint.count then
			level = index
		end
	end
	return level
end

-- Every trait present among `units`: active ones first (most members first), then partial ones.
function Traits.summary(units: { any }): { TraitState }
	local states = {}
	for trait, count in Traits.count(units) do
		local breakpoints = TraitConfig[trait].breakpoints
		local level = Traits.levelFor(trait, count)
		table.insert(states, {
			name = trait,
			kind = TraitConfig[trait].kind,
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
	return { stats = {}, shields = {} }
end

-- Combat-start bonuses for `units` (each with an id and a unitType): unit id -> Bonus. Units with
-- no bonus are left out.
function Traits.bonuses(units: { any }): { [string]: Bonus }
	local counts = Traits.count(units)
	local result = {}
	local traitNames = {}
	for trait in counts do
		table.insert(traitNames, trait)
	end
	table.sort(traitNames) -- a fixed order, so shields are applied the same way every time

	for _, trait in traitNames do
		local level = Traits.levelFor(trait, counts[trait])
		if level > 0 then
			for _, effect in TraitConfig[trait].breakpoints[level].effects do
				for _, unit in units do
					local receives = effect.target == "ALL_ALLIES"
						or table.find(Traits.traitsOf(unit.unitType), trait) ~= nil
					if receives then
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
						end
					end
				end
			end
		end
	end
	return result
end

return Traits
