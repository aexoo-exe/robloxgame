-- Fast-forward schedule (Playback, CombatConfig.playbackSpeeds).

local CombatConfig = require("../src/shared/CombatConfig")
local Playback = require("../src/shared/Playback")

local function near(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) < 1e-9, string.format("%s: expected %s, got %s", label, expected, actual))
end

local tests = {}

table.insert(tests, {
	name = "the configured schedule is normal speed until 30s, 2x from 30s and 3x from 40s",
	run = function()
		local steps = CombatConfig.playbackSpeeds
		assert(steps[1].fromSecond == 0, "the first step must start at 0")
		near(Playback.speedAt(0), 1, "speed at 0s")
		near(Playback.speedAt(29.9), 1, "speed at 29.9s")
		near(Playback.speedAt(30), 2, "speed at 30s")
		near(Playback.speedAt(39.9), 2, "speed at 39.9s")
		near(Playback.speedAt(40), 3, "speed at 40s")
		near(Playback.speedAt(50), 3, "speed at 50s")
	end,
})

table.insert(tests, {
	name = "real playback time follows the schedule",
	run = function()
		near(Playback.realSeconds(0), 0, "0s")
		near(Playback.realSeconds(20), 20, "a 20s fight")
		near(Playback.realSeconds(30), 30, "a 30s fight")
		near(Playback.realSeconds(35), 32.5, "a 35s fight") -- 30 + 5 / 2
		near(Playback.realSeconds(40), 35, "a 40s fight") -- 30 + 10 / 2
		near(Playback.realSeconds(50), 35 + 10 / 3, "a 50s fight (the time limit)")
		near(Playback.realSeconds(-1), -1, "before the fight starts")
	end,
})

table.insert(tests, {
	name = "fight time is the inverse of real time",
	run = function()
		for _, fight in { 0, 5, 29.5, 30, 31, 39.99, 40, 47.3, 50 } do
			near(Playback.fightSeconds(Playback.realSeconds(fight)), fight, "round trip at " .. fight .. "s")
		end
		near(Playback.fightSeconds(32.5), 35, "32.5s of playback")
		near(Playback.fightSeconds(-0.5), -0.5, "before the fight starts")
	end,
})

table.insert(tests, {
	name = "a custom schedule is honored",
	run = function()
		local schedule = { { fromSecond = 0, speed = 1 }, { fromSecond = 10, speed = 4 } }
		near(Playback.realSeconds(30, schedule), 15, "10 + 20 / 4")
		near(Playback.fightSeconds(15, schedule), 30, "inverse")
		near(Playback.speedAt(12, schedule), 4, "speed")
	end,
})

return tests
