-- zero_field (Tier 3): float, hang, drop. The real cast holds every enemy within 1 hex of her target
-- (0.75-1.25 s by star level), hurts each when its hold ends (a Damage event marked stunEnd), and
-- speeds up every ally's attacks, all at the Cast event.
--   -0.40  her fingertips touch; the pink pads glow
--   -0.12  she taps toward the target
--    0     pink rings pulse out over the area; every held enemy floats up, turning helplessly, in a
--          pink glow; a pink pulse under each ally she speeds up
--   end    she claps (release!) and on the real end-of-hold hits they slam down: dust, pink rings

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE

local def = {}

local function holdOf(run): number
	local stun = run:find("Stun")
	return if stun and stun.duration then stun.duration else 1
end

function def.poseFor(run)
	local d = holdOf(run)
	return {
		-- Fingertips together, the tap, then the clap at the release.
		leftArm = {
			{ -0.4, 0 },
			{ -0.25, 72 },
			{ -0.12, 72 },
			{ 0.2, 40 },
			{ d - 0.2, 60 },
			{ d - 0.05, 85, "snap" },
			{ d + 0.3, 80 },
			{ d + 0.6, 0 },
		},
		leftArmOut = {
			{ -0.4, 0 },
			{ -0.25, -18 },
			{ 0.2, 10 },
			{ d - 0.2, 30 },
			{ d - 0.05, -14, "snap" },
			{ d + 0.3, -14 },
			{ d + 0.6, 0 },
		},
		rightArm = {
			{ -0.4, 0 },
			{ -0.25, 72 },
			{ -0.12, 72 },
			{ -0.04, 96, "snap" },
			{ 0.2, 40 },
			{ d - 0.2, 60 },
			{ d - 0.05, 85, "snap" },
			{ d + 0.3, 80 },
			{ d + 0.6, 0 },
		},
		rightArmOut = {
			{ -0.4, 0 },
			{ -0.25, -18 },
			{ -0.04, 0, "snap" },
			{ 0.2, 10 },
			{ d - 0.2, 30 },
			{ d - 0.05, -14, "snap" },
			{ d + 0.3, -14 },
			{ d + 0.6, 0 },
		},
		lean = { { -0.4, 0 }, { -0.04, 6, "snap" }, { 0.2, 0 }, { d - 0.05, 4, "snap" }, { d + 0.6, 0 } },
	}
end

-- A held enemy: up, turning and wobbling, then down hard at the release.
local function floatTrack(d: number)
	return {
		rise = { { 0, 0 }, { 0.35, 1.5, "out" }, { d - 0.02, 1.7 }, { d + 0.06, 0, "in" } },
		spin = { { 0, 0 }, { d, 160 }, { d + 0.01, 0, "hold" } },
		tilt = { { 0, 0 }, { 0.3, 12 }, { 0.6, -10 }, { d, 8 }, { d + 0.06, 0 } },
		fall = { { 0, 0 }, { 0.4, -14 }, { d, -18 }, { d + 0.06, 0 } },
	}
end

def.beats = {
	{
		at = -0.4,
		run = function(run)
			run:face(run:target())
			Kit.orb(run, -0.3, -0.04, run.style.primary, function()
				return (run:hand("left") + run:hand("right")) / 2
			end, function(u)
				return (0.2 + 0.25 * u) * run:scale()
			end)
			run:sound("chime", 1.3)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	local pink = run.style.primary
	if kind == "AreaStun" then
		local center, radius = run:area()
		for i = 0, 2 do
			FxKit.ring(center, if i == 1 then WHITE else pink, radius * (1.6 + 0.4 * i), 0.4, i * 0.1)
		end
		return true
	elseif kind == "Stun" and event.target then
		local view = run.context.views[event.target]
		if view then
			local d = event.duration or holdOf(run)
			run:pose(floatTrack(d), view)
			Kit.shell(run, 0, d, pink, view.part.Position, function()
				return view.part.Size.Y * 1.1
			end, function()
				return 0.8
			end)
		end
		return false -- the stun halo still shows
	elseif kind == "Damage" and event.stunEnd and event.target then
		local view = run.context.views[event.target]
		if view then
			-- The slam down as the hold ends.
			local floor = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
			ImpactEffects.burst("puff", floor + Vector3.new(0, 0.3, 0), nil, {
				color = Kit.DUST,
				count = 8,
				size = 0.8,
				speed = { 3, 6 },
				lifetime = { 0.3, 0.6 },
				transparency = 0.35,
			})
			FxKit.ring(floor, pink, 4.5, 0.35)
			run:hitStop(view, 0.08)
		end
		if not run.memo.dropped then
			run.memo.dropped = true
			run:shake(0.18)
			run:sound("whoosh", 0.9)
		end
		return true
	elseif kind == "Buff" and event.target and event.target ~= run.unitIndex then
		local view = run.context.views[event.target]
		if view then
			FxKit.ring(view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0), pink, 3.5, 0.4, 0.1)
		end
		return true
	end
	return false
end

return def
