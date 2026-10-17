-- clockbreaker (Tier 3): the barrage, from a spirit behind a calm user. The real cast hits his
-- target four times over 0.75 s and then once hard with a stun at 1 s (a 1-second cast time).
--   -0.40  hands in his coat pockets, cap brim down; a purple spirit fades in behind him
--   -0.15  the spirit lunges forward past his shoulder
--    0     the barrage: fist afterimages pour into the target, a small impact on each real hit
--   +1.00  the final punch on the real last hit: a big purple burst, hit-stop
--   +1.00  the spirit fades back; his hands never left his pockets
-- Layers: the shared recipe (VfxRecipe, an energy theme in his purple with impact dust, tier 3).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local WHITE = Kit.WHITE

local def = {}

-- Hands in the pockets the whole time; the brim goes down.
def.pose = {
	leftArm = { { -0.4, 0 }, { -0.3, -8 }, { 1.1, -8 }, { 1.3, 0 } },
	leftArmOut = { { -0.4, 0 }, { -0.3, 12 }, { 1.1, 12 }, { 1.3, 0 } },
	rightArm = { { -0.4, 0 }, { -0.3, -8 }, { 1.1, -8 }, { 1.3, 0 } },
	rightArmOut = { { -0.4, 0 }, { -0.3, 12 }, { 1.1, 12 }, { 1.3, 0 } },
	lean = { { -0.4, 0 }, { -0.3, 7 }, { 0.95, 7 }, { 1.0, 3, "snap" }, { 1.3, 0 } },
}

-- Where the spirit stands at design time `t`: behind him, then lunged out in front of him.
local function spiritFrame(run, t: number): CFrame
	local forward = run:forward()
	local back = run:ground() - forward * 1.2
	local front = run:ground() + forward * 1.3
	local at = back:Lerp(front, Kit.smooth((t + 0.15) / 0.15)):Lerp(back, Kit.smooth((t - 1.0) / 0.3))
	at += Vector3.new(0, run.view.part.Size.Y * 0.65, 0)
	return CFrame.lookAt(at, at + forward)
end

local function alpha(t: number): number
	return Kit.smooth((t + 0.4) / 0.2) * (1 - Kit.smooth((t - 1.05) / 0.25))
end

local function buildSpirit(run)
	local purple = run.style.primary
	local h = run.view.part.Size.Y * 1.2
	local parts = {
		{ CFrame.new(0, 0, 0), Vector3.new(h * 0.38, h * 0.4, h * 0.22), purple },
		{ CFrame.new(0, h * 0.31, 0), Vector3.one * h * 0.22, purple:Lerp(WHITE, 0.2) },
	}
	for _, piece in parts do
		Kit.block(run, -0.4, 1.3, piece[3], function()
			return spiritFrame(run, run:designTime()) * piece[1]
		end, function()
			return piece[2]
		end, function()
			return 1 - 0.55 * alpha(run:designTime())
		end, Enum.Material.Neon)
	end
	-- Two arms, punching in turn as fast as the eye allows.
	for side = -1, 1, 2 do
		Kit.block(run, -0.4, 1.3, purple, function()
			local t = run:designTime()
			local punch = if t >= 0 and t < 1.05 then math.abs(math.sin((t * 18) + (side + 1) * 0.8)) else 0
			return spiritFrame(run, t)
				* CFrame.new(side * h * 0.26, h * 0.05, -h * (0.05 + 0.45 * punch))
				* CFrame.Angles(math.rad(-90 * math.min(1, punch * 2)), 0, 0)
		end, function()
			return Vector3.new(h * 0.11, h * 0.34, h * 0.11)
		end, function()
			return 1 - 0.55 * alpha(run:designTime())
		end, Enum.Material.Neon)
	end
end

def.beats = {
	{
		at = -0.4,
		run = function(run)
			local target = run:target()
			run:face(target)
			buildSpirit(run)
			run.memo.hits, run.memo.total = 0, 0
			for _, event in run.cast do
				if event.kind == "Damage" then
					run.memo.total += 1
				end
			end
			if not target then
				return
			end
			-- Fist afterimages flying into the target through the barrage.
			for i = 0, (if run.reduced then 8 else 16) do
				local t = i * 0.06
				run:at(t, function()
					local from = spiritFrame(run, t).Position
					local to = target.part.Position
						+ Vector3.new((math.random() - 0.5) * 1.2, (math.random() - 0.5) * 1.2, 0)
					Kit.live(run, t, t + 0.1, "Ball", run.style.primary, function(part, u)
						part.Size = Vector3.one * 0.55
						part.CFrame = CFrame.new(from:Lerp(to, u))
						part.Transparency = 0.3 + 0.6 * u
					end)
				end)
			end
			run:sound("charge", 1.2)
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
	if not view then
		return true
	end
	run.memo.hits = (run.memo.hits or 0) + 1
	local at = view.part.Position
	if run.memo.hits >= (run.memo.total or 5) then
		-- The final punch: the recipe's purple burst at the target (core, glow sheet and side sheets,
		-- shock ring, sparks, light), impact dust, then purple residue.
		local floor = at - Vector3.new(0, view.part.Size.Y / 2, 0)
		local spirit = VfxRecipe.energy(run.style.primary, WHITE:Lerp(run.style.primary, 0.4))
		VfxRecipe.burst(run, floor, 2 * run:scale(), { theme = spirit })
		VfxRecipe.aftermath(run, floor, 2 * run:scale(), { theme = spirit })
		VfxRecipe.dust(floor, 1.6 * run:scale(), if run.reduced then 1 else 3)
		run:hitStop(view, 0.14)
		run:sound("whoosh", 0.8)
	else
		-- A small impact on each barrage hit.
		local spirit = VfxRecipe.energy(run.style.primary, WHITE:Lerp(run.style.primary, 0.4))
		VfxRecipe.hit(run, at, view.part.Size.Y * 0.7, spirit, run:forward())
		run:shake(0.05)
		run:sound("tick", 1.2)
	end
	return true
end

return def
