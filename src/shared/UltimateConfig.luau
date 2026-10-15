-- Signature ultimates (client visuals only; src/client/Cinematic.luau runs them, one module per
-- unit in src/client/Ultimates). An ultimate dresses a unit's real cast: its anticipation plays
-- before the Cast event (the playback looks ahead in the precomputed event list, so nothing is
-- delayed), its impacts land on the cast's real events, and its finish plays after. Combat
-- results and event timing never change.
--
-- Units: seconds of fight time, studs, Color3. Design times are relative to the Cast event
-- (negative: before it).
--
-- Per unit (`units`, by unit id):
--   tier      presentation budget, 1-5 (= cost): `tiers` below caps camera, shake and length
--   preroll   design seconds of anticipation before the release. When the real window is shorter
--             (the unit cast moments ago), the anticipation is compressed to fit, never the impact
--   linger    design seconds the finish plays after the release
--   look      what to judge in Studio (DevLineup: key 3, or DevLineupQA:Invoke("ultimate", id))
--   wanted    the sounds a real version needs (this build uses built-in sounds only: `sounds`)
-- A unit is DONE when src/client/Ultimates/<unit id>.luau exists (scripts/audit-units checks it).

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
	-- Presentation budget per tier: camera cues allowed, the largest camera shake, the shortest
	-- anticipation kept when compressing (a fraction of `preroll`).
	tiers = {
		[1] = { camera = false, dim = false, shake = 0.08, minShare = 0.35 },
		[2] = { camera = false, dim = false, shake = 0.12, minShare = 0.35 },
		[3] = { camera = false, dim = false, shake = 0.2, minShare = 0.4 },
		[4] = { camera = true, dim = true, shake = 0.32, minShare = 0.45 },
		[5] = { camera = true, dim = true, shake = 0.45, minShare = 0.5 },
	},
	-- Room kept after a unit's previous cast before its next anticipation may start.
	afterPreviousCast = 0.3,

	-- Camera cues (src/client/CameraCues.luau): only on the board the local player watches.
	camera = {
		maxPush = 4.5, -- studs the camera may move toward a focus
		maxDim = 0.3, -- how far the screen may dim (0-1)
		maxConcurrent = 1, -- Tier 4-5 camera cues at once (the rest still play, without camera)
		cooldown = 1.2, -- seconds after a Tier 4-5 camera cue ends before the next may start
	},

	-- Built-in Roblox sounds (no uploads), by role. Volumes stay low: these are placeholders.
	sounds = {
		charge = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.35, speed = 0.45 },
		chime = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.3, speed = 1 },
		tick = { id = "rbxasset://sounds/clickfast.wav", volume = 0.4, speed = 1 },
		whoosh = { id = "rbxasset://sounds/action_falling.mp3", volume = 0.3, speed = 1.8, length = 0.5 },
		splash = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.4, speed = 1.2, length = 0.6 },
	},

	units = {
		-- Tier 5 -------------------------------------------------------------------------------
		infinite_collapse = {
			tier = 5,
			preroll = 1.2,
			linger = 1.3,
			look = "calm stop; blue orb pulls in (right hand), red orb pushes out (left); they spiral into a purple sphere; the flick is much faster than the build; erasure at the real hit; hand in pocket",
			wanted = {
				"low hum rising (blue orb, inward suck)",
				"distorted push-out pulse (red orb)",
				"reverse cymbal into silence (merge)",
				"sub-bass drop + air crack (flick)",
				"huge muffled erasure boom, then ringing",
			},
		},
		severing_temple = {
			tier = 5,
			preroll = 1.0,
			linger = 4.3, -- through the 4 s damage over time (the pose ends at 1.8)
			look = "hand sign; the shrine climbs out of the ground behind the area, the floor turns to a dark pool; a bell beat of stillness; the area fills with cuts on the real hit; fresh cuts on each enemy at every real tick; shrine fades by 2.6",
			wanted = { "temple bell", "rising drone", "hundreds of fast slash swishes", "big impact" },
		},
		ascending_core = {
			tier = 5,
			preroll = 0.9,
			linger = 1.2,
			look = "casts 1-2: fists clench, yell, gold aura spikes climb (blue sparks into Core III), palm blast, gold eruption on the form change; Core III: hands cupped at the hip, light grows, stones float, stillness, then a held full-board beam along the real line that thins out",
			wanted = { "power-up roar swell", "charging whine", "beam blast and sustain" },
		},
		final_argument = {
			tier = 5,
			preroll = 1.05,
			linger = 1.2,
			look = "bored to serious; the fist draws back slowly, dust lifts; total stillness; an almost invisible punch; a white flash, the cone of air and a crack across the board",
			wanted = { "silence drop", "fist creak", "massive punch boom", "wind rush" },
		},
		boiling_crown = {
			tier = 5,
			preroll = 1.05,
			linger = 1.4,
			look = "goes still, steam thickens and turns orange, chest glows, ground cracks; stillness; an eruption dome over the real area; steam rolls out",
			wanted = { "kettle rising", "rumble", "steam eruption roar", "hiss tail" },
		},
		-- Tier 4 -------------------------------------------------------------------------------
		reelbreaker = { tier = 4, preroll = 0.7, linger = 0.9, look = "", wanted = {} },
		night_command = { tier = 4, preroll = 0.8, linger = 0.9, look = "", wanted = {} },
		cyclone_edge = { tier = 4, preroll = 0.55, linger = 0.6, look = "", wanted = {} },
		frozen_moment = { tier = 4, preroll = 1.0, linger = 0.9, look = "", wanted = {} },
		restoration_strike = { tier = 4, preroll = 0.85, linger = 0.6, look = "", wanted = {} },
		night_parade = { tier = 4, preroll = 0.8, linger = 0.8, look = "", wanted = {} },
		starless_burst = { tier = 4, preroll = 0.85, linger = 0.9, look = "", wanted = {} },
		echo_legion = { tier = 4, preroll = 0.9, linger = 1.0, look = "", wanted = {} },
		elastic_wardrum = { tier = 4, preroll = 0.6, linger = 0.6, look = "", wanted = {} },
		-- Tier 3 -------------------------------------------------------------------------------
		thunder_nest = { tier = 3, preroll = 0.4, linger = 0.8, look = "", wanted = {} },
		horizon_cut = { tier = 3, preroll = 0.75, linger = 0.5, look = "", wanted = {} },
		snapfire = { tier = 3, preroll = 0.45, linger = 0.7, look = "", wanted = {} },
		clockbreaker = { tier = 3, preroll = 0.4, linger = 1.3, look = "", wanted = {} },
		titanheart = { tier = 3, preroll = 0.4, linger = 0.8, look = "", wanted = {} },
		skyboulder = { tier = 3, preroll = 0.5, linger = 0.6, look = "", wanted = {} },
		volt_spear = { tier = 3, preroll = 0.45, linger = 0.7, look = "", wanted = {} },
		mirror_script = { tier = 3, preroll = 0.45, linger = 0.5, look = "", wanted = {} },
		threefold_crash = { tier = 3, preroll = 0.25, linger = 0.9, look = "", wanted = {} },
		zero_field = { tier = 3, preroll = 0.4, linger = 1.2, look = "", wanted = {} },
		-- Tier 2 -------------------------------------------------------------------------------
		redline_cut = { tier = 2, preroll = 0.2, linger = 0.6, look = "", wanted = {} },
		orbit_breaker = { tier = 2, preroll = 0.35, linger = 0.5, look = "", wanted = {} },
		crimson_hunger = { tier = 2, preroll = 0.3, linger = 0.5, look = "", wanted = {} },
		shade_pack = { tier = 2, preroll = 0.25, linger = 0.5, look = "", wanted = {} },
		marsh_fortress = { tier = 2, preroll = 0.4, linger = 0.5, look = "", wanted = {} },
		flare_kick = { tier = 2, preroll = 0.15, linger = 0.4, look = "", wanted = {} },
		field_medic = { tier = 2, preroll = 0.3, linger = 0.4, look = "", wanted = {} },
		burst_vector = { tier = 2, preroll = 0.35, linger = 0.45, look = "", wanted = {} },
		skybreaker = { tier = 2, preroll = 0.3, linger = 0.55, look = "", wanted = {} },
		-- Tier 1 -------------------------------------------------------------------------------
		flashline = { tier = 1, preroll = 0.2, linger = 0.5, look = "", wanted = {} },
		cinder_arc = { tier = 1, preroll = 0.2, linger = 0.45, look = "", wanted = {} },
		wolfstep = { tier = 1, preroll = 0.15, linger = 0.45, look = "", wanted = {} },
		spurshot = { tier = 1, preroll = 0.2, linger = 0.45, look = "", wanted = {} },
		ripcord_frenzy = { tier = 1, preroll = 0.25, linger = 0.45, look = "", wanted = {} },
		null_edge = { tier = 1, preroll = 0.2, linger = 0.45, look = "", wanted = {} },
		bitter_vapor = { tier = 1, preroll = 0.2, linger = 0.55, look = "", wanted = {} },
		iron_rush = { tier = 1, preroll = 0.2, linger = 0.4, look = "", wanted = {} },
		blooming_aid = { tier = 1, preroll = 0.2, linger = 0.4, look = "", wanted = {} },
	},
})
