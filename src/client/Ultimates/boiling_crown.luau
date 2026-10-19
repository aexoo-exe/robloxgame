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
-- Layers at the eruption: the shared recipe (VfxRecipe, steam theme: white -> pale gray clouds,
-- droplets, rising steam columns and bubbling; tier 5: the biggest, most side blasts, the longest
-- aftermath). Nothing at the eruption is fire.
-- Batch 2 kit: the chest glow is a warm red-orange particle aura over his body (no neon parts);
-- the eruption throws 8-12 large steam billows (fx_steam_billow) out in a ring from his body, orange
-- embers rise, a brief speed-lines flash (fx_speed_lines) marks the peak, a shock ring
-- (mesh_shock_ring) runs out. The scorched ground is the crack mark only (no flat disc).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local HOT = Color3.fromRGB(255, 140, 60)
local EMBER = Color3.fromRGB(255, 80, 40)

local def = {}

def.pose = {
	crouch = { { -1.05, 0 }, { -0.6, 0.25 }, { -0.15, 0.32 }, { 0, 0, "snap" }, { 0.5, 0.05 }, { 1.2, 0 } },
	lean = { { -1.05, 0 }, { -0.6, 3 }, { -0.15, 5 }, { 0, -10, "snap" }, { 0.5, -4 }, { 1.2, 0 } },
	tremble = { { -0.6, 0 }, { -0.3, 1 }, { -0.16, 2 }, { -0.15, 0, "hold" }, { 0.05, 1.2 }, { 0.5, 0 } },
	rise = { { -0.02, 0 }, { 0.06, 0.6, "snap" }, { 0.55, 0 } },
}

def.beats = {
	{
		at = -1.05,
		run = function(run)
			run:camera(-1.05, 0.5, { key = "dim", dim = 0.25, rise = 0.4, fall = 0.4 })
			-- His steam thickens and heats from white to orange (a puff every 0.15 s: budget).
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
				t += 0.15
			end
			run:sound("charge", 0.4)
		end,
	},
	{
		-- The chest glow and the ground going black and cracking.
		at = -0.6,
		run = function(run)
			-- The glow building in him: a warm red-orange aura over his whole body, stronger near the end.
			local warm = VfxRecipe.energy(EMBER, HOT)
			VfxRecipe.aura(run, run.view, warm, 1.2, -0.6, 0.35)
			VfxRecipe.aura(run, run.view, warm, 1.8, -0.25, 0.3)
			local center, radius = run:area()
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
		local theme = VfxRecipe.themes.steam
		-- The eruption over the real area (core, steam cloud and side clouds, all capped at 1.5 unit
		-- heights: an area-wide cloud centered on him read as a see-through dome; the flat shock
		-- ring, sparks, light), then pale steam rolling out for the longest (tier 5) aftermath.
		VfxRecipe.burst(run, center, radius, { theme = theme })
		VfxRecipe.aftermath(run, center, radius, { theme = theme })
		-- The eruption: large steam billows thrown out in a ring from his body, a column of them
		-- rising, orange embers, a brief speed-lines flash at the peak (about his size, not the
		-- screen). The burst's ring is the only ring (budget).
		local body = run.view.part.Position
		local billows = if run.reduced then 6 else 9
		for i = 1, billows do
			local angle = (i / billows) * math.pi * 2 + math.random() * 0.3
			local out = Vector3.new(math.cos(angle), 0.25, math.sin(angle)).Unit
			VfxRecipe.kitSteam(body + out * 0.8, height * 0.55, 1, out, radius * 2.2, 8)
		end
		VfxRecipe.kitSteam(body + Vector3.new(0, height * 0.3, 0), height * 0.6, 2, Vector3.yAxis, height * 1.2, 15)
		VfxRecipe.embers(run, center + Vector3.new(0, 1, 0), run:scale() * 1.4, VfxRecipe.energy(EMBER, HOT).ember, 22)
		VfxRecipe.kitSpeedLines(run:chest(), run.view.part.Size.Y * 1.5, HOT, 0.2)
		if not run.reduced then
			-- A second wave of steam further out, rolling across the area.
			run:at(0.4, function()
				VfxRecipe.smoke(center, radius * 1.4, 4, theme.smoke, theme.smokeTransparency)
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
			-- Steam scalding up around each unit caught in it.
			VfxRecipe.steamColumn(view.part.Position - Vector3.new(0, view.part.Size.Y * 0.5, 0), 0.9 * run:scale())
		end
		return true
	end
	return false -- aura ticks and the rest keep their own effects
end

return def
