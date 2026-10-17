-- starless_burst (Tier 4): precise, clean, overwhelming magic, white and pale blue (never fiery).
-- The real cast fires a line from her through her target and 3 hexes past it, 25% stronger for
-- every earlier cast this fight, and shields her, at the Cast event.
--   -0.85  the staff rises, calm; a white and pale-blue magic circle opens in front of her, one
--          glyph ring after another (more rings for each earlier cast)
--   -0.55  light gathers at the circle's center
--   -0.15  stillness
--    0     a clean white-blue beam fires straight through the real line; a bright line on the
--          ground, small impacts along it, glyph sparks; a hexagonal barrier flickers around her
--   +0.40  she lowers the staff, expressionless
-- Layers at the beam: the shared recipe (VfxRecipe, an energy theme in white and pale blue, tier 4;
-- never fiery).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local ALONG = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's axis (X) along a CFrame's look

local def = {}

def.pose = {
	rightArm = { { -0.85, 0 }, { -0.6, 110, "out" }, { -0.02, 112 }, { 0.03, 100, "snap" }, { 0.45, 100 }, { 0.85, 0 } },
	rightArmOut = { { -0.85, 0 }, { -0.6, 8 }, { 0.85, 0 } },
	leftArm = { { -0.85, 0 }, { -0.6, 40 }, { -0.02, 42 }, { 0.03, 60, "snap" }, { 0.45, 30 }, { 0.85, 0 } },
	lean = { { -0.85, 0 }, { -0.6, -2 }, { 0.03, 3, "snap" }, { 0.45, 0 } },
}

-- How many times she cast before this one in the fight (more rings each time).
local function earlierCasts(run): number
	local count = 0
	local events = run.context.events
	for i = 1, (run.castIndex or 1) - 1 do
		local event = events[i]
		if event.kind == "Cast" and event.unit == run.unitIndex then
			count += 1
		end
	end
	return count
end

-- The circle's frame: in front of her chest, facing her target.
local function circleFrame(run): CFrame
	local target = run:target()
	local chest = run:chest()
	local aim = if target then target.part.Position else chest + run:forward() * 10
	aim = Vector3.new(aim.X, chest.Y, aim.Z)
	local at = chest + (aim - chest).Unit * 1.8
	return CFrame.lookAt(at, aim)
end

def.beats = {
	{
		at = -0.85,
		run = function(run)
			run:face(run:target())
			local rings = math.min(2 + earlierCasts(run), 5)
			run.memo.rings = rings
			local pale = run.style.secondary
			for i = 1, rings do
				local open = -0.75 + (i - 1) * 0.08
				local diameter = (1.4 + i * 0.7) * run:scale()
				local spin = (if i % 2 == 0 then -1 else 1) * (2 + i * 0.4)
				-- A ring: a bright thin disc behind a slightly smaller dark-clear one.
				Kit.live(run, open, 0.45, "Cylinder", if i % 2 == 0 then pale else WHITE, function(part, u)
					local d = diameter * Kit.easeOut(math.min(1, u * 5))
					part.Size = Vector3.new(0.04, d, d)
					part.CFrame = circleFrame(run) * CFrame.new(0, 0, -i * 0.05) * ALONG
					part.Transparency = if u > 0.85 then 0.55 + (u - 0.85) * 3 else 0.55
				end)
				if not run.reduced then
					for g = 1, 3 do
						-- Glyphs riding the ring.
						Kit.block(run, open, 0.45, WHITE, function()
							local angle = run:now() * spin + g * 2.09
							local r = diameter / 2
							return circleFrame(run)
								* CFrame.new(math.cos(angle) * r, math.sin(angle) * r, -i * 0.05 - 0.02)
								* CFrame.Angles(0, 0, angle)
						end, function()
							return Vector3.new(0.22, 0.08, 0.04)
						end, function(u)
							return if u > 0.85 then (u - 0.85) * 6 else 0.1
						end)
					end
				end
			end
			run:sound("chime", 1.2)
		end,
	},
	{
		at = -0.55,
		run = function(run)
			Kit.orb(run, -0.55, 0.05, WHITE, function()
				return circleFrame(run).Position
			end, function(u)
				return (0.2 + 0.7 * Kit.easeIn(u)) * run:scale()
			end)
			Kit.converge(run, -0.55, -0.1, function()
				return circleFrame(run).Position
			end, run.style.secondary, 2, if run.reduced then 5 else 10)
			run:camera(
				-0.45,
				0,
				{ key = "push", push = 1.8, focus = circleFrame(run).Position, rise = 0.3, fall = 0.06 }
			)
			run:camera(0, 0.4, { key = "pull", push = -1.4, focus = run:chest(), rise = 0.04, fall = 0.3 })
		end,
	},
}

function def.release(_run): boolean
	return true -- the beam is the release
end

function def.event(run, event): boolean
	local kind = event.kind
	local pale = run.style.secondary
	-- Her magic: white and pale blue glow sheets and sparks (never fiery).
	local magic = VfxRecipe.energy(pale, WHITE)
	if kind == "Area" and event.shape == "LINE" and event.cells then
		local start = circleFrame(run).Position
		local far, distance = start, -1
		for _, cell in event.cells do
			local at = run.context.toWorld(cell[1], cell[2])
			local d = (at - start).Magnitude
			if d > distance then
				far, distance = at, d
			end
		end
		local finish = Vector3.new(far.X, start.Y, far.Z) + (Vector3.new(far.X, start.Y, far.Z) - start).Unit * 1.7
		Kit.beam(run, 0, 0.45, WHITE, pale, function()
			return start
		end, function()
			return finish
		end, function(u)
			return 0.45 * run:scale() * (1 - 0.9 * Kit.easeIn(u))
		end)
		Kit.groove(run, 0, 1.0, pale, run:ground(), Vector3.new(finish.X, run:ground().Y, finish.Z), 0.35)
		for i, cell in event.cells do
			local at = run.context.toWorld(cell[1], cell[2])
			run:at(0.025 * i, function()
				-- A clean impact on each cell: a small core, a pale glow sheet, sparks, a light.
				VfxRecipe.hit(run, at + Vector3.new(0, 1.4, 0), 1.9, magic)
			end)
		end
		-- Glyph sparks off the circle as it fires, and the circle's light.
		VfxRecipe.sparks(start, 0.6, 26, magic.spark)
		VfxRecipe.light(run, start, 3 * run:scale(), magic.light, 1)
		for _, target in run:targets() do
			run:hitStop(target, 0.07)
		end
		run:shake(0.22)
		run:sound("whoosh", 1.9)
		return true
	elseif kind == "Shield" and event.target == run.unitIndex then
		-- A hexagonal barrier flickering around her.
		local h = run.view.part.Size.Y
		for i = 0, 5 do
			local angle = i * math.pi / 3
			Kit.block(run, 0, 0.6, pale, function()
				local at = run.view.part.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * h * 0.55
				return CFrame.lookAt(at, run.view.part.Position)
			end, function()
				return Vector3.new(h * 0.62, h * 1.1, 0.05)
			end, function(u)
				local flicker = if math.floor(u * 14 + i) % 3 == 0 then 0.25 else 0
				return math.min(1, 0.7 + flicker + 0.3 * u)
			end, Enum.Material.Neon)
		end
		return false -- the shield bubble still shows
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the line's impacts cover each hit
	end
	return false
end

return def
