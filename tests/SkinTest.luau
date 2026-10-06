-- SkinConfig holds everything players see about a character. Every unit needs an entry, and no
-- display name (character or ability) may appear in code, tests or the simulation anywhere else,
-- so renaming or reskinning a character stays a one-file change.

local fs = require("@lune/fs")

local SkinConfig = require("../src/shared/SkinConfig")
local UnitConfig = require("../src/shared/UnitConfig")

local SKIN_FILE = "src/shared/SkinConfig.luau"
local SEARCHED = { "src", "tests", "sim" }

-- Every .luau file under `directory`.
local function luauFiles(directory: string, into: { string })
	for _, name in fs.readDir(directory) do
		local path = directory .. "/" .. name
		if fs.isDir(path) then
			luauFiles(path, into)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(into, path)
		end
	end
	return into
end

-- A Lua pattern matching `text` as a whole word or phrase (not inside a longer word).
local function wordPattern(text: string): string
	local escaped = string.gsub(text, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	return "%f[%w_]" .. escaped .. "%f[^%w_]"
end

local tests = {}

table.insert(tests, {
	name = "every unit has a skin entry with a name, an ability name and a color, and nothing else does",
	run = function()
		local names = {}
		for id in UnitConfig do
			local skin = SkinConfig[id]
			assert(skin, id .. " has no skin entry")
			assert(type(skin.name) == "string" and skin.name ~= "", id .. " needs a display name")
			assert(type(skin.ability) == "string" and skin.ability ~= "", id .. " needs an ability display name")
			assert(type(skin.color) == "table" and #skin.color == 3, id .. " needs a { red, green, blue } color")
			for _, channel in skin.color do
				assert(type(channel) == "number" and channel >= 0 and channel <= 255, id .. " color out of range")
			end
			assert(not names[skin.name], "display name used twice: " .. skin.name)
			names[skin.name] = true
		end
		for id in SkinConfig do
			assert(UnitConfig[id], "skin entry for an unknown unit: " .. id)
		end
	end,
})

table.insert(tests, {
	name = "no display name appears outside SkinConfig",
	run = function()
		local displayNames = {}
		for _, skin in SkinConfig do
			table.insert(displayNames, skin.name)
			table.insert(displayNames, skin.ability)
		end
		local files = {}
		for _, directory in SEARCHED do
			luauFiles(directory, files)
		end
		assert(#files > 20, "test setup: too few files found")
		local found = {}
		for _, path in files do
			if path ~= SKIN_FILE then
				local text = fs.readFile(path)
				for _, name in displayNames do
					if string.find(text, wordPattern(name)) then
						table.insert(found, string.format("%s in %s", name, path))
					end
				end
			end
		end
		assert(#found == 0, "display names outside SkinConfig:\n  " .. table.concat(found, "\n  "))
	end,
})

return tests
