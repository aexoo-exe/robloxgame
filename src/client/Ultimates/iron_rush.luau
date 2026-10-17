-- iron_rush (Tier 1): the unstoppable armored charge. The real cast hardens his armor, charges his
-- target, hits and stuns it and shoves it back a hex, at the Cast event. He is a store model (no
-- limbs): the shoulder-down charge is his whole body.
--   -0.20  his plates flash gold as the armor hardens; steam vents
--   -0.10  he lowers his shoulder and stomps in (dust)
--    0     the ram on the real hit: a big impact, the enemy shoved back on the real knockback with a
--          scrape on the ground; the stun stars are the real ones
-- Layers: the shared recipe (VfxRecipe steam, dust and an impact theme in gold, tier 1).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local GOLD = Color3.fromRGB(240, 200, 110)
local STEAM = Color3.fromRGB(240, 238, 232)
local DUST = Kit.DUST

local def = {}

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
			Kit.shell(run, -0.2, -0.05, GOLD, run.view.part.Position, function(u)
				return run.view.part.Size.Y * (1 + 0.1 * u)
			end, function(u)
				return 0.6 + 0.4 * u
			end)
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
			-- The stomp: dust kicked up at his feet.
			VfxRecipe.dust(run:ground(), 1.2 * run:scale(), if run.reduced then 1 else 3)
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
			-- The ram: a gold impact (core, dust cloud, sparks along the charge, a light), dust and
			-- chips at the target's feet.
			local floor = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
			local impact = VfxRecipe.impact(GOLD)
			VfxRecipe.hit(run, view.part.Position, view.part.Size.Y, impact, run:forward())
			VfxRecipe.dust(floor, 1.4 * run:scale(), if run.reduced then 1 else 3)
			VfxRecipe.debris(floor, if run.reduced then 2 else 4, 0.25 * run:scale(), impact.debris, 1.2)
			FxKit.ring(floor, DUST, 4.5, 0.3)
			run:hitStop(view, 0.07)
			run:shake(0.08)
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
