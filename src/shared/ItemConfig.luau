-- Items (docs/items.md): the rules and every item's numbers. Item display names, effect text and
-- icon looks are in ItemSkinConfig, keyed by the same ids, so items can be renamed without touching
-- logic. Every number is a starting value (placeholder). ItemCombat runs the effects.
--
-- Each item:
--   category  OFFENSIVE, ABILITY or DEFENSIVE (item choices offer one of each)
--   tags      recommendation tags; a unit's tags come from its classes (classTags)
--   stats     changes for the whole fight, like trait bonuses: { [stat] = { flat?, percent? } }
--             (Battle.StatFields; CritChance flat is a 0-1 chance)
--   effect    the item's special effect (ItemCombat), with its numbers; nil for stats only
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.

local Category = table.freeze({
	Offensive = "OFFENSIVE",
	Ability = "ABILITY",
	Defensive = "DEFENSIVE",
})

local function freezeAll(value)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			freezeAll(child)
		end
		table.freeze(value)
	end
	return value
end

local function percent(value: number)
	return { percent = value }
end

local function flat(value: number)
	return { flat = value }
end

return freezeAll({
	Category = Category,

	rules = {
		slotsPerUnit = 3, -- items one unit can hold (never two of the same)
		inventoryCap = 10, -- items a player can hold unequipped; picking needs a free place
	},

	-- Item choices: after these rounds (at Results) every player is offered this many items to pick
	-- one from, whatever the fight's result. An offer is one item of each category in this order, then
	-- (round 20) any other item; never the same item twice in one offer. The offer stays open through
	-- the next Preparation; unpicked, its first item is taken when Preparation ends.
	offers = {
		rounds = { [3] = 3, [8] = 3, [12] = 3, [16] = 3, [20] = 4 },
		categories = { Category.Offensive, Category.Ability, Category.Defensive },
	},

	-- Recommendation tags by class (a unit shows the tags of its classes, at most maxUnitTags).
	-- Items sharing a tag with the selected unit are highlighted; tags never block equipping.
	classTags = {
		Blade = { "Attack", "Crit" },
		Assassin = { "Crit", "Attack" },
		Marksman = { "Speed", "Attack" },
		Brawler = { "Tank", "Sustain" },
		Guardian = { "Tank" },
		Caster = { "Ability", "Mana" },
		Support = { "Mana", "Ability" },
	},
	maxUnitTags = 3,

	items = {
		-- Offensive --------------------------------------------------------------------------------
		-- The holder's abilities can crit (its own crit chance and crit damage).
		sunforged_blade = {
			category = Category.Offensive,
			tags = { "Attack", "Crit" },
			stats = { AD = percent(20), CritChance = flat(0.20) },
			effect = { abilityCrit = true },
		},
		-- Each basic attack adds attack speed for the rest of the fight, up to maxStacks.
		runaway_clock = {
			category = Category.Offensive,
			tags = { "Speed" },
			stats = { AttackSpeed = percent(10) },
			effect = { attackSpeedPercentPerAttack = 3, maxStacks = 12 },
		},
		-- Basic attacks lower the target's armor (SHRED) for a few seconds.
		golden_arrow = {
			category = Category.Offensive,
			tags = { "Crit", "Attack" },
			stats = { AD = percent(10), CritChance = flat(0.15) },
			effect = { armorShredPercent = 30, seconds = 3 },
		},
		-- More damage to enemies with more max health than the holder.
		oni_cutter = {
			category = Category.Offensive,
			tags = { "Attack", "Speed" },
			stats = { AD = percent(10), AttackSpeed = percent(10) },
			effect = { bonusDamagePercent = 20 },
		},
		-- Heals for a share of all damage dealt; once per fight, below a health threshold, a shield of
		-- a share of max health.
		ghouls_mask = {
			category = Category.Offensive,
			tags = { "Sustain", "Attack" },
			stats = { AD = percent(10) },
			effect = { lifestealPercent = 12, belowPercent = 40, shieldPercent = 15, shieldSeconds = 5 },
		},

		-- Ability ----------------------------------------------------------------------------------
		thousand_year_staff = {
			category = Category.Ability,
			tags = { "Ability" },
			stats = { AP = flat(40) },
		},
		-- Starting mana, and mana after each cast.
		strange_fruit = {
			category = Category.Ability,
			tags = { "Mana" },
			stats = {},
			effect = { startingMana = 20, manaPerCast = 10 },
		},
		-- Mana for each basic attack.
		cursebreaker_spear = {
			category = Category.Ability,
			tags = { "Mana", "Attack" },
			stats = { AD = percent(10), AP = flat(10) },
			effect = { manaPerAttack = 5 },
		},
		-- Ability damage burns (true damage, a share of the hit, over a few seconds) and the burning
		-- target receives less healing (WOUND).
		tattered_grimoire = {
			category = Category.Ability,
			tags = { "Ability" },
			stats = { AP = flat(15), MaxHealth = percent(10) },
			effect = { burnPercent = 15, burnSeconds = 4, healingReductionPercent = 33 },
		},
		-- A stack each time the holder attacks or is hit, up to maxStacks; at full stacks also armor
		-- and magic resist.
		giants_serum = {
			category = Category.Ability,
			tags = { "Ability", "Tank" },
			stats = {},
			effect = { attackDamagePercentPerStack = 2, abilityPowerPerStack = 2, maxStacks = 20, fullResist = 20 },
		},

		-- Defensive --------------------------------------------------------------------------------
		steel_arm = {
			category = Category.Defensive,
			tags = { "Tank" },
			stats = { MaxHealth = percent(35) },
		},
		-- When hit by a basic attack: magic damage (flat) to every enemy next to the holder, at most
		-- once every cooldown seconds.
		straw_doll = {
			category = Category.Defensive,
			tags = { "Tank" },
			stats = { Armor = flat(30) },
			effect = { damage = 40, cooldown = 2 },
		},
		-- Heals a share of max health every interval.
		cloud_cloak = {
			category = Category.Defensive,
			tags = { "Tank", "Sustain" },
			stats = { MR = flat(30) },
			effect = { healPercent = 2, interval = 2 },
		},
		-- Armor and magic resist for every enemy currently targeting the holder.
		sand_gourd = {
			category = Category.Defensive,
			tags = { "Tank" },
			stats = { Armor = flat(10), MR = flat(10) },
			effect = { resistPerAttacker = 10 },
		},
		-- Immune to stuns (single, area, holds) for the first seconds of the fight.
		conquerors_will = {
			category = Category.Defensive,
			tags = { "Speed", "Tank" },
			stats = { AttackSpeed = percent(15) },
			effect = { stunImmuneSeconds = 12 },
		},
	},
})
