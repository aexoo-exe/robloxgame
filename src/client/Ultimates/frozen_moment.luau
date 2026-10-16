-- frozen_moment (Tier 4): everything stops, and all the knives land at once. The real cast stuns
-- every enemy within 2 hexes of him at the Cast event; when each stun ends (1-2 s later, by star
-- level) that enemy takes a knife (a Damage event marked stunEnd) and he heals for part of it.
--   -1.00  arms flung wide, chest out; a small gold sphere glows around him, a clock forms on the
--          ground under him
--    0     the real stun: the sphere snaps out over the whole area, the screen loses its colour,
--          each frozen enemy is held in a grey-green glaze
--   +0.10  he moves freely: knives appear one by one, floating, each pointed at a frozen enemy, as
--          he flicks them out with alternating hands
--   end    stillness and a push just before time resumes; the colour returns and every knife hits
--          at once on the real stun-end hits, hit-stop; green motes drift back into him
--   after  a smug finishing pose, hand at his face

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local GLAZE = Color3.fromRGB(150, 190, 160)
local STEEL = Color3.fromRGB(215, 220, 230)
local HILT = Color3.fromRGB(60, 50, 40)

local def = {}

-- How long the freeze lasts: the cast's real stun.
local function freezeOf(run): number
	local stun = run:find("Stun")
	return if stun and stun.duration then stun.duration else 1
end

function def.poseFor(run)
	local d = freezeOf(run)
	-- Arms wide before; flicks of the knives after the freeze starts; a pose once time resumes.
	return {
		leftArm = {
			{ -1.0, 0 },
			{ -0.75, 15, "out" },
			{ 0.05, 15 },
			{ 0.15, 110, "snap" },
			{ 0.3, 40 },
			{ 0.45, 110, "snap" },
			{ 0.6, 30 },
			{ d - 0.05, 30 },
			{ d + 0.15, 45 },
			{ d + 0.55, 45 },
			{ d + 0.85, 0 },
		},
		leftArmOut = {
			{ -1.0, 0 },
			{ -0.75, 80, "out" },
			{ 0.05, 80 },
			{ 0.15, 10 },
			{ 0.6, 10 },
			{ d + 0.15, -22 },
			{ d + 0.55, -22 },
			{ d + 0.85, 0 },
		},
		rightArm = {
			{ -1.0, 0 },
			{ -0.75, 15, "out" },
			{ 0.05, 15 },
			{ 0.22, 40 },
			{ 0.32, 110, "snap" },
			{ 0.48, 40 },
			{ 0.58, 110, "snap" },
			{ 0.7, 30 },
			{ d - 0.05, 30 },
			{ d + 0.15, 150 },
			{ d + 0.55, 150 },
			{ d + 0.85, 0 },
		},
		rightArmOut = {
			{ -1.0, 0 },
			{ -0.75, 80, "out" },
			{ 0.05, 80 },
			{ 0.22, 10 },
			{ d + 0.15, 12 },
			{ d + 0.55, 12 },
			{ d + 0.85, 0 },
		},
		lean = {
			{ -1.0, 0 },
			{ -0.75, -10, "out" },
			{ 0.05, -10 },
			{ 0.3, 4 },
			{ d - 0.05, 2 },
			{ d + 0.15, -6 },
			{ d + 0.85, 0 },
		},
		twist = {
			{ 0.05, 0 },
			{ 0.15, -14 },
			{ 0.32, 14 },
			{ 0.45, -14 },
			{ 0.58, 14 },
			{ 0.75, 0 },
			{ d + 0.15, -10 },
			{ d + 0.85, 0 },
		},
	}
end

-- A floating knife in front of `view`, pointed at it, from design time `from` to `to`.
local function floatingKnife(run, view, from: number, to: number, slot: number)
	local toward = run.view.part.Position - view.part.Position
	toward = Vector3.new(toward.X, 0, toward.Z)
	toward = if toward.Magnitude > 1e-3 then toward.Unit else Vector3.zAxis
	local side = Vector3.new(-toward.Z, 0, toward.X)
	local at = view.part.Position + toward * 2.2 + side * ((slot % 3) - 1) * 0.5 + Vector3.new(0, 0.6, 0)
	local aim = view.part.Position + Vector3.new(0, 0.3, 0)
	local function frame(): CFrame
		local bob = Vector3.new(0, math.sin(run:now() * 5 + slot) * 0.08, 0)
		return CFrame.lookAt(at + bob, aim + bob)
	end
	Kit.block(run, from, to, STEEL, function()
		return frame() * CFrame.new(0, 0, -0.25)
	end, function()
		return Vector3.new(0.05, 0.14, 0.7)
	end, function(u)
		return if u < 0.05 then 1 - u * 20 else 0
	end, Enum.Material.Metal)
	Kit.block(run, from, to, HILT, function()
		return frame() * CFrame.new(0, 0, 0.25)
	end, function()
		return Vector3.new(0.08, 0.08, 0.28)
	end, function(u)
		return if u < 0.05 then 1 - u * 20 else 0
	end)
	run.memo.knives = run.memo.knives or {}
	run.memo.knives[view] = at
end

def.beats = {
	{
		at = -1.0,
		run = function(run)
			run.memo.knives = {}
			local gold = run.style.primary
			Kit.shell(run, -0.8, 0, gold, run:chest(), function(u)
				return run.view.part.Size.Y * (0.8 + 0.6 * u)
			end, function(u)
				return 0.85 - 0.2 * u
			end)
			run:at(-0.6, function()
				FxKit.mark(run:ground(), gold, run.style.secondary, 3, "clock", run:span(-0.6, 0.6) + 0.1)
			end)
			run:camera(-0.4, 0, { key = "push", push = 2, focus = run:chest(), rise = 0.3, fall = 0.1 })
			run:sound("tick", 0.8)
			run:at(-0.5, function()
				run:sound("tick", 0.8)
			end)
			run:at(-0.25, function()
				run:sound("tick", 0.8)
			end)
		end,
	},
}

function def.release(run): boolean
	local center, radius = run:area()
	local d = freezeOf(run)
	local gold = run.style.primary
	-- The world stops: the sphere snaps out over the area and the colour drains.
	Kit.shell(run, 0, 0.3, gold, center + Vector3.new(0, 1, 0), function(u)
		return radius * 2.2 * Kit.easeOut(u)
	end, function(u)
		return 0.35 + 0.65 * u
	end)
	FxKit.mark(center, gold, run.style.secondary, radius, "clock", d)
	run:camera(0, d + 0.1, { key = "dim", dim = 0.3, rise = 0.12, fall = 0.15 })
	-- Time resumes: a beat of stillness and a push just before the knives land.
	run:camera(d - 0.2, d + 0.3, { key = "resume", push = 2.4, focus = run:chest(), rise = 0.15, fall = 0.3 })
	run:sound("chime", 0.4)
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "AreaStun" then
		return true -- the sphere and the clock are the area
	elseif kind == "Stun" and event.target then
		-- Frozen: a grey-green glaze over the enemy for the whole freeze, and its knife.
		local view = run.context.views[event.target]
		if view then
			local d = event.duration or freezeOf(run)
			Kit.shell(run, 0, d, GLAZE, view.part.Position, function()
				return view.part.Size.Y * 1.05
			end, function()
				return 0.72
			end, Enum.Material.Glass)
			run.memo.slots = (run.memo.slots or 0) + 1
			local slot = run.memo.slots
			floatingKnife(run, view, 0.12 + slot * 0.08, d, slot)
		end
		return false -- the stun halo still shows
	elseif kind == "Damage" and event.stunEnd and event.target then
		-- Every knife hits at once.
		local view = run.context.views[event.target]
		local from = run.memo.knives and run.memo.knives[view]
		if view then
			local to = view.part.Position + Vector3.new(0, 0.3, 0)
			if from then
				FxKit.beam(from, to, STEEL, 0.12, 0.12, "straight")
			end
			ImpactEffects.ball(to, WHITE, 1.4, 0.1)
			ImpactEffects.burst("spark", to, nil, {
				color = STEEL,
				color2 = run.style.primary,
				count = 8,
				size = 0.2,
				speed = { 6, 12 },
				lifetime = { 0.12, 0.25 },
			})
			run:hitStop(view, 0.1)
		end
		if not run.memo.resumed then
			run.memo.resumed = true
			run:shake(0.28)
			run:sound("whoosh", 1.7)
		end
		return true
	elseif kind == "Heal" and event.target == run.unitIndex then
		-- Green motes drift back into him.
		Kit.converge(run, run:designTime(), run:designTime() + 0.35, function()
			return run:chest()
		end, run.style.secondary, 3.5, 4, false, 0.35)
		return true
	end
	return false
end

return def
