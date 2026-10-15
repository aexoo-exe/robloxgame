-- mirror_script (Tier 3): the red eye and the ghost of the copied move. The real cast copies the
-- ability of the enemy that cast last (a Copy event, then the copied ability's own events as his);
-- if no enemy has cast yet, it is a magic hit on his target. Both at the Cast event.
--   -0.45  he lifts his headband: one eye glows red, marks spinning around it
-- Copy:
--   -0.20  a ghostly red outline of the copied enemy's pose flickers over him
--    0     a red thread from the copied enemy to him; the copied ability plays (in his colors, with
--          a red edge on its hits)
-- No copy:
--   -0.30  lightning gathers in his hand at his side
--    0     a quick stab: a lightning blade to the target

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local RED = Color3.fromRGB(230, 30, 40)
local INK = Color3.fromRGB(20, 10, 12)

local def = {}

local function copying(run): boolean
	return run:find("Copy") ~= nil
end

local COPY = {
	rightArm = {
		{ -0.45, 0 },
		{ -0.3, 160, "out" },
		{ -0.18, 160 },
		{ -0.05, 60 },
		{ 0.03, 95, "snap" },
		{ 0.35, 80 },
		{ 0.6, 0 },
	},
	rightArmOut = { { -0.45, 0 }, { -0.3, -22 }, { -0.18, -22 }, { -0.05, 0 } },
	leftArm = { { -0.2, 0 }, { 0.03, 60, "snap" }, { 0.6, 0 } },
	lean = { { -0.2, 0 }, { 0.03, 8, "snap" }, { 0.5, 0 } },
}

local STAB = {
	rightArm = {
		{ -0.45, 0 },
		{ -0.3, 160, "out" },
		{ -0.18, 160 },
		{ -0.08, -30 },
		{ -0.02, -35 },
		{ 0.03, 100, "snap" },
		{ 0.35, 90 },
		{ 0.6, 0 },
	},
	rightArmOut = { { -0.45, 0 }, { -0.3, -22 }, { -0.18, -22 }, { -0.08, 15 }, { 0.03, 0, "snap" } },
	crouch = { { -0.15, 0 }, { -0.02, 0.15 }, { 0.03, 0.05, "snap" }, { 0.4, 0 } },
	lean = { { -0.15, 0 }, { -0.02, 12 }, { 0.03, 16, "snap" }, { 0.4, 0 } },
	lunge = { { 0.02, 0 }, { 0.05, 0.35, "snap" }, { 0.4, 0 } },
}

function def.poseFor(run)
	return if copying(run) then COPY else STAB
end

-- His red eye, with marks turning around it.
local function eye(run)
	local function at(): Vector3
		local forward = run:forward()
		local side = Vector3.new(-forward.Z, 0, forward.X)
		return run:head() + forward * 0.45 + side * 0.18
	end
	Kit.orb(run, -0.3, 0.4, RED, at, function()
		return 0.16 * run:scale()
	end)
	if not run.reduced then
		for i = 1, 3 do
			Kit.live(run, -0.3, 0.4, "Ball", INK, function(part)
				local angle = i * 2.09 + run:now() * 12
				part.Size = Vector3.one * 0.06
				part.CFrame = CFrame.new(at() + Vector3.new(math.cos(angle) * 0.12, math.sin(angle) * 0.12, 0))
				part.Transparency = 0
			end)
		end
	end
end

-- The ghost of the copied enemy's pose over him: a red outline that flickers.
local function ghost(run)
	local h = run.view.part.Size.Y * 1.05
	local pieces = {
		{ CFrame.new(0, h * 0.55, 0), Vector3.new(h * 0.42, h * 0.42, h * 0.24) },
		{ CFrame.new(0, h * 0.88, 0), Vector3.one * h * 0.24 },
		{
			CFrame.new(h * 0.3, h * 0.6, -h * 0.2) * CFrame.Angles(math.rad(-70), 0, 0),
			Vector3.new(h * 0.12, h * 0.4, h * 0.12),
		},
		{
			CFrame.new(-h * 0.3, h * 0.55, 0) * CFrame.Angles(0, 0, math.rad(-30)),
			Vector3.new(h * 0.12, h * 0.4, h * 0.12),
		},
	}
	for _, piece in pieces do
		Kit.block(run, -0.2, 0.2, RED, function()
			local base = run:ground()
			return CFrame.lookAt(base, base + run:forward()) * piece[1]
		end, function()
			return piece[2]
		end, function(u)
			local flicker = if math.floor(u * 16) % 3 == 0 then 0.25 else 0
			return math.min(1, 0.6 + flicker + 0.3 * u)
		end, Enum.Material.Neon)
	end
end

def.beats = {
	{
		at = -0.45,
		run = function(run)
			run:face(run:target())
			eye(run)
			run.memo.copying = copying(run)
			if run.memo.copying then
				run:at(-0.2, ghost)
			else
				run:at(-0.3, function()
					Kit.orb(run, -0.3, 0.02, WHITE:Lerp(run.style.primary, 0.3), function()
						return run:hand("right")
					end, function(u)
						return (0.3 + 0.4 * u) * run:scale()
					end)
				end)
			end
			run:sound("chime", 1.6)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Copy" and event.target then
		local enemy = run.context.views[event.target]
		if enemy then
			Kit.zap(enemy.part.Position, run:chest(), RED, 0.18, 0.35, 3)
			ImpactEffects.ball(enemy.part.Position, RED, enemy.part.Size.Y * 0.6, 0.15)
		end
		return true
	elseif not run.memo.copying and kind == "Damage" and event.target and not event.dot then
		-- The lightning blade: a stab of lightning across to the target.
		local view = run.context.views[event.target]
		if view then
			Kit.zap(run:hand("right"), view.part.Position, WHITE, 0.3, 0.2, 3)
			Kit.zap(run:hand("right"), view.part.Position, run.style.primary, 0.6, 0.15, 2)
			ImpactEffects.ball(view.part.Position, WHITE, 2, 0.1)
			run:hitStop(view, 0.08)
			run:shake(0.15)
		end
		return true
	elseif run.memo.copying and kind == "Damage" and event.target and not event.dot then
		-- The copied hit keeps its own effect, with a red edge.
		local view = run.context.views[event.target]
		if view then
			ImpactEffects.burst("spark", view.part.Position, nil, {
				color = RED,
				count = 6,
				size = 0.22,
				speed = { 6, 10 },
				lifetime = { 0.12, 0.25 },
			})
		end
		return false
	end
	return false
end

return def
