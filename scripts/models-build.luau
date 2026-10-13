-- Builds the game's model data from vetted Creator Store model dumps: reads
-- docs/references/catalog/models/dumps/<key>.json (scripts/studio/export-models.luau, received by
-- scripts/models-receive) and writes src/shared/UnitModels/<key>.luau, a GENERATED pure-data module
-- the client builds the figure from (Figure). Run from the repository root:
--   lune run scripts/models-build              every dump
--   lune run scripts/models-build <key> ...    only these
--
-- The data holds only what is needed to draw the model: each part's anchor, shape, size, pose
-- (lengths as fractions of the model's height), color, material, transparency, mesh (type, mesh
-- and texture ids, scale, offset, vertex color) and decals. No script or code from the model is
-- ever kept. For a body it also works out the figure proportions that put the figure's anchors on
-- the model's joints (hips, shoulders, head); for a horse, the seat, body height, leg joints, bit
-- and saddle, and a paint role per part (coat, coat shade, socks, muzzle, mane, hoof, saddle, bag) so each
-- rider's horse can be recolored (HorseLookConfig).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local DUMPS = "docs/references/catalog/models/dumps"
local OUT = "src/shared/UnitModels"

-- Torso part names of R15 / R6 rigs (and plain models that name their torso).
local TORSO_NAMES = { ["torso"] = true, ["uppertorso"] = true, ["lowertorso"] = true }

-- The horse model's original colors, by paint role (5878963783: flat-colored parts).
local HORSE_ROLES = {
	["124,92,70"] = "coat",
	["112,83,63"] = "coatShade",
	["202,203,209"] = "socks",
	["74,54,41"] = "mane",
	["27,42,53"] = "hoof",
}

local function r4(n: number): number
	return math.floor(n * 10000 + 0.5) / 10000
end

local function fmt(n: number): string
	local text = string.format("%.4f", n)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	if text == "-0" then
		text = "0"
	end
	return text
end

local function list(numbers: { number }): string
	local parts = {}
	for _, n in numbers do
		table.insert(parts, fmt(n))
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function quote(text: string): string
	return string.format("%q", text)
end

local function center(box: any, axis: number): number
	return (box.min[axis] + box.max[axis]) / 2
end

-- Proportions (fractions of height) that put the figure's anchors on the body's joints.
local function bodyProportions(dump: any): any
	local H, boxes, joints = dump.height, dump.boxes, dump.joints
	local function shoulder(side: string)
		local box = boxes[side .. "Arm"]
		local width = box.max[1] - box.min[1]
		local joint = joints[side .. "Arm"]
		local x = if joint then joint[1] else center(box, 1)
		local y = if joint then joint[2] else box.max[2] - width / 2
		return math.abs(x), y, width, y - box.min[2]
	end
	local function hip(side: string)
		local box = boxes[side .. "Leg"]
		local joint = joints[side .. "Leg"]
		local x = if joint then joint[1] else center(box, 1)
		local y = if joint then joint[2] else box.max[2]
		return math.abs(x), y, box.max[1] - box.min[1]
	end
	local lsx, lsy, law, lal = shoulder("left")
	local rsx, rsy, raw, ral = shoulder("right")
	local lhx, lhy, llw = hip("left")
	local rhx, rhy, rlw = hip("right")
	local shoulderX, shoulderY = (lsx + rsx) / 2, (lsy + rsy) / 2
	local armWidth = (law + raw) / 2
	local hipY = (lhy + rhy) / 2
	local torsoWidth = math.max(2 * shoulderX - armWidth, 0.1 * H)
	local torsoHeight = shoulderY - hipY + armWidth / 2
	local head = boxes.head
	local headSize = head.max[2] - head.min[2]
	local headCenter = center(head, 2)
	local hips = boxes.hips
	return {
		legLength = hipY / H,
		legWidth = (llw + rlw) / 2 / H,
		legSpacing = (lhx + rhx) / 2 / H,
		torsoHeight = torsoHeight / H,
		torsoWidth = torsoWidth / H,
		torsoDepth = (hips.max[3] - hips.min[3]) / H,
		neck = (headCenter - hipY - torsoHeight - headSize / 2) / H,
		headSize = headSize / H,
		armLength = (lal + ral) / 2 / H,
		armWidth = armWidth / H,
		handReach = (lal + ral) / 2 / H,
	}
end

local function build(key: string)
	local dump = serde.decode("json", fs.readFile(DUMPS .. "/" .. key .. ".json"))
	local H = dump.height
	local horse = dump.kind == "horse"

	-- A body with named torso parts is re-anchored by position around that torso: model authors
	-- reuse rig names for decorations (chest plates named "RightHand"), so names alone mislead.
	-- Above the torso and within its width: head. Outside its width, above the knees: an arm.
	-- Below the hips: a leg. Otherwise: the hips. (Bodies without a named torso keep the grouping
	-- made at export, which already went by position.)
	local moved = 0
	local torso = nil
	if not horse then
		for _, part in dump.parts do
			if TORSO_NAMES[string.lower(part.n)] then
				local half = { part.z[1] / 2, part.z[2] / 2, part.z[3] / 2 }
				local min = { part.p[1] - half[1], part.p[2] - half[2], part.p[3] - half[3] }
				local max = { part.p[1] + half[1], part.p[2] + half[2], part.p[3] + half[3] }
				if torso then
					for i = 1, 3 do
						torso.min[i] = math.min(torso.min[i], min[i])
						torso.max[i] = math.max(torso.max[i], max[i])
					end
				else
					torso = { min = min, max = max }
				end
			end
		end
	end
	if torso then
		local cx = (torso.min[1] + torso.max[1]) / 2
		local halfWidth = (torso.max[1] - torso.min[1]) / 2
		local hipY, topY = torso.min[2], torso.max[2]
		for _, part in dump.parts do
			local x, y = part.p[1], part.p[2]
			local outside = math.abs(x - cx) > halfWidth * 1.02
			local anchor
			if y > topY and not outside then
				anchor = "head"
			elseif outside and y > hipY - 0.3 * H then
				anchor = if x < cx then "leftArm" else "rightArm"
			elseif y < hipY then
				anchor = if x < cx then "leftLeg" else "rightLeg"
			else
				anchor = "hips"
			end
			if anchor ~= part.a then
				part.a = anchor
				moved += 1
			end
		end
		-- The anchors' boxes follow the new grouping.
		local boxes = {}
		for _, part in dump.parts do
			local box = boxes[part.a]
				or { min = { math.huge, math.huge, math.huge }, max = { -math.huge, -math.huge, -math.huge } }
			for i = 1, 3 do
				box.min[i] = math.min(box.min[i], part.p[i] - part.z[i] / 2)
				box.max[i] = math.max(box.max[i], part.p[i] + part.z[i] / 2)
			end
			boxes[part.a] = box
		end
		boxes.hips = torso
		dump.boxes = boxes
	end

	local lines = {
		"-- GENERATED by scripts/models-build.luau from a vetted Creator Store model (scripts/studio/",
		"-- export-models.luau). Do not edit by hand. Pure data: the figure is built from it (Figure);",
		"-- no script from the model is kept. Lengths are fractions of the model's height.",
		"-- Part: a = anchor, s = shape, z = size, p = pose (position, then rotation matrix), c = color,",
		"-- m = material, t = transparency, k = mesh, d = decals, r = paint role (horses).",
		"",
		"return {",
		string.format("\tkey = %s,", quote(key)),
		string.format("\tsource = %d, -- Creator Store asset id", dump.id),
		string.format("\tkind = %s,", quote(dump.kind)),
	}
	if horse then
		local j = dump.joints
		local legs = {}
		for i = 1, 4 do
			local joint = j["horseLeg" .. i]
			table.insert(legs, string.format("\t\t%s,", list({ joint[1] / H, joint[2] / H, joint[3] / H })))
		end
		-- The bit: low on the front of the head, either side.
		local head, size = j.head, j.headSize
		local saddle = nil
		for _, part in dump.parts do
			if part.n == "Saddle" then
				saddle = part
			end
		end
		table.insert(lines, string.format("\tseat = %s,", fmt(j.seat / H)))
		table.insert(lines, string.format("\tbodyY = %s,", fmt(j.bodyY / H)))
		table.insert(lines, "\tlegs = { -- joints: front left, front right, back left, back right")
		for _, line in legs do
			table.insert(lines, line)
		end
		table.insert(lines, "\t},")
		table.insert(
			lines,
			string.format(
				"\tbit = %s, -- the right side; the left mirrors it",
				list({ (head[1] + size[1] * 0.45) / H, (head[2] - size[2] * 0.3) / H, (head[3] - size[3] * 0.35) / H })
			)
		)
		if saddle then
			table.insert(
				lines,
				string.format(
					"\tsaddle = { center = %s, size = %s },",
					list({ saddle.p[1] / H, saddle.p[2] / H, saddle.p[3] / H }),
					list({ saddle.z[1] / H, saddle.z[2] / H, saddle.z[3] / H })
				)
			)
		end
	else
		local p = bodyProportions(dump)
		table.insert(lines, "\tproportions = {")
		for _, name in
			{
				"legLength",
				"legWidth",
				"legSpacing",
				"torsoHeight",
				"torsoWidth",
				"torsoDepth",
				"neck",
				"headSize",
				"armLength",
				"armWidth",
				"handReach",
			}
		do
			table.insert(lines, string.format("\t\t%s = %s,", name, fmt(p[name])))
		end
		table.insert(lines, "\t},")
	end

	table.insert(lines, "\tparts = {")
	local counts = {}
	for _, part in dump.parts do
		local pose = part.p
		local fields = {
			string.format("a = %s", quote(part.a)),
			string.format("s = %s", quote(part.s)),
			string.format("z = %s", list({ part.z[1] / H, part.z[2] / H, part.z[3] / H })),
			string.format(
				"p = %s",
				list({
					pose[1] / H,
					pose[2] / H,
					pose[3] / H,
					pose[4],
					pose[5],
					pose[6],
					pose[7],
					pose[8],
					pose[9],
					pose[10],
					pose[11],
					pose[12],
				})
			),
			string.format("c = %s", list(part.c)),
			string.format("m = %s", quote(part.m)),
		}
		if part.t and part.t > 0 then
			table.insert(fields, string.format("t = %s", fmt(part.t)))
		end
		local k = part.k
		if k then
			local scale = if k.native then { k.scale[1] / H, k.scale[2] / H, k.scale[3] / H } else k.scale
			local mesh = {
				string.format("type = %s", quote(k.type)),
				string.format("id = %s", quote(k.id or "")),
				string.format("scale = %s", list(scale)),
			}
			if k.native then
				table.insert(mesh, "native = true")
			end
			if k.tex and k.tex ~= "" then
				table.insert(mesh, string.format("tex = %s", quote(k.tex)))
			end
			if k.offset and (k.offset[1] ~= 0 or k.offset[2] ~= 0 or k.offset[3] ~= 0) then
				table.insert(
					mesh,
					string.format("offset = %s", list({ k.offset[1] / H, k.offset[2] / H, k.offset[3] / H }))
				)
			end
			if k.vertex and (k.vertex[1] ~= 1 or k.vertex[2] ~= 1 or k.vertex[3] ~= 1) then
				table.insert(mesh, string.format("vertex = %s", list(k.vertex)))
			end
			table.insert(fields, "k = { " .. table.concat(mesh, ", ") .. " }")
		end
		if part.d then
			local decals = {}
			for _, decal in part.d do
				table.insert(decals, string.format("{ %s, %s, %s }", quote(decal[1]), quote(decal[2]), fmt(decal[3])))
			end
			table.insert(fields, "d = { " .. table.concat(decals, ", ") .. " }")
		end
		if horse then
			local role = HORSE_ROLES[table.concat(part.c, ",")]
			if part.n == "HeadS" then
				role = "muzzle"
			elseif part.n == "Saddle" then
				role = "saddle"
			elseif part.n == "Bag" then
				role = "bag"
			end
			if role then
				table.insert(fields, string.format("r = %s", quote(role)))
			end
		end
		counts[part.a] = (counts[part.a] or 0) + 1
		table.insert(lines, "\t\t{ " .. table.concat(fields, ", ") .. " },")
	end
	table.insert(lines, "\t},")
	table.insert(lines, "}")
	if not fs.isDir(OUT) then
		fs.writeDir(OUT)
	end
	fs.writeFile(OUT .. "/" .. key .. ".luau", table.concat(lines, "\n") .. "\n")
	local summary = {}
	for name, count in counts do
		table.insert(summary, name .. " " .. count)
	end
	table.sort(summary)
	print(
		string.format(
			"%s: %d parts (%s)%s",
			key,
			#dump.parts,
			table.concat(summary, ", "),
			if moved > 0 then string.format("; %d torso pieces moved to the hips", moved) else ""
		)
	)
end

local keys = process.args
if #keys == 0 then
	keys = {}
	for _, name in fs.readDir(DUMPS) do
		local key = string.match(name, "^([%w_]+)%.json$")
		if key and key ~= "ping" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
end
for _, key in keys do
	build(key)
end
