-- Catalog shortlist: finds R6-usable Roblox catalog items for each unit's avatar and builds the
-- local picker page. Run from the repository root:
--   lune run scripts/catalog-shortlist                 every unit in searches.json
--   lune run scripts/catalog-shortlist <unit_id> ...   only these units
--   lune run scripts/catalog-shortlist --refresh ...   search again even where results are cached
--   lune run scripts/catalog-shortlist --gaps          only the targeted outfit searches ("gaps" in
--                                                      searches.json), for every unit that has them
--   lune run scripts/catalog-shortlist --gaps <unit_id> ...   the same, for these units
--   lune run scripts/catalog-shortlist --page          only rebuild the page from the cache
--
-- Gap searches fill outfit holes: each query in a unit's "gaps" is searched as written and only
-- the slot's items are kept (shirt: classic shirts; pants: classic pants; hair: hair and hats;
-- face: face accessories and classic faces), up to GAP_PER_SLOT, shown on the page as their own
-- "outfit search" rows. A full run includes them too.
--
-- Reads docs/references/catalog/searches.json (local only, gitignored): for each unit id, the
-- character's name and extra keywords. For each unit it runs a few searches on the public catalog
-- API (name + hair / accessory / shirt / pants / face, the name alone, and the name + each extra
-- keyword), keeps only items an R6 avatar can wear (classic shirts, pants and faces, rigid
-- accessories; no layered clothing, bundles or dynamic heads), keeps the best few per slot
-- (items whose name matches first, then the most favorited), and downloads their thumbnails.
--
-- Everything it writes stays in docs/references/catalog/ (gitignored):
--   <unit_id>/shortlist.json   cached search results and the shortlist per slot
--   <unit_id>/<asset_id>.png   thumbnails
--   data.js                    every unit's shortlist and current picks, for the page
--   index.html                 the picker page (copied from scripts/catalog/picker.html)
-- A re-run only fetches what is missing: cached searches are reused (unless --refresh) and
-- existing thumbnails are kept. Requests are spaced out and back off politely on 429s, so a full
-- run takes a while.

local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local ROOT = "docs/references/catalog"
local SEARCHES = ROOT .. "/searches.json"
local PICKS_SOURCE = "src/shared/UnitAvatarPicks.luau"
local PICKER_TEMPLATE = "scripts/catalog/picker.html"
local PER_SLOT = 6 -- items kept per slot per unit
local THUMB_SIZE = "250x250"
local USER_AGENT = "robloxgame catalog shortlist (local dev tool)"
local GAP_PER_SLOT = 10 -- items kept per gap search slot
-- Seconds between requests, per service.
local SPACING = { catalog = 3, thumbnails = 1, cdn = 0.2 }
local MAX_ATTEMPTS = 6

-- R6-usable asset types and the slot each goes in (UnitAvatarPicks): classic clothing and faces,
-- and rigid accessories by HumanoidDescription slot.
local SLOT_OF_TYPE = {
	[11] = "shirt",
	[12] = "pants",
	[18] = "face",
	[8] = "Hat",
	[41] = "Hair",
	[42] = "Face",
	[43] = "Neck",
	[44] = "Shoulders",
	[45] = "Front",
	[46] = "Back",
	[47] = "Waist",
}

-- Catalog categories: 1 all, 3 clothing, 11 accessories. Hair and faces search "all" (the
-- accessories category ranks hair poorly; faces cannot be searched by keyword in body parts).
local PLAN = {
	{ suffix = " hair", category = 1 },
	{ suffix = " accessory", category = 11 },
	{ suffix = " shirt", category = 3, subcategory = 56 }, -- classic shirts only
	{ suffix = " pants", category = 3, subcategory = 57 }, -- classic pants only
	{ suffix = " face", category = 1 },
	{ suffix = "", category = 1 },
}

-- Gap search slots: the catalog category searched and the asset types kept.
local GAP_SLOTS = {
	shirt = { category = 3, subcategory = 56, types = { [11] = true }, label = "Shirt" },
	pants = { category = 3, subcategory = 57, types = { [12] = true }, label = "Pants" },
	hair = { category = 1, types = { [41] = true, [8] = true }, label = "Hair" },
	face = { category = 1, types = { [42] = true, [18] = true }, label = "Face" },
}

-- One catalog search. Subcategories: 56 classic shirts, 57 classic pants.
type Query = { keyword: string, category: number, subcategory: number? }

-- A search's key in the cache.
local function queryKey(query: Query): string
	return query.keyword .. "|" .. query.category .. (if query.subcategory then "|" .. query.subcategory else "")
end

local function now(): number
	return DateTime.now().unixTimestampMillis / 1000
end

local function readJson(path: string): any?
	if not fs.isFile(path) then
		return nil
	end
	local ok, value = pcall(serde.decode, "json", fs.readFile(path))
	return if ok then value else nil
end

local function writeJson(path: string, value: any)
	fs.writeFile(path, serde.encode("json", value, true))
end

-- A GET request, spaced out per service, retried with backoff on 429, 5xx and network errors.
local lastCall: { [string]: number } = {}
local function get(url: string, service: string): (string?, string?)
	for attempt = 1, MAX_ATTEMPTS do
		local waitFor = (lastCall[service] or 0) + SPACING[service] - now()
		if waitFor > 0 then
			task.wait(waitFor)
		end
		lastCall[service] = now()
		local ok, response = pcall(net.request, {
			url = url,
			method = "GET",
			headers = { ["User-Agent"] = USER_AGENT },
		})
		if ok and response.ok then
			return response.body, nil
		end
		local status = if ok then response.statusCode else 0
		if status ~= 0 and status ~= 429 and status < 500 then
			return nil, "HTTP " .. status
		end
		local retryAfter = if ok then tonumber(response.headers["retry-after"]) else nil
		local delay = retryAfter or math.min(60, 5 * 2 ^ (attempt - 1))
		print(
			string.format(
				"    %s, waiting %d s (attempt %d of %d)",
				if status == 0 then "network error" else "HTTP " .. status,
				delay,
				attempt,
				MAX_ATTEMPTS
			)
		)
		task.wait(delay)
	end
	return nil, "gave up after " .. MAX_ATTEMPTS .. " attempts"
end

-- The units' current picks (UnitAvatarPicks is plain data, so it loads here as is).
local function currentPicks(): { [string]: any }
	if not fs.isFile(PICKS_SOURCE) then
		return {}
	end
	local ok, picks = pcall(function()
		return luau.load(fs.readFile(PICKS_SOURCE), { debugName = PICKS_SOURCE })()
	end)
	if not ok then
		print("Could not read " .. PICKS_SOURCE .. ": " .. tostring(picks))
		return {}
	end
	return picks
end

local function pickedIds(pick: any?): { number }
	local ids = {}
	if pick then
		for _, key in { "shirt", "pants", "face" } do
			if pick[key] then
				table.insert(ids, pick[key])
			end
		end
		for _, accessory in pick.accessories or {} do
			table.insert(ids, accessory.id)
		end
	end
	return ids
end

local function lower(text: string): string
	return string.lower(text)
end

-- Does an item's name mention the character? The full name, or any word of four letters or more.
local function mentions(itemName: string, name: string): boolean
	local item = lower(itemName)
	if string.find(item, lower(name), 1, true) then
		return true
	end
	for word in string.gmatch(lower(name), "%S+") do
		if #word >= 4 and string.find(item, word, 1, true) then
			return true
		end
	end
	return false
end

-- Downloads the thumbnails of `ids` missing from `dir`. Pending thumbnails are left for a re-run.
local function downloadThumbnails(dir: string, ids: { number })
	local missing = {}
	for _, id in ids do
		if not fs.isFile(string.format("%s/%d.png", dir, id)) then
			table.insert(missing, id)
		end
	end
	for start = 1, #missing, 50 do
		local batch = {}
		for i = start, math.min(start + 49, #missing) do
			table.insert(batch, string.format("%d", missing[i]))
		end
		local body, problem = get(
			string.format(
				"https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=%s&format=Png",
				table.concat(batch, ","),
				THUMB_SIZE
			),
			"thumbnails"
		)
		local decoded = if body then serde.decode("json", body) else nil
		if not decoded then
			print("    thumbnails failed: " .. tostring(problem))
			continue
		end
		local pending = 0
		for _, thumb in decoded.data or {} do
			if thumb.state == "Completed" and thumb.imageUrl then
				local image = get(thumb.imageUrl, "cdn")
				if image then
					fs.writeFile(string.format("%s/%d.png", dir, thumb.targetId), image)
				end
			else
				pending += 1
			end
		end
		if pending > 0 then
			print(string.format("    %d thumbnails not ready yet; a re-run fetches them", pending))
		end
	end
end

local function shortlistUnit(search: any, refresh: boolean, gapsOnly: boolean, picks: { [string]: any })
	local dir = ROOT .. "/" .. search.unit
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	local cachePath = dir .. "/shortlist.json"
	local cache = readJson(cachePath) or {}
	cache.searches = cache.searches or {}

	local queries = {}
	for _, plan in PLAN do
		table.insert(
			queries,
			{ keyword = search.name .. plan.suffix, category = plan.category, subcategory = plan.subcategory }
		)
	end
	for _, extra in search.extra or {} do
		table.insert(queries, { keyword = search.name .. " " .. extra, category = 1 })
	end

	-- Runs (or reuses) one search; its R6-usable items are cached under keyword|category.
	local function run(query: Query)
		local key = queryKey(query)
		if not refresh and cache.searches[key] then
			return
		end
		print(string.format("  searching %q", query.keyword))
		local body, problem = get(
			string.format(
				"https://catalog.roblox.com/v1/search/items/details?Keyword=%s&Category=%d%s&Limit=30",
				net.urlEncode(query.keyword),
				query.category,
				if query.subcategory then "&Subcategory=" .. query.subcategory else ""
			),
			"catalog"
		)
		local decoded = if body then serde.decode("json", body) else nil
		if decoded and decoded.data then
			local items = {}
			for _, item in decoded.data do
				if item.itemType == "Asset" and SLOT_OF_TYPE[item.assetType] then
					table.insert(items, {
						id = item.id,
						name = item.name,
						creator = item.creatorName,
						type = item.assetType,
						price = item.price,
						favorites = item.favoriteCount,
					})
				end
			end
			cache.searches[key] = items
			writeJson(cachePath, cache) -- keep progress if the run stops
		else
			print(string.format("  search %q failed (%s); a re-run tries again", query.keyword, tostring(problem)))
		end
	end

	-- Every item of these searches once, best first: name matches, then favorites, then search
	-- order. `keep` filters by asset type.
	local function ranked(list: { Query }, keep: ((number) -> boolean)?): { any }
		local seen, result = {}, {}
		local order = 0
		for _, query in list do
			for _, item in cache.searches[queryKey(query)] or {} do
				order += 1
				if not seen[item.id] and (not keep or keep(item.type)) then
					seen[item.id] = true
					item.match = mentions(item.name, search.name)
					item.order = order
					table.insert(result, item)
				end
			end
		end
		table.sort(result, function(a, b)
			if a.match ~= b.match then
				return a.match
			end
			if (a.favorites or 0) ~= (b.favorites or 0) then
				return (a.favorites or 0) > (b.favorites or 0)
			end
			return a.order < b.order
		end)
		return result
	end

	local thumbs = {}
	if not gapsOnly then
		for _, query in queries do
			run(query)
		end
		local slots = {}
		for _, item in ranked(queries) do
			local slot = SLOT_OF_TYPE[item.type]
			slots[slot] = slots[slot] or {}
			if #slots[slot] < PER_SLOT then
				table.insert(slots[slot], item)
			end
		end
		cache.slots = slots
	end
	for _, list in cache.slots or {} do
		for _, item in list do
			table.insert(thumbs, item.id)
		end
	end

	-- Targeted outfit searches: one row per gap slot.
	local gaps = {}
	for _, gap in search.gaps or {} do
		local slot = GAP_SLOTS[gap.slot]
		if not slot then
			print("  unknown gap slot " .. tostring(gap.slot) .. " (use shirt, pants, hair or face)")
			continue
		end
		local list = {}
		for _, keyword in gap.queries or {} do
			table.insert(list, { keyword = keyword, category = slot.category, subcategory = slot.subcategory })
		end
		for _, query in list do
			run(query)
		end
		local items = {}
		for _, item in
			ranked(list, function(assetType)
				return slot.types[assetType] == true
			end)
		do
			if #items < GAP_PER_SLOT then
				table.insert(items, item)
				table.insert(thumbs, item.id)
			end
		end
		table.insert(gaps, { slot = gap.slot, label = slot.label, items = items })
	end
	cache.gaps = gaps
	writeJson(cachePath, cache)

	for _, id in pickedIds(picks[search.unit]) do
		table.insert(thumbs, id)
	end
	downloadThumbnails(dir, thumbs)
end

-- data.js and index.html: every unit in searches.json, with its cached shortlist and current picks.
local function writePage(searches: { any }, picks: { [string]: any })
	local units = {}
	for _, search in searches do
		local cache = readJson(ROOT .. "/" .. search.unit .. "/shortlist.json")
		table.insert(units, {
			unit = search.unit,
			name = search.name,
			reference = if fs.isFile("docs/references/" .. search.unit .. ".png")
				then "../" .. search.unit .. ".png"
				else nil,
			fetched = cache ~= nil and (cache.slots ~= nil or cache.gaps ~= nil),
			slots = if cache and cache.slots then cache.slots else {},
			gaps = if cache and cache.gaps then cache.gaps else {},
			current = picks[search.unit],
		})
	end
	local data = {
		generated = DateTime.now():toIsoDate(),
		units = units,
	}
	fs.writeFile(ROOT .. "/data.js", "window.CATALOG = " .. serde.encode("json", data) .. ";\n")
	fs.writeFile(ROOT .. "/index.html", fs.readFile(PICKER_TEMPLATE))
end

local config = readJson(SEARCHES)
if not config or not config.units then
	print("Missing or unreadable " .. SEARCHES .. " (run from the repository root).")
	process.exit(1)
end

local refresh, pageOnly, gapsOnly = false, false, false
local wanted: { [string]: boolean } = {}
local anyWanted = false
for _, arg in process.args do
	if arg == "--refresh" then
		refresh = true
	elseif arg == "--page" then
		pageOnly = true
	elseif arg == "--gaps" then
		gapsOnly = true
	else
		wanted[arg] = true
		anyWanted = true
	end
end
local known = {}
for _, search in config.units do
	known[search.unit] = true
end
for unit in wanted do
	if not known[unit] then
		print("Unknown unit id " .. unit .. " (not in " .. SEARCHES .. ")")
		process.exit(1)
	end
end

local picks = currentPicks()
if not pageOnly then
	local started = now()
	local todo = {}
	for _, search in config.units do
		local chosen = if anyWanted then wanted[search.unit] == true else true
		if chosen and (not gapsOnly or search.gaps) then
			table.insert(todo, search)
		end
	end
	if #todo == 0 then
		print(
			"Nothing to search" .. (if gapsOnly then " (no gaps for these units in " .. SEARCHES .. ")" else "") .. "."
		)
	end
	for index, search in todo do
		print(string.format("[%d/%d] %s%s", index, #todo, search.unit, if gapsOnly then " (gaps)" else ""))
		shortlistUnit(search, refresh, gapsOnly, picks)
		writePage(config.units, picks) -- the page is usable while a long run goes on
	end
	print(string.format("Done in %d s.", now() - started))
end
writePage(config.units, picks)
print("Picker page: " .. ROOT .. "/index.html (open it in a browser)")
