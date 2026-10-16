-- night_parade (Tier 4): collect, then compress into a spiral and release. The real casts take
-- turns: the first summons two curses (Summon events); the second recalls every living curse and
-- fires a line through his target (stronger per curse recalled), both at the Cast event. One
-- timeline, two choreographies, picked from the cast's real events.
-- Summon cast:
--   -0.80  an open palm rises; a dark purple-black vortex turns above it
--    0     on each real summon a curse drops out of the vortex onto its cell, in a burst of smoke
-- Firing cast:
--   -0.80  his living curses come apart into black streams that fly back to his palm
--   -0.40  they spiral into a dense black-purple ball that tightens and darkens; stillness, a push
--    0     the release: a swirling black-purple beam drills along the real line, impacts along it
--   +0.40  his robes settle; calm

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local DARK = Color3.fromRGB(20, 12, 28)

local def = {}

local function firing(run): boolean
	for _, event in run.cast do
		if event.kind == "Area" and event.shape == "LINE" then
			return true
		end
	end
	return false
end

-- Over his raised palm.
local function palmTop(run): Vector3
	return run:hand("right") + Vector3.new(0, 0.7, 0)
end

local SUMMON = {
	rightArm = { { -0.8, 0 }, { -0.55, 135, "out" }, { 0.35, 135 }, { 0.75, 0 } },
	rightArmOut = { { -0.8, 0 }, { -0.55, 12 }, { 0.35, 12 }, { 0.75, 0 } },
	leftArm = { { -0.8, 0 }, { -0.5, 20 }, { 0.5, 20 }, { 0.8, 0 } },
	lean = { { -0.8, 0 }, { -0.55, -5 }, { 0.5, -3 }, { 0.8, 0 } },
}

local FIRE = {
	rightArm = { { -0.8, 0 }, { -0.6, 80, "out" }, { -0.02, 84 }, { 0.03, 96, "snap" }, { 0.45, 90 }, { 0.8, 0 } },
	leftArm = { { -0.8, 0 }, { -0.6, 40 }, { -0.02, 40 }, { 0.03, 10, "snap" }, { 0.8, 0 } },
	twist = { { -0.6, 0 }, { -0.02, -12 }, { 0.03, 16, "snap" }, { 0.45, 8 }, { 0.8, 0 } },
	lean = { { -0.8, 0 }, { -0.6, -3 }, { -0.02, -4 }, { 0.03, 8, "snap" }, { 0.45, 3 }, { 0.8, 0 } },
	tremble = { { -0.2, 0 }, { -0.12, 0.6 }, { -0.02, 0.6 }, { 0, 0, "hold" } },
}

function def.poseFor(run)
	return if firing(run) then FIRE else SUMMON
end

-- The vortex over his palm: a dark core and a ring of dark orbs turning around it.
local function vortex(run, from: number, to: number)
	Kit.orb(run, from, to, DARK, function()
		return palmTop(run)
	end, function(u)
		return (0.4 + 0.5 * Kit.easeOut(u * 2)) * run:scale()
	end)
	for i = 1, (if run.reduced then 4 else 7) do
		local phase = i / 7 * 2 * math.pi
		Kit.live(run, from, to, "Ball", if i % 2 == 0 then run.style.primary else DARK, function(part, u)
			local angle = phase + run:now() * 7
			local r = 1.1 * run:scale() * (0.6 + 0.4 * Kit.easeOut(u * 2))
			part.Size = Vector3.one * 0.25
			part.CFrame = CFrame.new(
				palmTop(run) + Vector3.new(math.cos(angle) * r, math.sin(angle * 2) * 0.15, math.sin(angle) * r)
			)
			part.Transparency = 0.1
		end)
	end
end

def.beats = {
	{
		at = -0.8,
		run = function(run)
			run:face(run:target())
			run.memo.firing = firing(run)
			if not run.memo.firing then
				vortex(run, -0.6, 0.4)
				run:sound("charge", 0.7)
				return
			end
			-- His curses come apart into streams flying back to his palm.
			-- (one part per stream: a dark blob spiralling in along its own path)
			for _, summon in run:summons() do
				local start = summon.part.Position
				for k = 0, 2 do
					local phase = k * 2.1
					Kit.live(
						run,
						-0.78 + k * 0.1,
						-0.42 + k * 0.1,
						"Ball",
						if k == 1 then run.style.primary else DARK,
						function(part, u)
							local goal = run:hand("right")
							local along = start:Lerp(goal, Kit.easeIn(u))
							local side = math.sin(u * math.pi) * 1.2
							part.Size = Vector3.one * (0.6 - 0.35 * u)
							part.CFrame = CFrame.new(
								along
									+ Vector3.new(
										math.cos(phase + u * 8) * side,
										math.sin(phase + u * 8) * side * 0.5 + side,
										0
									)
							)
							part.Transparency = 0.1 + 0.4 * u
						end
					)
				end
			end
			-- The ball: tighter and darker as it gathers.
			Kit.orb(run, -0.5, 0, run.style.primary, function()
				return run:hand("right") + run:forward() * 0.4
			end, function(u)
				return (1.3 - 0.6 * Kit.easeIn(u)) * run:scale()
			end)
			Kit.converge(run, -0.5, -0.05, function()
				return run:hand("right")
			end, DARK, 2.4, if run.reduced then 6 else 12)
			run:camera(-0.4, 0, { key = "push", push = 2.4, focus = run:chest(), rise = 0.3, fall = 0.06 })
			run:camera(0, 0.5, { key = "pull", push = -1.6, focus = run:chest(), rise = 0.04, fall = 0.4 })
			run:sound("charge", 0.45)
		end,
	},
}

function def.release(run): boolean
	if run.memo.firing then
		ImpactEffects.ball(run:hand("right"), run.style.primary, 1.4 * run:scale(), 0.12)
	end
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Summon" then
		-- A curse drops out of the vortex onto its cell.
		local cell = run.context.toWorld(event.column, event.row)
		local from = palmTop(run)
		local now = run:designTime()
		Kit.live(run, now, now + 0.3, "Ball", DARK, function(part, u)
			local arc = Vector3.new(0, math.sin(u * math.pi) * 2.5, 0)
			part.Size = Vector3.one * (0.9 + 0.5 * u)
			part.CFrame = CFrame.new(from:Lerp(cell + Vector3.new(0, 0.8, 0), u) + arc)
			part.Transparency = 0.05
		end)
		run:at(now + 0.3, function()
			ImpactEffects.burst("smoke", cell + Vector3.new(0, 0.5, 0), Vector3.yAxis, {
				color = DARK,
				color2 = run.style.primary,
				count = 10,
				size = 1.1,
				speed = { 2, 4 },
				lifetime = { 0.5, 0.8 },
				spread = 60,
				transparency = 0.3,
			})
		end)
		return true
	elseif kind == "Area" and event.shape == "LINE" and event.cells then
		-- The spiral beam along the real line.
		local from = run:hand("right")
		local far, distance = from, -1
		for _, cell in event.cells do
			local at = run.context.toWorld(cell[1], cell[2]) + Vector3.new(0, 1.4, 0)
			local d = (at - from).Magnitude
			if d > distance then
				far, distance = at, d
			end
		end
		Kit.beam(run, 0, 0.5, run.style.primary, DARK, function()
			return from
		end, function()
			return far
		end, function(u)
			return 1.1 * run:scale() * (1 - 0.85 * Kit.easeIn(u))
		end)
		FxKit.beam(from, far, run.style.primary:Lerp(WHITE, 0.2), 0.9, 0.4, "spiral")
		for i, cell in event.cells do
			local at = run.context.toWorld(cell[1], cell[2])
			run:at(0.03 * i, function()
				ImpactEffects.ball(at + Vector3.new(0, 1.2, 0), run.style.primary, 1.8, 0.15)
				FxKit.ring(at, DARK, 3, 0.3)
			end)
		end
		for _, target in run:targets() do
			run:hitStop(target, 0.08)
		end
		run:shake(0.3)
		run:sound("whoosh", 0.8)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the beam's impacts cover each hit
	end
	return false
end

return def
