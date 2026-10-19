-- skyboulder (Tier 3): the pitcher's wind-up and the rock spray. The real cast hits a cone toward
-- his target (hardest next to him) and hardens his armor, at the Cast event. He is a store model
-- (no limbs to pose): the wind-up is his whole body turning away and back.
--   -0.50  a boulder appears at his side and he crushes it: dust, the rock breaks into fragments
--   -0.30  the wind-up: he turns far away, leans back, sinks
--   -0.06  the throw: he whips around and lunges
--    0     on the real hit a spray of fragments across the cone's real cells, the nearest ones the
--          biggest, dust bursting where they land
--   +0.30  he stands tall; his armor glows
-- Layers: the shared recipe (VfxRecipe dust and debris, tier 3) and the batch 2 kit: dust bursts
-- (fx_dust_burst, 1-2 billows each, turned and sized 0.8-1.3x so they never stack into the same
-- shape) where he crushes the boulder and at each rock's impact, debris, and one shock ring
-- (mesh_shock_ring) on the nearest impact.

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local STONE = Color3.fromRGB(140, 126, 110)
local DUST = Kit.DUST

local def = {}

def.pose = {
	twist = { { -0.5, 0 }, { -0.3, -10 }, { -0.08, -48 }, { 0, 40, "snap" }, { 0.3, 15 }, { 0.6, 0 } },
	lean = { { -0.5, 0 }, { -0.3, 4 }, { -0.08, -12 }, { 0, 16, "snap" }, { 0.3, 4 }, { 0.6, -4 }, { 0.9, 0 } },
	crouch = { { -0.5, 0 }, { -0.3, 0.1 }, { -0.08, 0.22 }, { 0, 0.05, "snap" }, { 0.5, 0 } },
	lunge = { { -0.02, 0 }, { 0.05, 0.4, "snap" }, { 0.45, 0 } },
}

-- Beside him, at his throwing side.
local function side(run): Vector3
	local forward = run:forward()
	return run:chest() + Vector3.new(-forward.Z, 0, forward.X) * run.view.part.Size.X * 0.7
end

def.beats = {
	{
		at = -0.5,
		run = function(run)
			run:face(run:target())
			-- The boulder, crushed.
			Kit.block(run, -0.5, -0.28, STONE, function(u)
				return CFrame.new(side(run)) * CFrame.Angles(u, u * 2, 0)
			end, function(u)
				return Vector3.one * 1.6 * (1 - 0.6 * Kit.easeIn(u)) * run:scale()
			end, function(u)
				return if u > 0.85 then (u - 0.85) * 6 else 0
			end, Enum.Material.Slate)
			run:at(-0.3, function()
				-- The boulder crushed: dust bursting off it, chips flying.
				local s = run:scale()
				VfxRecipe.kitDust(side(run) - Vector3.new(0, run.view.part.Size.Y * 0.5, 0), 2.6 * s, 2)
				VfxRecipe.debris(
					side(run) - Vector3.new(0, 0.5, 0),
					if run.reduced then 2 else 3,
					0.3 * s,
					DUST:Lerp(STONE, 0.6),
					1.5
				)
				run:sound("tick", 0.6)
			end)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" and event.cells then
		local from = side(run)
		local origin = run:ground()
		-- The nearest cell takes the one shock ring and the debris (budget: a ring and 3-4 billows on
		-- every cell was ~40 live layers).
		local nearest, nearestDistance = nil, math.huge
		for _, cell in event.cells do
			local d = (run.context.toWorld(cell[1], cell[2]) - origin).Magnitude
			if d < nearestDistance then
				nearest, nearestDistance = cell, d
			end
		end
		for _, cell in event.cells do
			local at = run.context.toWorld(cell[1], cell[2])
			local near = math.clamp(1 - (at - origin).Magnitude / 12, 0.3, 1)
			local first = cell == nearest
			for k = 1, (if run.reduced or not first then 1 else 2) do
				local offset = Vector3.new((math.random() - 0.5) * 1.6, 0, (math.random() - 0.5) * 1.6)
				local spin = math.random() * 5
				Kit.block(run, 0, 0.22, STONE, function(u)
					local p = from:Lerp(at + offset + Vector3.new(0, 0.4, 0), u)
						+ Vector3.new(0, math.sin(u * math.pi) * 1.2, 0)
					return CFrame.new(p) * CFrame.Angles(spin * u, spin, 0)
				end, function()
					return Vector3.one * (0.35 + 0.6 * near) * (if k == 1 then 1 else 0.7) * run:scale()
				end, function()
					return 0
				end, Enum.Material.Slate)
			end
			run:at(0.2, function()
				-- Each rock's impact: a dust burst (1 billow, 2 on the nearest, bigger nearer him); the
				-- nearest cell also the shock ring and chips thrown up; near cells a flash and sparks.
				local impact = VfxRecipe.impact()
				VfxRecipe.kitDust(at, (1.6 + 1.6 * near) * run:scale(), if first and not run.reduced then 2 else 1)
				if first then
					VfxRecipe.meshRing(at, (1.4 + 1.4 * near) * run:scale(), impact.edge, 0.3)
					if not run.reduced then
						VfxRecipe.debris(at, 2, 0.25 * run:scale(), impact.debris, 1.4)
					end
				end
				if near > 0.6 then
					VfxRecipe.core(at + Vector3.new(0, 0.8, 0), 1.6 * near, 1, impact.core)
					VfxRecipe.sparks(at + Vector3.new(0, 0.5, 0), 0.6 * near, 18, impact.spark)
				end
			end)
		end
		run:shake(0.18)
		run:sound("whoosh", 1.1)
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		-- His armor hardening: a short earthen glow.
		local glow = run.style.secondary
		-- An earthen aura flaring off him (no see-through shell).
		VfxRecipe.aura(run, run.view, VfxRecipe.energy(glow), 0.9, 0.3, 0.4)
		run:at(0.3, function()
			FxKit.ring(run:ground(), glow, 5, 0.35)
		end)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
