-- restoration_strike (Tier 4): the fixer. The real cast shields him, heals his two lowest-health
-- other allies and hits his target, all at the Cast event.
--   -0.85  a pink-white spirit fades in behind him, standing tall over his shoulders
--   -0.60  diamond shards swirl around him, closing in
--    0     the shards lock into his real shield (a flash, a pink shell); beams of pink light reach
--          each ally he really heals, and the cracks on them close up with sparkles ("repair",
--          not a plain heal); the spirit throws three quick jabs into his target, a pink diamond
--          burst on each
--   +0.40  proud pose; the spirit and the shards fade

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local CRACK = Color3.fromRGB(70, 40, 60)

local def = {}

def.pose = {
	rightArm = { { -0.85, 0 }, { -0.6, 30 }, { -0.02, 30 }, { 0.02, 92, "snap" }, { 0.4, 88 }, { 0.6, 0 } },
	leftArm = { { -0.85, 0 }, { -0.6, -12 }, { 0.6, -12 }, { 0.8, 0 } },
	leftArmOut = { { -0.85, 0 }, { -0.6, 26 }, { 0.6, 26 }, { 0.8, 0 } },
	lean = { { -0.85, 0 }, { -0.6, -6, "out" }, { 0.02, 4, "snap" }, { 0.4, -5 }, { 0.8, 0 } },
	twist = { { -0.02, 0 }, { 0.02, 16, "snap" }, { 0.4, 10 }, { 0.8, 0 } },
}

-- The spirit's frame: behind him and a little above, facing the way he faces.
local function spiritFrame(run): CFrame
	local forward = run:forward()
	local base = run:ground() - forward * 1.4 + Vector3.new(0, run.view.part.Size.Y * 0.62, 0)
	return CFrame.lookAt(base, base + forward)
end

-- How solid the spirit is at the design time now.
local function spiritAlpha(run): number
	local t = run:designTime()
	return Kit.smooth((t + 0.85) / 0.25) * (1 - Kit.smooth((t - 0.35) / 0.35))
end

local function spiritPart(run, color: Color3, offset: (number) -> CFrame, size: Vector3)
	Kit.block(run, -0.85, 0.7, color, function()
		local t = run:designTime()
		return spiritFrame(run) * offset(t)
	end, function()
		return size
	end, function()
		return 1 - 0.55 * spiritAlpha(run)
	end, Enum.Material.Neon)
end

local function buildSpirit(run)
	local pink, white = run.style.primary, run.style.secondary
	local h = run.view.part.Size.Y * 1.25
	local c = CFrame.new
	spiritPart(run, pink, function()
		return c(0, 0, 0)
	end, Vector3.new(h * 0.36, h * 0.38, h * 0.2))
	spiritPart(run, white, function()
		return c(0, h * 0.3, 0)
	end, Vector3.new(h * 0.22, h * 0.22, h * 0.22))
	-- The tall crest over its head.
	spiritPart(run, pink, function()
		return c(0, h * 0.45, -h * 0.05) * CFrame.Angles(math.rad(-25), 0, 0)
	end, Vector3.new(h * 0.16, h * 0.18, h * 0.3))
	-- Its arms: the left at its side, the right thrown forward for each jab after the release.
	spiritPart(run, pink, function()
		return c(-h * 0.25, -h * 0.05, 0)
	end, Vector3.new(h * 0.1, h * 0.36, h * 0.1))
	spiritPart(run, pink, function(t)
		local jab = if t < 0 then 0 else math.max(0, math.sin(math.clamp(t / 0.24, 0, 1) * math.pi * 3))
		return c(h * 0.25, h * 0.05, -h * (0.05 + 0.5 * jab))
			* CFrame.Angles(math.rad(-90 * math.min(1, jab * 3)), 0, 0)
	end, Vector3.new(h * 0.1, h * 0.36, h * 0.1))
end

def.beats = {
	{
		at = -0.85,
		run = function(run)
			run:face(run:target())
			buildSpirit(run)
			run:sound("chime", 1.1)
		end,
	},
	{
		-- Diamond shards swirling in.
		at = -0.6,
		run = function(run)
			local pink = run.style.primary
			for i = 1, (if run.reduced then 4 else 7) do
				local phase = i / 7 * 2 * math.pi
				Kit.block(run, -0.6, 0.05, pink:Lerp(WHITE, (i % 2) * 0.5), function(u)
					local angle = phase + u * 7
					local r = run.view.part.Size.Y * (0.9 - 0.45 * Kit.easeIn(u))
					local at = run:chest()
						+ Vector3.new(math.cos(angle) * r, math.sin(u * 9 + i) * 0.6, math.sin(angle) * r)
					return CFrame.new(at) * CFrame.Angles(u * 6, u * 4, math.rad(45))
				end, function()
					return Vector3.new(0.3, 0.3, 0.1)
				end, function()
					return 0.1
				end, Enum.Material.Glass)
			end
			run:camera(-0.5, 0, { key = "push", push = 1.8, focus = run:chest(), rise = 0.3, fall = 0.15 })
		end,
	},
}

function def.release(_run): boolean
	return true -- the shield, the repairs and the jabs carry the moment
end

-- A "repair" on an ally: cracks across it that close up, and sparkles.
local function repair(run, view)
	local now = run:designTime()
	for i = 1, 3 do
		local tilt = (i - 2) * 0.6
		Kit.block(run, now + 0.05, now + 0.5, CRACK, function()
			return CFrame.new(view.part.Position + Vector3.new(0, (i - 2) * 0.5, -view.part.Size.Z * 0.55))
				* CFrame.Angles(0, 0, tilt)
		end, function(u)
			return Vector3.new(math.max(0.05, view.part.Size.X * 0.9 * (1 - Kit.easeIn(u))), 0.06, 0.05)
		end, function()
			return 0.1
		end)
	end
	ImpactEffects.burst("spark", view.part.Position, nil, {
		color = WHITE,
		color2 = run.style.primary,
		count = 10,
		size = 0.24,
		speed = { 2, 5 },
		lifetime = { 0.3, 0.55 },
	})
end

function def.event(run, event): boolean
	local kind = event.kind
	local pink = run.style.primary
	if kind == "Shield" and event.target == run.unitIndex then
		ImpactEffects.ball(run:chest(), WHITE, run.view.part.Size.Y * 0.9, 0.12)
		Kit.shell(run, 0, 0.45, pink, run.view.part.Position, function(u)
			return run.view.part.Size.Y * (1.3 + 0.15 * u)
		end, function(u)
			return 0.55 + 0.45 * u
		end, Enum.Material.Glass)
		return false -- the shield bubble still shows
	elseif kind == "Heal" and event.target and event.target ~= run.unitIndex then
		local view = run.context.views[event.target]
		if view then
			FxKit.beam(run:chest(), view.part.Position, pink:Lerp(WHITE, 0.3), 0.3, 0.35, "straight")
			repair(run, view)
		end
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view then
			-- Three jabs: a diamond burst on each.
			for i = 0, 2 do
				run:at(i * 0.08, function()
					local at = view.part.Position + Vector3.new((i - 1) * 0.4, 0.3 + i * 0.25, 0)
					ImpactEffects.ball(at, pink:Lerp(WHITE, 0.4), 1.6, 0.1)
					ImpactEffects.burst("spark", at, nil, {
						color = pink,
						color2 = WHITE,
						count = 8,
						size = 0.26,
						speed = { 8, 14 },
						lifetime = { 0.12, 0.25 },
					})
					run:hitStop(view, 0.05)
				end)
			end
			run:shake(0.2)
			run:sound("whoosh", 1.5)
		end
		return true
	end
	return false
end

return def
