-- Creator Store model shortlist: finds free Toolbox models that could replace a block-built look
-- (a giant, a form, a rider's horse) and builds the local models picker page. Run from the
-- repository root:
--   lune run scripts/model-shortlist                 every entry in searches.json "models"
--   lune run scripts/model-shortlist <key> ...       only these entries (a key is the unit id, or
--                                                    the unit id and its form: titanheart_titan)
--   lune run scripts/model-shortlist --refresh ...   search again even where results are cached
--   lune run scripts/model-shortlist --page          only rebuild the page from the cache
--
-- Reads the "models" list of docs/references/catalog/searches.json (local only, gitignored): per
-- entry a key, the unit id, an optional form, the reference image and search terms. Each term is
-- searched in the Creator Store models category (apis.roblox.com toolbox-service v2
-- assets:search, no login needed). Only free models are kept. The best ~10 per entry are kept:
-- verified creators first, then the most upvotes. For each it records the id, name, creator,
-- verification, votes, script count, MeshPart count, triangle count and last update, and
-- downloads its thumbnail.
--
-- This script only reads search results and thumbnails. It never downloads, inserts or runs a
-- model: free models often carry malicious scripts. Vetting a pick happens in Studio, without
-- running anything (scripts/studio/vet-models.luau).
--
-- Everything it writes stays in docs/references/catalog/ (gitignored):
--   models/<unit_id>/<key>.json   cached searches and the shortlist
--   models/<unit_id>/<id>.png     thumbnails
--   models-data.js                every entry's shortlist, for the page
--   models.html                   the models picker page (copied from scripts/catalog/models.html)

local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local ROOT = "docs/references/catalog"
local SEARCHES = ROOT .. "/searches.json"
local PAGE_TEMPLATE = "scripts/catalog/models.html"
local KEEP = 10 -- candidates kept per entry
local PAGE_SIZE = 30 -- results read per search term
local THUMB_SIZE = "420x420"
local USER_AGENT = "robloxgame model shortlist (local dev tool)"
local SPACING = { search = 3, thumbnails = 1, cdn = 0.2 } -- seconds between requests
local MAX_ATTEMPTS = 6
-- Search words that say nothing about the subject, ignored when ranking by name.
local GENERIC = { model = true, rigged = true, rideable = true, heavy = true, point = true, boss = true }

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

-- Is a search result free? (A missing price counts as free; any price above zero does not.)
local function isFree(item: any): boolean
	local product = item.creatorStoreProduct
	local quantity = product and product.purchasePrice and product.purchasePrice.quantity
	return not quantity or (quantity.significand or 0) == 0
end

-- The fields kept per candidate.
local function record(item: any): any
	local asset, creator, voting = item.asset or {}, item.creator or {}, item.voting or {}
	local counts = asset.instanceCounts or {}
	local mesh = asset.objectMeshSummary or {}
	return {
		id = asset.id,
		name = asset.name,
		creator = creator.name,
		verified = creator.verified == true,
		upVotes = voting.upVotes or 0,
		downVotes = voting.downVotes or 0,
		upPercent = voting.upVotePercent,
		scripts = asset.scriptCount or counts.script or 0,
		meshParts = counts.meshPart or 0,
		triangles = mesh.triangles,
		updated = asset.updateTime,
		category = asset.categoryPath,
	}
end

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

local function shortlist(entry: any, refresh: boolean)
	local dir = ROOT .. "/models/" .. entry.unit
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	local cachePath = dir .. "/" .. entry.key .. ".json"
	local cache = readJson(cachePath) or {}
	cache.searches = cache.searches or {}

	for _, term in entry.terms or {} do
		if refresh or not cache.searches[term] then
			print(string.format("  searching %q", term))
			local body, problem = get(
				string.format(
					"https://apis.roblox.com/toolbox-service/v2/assets:search?searchCategoryType=Model&query=%s&maxPageSize=%d",
					net.urlEncode(term),
					PAGE_SIZE
				),
				"search"
			)
			local decoded = if body then serde.decode("json", body) else nil
			if decoded and decoded.creatorStoreAssets then
				local items = {}
				for _, item in decoded.creatorStoreAssets do
					if item.asset and item.asset.id and isFree(item) then
						table.insert(items, record(item))
					end
				end
				cache.searches[term] = items
				writeJson(cachePath, cache)
			else
				print(string.format("  search %q failed (%s); a re-run tries again", term, tostring(problem)))
			end
		end
	end

	-- Merge every term once. Relevant names first (a word of the search terms, four letters or
	-- more, not a generic one, appears in the model's name), then verified creators, then upvotes,
	-- then search order.
	local words = {}
	for _, term in entry.terms or {} do
		for word in string.gmatch(string.lower(term), "%a+") do
			if #word >= 4 and not GENERIC[word] then
				words[word] = true
			end
		end
	end
	local function relevant(name: string?): boolean
		local lowered = string.lower(name or "")
		for word in words do
			if string.find(lowered, word, 1, true) then
				return true
			end
		end
		return false
	end
	local seen, ranked, order = {}, {}, 0
	for _, term in entry.terms or {} do
		for _, item in cache.searches[term] or {} do
			order += 1
			if not seen[item.id] then
				seen[item.id] = true
				item.order = order
				item.relevant = relevant(item.name)
				table.insert(ranked, item)
			end
		end
	end
	table.sort(ranked, function(a, b)
		if a.relevant ~= b.relevant then
			return a.relevant
		end
		if a.verified ~= b.verified then
			return a.verified
		end
		if a.upVotes ~= b.upVotes then
			return a.upVotes > b.upVotes
		end
		return a.order < b.order
	end)
	local kept, ids = {}, {}
	for i = 1, math.min(KEEP, #ranked) do
		table.insert(kept, ranked[i])
		table.insert(ids, ranked[i].id)
	end
	cache.shortlist = kept
	writeJson(cachePath, cache)
	downloadThumbnails(dir, ids)
end

-- models-data.js and models.html: every entry with its cached shortlist.
local function writePage(entries: { any })
	local list = {}
	for _, entry in entries do
		local cache = readJson(ROOT .. "/models/" .. entry.unit .. "/" .. entry.key .. ".json")
		local shortlisted = if cache and cache.shortlist and #cache.shortlist > 0 then cache.shortlist else nil
		table.insert(list, {
			key = entry.key,
			unit = entry.unit,
			form = entry.form,
			kind = entry.kind,
			reference = if entry.reference and fs.isFile("docs/references/" .. entry.reference)
				then "../" .. entry.reference
				else nil,
			fetched = cache ~= nil,
			candidates = shortlisted, -- left out when empty (an empty table would encode as {})
		})
	end
	fs.writeFile(
		ROOT .. "/models-data.js",
		"window.MODELS = " .. serde.encode("json", { generated = DateTime.now():toIsoDate(), entries = list }) .. ";\n"
	)
	fs.writeFile(ROOT .. "/models.html", fs.readFile(PAGE_TEMPLATE))
end

local config = readJson(SEARCHES)
if not config or not config.models then
	print("Missing or unreadable " .. SEARCHES .. ' (or it has no "models" list). Run from the repository root.')
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
for _, entry in config.models do
	known[entry.key] = true
end
for key in wanted do
	if not known[key] then
		print("Unknown key " .. key .. " (not in the models list of " .. SEARCHES .. ")")
		process.exit(1)
	end
end

if not pageOnly then
	local started = now()
	local todo = {}
	for _, entry in config.models do
		if not anyWanted or wanted[entry.key] then
			table.insert(todo, entry)
		end
	end
	for index, entry in todo do
		print(string.format("[%d/%d] %s", index, #todo, entry.key))
		shortlist(entry, refresh)
		writePage(config.models)
	end
	print(string.format("Done in %d s.", now() - started))
end
writePage(config.models)
print("Models picker: " .. ROOT .. "/models.html (open it in a browser)")
