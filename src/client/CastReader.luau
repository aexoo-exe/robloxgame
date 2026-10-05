-- Works out two things the combat event list does not carry, by matching each cast's events
-- against the caster's ability data (Abilities applies effects in listed order, all within the
-- cast's tick):
--   * the damage type of every Attack and Damage event (basic attacks are always physical), and
--   * the center cell and radius of every AREA_DAMAGE effect.
-- Presentation only. Pure Luau: no Roblox APIs, so it runs in Lune tests.
--
-- Limitation: an AREA_DAMAGE effect claims every Damage event after it in the cast, so a DAMAGE
-- effect listed after an AREA_DAMAGE effect would be read as area damage. No ability does that.

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
}

export type Area = { column: number, row: number, radius: number }

export type Reading = {
	damageTypes: { [number]: string }, -- event index -> damage type, for Attack and Damage events
	areas: { [number]: { Area } }, -- index of a Cast event -> the areas that cast hit
}

local function valueAt(value: any, starLevel: number): number
	if type(value) == "table" then
		return value[starLevel]
	end
	return value
end

-- `units` are the fight's starting units (CombatSim UnitSummary). `abilityOf(unitIndex)` returns
-- that unit's ability data (a UnitConfig ability) or nil.
function CastReader.read(units: { any }, events: { any }, abilityOf: (number) -> any?): Reading
	local damageTypes = {}
	local areas = {}

	local cells = {}
	local starLevels = {}
	for _, unit in units do
		cells[unit.index] = { unit.column, unit.row }
		starLevels[unit.index] = unit.starLevel or 1
	end

	-- Called once the cast's last event has been read, before anyone else moves.
	local function finish(cast)
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
				table.insert(areas[cast.castIndex], { column = center[1], row = center[2], radius = area.radius })
			end
		end
	end

	-- Matches one of the caster's events to the next effect (from the cursor on) that produces it.
	local function match(cast, index: number, event)
		for position = cast.cursor, #cast.effects do
			local effect = cast.effects[position]
			if EVENT_FOR_EFFECT[effect.type] == event.kind then
				if effect.type == "AREA_DAMAGE" then
					damageTypes[index] = effect.damageType
					table.insert(cast.areas[position].hits, event.target)
					cast.cursor = position -- an area hits any number of units
				else
					if event.kind == "Damage" then
						damageTypes[index] = effect.damageType
					end
					if event.target and effect.target then
						cast.selected[effect.target] = event.target
					end
					cast.cursor = position + 1
				end
				return
			end
		end
	end

	local cast = nil
	for index, event in events do
		-- A cast's events all come straight after it in the same tick, apart from deaths it causes.
		if cast and (event.tick ~= cast.tick or (event.unit ~= cast.caster and event.kind ~= "Death")) then
			finish(cast)
			cast = nil
		end

		if event.kind == "Attack" then
			damageTypes[index] = "PHYSICAL"
		elseif event.kind == "Cast" then
			if cast then
				finish(cast)
			end
			local ability = abilityOf(event.unit)
			cast = {
				caster = event.unit,
				tick = event.tick,
				castIndex = index,
				effects = if ability then ability.effects else {},
				cursor = 1,
				selected = {},
				areas = {},
			}
			for position, effect in cast.effects do
				if effect.type == "AREA_DAMAGE" then
					cast.areas[position] = {
						selector = effect.center,
						radius = valueAt(effect.radius, starLevels[event.unit]),
						hits = {},
					}
				end
			end
		elseif cast and event.unit == cast.caster then
			match(cast, index, event)
		end

		if event.kind == "Move" or event.kind == "Dash" then
			cells[event.unit] = { event.column, event.row }
		end
	end
	if cast then
		finish(cast)
	end

	return { damageTypes = damageTypes, areas = areas }
end

return CastReader
