-- Item data rules (docs/items.md): item lists by category and item offers. Numbers are in
-- ItemConfig; what items do in a fight is ItemCombat.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local ItemConfig = if script then require(script.Parent.ItemConfig) else require("./ItemConfig")
local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")

local Items = {}

function Items.isItem(id: any): boolean
	return type(id) == "string" and ItemConfig.items[id] ~= nil
end

-- Item ids of `category` (every item if nil), sorted so a seed always gives the same offer.
function Items.ids(category: string?): { string }
	local ids = {}
	for id, entry in ItemConfig.items do
		if category == nil or entry.category == category then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- Rolls an item offer of `count` items with `rng`: one item of each category (ItemConfig.offers
-- order), then any other items; never the same item twice.
function Items.rollOffer(rng: SeededRandom.SeededRandom, count: number): { string }
	local offer = {}
	local function pickFrom(ids: { string })
		local open = {}
		for _, id in ids do
			if not table.find(offer, id) then
				table.insert(open, id)
			end
		end
		if #open > 0 then
			table.insert(offer, open[SeededRandom.nextInt(rng, #open)])
		end
	end
	for _, category in ItemConfig.offers.categories do
		if #offer < count then
			pickFrom(Items.ids(category))
		end
	end
	while #offer < count do
		local before = #offer
		pickFrom(Items.ids())
		if #offer == before then
			break -- fewer items than the offer size
		end
	end
	return offer
end

-- Items offered after `round` (0: none).
function Items.offerSize(round: number): number
	return ItemConfig.offers.rounds[round] or 0
end

return Items
