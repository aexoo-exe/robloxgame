-- elastic_wardrum (Tier 4): the gears, each with its own look; the last one goofy and godlike. The
-- real casts: the first steps him into Gear 2, the second into Gear 3 (the white form), and every
-- cast after shields him and slams everything next to him, all at the Cast event. One timeline,
-- three choreographies, picked from the cast's real events.
-- Into Gear 2:
--   -0.60  he pumps his legs, bouncing; steam pours off him, pink-white
--    0     the real form change: a gush of steam
-- Into Gear 3:
--   -0.60  thumb to his mouth: he bites and blows; he swells, rocking back
--    0     the real form change: a burst of white clouds and white flame; he laughs, arms wide
-- The slam (Gear 3 casts):
--   -0.60  drumbeats: rhythmic white rings thump out from his feet; stillness on the last beat
--    0     a giant stretched fist slams down around him on the real hit: a cartoon shockwave that
--          bounces, and the shimmer of his real shield

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local STEAM = Color3.fromRGB(255, 215, 220)
local SKIN = Color3.fromRGB(240, 200, 160)

local def = {}

-- Which cast this is: "gear2", "gear3" or "slam".
local function kindOf(run): string
	for _, event in run.cast do
		if event.kind == "Form" then
			return if (event.formIndex or 0) >= 3 then "gear3" else "gear2"
		end
	end
	return "slam"
end

local POSES = {
	gear2 = {
		crouch = {
			{ -0.6, 0 },
			{ -0.5, 0.22 },
			{ -0.4, 0.02 },
			{ -0.3, 0.22 },
			{ -0.2, 0.02 },
			{ -0.1, 0.24 },
			{ 0, 0.05, "snap" },
			{ 0.4, 0 },
		},
		leftArm = { { -0.6, 0 }, { -0.5, 30 }, { 0, 30 }, { 0.05, 60, "snap" }, { 0.5, 0 } },
		rightArm = { { -0.6, 0 }, { -0.5, 30 }, { 0, 30 }, { 0.05, 60, "snap" }, { 0.5, 0 } },
		lean = { { -0.6, 0 }, { -0.5, 10 }, { 0, 10 }, { 0.05, -6, "snap" }, { 0.5, 0 } },
	},
	gear3 = {
		rightArm = { { -0.6, 0 }, { -0.45, 150, "out" }, { -0.1, 150 }, { 0.05, 40, "snap" }, { 0.5, 30 }, { 0.8, 0 } },
		rightArmOut = { { -0.6, 0 }, { -0.45, -22 }, { -0.1, -22 }, { 0.05, 80, "snap" }, { 0.5, 80 }, { 0.8, 0 } },
		leftArmOut = { { -0.1, 0 }, { 0.05, 80, "snap" }, { 0.5, 80 }, { 0.8, 0 } },
		leftArm = { { -0.1, 0 }, { 0.05, 40, "snap" }, { 0.5, 30 }, { 0.8, 0 } },
		lean = { { -0.6, 0 }, { -0.3, -8 }, { -0.1, -12 }, { 0.05, -16, "back" }, { 0.5, -10 }, { 0.8, 0 } },
		crouch = { { -0.45, 0 }, { -0.1, 0.1 }, { 0.05, 0, "snap" } },
		rise = { { -0.02, 0 }, { 0.1, 0.5, "back" }, { 0.5, 0 } },
		tremble = { { 0.05, 0 }, { 0.1, 1.5 }, { 0.45, 1.5 }, { 0.5, 0, "hold" } },
	},
	slam = {
		crouch = { { -0.6, 0 }, { -0.45, 0.1 }, { -0.3, 0.02 }, { -0.15, 0.12 }, { 0, 0.2, "snap" }, { 0.4, 0 } },
		rightArm = { { -0.6, 0 }, { -0.15, 170, "out" }, { -0.02, 175 }, { 0.04, 40, "snap" }, { 0.5, 0 } },
		leftArm = { { -0.6, 0 }, { -0.3, 30 }, { 0.5, 0 } },
		lean = { { -0.15, 0 }, { -0.02, -8 }, { 0.04, 14, "snap" }, { 0.5, 0 } },
	},
}

function def.poseFor(run)
	return POSES[kindOf(run)]
end

local function steam(run, color: Color3, count: number)
	ImpactEffects.burst("puff", run:chest(), Vector3.yAxis, {
		color = color,
		count = count,
		size = 1,
		speed = { 2, 5 },
		lifetime = { 0.5, 0.9 },
		spread = 70,
		transparency = 0.4,
	})
end

def.beats = {
	{
		at = -0.6,
		run = function(run)
			run.memo.kind = kindOf(run)
			local kind = run.memo.kind
			if kind == "gear2" then
				for t = -0.55, 0, 0.1 do
					run:at(t, function()
						steam(run, STEAM, if run.reduced then 3 else 6)
					end)
				end
				run:sound("whoosh", 1.2)
			elseif kind == "gear3" then
				-- The thumb at his mouth, the blow, the swell.
				Kit.orb(run, -0.4, -0.05, SKIN, function()
					return run:head() + run:forward() * 0.6
				end, function(u)
					return (0.2 + 0.9 * u) * run:scale()
				end)
				run:sound("charge", 0.9)
			else
				-- Drumbeats: a ring and a tick on each beat, the last one held.
				for i, t in { -0.55, -0.4, -0.25 } do
					run:at(t, function()
						FxKit.ring(run:ground(), WHITE, (4 + i) * run:scale(), 0.25)
						run:sound("tick", 0.7 + i * 0.1)
					end)
				end
			end
		end,
	},
	{
		-- The slam's fist, stretching down from above onto the area.
		at = -0.14,
		run = function(run)
			if run.memo.kind ~= "slam" then
				return
			end
			local center = run:area()
			local top = run:hand("right") + Vector3.new(0, 7, 0)
			local red = run.style.primary
			Kit.live(run, -0.14, 0.12, "Ball", SKIN, function(part, u)
				local down = math.min(1, Kit.easeIn(u * 1.6))
				part.Size = Vector3.one * 3.2 * run:scale()
				part.CFrame = CFrame.new(top:Lerp(center + Vector3.new(0, 1.6, 0), down))
				part.Transparency = 0
			end, Enum.Material.SmoothPlastic)
			Kit.live(run, -0.14, 0.12, "Block", red, function(part, u)
				local down = math.min(1, Kit.easeIn(u * 1.6))
				local fist = top:Lerp(center + Vector3.new(0, 1.6, 0), down)
				local shoulder = run:hand("right")
				local length = math.max((fist - shoulder).Magnitude, 0.05)
				part.Size = Vector3.new(0.9, 0.9, length)
				part.CFrame = CFrame.lookAt((fist + shoulder) / 2, fist)
				part.Transparency = 0
			end, Enum.Material.SmoothPlastic)
		end,
	},
}

function def.release(run): boolean
	return run.memo.kind ~= nil
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Form" then
		if run.memo.kind == "gear3" then
			-- White clouds and white flame; he laughs.
			ImpactEffects.ball(run:chest(), WHITE, run.view.part.Size.Y * 1.3, 0.2)
			for i = 1, (if run.reduced then 3 else 6) do
				local angle = i / 6 * 2 * math.pi
				ImpactEffects.burst(
					"puff",
					run:ground() + Vector3.new(math.cos(angle) * 2, 1, math.sin(angle) * 2),
					Vector3.yAxis,
					{
						color = WHITE,
						count = 5,
						size = 1.8,
						speed = { 2, 4 },
						lifetime = { 0.6, 1 },
						spread = 50,
						transparency = 0.25,
					}
				)
			end
			Kit.aura(run, 0, 0.5, WHITE, if run.reduced then 5 else 9, function(u)
				return run.view.part.Size.Y * (1 - 0.5 * u)
			end)
			run:shake(0.3)
			run:sound("chime", 0.7)
		else
			steam(run, STEAM, 14)
			FxKit.ring(run:ground(), STEAM, 6, 0.4)
			run:shake(0.15)
		end
		return true
	elseif kind == "Area" then
		-- The cartoon shockwave: it overshoots and bounces back.
		local center, radius = run:area()
		ImpactEffects.ball(center + Vector3.new(0, 1, 0), WHITE, radius * 1.2, 0.12)
		FxKit.ring(center, WHITE, radius * 2.8, 0.25)
		FxKit.ring(center, run.style.secondary, radius * 2.2, 0.35, 0.18)
		FxKit.ring(center, WHITE, radius * 2.5, 0.25, 0.32)
		FxKit.mark(center, Kit.DUST, WHITE, radius * 0.8, "crack", 1)
		for _, target in run:targets() do
			run:hitStop(target, 0.1)
		end
		run:shake(0.32)
		run:sound("whoosh", 0.7)
		return true
	elseif kind == "Shield" and event.target == run.unitIndex then
		Kit.shell(run, 0, 0.4, WHITE, run.view.part.Position, function(u)
			return run.view.part.Size.Y * (1.3 + 0.2 * u)
		end, function(u)
			return 0.7 + 0.3 * u
		end)
		return false
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
