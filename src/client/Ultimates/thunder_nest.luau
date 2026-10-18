-- thunder_nest (Tier 3): godspeed. The real cast dashes him next to the highest-AD enemy, then hits
-- and stuns everything within 1 hex of where he lands, all at the Cast event.
--   -0.40  his hair and body crackle blue-white; he drops low, a claw hand ready
--    0     a zig-zag of blue lightning from where he stood to where he lands (no run), and a dome
--          of lightning snapping out 1 hex around him on the real hit
--   +0.10  the stunned enemies twitch with arcs
--   +0.50  he stands, lightning dying along his arms
-- Layers: the shared recipe (VfxRecipe, a lightning theme in his blue, tier 3) and the batch 2 kit:
-- a cyan crackle aura crawling over his whole body for the whole ultimate (fx_crackle), cyan
-- lightning bolts for the zig-zag and on each stunned enemy (fx_lightning), a small shock ring
-- (mesh_shock_ring) on the final hit.

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local CYAN = Color3.fromRGB(80, 225, 255)

local function cyan(run): Color3
	return run.style.primary:Lerp(CYAN, 0.6)
end

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
	VfxRecipe.crackle(run, at, size, theme(run), 1)
end

def.beats = {
	{
		at = -0.4,
		run = function(run)
			run:face(run:target())
			-- The crackle aura over his whole body, from the crouch to standing again.
			VfxRecipe.kitCrackleAura(run, run.view, cyan(run), -0.4, 1.3, 2)
			run:sound("tick", 1.6)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Dash" then
		-- The zig-zag path: where he stood to where he lands, in three kinks.
		local from = run:chest()
		local to = run.context.toWorld(event.column, event.row) + Vector3.new(0, run.view.part.Size.Y * 0.6, 0)
		local side = Vector3.new(-(to - from).Z, 0, (to - from).X)
		side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
		local points = { from, from:Lerp(to, 0.33) + side * 1.2, from:Lerp(to, 0.66) - side * 1.2, to }
		for i = 1, 3 do
			VfxRecipe.kitBolts(points[i], points[i + 1], cyan(run), if run.reduced then 1 else 2, 0.3)
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
		-- The recipe's lightning burst (core, glow sheet, arcs to the edge of the area, shockwave,
		-- sparks, light, scorch; crackling residue), and the shock ring snapping out on the hit.
		VfxRecipe.burst(run, center, radius, { theme = theme(run) })
		VfxRecipe.aftermath(run, center, radius, { theme = theme(run) })
		VfxRecipe.meshRing(center, radius * 0.9, cyan(run), 0.35)
		return true
	elseif kind == "Stun" and event.target then
		-- Each strike: a cyan bolt down onto the stunned enemy, then it twitches with crackle.
		local view = run.context.views[event.target]
		if view then
			local at = view.part.Position
			VfxRecipe.kitBolts(at + Vector3.new(0.4, view.part.Size.Y * 1.4, 0.3), at, cyan(run), 1, 0.25)
			run:at(0.1, function()
				if view.part.Parent then
					crackle(run, view.part.Position, 1.4)
				end
			end)
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
