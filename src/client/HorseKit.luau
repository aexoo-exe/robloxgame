-- Builds a rider's horse as a list of part specs (the LookKit spec format) on the horse anchors
-- Figure moves: "horse" (the body's center; -Z is the front) and "horseLeg1".."horseLeg4" (the hip
-- and shoulder joints: front left, front right, back left, back right), so the legs stride with
-- the existing animation. Only math and data here: no instances. Presentation only.
--
-- The shape comes from FigureConfig.horse (fractions of the rider's height), the colors from a
-- HorseLookConfig entry. The reins run from the bit to the rider's resting hands.

local HorseKit = {}

export type Horse = {
	specs: { any },
	joints: { Vector3 }, -- leg joints in the body's space, in leg anchor order
	seat: number, -- the top of the back above the ground: where the rider sits
	bodyY: number, -- the body's center above the ground
}

local rad = math.rad
local V = Vector3.new
local CF = CFrame.new
local LEGS = { "horseLeg1", "horseLeg2", "horseLeg3", "horseLeg4" }

local function turnX(degrees: number): CFrame
	return CFrame.Angles(rad(degrees), 0, 0)
end

-- `look`: the HorseLookConfig colors (coat resolved). `c`: FigureConfig.horse. `h`: the rider's
-- height. `hands`: the rider's resting hands in the body's space (left, right), for the reins.
function HorseKit.build(look: any, c: any, h: number, hands: { Vector3 }?): Horse
	local specs = {}
	local function add(anchor: string, shape: string, size: Vector3, offset: CFrame, color: Color3, material: string?)
		table.insert(specs, {
			anchor = anchor,
			shape = shape,
			size = size,
			offset = offset,
			color = color,
			material = material or "SmoothPlastic",
			tinted = false,
			transparency = 0,
		})
	end
	local function segment(anchor: string, from: Vector3, to: Vector3, thickness: number, color: Color3)
		add(anchor, "Block", V(thickness, thickness, (to - from).Magnitude), CFrame.lookAt((from + to) / 2, to), color)
	end

	local coat = look.coat
	local bl, bw, bh = c.bodyLength * h, c.bodyWidth * h, c.bodyHeight * h
	local seat = c.backHeight * h
	local lw = c.legWidth * h
	local legLength = seat - bh + lw / 2
	local top = bh / 2

	-- Body: barrel, a deeper chest, hindquarters with a rounded croup, and withers.
	add("horse", "Block", V(bw, bh, bl * 0.62), CFrame.identity, coat)
	add("horse", "Block", V(bw * 0.96, bh * 1.18, bl * 0.24), CF(0, -bh * 0.04, -bl * 0.36), coat)
	add("horse", "Block", V(bw * 1.02, bh * 1.06, bl * 0.24), CF(0, bh * 0.02, bl * 0.36), coat)
	add("horse", "Ball", Vector3.one * bw * 1.04, CF(0, bh * 0.12, bl * 0.39), coat)
	add("horse", "Block", V(bw * 0.66, bh * 0.32, bl * 0.16), CF(0, bh * 0.6, -bl * 0.3), coat)

	-- An arched neck in two segments, the upper more upright.
	local nw = c.neckWidth * h
	local lower, upper = c.neckLower * h, c.neckUpper * h
	local neckBase = CF(0, bh * 0.45, -bl * 0.4) * turnX(-c.neckAngle)
	add("horse", "Block", V(nw, lower, nw * 1.35), neckBase * CF(0, lower / 2, 0), coat)
	local upperBase = neckBase * CF(0, lower, 0) * turnX(c.neckArch)
	add("horse", "Block", V(nw * 0.85, upper, nw * 1.15), upperBase * CF(0, upper / 2, 0), coat)
	local poll = upperBase * CF(0, upper, 0)

	-- Mane along the crest, with two strands falling to the right.
	add("horse", "Block", V(nw * 0.35, lower * 1.05, nw * 0.4), neckBase * CF(0, lower * 0.5, nw * 0.7), look.mane)
	add("horse", "Block", V(nw * 0.35, upper * 1.05, nw * 0.35), upperBase * CF(0, upper * 0.5, nw * 0.6), look.mane)
	add(
		"horse",
		"Block",
		V(nw * 0.15, lower * 1.1, nw * 0.45),
		neckBase * CF(nw * 0.45, lower * 0.42, nw * 0.45) * CFrame.Angles(0, 0, rad(-8)),
		look.mane
	)
	add(
		"horse",
		"Block",
		V(nw * 0.15, upper, nw * 0.4),
		upperBase * CF(nw * 0.42, upper * 0.5, nw * 0.4) * CFrame.Angles(0, 0, rad(-8)),
		look.mane
	)

	-- The head points forward and down from the poll: skull, muzzle, cheek, nostrils, eyes, ears,
	-- forelock and an optional blaze.
	local hl, hw = c.headLength * h, c.headWidth * h
	local head = CF(poll.Position) * turnX(-c.headTilt)
	add("horse", "Block", V(hw, hw * 1.05, hl * 0.55), head * CF(0, 0, -hl * 0.22), coat)
	add("horse", "Block", V(hw * 0.86, hw * 0.85, hl * 0.42), head * CF(0, -hw * 0.08, -hl * 0.62), look.muzzle)
	add("horse", "Block", V(hw * 0.9, hw * 0.5, hl * 0.35), head * CF(0, -hw * 0.42, -hl * 0.18), coat)
	add("horse", "Block", V(hw * 0.7, hw * 0.18, h * 0.012), head * CF(0, -hw * 0.05, -hl * 0.835), look.eyes)
	for _, x in { -1, 1 } do
		add(
			"horse",
			"Block",
			V(h * 0.012, hw * 0.2, hw * 0.24),
			head * CF(x * hw * 0.51, hw * 0.2, -hl * 0.2),
			look.eyes
		)
		add(
			"horse",
			"Wedge",
			V(hw * 0.22, hw * 0.55, hw * 0.3),
			head * CF(x * hw * 0.3, hw * 0.5, hl * 0.02) * turnX(c.headTilt) * CF(0, hw * 0.27, 0),
			coat
		)
	end
	add("horse", "Block", V(hw * 0.4, hw * 0.25, hw * 0.35), head * CF(0, hw * 0.55, -hl * 0.06), look.mane)
	if look.blaze then
		add("horse", "Block", V(hw * 0.26, h * 0.008, hl * 0.62), head * CF(0, hw * 0.53, -hl * 0.42), look.blaze)
	end

	-- A tail in three segments, falling from the croup.
	local tw = c.tailWidth * h
	local tail = CF(0, bh * 0.38, bl * 0.49) * turnX(-65)
	for _, piece in { { 0.11, 1.2, 1, 0 }, { 0.13, 1.5, 1.1, 30 }, { 0.13, 1.7, 1, 20 } } do
		local length = piece[1] * h
		tail = tail * turnX(piece[4])
		add("horse", "Block", V(tw * piece[2], length, tw * piece[3]), tail * CF(0, -length / 2, 0), look.mane)
		tail = tail * CF(0, -length, 0)
	end

	-- Legs: a strong upper leg, a slim lower leg (white if it has a sock) and a hoof.
	local joints = {}
	local socks = {}
	for _, index in look.socks or {} do
		socks[index] = true
	end
	for _, z in { -1, 1 } do -- front (-Z), then back
		for _, x in { -1, 1 } do
			table.insert(joints, V(x * (bw - lw) / 2, -bh / 2 + lw / 4, z * (bl / 2 - c.legInset * h)))
			local index = #joints
			local anchor = LEGS[index]
			add(anchor, "Block", V(lw * 1.25, legLength * 0.48, lw * 1.45), CF(0, -legLength * 0.22, 0), coat)
			add(
				anchor,
				"Block",
				V(lw * 0.78, legLength * 0.42, lw * 0.85),
				CF(0, -legLength * 0.66, 0),
				if socks[index] then Color3.fromRGB(240, 240, 236) else coat
			)
			add(anchor, "Block", V(lw, legLength * 0.11, lw * 1.15), CF(0, -legLength * 0.945, -lw * 0.06), look.hooves)
		end
	end

	-- Tack: blanket with an edge, girth, saddle (seat, pommel, cantle), stirrups.
	add("horse", "Block", V(bw * 1.12, bh * 0.6, h * 0.27), CF(0, bh * 0.22, 0), look.blanket)
	add("horse", "Block", V(bw * 1.14, bh * 0.07, h * 0.275), CF(0, -bh * 0.06, 0), look.trim)
	add("horse", "Block", V(bw * 1.03, bh, h * 0.035), CF(0, -bh * 0.02, -h * 0.06), look.tack)
	add("horse", "Block", V(bw * 0.86, h * 0.035, h * 0.2), CF(0, top + bh * 0.02 + h * 0.0175, 0), look.saddle)
	add("horse", "Block", V(bw * 0.46, h * 0.055, h * 0.035), CF(0, top + h * 0.05, -h * 0.095), look.saddle)
	add("horse", "Block", V(bw * 0.62, h * 0.06, h * 0.035), CF(0, top + h * 0.055, h * 0.095), look.saddle)
	for _, x in { -1, 1 } do
		local side = x * (bw * 0.56 + h * 0.008)
		add("horse", "Block", V(h * 0.012, h * 0.15, h * 0.022), CF(side, top - h * 0.06, -h * 0.01), look.tack)
		add(
			"horse",
			"Block",
			V(h * 0.035, h * 0.018, h * 0.05),
			CF(side, top - h * 0.14, -h * 0.01),
			look.metal,
			"Metal"
		)
	end

	-- The personal detail on the blanket.
	local pattern = look.pattern
	if pattern and pattern.kind == "stars" then
		for _, x in { -1, 1 } do
			for _, z in { -0.07, 0.07 } do
				add(
					"horse",
					"Block",
					V(h * 0.006, h * 0.032, h * 0.032),
					CF(x * (bw * 0.56 + h * 0.003), bh * 0.24, z * h) * turnX(45),
					pattern.color
				)
			end
		end
	elseif pattern and pattern.kind == "tassels" then
		for _, x in { -1, 1 } do
			for _, z in { -0.125, 0.125 } do
				add("horse", "Ball", Vector3.one * h * 0.028, CF(x * bw * 0.57, -bh * 0.11, z * h), pattern.color)
			end
		end
	end

	-- Bridle: noseband, cheek straps and browband; reins from the bit to the rider's hands.
	add("horse", "Block", V(hw * 0.92, hw * 0.12, hl * 0.12), head * CF(0, -hw * 0.05, -hl * 0.55), look.tack)
	for _, x in { -1, 1 } do
		add(
			"horse",
			"Block",
			V(h * 0.008, hw * 0.9, h * 0.014),
			head * CF(x * (hw * 0.5 + h * 0.004), 0, -hl * 0.36),
			look.tack
		)
	end
	add("horse", "Block", V(hw * 1.04, hw * 0.1, h * 0.012), head * CF(0, hw * 0.42, -hl * 0.02), look.tack)
	for i, x in { -1, 1 } do
		local bit = (head * CF(x * hw * 0.47, -hw * 0.3, -hl * 0.62)).Position
		local hand = if hands then hands[i] else V(x * bw * 0.3, top + h * 0.08, -h * 0.12)
		segment("horse", bit, hand, h * 0.01, look.tack)
	end

	return { specs = specs, joints = joints, seat = seat, bodyY = seat - bh / 2 }
end

return HorseKit
