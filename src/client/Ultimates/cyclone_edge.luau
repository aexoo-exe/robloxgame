-- cyclone_edge (Tier 4): the spinning dive, chained. The real cast dashes him to the highest-AD
-- enemy and hits everything next to it at the Cast event; while his attack speed lasts, each time
-- his target dies he dives again (a FollowUp, then a dash and the same hit on the nearest enemy).
--   -0.55  grapple cables shoot from his hips to the target; gas jets puff
--   -0.30  he sinks low, blades reversed back, and launches
--    0     the dash: his whole body spins into a steel-blue blade tornado; on the real hit a whirl
--          of slash rings over the area, many quick cuts
--   +0.35  he comes out of the spin in a low crouch, blades back, still
--   chain  each real follow-up: a cable snaps to the next enemy, a faster spin and the whirl again

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local CABLE = Color3.fromRGB(70, 74, 80)
local GAS = Color3.fromRGB(235, 238, 240)

local def = {}

def.pose = {
	leftArm = {
		{ -0.55, 0 },
		{ -0.3, -40 },
		{ -0.02, -45 },
		{ 0.05, 60, "snap" },
		{ 0.35, 50 },
		{ 0.5, -30 },
		{ 0.9, -30 },
		{ 1.2, 0 },
	},
	rightArm = {
		{ -0.55, 0 },
		{ -0.3, -40 },
		{ -0.02, -45 },
		{ 0.05, 60, "snap" },
		{ 0.35, 50 },
		{ 0.5, -30 },
		{ 0.9, -30 },
		{ 1.2, 0 },
	},
	leftArmOut = {
		{ -0.3, 0 },
		{ -0.02, 20 },
		{ 0.05, 80, "snap" },
		{ 0.35, 80 },
		{ 0.5, 30 },
		{ 0.9, 30 },
		{ 1.2, 0 },
	},
	rightArmOut = {
		{ -0.3, 0 },
		{ -0.02, 20 },
		{ 0.05, 80, "snap" },
		{ 0.35, 80 },
		{ 0.5, 30 },
		{ 0.9, 30 },
		{ 1.2, 0 },
	},
	crouch = {
		{ -0.4, 0 },
		{ -0.05, 0.28 },
		{ 0.02, 0, "snap" },
		{ 0.35, 0.05 },
		{ 0.5, 0.22 },
		{ 0.9, 0.22 },
		{ 1.2, 0 },
	},
	lean = { { -0.4, 0 }, { -0.05, 14 }, { 0.02, 0, "snap" }, { 0.5, 10 }, { 0.9, 10 }, { 1.2, 0 } },
	-- Whole turns, then back to 0 (the same facing) so the fade-out does not unwind him.
	spin = { { 0, 0 }, { 0.38, 1080, "out" }, { 0.39, 0, "hold" } },
	rise = { { 0, 0 }, { 0.12, 0.6, "out" }, { 0.35, 0, "in" } },
}

-- A chained dive: a quicker spin, the same crouch out of it.
local CHAIN = {
	spin = { { 0, 0 }, { 0.26, 720, "out" }, { 0.27, 0, "hold" } },
	leftArmOut = { { 0, 80 }, { 0.26, 80 }, { 0.4, 30 }, { 0.6, 0 } },
	rightArmOut = { { 0, 80 }, { 0.26, 80 }, { 0.4, 30 }, { 0.6, 0 } },
	crouch = { { 0, 0.05 }, { 0.3, 0.2 }, { 0.6, 0 } },
}

-- A thin cable from his hip to `to`, shot out and held for a moment.
local function cable(run, from: number, to: number, side: number, goal: () -> Vector3)
	Kit.live(run, from, to, "Block", CABLE, function(part, u)
		local hips = run:ground() + Vector3.new(0, run.view.part.Size.Y * 0.4, 0)
		local across = Vector3.new(-run:forward().Z, 0, run:forward().X) * side * 0.6
		local a = hips + across
		local b = a:Lerp(goal(), math.clamp(u * 3.5, 0.02, 1))
		part.Size = Vector3.new(0.06, 0.06, math.max((b - a).Magnitude, 0.05))
		part.CFrame = CFrame.lookAt((a + b) / 2, b)
		part.Transparency = 0.05
	end)
end

local function gas(run)
	ImpactEffects.burst("puff", run:ground() + Vector3.new(0, run.view.part.Size.Y * 0.35, 0), -run:forward(), {
		color = GAS,
		count = 6,
		size = 0.8,
		speed = { 4, 8 },
		lifetime = { 0.3, 0.55 },
		spread = 50,
		transparency = 0.4,
	})
end

-- The whirl over the area: rings of steel and many quick cuts.
local function whirl(run, now: number, scale: number)
	local center, radius = run:area()
	local steel, blue = run.style.primary, run.style.secondary
	for i = 0, 2 do
		FxKit.ring(center, if i == 1 then blue else steel, radius * (1.6 + i * 0.5) * scale, 0.3, i * 0.06)
	end
	FxKit.spiral(center, blue, radius * 0.7, 3, 0.4)
	Kit.slashes(run, now, now + 0.3 * scale, center, radius, if run.reduced then 6 else 12, { steel, blue, WHITE }, 0.9)
end

def.beats = {
	{
		at = -0.55,
		run = function(run)
			local target = run:target()
			run:face(target)
			if target then
				for _, side in { -1, 1 } do
					cable(run, -0.55, 0.1, side, function()
						return target.part.Position + Vector3.new(0, target.part.Size.Y * 0.3, 0)
					end)
				end
			end
			gas(run)
			run:sound("tick", 1.3)
			run:at(-0.15, gas)
			run:camera(-0.3, 0.05, { key = "push", push = 1.6, focus = run:chest(), rise = 0.2, fall = 0.1 })
		end,
	},
}

function def.release(run): boolean
	run.memo.dives = (run.memo.dives or 0) + 1
	if run.memo.dives > 1 then
		-- A chained dive: the faster spin; its cable and whirl come with its real dash and hit.
		run:pose(CHAIN)
		run.memo.chained = true
		gas(run)
	end
	run:sound("whoosh", 1.5 + 0.15 * run.memo.dives)
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Dash" and run.memo.chained then
		local goal = run.context.toWorld(event.column, event.row) + Vector3.new(0, 1.5, 0)
		local now = run:designTime()
		cable(run, now, now + 0.15, 1, function()
			return goal
		end)
		return false -- the afterimages still show the path
	elseif kind == "Area" then
		whirl(run, run:designTime(), if run.memo.chained then 0.8 else 1)
		run:shake(if run.memo.chained then 0.18 else 0.28)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view then
			ImpactEffects.burst("spark", view.part.Position, nil, {
				color = WHITE,
				color2 = run.style.secondary,
				count = 12,
				size = 0.22,
				speed = { 8, 15 },
				lifetime = { 0.12, 0.25 },
			})
			run:hitStop(view, 0.06)
		end
		return true
	end
	return false
end

return def
