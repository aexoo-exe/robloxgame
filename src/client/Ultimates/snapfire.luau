-- snapfire (Tier 3): one small snap, one big fire. The real cast blasts everything within 1 hex of
-- his target (harder on enemies already burning) and sets them burning, at the Cast event.
--   -0.45  he raises his gloved hand, calm, two fingers ready; a faint circle of sparks on the glove
--   -0.18  SNAP: a tiny bright spark at his fingers
--   -0.15  a thin fuse of fire races along the ground to the target
--    0     the real hit: orange flame over the target and its neighbors, black smoke; a second,
--          bigger burst when his target was already burning
--   +0.30  he lowers his hand, unbothered (the burning markers are the real burns)

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local SMOKE = Color3.fromRGB(30, 26, 26)

local def = {}

def.pose = {
	rightArm = { { -0.45, 0 }, { -0.25, 85, "out" }, { -0.2, 88 }, { -0.17, 95, "snap" }, { 0.3, 90 }, { 0.6, 0 } },
	rightArmOut = { { -0.45, 0 }, { -0.25, 8 }, { 0.6, 0 } },
	leftArm = { { -0.45, 0 }, { -0.25, -10 }, { 0.6, 0 } },
	lean = { { -0.45, 0 }, { -0.25, -3 }, { -0.17, -1, "snap" }, { 0.6, 0 } },
}

-- Whether his target was already burning: a BURN damage over time on it in the last 3 seconds.
local function wasBurning(run, targetIndex: number): boolean
	local events = run.context.events
	local index = run.castIndex
	if not index then
		return false
	end
	local castTick = events[index].tick
	for i = index - 1, 1, -1 do
		local event = events[i]
		if castTick - event.tick > 3 * run.context.ticksPerSecond then
			break
		end
		if event.kind == "Dot" and event.status == "BURN" and event.target == targetIndex then
			return true
		end
	end
	return false
end

def.beats = {
	{
		at = -0.45,
		run = function(run)
			run:face(run:target())
			Kit.live(run, -0.42, -0.18, "Cylinder", run.style.secondary, function(part, u)
				local d = 0.9 * run:scale()
				part.Size = Vector3.new(0.04, d, d)
				part.CFrame = CFrame.new(run:hand("right")) * CFrame.Angles(0, run:now() * 6, math.pi / 2)
				part.Transparency = 0.5 + 0.3 * u
			end)
		end,
	},
	{
		at = -0.18,
		run = function(run)
			ImpactEffects.ball(run:hand("right"), WHITE, 0.6, 0.08)
			run:sound("tick", 1.4)
		end,
	},
	{
		-- The fuse racing along the ground.
		at = -0.15,
		run = function(run)
			local center = run:area()
			Kit.groove(run, -0.15, 0.3, run.style.primary, run:ground(), center, 0.25)
			for i = 1, 4 do
				run:at(-0.15 + i * 0.035, function()
					local at = run:ground():Lerp(center, i / 4)
					ImpactEffects.burst("flame", at + Vector3.new(0, 0.2, 0), Vector3.yAxis, {
						color = run.style.primary,
						color2 = run.style.secondary,
						count = 3,
						size = 0.5,
						speed = { 1, 3 },
						lifetime = { 0.2, 0.35 },
						spread = 20,
					})
				end)
			end
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		local center, radius = run:area()
		local air = center + Vector3.new(0, 1, 0)
		ImpactEffects.ball(air, run.style.secondary, radius * 1.3, 0.14)
		Kit.shell(run, 0, 0.35, run.style.primary, air, function(u)
			return radius * 2.1 * Kit.easeOut(u)
		end, function(u)
			return 0.25 + 0.75 * u
		end)
		ImpactEffects.burst("flame", center + Vector3.new(0, 0.5, 0), Vector3.yAxis, {
			color = run.style.primary,
			color2 = run.style.secondary,
			count = 16,
			size = 1.3,
			speed = { 3, 7 },
			lifetime = { 0.35, 0.6 },
			spread = 50,
		})
		ImpactEffects.burst("smoke", air, Vector3.yAxis, {
			color = SMOKE,
			count = 8,
			size = 1.2,
			speed = { 2, 4 },
			lifetime = { 0.6, 1 },
			spread = 40,
			transparency = 0.35,
		})
		FxKit.mark(center, run.style.primary, run.style.secondary, radius, "scorch", 0.9)
		local target = run:find("Damage")
		if target and target.target and wasBurning(run, target.target) then
			-- Already burning: the bigger second burst.
			run:at(0.12, function()
				ImpactEffects.ball(air, WHITE, radius * 1.6, 0.12)
				FxKit.ring(center, run.style.secondary, radius * 2.8, 0.35)
				ImpactEffects.burst("flame", air, nil, {
					color = run.style.secondary,
					color2 = run.style.primary,
					count = 14,
					size = 1.1,
					speed = { 5, 9 },
					lifetime = { 0.3, 0.5 },
				})
			end)
		end
		run:shake(0.16)
		run:sound("whoosh", 0.9)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
