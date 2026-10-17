-- infinite_collapse (Tier 5): blue and red become purple. The real cast holds every enemy within 2
-- hexes of the highest-AD enemy, shields him and blasts the same area, all at the Cast event; so the
-- whole build plays before it and the erasure lands on its real events.
--   -1.20  he stops, calm; the screen dims a little
--   -0.95  right hand out: a blue orb draws dust and sparks in
--   -0.65  left hand out: a red orb pushes them away
--   -0.30  hands together: the orbs spiral into each other, a crackling purple sphere; the camera
--          pushes in, he trembles with the held tension
--   -0.10  the flick: the sphere crosses to the area far faster than anything before it
--    0     the real hits: a white flash, a purple erasure over the area, a dark distortion, a
--          glowing crater and the groove the sphere cut; a faint blue shimmer of his shield
--   +0.30  one hand in his pocket while motes drift off the crater
-- Layers at the erasure: the shared recipe (VfxRecipe, an energy theme in his purple, tier 5).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local PURPLE = Color3.fromRGB(176, 86, 255)
local DEEP = Color3.fromRGB(58, 16, 92)
local BLUE_SHIELD = Color3.fromRGB(150, 205, 255)
-- His erasure: purple glow sheets, white-violet sparks, dark violet smoke, violet embers.
local ERASURE = VfxRecipe.energy(PURPLE, Color3.fromRGB(225, 190, 255))

-- Where his hands meet in front of the chest.
local function between(run): Vector3
	return (run:hand("left") + run:hand("right")) / 2
end

local def = {}

def.pose = {
	-- Right arm out first, left after: offset timing; then both in, then the flick on the right.
	rightArm = {
		{ -1.2, 0 },
		{ -0.95, 0 },
		{ -0.72, 82, "out" },
		{ -0.3, 82 },
		{ -0.18, 68 },
		{ -0.03, 108, "snap" },
		{ 0.25, 96 },
		{ 0.75, 12 },
		{ 1.3, 0 },
	},
	rightArmOut = { { -0.95, 0 }, { -0.72, 32, "out" }, { -0.3, 30 }, { -0.16, 4 }, { 0.3, 0 } },
	leftArm = {
		{ -0.68, 0 },
		{ -0.45, 82, "out" },
		{ -0.3, 82 },
		{ -0.18, 68 },
		{ -0.03, 25, "snap" },
		{ 0.3, -10 },
		{ 0.8, -12 },
		{ 1.3, 0 },
	},
	-- The left hand goes to the hip after the flick: his hand in his pocket.
	leftArmOut = {
		{ -0.68, 0 },
		{ -0.45, 32, "out" },
		{ -0.3, 30 },
		{ -0.16, 6 },
		{ 0.3, 14 },
		{ 0.8, 14 },
		{ 1.3, 0 },
	},
	twist = {
		{ -1.2, 0 },
		{ -0.72, 10 },
		{ -0.45, -6 },
		{ -0.16, 0 },
		{ -0.03, 24, "snap" },
		{ 0.25, 14 },
		{ 0.8, 3 },
		{ 1.3, 0 },
	},
	lean = {
		{ -1.2, 0 },
		{ -1.0, -4, "out" },
		{ -0.3, -3 },
		{ -0.16, 3 },
		{ -0.03, 11, "snap" },
		{ 0.3, 4 },
		{ 0.8, -4 },
		{ 1.3, 0 },
	},
	crouch = { { -0.3, 0 }, { -0.16, 0.07 }, { -0.03, 0.02, "snap" }, { 0.35, 0 } },
	tremble = { { -0.3, 0 }, { -0.24, 0.8 }, { -0.12, 1.4 }, { -0.04, 0, "hold" } },
	lunge = { { -0.03, 0 }, { 0.03, 0.3, "snap" }, { 0.45, 0 } },
}

def.beats = {
	{
		at = -1.2,
		run = function(run)
			run:face(run:target())
			-- Everything nearby dims a little while he builds; the push comes at the merge.
			run:camera(-1.2, 0.5, { key = "dim", dim = 0.18, rise = 0.35, fall = 0.4 })
		end,
	},
	{
		-- The blue orb on the right hand, drawing dust and sparks in.
		at = -0.95,
		run = function(run)
			local blue = run.style.primary
			Kit.orb(run, -0.95, -0.3, blue, function()
				return run:hand("right")
			end, function(u)
				return (0.25 + 0.55 * Kit.easeOut(u * 1.6)) * run:scale()
			end)
			Kit.converge(run, -0.95, -0.3, function()
				return run:hand("right")
			end, blue:Lerp(WHITE, 0.4), 2.6, if run.reduced then 6 else 14)
			if not run.reduced then
				Kit.converge(run, -0.9, -0.3, function()
					return run:hand("right")
				end, Kit.DUST, 2.2, 8)
			end
			run:sound("charge", 0.8)
		end,
	},
	{
		-- The red orb on the left hand, pushing everything away from it.
		at = -0.65,
		run = function(run)
			local red = run.style.secondary
			Kit.orb(run, -0.65, -0.3, red, function()
				return run:hand("left")
			end, function(u)
				return (0.25 + 0.5 * Kit.easeOut(u * 1.6)) * run:scale()
			end)
			Kit.converge(run, -0.62, -0.3, function()
				return run:hand("left")
			end, red:Lerp(WHITE, 0.3), 2.4, if run.reduced then 6 else 14, true)
			for i = 0, 2 do
				-- Pulses of pressure rolling off it.
				Kit.live(run, -0.6 + i * 0.1, -0.42 + i * 0.1, "Ball", red, function(part, u)
					part.Size = Vector3.one * (0.6 + 2.2 * Kit.easeOut(u)) * run:scale()
					part.CFrame = CFrame.new(run:hand("left"))
					part.Transparency = 0.55 + 0.45 * u
				end)
			end
			run:sound("charge", 1.35)
		end,
	},
	{
		-- The merge: the two orbs spiral into the point between his hands and collapse into purple.
		at = -0.3,
		run = function(run)
			local blue, red = run.style.primary, run.style.secondary
			for i, color in { blue, red } do
				local phase = if i == 1 then 0 else math.pi
				local hand = if i == 1 then "right" else "left"
				Kit.live(run, -0.3, -0.12, "Ball", color, function(part, u)
					local k = Kit.easeIn(u)
					local center = run:hand(hand):Lerp(between(run), k)
					local angle = phase + u * 9
					local r = 0.5 * (1 - k) * run:scale()
					part.Size = Vector3.one * (0.75 * (1 - 0.55 * k)) * run:scale()
					part.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * r, math.sin(angle) * r * 0.6, 0))
					part.Transparency = 0.05
				end)
			end
			-- The purple sphere, crackling, held between his hands until the flick.
			Kit.orb(run, -0.2, -0.1, PURPLE, function()
				return between(run)
			end, function(u)
				return (0.3 + 0.9 * Kit.easeOut(u)) * run:scale()
			end)
			for i = 0, (if run.reduced then 1 else 3) do
				run:at(-0.2 + i * 0.03, function()
					local center = between(run)
					local offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.6
					FxKit.beam(center, center + offset, WHITE:Lerp(PURPLE, 0.4), 0.18, 0.08, "jagged")
				end)
			end
			-- Silence and the push: the camera leans in on him until the flick, then snaps back as
			-- the erasure lands (the contrast is the point).
			run:camera(-0.3, 0, { key = "push", push = 3.5, focus = run:chest(), rise = 0.2, fall = 0.06 })
			run:camera(0, 0.55, { key = "pull", push = -2.2, focus = run:chest(), rise = 0.04, fall = 0.45 })
			run:sound("chime", 0.5)
		end,
	},
	{
		-- The flick: the sphere crosses to the area in a blink, cutting a streak behind it.
		at = -0.1,
		run = function(run)
			local start = between(run)
			local center = run:area()
			local goal = center + Vector3.new(0, 1.2, 0)
			Kit.live(run, -0.1, 0, "Ball", PURPLE, function(part, u)
				part.Size = Vector3.one * 1.2 * run:scale()
				part.CFrame = CFrame.new(start:Lerp(goal, Kit.easeIn(u)))
				part.Transparency = 0
			end)
			FxKit.beam(start, goal, PURPLE:Lerp(WHITE, 0.3), 0.35, 0.25, "straight", run:span(-0.1, 0.06))
			run:sound("whoosh", 1.3)
		end,
	},
}

-- The cast itself: the generic burst at his hands is replaced by a small purple snap.
function def.release(run): boolean
	ImpactEffects.ball(run:hand("right"), PURPLE:Lerp(WHITE, 0.5), 1.4 * run:scale(), 0.12)
	return true
end

-- The real hits: the erasure on the area, a distortion on each enemy hit, the shield shimmer.
function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		local center, radius = run:area()
		local air = center + Vector3.new(0, 1.2, 0)
		-- The flash and the purple erasure (core, glow sheet and side sheets, shockwave, sparks,
		-- light), then the residue: violet embers, dark smoke.
		VfxRecipe.burst(run, center, radius, { theme = ERASURE })
		VfxRecipe.aftermath(run, center, radius, { theme = ERASURE })
		-- The dark distortion that hangs a moment after the flash.
		Kit.shell(run, 0.06, 0.7, DEEP, air, function(u)
			return radius * (1.2 + 0.5 * u)
		end, function(u)
			return 0.35 + 0.65 * Kit.easeIn(u)
		end, Enum.Material.Glass)
		-- The crater: dark ground, a glowing rim, cracks, and the groove the sphere cut.
		Kit.pool(run, 0, 1.3, DEEP, center, function()
			return radius * 2
		end, function(u)
			return 0.25 + 0.75 * Kit.easeIn(u)
		end)
		Kit.pool(run, 0, 1.1, PURPLE, center, function(u)
			return radius * (2 + 0.15 * u)
		end, function(u)
			return 0.55 + 0.45 * u
		end, Enum.Material.Neon)
		FxKit.mark(center, PURPLE, WHITE, radius * 0.9, "crack", 1.3)
		if not run.reduced then
			Kit.groove(run, 0, 1.2, PURPLE, run:ground(), center, 0.5)
			Kit.drift(run, 0.2, 1.1, PURPLE:Lerp(WHITE, 0.3), center, radius, 0.18)
		end
		-- The impact frame holds: every enemy hit and the caster freeze for a beat (cosmetic only).
		for _, target in run:targets() do
			run:hitStop(target, 0.14)
		end
		run:hitStop(nil, 0.08)
		run:shake(0.45)
		run:sound("whoosh", 0.55)
		return true
	elseif kind == "AreaStun" then
		return true -- the erasure is the held area's mark
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view then
			local at = view.part.Position
			ImpactEffects.ball(at, DEEP, view.part.Size.Y * 0.9, 0.3)
			ImpactEffects.burst("spark", at, nil, {
				color = WHITE,
				color2 = PURPLE,
				count = 8,
				size = 0.25,
				speed = { 6, 12 },
				lifetime = { 0.15, 0.3 },
			})
		end
		return true
	elseif kind == "Shield" and event.target == run.unitIndex then
		local at = run.view.part.Position
		Kit.shell(run, 0, 0.5, BLUE_SHIELD, at, function(u)
			return run.view.part.Size.Y * (1.2 + 0.2 * u)
		end, function(u)
			return 0.7 + 0.3 * u
		end)
		return false -- the shield bubble still shows (CombatPlayback)
	end
	return false
end

return def
