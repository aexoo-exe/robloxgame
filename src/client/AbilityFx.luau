-- Ability effects generated from each ability's mechanics, so no ability looks generic. One effect
-- per building block, composed automatically from the playback events an ability produces (which
-- follow its data in UnitConfig: Abilities emits one event per effect), at the real geometry:
--   strikes      a single-target ability hit: the element's strike at the target, and its beam
--                from a caster out of melee reach
--   LINE         a beam or travelling slash wave along the line's real cells
--   CONE         a sweeping arc over the cone's real cells
--   circle       a blast: flash, shockwave ring, ground mark (and a spiral for wind)
--   BOUNCE       a beam jumping from target to target
--   splash       light element sparks on every target an area hits
--   dash, blink  afterimages along the path
--   pull         a line drawing the target in; knockback: a shockwave and dust
--   summon       a portal (ring, column, smoke); recall: the summon drawn back to its summoner
--   form change  a transformation burst
--   heal, shield the motes and bubble (CombatFx), touched in the caster's color
--   buff         an aura pulse; debuffs and damage over time: readable markers (StatusMarkers)
--   mark, immune a reticle; a golden flash
--   auras        a pulse ring around the aura's source every second (AbilityFxConfig)
-- Each is drawn in the unit's element (AbilityFxConfig.elements: beam, strike, particles, ground
-- mark) and colors (AbilityFxConfig.units). A unit with a signature (AbilitySignatures) draws its
-- own wind-up, release and strikes. Presentation only: it reads events and never changes them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityFxConfig = require(Shared:WaitForChild("AbilityFxConfig"))
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local AbilitySignatures = require(script.Parent.AbilitySignatures)
local CombatFx = require(script.Parent.CombatFx)
local FxKit = require(script.Parent.FxKit)
local ImpactEffects = require(script.Parent.ImpactEffects)
local UnitView = require(script.Parent.UnitView)

local AbilityFx = {}

export type Style = AbilitySignatures.Style

local HEX = math.sqrt(3) * RenderConfig.hexRadius -- between neighboring cell centers
local LIFT = Vector3.new(0, 1.6, 0) -- beams run at chest height over the ground
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 215, 90)
local DUST = Color3.fromRGB(190, 180, 165)
local CONFIG = AbilityFxConfig

local function ground(view: UnitView.UnitView): Vector3
	return view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
end
local function chest(view: UnitView.UnitView): Vector3
	return view.part.Position + Vector3.new(0, view.part.Size.Y * 0.1, 0)
end
local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- A unit type's ability style: its element and colors (AbilityFxConfig.units), or the default
-- element in `fallback` (its faction color) and white.
function AbilityFx.styleOf(unitType: string?, fallback: Color3): Style
	local entry = if unitType then CONFIG.units[unitType] else nil
	local element = if entry then entry.element else CONFIG.default
	return {
		element = element,
		def = CONFIG.elements[element] or CONFIG.elements[CONFIG.default],
		primary = if entry then entry.primary else fallback,
		secondary = if entry then entry.secondary else WHITE,
	}
end

-- How long a unit's cast wind-up is: its signature's, else AnimationConfig.cast.windup.
function AbilityFx.windupLength(unitType: string?): number
	local spec = AbilitySignatures.of(unitType)
	return if spec and spec.windup then spec.windup else AnimationConfig.cast.windup
end

-- The longest wind-up any unit can have.
function AbilityFx.maxWindup(): number
	return math.max(AnimationConfig.cast.windup, AbilitySignatures.maxWindup())
end

-- Particles -----------------------------------------------------------------------------------------

-- A burst of the element's particles (and a few of its accent) at `position`.
local function particles(style: Style, position: Vector3, count: number, scale: number, direction: Vector3?)
	local def = style.def
	local kind = def.particle
	local rising = kind == "flame" or kind == "smoke" or kind == "puff" or kind == "bubble"
	ImpactEffects.burst(kind, position, direction, {
		color = style.primary,
		color2 = style.secondary,
		count = count * scale,
		size = (if rising then 0.7 else 0.3) * scale,
		speed = if rising then { 2, 5 } else { 7, 14 },
		lifetime = if rising then { 0.35, 0.7 } else { 0.15, 0.35 },
		spread = 60,
		transparency = if kind == "smoke" then 0.3 else 0.05,
	})
	if def.accent then
		ImpactEffects.burst(def.accent, position, nil, {
			color = style.secondary,
			count = math.max(1, count * 0.4) * scale,
			size = 0.35 * scale,
			speed = { 3, 8 },
			lifetime = { 0.2, 0.45 },
			transparency = 0.2,
		})
	end
end

-- Strikes -------------------------------------------------------------------------------------------

-- The element's single-target hit at `target` (from `source`, if known).
local function strikeAt(style: Style, source: UnitView.UnitView?, target: UnitView.UnitView, scale: number)
	local def = style.def
	local at = chest(target)
	local floor = ground(target)
	local size = CONFIG.strikeSize * scale
	local facing = if source then flat(target.part.Position - source.part.Position) else Vector3.zAxis
	local kind = def.strike
	if kind == "bolt" then
		FxKit.beam(at + Vector3.new(0.6, 8, 0.4), at, style.primary, 0.5 * scale, 0.25, "jagged")
		ImpactEffects.ball(at, style.secondary, size * 0.8, 0.12)
		particles(style, at, 10, scale)
	elseif kind == "flame" then
		ImpactEffects.ball(at, style.primary, size * 0.7, 0.15)
		ImpactEffects.burst("flame", floor + Vector3.new(0, 0.5, 0), Vector3.yAxis, {
			color = style.primary,
			color2 = style.secondary,
			count = 12 * scale,
			size = 1.1 * scale,
			speed = { 3, 6 },
			lifetime = { 0.35, 0.6 },
			spread = 30,
		})
		particles(style, at, 6, scale)
	elseif kind == "splash" then
		FxKit.mark(floor, style.primary, style.secondary, size * 0.5, "splash", 0.5)
		particles(style, at, 12, scale, Vector3.yAxis)
	elseif kind == "swirl" then
		FxKit.spiral(floor, style.primary, size * 0.45, target.part.Size.Y * 1.1, 0.45)
		particles(style, at, 8, scale)
	elseif kind == "slash" then
		FxKit.slashArc(at, facing, style.primary, size * 1.2, 0.6, 0.3)
		FxKit.slashArc(at, facing, style.secondary, size * 1.1, -0.6, 0.3, 0.05)
		particles(style, at, 8, scale, facing)
	elseif kind == "shock" then
		ImpactEffects.burst("shock", at, facing, {
			color = style.secondary,
			count = 2,
			size = 1.1 * scale,
			speed = { 0, 1 },
			lifetime = { 0.25, 0.3 },
			transparency = 0.2,
		})
		FxKit.ring(floor, style.primary, size * 1.4, 0.35)
		ImpactEffects.burst("puff", floor + Vector3.new(0, 0.3, 0), nil, {
			color = DUST,
			count = 8 * scale,
			size = 0.6 * scale,
			speed = { 3, 6 },
			lifetime = { 0.3, 0.55 },
			transparency = 0.35,
		})
	elseif kind == "rings" then
		for i = 1, 3 do
			FxKit.ring(floor, if i == 2 then style.secondary else style.primary, size * (0.5 + 0.4 * i), 0.4, i * 0.06)
		end
		particles(style, at, 8, scale)
	elseif kind == "explode" then
		ImpactEffects.ball(at, style.primary, size * 1.2, 0.2)
		ImpactEffects.burst("flame", at, nil, {
			color = style.primary,
			color2 = style.secondary,
			count = 14 * scale,
			size = 1 * scale,
			speed = { 4, 8 },
			lifetime = { 0.3, 0.5 },
		})
		ImpactEffects.burst("smoke", at, nil, {
			color = style.secondary,
			count = 8 * scale,
			size = 0.9 * scale,
			speed = { 2, 4 },
			lifetime = { 0.6, 0.9 },
			transparency = 0.3,
		})
	elseif kind == "stretch" then
		ImpactEffects.burst("puff", at, facing, {
			color = WHITE,
			count = 6 * scale,
			size = 0.5 * scale,
			speed = { 3, 6 },
			lifetime = { 0.25, 0.4 },
			spread = 50,
			transparency = 0.3,
		})
		ImpactEffects.ball(at, style.secondary, size * 0.6, 0.12)
	else -- "burst"
		ImpactEffects.ball(at, style.primary, size, 0.16)
		particles(style, at, 12, scale)
	end
end

-- Areas ---------------------------------------------------------------------------------------------

-- A circle blast at `center` (ground) reaching `radius` studs.
local function blast(style: Style, center: Vector3, radius: number, scale: number)
	local def = style.def
	ImpactEffects.ball(center + Vector3.new(0, CONFIG.blastHeight, 0), style.primary, radius * 0.9, 0.2)
	FxKit.ring(center, style.secondary, radius * 2.1, 0.45)
	FxKit.ring(center, style.primary, radius * 1.6, 0.35, 0.05)
	if def.ground ~= "none" then
		FxKit.mark(center, style.primary, style.secondary, radius, def.ground, CONFIG.areaMarkDuration)
	end
	if def.swirl then
		FxKit.spiral(center, style.primary, radius * 0.6, 3.5, 0.6)
	end
	particles(style, center + Vector3.new(0, 0.8, 0), 14, scale)
end

-- A line from the caster's cell through the line's cells.
local function lineFx(style: Style, from: Vector3, cells: { Vector3 }, scale: number)
	local far, distance = from, -1
	for _, cell in cells do
		local d = (cell - from).Magnitude
		if d > distance then
			far, distance = cell, d
		end
	end
	if distance <= 0 then
		return
	end
	local direction = flat(far - from).Unit
	-- The beam runs from the caster to half a cell past the last cell.
	local to = far + direction * HEX * 0.5
	local width = CONFIG.beamWidth * 1.6 * scale
	FxKit.beam(from + LIFT, to + LIFT, style.primary, width, CONFIG.beamDuration * 1.5, style.def.beam)
	if style.def.beam ~= "straight" then
		FxKit.beam(from + LIFT, to + LIFT, style.secondary, width * 0.3, CONFIG.beamDuration, "straight")
	end
	for i, cell in cells do
		particles(style, cell + Vector3.new(0, 0.8, 0), 4, scale)
		if style.def.ground ~= "none" and i % 2 == 1 then
			FxKit.mark(
				cell,
				style.primary,
				style.secondary,
				HEX * 0.35,
				style.def.ground,
				CONFIG.areaMarkDuration * 0.8
			)
		end
	end
end

-- A cone from the caster's cell over the cone's cells.
local function coneFx(style: Style, from: Vector3, cells: { Vector3 }, scale: number)
	if #cells == 0 then
		return
	end
	local sum = Vector3.zero
	for _, cell in cells do
		sum += cell
	end
	local direction = flat(sum / #cells - from)
	if direction.Magnitude < 1e-3 then
		return
	end
	direction = direction.Unit
	local halfAngle, reach = 0.3, HEX
	for _, cell in cells do
		local offset = flat(cell - from)
		if offset.Magnitude > 1e-3 then
			halfAngle = math.max(halfAngle, math.acos(math.clamp(offset.Unit:Dot(direction), -1, 1)))
			reach = math.max(reach, offset.Magnitude)
		end
	end
	FxKit.sweep(from + Vector3.new(0, 1.2, 0), direction, halfAngle + 0.2, reach + HEX * 0.5, style.primary, 0.5)
	for _, cell in cells do
		particles(style, cell + Vector3.new(0, 0.8, 0), 4, scale, direction)
		if style.def.ground ~= "none" then
			FxKit.mark(cell, style.primary, style.secondary, HEX * 0.3, style.def.ground, CONFIG.areaMarkDuration * 0.7)
		end
	end
end

-- Fights ---------------------------------------------------------------------------------------------

-- What a fight's effects need from its playback.
export type Context = {
	views: { [number]: UnitView.UnitView }, -- living units, by unit index
	toWorld: (number, number) -> Vector3, -- a field cell's ground position
	styleOf: (number) -> Style, -- a unit's ability style
	unitTypeOf: (number) -> string?, -- nil for summons
	summonerOf: (number) -> number?,
	now: () -> number, -- fight time
	ticksPerSecond: number,
}

export type Fight = {
	context: Context,
	areaTick: { [number]: number }, -- unit index -> tick of its last Area event
	castAt: { [number]: number }, -- unit index -> fight time of its last cast
	dotStatus: { [number]: string }, -- unit index -> its damage over time's status
	auraAt: { [number]: number }, -- unit index -> fight time of its last aura pulse
}

local Fight = {}
Fight.__index = Fight

-- Effects for one fight's playback.
function AbilityFx.newFight(context: Context): Fight
	return setmetatable({
		context = context,
		areaTick = {},
		castAt = {},
		dotStatus = {},
		auraAt = {},
	}, Fight) :: any
end

local function scaleOf(view: UnitView.UnitView?): number
	return if view then UnitView.effectScale(view) else 1
end

-- The cast wind-up of unit `unitIndex` (its view `view`) from `startAt` to `releaseAt`.
function Fight.windup(self: Fight, unitIndex: number, view: UnitView.UnitView, startAt: number, releaseAt: number)
	local style = self.context.styleOf(unitIndex)
	local spec, kind = AbilitySignatures.of(self.context.unitTypeOf(unitIndex))
	if kind and kind.windup and kind.windup(spec, view, startAt, releaseAt, style) then
		return
	end
	CombatFx.castWindup(view, startAt, releaseAt, style.primary)
end

-- The moment of a cast (or a follow-up) by `unitIndex`.
function Fight.release(self: Fight, unitIndex: number, view: UnitView.UnitView)
	local style = self.context.styleOf(unitIndex)
	local spec, kind = AbilitySignatures.of(self.context.unitTypeOf(unitIndex))
	if kind and kind.release and kind.release(spec, view, style) then
		return
	end
	CombatFx.castRelease(view, style.primary)
	local scale = scaleOf(view)
	particles(style, chest(view), 10, scale)
	if style.def.swirl then
		FxKit.spiral(ground(view), style.primary, 1.4 * scale, view.part.Size.Y * 1.2, 0.5)
	end
end

local function strike(self: Fight, sourceIndex: number, target: UnitView.UnitView)
	local context = self.context
	local source = context.views[sourceIndex]
	local style = context.styleOf(sourceIndex)
	local spec, kind = AbilitySignatures.of(context.unitTypeOf(sourceIndex))
	if kind and kind.strike and kind.strike(spec, source, target, style) then
		return
	end
	local scale = scaleOf(source)
	-- A caster out of melee reach sends its beam (a stretch reaches out even in melee).
	local beam = style.def.beam
	if source and (beam == "stretch" or flat(target.part.Position - source.part.Position).Magnitude > HEX * 1.3) then
		FxKit.beam(chest(source), chest(target), style.primary, CONFIG.beamWidth * scale, CONFIG.beamDuration, beam)
	end
	strikeAt(style, source, target, scale)
end

-- Afterimages along a dash from where the unit is to `to` (ground).
local function afterimages(style: Style, view: UnitView.UnitView, to: Vector3)
	local from = view.base
	local destination = to + Vector3.new(0, view.part.Size.Y / 2, 0)
	local size = view.part.Size * Vector3.new(0.75, 0.95, 0.45)
	local count = CONFIG.afterimages
	local rotation = CFrame.lookAt(from, Vector3.new(destination.X, from.Y, destination.Z)).Rotation
	for i = 0, count - 1 do
		local at = from:Lerp(destination, i / count)
		FxKit.ghost(
			CFrame.new(at) * rotation,
			size,
			if i % 2 == 0 then style.primary else style.secondary,
			CONFIG.afterimageDuration,
			i * RenderConfig.dashDuration / count
		)
	end
end

-- Shows the ability effects of playback event `event` (index `index` in the fight's event list).
-- `fresh` is false for events from a while ago (joined mid-fight): state is still tracked, but
-- nothing is drawn. Call it before the playback applies the event (so a dash still knows where
-- the unit starts).
function Fight.event(self: Fight, _index: number, event, fresh: boolean)
	local context = self.context
	local views = context.views
	local kind = event.kind
	local now = context.now()
	local view = views[event.unit]
	local target = if event.target then views[event.target] else nil

	if kind == "Cast" or kind == "FollowUp" then
		self.castAt[event.unit] = event.tick / context.ticksPerSecond
	elseif kind == "Area" then
		self.areaTick[event.unit] = event.tick
	elseif kind == "Dot" and event.target and event.status then
		self.dotStatus[event.target] = event.status
	end
	if not fresh then
		return
	end

	local style = context.styleOf(event.unit)
	local scale = scaleOf(view)
	if kind == "Area" then
		if event.cells and (event.shape == "LINE" or event.shape == "CONE") then
			local from = context.toWorld(event.fromColumn or event.column, event.fromRow or event.row)
			local cells = {}
			for _, cell in event.cells do
				table.insert(cells, context.toWorld(cell[1], cell[2]))
			end
			if event.shape == "LINE" then
				lineFx(style, from, cells, scale)
			else
				coneFx(style, from, cells, scale)
			end
		else
			local radius = ((event.radius or 0) + 0.5) * HEX
			blast(style, context.toWorld(event.column, event.row), radius, scale)
		end
	elseif kind == "AreaStun" then
		local center = context.toWorld(event.column, event.row)
		local radius = ((event.radius or 0) + 0.5) * HEX
		local mark = if style.def.ground ~= "none" then style.def.ground else "rings"
		FxKit.mark(center, style.primary, style.secondary, radius, mark, CONFIG.areaMarkDuration)
		FxKit.ring(center, RenderConfig.areaStunColor, radius * 2, 0.4)
	elseif kind == "Damage" and target and not event.dot and not event.item then
		if event.splash or self.areaTick[event.unit] == event.tick then
			-- One of an area's (or a splash's) targets: light sparks of the element.
			particles(style, chest(target), 5, scale)
		else
			strike(self, event.unit, target)
		end
	elseif kind == "Damage" and target and event.dot then
		local status = self.dotStatus[event.target]
		if status then
			UnitView.mark(target, status, now + CONFIG.dotLinger)
		end
		if event.aura and view and now - (self.auraAt[event.unit] or -math.huge) >= CONFIG.auraPulseEvery * 0.9 then
			-- An aura's tick: a pulse ring around its source, as wide as the aura.
			self.auraAt[event.unit] = now
			local unitType = context.unitTypeOf(event.unit)
			local aura = unitType and UnitConfig[unitType] and UnitConfig[unitType].aura
			local radius = ((if aura then aura.radius else 1) + 0.5) * HEX
			FxKit.ring(ground(view), style.primary, radius * 2, 0.6)
			particles(style, ground(view) + Vector3.new(0, 0.6, 0), 5, scale)
		end
	elseif kind == "Dash" and view then
		afterimages(style, view, context.toWorld(event.column, event.row))
	elseif kind == "Pull" and view and target then
		FxKit.beam(chest(view), chest(target), style.primary, 0.2, RenderConfig.dashDuration + 0.25, "straight")
		particles(style, chest(target), 6, scale)
	elseif kind == "Knockback" and target then
		ImpactEffects.burst("shock", chest(target), nil, {
			color = WHITE,
			count = 1,
			size = 1.2,
			speed = { 0, 0 },
			lifetime = { 0.25, 0.3 },
			transparency = 0.3,
		})
		ImpactEffects.burst("puff", ground(target) + Vector3.new(0, 0.3, 0), nil, {
			color = DUST,
			count = 8,
			size = 0.6,
			speed = { 3, 6 },
			lifetime = { 0.3, 0.5 },
			transparency = 0.35,
		})
	elseif kind == "Bounce" and target and views[event.from] then
		local beam = if style.def.beam == "wave" or style.def.beam == "stretch" then "straight" else style.def.beam
		FxKit.beam(chest(views[event.from]), chest(target), style.primary, CONFIG.beamWidth * 0.7, 0.25, beam)
		strikeAt(style, views[event.from], target, scale * 0.8)
	elseif kind == "Summon" then
		local at = context.toWorld(event.column, event.row)
		FxKit.ring(at, style.primary, HEX * 0.9, CONFIG.portalDuration * 0.6)
		FxKit.disc(at, style.secondary, HEX * 0.6, CONFIG.portalDuration, 0.4)
		FxKit.column(at, style.primary, 4, 1.2, CONFIG.portalDuration)
		ImpactEffects.burst("smoke", at + Vector3.new(0, 0.6, 0), nil, {
			color = style.primary,
			color2 = style.secondary,
			count = 10,
			size = 0.9,
			speed = { 1.5, 3.5 },
			lifetime = { 0.5, 0.8 },
			transparency = 0.3,
		})
	elseif kind == "SummonEnd" and view and event.recalled then
		local summoner = context.summonerOf(event.unit)
		local home = if summoner then views[summoner] else nil
		FxKit.column(ground(view), style.primary, 3, 1, 0.35)
		if home then
			FxKit.beam(chest(view), chest(home), style.primary, 0.25, 0.3, style.def.beam)
		end
	elseif kind == "Form" and view then
		local height = view.part.Size.Y
		FxKit.column(ground(view), style.primary, height * 1.6, 2.2 * scale, CONFIG.transformDuration)
		FxKit.ring(ground(view), style.secondary, HEX * 1.3 * scale, 0.5)
		ImpactEffects.ball(chest(view), style.primary, height * 0.8, 0.2)
		particles(style, chest(view), 18, scale)
		ImpactEffects.shake(0.12)
	elseif kind == "Buff" and target then
		if event.status then
			UnitView.mark(target, event.status, now + (event.duration or 3))
		elseif not event.source and ((event.percent or 0) > 0 or (event.flat or 0) > 0) then
			-- An aura pulse: a ring rising around the buffed unit.
			local floor = ground(target)
			FxKit.ring(floor, style.primary, HEX * 0.8, 0.4)
			ImpactEffects.burst("mote", floor + Vector3.new(0, 0.3, 0), Vector3.yAxis, {
				color = style.primary,
				color2 = style.secondary,
				count = 6,
				size = 0.3,
				speed = { 2, 4 },
				lifetime = { 0.4, 0.6 },
				spread = 40,
			})
		end
	elseif kind == "Dot" and target and event.status then
		UnitView.mark(target, event.status, now + CONFIG.dotLinger + 1)
	elseif kind == "Mark" and target then
		UnitView.mark(target, "MARK", now + CONFIG.markDuration)
	elseif kind == "Immune" and view then
		ImpactEffects.ball(view.part.Position, GOLD, view.part.Size.Y * 0.9, 0.25)
		FxKit.ring(ground(view), GOLD, HEX * 0.8, 0.35)
	elseif (kind == "Heal" or kind == "Shield") and target and event.unit ~= event.target then
		-- A heal or shield from another unit: a thin line of the giver's color to it.
		if view and kind == "Heal" then
			FxKit.beam(chest(view), chest(target), style.primary, 0.12, 0.25, "straight")
		end
	end
end

return AbilityFx
