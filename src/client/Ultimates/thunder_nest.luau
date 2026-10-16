-- thunder_nest (Tier 3): godspeed. The real cast dashes him next to the highest-AD enemy, then hits
-- and stuns everything within 1 hex of where he lands, all at the Cast event.
--   -0.40  his hair and body crackle blue-white; he drops low, a claw hand ready
--    0     a zig-zag of blue lightning from where he stood to where he lands (no run), and a dome
--          of lightning snapping out 1 hex around him on the real hit
--   +0.10  the stunned enemies twitch with arcs
--   +0.50  he stands, lightning dying along his arms

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE

local def = {}

def.pose = {
	crouch = { { -0.4, 0 }, { -0.2, 0.26 }, { -0.02, 0.28 }, { 0.05, 0.3, "snap" }, { 0.5, 0.2 }, { 0.8, 0 } },
	lean = { { -0.4, 0 }, { -0.2, 16 }, { 0.05, 20, "snap" }, { 0.5, 10 }, { 0.8, 0 } },
	rightArm = { { -0.4, 0 }, { -0.2, 60 }, { 0.05, 100, "snap" }, { 0.5, 50 }, { 0.8, 0 } },
	rightArmOut = { { -0.4, 0 }, { -0.2, 25 }, { 0.05, 35 }, { 0.8, 0 } },
	leftArm = { { -0.4, 0 }, { -0.2, -30 }, { 0.5, -20 }, { 0.8, 0 } },
	tremble = { { -0.35, 0 }, { -0.25, 0.8 }, { -0.02, 0.8 }, { 0, 0, "hold" } },
}

local function crackle(run, at: Vector3, size: number)
	local to = at + Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5) * size
	Kit.zap(at, to, WHITE:Lerp(run.style.primary, 0.5), 0.1, 0.1, 2)
end

def.beats = {
	{
		at = -0.4,
		run = function(run)
			run:face(run:target())
			for i = 0, (if run.reduced then 2 else 5) do
				run:at(-0.38 + i * 0.06, function()
					crackle(run, run:head(), 1.6)
				end)
			end
			run:sound("tick", 1.6)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	local blue = run.style.primary
	if kind == "Dash" then
		-- The zig-zag path: where he stood to where he lands, in three kinks.
		local from = run:chest()
		local to = run.context.toWorld(event.column, event.row) + Vector3.new(0, run.view.part.Size.Y * 0.6, 0)
		local side = Vector3.new(-(to - from).Z, 0, (to - from).X)
		side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
		local points = { from, from:Lerp(to, 0.33) + side * 1.2, from:Lerp(to, 0.66) - side * 1.2, to }
		for i = 1, 3 do
			Kit.zap(points[i], points[i + 1], WHITE:Lerp(blue, 0.3), 0.35, 0.3, 1)
			Kit.zap(points[i], points[i + 1], blue, 0.8, 0.2, 1)
		end
		ImpactEffects.ball(from, WHITE, 1.4, 0.1)
		run:sound("whoosh", 1.9)
		return true
	elseif kind == "Area" or kind == "AreaStun" then
		if run.memo.dome then
			return true
		end
		run.memo.dome = true
		local center, radius = run:area()
		local air = center + Vector3.new(0, 1, 0)
		Kit.shell(run, 0, 0.3, blue, air, function(u)
			return radius * 2 * Kit.easeOut(u)
		end, function(u)
			return 0.3 + 0.7 * u
		end)
		for i = 1, (if run.reduced then 3 else 6) do
			local angle = i / 6 * 2 * math.pi
			Kit.zap(
				air,
				center + Vector3.new(math.cos(angle) * radius, 0.4, math.sin(angle) * radius),
				WHITE,
				0.2,
				0.2,
				2
			)
		end
		FxKit.ring(center, blue, radius * 2.3, 0.3)
		run:shake(0.18)
		return true
	elseif kind == "Stun" and event.target then
		-- The stunned twitch with arcs for a moment.
		local view = run.context.views[event.target]
		if view then
			for i = 1, 3 do
				run:at(0.1 + i * 0.12, function()
					if view.part.Parent then
						crackle(run, view.part.Position, 1.4)
					end
				end)
			end
		end
		return false
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

-- Lightning dying along his arms as he stands.
def.beats[2] = {
	at = 0.5,
	run = function(run)
		ImpactEffects.burst("spark", run:hand("right"), nil, {
			color = run.style.primary,
			count = 6,
			size = 0.18,
			speed = { 2, 4 },
			lifetime = { 0.2, 0.4 },
		})
	end,
}

return def
