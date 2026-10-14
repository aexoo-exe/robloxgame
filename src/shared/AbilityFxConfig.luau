-- Ability effects (client visuals only; src/client/AbilityFx.luau). Every ability's effect is
-- composed from its mechanics (the playback events and the ability's data: strikes, lines, cones,
-- areas, bounces, dashes, pulls, knockbacks, summons, heals, shields, buffs, debuffs, forms) and
-- drawn in its unit's element: a texture and shape vocabulary (`elements`) with the unit's two
-- colors (`units`). `signatures` hand-made effects override the generated one for a unit.
-- Nothing here changes fight timing or results.
--
-- Units: durations in seconds of fight time, sizes in studs, colors Color3.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

local function unit(element: string, primary: Color3, secondary: Color3)
	return { element = element, primary = primary, secondary = secondary }
end

local WHITE = rgb(245, 245, 250)
local STEEL = rgb(215, 220, 230)
local BLACK = rgb(28, 28, 34)

return deepFreeze({
	-- Elements: how an element draws each mechanic.
	--   beam      lines, bounces and ranged ability strikes: "straight" (a bright bar), "jagged"
	--             (zig-zag bolts), "wave" (a travelling crescent), "spiral" (rings twisting along),
	--             "wisp" (thin wavy dark strands), "stretch" (a limb that shoots out and snaps back)
	--   strike    a single-target ability hit: "bolt", "flame", "splash", "swirl", "burst",
	--             "slash" (crossed blade arcs), "shock" (shockwave and dust), "rings", "explode",
	--             "stretch"
	--   particle  the main particle (ImpactEffects kinds: spark, flame, ember, smoke, bubble, mote,
	--             puff, glow); `accent` a second one (optional)
	--   ground    the ground mark of areas: "crack", "scorch", "splash", "glyph", "clock", "rings",
	--             "smoke" or "none"
	--   swirl     areas also get a spiral of rings rising
	elements = {
		lightning = { beam = "jagged", strike = "bolt", particle = "spark", accent = "glow", ground = "scorch" },
		fire = { beam = "straight", strike = "flame", particle = "flame", accent = "ember", ground = "scorch" },
		water = { beam = "wave", strike = "splash", particle = "mote", accent = "bubble", ground = "splash" },
		wind = { beam = "spiral", strike = "swirl", particle = "mote", ground = "none", swirl = true },
		shadow = { beam = "wisp", strike = "burst", particle = "smoke", ground = "smoke" },
		cursed = { beam = "wisp", strike = "burst", particle = "smoke", accent = "mote", ground = "glyph" },
		blood = { beam = "wisp", strike = "slash", particle = "spark", ground = "none" },
		gravity = { beam = "straight", strike = "rings", particle = "mote", ground = "rings" },
		steam = { beam = "straight", strike = "burst", particle = "puff", ground = "smoke" },
		time = { beam = "straight", strike = "burst", particle = "mote", accent = "glow", ground = "clock" },
		ki = { beam = "straight", strike = "burst", particle = "glow", accent = "spark", ground = "none" },
		impact = { beam = "straight", strike = "shock", particle = "puff", accent = "spark", ground = "crack" },
		slash = { beam = "wave", strike = "slash", particle = "spark", ground = "none" },
		poison = { beam = "wisp", strike = "burst", particle = "bubble", accent = "smoke", ground = "splash" },
		magic = { beam = "straight", strike = "burst", particle = "mote", accent = "glow", ground = "glyph" },
		explosion = { beam = "straight", strike = "explode", particle = "flame", accent = "smoke", ground = "scorch" },
		rubber = { beam = "stretch", strike = "stretch", particle = "puff", ground = "none" },
	},

	-- Each roster unit's element and colors (primary: beams, cores, glows; secondary: particles,
	-- rings, accents), by unit id. Drafted from each ability and its reference notes; review freely.
	-- A unit not listed (and every creep, boss and summon) uses `default` in its faction color
	-- (AnimationConfig.factionColors).
	units = {
		-- Hunters
		flashline = unit("lightning", rgb(255, 222, 80), rgb(255, 150, 40)),
		cinder_arc = unit("fire", rgb(255, 120, 40), rgb(255, 215, 110)),
		thunder_nest = unit("lightning", rgb(120, 195, 255), WHITE),
		horizon_cut = unit("slash", rgb(40, 36, 44), rgb(215, 40, 55)),
		reelbreaker = unit("water", rgb(90, 200, 255), rgb(130, 225, 130)),
		-- Corps
		wolfstep = unit("slash", STEEL, rgb(130, 200, 255)),
		redline_cut = unit("slash", rgb(230, 60, 60), STEEL),
		cyclone_edge = unit("slash", STEEL, rgb(120, 205, 255)),
		snapfire = unit("fire", rgb(255, 110, 30), rgb(255, 222, 120)),
		-- Spirit
		spurshot = unit("wind", rgb(255, 212, 90), rgb(220, 140, 225)),
		orbit_breaker = unit("wind", rgb(225, 228, 238), rgb(235, 190, 80)),
		clockbreaker = unit("ki", rgb(150, 90, 225), rgb(235, 195, 80)),
		frozen_moment = unit("time", rgb(255, 212, 80), rgb(115, 225, 125)),
		restoration_strike = unit("ki", rgb(255, 150, 200), WHITE),
		-- Cursed
		ripcord_frenzy = unit("slash", rgb(255, 145, 40), STEEL),
		crimson_hunger = unit("blood", rgb(205, 25, 45), rgb(60, 12, 20)),
		shade_pack = unit("shadow", BLACK, rgb(95, 115, 210)),
		night_parade = unit("cursed", rgb(120, 45, 170), rgb(25, 18, 32)),
		severing_temple = unit("slash", rgb(185, 25, 45), BLACK),
		infinite_collapse = unit("gravity", rgb(90, 145, 255), rgb(255, 75, 75)),
		-- Arcane
		null_edge = unit("shadow", BLACK, rgb(205, 205, 215)),
		bitter_vapor = unit("poison", rgb(115, 225, 120), rgb(150, 55, 85)),
		starless_burst = unit("magic", rgb(255, 90, 110), rgb(235, 195, 95)),
		night_command = unit("shadow", rgb(125, 65, 185), rgb(150, 205, 245)),
		-- Titans
		iron_rush = unit("impact", rgb(225, 185, 115), rgb(205, 65, 55)),
		titanheart = unit("steam", rgb(250, 245, 235), rgb(255, 205, 80)),
		skyboulder = unit("impact", rgb(155, 115, 75), rgb(225, 205, 175)),
		boiling_crown = unit("steam", WHITE, rgb(215, 75, 60)),
		-- Shinobi
		blooming_aid = unit("ki", rgb(255, 140, 190), rgb(125, 230, 150)),
		marsh_fortress = unit("water", rgb(95, 170, 255), rgb(235, 120, 120)),
		volt_spear = unit("lightning", rgb(175, 195, 255), rgb(155, 95, 235)),
		mirror_script = unit("lightning", rgb(175, 215, 255), WHITE),
		echo_legion = unit("wind", rgb(120, 190, 255), WHITE),
		-- Crew
		flare_kick = unit("fire", rgb(255, 140, 40), rgb(255, 230, 120)),
		field_medic = unit("magic", rgb(255, 150, 200), WHITE),
		threefold_crash = unit("slash", rgb(115, 225, 125), WHITE),
		elastic_wardrum = unit("rubber", rgb(230, 60, 50), rgb(255, 222, 80)),
		-- Heroes
		burst_vector = unit("explosion", rgb(255, 150, 40), rgb(90, 90, 95)),
		skybreaker = unit("lightning", rgb(125, 255, 145), WHITE),
		zero_field = unit("gravity", rgb(255, 130, 190), WHITE),
		ascending_core = unit("ki", rgb(120, 195, 255), rgb(255, 222, 80)),
		final_argument = unit("impact", rgb(255, 222, 60), rgb(255, 85, 60)),
	},
	-- Units not listed: this element, in the faction color (primary) and white (secondary).
	default = "magic",

	-- Hand-made signature effects, by unit id: `kind` names a handler in src/client/AbilitySignatures
	-- that replaces parts of the generated effect (its other fields are that handler's settings).
	signatures = {
		-- One punch: a slow, heavy wind-up (fist pulled back, energy gathering at it, a beat of
		-- stillness), then the punch: a blast zone from the fist through the target (his real area
		-- is the target alone: the shockwave lands on the target's hex and the cone of air past it is
		-- drawn only), a ground crack, dust, a big camera shake and a long hit-stop.
		final_argument = {
			kind = "punch",
			-- Seconds (the generic wind-up is AnimationConfig.cast.windup); the poses are
			-- AnimationConfig.signaturePoses.punch.
			windup = 1.0,
			orbSize = 2.2, -- times the generic charge orb
			coneLength = 3.2, -- hexes past his fist the cone of air reaches (drawn only)
			coneHalfAngle = 26, -- degrees
			crackSize = 7,
			dustCount = 22,
			shake = 0.75,
			hitStop = 0.16,
			flashSize = 4.2,
		},
	},

	-- Readable markers on units with a status, by Battle.Status (and MARK). Colors and shapes:
	--   ring      a flat ring at the feet;   chevron   a downward arrow over the head
	--   wisps     dark smoke rising;         shards    small shards circling the waist
	--   cross     an X over the head;        flames    flames on the body
	--   bubbles   bubbles rising;            reticle   a target ring over the head
	-- Damage-over-time markers stay `dotLinger` seconds after the last tick.
	statuses = {
		SLOW = { shape = "ring", color = rgb(140, 210, 255) },
		WEAKEN = { shape = "chevron", color = rgb(190, 190, 200) },
		CURSE = { shape = "wisps", color = rgb(120, 50, 170) },
		SHRED = { shape = "shards", color = rgb(255, 160, 60) },
		WOUND = { shape = "cross", color = rgb(200, 40, 60) },
		BURN = { shape = "flames", color = rgb(255, 130, 40) },
		POISON = { shape = "bubbles", color = rgb(120, 230, 110) },
		MARK = { shape = "reticle", color = rgb(255, 70, 70) },
	},
	dotLinger = 1.3,
	markDuration = 3,

	-- Mechanic sizes and timings.
	beamWidth = 0.55,
	beamDuration = 0.3,
	waveSpeed = 0.28, -- seconds for a slash wave or a stretch to cross its line
	areaMarkDuration = 0.9, -- ground marks linger
	afterimages = 4, -- ghosts along a dash
	afterimageDuration = 0.3,
	portalDuration = 0.7,
	transformDuration = 0.6,
	auraPulseEvery = 1.0, -- seconds between a unit's aura pulse rings (auras tick every second)
	strikeSize = 2.2, -- single-target ability hit, studs
	blastHeight = 1.2, -- flash ball height over the ground in area blasts, studs
})
