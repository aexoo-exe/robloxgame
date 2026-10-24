-- Account XP and levels (RetentionConfig.xp, .matchXp, .rewards): the level curve, the XP a match
-- earns, and adding XP to an account with the level-up rewards it unlocks. Pure Luau: no Roblox
-- APIs, so it runs in Lune tests. The server grants (RetentionService); the client only shows.

local RetentionConfig = if script then require(script.Parent.RetentionConfig) else require("./RetentionConfig")

local Progression = {}

export type Account = { level: number, xp: number, totalXp: number }
export type Reward = { coins: number?, title: string?, cosmetic: string? }

-- XP needed to go from `level` to `level + 1`.
function Progression.xpToNext(level: number): number
	local curve = RetentionConfig.xp
	return math.floor(curve.base + curve.growth * math.max(0, level - 1) ^ curve.power + 0.5)
end

-- Total XP from level 1 to reach `level`.
function Progression.totalForLevel(level: number): number
	local total = 0
	for l = 1, level - 1 do
		total += Progression.xpToNext(l)
	end
	return total
end

export type MatchResult = {
	placement: number, -- final placement (0: unknown)
	rounds: number, -- rounds survived
	practice: boolean?,
	leftEarly: boolean?, -- left the game while still in the match
}

-- Account XP for one match: base + rounds survived + a placement bonus for a Play match; a share
-- of it for Practice; a smaller share (never zero) for leaving early.
function Progression.matchXp(result: MatchResult): number
	local config = RetentionConfig.matchXp
	local rounds = math.max(0, result.rounds) * config.perRound
	if result.leftEarly then
		return math.max(config.leaverMinimum, math.floor((config.base + rounds) * config.leaverShare + 0.5))
	end
	local placementBonus = 0
	if result.placement >= 1 then
		local table_ = config.placement
		placementBonus = table_[math.min(result.placement, #table_)]
	end
	local xp = config.base + rounds + placementBonus
	if result.practice then
		xp = math.floor(xp * config.practiceShare + 0.5)
	end
	return xp
end

-- The reward for reaching `level` (nil past the table).
function Progression.rewardFor(level: number): Reward?
	return RetentionConfig.rewards[level]
end

-- Adds `amount` XP to `account` (changed in place). Returns the levels reached, in order, each with
-- its reward (nil past the reward table).
function Progression.addXp(account: Account, amount: number): { { level: number, reward: Reward? } }
	local reached = {}
	if amount <= 0 then
		return reached
	end
	account.totalXp += amount
	account.xp += amount
	while account.xp >= Progression.xpToNext(account.level) do
		account.xp -= Progression.xpToNext(account.level)
		account.level += 1
		table.insert(reached, { level = account.level, reward = Progression.rewardFor(account.level) })
	end
	return reached
end

return Progression
