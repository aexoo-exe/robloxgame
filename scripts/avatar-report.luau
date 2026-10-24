-- The avatar curation report: per unit, what its catalog avatar is made of (UnitAvatarPicks and
-- UnitAvatarConfig tuning), for reviewing the picks later. It changes nothing. Run from the
-- repository root:
--   lune run scripts/avatar-report
-- Writes docs/references/avatar-report.md (gitignored, local only).
--
-- Columns: items (accessories + shirt + pants + face), accessories per slot, shirt / pants, skin,
-- scale (FigureConfig override x the avatar's own scale, CharacterLook's rule), whether a hand-built
-- fallback look exists (UnitLookConfig), tuned weapons / outfit, and clamp warnings. Accessory bounds
-- are measured on the server when it builds each avatar ("[UnitAvatars] <unit> clamped <accessory>
-- x<factor>" in the server output); paste those lines into docs/references/avatar-clamps.log and
-- they show in the report.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any

local OUTPUT = "docs/references/avatar-report.md"
local CLAMPS = "docs/references/avatar-clamps.log"

-- Loads a src/shared module with the Roblox datatypes its data uses and `script.Parent.X` requires.
local loaded = {}
local function load(name: string): any
	if loaded[name] ~= nil then
		return loaded[name]
	end
	local file = "src/shared/" .. name .. ".luau"
	local parent = setmetatable({}, {
		__index = function(_, child)
			return { __module = child }
		end,
	})
	local env = setmetatable({
		script = { Parent = parent },
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Enum = roblox.Enum,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		UDim2 = roblox.UDim2,
		require = function(target)
			assert(type(target) == "table" and target.__module, "unexpected require in " .. file)
			return load(target.__module)
		end,
	}, { __index = getfenv(1) })
	loaded[name] = luau.load(fs.readFile(file), { debugName = file, environment = env })()
	return loaded[name]
end

local Picks = load("UnitAvatarPicks")
local AvatarConfig = load("UnitAvatarConfig")
local LookConfig = load("UnitLookConfig")
local FigureConfig = load("FigureConfig")

-- Server clamp lines, by unit.
local clamps: { [string]: { string } } = {}
if fs.isFile(CLAMPS) then
	for line in string.gmatch(fs.readFile(CLAMPS), "[^\n]+") do
		local unit, rest = string.match(line, "%[UnitAvatars%] ([%w_]+) clamped (.+)")
		if unit then
			clamps[unit] = clamps[unit] or {}
			table.insert(clamps[unit], (string.gsub(rest, " %(over.*$", "")))
		end
	end
end

local function hex(color: any): string
	if typeof(color) ~= "Color3" then
		return "default"
	end
	return "#" .. string.lower(color:ToHex())
end

local ids = {}
for unitType in Picks do
	table.insert(ids, unitType)
end
table.sort(ids)

local rows, outliers = {}, {}
local defaultSkins = 0
local defaultSkin = AvatarConfig.defaultSkin
for _, unitType in ids do
	local entry = AvatarConfig.units[unitType]
	local slots, count = {}, 0
	for _, accessory in entry.accessories or {} do
		slots[accessory.slot] = (slots[accessory.slot] or 0) + 1
		count += 1
	end
	local slotNames = {}
	for slot in slots do
		table.insert(slotNames, slot)
	end
	table.sort(slotNames)
	local slotText = {}
	for _, slot in slotNames do
		table.insert(slotText, string.format("%s %d", slot, slots[slot]))
	end
	local items = count
		+ (if entry.shirt then 1 else 0)
		+ (if entry.pants then 1 else 0)
		+ (if entry.face then 1 else 0)
	local override = FigureConfig.characters[unitType]
	local scale = (if override and override.scale then override.scale else 1) * (entry.scale or 1)
	local fallback = LookConfig[unitType] ~= nil
	local tuned = {}
	if entry.weapons then
		table.insert(tuned, "weapons")
	end
	if entry.outfit then
		table.insert(tuned, "outfit")
	end
	if entry.colors then
		table.insert(tuned, "limb colors")
	end
	local skin = entry.skin
	local clampText = if clamps[unitType] then table.concat(clamps[unitType], "; ") else ""
	table.insert(
		rows,
		string.format(
			"| %s | %d | %s | %s | %s | %s | %.2f | %s | %s | %s |",
			unitType,
			items,
			if #slotText > 0 then table.concat(slotText, ", ") else "none",
			if entry.shirt then "yes" else "no",
			if entry.pants then "yes" else "no",
			if skin then hex(skin) else "default " .. hex(defaultSkin),
			scale,
			if fallback then "yes" else "no",
			if #tuned > 0 then table.concat(tuned, ", ") else "",
			clampText
		)
	)

	-- Possible outliers, for a look later (nothing is changed).
	local notes = {}
	if not slots.Hair and not slots.Hat then
		table.insert(notes, "no hair or hat accessory (bald avatar head)")
	end
	if count >= 5 then
		table.insert(notes, string.format("%d accessories (heavy, and more to go wrong)", count))
	end
	for slot, n in slots do
		if n >= 2 then
			table.insert(notes, string.format("%d %s accessories stacked", n, slot))
		end
	end
	if not entry.shirt and not entry.pants and not entry.outfit then
		table.insert(notes, "no shirt, pants or block outfit (plain limbs)")
	end
	if not fallback then
		table.insert(notes, "no hand-built fallback: a failed avatar shows the plain placeholder")
	end
	if not skin and not entry.colors then
		defaultSkins += 1 -- summarized once below, not per unit
	end
	if math.abs(scale - 1) > 1e-6 then
		table.insert(notes, string.format("scale %.2f", scale))
	end
	if clamps[unitType] then
		table.insert(notes, "accessory clamped on the server: " .. clampText)
	end
	if #notes > 0 then
		table.insert(outliers, string.format("- **%s**: %s", unitType, table.concat(notes, "; ")))
	end
end

local lines = {
	"# Avatar report (LOCAL ONLY: gitignored)",
	"",
	"Generated by `lune run scripts/avatar-report` from UnitAvatarPicks and UnitAvatarConfig. Nothing",
	"was changed. Clamp warnings come from " .. CLAMPS .. (if fs.isFile(CLAMPS)
		then " (found)."
		else ' (not found: paste the server\'s "[UnitAvatars] ... clamped" lines there).'),
	"",
	string.format("%d avatar units.", #ids),
	"",
	"| unit | items | accessories per slot | shirt | pants | skin | scale | fallback look | tuned | clamp warnings |",
	"|---|---|---|---|---|---|---|---|---|---|",
}
for _, row in rows do
	table.insert(lines, row)
end
table.insert(lines, "")
table.insert(lines, "## Possible outliers (for review; not changed)")
table.insert(lines, "")
table.insert(lines, string.format("%d of %d units use the default skin color (no `skin` tuning).", defaultSkins, #ids))
table.insert(lines, "")
for _, line in outliers do
	table.insert(lines, line)
end
if #outliers == 0 then
	table.insert(lines, "None.")
end
table.insert(lines, "")

if not fs.isDir("docs/references") then
	fs.writeDir("docs/references")
end
fs.writeFile(OUTPUT, table.concat(lines, "\n"))
print(string.format("wrote %s: %d units, %d with notes", OUTPUT, #ids, #outliers))
