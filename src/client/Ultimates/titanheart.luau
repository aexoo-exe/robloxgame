-- titanheart (Tier 3): lightning strike and steam reveal. His real cast is a heavy hit on his
-- target in either form; the shift into the titan is a real form change when his health drops
-- (not a cast), and back to human when the titan's pool breaks: both play as shifts.
-- Cast:
--   -0.40  he plants and draws back, steam venting from him
--    0     the real hit: a heavy blow, a burst of steam and a crack
-- Shift into the titan (the real form change):
--    0     his hand to his mouth (no blood); a bolt of yellow lightning strikes down on him, a huge
--          flash; a massive steam explosion the titan emerges from; a roar, steam venting, a shake
-- Shift back to human:
--    0     a steam burst; the giant collapses into steam and he stumbles out
-- Layers: the shared recipe (VfxRecipe: the steam theme, and a lightning theme in yellow for the
-- bolt; tier 3).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local BOLT = Color3.fromRGB(255, 230, 90)
local STEAM = Color3.fromRGB(245, 240, 232)
local STEAM_THEME = VfxRecipe.themes.steam
local BOLT_THEME = VfxRecipe.lightning(BOLT, WHITE)

local def = {}

def.shiftLinger = 1.2

def.pose = {
	rightArm = { { -0.4, 0 }, { -0.2, -40 }, { -0.02, -45 }, { 0.03, 95, "snap" }, { 0.35, 80 }, { 0.6, 0 } },
	leftArm = { { -0.4, 0 }, { -0.2, 40 }, { 0.03, 10, "snap" }, { 0.6, 0 } },
	twist = { { -0.4, 0 }, { -0.2, -25 }, { 0.03, 25, "snap" }, { 0.35, 10 }, { 0.6, 0 } },
	lean = { { -0.4, 0 }, { -0.2, -6 }, { 0.03, 14, "snap" }, { 0.35, 5 }, { 0.6, 0 } },
	crouch = { { -0.4, 0 }, { -0.2, 0.15 }, { 0.03, 0.05, "snap" }, { 0.5, 0 } },
}

local ROAR = {
	rightArm = { { 0, 150 }, { 0.15, 150 }, { 0.5, 30 }, { 0.9, 0 } },
	leftArm = { { 0, 0 }, { 0.5, 30 }, { 0.9, 0 } },
	leftArmOut = { { 0.3, 0 }, { 0.5, 40 }, { 0.9, 0 } },
	rightArmOut = { { 0.3, 0 }, { 0.5, 40 }, { 0.9, 0 } },
	lean = { { 0, 0 }, { 0.3, -14, "back" }, { 0.8, -6 }, { 1.1, 0 } },
	tremble = { { 0.3, 0 }, { 0.35, 1.5 }, { 0.8, 1.5 }, { 0.85, 0, "hold" } },
}

local STUMBLE = {
	lean = { { 0, 0 }, { 0.2, 18, "out" }, { 0.45, -6 }, { 0.8, 0 } },
	crouch = { { 0, 0.2 }, { 0.3, 0.1 }, { 0.8, 0 } },
	leftArm = { { 0, 40 }, { 0.5, 20 }, { 0.8, 0 } },
}

-- Steam venting at `at`: pale puffs rising and spreading (the recipe's steam), `size` studs.
local function steamBurst(at: Vector3, count: number, size: number)
	VfxRecipe.smoke(at, size * 1.2, math.max(1, math.ceil(count / 2)), STEAM_THEME.smoke, STEAM_THEME.smokeTransparency)
end

def.beats = {
	{
		at = -0.4,
		run = function(run)
			run:face(run:target())
			for t = -0.38, -0.05, 0.11 do
				run:at(t, function()
					steamBurst(run:chest(), if run.reduced then 2 else 4, 0.7)
				end)
			end
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	if event.kind ~= "Damage" or not event.target or event.dot then
		return false
	end
	local view = run.context.views[event.target]
	if view then
		local floor = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
		-- The heavy blow: a steam hit (core, pale cloud, droplets, light), a steam column, the crack.
		VfxRecipe.hit(run, view.part.Position, 2.4 * run:scale(), STEAM_THEME, run:forward())
		VfxRecipe.steamColumn(floor, 1 * run:scale())
		steamBurst(floor + Vector3.new(0, 0.5, 0), 8, 1.2)
		FxKit.mark(floor, Kit.DUST, STEAM, 2.2 * run:scale(), "crack", 0.9)
		FxKit.ring(floor, STEAM, 6 * run:scale(), 0.35)
		run:hitStop(view, 0.1)
		run:shake(0.2)
	end
	return true
end

-- The real form change: into the titan (lightning and steam) or back (a collapse into steam).
function def.shift(run, event): boolean
	local ground = run:ground()
	if (event.formIndex or 1) >= 2 then
		run:pose(ROAR)
		local sky = ground + Vector3.new(0.6, 26, 0.4)
		-- The bolt: yellow lightning arcs striking down, a huge flash and light.
		VfxRecipe.arcs(run, sky, ground + Vector3.new(0, 1, 0), BOLT_THEME, 3, 1.4, 0.35)
		VfxRecipe.core(ground + Vector3.new(0, 3, 0), 6, 1, BOLT_THEME.core)
		VfxRecipe.light(run, ground + Vector3.new(0, 3, 0), 6, BOLT, 1.3)
		-- The massive steam explosion the titan emerges from, then rolling, rising steam.
		VfxRecipe.burst(run, ground, 4.5 * run:scale(), { theme = STEAM_THEME, big = true })
		VfxRecipe.aftermath(run, ground, 4.5 * run:scale(), { theme = STEAM_THEME })
		for i = 0, (if run.reduced then 2 else 4) do
			run:at(0.08 + i * 0.12, function()
				steamBurst(ground + Vector3.new(0, 1 + i, 0), 10, 2.4)
			end)
		end
		FxKit.ring(ground, BOLT, 10, 0.4)
		FxKit.ring(ground, STEAM, 14, 0.6, 0.15)
		run:sound("whoosh", 0.5)
	else
		run:pose(STUMBLE)
		-- The giant collapses into steam.
		VfxRecipe.burst(run, ground, 3.5 * run:scale(), { theme = STEAM_THEME })
		steamBurst(run:chest(), 16, 2.2)
		FxKit.ring(ground, STEAM, 10, 0.5)
		run:sound("whoosh", 0.8)
	end
	return true
end

return def
