-- skyboulder (Tier 3): the pitcher's wind-up and the rock spray. The real cast hits a cone toward
-- his target (hardest next to him) and hardens his armor, at the Cast event. He is a store model
-- (no limbs to pose): the wind-up is his whole body turning away and back.
--   -0.50  a boulder appears at his side and he crushes it: dust, the rock breaks into fragments
--   -0.30  the wind-up: he turns far away, leans back, sinks
--   -0.06  the throw: he whips around and lunges
--    0     on the real hit a spray of fragments across the cone's real cells, the nearest ones the
--          biggest, dust bursting where they land
--   +0.30  he stands tall; his armor glows

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

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
				ImpactEffects.burst("puff", side(run), nil, {
					color = DUST,
					count = 8,
					size = 0.9,
					speed = { 2, 5 },
					lifetime = { 0.3, 0.6 },
					transparency = 0.35,
				})
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
		for _, cell in event.cells do
			local at = run.context.toWorld(cell[1], cell[2])
			local near = math.clamp(1 - (at - origin).Magnitude / 12, 0.3, 1)
			for k = 1, (if run.reduced then 1 else 2) do
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
				ImpactEffects.burst("puff", at + Vector3.new(0, 0.4, 0), nil, {
					color = DUST,
					count = math.floor(4 + 6 * near),
					size = 0.6 + 0.8 * near,
					speed = { 2, 5 },
					lifetime = { 0.35, 0.7 },
					transparency = 0.35,
				})
			end)
		end
		run:shake(0.18)
		run:sound("whoosh", 1.1)
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		-- His armor hardening: a short earthen glow.
		local glow = run.style.secondary
		run:at(0.3, function()
			Kit.shell(run, 0.3, 0.7, glow, run.view.part.Position, function(u)
				return run.view.part.Size.Y * (1.1 + 0.15 * u)
			end, function(u)
				return 0.7 + 0.3 * u
			end)
			FxKit.ring(run:ground(), glow, 5, 0.35)
		end)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
