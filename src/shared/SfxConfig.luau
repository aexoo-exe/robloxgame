-- Sound effects by name (client presentation only; src/client/Sfx.luau plays them).
--
--   library  the shared core sounds every ultimate draws from: Sfx.play("impactHeavy"), with
--            per-use variation through the play options (Sfx.play("whooshLight", { pitch = 1.1 })).
--   units    optional signature sounds of one unit, by unit id: Sfx.play("<unit_id>.<sound>"). At
--            most 2 per unit and only for tier 3+ ultimates (the slice-unit skill); everything
--            else uses the library.
--
-- Fill each `id` with a Creator Store audio asset id ("rbxassetid://123..." or just the number);
-- docs/design/sound-picks.md has search terms and what each should sound like. An empty id plays
-- nothing (silently), except a `fallback`: the built-in placeholder sound of that role
-- (UltimateConfig.sounds) plays until the id is filled.
--
--   id            the audio asset ("" until chosen)
--   volume        0-1
--   pitch         { min, max } playback speed, picked at random per play (variation)
--   volumeJitter  each play's volume varies by up to this share (0.1: +-10%)
--   fallback      UltimateConfig.sounds role used while `id` is empty (nil: silent)

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
	library = {
		-- Swings and movement --------------------------------------------------------------------
		-- One fast blade or limb swing: a sharp, bright whoosh (~0.2 s), no impact in it.
		whooshLight = {
			id = "74419593834838",
			volume = 0.5,
			pitch = { 0.92, 1.1 },
			volumeJitter = 0.1,
			fallback = "whoosh",
		},
		-- A big, heavy swing (greatsword, giant limb): a deep, longer whoosh (~0.4 s), no impact.
		whooshHeavy = { id = "", volume = 0.55, pitch = { 0.88, 1.02 }, volumeJitter = 0.1 },
		-- A rush of air (a dash, a shockwave passing, a held breath released): ~0.6 s, soft attack.
		windGust = { id = "", volume = 0.45, pitch = { 0.9, 1.1 }, volumeJitter = 0.1 },

		-- Hits -----------------------------------------------------------------------------------
		-- A sword connecting: a short, punchy slice-and-thud (~0.15 s), cartoon-anime style.
		impactLight = { id = "101309544882556", volume = 0.55, pitch = { 0.9, 1.1 }, volumeJitter = 0.1 },
		-- The finisher: a deep, heavy boom with a tail (~0.8 s), the loudest of the set.
		impactHeavy = { id = "138533090376585", volume = 0.65, pitch = { 0.95, 1.02 }, volumeJitter = 0.05 },
		-- Steel on steel or a clean cut: a bright metallic slash with a short ring (~0.3 s).
		slashMetal = { id = "", volume = 0.5, pitch = { 0.95, 1.1 }, volumeJitter = 0.1 },
		-- A rapid barrage of punches: ~1 s of fast thuds, loopable feel, no single big hit.
		punchRush = { id = "", volume = 0.5, pitch = { 0.95, 1.08 }, volumeJitter = 0.08 },
		-- Something heavy landing or a fist into the ground: a low thud with a crunch (~0.5 s).
		groundSlam = { id = "", volume = 0.6, pitch = { 0.9, 1.05 }, volumeJitter = 0.08 },
		-- Rocks and debris scattering after a slam: ~0.8 s of tumbling stones.
		rockDebris = { id = "", volume = 0.45, pitch = { 0.92, 1.08 }, volumeJitter = 0.1 },

		-- Elements -------------------------------------------------------------------------------
		-- A burst of flame catching: a soft "fwoomp" with crackle (~0.6 s), not an explosion.
		fireBurst = { id = "96009794895457", volume = 0.5, pitch = { 0.94, 1.06 }, volumeJitter = 0.1 },
		-- A small fire crackle or a finger snap with a spark (~0.4 s); also the start of a fuse.
		fireCrackle = { id = "", volume = 0.4, pitch = { 0.95, 1.08 }, volumeJitter = 0.1 },
		-- An explosion: a punchy blast with a short rumble (~1 s).
		explosion = { id = "", volume = 0.6, pitch = { 0.92, 1.05 }, volumeJitter = 0.08 },
		-- A sharp, dry thunder crack with a short electric snap (~0.5 s), no long rumble tail.
		lightningCrack = { id = "", volume = 0.6, pitch = { 0.96, 1.04 }, volumeJitter = 0.06 },
		-- A crackling electric buzz or chirp (~0.6 s), for charged hands and bodies.
		electricBuzz = { id = "", volume = 0.4, pitch = { 0.95, 1.1 }, volumeJitter = 0.1 },
		-- A splash of water or mud (~0.6 s).
		waterSplash = { id = "", volume = 0.5, pitch = { 0.92, 1.08 }, volumeJitter = 0.1 },

		-- Energy and magic -----------------------------------------------------------------------
		-- A charge building (a blade drawn back, energy gathering): a short rising tone or scrape
		-- (~0.4-0.8 s), ending on a held breath, no impact in it.
		energyCharge = { id = "", volume = 0.45, pitch = { 0.97, 1.03 }, volumeJitter = 0.08 },
		-- Stored energy let go: a bright release with a whoosh of power (~0.5 s).
		energyRelease = { id = "", volume = 0.55, pitch = { 0.95, 1.05 }, volumeJitter = 0.08 },
		-- A magic chime or bell: a clear tone with a soft tail (~1 s); pitched down, a deep bell.
		magicChime = { id = "", volume = 0.45, pitch = { 0.95, 1.05 }, volumeJitter = 0.08 },
		-- A healing twinkle: soft sparkles (~0.6 s).
		healTwinkle = { id = "", volume = 0.4, pitch = { 0.97, 1.08 }, volumeJitter = 0.1 },

		-- Weapons --------------------------------------------------------------------------------
		-- A blade slid into its scabbard, ending on a crisp metal click (~0.4 s).
		sheathe = { id = "", volume = 0.45, pitch = { 0.97, 1.03 }, volumeJitter = 0.05 },
	},

	-- Signature sounds by unit id (Sfx.play("<unit_id>.<sound>")). None yet: cinder_arc and
	-- flashline use library sounds only.
	units = {},
})
