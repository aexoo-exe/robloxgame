--!nocheck
-- Exports vetted Creator Store models as plain data for scripts/models-build.luau, in Roblox Studio
-- EDIT mode, without running anything. Run it in the command bar or through the Studio MCP (Edit
-- data model) while the receiver runs (lune run scripts/models-receive), after filling JOBS.
--
-- For each job it:
--   1. reads the model with game:GetObjects (unparented: nothing in it can run) and deletes every
--      Script, LocalScript and ModuleScript, plus sounds, lights, effects and click/prompt objects;
--   2. puts it in our frame: facing -Z (its root part's front, turned by `turn` degrees if
--      needed), feet at y = 0, centered on its root;
--   3. gives every visible part an anchor: by rig part names when the model is rigged (R15 / R6,
--      or a horse's shoulder and thigh chains), spreading along welds to attached pieces, then by
--      position around the torso for the rest;
--   4. records each part's shape, size, pose, color, material, transparency, mesh (MeshPart or
--      SpecialMesh: id, texture, scale, offset, vertex color) and decals, the bounding box of each
--      anchor's parts and the rig's joint positions;
--   5. POSTs the dump as JSON to the receiver (HttpEnabled is switched on only for the post and
--      restored at once).
-- Unions and SurfaceAppearance textures cannot be rebuilt from data; they are counted and skipped.

local JOBS = {
	-- { key = "boiling_crown", id = 12125701097, kind = "body" },
	-- { key = "horse", id = 5878963783, kind = "horse", drop = { "Seat", "Reins" } },
}
local RECEIVER = "http://127.0.0.1:34999/"

local HttpService = game:GetService("HttpService")
assert(not game:GetService("RunService"):IsRunning(), "export-models: stop the game first; edit mode only")

local STRIP = {
	"LuaSourceContainer",
	"Sound",
	"ParticleEmitter",
	"Beam",
	"Trail",
	"Light",
	"Fire",
	"Smoke",
	"Sparkles",
	"ClickDetector",
	"ProximityPrompt",
	"Animation",
	"AnimationController",
	"BillboardGui",
	"SurfaceGui",
}

-- Rig part names (lowercase, exact) per anchor, for rigged bodies.
local BODY_NAMES = {
	head = { "head", "neck", "lefteye", "righteye", "hair" },
	hips = { "torso", "uppertorso", "lowertorso", "humanoidrootpart" },
	leftArm = { "left arm", "leftupperarm", "leftlowerarm", "lefthand" },
	rightArm = { "right arm", "rightupperarm", "rightlowerarm", "righthand" },
	leftLeg = { "left leg", "leftupperleg", "leftlowerleg", "leftfoot" },
	rightLeg = { "right leg", "rightupperleg", "rightlowerleg", "rightfoot" },
}
local HORSE_LEG_ROOTS = { "lshoulder", "rshoulder", "lthigh", "rthigh" }

local function round(n: number): number
	return math.floor(n * 10000 + 0.5) / 10000
end
local function v3(v: Vector3)
	return { round(v.X), round(v.Y), round(v.Z) }
end
local function cframe(cf: CFrame)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return {
		round(x),
		round(y),
		round(z),
		round(r00),
		round(r01),
		round(r02),
		round(r10),
		round(r11),
		round(r12),
		round(r20),
		round(r21),
		round(r22),
	}
end
local function color(c: Color3)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

-- The first BasePart named `name` inside `root` (a name can also be a Model, e.g. a saddle).
local function findPart(root: Instance, name: string): BasePart?
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

local function export(job: any): (string, string)
	local report = {}
	local objects = game:GetObjects("rbxassetid://" .. job.id)
	local holder = Instance.new("Model")
	for _, object in objects do
		object.Parent = holder -- the holder is not in the game: nothing runs
	end
	-- Scripts and side effects go first.
	local stripped = {}
	for _, descendant in holder:GetDescendants() do
		for _, class in STRIP do
			if descendant:IsA(class) then
				stripped[descendant.ClassName] = (stripped[descendant.ClassName] or 0) + 1
				descendant:Destroy()
				break
			end
		end
	end
	for class, count in stripped do
		table.insert(report, string.format("removed %d %s", count, class))
	end

	local drop = {}
	for _, name in job.drop or {} do
		drop[string.lower(name)] = true
	end
	local parts, unions, surfaceAppearances = {}, 0, 0
	for _, descendant in holder:GetDescendants() do
		if descendant:IsA("UnionOperation") then
			unions += 1
		elseif descendant:IsA("BasePart") and not descendant:IsA("TrussPart") then
			local lower = string.lower(descendant.Name)
			if descendant.Transparency < 0.98 and not drop[lower] and lower ~= "humanoidrootpart" then
				table.insert(parts, descendant)
			end
			if descendant:FindFirstChildOfClass("SurfaceAppearance") then
				surfaceAppearances += 1
			end
		end
	end

	-- Our frame: the root's rotation (turned by job.turn), centered on the root, feet at y = 0.
	-- `job.root` names the part to use when the default one is tilted.
	local root = (job.root and findPart(holder, job.root))
		or holder:FindFirstChild("HumanoidRootPart", true)
		or holder:FindFirstChild("LowerTorso", true)
		or holder:FindFirstChild("Torso", true)
	if not root then
		local largest = nil
		for _, part in parts do
			if not largest or part.Size.Magnitude > largest.Size.Magnitude then
				largest = part
			end
		end
		root = largest
	end
	local frame = CFrame.new(root.Position) * root.CFrame.Rotation * CFrame.Angles(0, math.rad(job.turn or 0), 0)
	if frame.UpVector.Y < 0.9 then
		table.insert(report, "WARNING: the root is not upright; check the result")
	end
	local minY, maxY = math.huge, -math.huge
	local rel = {}
	for _, part in parts do
		local cf = frame:ToObjectSpace(part.CFrame)
		rel[part] = cf
		local s = part.Size / 2
		for _, corner in
			{
				Vector3.new(s.X, s.Y, s.Z),
				Vector3.new(-s.X, s.Y, s.Z),
				Vector3.new(s.X, -s.Y, s.Z),
				Vector3.new(s.X, s.Y, -s.Z),
				Vector3.new(-s.X, -s.Y, s.Z),
				Vector3.new(-s.X, s.Y, -s.Z),
				Vector3.new(s.X, -s.Y, -s.Z),
				Vector3.new(-s.X, -s.Y, -s.Z),
			}
		do
			local y = (cf * corner).Y
			minY, maxY = math.min(minY, y), math.max(maxY, y)
		end
	end
	local lift = CFrame.new(0, -minY, 0)
	for part, cf in rel do
		rel[part] = lift * cf
	end
	local function framed(position: Vector3): Vector3
		return lift * frame:PointToObjectSpace(position)
	end

	-- Anchors.
	local anchor = {}
	local edges = {} -- welds: pieces attached to a part share its anchor
	local motors = {}
	for _, descendant in holder:GetDescendants() do
		if descendant:IsA("Motor6D") then
			table.insert(motors, descendant)
		elseif
			(descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint"))
			and descendant.Part0
			and descendant.Part1
		then
			edges[descendant.Part0] = edges[descendant.Part0] or {}
			edges[descendant.Part1] = edges[descendant.Part1] or {}
			table.insert(edges[descendant.Part0], descendant.Part1)
			table.insert(edges[descendant.Part1], descendant.Part0)
		end
	end
	local joints = {}
	if job.kind == "horse" then
		-- Motor children of each leg root belong to that leg; the rest is the body.
		local children = {}
		for _, motor in motors do
			if motor.Part0 and motor.Part1 then
				children[motor.Part0] = children[motor.Part0] or {}
				table.insert(children[motor.Part0], motor.Part1)
			end
		end
		local legs = {}
		for _, motor in motors do
			local name = motor.Part1 and string.lower(motor.Part1.Name)
			if name and table.find(HORSE_LEG_ROOTS, name) then
				local joint = framed((motor.Part0.CFrame * motor.C0).Position)
				-- front left, front right, back left, back right (front is -Z, left is -X)
				local index = (if joint.Z < 0 then 0 else 2) + (if joint.X < 0 then 1 else 2)
				legs[index] = { root = motor.Part1, joint = joint }
			end
		end
		for index, leg in legs do
			joints["horseLeg" .. index] = v3(leg.joint)
			local stack = { leg.root }
			while #stack > 0 do
				local part = table.remove(stack)
				anchor[part] = "horseLeg" .. index
				for _, child in children[part] or {} do
					table.insert(stack, child)
				end
			end
		end
		for _, part in parts do
			anchor[part] = anchor[part] or "horse"
		end
		local saddle = findPart(holder, "Saddle")
		local seat = findPart(holder, "Seat")
		local top = saddle or seat
		if top then
			joints.seat = round(framed(top.Position).Y + top.Size.Y / 2 * 0.6)
		end
		local head = findPart(holder, "Head")
		if head then
			joints.head = v3(framed(head.Position))
			joints.headSize = v3(head.Size)
		end
		local body = findPart(holder, "MiddleBody") or root
		joints.bodyY = round(framed(body.Position).Y)
	else
		-- Rig names seed the anchors (only when the model has a Motor6D rig: unrigged names lie).
		if #motors >= 4 then
			for _, part in parts do
				local lower = string.lower(part.Name)
				for name, list in BODY_NAMES do
					if table.find(list, lower) then
						anchor[part] = name
					end
				end
			end
		end
		-- Other pieces of a rigged model join the rig group whose box holds them, or the nearest
		-- (welds can chain a chest piece to an arm, so they are not followed).
		local seedBoxes = {}
		for part, name in anchor do
			local box = seedBoxes[name]
				or {
					min = Vector3.new(math.huge, math.huge, math.huge),
					max = Vector3.new(-math.huge, -math.huge, -math.huge),
				}
			local s = part.Size / 2
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local p = rel[part] * Vector3.new(x * s.X, y * s.Y, z * s.Z)
						box.min = box.min:Min(p)
						box.max = box.max:Max(p)
					end
				end
			end
			seedBoxes[name] = box
		end
		if next(seedBoxes) then
			for _, part in parts do
				if not anchor[part] then
					local c = rel[part].Position
					local best, bestDistance = nil, math.huge
					for name, box in seedBoxes do
						local outside = (box.min - c):Max(Vector3.zero) + (c - box.max):Max(Vector3.zero)
						local volume = (box.max - box.min).X * (box.max - box.min).Y * (box.max - box.min).Z
						local distance = outside.Magnitude + volume * 1e-9 -- inside two boxes: the smaller wins
						if distance < bestDistance then
							best, bestDistance = name, distance
						end
					end
					anchor[part] = best
				end
			end
		end
		-- The rest by position around the torso (the hips parts, else the largest part).
		local torso = {
			min = Vector3.new(math.huge, math.huge, math.huge),
			max = Vector3.new(-math.huge, -math.huge, -math.huge),
		}
		local function grow(box, cf: CFrame, size: Vector3)
			local s = size / 2
			for _, corner in
				{
					Vector3.new(s.X, s.Y, s.Z),
					Vector3.new(-s.X, -s.Y, -s.Z),
					Vector3.new(-s.X, s.Y, s.Z),
					Vector3.new(s.X, -s.Y, -s.Z),
				}
			do
				local p = cf * corner
				box.min = box.min:Min(p)
				box.max = box.max:Max(p)
			end
		end
		local seeded = false
		for part, name in anchor do
			if name == "hips" then
				grow(torso, rel[part], part.Size)
				seeded = true
			end
		end
		if not seeded then
			local named = holder:FindFirstChild("Torso", true)
			local largest = if named and table.find(parts, named) then named else nil
			if not largest then
				for _, part in parts do
					if not largest or part.Size.Magnitude > largest.Size.Magnitude then
						largest = part
					end
				end
			end
			grow(torso, rel[largest], largest.Size)
		end
		local height = maxY - minY
		local cx = (torso.min.X + torso.max.X) / 2
		local halfWidth = (torso.max.X - torso.min.X) / 2
		local hipY = if job.hip then job.hip * height else torso.min.Y
		for _, part in parts do
			if not anchor[part] then
				local c = rel[part].Position
				if c.Y > torso.max.Y - 0.04 * height and math.abs(c.X - cx) < halfWidth * 0.8 then
					anchor[part] = "head"
				elseif math.abs(c.X - cx) > halfWidth * 0.92 and c.Y > hipY - 0.3 * height then
					anchor[part] = if c.X < cx then "leftArm" else "rightArm"
				elseif c.Y < hipY then
					anchor[part] = if c.X < cx then "leftLeg" else "rightLeg"
				else
					anchor[part] = "hips"
				end
			end
		end
		-- Rig joints, when there are motors between the anchors.
		for _, motor in motors do
			if motor.Part0 and motor.Part1 and anchor[motor.Part0] and anchor[motor.Part1] then
				local from, to = anchor[motor.Part0], anchor[motor.Part1]
				if from == "hips" and to ~= "hips" and not joints[to] then
					joints[to] = v3(framed((motor.Part0.CFrame * motor.C0).Position))
				end
			end
		end
	end

	-- Bounding box of each anchor's parts.
	local boxes = {}
	for _, part in parts do
		local name = anchor[part]
		local box = boxes[name]
			or {
				min = Vector3.new(math.huge, math.huge, math.huge),
				max = Vector3.new(-math.huge, -math.huge, -math.huge),
				count = 0,
			}
		local s = part.Size / 2
		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					local p = rel[part] * Vector3.new(x * s.X, y * s.Y, z * s.Z)
					box.min = box.min:Min(p)
					box.max = box.max:Max(p)
				end
			end
		end
		box.count += 1
		boxes[name] = box
	end
	local boxData = {}
	for name, box in boxes do
		boxData[name] = { min = v3(box.min), max = v3(box.max), count = box.count }
	end

	-- Parts.
	local out = {}
	local counts = {}
	for _, part in parts do
		local entry = {
			a = anchor[part],
			n = part.Name,
			z = v3(part.Size),
			p = cframe(rel[part]),
			c = color(part.Color),
			m = part.Material.Name,
			t = round(part.Transparency),
		}
		if part:IsA("WedgePart") then
			entry.s = "Wedge"
		elseif part:IsA("CornerWedgePart") then
			entry.s = "CornerWedge"
		elseif part:IsA("Part") then
			entry.s = part.Shape.Name
		else
			entry.s = "Block"
		end
		if part:IsA("MeshPart") then
			local native = part.MeshSize
			entry.k = {
				type = "FileMesh",
				id = part.MeshId,
				tex = part.TextureID,
				scale = v3(
					Vector3.new(
						part.Size.X / math.max(native.X, 1e-4),
						part.Size.Y / math.max(native.Y, 1e-4),
						part.Size.Z / math.max(native.Z, 1e-4)
					)
				),
				native = true,
			}
		else
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				entry.k = {
					type = mesh.MeshType.Name,
					id = mesh.MeshId,
					tex = mesh.TextureId,
					scale = v3(mesh.Scale),
					offset = v3(mesh.Offset),
					vertex = v3(mesh.VertexColor),
					native = mesh.MeshType == Enum.MeshType.FileMesh,
				}
			end
		end
		local decals = {}
		for _, child in part:GetChildren() do
			if child:IsA("Decal") then
				table.insert(decals, { child.Texture, child.Face.Name, round(child.Transparency), color(child.Color3) })
			end
		end
		if #decals > 0 then
			entry.d = decals
		end
		counts[entry.a] = (counts[entry.a] or 0) + 1
		table.insert(out, entry)
	end
	local anchorCounts = {}
	for name, count in counts do
		table.insert(anchorCounts, name .. " " .. count)
	end
	table.sort(anchorCounts)
	table.insert(
		report,
		string.format(
			"%d parts kept (%s); %d unions and %d SurfaceAppearances skipped; height %.1f studs",
			#out,
			table.concat(anchorCounts, ", "),
			unions,
			surfaceAppearances,
			maxY - minY
		)
	)
	holder:Destroy()

	local dump = HttpService:JSONEncode({
		key = job.key,
		id = job.id,
		kind = job.kind,
		height = round(maxY - minY),
		boxes = boxData,
		joints = joints,
		parts = out,
	})
	return dump, table.concat(report, "; ")
end

local lines = {}
for _, job in JOBS do
	local ok, dump, report = pcall(export, job)
	if not ok then
		table.insert(lines, job.key .. ": FAILED " .. tostring(dump))
		continue
	end
	local before = HttpService.HttpEnabled
	pcall(function()
		HttpService.HttpEnabled = true
	end)
	local posted, problem = pcall(function()
		return HttpService:PostAsync(RECEIVER .. job.key, dump)
	end)
	pcall(function()
		HttpService.HttpEnabled = before
	end)
	table.insert(
		lines,
		string.format(
			"%s: %s; posted %s (%d bytes)%s",
			job.key,
			report,
			tostring(posted),
			#dump,
			if posted then "" else " " .. tostring(problem)
		)
	)
end
local result = table.concat(lines, "\n")
print(result)
return result
