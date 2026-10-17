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
		glow_soft = { blend = "alpha", beam = false },
		glow_hard_core = { blend = "alpha", beam = false },
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

	-- Loading. Every image is preloaded in one batch at client start; any not loaded is tried once
	-- more after `retryDelays[1]` seconds, and one still reporting Failure or TimedOut falls back to
	-- neon. Images given up on are asked about again every `recheck`
	-- seconds when an effect would draw with them. requireLoaded = false: an image is drawn while it
	-- loads (it pops in when it arrives); true: only once loaded.
	loading = { requireLoaded = false, retryDelays = { 2 }, recheck = 2 },

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
	-- at random so repeats do not look stamped).
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
		-- a bolt striking down: off (the kit's lightning is a horizontal beam strip, not an upright bolt)
		bolt = { on = false, roles = { "lightning" }, modes = { "billboard" }, brightness = 2, upright = true },
		halo = { on = true, roles = { "energy", "glow" }, modes = { "billboard" }, brightness = 1.6 }, -- orbs and orb projectiles
		-- growing shockwave shells: the thick ring
		shell = { on = true, roles = { "rings" }, first = { "rings:2" }, modes = { "billboard" }, brightness = 1.3 },
		-- aura spikes: the fire flipbook (as sprites)
		aura = { on = true, roles = { "fire" }, modes = { "billboard" }, brightness = 1.6, upright = true },
		lightning = { on = true, roles = { "lightning" }, modes = { "beam" }, speed = 3, width = 3 }, -- jagged beams, zaps
		-- the soft glow around beams, columns: off (no kit texture made for it yet)
		beamGlow = { on = false, roles = { "glow", "smoke" }, modes = { "beam" }, width = 1.4 },
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
