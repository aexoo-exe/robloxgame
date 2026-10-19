-- ascending_core (Tier 5): stronger with every cast, then the full-board beam. The real casts:
-- Core I and Core II each hit an area around his target and step him up a form at the Cast event;
-- in Core III each cast is a line from him to the board's edge. One timeline, two choreographies,
-- picked from the cast's real events.
-- Power-up (a cast with a form change):
--   -0.90  fists clench, arms down and out, he leans back and yells (a shiver of strain)
--   -0.55  gold aura spikes rise around him and climb (blue sparks too on the way to Core III)
--   -0.08  one palm snaps forward: a ki blast crosses to the target
--    0     the real hit (a gold-white burst) and the real form change: an eruption of gold
-- Beam (Core III):
--   -0.90  hands cupped at his right hip, body turned away, low
--   -0.60  blue-white light grows between his hands, small stones float up, the camera leans in
--   -0.15  stillness
--    0     both hands thrust: a huge beam along the real line to the board's edge, impacts along it
--   +0.45  the beam thins out; steam rises off him
-- Layers: the shared recipe (VfxRecipe, energy themes in his gold and blue, tier 5).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local STONE = Color3.fromRGB(150, 140, 128)
-- The aura spikes: gold fading to deep orange.
local AURA_GOLD = Color3.fromRGB(255, 200, 40)
local AURA_DEEP = Color3.fromRGB(255, 140, 0)
local HEX = math.sqrt(3) * RenderConfig.hexRadius -- between neighboring cell centers

local def = {}

-- The cast's line (Core III), if it is one.
local function lineOf(run): any?
	for _, event in run.cast do
		if event.kind == "Area" and event.shape == "LINE" and event.cells then
			return event
		end
	end
	return nil
end

-- Where the beam ends: half a cell past the line's farthest cell from him.
local function beamEnd(run, line): Vector3
	local from = run.context.toWorld(line.fromColumn or line.column, line.fromRow or line.row)
	local far, distance = from, -1
	for _, cell in line.cells do
		local at = run.context.toWorld(cell[1], cell[2])
		local d = (at - from).Magnitude
		if d > distance then
			far, distance = at, d
		end
	end
	local direction = Vector3.new(far.X - from.X, 0, far.Z - from.Z)
	direction = if direction.Magnitude > 1e-3 then direction.Unit else run:forward()
	return far + direction * HEX * 0.5 + Vector3.new(0, 1.6, 0)
end

local function cupped(run): Vector3
	return (run:hand("left") + run:hand("right")) / 2
end

local POWER_UP = {
	leftArm = { { -0.9, 0 }, { -0.7, -12, "out" }, { -0.1, -12 }, { -0.02, 20, "snap" }, { 0.4, 0 }, { 1.0, 0 } },
	leftArmOut = { { -0.9, 0 }, { -0.7, 26, "out" }, { -0.1, 30 }, { -0.02, 10, "snap" }, { 0.5, 0 } },
	rightArm = { { -0.9, 0 }, { -0.7, -12, "out" }, { -0.1, -12 }, { -0.02, 96, "snap" }, { 0.3, 90 }, { 0.9, 0 } },
	rightArmOut = { { -0.9, 0 }, { -0.7, 26, "out" }, { -0.1, 30 }, { -0.02, 0, "snap" }, { 0.5, 0 } },
	lean = { { -0.9, 0 }, { -0.7, -9, "out" }, { -0.1, -11 }, { -0.02, 9, "snap" }, { 0.4, 2 }, { 0.9, 0 } },
	twist = { { -0.1, 0 }, { -0.02, 20, "snap" }, { 0.35, 10 }, { 0.9, 0 } },
	crouch = { { -0.9, 0 }, { -0.7, 0.12 }, { -0.1, 0.14 }, { -0.02, 0.03, "snap" }, { 0.4, 0 } },
	tremble = { { -0.7, 0 }, { -0.5, 1 }, { -0.1, 1.8 }, { -0.02, 0, "hold" } },
	lunge = { { -0.02, 0 }, { 0.05, 0.35, "snap" }, { 0.5, 0 } },
}

local BEAM = {
	-- Both hands go to the right hip, the left crossing over; the body turns away and sinks.
	leftArm = { { -0.9, 0 }, { -0.62, 30, "out" }, { -0.15, 34 }, { -0.02, 92, "snap" }, { 0.5, 88 }, { 1.1, 0 } },
	leftArmOut = { { -0.9, 0 }, { -0.62, -28, "out" }, { -0.15, -28 }, { -0.02, -6, "snap" }, { 0.5, -4 }, { 1.1, 0 } },
	rightArm = { { -0.9, 0 }, { -0.62, 26, "out" }, { -0.15, 30 }, { -0.02, 92, "snap" }, { 0.5, 88 }, { 1.1, 0 } },
	rightArmOut = { { -0.9, 0 }, { -0.62, 6, "out" }, { -0.02, 6, "snap" }, { 1.1, 0 } },
	twist = { { -0.9, 0 }, { -0.62, -34, "out" }, { -0.15, -38 }, { -0.02, 14, "snap" }, { 0.5, 8 }, { 1.1, 0 } },
	lean = { { -0.9, 0 }, { -0.62, -4 }, { -0.15, -6 }, { -0.02, 10, "snap" }, { 0.5, 6 }, { 1.1, 0 } },
	crouch = { { -0.9, 0 }, { -0.62, 0.16 }, { -0.15, 0.18 }, { -0.02, 0.1, "snap" }, { 0.6, 0.08 }, { 1.1, 0 } },
	tremble = { { -0.3, 0 }, { -0.15, 1.2 }, { -0.02, 0, "hold" }, { 0.05, 0.9 }, { 0.45, 0.9 }, { 0.5, 0, "hold" } },
	lunge = { { -0.02, 0 }, { 0.04, -0.25, "snap" }, { 0.5, -0.2 }, { 1.0, 0 } },
}

function def.poseFor(run)
	return if lineOf(run) then BEAM else POWER_UP
end

-- Gold aura spikes, then a palm blast at the target.
local function powerUp(run)
	local gold = run.style.secondary
	local toCoreThree = false
	for _, event in run.cast do
		if event.kind == "Form" and (event.formIndex or 0) >= 3 then
			toCoreThree = true
		end
	end
	run.memo.toCoreThree = toCoreThree
	-- The gold flame aura (fx_aura_spike): three overlapping sheets on his torso rising off him,
	-- 1-1.3x his height, turned a little and flickering, gold to deep orange, through the power-up;
	-- gold motes under it (particles: no glow sheet or shell; the form looks have none either).
	VfxRecipe.kitAuraSpike(run, run.view, AURA_GOLD, -0.55, 0.85, 3, AURA_DEEP)
	VfxRecipe.aura(run, run.view, VfxRecipe.energy(gold, WHITE:Lerp(gold, 0.4)), 0.8, -0.55, 0.85)
	-- Small blue crackle over him (more on the way to Core III).
	VfxRecipe.kitCrackleAura(run, run.view, run.style.primary, -0.5, 0.5, if toCoreThree then 2 else 1)
	run:sound("charge", if toCoreThree then 1.1 else 0.85)
	run:at(-0.08, function()
		local target = run:target()
		if not target then
			return
		end
		-- The ki blast: a gold streak of glow crossing to the target (no solid ball).
		local from = run:hand("right")
		local along = target.part.Position - from
		if along.Magnitude > 1e-3 then
			ImpactEffects.emit(from, {
				usage = "sparks",
				count = if run.reduced then 2 else 4,
				color = VfxRecipe.colors({ { 0, WHITE:Lerp(gold, 0.35) }, { 1, gold } }),
				size = VfxRecipe.curve({ { 0, 0.8 * run:scale() }, { 1, 0.35 * run:scale() } }),
				transparency = VfxRecipe.curve({ { 0, 0.1 }, { 0.8, 0.3 }, { 1, 1 } }),
				lifetime = { 0.08, 0.1 },
				speed = { along.Magnitude / 0.09, along.Magnitude / 0.08 },
				spread = 4,
				direction = along.Unit,
				lightEmission = 1,
				brightness = 2.5,
				stretch = true,
			})
		end
		run:sound("whoosh", 1.4)
	end)
end

-- The beam's gathering: light between his hands, stones lifting off the ground.
local function gather(run)
	local blue = run.style.primary
	Kit.orb(run, -0.6, 0, blue:Lerp(WHITE, 0.4), function()
		return cupped(run)
	end, function(u)
		return (0.3 + 1.1 * Kit.easeIn(u)) * run:scale()
	end)
	Kit.converge(run, -0.6, -0.1, function()
		return cupped(run)
	end, blue:Lerp(WHITE, 0.5), 2.4, if run.reduced then 6 else 12)
	if not run.reduced then
		local ground = run:ground()
		for i = 1, 6 do
			local angle = i / 6 * 2 * math.pi + math.random() * 0.4
			local r = 2 + math.random() * 2.5
			local at = ground + Vector3.new(math.cos(angle) * r, 0.15, math.sin(angle) * r)
			local spin = math.random() * 3
			Kit.block(run, -0.55, 0.6, STONE, function(u)
				local lift = Kit.easeOut(u * 1.6) * (1 + i % 3 * 0.5)
				return CFrame.new(at + Vector3.new(0, lift, 0)) * CFrame.Angles(spin * u, spin, 0)
			end, function()
				return Vector3.new(0.35, 0.3, 0.32)
			end, function(u)
				return if u > 0.8 then (u - 0.8) * 5 else 0
			end, Enum.Material.Slate)
		end
	end
	run:camera(-0.6, 0, { key = "push", push = 3, focus = run:chest(), rise = 0.35, fall = 0.06 })
	run:camera(0, 0.6, { key = "pull", push = -2, focus = run:chest(), rise = 0.05, fall = 0.4 })
	run:sound("charge", 1.3)
end

def.beats = {
	{
		at = -0.9,
		run = function(run)
			run:face(run:target())
			run.memo.line = lineOf(run)
			if run.memo.line then
				gather(run)
			else
				run:at(-0.55, powerUp)
			end
		end,
	},
}

function def.release(run): boolean
	if not run.memo.line then
		-- The palm's pop (a short tinted flash and stars, not a white ball).
		local gold = run.style.secondary
		VfxRecipe.pop(run, run:hand("right"), 0.9 * run:scale(), VfxRecipe.energy(gold, WHITE:Lerp(gold, 0.4)))
	end
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	local blue, gold = run.style.primary, run.style.secondary
	if kind == "Area" and event.shape == "LINE" and event.cells then
		-- The beam, held, then thinning out, with impacts along the whole line.
		local finish = beamEnd(run, event)
		local width = 1.6 * run:scale()
		Kit.beam(run, 0, 0.9, WHITE:Lerp(blue, 0.25), blue, function()
			return cupped(run)
		end, function()
			return finish
		end, function(u)
			return width
				* (if u < 0.4 then 1 + 0.15 * math.sin(run:now() * 40) else 1 - Kit.easeIn((u - 0.4) / 0.6) * 0.92)
		end)
		local impact = VfxRecipe.energy(blue, WHITE:Lerp(blue, 0.3))
		for i, cell in event.cells do
			local at = run.context.toWorld(cell[1], cell[2])
			run:at(0.02 * i, function()
				-- An impact along the line: a small core, a blue glow sheet, sparks, the ground marked.
				VfxRecipe.hit(run, at + Vector3.new(0, 1.4, 0), 2.6, impact)
				FxKit.mark(at, blue, WHITE, 1.4, "scorch", 1.0)
			end)
		end
		for _, target in run:targets() do
			run:hitStop(target, 0.1)
		end
		run:shake(0.4)
		run:sound("whoosh", 0.7)
		-- Steam rising off him after the beam.
		for t = 0.6, 1.1, 0.25 do
			run:at(t, function()
				ImpactEffects.burst("puff", run:chest(), Vector3.yAxis, {
					color = WHITE,
					count = 4,
					size = 0.7,
					speed = { 1, 2 },
					lifetime = { 0.6, 0.9 },
					spread = 30,
					transparency = 0.5,
				})
			end)
		end
		return true
	elseif kind == "Area" then
		-- The blast at the target: a gold-white burst.
		local center, radius = run:area()
		-- The gold burst: the shared recipe in his gold (core, glow sheet and side sheets, all capped
		-- at 1.5 unit heights; the flat shock ring, sparks, light), then gold embers and a little
		-- dark smoke.
		local burst = VfxRecipe.energy(gold, WHITE:Lerp(gold, 0.4))
		VfxRecipe.burst(run, center, radius, { theme = burst })
		VfxRecipe.aftermath(run, center, radius, { theme = burst })
		-- Its impact: a gold hit star (fx_impact_star) about a unit's size (the burst has the ring).
		local height = run.view.part.Size.Y
		VfxRecipe.kitHitStar(
			center + Vector3.new(0, 1.4, 0),
			math.min(radius * 1.2, height * 1.3),
			gold:Lerp(WHITE, 0.15)
		)
		return true
	elseif kind == "Form" then
		-- The step up: an eruption of gold around him.
		-- An eruption of gold off his body (an aura flaring up, not a see-through column).
		local ground = run:ground()
		FxKit.ring(ground, gold, HEX * 2.2, 0.5)
		local power = VfxRecipe.energy(gold, WHITE:Lerp(gold, 0.4))
		VfxRecipe.aura(run, run.view, power, 1.6, run:designTime(), 0.6)
		VfxRecipe.embers(run, ground + Vector3.new(0, 0.5, 0), run:scale(), power.ember, 14)
		VfxRecipe.core(run:chest(), run.view.part.Size.Y * 0.8, 1, power.core)
		VfxRecipe.sparks(run:chest(), 0.7 * run:scale(), 30, power.spark)
		VfxRecipe.light(run, run:chest(), 2.5 * run:scale(), power.light, 1)
		if run.memo.toCoreThree then
			FxKit.ring(ground, blue, HEX * 2.8, 0.55)
		end
		run:shake(0.35)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view then
			ImpactEffects.burst("spark", view.part.Position, nil, {
				color = WHITE,
				color2 = if run.memo.line then blue else gold,
				count = 10,
				size = 0.28,
				speed = { 8, 14 },
				lifetime = { 0.15, 0.3 },
			})
		end
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		return true -- his stacks: the aura already says it
	end
	return false
end

return def
