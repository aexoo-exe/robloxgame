-- Items (docs/items.md): the rules and every item's numbers. Item display names, effect text and
-- icon looks are in ItemSkinConfig, keyed by the same ids, so items can be renamed without touching
-- logic. Every number is a starting value (placeholder).
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.

local Category = table.freeze({
	Offensive = "OFFENSIVE",
	Ability = "ABILITY",
	Defensive = "DEFENSIVE",
})

local function item(category: string)
	return { category = category }
end

return table.freeze({
	Category = Category,

	rules = table.freeze({
		slotsPerUnit = 3, -- items one unit can hold (never two of the same)
		inventoryCap = 10, -- items a player can hold unequipped; picking needs a free place
	}),

	-- Item choices: after these rounds (at Results) every player is offered this many items to pick
	-- one from, whatever the fight's result. An offer is one item of each category in this order, then
	-- (round 20) any other item; never the same item twice in one offer. The offer stays open through
	-- the next Preparation; unpicked, its first item is taken when Preparation ends.
	offers = table.freeze({
		rounds = table.freeze({ [3] = 3, [8] = 3, [12] = 3, [16] = 3, [20] = 4 }),
		categories = table.freeze({ Category.Offensive, Category.Ability, Category.Defensive }),
	}),

	-- The items, by id. Phase 3 adds each item's numbers.
	items = table.freeze({
		sunforged_blade = item(Category.Offensive),
		runaway_clock = item(Category.Offensive),
		golden_arrow = item(Category.Offensive),
		oni_cutter = item(Category.Offensive),
		ghouls_mask = item(Category.Offensive),
		thousand_year_staff = item(Category.Ability),
		strange_fruit = item(Category.Ability),
		cursebreaker_spear = item(Category.Ability),
		tattered_grimoire = item(Category.Ability),
		giants_serum = item(Category.Ability),
		steel_arm = item(Category.Defensive),
		straw_doll = item(Category.Defensive),
		cloud_cloak = item(Category.Defensive),
		sand_gourd = item(Category.Defensive),
		conquerors_will = item(Category.Defensive),
	}),
})
