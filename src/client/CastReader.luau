-- Works out two things for playback:
--   * the damage type of every Attack and Damage event (basic attacks are always physical), and
--   * the areas each cast hit.
-- Since Overhaul 1 the server's events carry both: Damage events have their damageType, and every
-- AREA_DAMAGE emits an Area event (circle, line or cone, with its cells). Those are used whenever
-- present, including for hits outside a cast (delayed hits, follow-ups, splash, auras). For event
-- lists without them (older recordings, hand-written test events) it falls back to matching each
-- cast's events against the caster's ability data (Abilities applies effects in listed order, all
-- within the cast's tick).
-- Presentation only. Pure Luau: no Roblox APIs, so it runs in Lune tests.
--
-- Fallback limitation: an AREA_DAMAGE effect claims every Damage event after it in the cast, so a
-- DAMAGE effect listed after an AREA_DAMAGE effect would be read as area damage.

local HexGrid = if script
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("HexGrid"))
	else require("../shared/HexGrid")

local CastReader = {}

-- The event each effect type produces.
local EVENT_FOR_EFFECT = {
	DAMAGE = "Damage",
	AREA_DAMAGE = "Damage",
	HEAL = "Heal",
	SHIELD = "Shield",
	STUN = "Stun",
	BUFF = "Buff",
	DASH = "Dash",
	AREA_STUN = "Stun",
	SUMMON = "Summon",
	PULL = "Pull",
	DAMAGE_OVER_TIME = "Dot",
	COPY = "Copy",
}

-- Effects that can produce any number of their event, so matching stays on them.
local MANY_EVENTS = { AREA_DAMAGE = true, AREA_STUN = true, SUMMON = true, DAMAGE_OVER_TIME = true }

-- Events inside a cast that carry another unit's index rather than the caster's (a hit can make
-- its target change form; a recall ends summons).
local OTHER_UNIT_EVENTS = { Death = true, MaxHealth = true, Form = true, SummonEnd = true }

-- A circle (radius) or a set of cells (lines and cones). `inferred` marks a circle worked out by
-- matching (no Area event); playback pulses those at the cast and pulses Area events as they come.
export type Area = {
	column: number,
	row: number,
	radius: number?,
	cells: { { number } }?,
	inferred: boolean?,
}

export type Reading = {
	damageTypes: { [number]: string }, -- event index -> damage type, for Attack and Damage events
	areas: { [number]: { Area } }, -- index of a Cast event -> the areas that cast hit
	areaEvents: { [number]: Area }, -- index of an Area event -> its area
}

-- The area an Area event describes.
function CastReader.areaOf(event): Area
	return {
		column = event.column,
		row = event.row,
		radius = event.radius,
		cells = event.cells,
	}
end

-- True if the cell lies inside `area`.
function CastReader.contains(area: Area, column: number, row: number): boolean
	if area.cells then
		for _, cell in area.cells do
			if cell[1] == column and cell[2] == row then
				return true
			end
		end
		return false
	end
	return HexGrid.distance(area.column, area.row, column, row) <= (area.radius or 0)
end

local function valueAt(value: any, starLevel: number): number
	if type(value) == "table" then
		return value[starLevel]
	end
	return value
end

-- `units` are the fight's starting units (CombatSim UnitSummary). `abilityOf(unitIndex, name)`
-- returns that unit's ability data (a UnitConfig ability, or a form's ability) named `name` (from
-- the Cast or Copy event), or nil; it is also asked for the target of a COPY.
function CastReader.read(units: { any }, events: { any }, abilityOf: (number, string?) -> any?): Reading
	local damageTypes = {}
	local areas = {}
	local areaEvents = {}

	local cells = {}
	local starLevels = {}
	for _, unit in units do
		cells[unit.index] = { unit.column, unit.row }
		starLevels[unit.index] = unit.starLevel or 1
	end

	-- Called once the cast's last event has been read, before anyone else moves. Casts whose areas
	-- came as Area events need no inference.
	local function finish(cast)
		if cast.hasAreaEvents then
			return
		end
		for _, area in cast.areas do
			local center = nil
			if area.selector == "SELF" then
				center = cells[cast.caster]
			elseif cast.selected[area.selector] then
				center = cells[cast.selected[area.selector]]
			else
				-- No other effect shares the selector. The center unit was alive when the cast started,
				-- so it was hit: take the first hit unit that has every other hit within the radius.
				for _, candidate in area.hits do
					local cell = cells[candidate]
					local coversAll = true
					for _, other in area.hits do
						if HexGrid.distance(cell[1], cell[2], cells[other][1], cells[other][2]) > area.radius then
							coversAll = false
							break
						end
					end
					if coversAll then
						center = cell
						break
					end
				end
			end
			if center then
				areas[cast.castIndex] = areas[cast.castIndex] or {}
				table.insert(
					areas[cast.castIndex],
					{ column = center[1], row = center[2], radius = area.radius, inferred = true }
				)
			end
		end
	end

	local function newCast(caster: number, tick: number, castIndex: number, ability)
		local effects = {}
		for _, effect in if ability then ability.effects else {} do
			table.insert(effects, effect)
		end
		local cast = {
			caster = caster,
			tick = tick,
			castIndex = castIndex,
			effects = effects,
			cursor = 1,
			selected = {},
			areas = {},
		}
		for position, effect in effects do
			if effect.type == "AREA_DAMAGE" then
				cast.areas[position] = {
					selector = effect.center,
					radius = valueAt(effect.radius, starLevels[caster] or 1),
					hits = {},
				}
			end
		end
		return cast
	end

	-- Matches one of the caster's events to the next effect (from the cursor on) that produces it.
	-- Returns a new cast to continue with when the event is a COPY (the copied ability's effects).
	local function match(cast, index: number, event)
		for position = cast.cursor, #cast.effects do
			local effect = cast.effects[position]
			if EVENT_FOR_EFFECT[effect.type] == event.kind then
				if effect.type == "COPY" then
					-- The copied ability's events follow, as if the caster had cast it. A COPY inside it
					-- is ignored by the engine, so it is dropped here too.
					finish(cast)
					local copied =
						newCast(cast.caster, cast.tick, cast.castIndex, abilityOf(event.target, event.ability))
					for i = #copied.effects, 1, -1 do
						if copied.effects[i].type == "COPY" then
							table.remove(copied.effects, i)
							copied.areas[i] = nil
						end
					end
					return copied
				elseif MANY_EVENTS[effect.type] then
					if effect.type == "AREA_DAMAGE" then
						damageTypes[index] = effect.damageType
						table.insert(cast.areas[position].hits, event.target)
					end
					cast.cursor = position -- this effect can produce more of the same event
				else
					if event.kind == "Damage" then
						damageTypes[index] = effect.damageType
					end
					if event.target and effect.target then
						cast.selected[effect.target] = event.target
					end
					cast.cursor = position + 1
				end
				return cast
			end
		end
		return cast
	end

	local cast = nil
	for index, event in events do
		-- A cast's events all come straight after it in the same tick, apart from deaths and max
		-- health changes it causes on other units.
		if cast and (event.tick ~= cast.tick or (event.unit ~= cast.caster and not OTHER_UNIT_EVENTS[event.kind])) then
			finish(cast)
			cast = nil
		end

		if event.kind == "Attack" then
			damageTypes[index] = "PHYSICAL"
		elseif event.kind == "Damage" and event.dot then
			-- Damage-over-time ticks carry their own type.
			damageTypes[index] = event.damageType
		elseif event.kind == "Cast" then
			if cast then
				finish(cast)
			end
			cast = newCast(event.unit, event.tick, index, abilityOf(event.unit, event.ability))
		elseif event.kind == "Area" then
			-- The server described the area: no matching needed.
			local area = CastReader.areaOf(event)
			areaEvents[index] = area
			if cast and event.unit == cast.caster then
				cast.hasAreaEvents = true
				areas[cast.castIndex] = areas[cast.castIndex] or {}
				table.insert(areas[cast.castIndex], area)
			end
		elseif cast and event.unit == cast.caster then
			cast = match(cast, index, event)
		end
		-- Hits that carry their damage type are read as such, wherever they happen.
		if event.kind == "Damage" and event.damageType then
			damageTypes[index] = event.damageType
		end

		if event.kind == "Move" or event.kind == "Dash" then
			cells[event.unit] = { event.column, event.row }
		elseif event.kind == "Summon" then
			cells[event.summon] = { event.column, event.row }
		elseif event.kind == "Pull" or event.kind == "Knockback" then
			cells[event.target] = { event.column, event.row }
		end
	end
	if cast then
		finish(cast)
	end

	return { damageTypes = damageTypes, areas = areas, areaEvents = areaEvents }
end

return CastReader
