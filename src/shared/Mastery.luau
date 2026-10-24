-- Unit mastery (RetentionConfig.mastery): XP per unit for fielding it, mastery levels from total
-- XP, and the cosmetic rewards each level unlocks. Pure Luau: no Roblox APIs, so it runs in Lune.

local RetentionConfig = if script then require(script.Parent.RetentionConfig) else require("./RetentionConfig")

local Mastery = {}

local CONFIG = RetentionConfig.mastery

export type Entry = { xp: number, level: number }

-- The mastery level for `xp` total.
function Mastery.levelFor(xp: number): number
	local level = 1
	for index, needed in CONFIG.levels do
		if xp >= needed then
			level = index
		end
	end
	return level
end

-- XP to the next level from `xp` (0 at the top level).
function Mastery.toNext(xp: number): number
	local level = Mastery.levelFor(xp)
	local nextNeeded = CONFIG.levels[level + 1]
	return if nextNeeded then nextNeeded - xp else 0
end

-- One match's mastery XP per unit: `roundsFielded` (unit id -> rounds it fought), `finalBoard`
-- (unit ids on the last fight's board), and whether the player placed top 4.
function Mastery.matchGains(
	roundsFielded: { [string]: number },
	finalBoard: { string },
	top4: boolean
): { [string]: number }
	local gains = {}
	for unitType, rounds in roundsFielded do
		gains[unitType] = rounds * CONFIG.perRound
	end
	local seen = {}
	for _, unitType in finalBoard do
		if not seen[unitType] then
			seen[unitType] = true
			gains[unitType] = (gains[unitType] or 0) + (if top4 then CONFIG.top4Bonus else CONFIG.finalBonus)
		end
	end
	return gains
end

-- The reward for reaching mastery `level` with `unitType` (ids filled in), or nil.
function Mastery.rewardFor(unitType: string, level: number): { title: string?, cosmetic: string? }?
	local reward = CONFIG.rewards[level]
	if not reward then
		return nil
	end
	return {
		title = reward.title,
		cosmetic = if reward.cosmetic then (string.gsub(reward.cosmetic, "<unit>", unitType)) else nil,
	}
end

-- Adds `amount` to a unit's entry in `mastery` (unit id -> Entry, changed in place). Returns the
-- levels reached, in order, with their rewards.
function Mastery.add(mastery: { [string]: Entry }, unitType: string, amount: number): { { level: number, reward: any } }
	local entry = mastery[unitType]
	if not entry then
		entry = { xp = 0, level = 1 }
		mastery[unitType] = entry
	end
	local reached = {}
	if amount <= 0 then
		return reached
	end
	local before = entry.level
	entry.xp += amount
	entry.level = Mastery.levelFor(entry.xp)
	for level = before + 1, entry.level do
		table.insert(reached, { level = level, reward = Mastery.rewardFor(unitType, level) })
	end
	return reached
end

return Mastery
