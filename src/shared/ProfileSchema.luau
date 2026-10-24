-- The saved player profile (PlayerData): its versioned shape, migrations from older saves, and the
-- save guard that never lets a save wipe progress. Pure Luau: no Roblox APIs, so it runs in Lune
-- tests.
--
-- Version 1:
--   v, createdAt, lastSeen (os.time)
--   flags        { tutorialSeen, funnel = { [step] = true } } (copied from the old PlayerFlags
--                store when a profile is first made; PlayerFlags stays in use for those two)
--   account      { level, xp (into the level), totalXp }
--   coins        soft currency
--   titles       { [title id] = true }; cosmetics { [cosmetic id] = true } (stored for later)
--   equipped     { title = "" }
--   quests       Quests.State
--   mastery      { [unit id] = { xp, level } }
--   days         { first, last, played, streak, best }: UTC days (first seen, last played) and
--                counts; a missed day only restarts `streak`, nothing is lost
--   stats        { matches, top4, wins }

local Quests = if script then require(script.Parent.Quests) else require("./Quests")

local ProfileSchema = {}

ProfileSchema.VERSION = 1

export type Profile = { [string]: any }

function ProfileSchema.default(now: number): Profile
	local day = Quests.dayOf(now)
	return {
		v = ProfileSchema.VERSION,
		createdAt = now,
		lastSeen = now,
		flags = { tutorialSeen = false, funnel = {} },
		account = { level = 1, xp = 0, totalXp = 0 },
		coins = 0,
		titles = {},
		cosmetics = {},
		equipped = { title = "" },
		quests = Quests.newState(),
		mastery = {},
		days = { first = day, last = -1, played = 0, streak = 0, best = 0 },
		stats = { matches = 0, top4 = 0, wins = 0 },
	}
end

-- Fills any field the profile lacks with its default (a field added later never breaks a save).
local function fill(profile: Profile, defaults: Profile)
	for key, value in defaults do
		if profile[key] == nil then
			profile[key] = value
		elseif type(value) == "table" and type(profile[key]) == "table" and next(value) ~= nil then
			fill(profile[key], value)
		end
	end
end

-- Migrations from version n to n + 1 (none yet: version 1 is the first).
local MIGRATIONS: { [number]: (Profile) -> () } = {}

-- The profile from whatever was stored (`stored`: nil for a new player), upgraded to VERSION.
-- `legacyFlags` (the old PlayerFlags entry: { tutorialSeen?, funnel? }) is folded in for a new
-- profile. Returns the profile and whether it may be saved (false for a profile written by a newer
-- version of the game: saving it here would lose its newer fields).
function ProfileSchema.migrate(stored: any, now: number, legacyFlags: any?): (Profile, boolean)
	if type(stored) ~= "table" or type(stored.v) ~= "number" then
		local profile = ProfileSchema.default(now)
		-- A stored table without a version is an old flags entry: keep what it knew.
		local flags = if type(stored) == "table" then stored else legacyFlags
		if type(flags) == "table" then
			profile.flags.tutorialSeen = flags.tutorialSeen == true
			if type(flags.funnel) == "table" then
				for step, reached in flags.funnel do
					profile.flags.funnel[step] = reached == true
				end
			end
		end
		return profile, true
	end
	if stored.v > ProfileSchema.VERSION then
		return stored, false
	end
	local profile = stored
	while profile.v < ProfileSchema.VERSION do
		local step = MIGRATIONS[profile.v]
		if step then
			step(profile)
		end
		profile.v += 1
	end
	fill(profile, ProfileSchema.default(now))
	return profile, true
end

-- True if the profile holds no progress at all (what a fresh or failed load looks like).
function ProfileSchema.isEmpty(profile: Profile): boolean
	return (profile.account == nil or (profile.account.totalXp or 0) == 0)
		and (profile.coins or 0) == 0
		and next(profile.titles or {}) == nil
		and next(profile.mastery or {}) == nil
		and ((profile.stats and profile.stats.matches) or 0) == 0
end

-- The save guard: may `new` replace `old` (what is stored now, nil if nothing)? Never with an
-- invalid profile, an older version, an empty profile over one with progress, or less account XP
-- than is stored (coins may go down: they will be spent). Returns ok and why not.
function ProfileSchema.safeToReplace(old: any, new: any): (boolean, string?)
	if type(new) ~= "table" or type(new.v) ~= "number" or type(new.account) ~= "table" then
		return false, "invalid profile"
	end
	if type(old) ~= "table" or type(old.v) ~= "number" then
		return true, nil -- nothing (or only an old flags entry) stored yet
	end
	if new.v < old.v then
		return false, "older version than the stored profile"
	end
	if ProfileSchema.isEmpty(new) and not ProfileSchema.isEmpty(old) then
		return false, "empty profile over saved progress"
	end
	local oldXp = (old.account and old.account.totalXp) or 0
	if (new.account.totalXp or 0) < oldXp then
		return false, "less account XP than stored"
	end
	return true, nil
end

return ProfileSchema
