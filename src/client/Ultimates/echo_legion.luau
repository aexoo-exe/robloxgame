-- echo_legion (Tier 4): clones form it, then the wind sphere. The real cast hits a 2-hex area at his
-- target four times, at 0.25, 0.5, 0.75 and 1 s after the Cast event (the clones are visual only;
-- this ultimate draws its own, the generic cast clones are skipped).
--   -0.90  two shadow clones pop in beside him in puffs of smoke
--   -0.60  his hand rises; the clones reach in to help form a blue sphere over it, four white wind
--          blades spinning out of it with a rising whine
--   -0.10  the clones vanish in smoke
--    0     he throws: the spinning sphere flies to the target
--   +0.25  the first real hit: it opens into a wide white-blue sphere of wind over the area; a pulse
--          and quick cuts on each real hit after
--   +1.00  the last real hit: the sphere collapses in a final burst

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local SMOKE = Color3.fromRGB(235, 235, 235)

local def = {}

def.ownClones = true

def.pose = {
	rightArm = {
		{ -0.9, 0 },
		{ -0.6, 160, "out" },
		{ -0.1, 165 },
		{ -0.02, 175 },
		{ 0.04, 80, "snap" },
		{ 0.4, 70 },
		{ 0.8, 0 },
	},
	leftArm = { { -0.9, 0 }, { -0.6, 30 }, { 0.04, 10, "snap" }, { 0.8, 0 } },
	twist = { { -0.6, 0 }, { -0.1, -14 }, { 0.04, 22, "snap" }, { 0.4, 10 }, { 0.8, 0 } },
	lean = { { -0.6, 0 }, { -0.1, -8 }, { 0.04, 10, "snap" }, { 0.4, 4 }, { 0.8, 0 } },
	lunge = { { 0.02, 0 }, { 0.06, 0.3, "snap" }, { 0.45, 0 } },
}

-- Over his raised hand.
local function overHand(run): Vector3
	return run:hand("right") + Vector3.new(0, 0.8, 0)
end

-- A shadow clone at `side` (-1 left, 1 right): a see-through figure reaching toward his sphere.
local function clone(run, side: number)
	local h = run.view.part.Size.Y
	local function base(): CFrame
		local forward = run:forward()
		local across = Vector3.new(-forward.Z, 0, forward.X) * side
		local at = run:ground() + across * h * 0.55 - forward * 0.3 + Vector3.new(0, h * 0.5, 0)
		return CFrame.lookAt(at, at + forward)
	end
	local color = run.style.primary
	local function fade(u): number
		return if u < 0.08 then 1 - u * 6 elseif u > 0.9 then 0.5 + (u - 0.9) * 5 else 0.5
	end
	Kit.block(run, -0.9, -0.1, color, function()
		return base()
	end, function()
		return Vector3.new(h * 0.36, h * 0.6, h * 0.2)
	end, fade, Enum.Material.Neon)
	Kit.block(run, -0.9, -0.1, color:Lerp(WHITE, 0.3), function()
		return base() * CFrame.new(0, h * 0.42, 0)
	end, function()
		return Vector3.one * h * 0.22
	end, fade, Enum.Material.Neon)
	-- Its inner arm, raised toward the sphere.
	Kit.block(run, -0.9, -0.1, color, function()
		return base() * CFrame.new(-side * h * 0.22, h * 0.32, -h * 0.05) * CFrame.Angles(0, 0, side * 0.6)
	end, function()
		return Vector3.new(h * 0.1, h * 0.4, h * 0.1)
	end, fade, Enum.Material.Neon)
	for _, at in { -0.9, -0.12 } do
		run:at(at, function()
			ImpactEffects.burst("puff", base().Position, nil, {
				color = SMOKE,
				count = 8,
				size = 1,
				speed = { 2, 4 },
				lifetime = { 0.3, 0.5 },
				transparency = 0.3,
			})
		end)
	end
end

-- Four white blades spinning around `center()`, `reach(u)` studs out.
local function blades(run, from: number, to: number, center: () -> Vector3, reach: (number) -> number)
	for i = 1, 4 do
		Kit.block(run, from, to, WHITE, function(u)
			local angle = i * math.pi / 2 + run:now() * 16
			local r = reach(u)
			return CFrame.new(center() + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r))
				* CFrame.Angles(0, -angle, 0)
		end, function(u)
			return Vector3.new(0.12, 0.06, 0.4 + reach(u) * 0.8)
		end, function()
			return 0.15
		end, Enum.Material.Neon)
	end
end

def.beats = {
	{
		at = -0.9,
		run = function(run)
			run:face(run:target())
			clone(run, -1)
			clone(run, 1)
			run.memo.hits = 0
			run.memo.total = 0
			for _, event in run.cast do
				if event.kind == "Area" then
					run.memo.total += 1
				end
			end
		end,
	},
	{
		at = -0.6,
		run = function(run)
			local blue = run.style.primary
			Kit.orb(run, -0.6, 0, blue, function()
				return overHand(run)
			end, function(u)
				return (0.4 + 0.6 * Kit.easeOut(u)) * run:scale()
			end)
			blades(run, -0.45, 0, function()
				return overHand(run)
			end, function(u)
				return (0.5 + 0.8 * Kit.easeOut(u)) * run:scale()
			end)
			run:camera(-0.5, 0, { key = "push", push = 1.8, focus = overHand(run), rise = 0.3, fall = 0.1 })
			run:sound("charge", 1.6)
		end,
	},
}

-- The throw: the spinning sphere crosses to the target before the first real hit.
function def.release(run): boolean
	local center = run:area()
	local start = overHand(run)
	local goal = center + Vector3.new(0, 1.4, 0)
	local blue = run.style.primary
	local function at(u: number): Vector3
		return start:Lerp(goal, Kit.easeIn(u))
	end
	local progress = function(): number
		return math.clamp(run:designTime() / 0.25, 0, 1)
	end
	Kit.orb(run, 0, 0.25, blue, function()
		return at(progress())
	end, function()
		return 1 * run:scale()
	end)
	blades(run, 0, 0.25, function()
		return at(progress())
	end, function()
		return 1.3 * run:scale()
	end)
	run:sound("whoosh", 1.7)
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		local center, radius = run:area()
		local air = center + Vector3.new(0, 1.4, 0)
		local blue, white = run.style.primary, run.style.secondary
		run.memo.hits = (run.memo.hits or 0) + 1
		local hit, total = run.memo.hits, math.max(run.memo.total or 4, 1)
		local now = run:designTime()
		if hit == 1 then
			-- It opens into the wide sphere of wind until the last hit.
			local last = now + (total - 1) * 0.25 + 0.1
			Kit.shell(run, now, last, white, air, function(u)
				local open = Kit.easeOut(math.min(1, u * 4))
				return radius * 2.1 * open * (1 + 0.04 * math.sin(run:now() * 30))
			end, function()
				return 0.6
			end)
			Kit.shell(run, now, last, blue, air, function(u)
				return radius * 1.4 * Kit.easeOut(math.min(1, u * 4))
			end, function()
				return 0.45
			end)
		end
		FxKit.ring(center, white, radius * 2.3, 0.22)
		Kit.slashes(run, now, now + 0.2, center, radius * 0.9, if run.reduced then 4 else 8, { WHITE, blue }, 1.6)
		if hit >= total then
			-- The collapse: a final burst.
			ImpactEffects.ball(air, WHITE, radius * 1.4, 0.15)
			FxKit.ring(center, blue, radius * 2.8, 0.4)
			run:shake(0.28)
			run:sound("whoosh", 1.2)
		else
			run:shake(0.1)
		end
		for _, target in run:targets() do
			run:hitStop(target, 0.04)
		end
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view then
			ImpactEffects.burst("spark", view.part.Position, nil, {
				color = WHITE,
				color2 = run.style.primary,
				count = 5,
				size = 0.2,
				speed = { 6, 10 },
				lifetime = { 0.1, 0.2 },
			})
		end
		return true
	end
	return false
end

return def
