-- reelbreaker (Tier 4): reel in, then the charged punch. The real cast pulls the farthest enemy to
-- the cell next to him and hits it hard, both at the Cast event (the pull slides it over 0.15 s).
--   -0.70  the rod goes up overhead and whips forward; the line flies out to the farthest enemy
--   -0.40  hooked: the line holds taut; his free fist draws back and yellow-green aura gathers in
--          it, growing and brightening (the "rock"); the camera leans in on the fist
--    0     he yanks the rod back and the enemy flies in as the fist snaps out; the impact lands as
--          it arrives: a big yellow-green burst, a ground crack, hit-stop
--   +0.40  the follow-through holds; the aura sheds away as sparks

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local LINE = Color3.fromRGB(235, 235, 225)

local ARRIVE = 0.12 -- the pulled enemy lands in front of him (RenderConfig.dashDuration 0.15)

local def = {}

def.pose = {
	-- The rod arm: up overhead, the cast forward, held, the yank back.
	rightArm = {
		{ -0.7, 0 },
		{ -0.55, 160, "out" },
		{ -0.42, 70, "snap" },
		{ -0.02, 72 },
		{ 0.06, 120, "snap" },
		{ 0.5, 60 },
		{ 0.9, 0 },
	},
	-- The fist: back from the hook on, then the punch.
	leftArm = { { -0.4, 0 }, { -0.2, -45, "out" }, { -0.02, -50 }, { 0.03, 98, "snap" }, { 0.4, 92 }, { 0.9, 0 } },
	leftArmOut = { { -0.4, 0 }, { -0.2, 12 }, { 0.03, 0, "snap" }, { 0.9, 0 } },
	twist = {
		{ -0.7, 0 },
		{ -0.55, 10 },
		{ -0.42, -6 },
		{ -0.2, 18 },
		{ -0.02, 22 },
		{ 0.03, -30, "snap" },
		{ 0.4, -20 },
		{ 0.9, 0 },
	},
	lean = {
		{ -0.7, 0 },
		{ -0.55, -6 },
		{ -0.42, 6, "snap" },
		{ -0.2, -3 },
		{ 0.03, 12, "snap" },
		{ 0.4, 6 },
		{ 0.9, 0 },
	},
	crouch = { { -0.4, 0 }, { -0.2, 0.12 }, { -0.02, 0.14 }, { 0.03, 0.05, "snap" }, { 0.5, 0 } },
	tremble = { { -0.2, 0 }, { -0.1, 0.8 }, { -0.02, 1.2 }, { 0, 0, "hold" } },
	lunge = { { 0.02, 0 }, { 0.06, 0.3, "snap" }, { 0.5, 0 } },
}

-- The rod's tip: up and ahead of his right hand.
local function rodTip(run): Vector3
	return run:hand("right") + run:forward() * 2.2 + Vector3.new(0, 1.2, 0)
end

def.beats = {
	{
		at = -0.7,
		run = function(run)
			local target = run:target()
			run:face(target)
			if not target then
				return
			end
			-- The line flies out after the cast, then holds taut until the yank.
			Kit.live(run, -0.44, 0.08, "Block", LINE, function(part, u)
				local tip = rodTip(run)
				local far = target.part.Position
				local t = run:designTime()
				local out = Kit.easeOut((t + 0.44) / 0.14)
				local reach = tip:Lerp(far, math.clamp(out, 0.02, 1))
				local length = math.max((reach - tip).Magnitude, 0.05)
				part.Size = Vector3.new(0.05, 0.05, length)
				part.CFrame = CFrame.lookAt((tip + reach) / 2, reach)
				part.Transparency = if u > 0.92 then 1 else 0.1
			end)
			run:at(-0.3, function()
				ImpactEffects.burst("spark", target.part.Position, nil, {
					color = WHITE,
					count = 6,
					size = 0.2,
					speed = { 4, 8 },
					lifetime = { 0.1, 0.2 },
				})
				run:sound("tick")
			end)
			run:sound("whoosh", 1.6)
		end,
	},
	{
		-- The rock: aura gathering in the drawn-back fist.
		at = -0.4,
		run = function(run)
			local glow = run.style.primary
			Kit.orb(run, -0.4, 0.05, glow, function()
				return run:hand("left")
			end, function(u)
				return (0.3 + 1.2 * Kit.easeIn(u)) * run:scale()
			end)
			Kit.converge(run, -0.4, 0, function()
				return run:hand("left")
			end, run.style.secondary, 2.4, if run.reduced then 6 else 14)
			run:camera(-0.4, 0, { key = "push", push = 2.4, focus = run:hand("left"), rise = 0.3, fall = 0.05 })
			run:camera(ARRIVE, 0.6, { key = "pull", push = -1.8, focus = run:chest(), rise = 0.04, fall = 0.4 })
			run:sound("charge", 1.1)
		end,
	},
}

function def.release(run): boolean
	ImpactEffects.ball(run:hand("left"), run.style.primary, 1.2 * run:scale(), 0.1)
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Pull" then
		return true -- the line's yank is the pull
	elseif kind == "Damage" and event.target and not event.dot then
		local target = run.context.views[event.target]
		if not target then
			return true
		end
		-- The impact lands as the reeled-in enemy arrives in front of him.
		run:at(ARRIVE, function()
			local glow, accent = run.style.primary, run.style.secondary
			local at = target.part.Position
			local floor = at - Vector3.new(0, target.part.Size.Y / 2, 0)
			ImpactEffects.ball(at, WHITE, 3 * run:scale(), 0.1)
			Kit.shell(run, ARRIVE, ARRIVE + 0.35, glow, at, function(u)
				return 5 * Kit.easeOut(u) * run:scale()
			end, function(u)
				return 0.2 + 0.8 * u
			end)
			FxKit.ring(floor, accent, 7 * run:scale(), 0.4)
			FxKit.mark(floor, glow, accent, 2.4 * run:scale(), "crack", 1.1)
			ImpactEffects.burst("glow", at, run:forward(), {
				color = glow,
				color2 = accent,
				count = 12,
				size = 0.5,
				speed = { 8, 16 },
				lifetime = { 0.25, 0.45 },
				spread = 50,
			})
			run:hitStop(target, 0.14)
			run:hitStop(nil, 0.1)
			run:shake(0.32)
			run:sound("whoosh", 0.6)
		end)
		-- The aura sheds away as sparks.
		run:at(0.35, function()
			ImpactEffects.burst("spark", run:hand("left"), nil, {
				color = run.style.secondary,
				count = 10,
				size = 0.22,
				speed = { 3, 6 },
				lifetime = { 0.3, 0.5 },
			})
		end)
		return true
	end
	return false
end

return def
