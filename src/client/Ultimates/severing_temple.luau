-- severing_temple (Tier 5): the shrine. The real cast cuts every enemy within 2 hexes of his target
-- at the Cast event and leaves a 4-second damage over time on them; so the shrine rises before it,
-- the area fills with cuts on the real hit, and fresh cuts flicker on each real tick after.
--   -1.00  a hand sign at his chest; the ground under the area darkens red-black, the screen dims
--   -0.85  one hand rises; the shrine climbs out of the ground behind the area, red-lit, teeth
--          along its beam; the camera leans toward it
--   -0.25  a single bell beat: one slow ring rolls out, everything holds still
--    0     the real hit: a flash and a shockwave, the area fills with crimson and white cuts, hit-stop;
--          his raised hand sweeps down and out
--   +0.4   arms folded, unmoved; the shrine lingers faintly and fades by 2.6
--   ticks  each real damage-over-time tick flickers a few cuts on that enemy

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local WOOD = Color3.fromRGB(42, 22, 20)
local IVORY = Color3.fromRGB(232, 222, 202)
local GLOW = Color3.fromRGB(255, 40, 52)
local POOL = Color3.fromRGB(34, 6, 10)

local RISE_FROM, RISE_TO = -0.85, -0.35 -- the shrine climbs out of the ground
local FADE_FROM, FADE_TO = 1.0, 2.6 -- and fades after the hit

local def = {}

def.pose = {
	-- Both hands meet in a sign at the chest; then the right rises alone and holds.
	leftArm = {
		{ -1.0, 0 },
		{ -0.85, 72, "out" },
		{ -0.1, 72 },
		{ 0.04, 30, "snap" },
		{ 0.4, 45 },
		{ 1.4, 45 },
		{ 1.8, 0 },
	},
	leftArmOut = { { -1.0, 0 }, { -0.85, -10, "out" }, { 0.04, 10, "snap" }, { 0.4, -24 }, { 1.4, -24 }, { 1.8, 0 } },
	rightArm = {
		{ -1.0, 0 },
		{ -0.85, 72, "out" },
		{ -0.6, 118 },
		{ -0.1, 118 },
		{ 0.04, 35, "snap" },
		{ 0.4, 40 },
		{ 1.4, 40 },
		{ 1.8, 0 },
	},
	rightArmOut = {
		{ -1.0, 0 },
		{ -0.85, -10, "out" },
		{ -0.6, 8 },
		{ 0.04, 48, "snap" },
		{ 0.4, -20 },
		{ 1.4, -20 },
		{ 1.8, 0 },
	},
	twist = { { -1.0, 0 }, { -0.6, 6 }, { -0.1, 6 }, { 0.04, -22, "snap" }, { 0.4, -4 }, { 1.8, 0 } },
	lean = { { -1.0, 0 }, { -0.6, -5 }, { -0.1, -5 }, { 0.04, 7, "snap" }, { 0.4, -3 }, { 1.8, 0 } },
	crouch = { { -0.1, 0 }, { 0.04, 0.06, "snap" }, { 0.4, 0 } },
}

-- The shrine's place: past the area, facing back toward him.
local function shrineFrame(run): CFrame
	local center, radius = run:area()
	local away = center - run:ground()
	away = Vector3.new(away.X, 0, away.Z)
	away = if away.Magnitude > 1e-3 then away.Unit else run:forward()
	local base = center + away * radius * 0.85
	return CFrame.lookAt(base, base - away)
end

-- How far up the shrine is (0 under the ground, 1 standing) and how faded (0 solid, 1 gone).
local function shrineState(run): (number, number)
	local t = run:designTime()
	local up = Kit.easeOut((t - RISE_FROM) / (RISE_TO - RISE_FROM))
	local fade = Kit.smooth((t - FADE_FROM) / (FADE_TO - FADE_FROM))
	return up, fade
end

-- One shrine part: `offset` from the shrine's base frame, `size`, solid at `solid` transparency.
local function shrinePart(run, frame: CFrame, color: Color3, offset: CFrame, size: Vector3, solid: number, material)
	Kit.block(run, RISE_FROM, FADE_TO, color, function()
		local up = shrineState(run)
		return frame * CFrame.new(0, -9 * (1 - up), 0) * offset
	end, function()
		return size
	end, function()
		local up, fade = shrineState(run)
		return math.min(1, solid + (1 - solid) * fade + (if up <= 0 then 1 else 0))
	end, material)
end

local function buildShrine(run)
	local frame = shrineFrame(run)
	local v = Vector3.new
	local c = CFrame.new
	-- Pillars, beam, a pitched roof with a ridge, teeth along the beam, a red glow between pillars.
	for _, x in { -3.2, 3.2 } do
		shrinePart(run, frame, WOOD, c(x, 3.4, 0), v(0.7, 6.8, 0.7), 0.05)
		shrinePart(run, frame, GLOW, c(x * 0.97, 3.4, -0.36), v(0.12, 6.2, 0.05), 0.15, Enum.Material.Neon)
	end
	shrinePart(run, frame, WOOD, c(0, 6.9, 0), v(8.6, 0.55, 1.4), 0.05)
	shrinePart(run, frame, GLOW, c(0, 6.6, -0.72), v(8.2, 0.1, 0.05), 0.1, Enum.Material.Neon)
	for _, side in { -1, 1 } do
		shrinePart(run, frame, WOOD, c(side * 2.6, 7.75, 0) * CFrame.Angles(0, 0, -side * 0.28), v(5.8, 0.4, 3.2), 0.05)
	end
	shrinePart(run, frame, WOOD, c(0, 8.45, 0), v(1.2, 0.5, 3.4), 0.05)
	if not run.reduced then
		for i = -3, 3 do
			shrinePart(
				run,
				frame,
				IVORY,
				c(i * 1.1, 6.35, -0.5) * CFrame.Angles(0, 0, math.rad(45)),
				v(0.32, 0.32, 0.2),
				0.05
			)
		end
	end
	shrinePart(run, frame, GLOW, c(0, 3.3, 0.2), v(5.6, 6, 0.08), 0.82, Enum.Material.Neon)
end

def.beats = {
	{
		at = -1.0,
		run = function(run)
			run:face(run:target())
			local center, radius = run:area()
			-- The ground under the area turns to a dark, shallow pool.
			Kit.pool(run, -1.0, FADE_TO, POOL, center, function()
				local t = run:designTime()
				return radius * 2.2 * Kit.easeOut((t + 1.0) / 0.55)
			end, function()
				local t = run:designTime()
				return 0.15 + 0.85 * Kit.smooth((t - FADE_FROM) / (FADE_TO - FADE_FROM))
			end, Enum.Material.Glass)
			run:camera(-1.0, 1.0, { key = "dim", dim = 0.3, rise = 0.4, fall = 0.6 })
			run:sound("charge", 0.6)
		end,
	},
	{
		at = -0.85,
		run = function(run)
			buildShrine(run)
			local center = run:area()
			run:camera(-0.7, 0, { key = "push", push = 2.6, focus = center, rise = 0.4, fall = 0.06 })
			ImpactEffects.burst("puff", center + Vector3.new(0, 0.3, 0), nil, {
				color = POOL:Lerp(WHITE, 0.25),
				count = 10,
				size = 1.1,
				speed = { 2, 4 },
				lifetime = { 0.5, 0.9 },
				transparency = 0.4,
			})
		end,
	},
	{
		-- The bell: one slow ring, then nothing moves.
		at = -0.25,
		run = function(run)
			local center, radius = run:area()
			FxKit.ring(center, GLOW, radius * 2.6, run:span(-0.25, 0.25) + 0.25)
			run:sound("chime", 0.32)
		end,
	},
}

function def.release(run): boolean
	ImpactEffects.ball(run:hand("right"), GLOW, 1.2 * run:scale(), 0.12)
	return true
end

-- Sparks off one enemy as the cuts reach it (particles: no parts, however many are hit).
local function cutSparks(view, color: Color3)
	ImpactEffects.burst("spark", view.part.Position, nil, {
		color = WHITE,
		color2 = color,
		count = 10,
		size = 0.24,
		speed = { 8, 14 },
		lifetime = { 0.12, 0.25 },
	})
end

function def.event(run, event): boolean
	local kind = event.kind
	local crimson = run.style.primary
	if kind == "Area" then
		local center, radius = run:area()
		ImpactEffects.ball(center + Vector3.new(0, 1.2, 0), WHITE, radius * 1.1, 0.1)
		FxKit.ring(center, crimson, radius * 2.6, 0.45)
		FxKit.ring(center, WHITE, radius * 1.8, 0.3)
		Kit.slashes(run, 0, 0.45, center, radius, if run.reduced then 12 else 28, { crimson, WHITE, IVORY })
		for _, target in run:targets() do
			run:hitStop(target, 0.12)
		end
		run:shake(0.4)
		run:sound("whoosh", 1.6)
		run:at(0.12, function()
			run:sound("whoosh", 1.9)
		end)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view then
			cutSparks(view, crimson)
		end
		return true
	elseif kind == "Damage" and event.target and event.dot then
		-- A real tick of the damage over time: a few fresh cuts on that enemy.
		local view = run.context.views[event.target]
		if view then
			local at = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
			Kit.slashes(run, run:designTime(), run:designTime() + 0.15, at, 1.4, 4, { crimson, WHITE })
		end
		return true
	elseif kind == "Dot" then
		return true
	end
	return false
end

return def
