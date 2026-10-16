-- iron_rush (Tier 1): the unstoppable armored charge. The real cast hardens his armor, charges his
-- target, hits and stuns it and shoves it back a hex, at the Cast event. He is a store model (no
-- limbs): the shoulder-down charge is his whole body.
--   -0.20  his plates flash gold as the armor hardens; steam vents
--   -0.10  he lowers his shoulder and stomps in (dust)
--    0     the ram on the real hit: a big impact, the enemy shoved back on the real knockback with a
--          scrape on the ground; the stun stars are the real ones

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

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
			ImpactEffects.burst("puff", run:chest() + Vector3.new(0, run.view.part.Size.Y * 0.3, 0), Vector3.yAxis, {
				color = STEAM,
				count = 6,
				size = 0.8,
				speed = { 2, 4 },
				lifetime = { 0.4, 0.6 },
				spread = 50,
				transparency = 0.4,
			})
		end,
	},
	{
		at = -0.1,
		run = function(run)
			ImpactEffects.burst("puff", run:ground() + Vector3.new(0, 0.2, 0), nil, {
				color = DUST,
				count = 6,
				size = 0.7,
				speed = { 2, 4 },
				lifetime = { 0.3, 0.5 },
				transparency = 0.35,
			})
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
			ImpactEffects.ball(view.part.Position, GOLD, 2.2, 0.1)
			FxKit.ring(view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0), DUST, 4.5, 0.3)
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
