-- Catalog shortlist: finds R6-usable Roblox catalog items for each unit's avatar and builds the
-- local picker page. Run from the repository root:
--   lune run scripts/catalog-shortlist                 every unit in searches.json
--   lune run scripts/catalog-shortlist <unit_id> ...   only these units
--   lune run scripts/catalog-shortlist --refresh ...   search again even where results are cached
--   lune run scripts/catalog-shortlist --page          only rebuild the page from the cache
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
-- Seconds between requests, per service.
local GAPS = { catalog = 3, thumbnails = 1, cdn = 0.2 }
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
	{ suffix = " shirt", category = 3 },
	{ suffix = " pants", category = 3 },
	{ suffix = " face", category = 1 },
	{ suffix = "", category = 1 },
}

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
		local waitFor = (lastCall[service] or 0) + GAPS[service] - now()
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

local function shortlistUnit(search: any, refresh: boolean, picks: { [string]: any })
	local dir = ROOT .. "/" .. search.unit
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	local cachePath = dir .. "/shortlist.json"
	local cache = readJson(cachePath) or {}
	cache.searches = cache.searches or {}

	local queries = {}
	for _, plan in PLAN do
		table.insert(queries, { keyword = search.name .. plan.suffix, category = plan.category })
	end
	for _, extra in search.extra or {} do
		table.insert(queries, { keyword = search.name .. " " .. extra, category = 1 })
	end

	for _, query in queries do
		local key = query.keyword .. "|" .. query.category
		if refresh or not cache.searches[key] then
			print(string.format("  searching %q", query.keyword))
			local body, problem = get(
				string.format(
					"https://catalog.roblox.com/v1/search/items/details?Keyword=%s&Category=%d&Limit=30",
					net.urlEncode(query.keyword),
					query.category
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
	end

	-- Merge every search, best first per slot: name matches, then favorites, then search order.
	local seen, ranked = {}, {}
	local order = 0
	for _, query in queries do
		for _, item in cache.searches[query.keyword .. "|" .. query.category] or {} do
			order += 1
			if not seen[item.id] then
				seen[item.id] = true
				item.match = mentions(item.name, search.name)
				item.order = order
				table.insert(ranked, item)
			end
		end
	end
	table.sort(ranked, function(a, b)
		if a.match ~= b.match then
			return a.match
		end
		if (a.favorites or 0) ~= (b.favorites or 0) then
			return (a.favorites or 0) > (b.favorites or 0)
		end
		return a.order < b.order
	end)
	local slots = {}
	local thumbs = {}
	for _, item in ranked do
		local slot = SLOT_OF_TYPE[item.type]
		slots[slot] = slots[slot] or {}
		if #slots[slot] < PER_SLOT then
			table.insert(slots[slot], item)
			table.insert(thumbs, item.id)
		end
	end
	cache.slots = slots
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
			fetched = cache ~= nil and cache.slots ~= nil,
			slots = if cache and cache.slots then cache.slots else {},
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

local refresh, pageOnly = false, false
local wanted: { [string]: boolean } = {}
local anyWanted = false
for _, arg in process.args do
	if arg == "--refresh" then
		refresh = true
	elseif arg == "--page" then
		pageOnly = true
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
		if not anyWanted or wanted[search.unit] then
			table.insert(todo, search)
		end
	end
	for index, search in todo do
		print(string.format("[%d/%d] %s", index, #todo, search.unit))
		shortlistUnit(search, refresh, picks)
		writePage(config.units, picks) -- the page is usable while a long run goes on
	end
	print(string.format("Done in %d s.", now() - started))
end
writePage(config.units, picks)
print("Picker page: " .. ROOT .. "/index.html (open it in a browser)")
