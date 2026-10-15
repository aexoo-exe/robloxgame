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
			look = "slouched and bored, then straight; the fist draws back slowly inside a bend of air, dust lifts; stillness while the camera goes face then fist; an almost invisible punch; white flash, a cone of air, a long crack along the punch, wind streaks and debris, long hit-stop; back to bored",
			wanted = { "silence drop", "fist creak", "massive punch boom", "wind rush" },
		},
		boiling_crown = {
			tier = 5,
			preroll = 1.05,
			linger = 1.4,
			look = "store model: sinks and trembles harder, steam thickens white to orange, a glow in the chest, the ground blackens and cracks; stillness; eruption column and dome on the real hit, he heaves up and back, steam rolls out, scorched ground",
			wanted = { "kettle rising", "rumble", "steam eruption roar", "hiss tail" },
		},
		-- Tier 4 -------------------------------------------------------------------------------
		reelbreaker = {
			tier = 4,
			preroll = 0.7,
			linger = 0.9,
			look = "rod overhead and whipped forward, the line flies to the farthest enemy and holds taut; the free fist draws back glowing yellow-green and growing (push on the fist); yank and punch together, the impact lands as the enemy arrives; aura sheds as sparks",
			wanted = {
				"rod whip and reel whirr",
				"rising charge hum in the fist",
				"line snap",
				"huge punch thud with crack",
			},
		},
		night_command = {
			tier = 4,
			preroll = 0.8,
			linger = 0.9,
			look = "hand raised, eyes glow purple, mist at his feet; a black-purple pool spreads under him, stillness and a push; a dark silhouette with lit eyes rises out of the pool at each real summon cell; pool drains, daggers glint blue and red",
			wanted = { "deep whispered command", "shadow pool hiss", "rising groan per soldier", "dagger glint ting" },
		},
		cyclone_edge = {
			tier = 4,
			preroll = 0.55,
			linger = 4.2, -- through the chain window (his attack speed lasts 4 s); the pose ends at 1.2
			look = "two cables shoot from his hips to the target, gas puffs; he sinks and launches; the whole body spins into a blade tornado on the dash, a whirl of rings and cuts on the real hit; low crouch after; each real chain: a cable snaps to the next enemy and a faster spin",
			wanted = { "cable fire and reel", "gas jet hiss", "spinning blade whirr", "rapid cut flurry" },
		},
		frozen_moment = {
			tier = 4,
			preroll = 1.0,
			linger = 2.9, -- the freeze lasts up to 2 s (3-star), then the knives and his pose
			look = "arms flung wide, a small gold sphere and a ticking clock under him; on the real stun the sphere snaps over the area and the colour drains, frozen enemies glazed grey-green; he flicks knives out that float pointed at each one; a push just before time resumes, then every knife lands at once on the real stun-end hits; motes back into him; hand-to-face pose",
			wanted = {
				"clock ticks",
				"time-stop whoosh into silence",
				"knife flicks",
				"all knives landing together",
				"time resuming swell",
			},
		},
		restoration_strike = {
			tier = 4,
			preroll = 0.85,
			linger = 0.8,
			look = "a pink spirit with a tall crest fades in behind him; diamond shards swirl in and lock into the real shield; pink beams to each really healed ally whose cracks close up with sparkles; the spirit throws three quick jabs into the target, a diamond burst each; proud pose",
			wanted = { "spirit appearing shimmer", "crystal shards tinkling", "repair chime", "three rapid punch hits" },
		},
		night_parade = {
			tier = 4,
			preroll = 0.8,
			linger = 0.8,
			look = "summon cast: open palm up, a dark vortex turns over it, a curse drops out onto each real summon cell; firing cast: his curses come apart into dark streams into his palm, a ball that tightens and darkens, a push and stillness, then a spiral black-purple beam along the real line",
			wanted = {
				"vortex rumble",
				"curse crawling squelch",
				"streams rushing in",
				"compression whine",
				"spiral beam drill",
			},
		},
		starless_burst = {
			tier = 4,
			preroll = 0.85,
			linger = 0.9,
			look = "staff up, calm; a white and pale-blue magic circle opens ring by ring (one more ring per earlier cast), glyphs riding it; light gathers; stillness; a clean thin beam along the real line, a bright groove, small impacts; a flickering hexagonal barrier; NOT fiery",
			wanted = { "soft magic hum", "glyph ring clicks", "clean high beam", "barrier shimmer" },
		},
		echo_legion = {
			tier = 4,
			preroll = 0.9,
			linger = 1.3,
			look = "two shadow clones pop in and help form a blue sphere over his raised hand, four white blades spinning out; clones vanish in smoke; the throw; it opens into a wide wind sphere on the first real hit, pulses and cuts on each of the next, collapses in a burst on the last (no generic clones)",
			wanted = { "clone pop", "rising wind whine", "throw whoosh", "four wind hits", "collapse burst" },
		},
		elastic_wardrum = {
			tier = 4,
			preroll = 0.6,
			linger = 0.8,
			look = "into Gear 2: bouncing leg pumps, pink-white steam, a gush on the form change; into Gear 3: thumb to mouth, swell, white clouds and white flame, laughing with arms wide; later casts: drumbeat rings, then a giant stretched fist slams down around him, a bouncing cartoon shockwave, shield shimmer",
			wanted = {
				"steam pump hiss",
				"thumb blow and inflate",
				"drumbeats",
				"rubber fist stretch and slam",
				"laugh",
			},
		},
		-- Tier 3 -------------------------------------------------------------------------------
		thunder_nest = {
			tier = 3,
			preroll = 0.4,
			linger = 0.8,
			look = "crackling head, drops low with a claw hand; a three-kink zig-zag of lightning from start to landing on the real dash; a lightning dome snaps out 1 hex on the real hit; stunned enemies twitch with arcs; he stands",
			wanted = { "electric crackle", "thunderclap dash", "dome zap" },
		},
		horizon_cut = {
			tier = 3,
			preroll = 0.75,
			linger = 0.75,
			look = "cleaver raised two-handed, black-red energy pouring off it, ground darkens; the swing launches a black crescent with a red rim that crosses the board onto the real hit, a scorched line behind it; a black-red slash cross on the target; blade rests on his shoulder",
			wanted = { "dark energy roar", "huge swing whoosh", "crescent tearing the air", "slash impact" },
		},
		snapfire = {
			tier = 3,
			preroll = 0.45,
			linger = 0.6,
			look = "calm gloved hand up with a spark ring; a tiny snap; a fuse of fire races along the ground; orange flame and black smoke over the real area; a bigger second burst when the target was already burning; he lowers his hand unbothered",
			wanted = { "finger snap", "fuse sizzle", "fire explosion", "secondary blast" },
		},
		clockbreaker = {
			tier = 3,
			preroll = 0.4,
			linger = 1.35,
			look = "hands in his pockets, brim down, the whole time; a purple spirit fades in behind him and lunges past him; fist afterimages pour into the target with a small impact on each real hit; a big burst and hit-stop on the real last hit; the spirit fades back",
			wanted = { "spirit appear hum", "rapid punch barrage", "final heavy punch" },
		},
		titanheart = {
			tier = 3,
			preroll = 0.4,
			linger = 0.6,
			look = "cast: plant and draw back with steam venting, a heavy blow with steam and a crack. Real form change into the titan (a health trigger, not a cast; in the lineup press F): a yellow bolt from the sky, a huge flash, steam explosion, roar with steam; back to human: a steam burst and a stumble",
			wanted = { "lightning strike", "steam explosion", "titan roar", "steam collapse" },
		},
		skyboulder = {
			tier = 3,
			preroll = 0.5,
			linger = 0.9,
			look = "store model: a boulder appears at his side and crumbles; he turns far away, sinks, then whips around and lunges; a spray of fragments across the real cone cells, the nearest biggest, dust where they land; an earthen glow for his armor",
			wanted = { "rock crunch", "big throw grunt", "gravel spray", "stone thuds" },
		},
		volt_spear = {
			tier = 3,
			preroll = 0.45,
			linger = 0.7,
			look = "hand down and back with a crackling blue-white ball and a rapid chirp; drops low; a lightning-torn groove along the real lunge; a burst of lightning through the target (the stun and burn markers are the real ones)",
			wanted = { "chirping lightning", "lunge crack", "lightning burst" },
		},
		mirror_script = {
			tier = 3,
			preroll = 0.45,
			linger = 0.6,
			look = "lifts his headband, a red eye with marks turning; copy: a flickering red ghost of the copied pose over him, a red thread from the copied enemy, the copied effects with red sparks; no copy: lightning in his hand, a quick lightning-blade stab (needs an enemy cast first to see the copy: in a real fight)",
			wanted = { "eye activation hum", "copy whoosh", "lightning blade chirp" },
		},
		threefold_crash = {
			tier = 3,
			preroll = 0.25,
			linger = 1.35,
			look = "third sword in his teeth, two crossed, green aura; a right cut and a crossing left cut on the two real hits; a 1.5-turn spin with arms wide on the real area hit, a green tornado of rings and cuts; holds with his back to the enemy, then turns back",
			wanted = { "blade unsheathe", "two quick slashes", "tornado spin whoosh" },
		},
		zero_field = {
			tier = 3,
			preroll = 0.4,
			linger = 1.9, -- through the hold (up to 1.25 s) and the drop
			look = "fingertips touch, pink pads glow, a tap; pink rings over the area; every held enemy floats up turning in a pink glow; a pink pulse under each sped-up ally; she claps and they slam down on the real end-of-hold hits, dust and pink rings",
			wanted = { "soft float hum", "clap", "heavy drop thuds" },
		},
		-- Tier 2 -------------------------------------------------------------------------------
		redline_cut = {
			tier = 2,
			preroll = 0.2,
			linger = 0.6,
			look = "head snaps toward the threat, red scarf flicks; a cable and gas puff on the real dash; a full spin with a red cut on the real hit; lands with blades crossed, a red ring for her attack speed",
			wanted = { "cable zip", "gas hiss", "spin cut" },
		},
		orbit_breaker = {
			tier = 2,
			preroll = 0.35,
			linger = 0.5,
			look = "a steel ball spinning in his palm with gold motes circling; a sidearm whip throws it to the target; a golden spiral shock on the real hit and on each real bounce (rider: check from the horse)",
			wanted = { "spinning ball whirr", "sidearm throw", "metal ricochet pings" },
		},
		crimson_hunger = {
			tier = 2,
			preroll = 0.3,
			linger = 0.65,
			look = "four crimson tendrils flare out from his back, one red eye; they lash onto the target together; the burst grows bigger and darker the more hurt he is; on a real kill-heal red light is drawn back into him",
			wanted = { "wet tendril lash", "crimson impact", "drain on kill" },
		},
		shade_pack = {
			tier = 2,
			preroll = 0.25,
			linger = 0.5,
			look = "first cast: a dog hand sign, a black wolf with lit eyes rises from his shadow on each real summon; later casts: hands high, a dark circle over the target, a shadow elephant drops onto the real area with a dark splash",
			wanted = { "hand sign clap", "wolf snarl", "heavy elephant drop splash" },
		},
		marsh_fortress = {
			tier = 2,
			preroll = 0.4,
			linger = 0.5,
			look = "puffs up with pipe smoke; a big hop that lands exactly on the real hit; a water-splash ring over 1 hex with mud and bubbles; blue-green motes into him for the real heal",
			wanted = { "toad croak", "big hop", "water splash slam" },
		},
		flare_kick = {
			tier = 2,
			preroll = 0.15,
			linger = 0.65,
			look = "a full spin on one leg as the leg catches fire; a fire trail along the real dash and a flaming kick burst on the real hit; lands on one foot and straightens his tie",
			wanted = { "fire whoosh spin", "kick impact" },
		},
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
