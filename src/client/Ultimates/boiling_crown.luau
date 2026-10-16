-- boiling_crown (Tier 5): a giant becoming a volcano. The real cast is a blast over everything
-- within 2 hexes of him at the Cast event (his aura keeps ticking on its own). He is a store model
-- (no limbs to pose), so the choreography is his whole body: the sink, the tremble, the heave.
--   -1.05  he goes still and sinks a little; his steam thickens and turns from white to orange
--   -0.60  a glow builds in his chest; the ground under him blackens and cracks outward; he
--          trembles harder and harder
--   -0.15  stillness; the camera leans in
--    0     the eruption: a column and a dome of superheated steam over the real area, shockwave
--          rings, hit-stop; he heaves up and back
--   +0.10  steam rolls out across the area and thins; the ground stays scorched a while

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local HOT = Color3.fromRGB(255, 140, 60)
local EMBER = Color3.fromRGB(255, 80, 40)
local CHAR = Color3.fromRGB(26, 18, 16)

local def = {}

def.pose = {
	crouch = { { -1.05, 0 }, { -0.6, 0.25 }, { -0.15, 0.32 }, { 0, 0, "snap" }, { 0.5, 0.05 }, { 1.2, 0 } },
	lean = { { -1.05, 0 }, { -0.6, 3 }, { -0.15, 5 }, { 0, -10, "snap" }, { 0.5, -4 }, { 1.2, 0 } },
	tremble = { { -0.6, 0 }, { -0.3, 1 }, { -0.16, 2 }, { -0.15, 0, "hold" }, { 0.05, 1.2 }, { 0.5, 0 } },
	rise = { { -0.02, 0 }, { 0.06, 0.6, "snap" }, { 0.55, 0 } },
}

-- A point just in front of his chest (the model has no hands).
local function chestFront(run): Vector3
	return run:chest() + run:forward() * run.view.part.Size.Z * 0.35 + Vector3.new(0, run.view.part.Size.Y * 0.1, 0)
end

def.beats = {
	{
		at = -1.05,
		run = function(run)
			run:camera(-1.05, 0.5, { key = "dim", dim = 0.25, rise = 0.4, fall = 0.4 })
			-- His steam thickens and heats from white to orange.
			local t = -1.0
			while t < -0.15 do
				local heat = (t + 1.0) / 0.85
				run:at(t, function()
					ImpactEffects.burst(
						"puff",
						run:chest() + Vector3.new(0, run.view.part.Size.Y * 0.2, 0),
						Vector3.yAxis,
						{
							color = WHITE:Lerp(HOT, heat),
							count = if run.reduced then 3 else 6,
							size = 1.2 + heat,
							speed = { 2, 4 + heat * 3 },
							lifetime = { 0.6, 1 },
							spread = 50,
							transparency = 0.45 - heat * 0.15,
						}
					)
				end)
				t += 0.1
			end
			run:sound("charge", 0.4)
		end,
	},
	{
		-- The chest glow and the ground going black and cracking.
		at = -0.6,
		run = function(run)
			Kit.orb(run, -0.6, 0.05, EMBER, function()
				return chestFront(run)
			end, function(u)
				return (0.6 + 1.6 * Kit.easeIn(u)) * run:scale()
			end)
			local center, radius = run:area()
			Kit.pool(run, -0.6, 1.4, CHAR, center, function()
				local t = run:designTime()
				return radius * 2.1 * Kit.easeOut((t + 0.6) / 0.5)
			end, function()
				local t = run:designTime()
				return 0.2 + 0.8 * Kit.smooth((t - 0.6) / 0.8)
			end)
			run:at(-0.4, function()
				FxKit.mark(center, EMBER, HOT, radius * 0.95, "crack", run:span(-0.4, 0.4) + 1.4)
			end)
			run:camera(-0.6, 0, { key = "push", push = 2.6, focus = run:chest(), rise = 0.35, fall = 0.05 })
			run:camera(0, 0.6, { key = "pull", push = -2.2, focus = run:chest(), rise = 0.04, fall = 0.45 })
			run:sound("charge", 0.3)
		end,
	},
}

function def.release(_run): boolean
	return true -- the eruption is the release (on the real area hit)
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		local center, radius = run:area()
		local height = run.view.part.Size.Y * 2.6
		ImpactEffects.ball(center + Vector3.new(0, 2, 0), WHITE, radius * 1.2, 0.12)
		FxKit.column(center, HOT:Lerp(WHITE, 0.4), height, radius * 0.9, 0.7)
		Kit.shell(run, 0, 0.5, HOT, center + Vector3.new(0, 1, 0), function(u)
			return radius * 2.3 * Kit.easeOut(u)
		end, function(u)
			return 0.3 + 0.7 * u
		end)
		FxKit.ring(center, HOT, radius * 2.6, 0.45)
		FxKit.ring(center, WHITE, radius * 2, 0.3)
		-- Steam rolling out across the area, thinning.
		for i = 1, (if run.reduced then 3 else 6) do
			run:at(0.08 * i, function()
				local angle = math.random() * 2 * math.pi
				local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
				ImpactEffects.burst("puff", center + out * radius * (0.4 + 0.12 * i) + Vector3.new(0, 0.8, 0), out, {
					color = WHITE:Lerp(HOT, 0.3),
					count = 6,
					size = 1.6,
					speed = { 4, 8 },
					lifetime = { 0.7, 1.1 },
					spread = 60,
					transparency = 0.4,
				})
			end)
		end
		for _, target in run:targets() do
			run:hitStop(target, 0.12)
		end
		run:shake(0.45)
		run:sound("whoosh", 0.5)
		return true
	elseif kind == "Damage" and event.target and not event.dot and not event.aura then
		local view = run.context.views[event.target]
		if view then
			ImpactEffects.burst("flame", view.part.Position, Vector3.yAxis, {
				color = HOT,
				color2 = EMBER,
				count = 6,
				size = 0.8,
				speed = { 3, 6 },
				lifetime = { 0.3, 0.5 },
				spread = 40,
			})
		end
		return true
	end
	return false -- aura ticks and the rest keep their own effects
end

return def
