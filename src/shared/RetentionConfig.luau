-- Retention v1 numbers (docs/design/retention.md): account XP and its level curve, the level-up
-- reward table, the quest pool, unit mastery and the soft currency. Rewards are cosmetic, titles or
-- progress only: nothing here changes a match. Bots never earn any of it. Cosmetic ids are stored
-- on the profile for now (no shop or equip UI for them yet); titles have display text below.

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

-- The level-up reward of level `level` (2-30): coins every level, plus a title, nameplate, profile
-- icon, board skin or a cosmetic hook on some levels.
local rewards = {}
local specials = {
	[2] = { title = "rookie" },
	[3] = { cosmetic = "icon_spark" },
	[4] = { cosmetic = "nameplate_steel" },
	[5] = { title = "contender" },
	[6] = { cosmetic = "icon_blade" },
	[7] = { cosmetic = "boardskin_dusk" },
	[8] = { cosmetic = "icon_flame" },
	[10] = { title = "tactician" },
	[12] = { cosmetic = "nameplate_jade" },
	[14] = { cosmetic = "emote_bow" },
	[15] = { title = "strategist" },
	[16] = { cosmetic = "icon_wave" },
	[18] = { cosmetic = "boardskin_sakura" },
	[20] = { title = "veteran" },
	[22] = { cosmetic = "nameplate_gold" },
	[24] = { cosmetic = "finisher_thunder" },
	[25] = { title = "warlord" },
	[26] = { cosmetic = "icon_crown" },
	[28] = { cosmetic = "boardskin_eclipse" },
	[30] = { title = "legend", cosmetic = "nameplate_legend" },
}
for level = 2, 30 do
	local reward = { coins = 40 + 10 * level }
	for key, value in specials[level] or {} do
		reward[key] = value
	end
	rewards[level] = reward
end

return deepFreeze({
	currencyName = "coins", -- the soft currency's placeholder name

	-- Account XP to go from `level` to the next: base + growth x (level - 1)^power. Fast early
	-- (level 2 in about one match), slower later. Past maxRewardLevel levels keep going, no rewards.
	xp = {
		base = 120,
		growth = 30,
		power = 1.35,
		maxRewardLevel = 30,
	},

	-- Account XP from one match (Progression.matchXp).
	matchXp = {
		base = 60, -- for finishing a Play match
		perRound = 4, -- per round survived
		-- by final placement (1st first); placements past the list get the last value
		placement = { 90, 70, 55, 45, 30, 20, 12, 8 },
		practiceShare = 0.4, -- Practice matches: this share of a Play match's XP
		leaverShare = 0.25, -- left early: this share of base + rounds (no placement bonus)
		leaverMinimum = 10, -- but never less than this (not zero)
		firstMatchOfDayCoins = 25, -- a small bonus for the day's first match (missing days costs nothing)
	},

	rewards = rewards,

	titles = {
		rookie = "Rookie",
		contender = "Contender",
		tactician = "Tactician",
		strategist = "Strategist",
		veteran = "Veteran",
		warlord = "Warlord",
		legend = "Legend",
		mastery_adept = "Adept",
		mastery_master = "Master",
	},

	-- Quests: 3 dailies and 3 weeklies a player gets from these pools (Quests.rotate), reset at 00:00
	-- UTC (weeklies on Monday). `stat` is what counts (Quests.STATS), `target` how much, `trait` a
	-- stat that names a trait (the trait is picked when the quest is rolled, from `traits`). Rewards:
	-- coins and account XP when claimed. All doable by a new player in one or a few matches.
	quests = {
		dailyCount = 3,
		weeklyCount = 3,
		rerollsPerDay = 1,
		traits = { "Hunters", "Corps", "Spirit", "Cursed", "Arcane", "Titans", "Shinobi", "Crew", "Heroes" },
		daily = {
			{ id = "d_play", stat = "matches", target = 2, coins = 60, xp = 80, text = "Play %d matches" },
			{ id = "d_top4", stat = "top4", target = 1, coins = 80, xp = 100, text = "Place top 4 in %d match" },
			{ id = "d_rounds", stat = "roundsWon", target = 5, coins = 60, xp = 80, text = "Win %d rounds" },
			{ id = "d_reroll", stat = "rerolls", target = 6, coins = 50, xp = 60, text = "Reroll the shop %d times" },
			{ id = "d_star2", stat = "star2", target = 3, coins = 60, xp = 80, text = "Upgrade %d units to 2 stars" },
			{
				id = "d_traits3",
				stat = "threeTraits",
				target = 3,
				coins = 70,
				xp = 90,
				text = "Fight %d rounds with 3 traits active",
			},
			{
				id = "d_trait_wins",
				stat = "traitWins",
				trait = true,
				target = 3,
				coins = 70,
				xp = 90,
				text = "Win %d rounds with %s active",
			},
		},
		weekly = {
			{ id = "w_play", stat = "matches", target = 10, coins = 250, xp = 300, text = "Play %d matches" },
			{ id = "w_top4", stat = "top4", target = 5, coins = 300, xp = 350, text = "Place top 4 in %d matches" },
			{ id = "w_rounds", stat = "roundsWon", target = 30, coins = 250, xp = 300, text = "Win %d rounds" },
			{ id = "w_star3", stat = "star3", target = 1, coins = 300, xp = 350, text = "Upgrade %d unit to 3 stars" },
			{
				id = "w_trait_wins",
				stat = "traitWins",
				trait = true,
				target = 12,
				coins = 280,
				xp = 320,
				text = "Win %d rounds with %s active",
			},
		},
	},

	-- Unit mastery: XP for each unit a player fields (Mastery.matchGains).
	mastery = {
		perRound = 5, -- per round the unit fought on the player's board
		top4Bonus = 20, -- per unit on the final board when the player placed top 4
		finalBonus = 5, -- per unit on the final board otherwise
		-- total XP needed for each level (level 1 at 0)
		levels = { 0, 50, 150, 300, 500, 800, 1200, 1700, 2300, 3000 },
		-- rewards by level: cosmetic badges and titles now; recolors and finishers are hooks for later
		-- (stored, not usable yet). "<unit>" becomes the unit id.
		rewards = {
			[3] = { cosmetic = "mastery_badge_<unit>_bronze" },
			[5] = { cosmetic = "mastery_badge_<unit>_silver", title = "mastery_adept" },
			[7] = { cosmetic = "mastery_badge_<unit>_gold" },
			[8] = { cosmetic = "mastery_recolor_<unit>" }, -- hook: VFX recolor, later
			[10] = { cosmetic = "mastery_finisher_<unit>", title = "mastery_master" }, -- hook: finisher, later
		},
	},
})
