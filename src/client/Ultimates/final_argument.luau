-- final_argument (Tier 5): bored, then serious, then one punch that changes the board. The real
-- cast is a single huge true-damage hit on his target at the Cast event (his signature punch in
-- AbilityFxConfig stays as the fallback if this module is missing).
--   -1.05  slouched and bored, arms hanging; the board quiets (dim)
--   -0.80  he straightens: chest up, chin level (the face changes)
--   -0.70  the fist draws back, slowly, the other hand up; the air bends around the fist, dust
--          lifts off the board around him
--   -0.15  total stillness; the camera pushes to his face, then to the fist
--    0     the punch, almost invisible: a huge white flash at the target, a cone of air tearing the
--          ground past it, a long crack, wind streaks across the board, debris; a long hit-stop
--   +0.45  dust and smoke blown along the punch; he goes back to bored

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local DUST = Kit.DUST
local STONE = Color3.fromRGB(150, 140, 128)

local def = {}

def.pose = {
	rightArm = {
		{ -1.05, -4 },
		{ -0.8, 4 },
		{ -0.7, 4 },
		{ -0.2, -48, "inOut" },
		{ -0.02, -50 },
		{ 0, 96, "snap" },
		{ 0.25, 92 },
		{ 0.6, 0 },
		{ 1.2, -4 },
	},
	leftArm = {
		{ -1.05, -4 },
		{ -0.8, 4 },
		{ -0.7, 4 },
		{ -0.25, 55 },
		{ -0.02, 58 },
		{ 0, 10, "snap" },
		{ 0.6, 0 },
		{ 1.2, -4 },
	},
	twist = { { -0.7, 0 }, { -0.2, -32 }, { -0.02, -34 }, { 0, 30, "snap" }, { 0.3, 22 }, { 0.8, 0 } },
	-- Slouched, then straight, then the coil.
	lean = {
		{ -1.05, 7 },
		{ -0.8, -3, "out" },
		{ -0.7, -3 },
		{ -0.2, -6 },
		{ 0, 12, "snap" },
		{ 0.35, 6 },
		{ 0.8, 0 },
		{ 1.2, 6 },
	},
	tilt = { { -1.05, 4 }, { -0.8, 0 }, { 0.8, 0 }, { 1.2, 3 } },
	crouch = { { -0.7, 0 }, { -0.2, 0.12 }, { -0.02, 0.13 }, { 0, 0.05, "snap" }, { 0.4, 0 } },
	tremble = { { -0.2, 0 }, { -0.15, 0.5 }, { -0.03, 0.5 }, { -0.02, 0, "hold" } },
	lunge = { { 0, 0 }, { 0.03, 0.7, "snap" }, { 0.5, 0.2 }, { 0.9, 0 } },
}

def.beats = {
	{
		at = -1.05,
		run = function(run)
			run:face(run:target())
			run:camera(-1.05, 0.4, { key = "dim", dim = 0.25, rise = 0.4, fall = 0.25 })
		end,
	},
	{
		-- The draw-back: the air bends around the fist, dust lifts off the board.
		at = -0.7,
		run = function(run)
			Kit.live(run, -0.7, 0, "Ball", WHITE, function(part, u)
				local pulse = 1 + 0.06 * math.sin(run:now() * 30)
				part.Size = Vector3.one * (0.8 + 1.6 * Kit.easeIn(u)) * pulse * run:scale()
				part.CFrame = CFrame.new(run:hand("right"))
				part.Transparency = 0.85 - 0.15 * u
			end, Enum.Material.Glass)
			Kit.drift(run, -0.65, -0.05, DUST, run:ground(), 7, if run.reduced then 0.16 else 0.08)
			run:sound("charge", 0.5)
		end,
	},
	{
		-- Stillness: the camera to his face, then to the fist.
		at = -0.2,
		run = function(run)
			run:camera(-0.2, -0.08, { key = "push", push = 3, focus = run:head(), rise = 0.12, fall = 0.02 })
			run:camera(-0.08, 0, { key = "fist", push = 3.4, focus = run:hand("right"), rise = 0.03, fall = 0.03 })
			run:camera(0, 0.6, { key = "pull", push = -2.6, focus = run:chest(), rise = 0.03, fall = 0.5 })
		end,
	},
}

function def.release(run): boolean
	ImpactEffects.ball(run:hand("right"), WHITE, 1.8 * run:scale(), 0.08)
	return true
end

function def.event(run, event): boolean
	if event.kind ~= "Damage" or not event.target or event.dot then
		return false
	end
	local target = run.context.views[event.target]
	-- One punch, one board-changing impact (should a cast ever hit twice, the second is plain).
	if not target or run.memo.hit then
		return target == nil
	end
	run.memo.hit = true
	local scale = run:scale()
	local direction = target.part.Position - run.view.part.Position
	direction = Vector3.new(direction.X, 0, direction.Z)
	direction = if direction.Magnitude > 1e-3 then direction.Unit else run:forward()
	local point = target.part.Position - direction * target.part.Size.X * 0.3
	local floor = target.part.Position - Vector3.new(0, target.part.Size.Y / 2, 0)

	-- The flash and the cone of air past the target.
	ImpactEffects.ball(point, WHITE, 5 * scale, 0.14)
	ImpactEffects.ball(point, run.style.primary, 6.5 * scale, 0.3)
	FxKit.pressureCone(point, direction, 12, math.rad(24), WHITE, 0.55)
	FxKit.pressureCone(point, direction, 8, math.rad(14), run.style.primary, 0.4, 0.03)
	-- The ground torn open along the punch.
	FxKit.mark(floor, DUST, run.style.secondary, 3.4 * scale, "crack", 1.6)
	Kit.groove(run, 0, 1.4, Color3.fromRGB(70, 60, 52), floor, floor + direction * 14, 0.6)
	if not run.reduced then
		Kit.streaks(run, 0, point - direction * 2, direction, 12, 34, 9, WHITE)
		for i = 1, 5 do
			local at = floor + Vector3.new(0, 0.3, 0)
			local fling = direction * (6 + math.random() * 8)
				+ Vector3.new((math.random() - 0.5) * 4, 3 + math.random() * 3, 0)
			local spin = math.random() * 4
			Kit.block(run, 0, 0.7, STONE, function(u)
				local p = at + fling * u + Vector3.new(0, -9 * u * u, 0)
				return CFrame.new(p) * CFrame.Angles(spin * u * 6, spin, 0)
			end, function()
				return Vector3.one * (0.25 + i * 0.04)
			end, function(u)
				return if u > 0.85 then (u - 0.85) * 6 else 0
			end, Enum.Material.Slate)
		end
	end
	-- Dust and smoke blown along the punch.
	for i = 1, 4 do
		run:at(0.05 + i * 0.1, function()
			ImpactEffects.burst("puff", floor + direction * (i * 3) + Vector3.new(0, 0.6, 0), direction, {
				color = DUST,
				count = 6,
				size = 1.2,
				speed = { 6, 12 },
				lifetime = { 0.5, 0.9 },
				spread = 30,
				transparency = 0.35,
			})
		end)
	end
	run:hitStop(target, 0.18)
	run:hitStop(nil, 0.16)
	run:shake(0.45)
	run:sound("whoosh", 0.45)
	return true
end

return def
