-- Placeholder trait symbols (TraitIconConfig): every trait in the roster has one, and no two look
-- alike (unique letters and colors; origins and classes use different shapes).

local TraitIconConfig = require("../src/shared/TraitIconConfig")
local UnitConfig = require("../src/shared/UnitConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local SHAPES = { circle = true, diamond = true, square = true }

local tests = {}

table.insert(tests, {
	name = "every origin and class in the roster has a well-formed symbol, and no symbol is unused",
	run = function()
		local used = {}
		for id, unit in UnitConfig do
			used[unit.origin] = "origin"
			assert(TraitIconConfig[unit.origin], id .. ": no symbol for origin " .. unit.origin)
			for _, class in unit.classes do
				used[class] = "class"
				assert(TraitIconConfig[class], id .. ": no symbol for class " .. class)
			end
		end
		for traitId, entry in TraitIconConfig do
			assert(used[traitId], traitId .. " has a symbol but no character has the trait")
			assert(type(entry.name) == "string" and entry.name ~= "", traitId .. " needs a name")
			assert(
				type(entry.letters) == "string" and #entry.letters >= 1 and #entry.letters <= 2,
				traitId .. " needs one or two letters"
			)
			assert(SHAPES[entry.shape], traitId .. ": unknown shape " .. tostring(entry.shape))
			assert(type(entry.color) == "table" and #entry.color == 3, traitId .. " needs a { r, g, b } color")
			for _, channel in entry.color do
				assert(channel >= 0 and channel <= 255 and channel == math.floor(channel), traitId .. " color channel")
			end
			expectEqual(entry.shape, if used[traitId] == "origin" then "circle" else "diamond", traitId .. " shape")
		end
	end,
})

table.insert(tests, {
	name = "trait symbols are easy to tell apart: unique letters and unique colors",
	run = function()
		local letters, colors = {}, {}
		for traitId, entry in TraitIconConfig do
			assert(not letters[entry.letters], traitId .. " shares letters with " .. tostring(letters[entry.letters]))
			letters[entry.letters] = traitId
			local key = table.concat(entry.color, ",")
			assert(not colors[key], traitId .. " shares its color with " .. tostring(colors[key]))
			colors[key] = traitId
		end
	end,
})

return tests
