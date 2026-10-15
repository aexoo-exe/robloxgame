-- crimson_hunger (Tier 2): the tendrils, fiercer the more hurt he is. The real cast hits his target
-- (harder the more health he is missing) and heals him a lot only if the hit kills, at the Cast
-- event.
--   -0.30  crimson segmented tendrils flare out from his back; one eye glows red
--    0     the tendrils lash forward together onto the target; a crimson burst, bigger and darker
--          the lower his health
--   +0.10  on a real kill-heal, red light is pulled back into him; otherwise the tendrils retract

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local DARK = Color3.fromRGB(70, 8, 16)

local def = {}

def.pose = {
	lean = { { -0.3, 0 }, { -0.15, -6 }, { -0.02, -6 }, { 0.03, 14, "snap" }, { 0.35, 4 }, { 0.6, 0 } },
	crouch = { { -0.3, 0 }, { -0.15, 0.1 }, { 0.03, 0.18, "snap" }, { 0.6, 0 } },
	rightArm = { { -0.3, 0 }, { -0.15, 30 }, { 0.6, 0 } },
	leftArm = { { -0.3, 0 }, { -0.15, 30 }, { 0.6, 0 } },
}

-- How hurt he is (0 healthy, 1 nearly dead).
local function hurt(run): number
	local view = run.view
	return 1 - math.clamp((view.health or 1) / math.max(view.maxHealth or 1, 1), 0, 1)
end

-- A tendril from his lower back: flared out wide, then lashed to `goal()` and back.
local function tendril(run, side: number, rise: number, goal: () -> Vector3)
	-- Where it starts and where its tip is now: flared out, lashing to the target at the release.
	local function ends(): (Vector3, Vector3)
		local t = run:designTime()
		local forward = run:forward()
		local back = run:ground() + Vector3.new(0, run.view.part.Size.Y * 0.45, 0) - forward * 0.4
		local across = Vector3.new(-forward.Z, 0, forward.X) * side
		local flared = back + across * 2 + Vector3.new(0, rise, 0) - forward * 0.6
		local lash = Kit.easeIn(math.clamp((t + 0.05) / 0.08, 0, 1)) * (1 - Kit.smooth((t - 0.08) / 0.2))
		local grown = Kit.easeOut((t + 0.3) / 0.12)
		return back, back:Lerp(flared:Lerp(goal(), lash), math.max(grown, 0.05))
	end
	Kit.block(run, -0.3, 0.3, run.style.primary, function()
		local back, tip = ends()
		return CFrame.lookAt((back + tip) / 2, tip)
	end, function()
		local back, tip = ends()
		return Vector3.new(0.22, 0.22, math.max((tip - back).Magnitude, 0.05))
	end, function(u)
		return if u > 0.85 then (u - 0.85) * 6 else 0.05
	end)
end

def.beats = {
	{
		at = -0.3,
		run = function(run)
			local target = run:target()
			run:face(target)
			local function goal(): Vector3
				return if target then target.part.Position else run:chest() + run:forward() * 4
			end
			for i, spec in { { -1, 0.6 }, { 1, 0.6 }, { -1, -0.4 }, { 1, -0.4 } } do
				if not run.reduced or i <= 2 then
					tendril(run, spec[1], spec[2], goal)
				end
			end
			-- One eye lit red.
			Kit.orb(run, -0.28, 0.3, run.style.primary, function()
				local forward = run:forward()
				return run:head() + forward * 0.45 + Vector3.new(-forward.Z, 0, forward.X) * 0.18
			end, function()
				return 0.14
			end)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view then
			local fury = hurt(run)
			local color = run.style.primary:Lerp(DARK, fury * 0.6)
			ImpactEffects.ball(view.part.Position, color, 1.6 + 2 * fury, 0.12 + 0.08 * fury)
			ImpactEffects.burst("spark", view.part.Position, nil, {
				color = color,
				count = math.floor(6 + 10 * fury),
				size = 0.24,
				speed = { 6, 12 },
				lifetime = { 0.12, 0.3 },
			})
			run:hitStop(view, 0.05 + 0.06 * fury)
			run:shake(0.06 + 0.06 * fury)
		end
		return true
	elseif kind == "Heal" and event.target == run.unitIndex then
		-- The kill-heal: red light pulled back into him.
		Kit.converge(run, run:designTime(), run:designTime() + 0.3, function()
			return run:chest()
		end, run.style.primary, 3, 8, false, 0.3)
		return true
	end
	return false
end

return def
