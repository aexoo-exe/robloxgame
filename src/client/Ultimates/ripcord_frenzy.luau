-- ripcord_frenzy (Tier 1): pull the cord, and the rev. His real first cast changes him into the
-- chainsaw form for the fight (a Form event); every later cast heals him. No blood.
-- First cast:
--   -0.25  he grabs the cord on his chest and yanks it out
--    0     the engine revs on the real form change: smoke puffs and orange sparks as the blades come
--          out; a hunched roar
-- Later casts:
--   -0.25  he revs the saws: a shudder, orange sparks, a small green-orange glow for the heal

local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local SMOKE = Color3.fromRGB(70, 66, 64)
local SPARK = Color3.fromRGB(255, 160, 50)
local HEAL = Color3.fromRGB(190, 220, 90)

local def = {}

local function changing(run): boolean
	return run:find("Form") ~= nil
end

local PULL = {
	rightArm = { { -0.25, 0 }, { -0.15, 60 }, { -0.08, 60 }, { -0.02, 20, "snap" }, { 0.2, 20 }, { 0.45, 0 } },
	rightArmOut = { { -0.25, 0 }, { -0.15, -32 }, { -0.08, -32 }, { -0.02, 65, "snap" }, { 0.2, 50 }, { 0.45, 0 } },
	lean = { { -0.25, 0 }, { -0.02, -6 }, { 0.08, 22, "snap" }, { 0.45, 10 }, { 0.6, 0 } },
	crouch = { { 0, 0 }, { 0.08, 0.2, "snap" }, { 0.6, 0 } },
	tremble = { { 0, 0 }, { 0.05, 1.6 }, { 0.4, 1.6 }, { 0.45, 0, "hold" } },
}

local REV = {
	leftArm = { { -0.25, 0 }, { -0.15, 60 }, { 0.2, 60 }, { 0.4, 0 } },
	rightArm = { { -0.25, 0 }, { -0.15, 60 }, { 0.2, 60 }, { 0.4, 0 } },
	tremble = { { -0.2, 0 }, { -0.15, 1.2 }, { 0.2, 1.2 }, { 0.25, 0, "hold" } },
	crouch = { { -0.25, 0 }, { -0.15, 0.1 }, { 0.4, 0 } },
}

function def.poseFor(run)
	return if changing(run) then PULL else REV
end

local function sparks(run, count: number)
	ImpactEffects.burst("spark", run:chest(), nil, {
		color = SPARK,
		count = count,
		size = 0.2,
		speed = { 6, 12 },
		lifetime = { 0.15, 0.35 },
	})
end

def.beats = {
	{
		at = -0.25,
		run = function(run)
			if not changing(run) then
				sparks(run, 8)
				run:at(-0.1, function()
					sparks(run, 6)
				end)
				run:sound("tick", 0.6)
			end
		end,
	},
}

function def.release(run): boolean
	if not changing(run) then
		FxKit.ring(run:ground(), HEAL, 3.4, 0.35)
	end
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Form" then
		ImpactEffects.burst("smoke", run:chest(), Vector3.yAxis, {
			color = SMOKE,
			count = 10,
			size = 0.9,
			speed = { 2, 4 },
			lifetime = { 0.4, 0.7 },
			spread = 60,
			transparency = 0.3,
		})
		sparks(run, 16)
		run:shake(0.08)
		run:sound("whoosh", 0.5)
		return true
	elseif kind == "Heal" and event.target == run.unitIndex then
		ImpactEffects.burst("mote", run:chest(), Vector3.yAxis, {
			color = HEAL,
			color2 = SPARK,
			count = 6,
			size = 0.3,
			speed = { 2, 4 },
			lifetime = { 0.4, 0.6 },
			spread = 40,
		})
		return true
	end
	return false
end

return def
