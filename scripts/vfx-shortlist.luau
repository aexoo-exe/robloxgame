-- Creator Store VFX shortlist: finds free textures (decals) and VFX model packs that could replace
-- the plain neon shapes and default particles of the combat effects, grouped by the role they would
-- play (slash arcs, smoke, sparks, rings ...), and builds the local VFX picker page. Run from the
-- repository root:
--   lune run scripts/vfx-shortlist                   every role
--   lune run scripts/vfx-shortlist <role> ...        only these roles (slash, smoke, sparks, ...)
--   lune run scripts/vfx-shortlist --refresh ...     search again even where results are cached
--   lune run scripts/vfx-shortlist --page            only rebuild the page from the cache
--
-- The roles and their search terms are below (ROLES). Each term is searched in the Creator Store
-- (apis.roblox.com toolbox-service v2 assets:search, no login needed), in the decals category
-- (`images`) or the models category (`models`). Only free assets are kept. The best ~12 per role are
-- kept: names that match the role first, then verified creators, then the most upvotes, with a few
-- places held for model packs. For each it records the id (and for a decal the image id that
-- ParticleEmitter.Texture, Beam.Texture and Decal.Texture take), name, creator, votes, type, script
-- count, and whether the name suggests a flipbook (a grid sheet of frames), and downloads its
-- thumbnail.
--
-- This script only reads search results and thumbnails. It never downloads, inserts or runs an
-- asset: free models often carry malicious scripts. A model pack with scripts is flagged; when a
-- pick is vetted in Studio its scripts are deleted without running (scripts/studio/vet-models.luau).
--
-- Everything it writes stays in docs/references/catalog/ (gitignored):
--   vfx/<role>/search.json   cached searches and the shortlist
--   vfx/<role>/<id>.png      thumbnails
--   vfx-data.js              every role's shortlist, for the page
--   vfx.html                 the VFX picker page (copied from scripts/catalog/vfx.html)

local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local ROOT = "docs/references/catalog"
local PAGE_TEMPLATE = "scripts/catalog/vfx.html"
local KEEP = 12 -- candidates kept per role
local MODEL_SLOTS = 3 -- of those, places held for model packs (when any were found)
local PAGE_SIZE = 30 -- results read per search term
local THUMB_SIZE = "420x420"
local USER_AGENT = "robloxgame vfx shortlist (local dev tool)"
local SPACING = { search = 3, thumbnails = 1, cdn = 0.2 } -- seconds between requests
local MAX_ATTEMPTS = 6

-- The roles, in page order. `images`: terms searched as decals (textures); `models`: terms searched
-- as models (VFX packs and ready effects). `words`: name words that mark a result as on-topic.
local ROLES = {
	{
		key = "slash",
		title = "Slash arcs",
		use = "melee swing trails, slash waves, ultimate cuts",
		images = { "slash texture", "sword slash vfx", "anime slash" },
		models = { "sword slash vfx" },
		words = { "slash", "swing", "cut", "arc", "crescent" },
	},
	{
		key = "smoke",
		title = "Smoke",
		use = "death puffs, form-change puffs, dust on landings and slams",
		images = { "smoke texture", "smoke flipbook" },
		models = { "smoke vfx" },
		words = { "smoke", "dust", "puff", "cloud", "fog" },
	},
	{
		key = "sparks",
		title = "Sparks",
		use = "impact sparks, shield-break shards, charge sparkles",
		images = { "spark texture" },
		models = { "spark vfx" },
		words = { "spark", "sparkle", "glint", "star" },
	},
	{
		key = "rings",
		title = "Rings and shockwaves",
		use = "ground rings, cast bursts, slam rings",
		images = { "shockwave ring" },
		models = { "shockwave vfx" },
		words = { "shockwave", "ring", "wave", "circle", "shock" },
	},
	{
		key = "flashes",
		title = "Impact flashes",
		use = "the flash ball on hits and crits, cast releases",
		images = { "impact flash" },
		models = { "impact vfx" },
		words = { "impact", "flash", "hit", "burst", "glow" },
	},
	{
		key = "lightning",
		title = "Lightning",
		use = "electric abilities, chain beams, zaps",
		images = { "lightning texture" },
		models = { "lightning vfx" },
		words = { "lightning", "electric", "bolt", "thunder", "zap" },
	},
	{
		key = "energy",
		title = "Energy and orbs",
		use = "cast charge orbs, projectiles, energy beams",
		images = { "energy orb" },
		models = { "energy orb vfx" },
		words = { "energy", "orb", "ball", "sphere", "beam" },
	},
	{
		key = "fire",
		title = "Fire",
		use = "burns, flame abilities, fire projectiles",
		images = { "fire flipbook" },
		models = { "fire vfx" },
		words = { "fire", "flame", "flipbook", "blaze", "burn" },
	},
	{
		key = "explosions",
		title = "Explosions (flipbooks)",
		use = "big ability hits, ultimate releases",
		images = { "explosion flipbook" },
		models = { "explosion vfx" },
		words = { "explosion", "explode", "blast", "boom", "flipbook" },
	},
	{
		key = "cracks",
		title = "Ground cracks and decals",
		use = "slam and landing marks, ultimate ground marks",
		images = { "crack decal" },
		models = { "ground crack vfx" },
		words = { "crack", "crater", "ground", "cracked", "rubble" },
	},
	{
		key = "auras",
		title = "Auras",
		use = "transformations, buffs, ultimate wind-ups",
		images = { "aura texture" },
		models = { "aura vfx", "anime vfx pack" },
		words = { "aura", "energy", "power", "glow", "vfx" },
	},
}

-- Name words that suggest a flipbook (a grid sheet of frames for ParticleEmitter.FlipbookLayout).
local FLIPBOOK_WORDS =
	{ "flipbook", "flip book", "spritesheet", "sprite sheet", "sheet", "atlas", "frames", "sequence", "animated" }

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

-- The grid a flipbook name suggests ("8x8", "4x4" or "2x2"), or true for a flipbook of unknown
-- grid, or nil when the name does not suggest one.
local function flipbookOf(name: string?): (boolean, string?)
	local lowered = string.lower(name or "")
	local grid = string.match(lowered, "(%d+)%s*x%s*%d+")
	local layout = if grid == "2" or grid == "4" or grid == "8" then grid .. "x" .. grid else nil
	if layout then
		return true, layout
	end
	for _, word in FLIPBOOK_WORDS do
		if string.find(lowered, word, 1, true) then
			return true, nil
		end
	end
	return false, nil
end

-- The fields kept per candidate. `kind` is "image" (a decal: its `textureId` is the image) or
-- "model" (a pack or a ready effect).
local function record(item: any, kind: string): any
	local asset, creator, voting = item.asset or {}, item.creator or {}, item.voting or {}
	local counts = asset.instanceCounts or {}
	local flipbook, layout = flipbookOf(asset.name)
	return {
		id = asset.id,
		textureId = asset.textureId, -- decals only
		kind = kind,
		name = asset.name,
		creator = creator.name,
		verified = creator.verified == true,
		upVotes = voting.upVotes or 0,
		downVotes = voting.downVotes or 0,
		upPercent = voting.upVotePercent,
		scripts = if kind == "model" then (asset.scriptCount or counts.script or 0) else 0,
		hasScripts = kind == "model" and (asset.hasScripts == true or (asset.scriptCount or counts.script or 0) > 0),
		decals = counts.decal,
		meshParts = counts.meshPart,
		category = asset.categoryPath,
		flipbook = flipbook,
		layout = layout,
		updated = asset.updateTime,
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

local CATEGORIES = { images = "Decal", models = "Model" }

local function shortlist(role: any, refresh: boolean)
	local dir = ROOT .. "/vfx/" .. role.key
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	local cachePath = dir .. "/search.json"
	local cache = readJson(cachePath) or {}
	cache.searches = cache.searches or {}

	-- Searches are cached by "<kind>:<term>" (a term can be searched as decals and as models).
	local searched = {}
	for _, group in { "images", "models" } do
		local kind = if group == "images" then "image" else "model"
		for _, term in role[group] or {} do
			local cacheKey = kind .. ":" .. term
			table.insert(searched, cacheKey)
			if refresh or not cache.searches[cacheKey] then
				print(string.format("  searching %s %q", if kind == "image" then "decals" else "models", term))
				local body, problem = get(
					string.format(
						"https://apis.roblox.com/toolbox-service/v2/assets:search?searchCategoryType=%s&query=%s&maxPageSize=%d",
						CATEGORIES[group],
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
							table.insert(items, record(item, kind))
						end
					end
					cache.searches[cacheKey] = items
					writeJson(cachePath, cache)
				else
					print(string.format("  search %q failed (%s); a re-run tries again", term, tostring(problem)))
				end
			end
		end
	end

	-- Merge every search once. On-topic names first (a role word appears in the name; for models,
	-- the visual-effects category counts too), then verified creators, then upvotes, then search
	-- order. Up to MODEL_SLOTS places go to the best on-topic models; the rest are filled in rank
	-- order.
	local function relevant(item: any): boolean
		local lowered = string.lower(item.name or "")
		for _, word in role.words do
			if string.find(lowered, word, 1, true) then
				return true
			end
		end
		return item.kind == "model" and item.category == "visual-effects"
	end
	local seen, ranked, order = {}, {}, 0
	for _, cacheKey in searched do
		for _, item in cache.searches[cacheKey] or {} do
			order += 1
			if not seen[item.id] then
				seen[item.id] = true
				item.order = order
				item.relevant = relevant(item)
				item.flipbook, item.layout = flipbookOf(item.name) -- again: cached results take new rules
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
	local held, chosen, count = 0, {}, 0
	for _, item in ranked do
		if item.kind == "model" and item.relevant and held < MODEL_SLOTS then
			held += 1
			chosen[item] = true
			count += 1
		end
	end
	for _, item in ranked do
		if count >= KEEP then
			break
		end
		if not chosen[item] then
			chosen[item] = true
			count += 1
		end
	end
	local kept, ids = {}, {}
	for _, item in ranked do
		if chosen[item] then
			table.insert(kept, item)
			table.insert(ids, item.id)
		end
	end
	cache.shortlist = kept
	writeJson(cachePath, cache)
	downloadThumbnails(dir, ids)
end

-- vfx-data.js and vfx.html: every role with its cached shortlist.
local function writePage()
	local list = {}
	for _, role in ROLES do
		local cache = readJson(ROOT .. "/vfx/" .. role.key .. "/search.json")
		local shortlisted = if cache and cache.shortlist and #cache.shortlist > 0 then cache.shortlist else nil
		table.insert(list, {
			key = role.key,
			title = role.title,
			use = role.use,
			fetched = cache ~= nil,
			candidates = shortlisted, -- left out when empty (an empty table would encode as {})
		})
	end
	fs.writeFile(
		ROOT .. "/vfx-data.js",
		"window.VFX = " .. serde.encode("json", { generated = DateTime.now():toIsoDate(), roles = list }) .. ";\n"
	)
	fs.writeFile(ROOT .. "/vfx.html", fs.readFile(PAGE_TEMPLATE))
end

if not fs.isDir("scripts") or not fs.isFile(PAGE_TEMPLATE) then
	print("Run from the repository root (" .. PAGE_TEMPLATE .. " not found).")
	process.exit(1)
end
if not fs.isDir(ROOT) then
	fs.writeDir(ROOT)
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
for _, role in ROLES do
	known[role.key] = true
end
for key in wanted do
	if not known[key] then
		local keys = {}
		for _, role in ROLES do
			table.insert(keys, role.key)
		end
		print("Unknown role " .. key .. " (roles: " .. table.concat(keys, ", ") .. ")")
		process.exit(1)
	end
end

if not pageOnly then
	local started = now()
	local todo = {}
	for _, role in ROLES do
		if not anyWanted or wanted[role.key] then
			table.insert(todo, role)
		end
	end
	for index, role in todo do
		print(string.format("[%d/%d] %s", index, #todo, role.key))
		shortlist(role, refresh)
		writePage()
	end
	print(string.format("Done in %d s.", now() - started))
end
writePage()
print("VFX picker: " .. ROOT .. "/vfx.html (open it in a browser)")
