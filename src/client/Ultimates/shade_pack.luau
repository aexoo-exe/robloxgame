-- shade_pack (Tier 2): hand signs, and creatures out of the shadows. The real first cast summons
-- two wolves (Summon events); every later cast drops a blow on his target's area and stuns it
-- (Area and AreaStun events), and dead wolves come back. One timeline, two choreographies.
-- Wolves:
--   -0.25  a hand sign: interlocked hands making a dog's head
--    0     on each real summon a black wolf with blue-white eyes rises out of his shadow
-- Elephant:
--   -0.25  a different sign, hands high; a dark circle grows over the target
--    0     a shadow elephant drops from above onto the real area: a dark splash, the real stun

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local SHADOW = Color3.fromRGB(12, 12, 20)
local EYES = Color3.fromRGB(200, 230, 255)

local def = {}

local function elephant(run): boolean
	return run:find("Area") ~= nil
end

local WOLVES = {
	leftArm = { { -0.25, 0 }, { -0.12, 75 }, { 0.3, 75 }, { 0.5, 0 } },
	leftArmOut = { { -0.25, 0 }, { -0.12, -22 }, { 0.3, -22 }, { 0.5, 0 } },
	rightArm = { { -0.25, 0 }, { -0.12, 80 }, { 0.3, 80 }, { 0.5, 0 } },
	rightArmOut = { { -0.25, 0 }, { -0.12, -18 }, { 0.3, -18 }, { 0.5, 0 } },
	crouch = { { -0.25, 0 }, { -0.1, 0.08 }, { 0.5, 0 } },
}

local ELEPHANT = {
	leftArm = { { -0.25, 0 }, { -0.12, 150 }, { 0.02, 150 }, { 0.06, 60, "snap" }, { 0.5, 0 } },
	rightArm = { { -0.25, 0 }, { -0.12, 150 }, { 0.02, 150 }, { 0.06, 60, "snap" }, { 0.5, 0 } },
	leftArmOut = { { -0.25, 0 }, { -0.12, -10 }, { 0.5, 0 } },
	rightArmOut = { { -0.25, 0 }, { -0.12, -10 }, { 0.5, 0 } },
	lean = { { -0.12, 0 }, { 0.06, 10, "snap" }, { 0.5, 0 } },
}

function def.poseFor(run)
	return if elephant(run) then ELEPHANT else WOLVES
end

def.beats = {
	{
		at = -0.25,
		run = function(run)
			run:face(run:target())
			if not elephant(run) then
				return
			end
			local center, radius = run:area()
			Kit.pool(run, -0.22, 0.4, SHADOW, center, function(u)
				return radius * 2 * Kit.easeOut(math.min(1, u * 3))
			end, function(u)
				return 0.2 + 0.8 * Kit.easeIn(u)
			end, Enum.Material.Glass)
			-- The elephant falling: a dark body dropping onto the area.
			Kit.block(run, -0.16, 0.06, SHADOW, function(u)
				return CFrame.new(center + Vector3.new(0, 1.6 + 10 * (1 - Kit.easeIn(u)), 0))
			end, function()
				return Vector3.new(3.2, 2.4, 4.2) * run:scale()
			end, function(u)
				return if u > 0.9 then (u - 0.9) * 10 else 0.05
			end)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Summon" then
		-- A wolf rising out of his shadow at its cell.
		local at = run.context.toWorld(event.column, event.row)
		local now = run:designTime()
		local heading = CFrame.lookAt(at, at + run:forward())
		Kit.block(run, now, now + 0.4, SHADOW, function(u)
			return heading * CFrame.new(0, -0.6 + 1.2 * Kit.easeOut(u / 0.6), 0)
		end, function()
			return Vector3.new(0.9, 0.9, 1.8)
		end, function(u)
			return if u > 0.75 then (u - 0.75) * 4 else 0.05
		end)
		Kit.live(run, now, now + 0.4, "Ball", EYES, function(part, u)
			part.Size = Vector3.one * 0.16
			part.CFrame = heading * CFrame.new(0, -0.3 + 1.2 * Kit.easeOut(u / 0.6), -0.95)
			part.Transparency = if u > 0.75 then (u - 0.75) * 4 else 0
		end)
		ImpactEffects.burst("smoke", at + Vector3.new(0, 0.4, 0), Vector3.yAxis, {
			color = SHADOW,
			color2 = run.style.secondary,
			count = 6,
			size = 0.9,
			speed = { 1, 3 },
			lifetime = { 0.4, 0.7 },
			spread = 50,
			transparency = 0.3,
		})
		return true
	elseif kind == "Area" then
		local center, radius = run:area()
		FxKit.mark(center, SHADOW, run.style.secondary, radius, "splash", 0.8)
		ImpactEffects.burst("smoke", center + Vector3.new(0, 0.5, 0), nil, {
			color = SHADOW,
			color2 = run.style.secondary,
			count = 12,
			size = 1.2,
			speed = { 4, 8 },
			lifetime = { 0.4, 0.7 },
			transparency = 0.3,
		})
		run:shake(0.12)
		run:sound("splash", 0.6)
		return true
	elseif kind == "AreaStun" then
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
