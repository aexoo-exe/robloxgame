-- Runs signature ultimates (UltimateConfig; one module per unit in Ultimates/). An ultimate is a
-- timeline around a unit's real cast, in design seconds relative to the Cast event (negative:
-- before it):
--   pose     pose keys per channel (UnitMotion.ultimatePose): { { t, value, ease? }, ... }
--   poseFor  function(run) -> pose keys, instead of `pose`, for units whose casts differ
--   beats    { { at = t, run = function(run) } }: effects, camera cues, sounds at their moment
--   release  function(run): the moment of the cast; return true to replace the generic release
--   event    function(run, event): each of the caster's events while it runs (its real hits,
--            areas, stuns, shields); return true to replace the generated effect of that event
--   ownClones  true: the ultimate draws its own cast clones (RenderConfig.castClones are skipped)
-- `release` also runs for each FollowUp event (a chained repeat) while the ultimate runs.
-- The anticipation (t < 0) is scaled to the real window before the cast (the playback starts it
-- early from the precomputed event list; a short window after a previous cast compresses it);
-- the release and everything after run at design speed on the cast's real events. Nothing here
-- changes combat or event timing. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local UltimateConfig = require(Shared:WaitForChild("UltimateConfig"))

local CameraCues = require(script.Parent.CameraCues)
local EffectSettings = require(script.Parent.EffectSettings)
local ImpactEffects = require(script.Parent.ImpactEffects)
local Ultimates = require(script.Parent.Ultimates)
local UnitView = require(script.Parent.UnitView)

local Cinematic = {}

local HEX = math.sqrt(3) * RenderConfig.hexRadius
-- How long after the cast its own events are looked for (the longest delayed effect is ~1 s).
local CAST_WINDOW = 1.6

export type Context = {
	views: { [number]: any },
	toWorld: (number, number) -> Vector3,
	now: () -> number,
	ticksPerSecond: number,
	events: { any },
	summonerOf: (number) -> number?,
}

export type Run = {
	unitIndex: number,
	unitType: string,
	view: any,
	style: any,
	tier: number,
	config: any,
	def: any,
	context: Context,
	startAt: number, -- fight time the anticipation starts
	releaseAt: number, -- fight time of the Cast event
	endAt: number,
	k: number, -- anticipation speed: real seconds per design second (<= 1)
	castIndex: number?,
	cast: { any }, -- the cast's own events (caster's, from the Cast event on)
	reduced: boolean, -- EffectSettings.reducedEffects
	pending: { { at: number, run: (any) -> () } },
	memo: { [string]: any }, -- per-run state for the unit module
}

local runs: { [number]: Run } = {} -- by unit index
local connection: RBXScriptConnection? = nil

-- Design time `t` (relative to the release) as fight time.
local function timeOf(run: Run, t: number): number
	return if t < 0 then run.releaseAt + t * run.k else run.releaseAt + t
end

local Methods = {}
Methods.__index = Methods

function Methods.time(self: Run, t: number): number
	return timeOf(self, t)
end

-- Real seconds a design span of `seconds` starting at design time `t` takes (compressed before the
-- release).
function Methods.span(self: Run, t: number, seconds: number): number
	return timeOf(self, t + seconds) - timeOf(self, t)
end

-- Runs `fn(run)` at design time `t`.
function Methods.at(self: Run, t: number, fn: (any) -> ())
	table.insert(self.pending, { at = timeOf(self, t), run = fn })
end

function Methods.now(self: Run): number
	return self.context.now()
end

-- The design time now (relative to the release; the anticipation's compression undone).
function Methods.designTime(self: Run): number
	local now = self.context.now()
	if now < self.releaseAt then
		return (now - self.releaseAt) / math.max(self.k, 1e-3)
	end
	return now - self.releaseAt
end

function Methods.alive(self: Run): boolean
	return self.view ~= nil and self.view.part.Parent ~= nil and UnitView.isAlive(self.view)
end

-- Positions on the caster now (they follow every pose).
function Methods.chest(self: Run): Vector3
	local part = self.view.part
	return part.Position + Vector3.new(0, part.Size.Y * 0.1, 0)
end
function Methods.ground(self: Run): Vector3
	local part = self.view.part
	return part.Position - Vector3.new(0, part.Size.Y / 2, 0)
end
function Methods.head(self: Run): Vector3
	local anchors = self.view.figure.anchors
	if anchors.head and not self.view.figure.isModel then
		return anchors.head.Position
	end
	local part = self.view.part
	return part.Position + Vector3.new(0, part.Size.Y * 0.4, 0)
end
-- A hand ("left" or "right") just past the fist, or the chest for figures with no arms.
function Methods.hand(self: Run, side: string): Vector3
	local anchor = self.view.figure.anchors[side .. "Hand"]
	if anchor and not self.view.figure.isModel then
		return (anchor * CFrame.new(0, -self.view.part.Size.Y * 0.04, 0)).Position
	end
	local part = self.view.part
	local x = if side == "left" then -1 else 1
	return part.Position + (CFrame.Angles(0, self.view.yaw, 0) * Vector3.new(x * part.Size.X * 0.6, 0, -part.Size.Z))
end
-- The caster's facing on the ground plane.
function Methods.forward(self: Run): Vector3
	return CFrame.Angles(0, self.view.yaw, 0).LookVector
end
-- Effect size multiplier (star level).
function Methods.scale(self: Run): number
	return UnitView.effectScale(self.view)
end

-- The cast's first event of `kind` (or of any of `kinds`), if any.
function Methods.find(self: Run, ...: string): any?
	local wanted = { ... }
	for _, event in self.cast do
		if table.find(wanted, event.kind) then
			return event
		end
	end
	return nil
end

-- The cast's area: its center (ground) and radius in studs, from its first Area or AreaStun event,
-- else around its first target, else in front of the caster.
function Methods.area(self: Run): (Vector3, number)
	local event = self:find("AreaStun", "Area")
	if event and event.column then
		return self.context.toWorld(event.column, event.row), ((event.radius or 0) + 0.5) * HEX
	end
	local target = self:target()
	if target then
		return target.part.Position - Vector3.new(0, target.part.Size.Y / 2, 0), HEX * 0.5
	end
	return self:ground() + self:forward() * HEX, HEX * 0.5
end

-- Every unit the cast hits or holds (Damage, Stun, Pull, Knockback targets), first hit first.
function Methods.targets(self: Run): { any }
	local seen, list = {}, {}
	for _, event in self.cast do
		local kind = event.kind
		if (kind == "Damage" or kind == "Stun" or kind == "Pull" or kind == "Knockback") and event.target then
			local view = self.context.views[event.target]
			if view and not seen[event.target] and event.target ~= self.unitIndex then
				seen[event.target] = true
				table.insert(list, view)
			end
		end
	end
	return list
end
function Methods.target(self: Run): any?
	return self:targets()[1]
end

-- A camera cue (CameraCues) from design time `from` to `to`; push in studs, dim 0-1. `key` lets a
-- run hold several cues (a dim and a push) without one replacing the other.
function Methods.camera(
	self: Run,
	from: number,
	to: number,
	cue: { push: number?, dim: number?, focus: Vector3?, rise: number?, fall: number?, key: string? }
)
	CameraCues.request({
		owner = self,
		key = cue.key,
		tier = self.tier,
		startAt = timeOf(self, from),
		endAt = timeOf(self, to),
		rise = cue.rise,
		fall = cue.fall,
		push = cue.push,
		dim = cue.dim,
		focus = cue.focus,
	})
end

-- A cosmetic hit-stop impression on `view` (a unit's pose holds for `seconds`; combat goes on).
function Methods.hitStop(self: Run, view: any?, seconds: number)
	local target = view or self.view
	if target and target.part.Parent then
		UnitView.hitStop(target, seconds, target ~= self.view, true)
	end
end

-- Camera shake, capped by the tier.
function Methods.shake(self: Run, amount: number)
	ImpactEffects.shake(math.min(amount, UltimateConfig.tiers[self.tier].shake))
end

-- A built-in sound by role (UltimateConfig.sounds), not positional, quiet.
function Methods.sound(self: Run, role: string, pitch: number?)
	local spec = UltimateConfig.sounds[role]
	local camera = workspace.CurrentCamera
	if not spec or not camera or not self.view then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = spec.id
	sound.Volume = spec.volume
	sound.PlaybackSpeed = spec.speed * (pitch or 1)
	sound.Parent = camera
	sound:Play()
	task.delay(spec.length or 2, function()
		sound:Destroy()
	end)
end

-- Plays `track` (pose keys) now, its design time 0 at this moment: a follow-up's own motion.
function Methods.pose(self: Run, track: any)
	local now = self.context.now()
	local last = 0
	for _, keys in track do
		if #keys > 0 then
			last = math.max(last, keys[#keys][1])
		end
	end
	UnitView.ultimatePose(self.view, track, now, now, 1, now + last + 0.2)
end

-- The caster's living summons (views).
function Methods.summons(self: Run): { any }
	local list = {}
	for index, view in self.context.views do
		if self.context.summonerOf(index) == self.unitIndex then
			table.insert(list, view)
		end
	end
	return list
end

-- Faces the caster toward `target` (a view) for the rest of the run.
function Methods.face(self: Run, target: any?)
	if target then
		UnitView.face(self.view, target)
	end
end

local function update()
	if next(runs) == nil then
		if connection then
			connection:Disconnect()
			connection = nil
		end
		return
	end
	for unitIndex, run in runs do
		local now = run.context.now()
		for i = #run.pending, 1, -1 do
			local beat = run.pending[i]
			if now >= beat.at then
				table.remove(run.pending, i)
				local ok, err = pcall(beat.run, run)
				if not ok then
					warn("[Cinematic] " .. run.unitType .. ": " .. tostring(err))
				end
			end
		end
		if now > run.endAt then
			runs[unitIndex] = nil
			CameraCues.release(run)
		end
	end
end

-- Whether a unit type has an ultimate.
function Cinematic.has(unitType: string?): boolean
	return unitType ~= nil and UltimateConfig.units[unitType] ~= nil and Ultimates.of(unitType) ~= nil
end

-- The design anticipation of a unit type's ultimate (nil: none).
function Cinematic.preroll(unitType: string?): number?
	if not Cinematic.has(unitType) then
		return nil
	end
	return UltimateConfig.units[unitType :: string].preroll
end

-- The anticipation kept at the least when compressing (UltimateConfig.tiers `minShare`).
function Cinematic.minPreroll(unitType: string): number
	local config = UltimateConfig.units[unitType]
	return config.preroll * UltimateConfig.tiers[config.tier].minShare
end

-- The longest anticipation of any ultimate (for looking ahead in the event list).
function Cinematic.maxPreroll(): number
	local most = 0
	for unitType, config in UltimateConfig.units do
		if Ultimates.of(unitType) then
			most = math.max(most, config.preroll)
		end
	end
	return most
end

-- The cast's own events: the caster's from the Cast event at `castIndex` on, until its next cast
-- or CAST_WINDOW seconds later.
local function castEvents(context: Context, unitIndex: number, castIndex: number?): { any }
	local list = {}
	if not castIndex then
		return list
	end
	local events = context.events
	local first = events[castIndex]
	local lastTick = first.tick + CAST_WINDOW * context.ticksPerSecond
	for i = castIndex + 1, #events do
		local event = events[i]
		if event.tick > lastTick then
			break
		end
		if event.unit == unitIndex then
			if event.kind == "Cast" then
				break
			end
			table.insert(list, event)
		end
	end
	return list
end

-- Starts unit `unitIndex`'s ultimate: anticipation from `startAt` (fight time) to the cast at
-- `releaseAt`. Returns false if it has none.
function Cinematic.start(
	context: Context,
	unitIndex: number,
	unitType: string,
	view: any,
	style: any,
	startAt: number,
	releaseAt: number,
	castIndex: number?
): boolean
	local def = Ultimates.of(unitType)
	local config = UltimateConfig.units[unitType]
	if not def or not config then
		return false
	end
	local now = context.now()
	local from = math.max(startAt, now)
	local k = math.clamp((releaseAt - from) / config.preroll, 0, 1)
	local run: Run = setmetatable({
		unitIndex = unitIndex,
		unitType = unitType,
		view = view,
		style = style,
		tier = config.tier,
		config = config,
		def = def,
		context = context,
		startAt = from,
		releaseAt = releaseAt,
		endAt = releaseAt + config.linger,
		k = k,
		castIndex = castIndex,
		cast = castEvents(context, unitIndex, castIndex),
		reduced = EffectSettings.reducedEffects(),
		pending = {},
		memo = {},
	}, Methods) :: any
	runs[unitIndex] = run
	-- `poseFor(run)` picks the pose keys from the cast's own events (a unit whose casts differ).
	local track = if def.poseFor then def.poseFor(run) else def.pose
	if track then
		-- The pose layer ends just after its last key (a long linger keeps only its effects), so the
		-- unit's own attacks show again.
		local last = -math.huge
		for _, keys in track do
			if #keys > 0 then
				last = math.max(last, keys[#keys][1])
			end
		end
		local poseEnd = math.min(run.endAt, timeOf(run, last) + 0.2)
		UnitView.ultimatePose(view, track, from, releaseAt, k, poseEnd)
	end
	for _, beat in def.beats or {} do
		-- Beats before the window (a late start) are skipped; t >= -preroll always fits.
		if timeOf(run, beat.at) >= from - 1e-3 or beat.at >= 0 then
			run:at(beat.at, beat.run)
		end
	end
	if not connection then
		connection = RunService.RenderStepped:Connect(update)
	end
	return true
end

-- The running ultimate of a unit, if any.
function Cinematic.running(unitIndex: number): Run?
	return runs[unitIndex]
end

-- The cast's release: the ultimate's own, if it has one. Returns true when it drew it.
function Cinematic.release(unitIndex: number): boolean
	local run = runs[unitIndex]
	if not run or not run.def.release then
		return false
	end
	local ok, result = pcall(run.def.release, run)
	if not ok then
		warn("[Cinematic] " .. run.unitType .. " release: " .. tostring(result))
		return false
	end
	return result == true
end

-- One of the caster's events while its ultimate runs. Returns true when the ultimate drew it
-- (the generated effect is skipped).
function Cinematic.event(event): boolean
	local run = runs[event.unit]
	if not run or not run.def.event then
		return false
	end
	local ok, result = pcall(run.def.event, run, event)
	if not ok then
		warn("[Cinematic] " .. run.unitType .. " event: " .. tostring(result))
		return false
	end
	return result == true
end

-- Ends every ultimate (the playback ended).
function Cinematic.clear()
	table.clear(runs)
	CameraCues.clear()
end

return Cinematic
