-- field_medic (Tier 2): cute medic, then giant monster. As a medic his real cast heals every ally;
-- once below half health he turns into a melee bruiser for the rest of the fight (a real form
-- change from a health trigger, not a cast: it plays as a shift), whose cast is a heavy hit.
-- Medic cast:
--   -0.30  he pops a little medicine bag; a soft green cross shines above him
--    0     gentle green waves roll out to every ally he really heals, motes rising on each
-- Bruiser cast:
--   -0.30  shoulders up, claws back
--    0     a heavy swipe on the real hit: three claw marks
-- The change into the bruiser (shift):
--    0     a blue pill: a blue flash at his mouth; he swells inside a puff of fur and steam; a roar
--          and a ground shake

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local PILL = Color3.fromRGB(70, 130, 240)
local FUR = Color3.fromRGB(212, 172, 118)
local CLAW = Color3.fromRGB(40, 35, 35)

local def = {}

def.shiftLinger = 1.0

local function healing(run): boolean
	return run:find("Heal") ~= nil
end

local MEDIC = {
	rightArm = { { -0.3, 0 }, { -0.15, 70 }, { 0, 60 }, { 0.04, 130, "snap" }, { 0.35, 120 }, { 0.5, 0 } },
	leftArm = { { -0.3, 0 }, { 0.04, 40, "snap" }, { 0.5, 0 } },
	leftArmOut = { { -0.3, 0 }, { 0.04, 35 }, { 0.5, 0 } },
	lean = { { -0.3, 0 }, { 0.04, -6, "snap" }, { 0.5, 0 } },
}

local BRUISER = {
	rightArm = { { -0.3, 0 }, { -0.15, 140 }, { -0.02, 145 }, { 0.04, 30, "snap" }, { 0.35, 20 }, { 0.5, 0 } },
	rightArmOut = { { -0.3, 0 }, { -0.15, 30 }, { 0.04, -10, "snap" }, { 0.5, 0 } },
	twist = { { -0.3, 0 }, { -0.15, -20 }, { 0.04, 26, "snap" }, { 0.5, 0 } },
	lean = { { -0.3, 0 }, { -0.15, -6 }, { 0.04, 16, "snap" }, { 0.5, 0 } },
	crouch = { { -0.15, 0 }, { 0.04, 0.15, "snap" }, { 0.5, 0 } },
}

local ROAR = {
	lean = { { 0, 0 }, { 0.15, 10 }, { 0.35, -14, "back" }, { 0.8, 0 } },
	crouch = { { 0, 0.2 }, { 0.3, 0 } },
	leftArmOut = { { 0.2, 0 }, { 0.35, 50 }, { 0.75, 50 }, { 0.95, 0 } },
	rightArmOut = { { 0.2, 0 }, { 0.35, 50 }, { 0.75, 50 }, { 0.95, 0 } },
	tremble = { { 0.35, 0 }, { 0.4, 1.4 }, { 0.75, 1.4 }, { 0.8, 0, "hold" } },
}

function def.poseFor(run)
	return if healing(run) then MEDIC else BRUISER
end

def.beats = {
	{
		at = -0.3,
		run = function(run)
			if not healing(run) then
				run:face(run:target())
				return
			end
			local green = run.style.primary
			-- The green cross above him.
			for _, turn in { 0, math.pi / 2 } do
				Kit.block(run, -0.28, 0.35, green, function()
					return CFrame.new(run:head() + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, run:now() * 2, turn)
				end, function()
					return Vector3.new(0.9, 0.28, 0.12)
				end, function(u)
					return if u > 0.8 then 0.2 + (u - 0.8) * 4 else 0.2
				end)
			end
			ImpactEffects.ball(run:hand("right"), WHITE, 0.6, 0.12)
			run:sound("chime", 1.2)
		end,
	},
}

function def.release(run): boolean
	if healing(run) then
		FxKit.ring(run:ground(), run.style.primary, 6, 0.5)
		FxKit.ring(run:ground(), run.style.secondary, 9, 0.6, 0.1)
	end
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Heal" and event.target then
		local view = run.context.views[event.target]
		if view then
			local floor = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
			FxKit.ring(floor, run.style.secondary, 3.2, 0.4, 0.12)
			ImpactEffects.burst("mote", floor + Vector3.new(0, 0.4, 0), Vector3.yAxis, {
				color = run.style.primary,
				color2 = WHITE,
				count = 6,
				size = 0.3,
				speed = { 2, 4 },
				lifetime = { 0.4, 0.7 },
				spread = 30,
			})
		end
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view then
			local at = view.part.Position + Vector3.new(0, view.part.Size.Y * 0.1, 0)
			local facing = view.part.Position - run.view.part.Position
			FxKit.slashArc(at, facing, CLAW, 2.6, 1.0, 0.3)
			ImpactEffects.ball(at, FUR, 1.6, 0.1)
			run:hitStop(view, 0.07)
			run:shake(0.12)
		end
		return true
	end
	return false
end

-- The change into the bruiser: the blue pill, the swell, the roar.
function def.shift(run, event): boolean
	if (event.formIndex or 1) < 2 then
		return false
	end
	run:pose(ROAR)
	ImpactEffects.ball(run:head(), PILL, 1.4, 0.15)
	run:at(0.12, function()
		ImpactEffects.burst("puff", run:chest(), nil, {
			color = FUR,
			color2 = WHITE,
			count = 14,
			size = 1.6,
			speed = { 3, 6 },
			lifetime = { 0.5, 0.8 },
			transparency = 0.3,
		})
	end)
	run:at(0.35, function()
		FxKit.ring(run:ground(), FUR, 8, 0.45)
		run:shake(0.12)
		run:sound("whoosh", 0.6)
	end)
	return true
end

return def
