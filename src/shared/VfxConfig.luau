-- Effect textures (client visuals only): which picked texture (VfxPicks, from the VFX picker) each
-- effect draws with, per role, element and unit, and how. Read by src/shared/VfxResolve.luau (the
-- choice) and src/client/Vfx.luau (loading and the current unit). Nothing here changes fight timing
-- or results; an effect whose texture is missing or fails to load keeps its plain neon look.
--
-- A texture is named "<role>:<rank>": the pick of that rank in that role (VfxPicks). Roles: slash,
-- smoke, sparks, rings, flashes, lightning, energy, fire, explosions, cracks, auras.
-- To change an assignment, edit one line in `units` or `elements` (or reorder ranks in the picker
-- and run lune run scripts/vfx-apply).

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
		"smoke",
		"sparks",
		"rings",
		"flashes",
		"lightning",
		"energy",
		"fire",
		"explosions",
		"cracks",
		"auras",
	},

	-- What each picked image is, by texture id (checked by eye on its thumbnail):
	--   blend     "alpha" (a transparent background: fine on planes and billboards) or "additive" (a
	--             black background: only particles and beams, which add light, can hide it)
	--   baked     the texture's own color: it is not tinted (an element color would muddy it), and it
	--             is chosen only for colors close to it (`hue` below) unless a variant names it
	--   tint      false: drawn in its own colors, for any color (a black crack)
	--   flipbook  a grid of frames: { layout = "2x2" | "4x4" | "8x8", mode = "OneShot" | "Loop",
	--             fps (Loop only) } (particles only)
	--   burst     one whole burst in the image: only for single big particles (flashes), not for
	--             streams of small sparks
	--   beam      false: does not read along a beam (a vertical bolt would lie across it)
	--   frame     a full-screen impact frame (screen only)
	--   unusable  why it is never used
	traits = {
		[8273465648] = { blend = "alpha" }, -- slash:1 a white swoosh streak
		[138157711335343] = { blend = "alpha", flipbook = { layout = "4x4", mode = "OneShot" } }, -- slash:2 electric crescent, 4x4 frames (the picker had no grid set)
		[101393300473082] = { blend = "alpha" }, -- slash:3 wind slash
		[9061498628] = { blend = "alpha" }, -- smoke:1 soft white puff
		[6956634044] = { blend = "alpha" }, -- smoke:2 billowy cloud
		[122079743545882] = { blend = "additive", baked = rgb(255, 170, 90), burst = true }, -- sparks:2 an orange spark burst on black
		[134674538402910] = { blend = "alpha" }, -- rings:1 a faint bubble with a bright rim
		[119064104030965] = { blend = "alpha" }, -- rings:2 a clean soft ring
		[120301856301662] = { blend = "alpha", frame = true }, -- flashes:1 manga impact frame on white (full screen only)
		[125496445293050] = { blend = "additive", burst = true }, -- flashes:2 a white starburst on black
		[99013781938083] = { blend = "alpha", baked = rgb(255, 150, 60), beam = false }, -- lightning:1 an upright orange bolt
		[16601233770] = { blend = "additive", baked = rgb(170, 90, 255) }, -- lightning:2 purple forks on black
		[12525387853] = { blend = "alpha" }, -- lightning:3 white branching lightning
		[16601260137] = { blend = "additive", baked = rgb(150, 70, 230), beam = false }, -- energy:1 a purple orb on black
		[6900421146] = { blend = "alpha", beam = false }, -- energy:2 a white crackling orb
		[17703378809] = { blend = "alpha", flipbook = { layout = "4x4", mode = "Loop", fps = 24 } }, -- fire:3 4x4 fire loop
		[8734114950] = { blend = "alpha", flipbook = { layout = "8x8", mode = "OneShot" } }, -- explosions:2 8x8 pixel blast
		[8815468530] = { unusable = "an opaque white background: it would show as a white square on the ground" }, -- cracks:1
		[100563112706114] = { blend = "alpha", tint = false }, -- cracks:2 a black crack (black takes no tint)
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

	-- requireLoaded = false: an image is used as soon as it is chosen (it pops in when it arrives)
	-- and only one that failed to load falls back to neon. true: only images already loaded.
	loading = { requireLoaded = false },

	-- How each kind of effect draws. `roles` in order (the first with a fitting texture wins), `modes`
	-- in order of preference:
	--   particle   a ParticleEmitter texture (flipbooks play)
	--   plane      an unlit textured plane (SurfaceGui) in place of a flat neon part
	--   billboard  an unlit textured sprite facing the camera in place of a neon ball
	--   beam       a Beam stretched along a neon bar's length
	--   screen     a full-screen frame
	-- `brightness` brightens planes and billboards (bloom catches above 1); `burst` allows burst
	-- images; `speed` scrolls a beam's texture; `width` is a beam's width, times the neon bar's
	-- (textures have soft or empty edges); `upright` keeps a billboard's image upright (others turn
	-- at random so repeats do not look stamped).
	uses = {
		sparks = { roles = { "sparks" }, modes = { "particle" } }, -- spark and ember bursts (hits, casts)
		smoke = { roles = { "smoke" }, modes = { "particle" } }, -- puffs, dust, smoke
		fire = { roles = { "fire" }, modes = { "particle" } }, -- flame bursts
		glow = { roles = { "energy" }, modes = { "particle" } }, -- glow bursts (ki, time, magic)
		shock = { roles = { "rings" }, modes = { "particle" } }, -- shockwave bursts
		explosion = { roles = { "explosions" }, modes = { "particle" } }, -- explode strikes, big blasts
		flash = { roles = { "flashes" }, modes = { "particle" }, burst = true }, -- the flash at every hit and burst
		critFlash = { roles = { "sparks", "flashes" }, modes = { "particle" }, burst = true }, -- crits
		ring = { roles = { "rings" }, modes = { "plane" }, brightness = 1.6 }, -- ground rings, spirals, cones
		disc = { roles = { "smoke" }, modes = { "plane" }, brightness = 1.1 }, -- soft ground discs and pools
		crack = { roles = { "cracks" }, modes = { "plane" }, brightness = 1 }, -- ground cracks
		slash = { roles = { "slash" }, modes = { "plane", "particle" }, brightness = 2 }, -- slash arcs, waves, cuts
		slashBurst = { roles = { "slash" }, modes = { "particle" } }, -- a slash flash at a cut (flipbooks play)
		bolt = { roles = { "lightning" }, modes = { "billboard" }, brightness = 2, upright = true }, -- a bolt striking down
		halo = { roles = { "energy" }, modes = { "billboard" }, brightness = 1.6 }, -- orbs and orb projectiles
		shell = { roles = { "rings" }, modes = { "billboard" }, brightness = 1.3 }, -- growing shockwave shells
		aura = { roles = { "auras" }, modes = { "billboard" }, brightness = 1.6, upright = true }, -- aura spikes
		lightning = { roles = { "lightning" }, modes = { "beam" }, speed = 3, width = 3 }, -- jagged beams, zaps
		beamGlow = { roles = { "energy", "smoke" }, modes = { "beam" }, width = 1.4 }, -- the soft glow around beams, columns
		impactFrame = { roles = { "flashes" }, modes = { "screen" } }, -- ultimate releases (below)
	},

	-- Variants by element (AbilityFxConfig.units `element`) and by unit id: role -> "<role>:<rank>".
	-- A unit's line wins over its element's; both win over rank 1 (and skip the hue check).
	elements = {
		lightning = { slash = "slash:2" }, -- lightning swordsmen cut with the electric crescent
		wind = { slash = "slash:3" }, -- wind users cut with the wind slash
		steam = { smoke = "smoke:2" }, -- billowing steam
		explosion = { smoke = "smoke:2" }, -- big blast clouds
		impact = { smoke = "smoke:2", rings = "rings:2" }, -- heavy dust, crisp shock rings
		ki_impact = { smoke = "smoke:2", rings = "rings:2" },
		gravity = { rings = "rings:2" }, -- clean gravity rings
		fire = { explosions = "explosions:2" }, -- fire blasts burst like the pixel explosion
	},
	units = {
		cyclone_edge = { slash = "slash:3" }, -- the cyclone blade cuts with wind
		wolfstep = { slash = "slash:3" }, -- wind-step lunges
		volt_spear = { lightning = "lightning:2", energy = "energy:1" }, -- violet lightning
		clockbreaker = { energy = "energy:1" }, -- violet ki
		night_parade = { energy = "energy:1", lightning = "lightning:2" }, -- cursed violet
		night_command = { energy = "energy:1" },
		flashline = { lightning = "lightning:1" }, -- the orange-gold bolt
		burst_vector = { explosions = "explosions:2" },
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
