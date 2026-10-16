-- night_command (Tier 4): arise. The real cast summons two or three shadow soldiers beside him at
-- the Cast event (each a Summon event on its own cell).
--   -0.80  one hand rises; his eyes glow purple; dark mist spills at his feet
--   -0.50  the ground around him becomes a pool of black-purple shadow; stillness, the camera
--          leans in (the word)
--    0     on each real summon a dark silhouette rises out of the pool at its cell, eyes lit, in a
--          burst of purple mist
--   +0.40  the pool drains away; he lowers his hand and both daggers glint, blue and red

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local SHADOW = Color3.fromRGB(16, 10, 24)
local EYES = Color3.fromRGB(190, 120, 255)
local BLUE_EDGE = Color3.fromRGB(150, 205, 245)
local RED_EDGE = Color3.fromRGB(200, 30, 45)

local def = {}

def.pose = {
	rightArm = { { -0.8, 0 }, { -0.55, 150, "out" }, { -0.05, 152 }, { 0.05, 165, "snap" }, { 0.45, 150 }, { 0.8, 0 } },
	rightArmOut = { { -0.8, 0 }, { -0.55, 10 }, { 0.45, 10 }, { 0.8, 0 } },
	leftArm = { { -0.8, 0 }, { -0.5, -15 }, { 0.5, -15 }, { 0.8, 0 } },
	leftArmOut = { { -0.8, 0 }, { -0.5, 20 }, { 0.5, 20 }, { 0.8, 0 } },
	lean = { { -0.8, 0 }, { -0.55, -6 }, { 0.05, -8 }, { 0.5, -2 }, { 0.8, 0 } },
	tremble = { { -0.4, 0 }, { -0.3, 0.4 }, { -0.05, 0.4 }, { 0, 0, "hold" } },
}

def.beats = {
	{
		at = -0.8,
		run = function(run)
			-- Eyes lit: two small glows at the front of the head.
			for _, x in { -0.18, 0.18 } do
				Kit.orb(run, -0.75, 0.5, EYES, function()
					local head = run:head()
					local side = Vector3.new(-run:forward().Z, 0, run:forward().X)
					return head + run:forward() * 0.45 + side * x
				end, function()
					return 0.14 * run:scale()
				end)
			end
			ImpactEffects.burst("smoke", run:ground() + Vector3.new(0, 0.3, 0), nil, {
				color = SHADOW,
				color2 = run.style.primary,
				count = if run.reduced then 6 else 12,
				size = 1.2,
				speed = { 1, 3 },
				lifetime = { 0.6, 1 },
				transparency = 0.3,
			})
			run:sound("charge", 0.55)
		end,
	},
	{
		-- The pool of shadow spreading under him, wide enough for his soldiers.
		at = -0.5,
		run = function(run)
			Kit.pool(run, -0.5, 0.75, SHADOW, run:ground(), function()
				local t = run:designTime()
				local open = Kit.easeOut((t + 0.5) / 0.4)
				local drain = Kit.easeIn((t - 0.35) / 0.4)
				return 12 * open * (1 - drain)
			end, function()
				return 0.12
			end, Enum.Material.Glass)
			Kit.pool(run, -0.45, 0.7, run.style.primary, run:ground(), function()
				local t = run:designTime()
				return 12.6 * Kit.easeOut((t + 0.45) / 0.4) * (1 - Kit.easeIn((t - 0.35) / 0.4))
			end, function()
				return 0.75
			end, Enum.Material.Neon)
			run:camera(-0.45, 0, { key = "push", push = 2.2, focus = run:chest(), rise = 0.3, fall = 0.1 })
		end,
	},
	{
		-- The daggers glint as the hand comes down.
		at = 0.5,
		run = function(run)
			ImpactEffects.ball(run:hand("left"), BLUE_EDGE, 0.8, 0.15)
			ImpactEffects.ball(run:hand("right"), RED_EDGE, 0.8, 0.15)
			run:sound("chime", 1.4)
		end,
	},
}

function def.release(run): boolean
	ImpactEffects.ball(run:hand("right"), EYES, 1 * run:scale(), 0.12)
	return true
end

function def.event(run, event): boolean
	if event.kind ~= "Summon" then
		return false
	end
	-- A soldier rises out of the shadow at its real cell.
	local at = run.context.toWorld(event.column, event.row)
	local height = run.view.part.Size.Y * 1.05
	local now = run:designTime()
	Kit.block(run, now, now + 0.45, SHADOW, function(u)
		local rise = Kit.easeOut(u / 0.7)
		return CFrame.new(at + Vector3.new(0, height * (rise - 0.5), 0))
	end, function()
		return Vector3.new(1.3, height, 0.8)
	end, function(u)
		return if u < 0.75 then 0.05 else (u - 0.75) * 4
	end)
	for _, x in { -0.25, 0.25 } do
		Kit.live(run, now, now + 0.45, "Ball", EYES, function(part, u)
			local rise = Kit.easeOut(u / 0.7)
			part.Size = Vector3.one * 0.18
			part.CFrame = CFrame.new(at + Vector3.new(x, height * (rise - 0.5) + height * 0.38, -0.42))
			part.Transparency = if u < 0.75 then 0 else (u - 0.75) * 4
		end)
	end
	ImpactEffects.burst("smoke", at + Vector3.new(0, 0.6, 0), Vector3.yAxis, {
		color = run.style.primary,
		color2 = SHADOW,
		count = 10,
		size = 1.1,
		speed = { 2, 5 },
		lifetime = { 0.5, 0.8 },
		spread = 50,
		transparency = 0.3,
	})
	ImpactEffects.ring(at, EYES:Lerp(WHITE, 0.2), 4)
	run:sound("whoosh", 0.8)
	return true
end

return def
