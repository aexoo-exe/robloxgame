-- Retention v1 pure logic: the XP curve and level-ups, match XP, quest rotation / progress / claim /
-- reroll, unit mastery, profile migration and the never-save-empty guard.

local Mastery = require("../src/shared/Mastery")
local ProfileSchema = require("../src/shared/ProfileSchema")
local Progression = require("../src/shared/Progression")
local Quests = require("../src/shared/Quests")
local RetentionConfig = require("../src/shared/RetentionConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local DAY = 86400
local MONDAY = 4 * DAY -- 1970-01-05 00:00 UTC was a Monday

local tests = {}

table.insert(tests, {
	name = "XP curve: rises every level, fast early (level 2 in one match), slower later",
	run = function()
		local previous = 0
		for level = 1, 40 do
			local needed = Progression.xpToNext(level)
			assert(needed > previous, "the curve must rise at level " .. level)
			previous = needed
		end
		local typicalMatch = Progression.matchXp({ placement = 4, rounds = 12 })
		assert(typicalMatch >= Progression.xpToNext(1), "level 2 should take about one match")
		assert(Progression.xpToNext(30) > 10 * Progression.xpToNext(1), "late levels take much more than early ones")
		expectEqual(Progression.totalForLevel(1), 0, "level 1 total")
		expectEqual(Progression.totalForLevel(3), Progression.xpToNext(1) + Progression.xpToNext(2), "level 3 total")
	end,
})

table.insert(tests, {
	name = "addXp: several levels at once, leftover XP kept, rewards from the table",
	run = function()
		local account = { level = 1, xp = 0, totalXp = 0 }
		local amount = Progression.totalForLevel(5) + 7
		local reached = Progression.addXp(account, amount)
		expectEqual(account.level, 5, "level")
		expectEqual(account.xp, 7, "leftover")
		expectEqual(account.totalXp, amount, "total")
		expectEqual(#reached, 4, "levels reached")
		expectEqual(reached[1].level, 2, "first level reached")
		expectEqual(reached[1].reward.title, "rookie", "level 2 title")
		expectEqual(reached[4].reward.title, "contender", "level 5 title")
		assert((reached[2].reward.coins or 0) > 0, "every level gives coins")
		expectEqual(#Progression.addXp(account, 0), 0, "no XP, no levels")
		for level = 2, 30 do
			assert(RetentionConfig.rewards[level], "missing reward for level " .. level)
		end
	end,
})

table.insert(tests, {
	name = "match XP: Play > Practice > leaving early > 0, better placement earns more",
	run = function()
		local first = Progression.matchXp({ placement = 1, rounds = 20 })
		local sixth = Progression.matchXp({ placement = 6, rounds = 20 })
		local practice = Progression.matchXp({ placement = 1, rounds = 20, practice = true })
		local leaver = Progression.matchXp({ placement = 0, rounds = 2, leftEarly = true })
		assert(first > sixth, "placement matters")
		assert(sixth > practice, "practice earns less")
		assert(practice > leaver, "leaving early earns less")
		assert(leaver >= RetentionConfig.matchXp.leaverMinimum, "leaving early is never zero")
		assert(
			Progression.matchXp({ placement = 0, rounds = 0, leftEarly = true })
				>= RetentionConfig.matchXp.leaverMinimum,
			"minimum"
		)
	end,
})

table.insert(tests, {
	name = "quests: rotation per UTC day and Monday week, deterministic per player, new set on change",
	run = function()
		local a = Quests.newState()
		assert(Quests.rotate(a, MONDAY + 3600, 42), "first rotate rolls")
		expectEqual(#a.daily, RetentionConfig.quests.dailyCount, "dailies")
		expectEqual(#a.weekly, RetentionConfig.quests.weeklyCount, "weeklies")
		local ids = {}
		for _, quest in a.daily do
			assert(not ids[quest.id], "dailies are different quests")
			ids[quest.id] = true
		end
		assert(not Quests.rotate(a, MONDAY + 7200, 42), "same day: nothing new")
		local b = Quests.newState()
		Quests.rotate(b, MONDAY + 10, 42)
		for index, quest in a.daily do
			expectEqual(b.daily[index].id, quest.id, "same player, same day, same quests")
		end
		local weekBefore = a.week
		Quests.rotate(a, MONDAY + DAY + 1, 42) -- Tuesday
		expectEqual(a.week, weekBefore, "same week on Tuesday")
		expectEqual(a.day, Quests.dayOf(MONDAY + DAY + 1), "new day")
		Quests.rotate(a, MONDAY + 7 * DAY + 1, 42) -- next Monday
		expectEqual(a.week, weekBefore + 1, "new week on Monday")
	end,
})

table.insert(tests, {
	name = "quests: progress from stats, capped at the target; claim only when complete and once",
	run = function()
		local state = Quests.newState()
		Quests.rotate(state, MONDAY, 7)
		-- Give every stat a lot: every quest completes.
		local traitWins = {}
		for _, trait in RetentionConfig.quests.traits do
			traitWins[trait] = 100
		end
		local quest = state.daily[1]
		local spec = Quests.spec("daily", quest)
		expectEqual(Quests.claim(state, "daily", 1), nil, "incomplete quest cannot be claimed")
		local changes = Quests.addStats(state, {
			matches = 100,
			top4 = 100,
			roundsWon = 100,
			rerolls = 100,
			star2 = 100,
			star3 = 100,
			threeTraits = 100,
			traitWins = traitWins,
		})
		assert(#changes >= 1, "progress recorded")
		expectEqual(quest.progress, spec.target, "capped at the target")
		local reward = Quests.claim(state, "daily", 1)
		assert(reward and reward.coins == spec.coins and reward.xp == spec.xp, "claim gives the reward")
		local again, why = Quests.claim(state, "daily", 1)
		expectEqual(again, nil, "second claim refused")
		expectEqual(why, "already claimed", "reason")
		expectEqual(Quests.claim(state, "daily", 99), nil, "no such quest")
		expectEqual(Quests.claim(state, "bogus", 1), nil, "bad kind")
		-- A claimed quest takes no more progress.
		expectEqual(#Quests.addStats(state, { matches = 1 }), 0, "nothing left to progress")
	end,
})

table.insert(tests, {
	name = "quests: one daily reroll per UTC day, never on a done quest",
	run = function()
		local state = Quests.newState()
		Quests.rotate(state, MONDAY, 9)
		local before = state.daily[2].id
		local ok = Quests.reroll(state, 2, MONDAY + 60, 9)
		assert(ok, "first reroll works")
		assert(state.daily[2].id ~= before, "a different quest")
		local ids = {}
		for _, quest in state.daily do
			assert(not ids[quest.id], "no duplicate after reroll")
			ids[quest.id] = true
		end
		local again, why = Quests.reroll(state, 1, MONDAY + 120, 9)
		assert(not again and why == "already rerolled today", "second reroll the same day refused")
		Quests.rotate(state, MONDAY + DAY, 9)
		state.daily[1].progress = Quests.spec("daily", state.daily[1]).target
		local done = Quests.reroll(state, 1, MONDAY + DAY + 5, 9)
		assert(not done, "a complete quest is not rerolled")
		assert(Quests.reroll(state, 2, MONDAY + DAY + 5, 9), "a new day allows a reroll")
		assert(not Quests.reroll(state, 99, MONDAY + DAY + 5, 9), "bad index")
	end,
})

table.insert(tests, {
	name = "mastery: XP per round fielded, a top-4 bonus on the final board, levels and rewards",
	run = function()
		local gains = Mastery.matchGains({ cinder_arc = 4, flashline = 2 }, { "cinder_arc", "cinder_arc" }, true)
		local config = RetentionConfig.mastery
		expectEqual(gains.cinder_arc, 4 * config.perRound + config.top4Bonus, "rounds + top-4 bonus, once per unit")
		expectEqual(gains.flashline, 2 * config.perRound, "rounds only")
		local lower = Mastery.matchGains({ cinder_arc = 4 }, { "cinder_arc" }, false)
		assert(lower.cinder_arc < gains.cinder_arc, "top 4 earns more")
		expectEqual(Mastery.levelFor(0), 1, "level 1")
		expectEqual(Mastery.levelFor(config.levels[3]), 3, "level 3 at its threshold")
		expectEqual(Mastery.levelFor(1e9), #config.levels, "top level")
		local mastery = {}
		local reached = Mastery.add(mastery, "flashline", config.levels[5])
		expectEqual(mastery.flashline.level, 5, "level after a big gain")
		expectEqual(#reached, 4, "levels 2-5 reached")
		local fifth = reached[4]
		expectEqual(fifth.reward.cosmetic, "mastery_badge_flashline_silver", "unit id filled in")
		expectEqual(fifth.reward.title, "mastery_adept", "title at level 5")
		expectEqual(Mastery.toNext(1e9), 0, "nothing past the top")
	end,
})

table.insert(tests, {
	name = "profile: new, from old flags, from a version-1 save, and from a newer version",
	run = function()
		local now = MONDAY + 100
		local fresh, saveable = ProfileSchema.migrate(nil, now)
		expectEqual(fresh.v, ProfileSchema.VERSION, "version")
		expectEqual(fresh.account.level, 1, "level 1")
		assert(saveable, "a new profile can be saved")
		assert(ProfileSchema.isEmpty(fresh), "a new profile is empty")
		-- An old PlayerFlags entry keeps what it knew.
		local fromFlags =
			ProfileSchema.migrate(nil, now, { tutorialSeen = true, funnel = { joined = true, queued = true } })
		expectEqual(fromFlags.flags.tutorialSeen, true, "tutorial seen kept")
		expectEqual(fromFlags.flags.funnel.queued, true, "funnel kept")
		local fromStoredFlags = ProfileSchema.migrate({ tutorialSeen = true }, now)
		expectEqual(fromStoredFlags.flags.tutorialSeen, true, "a stored flags-shaped entry")
		-- A version-1 save missing a newer field gets it filled, keeping its progress.
		local old = { v = 1, account = { level = 4, xp = 10, totalXp = 500 }, coins = 30, titles = { rookie = true } }
		local migrated = ProfileSchema.migrate(old, now)
		expectEqual(migrated.account.totalXp, 500, "progress kept")
		expectEqual(migrated.coins, 30, "coins kept")
		assert(migrated.quests and migrated.days and migrated.stats, "missing fields filled")
		-- A newer version is loaded but never saved here.
		local _, newerSaveable = ProfileSchema.migrate({ v = ProfileSchema.VERSION + 1, account = {} }, now)
		assert(not newerSaveable, "a newer profile is read-only")
	end,
})

table.insert(tests, {
	name = "save guard: never an empty or regressed profile over saved progress",
	run = function()
		local now = MONDAY
		local saved = ProfileSchema.migrate(nil, now)
		saved.account.totalXp = 900
		saved.account.level = 6
		saved.coins = 120
		local empty = ProfileSchema.migrate(nil, now)
		assert(not ProfileSchema.safeToReplace(saved, empty), "empty over progress refused")
		assert(not ProfileSchema.safeToReplace(saved, nil), "nil refused")
		assert(not ProfileSchema.safeToReplace(saved, { v = 1 }), "invalid refused")
		local regressed = ProfileSchema.migrate(nil, now)
		regressed.account.totalXp = 400
		regressed.coins = 5
		assert(not ProfileSchema.safeToReplace(saved, regressed), "less XP refused")
		local spent = ProfileSchema.migrate(nil, now)
		spent.account.totalXp = 950
		spent.coins = 10 -- coins may go down (spent)
		assert(ProfileSchema.safeToReplace(saved, spent), "more XP, fewer coins is fine")
		assert(ProfileSchema.safeToReplace(nil, empty), "anything over nothing")
		assert(ProfileSchema.safeToReplace({ tutorialSeen = true }, empty), "over an old flags entry")
		local older = ProfileSchema.migrate(nil, now)
		older.v = 0
		older.account.totalXp = 2000
		assert(not ProfileSchema.safeToReplace(saved, older), "older version refused")
	end,
})

return tests
