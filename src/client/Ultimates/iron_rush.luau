-- iron_rush (Tier 1): the unstoppable armored charge. The real cast hardens his armor, charges his
-- target, hits and stuns it and shoves it back a hex, at the Cast event. He is a store model (no
-- limbs): the shoulder-down charge is his whole body.
--   -0.20  his plates flash gold as the armor hardens; steam vents
--   -0.10  he lowers his shoulder and stomps in (dust)
--    0     the ram on the real hit: a big impact, the enemy shoved back on the real knockback with a
--          scrape on the ground; the stun stars are the real ones
-- Layers: the shared recipe (VfxRecipe steam, dust and an impact theme in gold, tier 1) and the
-- batch 2 kit: steam billows (fx_steam_billow) trailing the charge; on the impact a dust burst
-- (fx_dust_burst), debris and the burst's flat shock ring. The gold sparks stay.
-- Budget (tier 1: 14 live layers): one dust burst for the stomp, two steam billows on the rush, and
-- at the ram the recipe burst (its dust cloud, debris and ring) with two dust bursts; no aftermath
-- (its rolling dust and puffs doubled the dust bursts), no second ring, steam column or debris.

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local GOLD = Color3.fromRGB(240, 200, 110)
local STEAM = Color3.fromRGB(240, 238, 232)

local def = {}

-- His impact theme in gold: the recipe's impact (dust cloud, debris) with gold sparks, embers and
-- shock ring (the plain impact theme's tan dust and pale sparks vanish on a gray floor).
local function goldImpact()
	local theme = VfxRecipe.impact(GOLD)
	theme.spark = VfxRecipe.colors({ { 0, Color3.new(1, 1, 1) }, { 0.3, GOLD }, { 1, Color3.fromRGB(230, 120, 40) } })
	theme.ember =
		VfxRecipe.colors({ { 0, Color3.fromRGB(255, 235, 170) }, { 0.5, GOLD }, { 1, Color3.fromRGB(200, 110, 40) } })
	theme.edge = GOLD
	theme.edgeBig = GOLD
	return theme
end

def.pose = {
	lean = { { -0.2, 0 }, { -0.1, 22 }, { 0.02, 26, "snap" }, { 0.3, 6 }, { 0.45, 0 } },
	twist = { { -0.2, 0 }, { -0.1, -20 }, { 0.02, -24 }, { 0.45, 0 } },
	crouch = { { -0.2, 0 }, { -0.1, 0.15 }, { 0.3, 0.05 }, { 0.45, 0 } },
	lunge = { { 0, 0 }, { 0.04, 0.4, "snap" }, { 0.4, 0 } },
}

def.beats = {
	{
		at = -0.2,
		run = function(run)
			run:face(run:target())
			-- The armor hardening: a gold aura flaring off the plates (no see-through shell).
			VfxRecipe.aura(run, run.view, VfxRecipe.energy(GOLD), 1.6, -0.2, 0.45)
			-- Steam venting off the plates.
			VfxRecipe.steamColumn(
				run:chest() + Vector3.new(0, run.view.part.Size.Y * 0.2, 0),
				0.6 * run:scale(),
				VfxRecipe.colors({ { 0, STEAM }, { 1, STEAM:Lerp(Color3.fromRGB(160, 160, 165), 0.6) } })
			)
		end,
	},
	{
		at = -0.1,
		run = function(run)
			-- The stomp: one dust burst at his feet, then the charge's trail of grinding sparks racing
			-- to the target.
			local height = run.view.part.Size.Y
			VfxRecipe.kitDust(run:ground(), height * 0.6, 1)
			local target = run:target()
			if target then
				local from = run:ground()
				local to = target.part.Position - Vector3.new(0, target.part.Size.Y / 2, 0)
				VfxRecipe.trail(run, from, to, {
					theme = goldImpact(),
					steps = if run.reduced then 3 else 5,
					from = -0.1,
					span = 0.1,
					size = 2 * run:scale(),
				})
				-- Steam billowing off him along the rush (fx_steam_billow).
				for i = 1, if run.reduced then 1 else 2 do
					run:at(-0.1 + 0.04 * i, function()
						local at = from:Lerp(to, i / 3)
						VfxRecipe.kitSteam(
							at + Vector3.new(0, height * 0.55, 0),
							height * 0.6,
							1,
							Vector3.yAxis,
							2.5,
							30
						)
					end)
				end
			end
			run:sound("tick", 0.5)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view and not run.memo.ram then
			run.memo.ram = true
			-- The ram: the recipe's gold impact burst at the target (core, dust cloud, the flat gold
			-- shock ring, sparks, stone debris, light), sparks along the charge, and dust bursting up
			-- (fx_dust_burst). The steam off the plates is the column from the armor beat.
			local floor = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
			local impact = goldImpact()
			VfxRecipe.burst(run, floor, 1.5 * run:scale(), { theme = impact })
			VfxRecipe.sparks(view.part.Position, 0.6, 20, impact.spark, run:forward())
			VfxRecipe.kitDust(floor, 3 * run:scale(), if run.reduced then 1 else 2)
			run:hitStop(view, 0.09)
			run:shake(0.12)
			run:sound("whoosh", 0.6)
		end
		return true
	elseif kind == "Knockback" and event.target then
		-- The shove: a scrape from where it stood to its new cell.
		local view = run.context.views[event.target]
		if view then
			local from = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
			Kit.groove(run, 0, 0.6, Color3.fromRGB(80, 70, 60), from, run.context.toWorld(event.column, event.row), 0.5)
		end
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		return true -- the gold flash was the armor
	end
	return false
end

return def
