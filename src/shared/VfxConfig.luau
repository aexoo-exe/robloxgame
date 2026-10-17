-- Effect textures (client visuals only): which VFX kit texture (VfxPicks, generated from
-- assets/vfx/ids.json by scripts/vfx-apply) each effect draws with, per role, element and unit, and
-- how. Read by src/shared/VfxResolve.luau (the choice) and src/client/Vfx.luau (loading and the
-- current unit). Nothing here changes fight timing or results; an effect whose usage is switched off,
-- or whose texture is missing, not uploaded or fails to load, keeps its plain neon look.
--
-- A texture is named "<role>:<rank>": the kit texture of that rank in that role (VfxPicks). Roles:
-- slash, rings, glow, sparks, smoke, explosions, fire, lightning, energy, cracks, impact.
-- To change an assignment, edit one line in `uses`, `units` or `elements` (or the role mapping in
-- scripts/vfx-apply.luau, then run lune run scripts/vfx-apply).

local Picks = require(script.Parent:WaitForChild("VfxPicks"))

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

return deepFreeze({
	picks = Picks.roles,
	roles = {
		"slash",
		"rings",
		"glow",
		"sparks",
		"smoke",
		"explosions",
		"fire",
		"lightning",
		"energy",
		"cracks",
		"impact",
	},

	-- What each kit texture is, by its name (VfxPicks `name`). Every kit texture is a white core on a
	-- real transparent background (docs/design/vfx-style.md), tinted by the effect's color; anything
	-- not listed is { blend = "alpha" }.
	--   blend     "alpha" (a transparent background: fine on planes and billboards) or "additive" (a
	--             black background: only particles and beams, which add light, can hide it)
	--   baked     the texture's own color: it is not tinted (an element color would muddy it), and it
	--             is chosen only for colors close to it (`hue` below) unless a variant names it
	--   tint      false: drawn in its own colors, for any color
	--   shade     always drawn in this color, whatever the effect's (soot)
	--   flipbook  a grid of frames: { layout = "2x2" | "4x4" | "8x8", mode = "OneShot" | "Loop",
	--             fps (Loop only) } (particles only; planes and billboards draw it as a sprite)
	--   scale     particles and sprites are drawn this many times bigger (art small in its frame)
	--   tile      beams repeat the texture every this many studs instead of stretching it once
	--   light     LightEmission on beams and sprites (0-1: how much it adds light)
	--   burst     one whole burst in the image: only for single big particles (flashes), not for
	--             streams of small sparks
	--   beam      false: does not read along a beam
	--   frame     a full-screen impact frame (screen only)
	--   unusable  why it is never used
	traits = {
		smoke_flipbook = { blend = "alpha", flipbook = { layout = "4x4", mode = "OneShot" } }, -- puff that fades out
		explosion_flipbook = { blend = "alpha", flipbook = { layout = "4x4", mode = "OneShot" } }, -- flash, fireball, smoke
		-- flames fill only the lower middle of each 256 px frame: drawn bigger so they read
		fire_flipbook = { blend = "alpha", flipbook = { layout = "4x4", mode = "Loop", fps = 24 }, scale = 1.8 },
		lightning_strip = { blend = "alpha", tile = 6, light = 1 }, -- tiles along the beam (U)
		energy_orb = { blend = "alpha", beam = false },
		energy_swirl = { blend = "alpha", beam = false },
		-- glows read along beams too: a soft streak, fading at both ends (beam glows, grooves, streaks)
		impact_starburst = { blend = "alpha", burst = true, beam = false }, -- one whole hit burst
		ground_scorch = { blend = "alpha", shade = rgb(45, 40, 38) }, -- dark soot whatever the element
	},
	-- Textures exported from a model pack (VfxPicks `textures`) are particle textures: additive unless
	-- listed in `traits`. `packs` picks which of a pack's textures a role uses (1 = the most used).
	packs = {},

	-- Baked textures. By default (strict = false) they are used for any color: drawn in their own
	-- colors when the effect's color is close to theirs (hue within `maxGap`, 0-1 around the wheel;
	-- colors paler than `minSaturation` only match pale textures), otherwise tinted `bakedTint` of the
	-- way toward it. strict = true: a baked texture is skipped for colors that do not suit it (the
	-- next pick is used) and is never tinted.
	hue = { strict = false, bakedTint = 0.5, maxGap = 0.09, minSaturation = 0.3 },

	-- Loading. At client start every image gets a hidden ImageLabel that uses it (kept for the
	-- session) and those labels are preloaded: an image is drawn while it loads. One whose label has
	-- still not loaded `failAfter` seconds after start is drawn neon, re-fetched every `retryEvery`
	-- seconds, and drawn again once loaded (re-checked at draw time every `recheck` seconds).
	-- requireLoaded = true: an image is drawn only once its label has loaded.
	loading = { requireLoaded = false, failAfter = 20, retryEvery = 10, recheck = 2 },

	-- Filters, each a switch:
	--   sprites       true: a black-background (additive) or flipbook texture asked to draw as a plane
	--                 or billboard draws as one additive particle sprite of the same size, place and fade
	--                 (flat on the ground for planes) instead of being passed over
	--   burstAnywhere true: a whole-burst image may also be a stream particle (sparks); false: only
	--                 single flashes
	--   beamAlong     true: a texture marked `beam = false` is passed over for beams (the next fits)
	filters = { sprites = true, burstAnywhere = true, beamAlong = true },

	-- How each kind of effect draws. `on` switches a usage (false: always the neon look). `roles` in
	-- order (the first with a fitting texture wins); `first` (optional) are picks tried before the
	-- roles' ranks (after unit and element variants); `modes` in order of preference:
	--   particle   a ParticleEmitter texture (flipbooks play)
	--   plane      an unlit textured plane (SurfaceGui) in place of a flat neon part
	--   billboard  an unlit textured sprite facing the camera in place of a neon ball
	--   beam       a Beam stretched (or tiled: traits `tile`) along a neon bar's length
	--   screen     a full-screen frame
	-- `brightness` brightens planes and billboards (bloom catches above 1); `burst` allows burst
	-- images; `speed` scrolls a beam's texture; `width` is a beam's width, times the neon bar's
	-- (textures have soft or empty edges); `upright` keeps a billboard's image upright (others turn
	-- at random so repeats do not look stamped); `scale` draws particles, sprites and billboards bigger
	-- (soft-edged art looks smaller than its neon shape); `light` is the LightEmission of beams and
	-- sprites (1: adds light, the punchy look).
	uses = {
		sparks = { on = true, roles = { "sparks" }, modes = { "particle" } }, -- spark and ember bursts (hits, casts)
		-- puffs, dust, smoke: the fading puff flipbook
		smoke = { on = true, roles = { "smoke" }, first = { "smoke:2" }, modes = { "particle" } },
		fire = { on = true, roles = { "fire" }, modes = { "particle" } }, -- flame bursts (fire flipbook loop)
		glow = { on = true, roles = { "glow", "energy" }, modes = { "particle" } }, -- glow bursts (ki, time, magic)
		-- shockwave bursts: the thick ring
		shock = { on = true, roles = { "rings" }, first = { "rings:2" }, modes = { "particle" } },
		explosion = { on = true, roles = { "explosions" }, modes = { "particle" } }, -- explode strikes, big blasts
		-- the flash at every hit and burst: the hard-cored glow
		flash = { on = true, roles = { "glow" }, first = { "glow:2" }, modes = { "particle" }, burst = true },
		critFlash = { on = true, roles = { "impact", "glow" }, modes = { "particle" }, burst = true }, -- crits: the starburst
		ring = { on = true, roles = { "rings" }, modes = { "plane" }, brightness = 1.6 }, -- ground rings, spirals, cones
		disc = { on = true, roles = { "smoke" }, modes = { "plane" }, brightness = 1.1 }, -- soft ground discs and pools
		crack = { on = true, roles = { "cracks" }, modes = { "plane" }, brightness = 1 }, -- ground cracks
		slash = { on = true, roles = { "slash" }, modes = { "plane", "particle" }, brightness = 2 }, -- slash arcs, waves, cuts
		slashBurst = { on = true, roles = { "slash" }, modes = { "particle" } }, -- a slash flash at a cut
		-- a bolt striking down: the lightning strip tiled along a vertical beam from the sky
		bolt = { on = true, roles = { "lightning" }, modes = { "beam" }, speed = 4, width = 2.5 },
		halo = { on = true, roles = { "energy", "glow" }, modes = { "billboard" }, brightness = 1.6 }, -- orbs and orb projectiles
		-- growing shockwave shells: the thick ring
		shell = { on = true, roles = { "rings" }, first = { "rings:2" }, modes = { "billboard" }, brightness = 1.3 },
		-- aura spikes: the fire flipbook (as sprites)
		aura = { on = true, roles = { "fire" }, modes = { "billboard" }, brightness = 1.6, upright = true },
		lightning = { on = true, roles = { "lightning" }, modes = { "beam" }, speed = 3, width = 3 }, -- jagged beams, zaps
		-- the soft glow around beams, columns and glowing bars (over their neon core)
		beamGlow = { on = true, roles = { "glow" }, modes = { "beam" }, width = 1.6, light = 1 },
		-- motes drawn in or pushed out, spiral orbs: twinkling star sparks
		mote = {
			on = true,
			roles = { "glow" },
			first = { "sparks:2" },
			modes = { "billboard" },
			brightness = 2.2,
			scale = 2.4,
		},
		-- wind streaks and ground grooves: a soft glow streak along the line
		streak = { on = true, roles = { "glow" }, modes = { "beam" }, width = 3, light = 1 },
		-- Particle usages for fully specified emits (ImpactEffects.emit, showcase ultimates):
		star = { on = true, roles = { "sparks" }, first = { "sparks:2" }, modes = { "particle" } }, -- star twinkles
		smokePuff = { on = true, roles = { "smoke" }, modes = { "particle" } }, -- one soft puff (no flipbook)
		ember = { on = true, roles = { "glow" }, first = { "glow:2" }, modes = { "particle" } }, -- hot dots
		-- a burnt patch on the ground (ground_scorch, always soot-dark)
		scorch = { on = true, roles = { "cracks" }, first = { "cracks:2" }, modes = { "plane" }, brightness = 1 },
		-- the glow over a neon block (spirit bodies, barriers, shrine lights): a soft halo
		glowBlob = { on = true, roles = { "glow" }, modes = { "billboard" }, brightness = 1.8, scale = 1.5 },
		-- ultimate releases (below): off (the kit has no full-screen impact frame)
		impactFrame = { on = false, roles = { "impact" }, modes = { "screen" } },
	},

	-- Variants by element (AbilityFxConfig.units `element`) and by unit id: role -> "<role>:<rank>".
	-- A unit's line wins over its element's; both win over `first` and rank 1 (and skip the hue check).
	elements = {
		lightning = { slash = "slash:3" }, -- lightning swordsmen cut with the double crescent
		wind = { slash = "slash:2" }, -- wind users cut with the wide crescent
		impact = { rings = "rings:2" }, -- heavy, thick shock rings
		ki_impact = { rings = "rings:2" },
		gravity = { rings = "rings:3" }, -- segmented gravity rings
		fire = { cracks = "cracks:2" }, -- fire scorches the ground
		explosion = { cracks = "cracks:2" }, -- blasts scorch the ground
		time = { energy = "energy:2" }, -- time ki swirls
		cursed = { energy = "energy:2" }, -- cursed energy swirls
		magic = { sparks = "sparks:2" }, -- magic twinkles with star sparks
	},
	units = {
		cyclone_edge = { slash = "slash:2" }, -- the cyclone blade cuts wide
		wolfstep = { slash = "slash:2" }, -- wind-step lunges
		clockbreaker = { energy = "energy:2" }, -- swirling ki
		night_parade = { energy = "energy:2" }, -- cursed swirl
		night_command = { energy = "energy:2" },
	},

	-- Ultimate releases flash a full-screen impact frame for the listed tiers (UltimateConfig), unless
	-- the player has ReducedEffects on or the quality level does not allow it.
	impactFrame = { tiers = { [4] = true, [5] = true }, duration = 0.07, transparency = 0.15 },

	-- Per effect quality level (AnimationConfig.quality): `maxSkinned` textured planes, billboards and
	-- beams alive at once (the rest stay neon; each is a pooled shape, AnimationConfig.pools.shapes);
	-- `impactFrame` allows the screen frame.
	quality = {
		low = { maxSkinned = 0, impactFrame = false },
		medium = { maxSkinned = 48, impactFrame = true },
		high = { maxSkinned = 120, impactFrame = true },
	},

	-- The flash particle that replaces neon flash balls: it swells from `from` of its size and lives
	-- `life` times the ball's duration (real time). `core` keeps a small neon ball inside, this share
	-- of the size (0: none).
	flash = { from = 0.35, life = 1.6, core = 0.35 },
})
