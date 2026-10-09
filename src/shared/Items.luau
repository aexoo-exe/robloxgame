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

-- A number for display: whole numbers without decimals, others with up to two.
local function shown(value: number): string
	if value == math.floor(value) then
		return string.format("%d", value)
	end
	return (string.gsub(string.format("%.2f", value), "0+$", ""))
end

-- The value at a dot path ("stats.AD.percent") of an item's ItemConfig entry, or nil.
local function valueAt(entry, path: string): any
	local value = entry
	for key in string.gmatch(path, "[^%.]+") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[key]
	end
	return value
end

-- An item's effect text (ItemSkinConfig) with its current numbers filled in. `skinConfig` is
-- ItemSkinConfig (passed in, so this module stays free of display text).
function Items.describe(id: string, skinConfig): string
	local skin = skinConfig.items[id]
	local entry = ItemConfig.items[id]
	if not skin or not entry then
		return ""
	end
	return (
		string.gsub(skin.text, "{(%%?)([%w%.]+)}", function(scale, path)
			local value = valueAt(entry, path)
			if type(value) ~= "number" then
				return "?"
			end
			return shown(if scale == "%" then value * 100 else value)
		end)
	)
end

-- Recommendation tags of a unit type: its classes' tags (ItemConfig.classTags), in class order,
-- without repeats, at most ItemConfig.maxUnitTags. `classes` is the unit type's class list.
function Items.unitTags(classes: { string }): { string }
	local tags = {}
	for _, class in classes do
		for _, tag in ItemConfig.classTags[class] or {} do
			if #tags < ItemConfig.maxUnitTags and not table.find(tags, tag) then
				table.insert(tags, tag)
			end
		end
	end
	return tags
end

-- True if an item shares a recommendation tag with `tags`.
function Items.matches(id: string, tags: { string }): boolean
	local entry = ItemConfig.items[id]
	for _, tag in if entry then entry.tags or {} else {} do
		if table.find(tags, tag) then
			return true
		end
	end
	return false
end

local CATEGORIES = { OFFENSIVE = true, ABILITY = true, DEFENSIVE = true }

-- Checks the item config: categories, stats (with `statFields`, Battle.StatFields, when given),
-- effects only for items ItemCombat knows (`effects`, ItemCombat.effects, when given). Returns true,
-- or false and a reason.
function Items.validate(statFields: { [string]: any }?, effects: { [string]: any }?): (boolean, string?)
	for id, entry in ItemConfig.items do
		if not CATEGORIES[entry.category] then
			return false, id .. ": unknown category " .. tostring(entry.category)
		end
		for stat, change in entry.stats or {} do
			if statFields and not statFields[stat] then
				return false, id .. ": unknown stat " .. tostring(stat)
			end
			if type(change) ~= "table" or (type(change.flat) ~= "number" and type(change.percent) ~= "number") then
				return false, id .. ": " .. stat .. " needs flat or percent"
			end
		end
		if entry.effect ~= nil and effects and not effects[id] then
			return false, id .. ": has an effect but ItemCombat has no handler"
		end
	end
	return true
end

return Items
