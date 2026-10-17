-- thunder_nest (Tier 3): godspeed. The real cast dashes him next to the highest-AD enemy, then hits
-- and stuns everything within 1 hex of where he lands, all at the Cast event.
--   -0.40  his hair and body crackle blue-white; he drops low, a claw hand ready
--    0     a zig-zag of blue lightning from where he stood to where he lands (no run), and a dome
--          of lightning snapping out 1 hex around him on the real hit
--   +0.10  the stunned enemies twitch with arcs
--   +0.50  he stands, lightning dying along his arms
-- Layers: the shared recipe (VfxRecipe, a lightning theme in his blue, tier 3).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

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

-- His lightning: blue arcs with a white-hot core.
local function theme(run)
	run.memo.theme = run.memo.theme or VfxRecipe.lightning(run.style.primary, WHITE:Lerp(run.style.primary, 0.4))
	return run.memo.theme
end

local function crackle(run, at: Vector3, size: number)
	VfxRecipe.crackle(run, at, size, theme(run), 2)
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
			VfxRecipe.arcs(run, points[i], points[i + 1], theme(run), 2, 1.1 * run:scale(), 0.35)
		end
		-- Bolts crackling over his body through the dash.
		local now = run:designTime()
		for i = 0, (if run.reduced then 2 else 5) do
			run:at(now + i * 0.05, function()
				crackle(run, run:chest(), 2.2 * run:scale())
			end)
		end
		VfxRecipe.pop(run, from, 1.4 * run:scale(), theme(run))
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
		-- The dome snapping out (above), then the recipe's lightning burst: core, glow sheet, arcs to
		-- the edge of the area, shockwave, sparks, light, scorch; crackling residue.
		VfxRecipe.burst(run, center, radius, { theme = theme(run) })
		VfxRecipe.aftermath(run, center, radius, { theme = theme(run) })
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
		crackle(run, run:hand("right"), 1.2)
	end,
}

return def
