-- Gold and XP math: interest, streaks, round income and leveling.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local EconomyConfig = if script then require(script.Parent.EconomyConfig) else require("./EconomyConfig")
local LevelConfig = if script then require(script.Parent.LevelConfig) else require("./LevelConfig")

local Economy = {}

-- Outcome of a fight for one player.
Economy.Outcome = table.freeze({
	Win = "Win",
	Loss = "Loss",
	Draw = "Draw",
})

export type Income = {
	base: number,
	interest: number,
	streak: number,
	win: number,
	total: number,
}

function Economy.interest(gold: number): number
	return math.min(EconomyConfig.maxInterest, gold // EconomyConfig.goldPerInterest)
end

-- `streak` is positive for consecutive wins and negative for consecutive losses.
function Economy.streakBonus(streak: number): number
	local length = math.abs(streak)
	for _, bonus in EconomyConfig.streakBonuses do
		if length >= bonus.minStreak then
			return bonus.gold
		end
	end
	return 0
end

-- Returns the streak after a fight. A draw ends any streak.
function Economy.nextStreak(streak: number, outcome: string): number
	if outcome == Economy.Outcome.Win then
		return if streak > 0 then streak + 1 else 1
	elseif outcome == Economy.Outcome.Loss then
		return if streak < 0 then streak - 1 else -1
	end
	return 0
end

-- Gold paid at the start of a Preparation that follows a fight. Interest is based on the gold
-- held before this income is added.
function Economy.roundIncome(gold: number, streak: number, wonLastFight: boolean): Income
	local income = {
		base = EconomyConfig.baseIncome,
		interest = Economy.interest(gold),
		streak = Economy.streakBonus(streak),
		win = if wonLastFight then EconomyConfig.winBonus else 0,
		total = 0,
	}
	income.total = income.base + income.interest + income.streak + income.win
	return income
end

-- XP needed to reach the next level, or nil at the maximum level.
function Economy.xpToNextLevel(level: number): number?
	if level >= LevelConfig.maxLevel then
		return nil
	end
	return LevelConfig.xpToNextLevel[level]
end

-- Adds XP and applies any level-ups. Returns the new level and XP. XP is 0 at the maximum level.
function Economy.addXp(level: number, xp: number, amount: number): (number, number)
	xp += amount
	while true do
		local needed = Economy.xpToNextLevel(level)
		if needed == nil then
			return level, 0
		end
		if xp < needed then
			return level, xp
		end
		xp -= needed
		level += 1
	end
end

return Economy
