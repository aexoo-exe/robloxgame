-- Daily and weekly quests (RetentionConfig.quests): which quests a player has (rolled per player
-- from the pools when the UTC day or week changes), progress from match stats, claiming, and one
-- daily reroll. Pure Luau: no Roblox APIs, so it runs in Lune tests. The server owns the state;
-- clients only ask to claim or reroll (RetentionService validates through these functions).
--
-- Stats a quest can count (Quests.STATS), filled by RetentionService from a match:
--   matches, top4, roundsWon, rerolls, star2 (units upgraded to 2 stars), star3, threeTraits
--   (rounds fought with 3+ traits active), traitWins (rounds won with a given trait active, by trait)

local RetentionConfig = if script then require(script.Parent.RetentionConfig) else require("./RetentionConfig")
local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")

local Quests = {}

local CONFIG = RetentionConfig.quests
local DAY = 86400

Quests.STATS = table.freeze({ "matches", "top4", "roundsWon", "rerolls", "star2", "star3", "threeTraits", "traitWins" })

export type Quest = { id: string, trait: string?, progress: number, claimed: boolean }
export type State = {
	day: number, -- the UTC day the dailies were rolled for
	week: number, -- the week (Monday start) the weeklies were rolled for
	daily: { Quest },
	weekly: { Quest },
	rerollDay: number, -- the day the daily reroll was last used (-1: never)
}
export type Stats = { [string]: any } -- stat -> number; traitWins -> { [trait] = number }

-- UTC day and week numbers of a time (os.time()). Weeks start on Monday (day 0 was a Thursday).
function Quests.dayOf(time: number): number
	return time // DAY
end
function Quests.weekOf(time: number): number
	return (Quests.dayOf(time) + 3) // 7
end

function Quests.newState(): State
	return { day = -1, week = -1, daily = {}, weekly = {}, rerollDay = -1 }
end

local function pool(kind: string): { any }
	return if kind == "daily" then CONFIG.daily else CONFIG.weekly
end

-- The pool entry of a quest.
function Quests.spec(kind: string, quest: Quest): any?
	for _, spec in pool(kind) do
		if spec.id == quest.id then
			return spec
		end
	end
	return nil
end

-- The quest's text, e.g. "Win 3 rounds with Hunters active".
function Quests.describe(kind: string, quest: Quest): string
	local spec = Quests.spec(kind, quest)
	if not spec then
		return quest.id
	end
	return string.format(spec.text, spec.target, quest.trait or "")
end

local function newQuest(spec, rng): Quest
	local trait = nil
	if spec.trait then
		trait = CONFIG.traits[SeededRandom.nextInt(rng, #CONFIG.traits)]
	end
	return { id = spec.id, trait = trait, progress = 0, claimed = false }
end

-- `count` different quests from the pool, skipping ids in `exclude`.
local function roll(kind: string, count: number, rng, exclude: { [string]: boolean }?): { Quest }
	local candidates = {}
	for _, spec in pool(kind) do
		if not (exclude and exclude[spec.id]) then
			table.insert(candidates, spec)
		end
	end
	SeededRandom.shuffle(rng, candidates)
	local quests = {}
	for index = 1, math.min(count, #candidates) do
		table.insert(quests, newQuest(candidates[index], rng))
	end
	return quests
end

-- Rolls new dailies and/or weeklies when the day or week of `now` differs from the state's. Each
-- player's set is its own (`seed`, e.g. the UserId) and the same on every server. Returns whether
-- anything was rolled.
function Quests.rotate(state: State, now: number, seed: number): boolean
	local day, week = Quests.dayOf(now), Quests.weekOf(now)
	local changed = false
	if state.day ~= day then
		state.day = day
		state.daily = roll("daily", CONFIG.dailyCount, SeededRandom.new(seed * 7919 + day * 31 + 1))
		changed = true
	end
	if state.week ~= week then
		state.week = week
		state.weekly = roll("weekly", CONFIG.weeklyCount, SeededRandom.new(seed * 7919 + week * 131 + 2))
		changed = true
	end
	return changed
end

function Quests.isComplete(kind: string, quest: Quest): boolean
	local spec = Quests.spec(kind, quest)
	return spec ~= nil and quest.progress >= spec.target
end

-- How much of `stats` counts for a quest.
local function amountFor(spec, quest: Quest, stats: Stats): number
	if spec.stat == "traitWins" then
		local byTrait = stats.traitWins
		return if type(byTrait) == "table" and quest.trait then byTrait[quest.trait] or 0 else 0
	end
	local value = stats[spec.stat]
	return if type(value) == "number" then value else 0
end

export type Change = { kind: string, index: number, quest: Quest, before: number, after: number, completed: boolean }

-- Adds a match's `stats` to every unclaimed quest. Returns what changed (with `completed` true
-- for a quest that reached its target just now).
function Quests.addStats(state: State, stats: Stats): { Change }
	local changes = {}
	for _, kind in { "daily", "weekly" } do
		for index, quest in state[kind] do
			local spec = Quests.spec(kind, quest)
			if spec and not quest.claimed and quest.progress < spec.target then
				local amount = amountFor(spec, quest, stats)
				if amount > 0 then
					local before = quest.progress
					quest.progress = math.min(spec.target, before + amount)
					table.insert(changes, {
						kind = kind,
						index = index,
						quest = quest,
						before = before,
						after = quest.progress,
						completed = quest.progress >= spec.target,
					})
				end
			end
		end
	end
	return changes
end

-- Claims a completed quest. Returns its reward ({ coins, xp }) or nil and why not.
function Quests.claim(state: State, kind: string, index: number): ({ coins: number, xp: number }?, string?)
	if kind ~= "daily" and kind ~= "weekly" then
		return nil, "no such quest"
	end
	local quest = state[kind][index]
	if type(index) ~= "number" or not quest then
		return nil, "no such quest"
	end
	if quest.claimed then
		return nil, "already claimed"
	end
	if not Quests.isComplete(kind, quest) then
		return nil, "not complete yet"
	end
	quest.claimed = true
	local spec = Quests.spec(kind, quest)
	return { coins = spec.coins, xp = spec.xp }, nil
end

-- Swaps one daily (not claimed, not complete) for another from the pool, once per UTC day.
-- Returns true or false and why not.
function Quests.reroll(state: State, index: number, now: number, seed: number): (boolean, string?)
	local quest = if type(index) == "number" then state.daily[index] else nil
	if not quest then
		return false, "no such quest"
	end
	local day = Quests.dayOf(now)
	if state.rerollDay == day then
		return false, "already rerolled today"
	end
	if quest.claimed or Quests.isComplete("daily", quest) then
		return false, "quest is done"
	end
	local exclude = {}
	for _, other in state.daily do
		exclude[other.id] = true
	end
	local replacement = roll("daily", 1, SeededRandom.new(seed * 7919 + day * 31 + 7 + index), exclude)[1]
	if not replacement then
		return false, "no other quest"
	end
	state.daily[index] = replacement
	state.rerollDay = day
	return true, nil
end

return Quests
