-- Items (docs/items.md): the rules and every item's numbers. Item display names, effect text and
-- icon looks are in ItemSkinConfig, keyed by the same ids, so items can be renamed without touching
-- logic. Every number is a starting value (placeholder).
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.

return table.freeze({
	rules = table.freeze({
		slotsPerUnit = 3, -- items one unit can hold (never two of the same)
		inventoryCap = 10, -- items a player can hold unequipped; picking needs a free place
	}),

	-- The items, by id. Filled in phase 3.
	items = table.freeze({}),
})
