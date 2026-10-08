-- Fast-forward for long fights: converts between fight time (seconds of the simulated fight) and
-- real time (seconds of playback) using the speed schedule in CombatConfig.playbackSpeeds. The
-- server times the Combat phase with Playback.realSeconds and every client plays fights back with
-- Playback.fightSeconds, so all players stay in sync. Fights are simulated before playback, so the
-- schedule never changes what happens in a fight.
-- Every function takes an optional schedule (CombatConfig.playbackSpeeds if omitted), so tests can
-- use their own. Before the fight starts (negative times) playback runs at normal speed.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local CombatConfig = if script then require(script.Parent.CombatConfig) else require("./CombatConfig")

local Playback = {}

export type Step = { fromSecond: number, speed: number }

local function stepsOf(schedule: { Step }?): { Step }
	return schedule or CombatConfig.playbackSpeeds
end

-- Playback speed at a moment of the fight.
function Playback.speedAt(fightSeconds: number, schedule: { Step }?): number
	local speed = 1
	for _, step in stepsOf(schedule) do
		if fightSeconds >= step.fromSecond then
			speed = step.speed
		end
	end
	return speed
end

-- Real seconds it takes to play back the first `fightSeconds` of a fight.
function Playback.realSeconds(fightSeconds: number, schedule: { Step }?): number
	if fightSeconds <= 0 then
		return fightSeconds
	end
	local steps = stepsOf(schedule)
	local real = 0
	for i, step in steps do
		if fightSeconds <= step.fromSecond then
			break
		end
		local stepEnd = if steps[i + 1] then steps[i + 1].fromSecond else math.huge
		real += (math.min(fightSeconds, stepEnd) - step.fromSecond) / step.speed
	end
	return real
end

-- The moment of the fight shown after `realSeconds` of playback (the inverse of realSeconds).
function Playback.fightSeconds(realSeconds: number, schedule: { Step }?): number
	if realSeconds <= 0 then
		return realSeconds
	end
	local steps = stepsOf(schedule)
	local real = 0
	for i, step in steps do
		local stepEnd = if steps[i + 1] then steps[i + 1].fromSecond else math.huge
		local stepReal = (stepEnd - step.fromSecond) / step.speed
		if realSeconds <= real + stepReal then
			return step.fromSecond + (realSeconds - real) * step.speed
		end
		real += stepReal
	end
	return math.huge
end

return Playback
