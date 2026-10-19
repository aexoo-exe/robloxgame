-- Hit feel for ultimates and big hits: hit-stop on the units involved (their poses and the effects
-- around them), a capped camera shake with falloff, a quick zoom punch-in, and the target's
-- reaction (a white flash, a knockback slide, a stagger). Local and presentation only: the fight
-- runs on, no unit's real position changes (the knockback is UnitView's pose offset, which returns
-- to zero), and every time runs on the effects' clock (ImpactEffects.now), so slow motion slows it.
--
-- Use (from an ultimate module, `run` its Cinematic run):
--   HitFeel.hitStop({ run.view, target }, 0.07, { caster = run.view })
--   HitFeel.cameraShake(0.15, 0.2)            -- a strike; the finisher ~0.3 for 0.35 s
--   HitFeel.punchIn(1)                        -- the finisher only
--   HitFeel.react(target, run:chest(), { final = true })
-- HitFeel.SETTINGS holds the caps; HitFeel.setFocused(true) while one ultimate is the focus (the
-- dev lineup's close-ups and reel) gives the full punch-in, otherwise it stays mild.

local RunService = game:GetService("RunService")

local EffectSettings = require(script.Parent.EffectSettings)
local ImpactEffects = require(script.Parent.ImpactEffects)
local UnitView = require(script.Parent.UnitView)

local HitFeel = {}

HitFeel.SETTINGS = {
	maxShake = 0.4, -- the most trauma (0-1) one shake may add
	shakeWindow = 1.5, -- seconds over which shakes add up toward the budget
	shakeBudget = 0.8, -- trauma per window before new shakes are scaled down (many ultimates at once)
	shakeFloor = 0.25, -- a shake past the budget keeps at least this share
	reducedShake = 0.35, -- shake share with ReducedCameraMotion (punch-ins are off then)
	punchFocused = 8, -- degrees of field of view a full punch-in takes when focused
	punchNormal = 2.5, -- ... and in a normal match
	punchSeconds = 0.15,
	freezeRadius = 6, -- studs around each held unit whose effects pause with it
	knock = 1, -- studs a strike slides its target (normal size)
	finalKnock = 1.8, -- the finisher's
}
local S = HitFeel.SETTINGS

local focused = false

-- Whether one ultimate is the focus of the screen (dev close-ups, the reel): full punch-ins.
function HitFeel.setFocused(on: boolean)
	focused = on
end

-- Hit-stop: each view holds its pose for `seconds` (the ones hit jitter; `opts.caster` holds still),
-- and the particles out around them pause as long.
function HitFeel.hitStop(views: { any }, seconds: number, opts: { caster: any? }?)
	local caster = opts and opts.caster
	local points = {}
	for _, view in views do
		if view and view.part and view.part.Parent then
			UnitView.hitStop(view, seconds, view ~= caster, true)
			table.insert(points, view.part.Position)
		end
	end
	ImpactEffects.freezeNear(points, S.freezeRadius, seconds)
end

-- Recent shakes (effects-clock time, trauma), for the budget.
local recent: { { at: number, amount: number } } = {}

-- A camera shake of `intensity` (0-1 trauma) over `duration` seconds, falling off to nothing. Capped
-- at SETTINGS.maxShake, scaled down once the shakes of the last shakeWindow seconds pass the budget
-- (so a fight full of ultimates never gets nauseating), and cut with ReducedCameraMotion.
function HitFeel.cameraShake(intensity: number, duration: number)
	local now = ImpactEffects.now()
	local spent = 0
	for i = #recent, 1, -1 do
		local entry = recent[i]
		if now - entry.at > S.shakeWindow or now < entry.at then
			table.remove(recent, i)
		else
			spent += entry.amount
		end
	end
	local share = math.clamp(1 - spent / S.shakeBudget, S.shakeFloor, 1)
	local amount = math.min(intensity, S.maxShake) * share
	if EffectSettings.reducedCameraMotion() then
		amount *= S.reducedShake
	end
	table.insert(recent, { at = now, amount = amount })
	ImpactEffects.shakeFor(amount, duration)
end

-- The punch-in: the field of view narrows quickly and eases back (a zoom kick), `strength` 0-1 of
-- SETTINGS.punchFocused (focused) or punchNormal degrees, over `seconds` (default punchSeconds).
-- The camera's own field of view is put back exactly when it ends. None with ReducedCameraMotion.
local punch: { base: number, degrees: number, startsAt: number, seconds: number, realStart: number }? = nil
local punchConnection: RBXScriptConnection? = nil

local function endPunch()
	if punchConnection then
		punchConnection:Disconnect()
		punchConnection = nil
	end
	local camera = workspace.CurrentCamera
	if punch and camera then
		camera.FieldOfView = punch.base
	end
	punch = nil
end

function HitFeel.punchIn(strength: number, seconds: number?)
	local camera = workspace.CurrentCamera
	if not camera or EffectSettings.reducedCameraMotion() then
		return
	end
	local degrees = (if focused then S.punchFocused else S.punchNormal) * math.clamp(strength, 0, 1)
	if degrees <= 0 then
		return
	end
	-- A punch already running keeps its base (the camera's real field of view).
	local base = if punch then punch.base else camera.FieldOfView
	punch = {
		base = base,
		degrees = degrees,
		startsAt = ImpactEffects.now(),
		seconds = seconds or S.punchSeconds,
		realStart = os.clock(),
	}
	if punchConnection then
		return
	end
	punchConnection = RunService.RenderStepped:Connect(function()
		local p = punch
		local cam = workspace.CurrentCamera
		if not p or not cam then
			endPunch()
			return
		end
		local t = (ImpactEffects.now() - p.startsAt) / p.seconds
		-- Done, the clock reset under it, or held far too long (a freeze): put the camera back.
		if t >= 1 or t < 0 or os.clock() - p.realStart > 5 then
			endPunch()
			return
		end
		-- In over the first quarter, out over the rest.
		local shape = if t < 0.25 then 1 - (1 - t / 0.25) ^ 2 else (1 - (t - 0.25) / 0.75) ^ 2
		cam.FieldOfView = p.base - p.degrees * shape
	end)
end

export type ReactOptions = {
	final: boolean?, -- the finisher: knocked further (SETTINGS.finalKnock)
	knock: number?, -- studs (normal size), instead of the default
}

-- A target's reaction to a hit from `from` (a point: the attacker or its blade): a white flash
-- (UnitView's hit flash, a Highlight on avatars), a knockback slide away from `from` that eases back,
-- and a stagger (the hit pose: lean back, head snap, arms flail) that recovers.
function HitFeel.react(view: any, from: Vector3, opts: ReactOptions?)
	if not view or not view.part or not view.part.Parent or not UnitView.isAlive(view) then
		return
	end
	local o = opts or {}
	local knock = o.knock or (if o.final then S.finalKnock else S.knock)
	UnitView.flash(view, false, view.part.Position - from, knock)
end

-- Drops a running punch-in (a fight or preview ends).
function HitFeel.clear()
	endPunch()
	table.clear(recent)
end

return HitFeel
