-- Key 3: the unit's real ability, as a fight plays it, on a small field of dummies (a private
-- CombatSim run), shown on the test arena with its camera; and T / C, which change the arena and
-- its camera. Studio only (see DevLineup).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoardConfig = require(Shared:WaitForChild("BoardConfig"))
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local CombatSim = require(Shared:WaitForChild("CombatSim"))
local Pve = require(Shared:WaitForChild("Pve"))
local UltimateConfig = require(Shared:WaitForChild("UltimateConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local Config = require(script.Parent.Config)
local Hud = require(script.Parent.Hud)
local State = require(script.Parent.State)
local TestArena = require(script.Parent.TestArena)

local AbilityFx = require(script.Parent.Parent.AbilityFx)
local Arena = require(script.Parent.Parent.Arena)
local CameraCues = require(script.Parent.Parent.CameraCues)
local CombatEffects = require(script.Parent.Parent.CombatEffects)
local CombatPlayback = require(script.Parent.Parent.CombatPlayback)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Field = {}

local FIELD_UNIT, FIELD_DUMMY, FIELD_DUMMIES = Config.FIELD_UNIT, Config.FIELD_DUMMY, Config.FIELD_DUMMIES
local FIELD_ALLY, FIELD_ALLY_CELL, FIELD_ALLY_HEALTH =
	Config.FIELD_ALLY, Config.FIELD_ALLY_CELL, Config.FIELD_ALLY_HEALTH
local stageClock = State.stageClock

-- Leaves the field preview: the playback ends and the stage's unit and dummy come back.
function Field.endPreview(s: State.Stage)
	if not s.fieldPreview then
		return
	end
	CombatPlayback.stop() -- also resets the effects' clocks: back to the stage's
	CombatEffects.setClock(stageClock)
	ImpactEffects.setClock(stageClock)
	CameraCues.setClock(stageClock)
	s.fieldPreview:Destroy()
	s.fieldPreview = nil
	s.fieldOffset = nil
	TestArena.leave()
	s.actor.part.Parent = s.folder
	s.dummy.part.Parent = s.folder
	s.camera = s.stageCamera
end

-- Runs a short fight between the unit and FIELD_DUMMIES with CombatSim, on private copies of the
-- stats (the unit's mana bar shortened so it casts after one attack, then every few attacks; the
-- dummies tough, harmless and standing still). Nothing it runs reaches the server or any real
-- fight. Returns the result, the unit's index and its Cast events, or nil if it never casts.
local function fieldFight(s: State.Stage): (any?, number?, { any }, { any })
	local stats = table.clone(UnitConfig[s.unitType])
	stats.maxMana = math.min(stats.maxMana or Config.FIELD_MANA, Config.FIELD_MANA)
	stats.startingMana = stats.maxMana - 1
	local dummy = table.clone(Pve.pveUnitType(FIELD_DUMMY))
	dummy.health = 1e6
	dummy.attackDamage = 0
	dummy.attacksPerSecond = 0.001
	dummy.range = 12 -- every target in reach: dummies never walk
	-- A form that comes when the unit's health drops (titanheart's titan): the dummies hit hard
	-- enough that it happens within a second or two, so the preview shows the shift too.
	for _, form in stats.forms or {} do
		local trigger = form.trigger
		if trigger and trigger.type == "HEALTH_BELOW" then
			local needed = (stats.health or 1000) * (1 - (trigger.belowPercent or 50) / 100)
			dummy.attacksPerSecond = 2
			dummy.attackDamage = math.ceil(needed / (#FIELD_DUMMIES * 2) * s.starLevel)
		end
	end
	-- A heal that waits for a wounded ally (blooming_aid's ALLY_BELOW): an ally beside the unit
	-- (FIELD_ALLY) that the dummy across from it wears below the threshold, so a cast heals it. The
	-- unit's own health is raised so the dummies never kill it first.
	local allyBelow: number? = nil
	for _, effect in (stats.ability and stats.ability.effects) or {} do
		local condition = effect.condition
		if condition and condition.type == "ALLY_BELOW" and not condition.negate then
			allyBelow = condition.healthPercent
		end
	end
	local own = {
		{ id = "unit", unitType = s.unitType, starLevel = s.starLevel, column = FIELD_UNIT[1], row = FIELD_UNIT[2] },
	}
	local unitTypes = { [s.unitType] = stats, [FIELD_DUMMY] = dummy }
	if allyBelow then
		local ally = table.clone(Pve.pveUnitType(FIELD_ALLY))
		ally.health = FIELD_ALLY_HEALTH
		ally.attackDamage = 0
		ally.attacksPerSecond = 0.001
		ally.range = 12 -- never walks
		unitTypes[FIELD_ALLY] = ally
		table.insert(own, { id = "ally", unitType = FIELD_ALLY, column = FIELD_ALLY_CELL[1], row = FIELD_ALLY_CELL[2] })
		stats.health = (stats.health or 600) * 4
		dummy.attacksPerSecond = 2
		dummy.attackDamage = math.ceil(FIELD_ALLY_HEALTH * (1 - allyBelow / 100) * 1.5 / 3)
	end
	local dummies = {}
	for i, cell in FIELD_DUMMIES do
		table.insert(dummies, { id = "dummy" .. i, unitType = FIELD_DUMMY, column = cell[1], row = cell[2] })
	end
	local ok, result = pcall(CombatSim.run, {
		boards = { own, dummies },
		columns = BoardConfig.columns,
		rows = BoardConfig.rows,
		unitTypes = unitTypes,
		ticksPerSecond = CombatConfig.ticksPerSecond,
		maxTicks = CombatConfig.ticksPerSecond * Config.FIELD_SECONDS,
		critChance = 0,
		seed = 7,
	})
	if not ok then
		warn("[DevLineup] the preview fight failed: " .. tostring(result))
		return nil, nil, {}, {}
	end
	local actorIndex, sides = nil, {}
	for _, unit in result.units do
		sides[unit.index] = unit.side
		if unit.side == 1 and unit.id == "unit" then
			actorIndex = unit.index
		end
	end
	-- The dummies' own attacks and steps are left out of the playback.
	local events, casts, shifts = {}, {}, {}
	for _, event in result.events do
		local dummyAct = sides[event.unit] == 2 and (event.kind == "Attack" or event.kind == "Move")
		if not dummyAct then
			table.insert(events, event)
			if event.kind == "Cast" and event.unit == actorIndex then
				table.insert(casts, event)
			elseif event.kind == "Form" and event.unit == actorIndex then
				table.insert(shifts, event)
			elseif event.kind == "Heal" and event.unit == actorIndex and event.target ~= actorIndex then
				-- A cast that heals the wounded ally: the first press shows it (cast, below).
				local last = casts[#casts]
				if last and not last.heals then
					last.heals = true
				end
			end
		end
	end
	result.events = events
	return result, actorIndex, casts, shifts
end

-- Key 3: the unit's real ability, as a fight plays it, against several dummies on a small field so
-- its lines, cones and areas show. Each press shows its next cast (forms that change with casts
-- step up); the playback starts just before the cast's wind-up. Returns whether a cast plays.
function Field.cast(s: State.Stage): boolean
	Field.endPreview(s)
	local result, _, casts, shifts = fieldFight(s)
	if not result or #casts == 0 then
		print("[DevLineup] " .. s.unitType .. " did not cast in the preview fight")
		return false
	end
	s.castPresses += 1
	local index = (s.castPresses - 1) % #casts + 1
	if s.castPresses == 1 then
		-- A healer's first press shows the cast that heals the wounded ally (fieldFight), if any.
		for i, event in casts do
			if event.heals then
				index = i
				break
			end
		end
	end
	local castEvent = casts[index]
	local ticks = result.ticksPerSecond
	local castAt = castEvent.tick / ticks
	-- Only this cast and what follows it for a few seconds.
	local endTick = castEvent.tick + math.floor(Config.FIELD_AFTER * ticks)
	local from = castAt - AbilityFx.windupLength(s.unitType) - 0.5
	-- A health-triggered form change (fieldFight) on the first press: its shift is in the window too.
	local shift = if s.castPresses == 1 then shifts[1] else nil
	if shift then
		from = math.min(from, shift.tick / ticks - 0.8)
		endTick = math.max(endTick, shift.tick + math.floor(Config.FIELD_AFTER * ticks))
	end
	local kept = {}
	for _, event in result.events do
		if event.tick <= endTick then
			table.insert(kept, event)
		end
	end
	result.events = kept
	result.endTick = endTick
	result.winner = nil
	s.previewSeconds = endTick / ticks - from

	-- The field: the arena's ground (T: TestArena.build) under the arena cells, shifted by `offset`.
	local fieldFolder = Instance.new("Folder")
	fieldFolder.Name = "FieldPreview"
	local offset = TestArena.build(fieldFolder)
	local middle = Arena.cellPosition(4, BoardConfig.rows + 1) + offset
	fieldFolder.Parent = s.folder
	s.fieldPreview = fieldFolder
	s.fieldOffset = offset
	s.actor.part.Parent = nil
	s.dummy.part.Parent = nil
	-- Frame the unit and the dummies from behind the unit's side, as the board camera does (in an
	-- arena: its fixed camera).
	s.fieldFocus = Config.FIELD_ORIGIN:Lerp(middle, 0.6)
	s.camera = if State.arenaMode == "off"
		then TestArena.fieldFraming(s.fieldFocus :: Vector3)
		else TestArena.framing(s, offset)
	local startedAt = stageClock()
	CombatPlayback.preview(result, fieldFolder, offset, from, function()
		return from + (stageClock() - startedAt)
	end)
	print(
		string.format(
			"[DevLineup] %s: cast %d of %d in the preview fight (at %.1f s)",
			s.unitType,
			index,
			#casts,
			castAt
		)
	)
	local ultimate = UltimateConfig.units[s.unitType]
	if ultimate and ultimate.look ~= "" then
		print(string.format("[Ultimate] %s (tier %d): %s", s.unitType, ultimate.tier, ultimate.look))
	end
	return true
end

local function cycle(list: { string }, current: string): string
	local index = table.find(list, current) or 0
	return list[index % #list + 1]
end

-- T: the next test arena; a shown cast plays again in it.
function Field.nextArena(s: State.Stage)
	State.arenaMode = cycle(Config.ARENA_MODES, State.arenaMode)
	print("[DevLineup] arena: " .. State.arenaMode)
	if s.fieldPreview then
		s.castPresses -= 1 -- the same cast again
		Field.cast(s)
	end
	Hud.refreshTitle()
end

-- C: the arena's next fixed camera, applied to a shown cast at once.
function Field.nextArenaCamera(s: State.Stage)
	State.arenaCamera = cycle(Config.ARENA_CAMERAS, State.arenaCamera)
	print(
		"[DevLineup] arena camera: "
			.. State.arenaCamera
			.. (if State.arenaMode == "off" then " (T: an arena to use it)" else "")
	)
	if s.fieldPreview and s.fieldOffset and State.arenaMode ~= "off" then
		s.camera = TestArena.framing(s, s.fieldOffset)
	end
	Hud.refreshTitle()
end

return Field
