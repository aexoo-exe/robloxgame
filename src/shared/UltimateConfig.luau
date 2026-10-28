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
	-- anticipation kept when compressing (a fraction of `preroll`). The floor is 0.6 for every tier:
	-- below it, from the match camera an ultimate read as a ~1 s flicker. A module that knows its
	-- beats can spend the compression on its holds first (Cinematic run.k; cinder_arc does).
	tiers = {
		[1] = { camera = false, dim = false, shake = 0.08, minShare = 0.6 },
		[2] = { camera = false, dim = false, shake = 0.12, minShare = 0.6 },
		[3] = { camera = false, dim = false, shake = 0.2, minShare = 0.6 },
		[4] = { camera = true, dim = true, shake = 0.32, minShare = 0.6 },
		[5] = { camera = true, dim = true, shake = 0.45, minShare = 0.6 },
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
			-- The two-orb build, a shivering set, dead stillness, the merge snap, the load, the flick on the real hit.
			preroll = 1.34,
			linger = 1.3, -- through the follow-through, the hand-in-pocket stand, idle (+1.05) and the motes' fade
			look = "calm stop; a blue orb on the right hand pulls motes in, a red orb on the left pushes them out; arms spread and held, shivering, then dead still; the hands slam together into a violet sphere, cocked and flicked at the target far faster than the build; a hollow violet shell and one ring erase the area on the real hit; hand in pocket",
			wanted = {
				"energyCharge low (blue orb)",
				"energyCharge high (red orb)",
				"windGust short and high (the merge)",
				"energyRelease (the flick)",
				"impactHeavy, then a low windGust (the erasure)",
			},
		},
		severing_temple = {
			tier = 5,
			-- The hand sign, the raised hand while the shrine rises, the bell and stillness, the load, the sweep on the real hit.
			preroll = 1.23,
			linger = 4.3, -- through the 4 s damage over time and its tick cuts (the pose ends at +1.6, the shrine is gone by +1.3)
			look = "a hand sign; the right hand raised overhead while a dark shrine climbs out of the ground behind the area and the floor darkens; a deep bell and dead stillness; the hand sweeps down and out on the real hit and the area fills with cuts that wipe in and vanish; every enemy staggers; the shrine sinks; fresh cuts on each enemy at every real tick",
			wanted = {
				"energyCharge low (the sign)",
				"magicChime pitched down, a deep bell (the stillness)",
				"impactHeavy (the hit)",
				"slashMetal, rapid (the storm)",
			},
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
			-- Bored, straightening, the slow draw, stillness, the load, the punch on the real hit.
			preroll = 1.38,
			linger = 1.5, -- through the follow-through, back to bored (+0.85), idle (+1.3) and the crack's fade (+1.2)
			look = "slouched and bored, then straight; the fist draws back slowly inside a bend of air with a low aura, dust lifts; stillness while the camera goes face then fist; an almost invisible punch on the real hit with a step into it; a brief white flash, a cone of air past the target, one shock ring, a long crack along the punch, dust and stones; back to bored",
			wanted = {
				"windGust low, then high (the draw, the stillness)",
				"impactHeavy + groundSlam (the punch)",
				"rockDebris (after)",
			},
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
			-- Calm, the circle opening ring by ring while light gathers at the staff, stillness, the load, the thrust on the real hit.
			preroll = 0.98,
			linger = 1.0, -- through the follow-through, the staff lowered (+0.6), idle (+0.95) and the groove's fade (+0.8)
			look = "staff upright, calm, the left palm out; a pale magic circle opens ring by ring before her (one more ring per earlier cast), glyphs riding it, light gathering at the staff's head; dead stillness; the staff thrust at the target on the real hit, one thin clean white beam along the real line and a bright groove; small pale hit stars; NOT fiery",
			wanted = {
				"magicChime, high, per ring (the circle's clicks)",
				"energyCharge (the gathering light)",
				"energyRelease (the beam)",
			},
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
			-- The pumps, the swell (by cast: the raised swelling fist, the thumb blow, more pumping), stillness, the load, the payoff.
			preroll = 0.96,
			linger = 1.1, -- through the giant fist's snap back (+0.3), the laugh (+0.5) and idle (+1.0)
			look = "bouncing leg pumps with pink-white steam on every cast; into Gear 2: a steam gush; into Gear 3: thumb to mouth, swell, white clouds and a white flame aura, arms flung wide; later casts: the fist raised and swelling, drumbeat rings, then a giant stretched fist slams down in front of him with a bouncing shock ring; he deflates laughing",
			wanted = {
				"punchRush (the drumbeats)",
				"energyCharge (the thumb blow)",
				"whooshHeavy (the stretch, the gush)",
				"impactHeavy (the slam)",
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
		field_medic = {
			tier = 2,
			preroll = 0.3,
			linger = 0.5,
			look = "medic: a little bag pops, a green cross turns above him, gentle green rings roll out and motes rise on each really healed ally; bruiser: claws back, a heavy swipe with dark claw marks; the real change into the bruiser (press F in the lineup): a blue pill flash, a puff of fur and steam, a roar",
			wanted = { "medicine bag pop", "gentle heal chime", "pill gulp", "monster roar", "claw swipe" },
		},
		burst_vector = {
			tier = 2,
			preroll = 0.35,
			linger = 0.5,
			look = "palms pop with sparks; a palm blast under him rocket-jumps him up; a big orange explosion with black smoke on the real area as he lands; crouch and an orange ring for his buff",
			wanted = { "palm crackle pops", "rocket-jump blast", "big explosion" },
		},
		skybreaker = {
			tier = 2,
			preroll = 0.3,
			linger = 0.55,
			look = "green lightning crackles over him, fist drawn back; the smash on the real hit with a pressure cone, and green pressure streaks with dust carrying through the real line behind the target",
			wanted = { "electric crackle", "smash boom", "air pressure rush" },
		},
		-- Tier 1 -------------------------------------------------------------------------------
		flashline = {
			tier = 1,
			-- The quick-draw: coil, shivering set, dead stillness, load dip, the draw on the real hit.
			preroll = 0.93,
			linger = 1.65, -- through the delayed cut, the slow sheathe (+0.85), the slide home (+1.45) and the trail's fade
			look = "crouched quick-draw stance with gold crackle, a held beat of dead stillness; the draw on the real hit dashes him through the target with crisp gold lightning bolts and a gold blade trail; the target is cut a split second after he is past; a low follow-through, a slow sheathe with a click, slide home",
			wanted = { "thunder crack", "sheathe click" },
		},
		cinder_arc = {
			tier = 1,
			-- The vertical slice: a three-strike spiral, the finisher on the real hit (client only).
			preroll = 1.3,
			linger = 1.25, -- through the hop, the recovery and the slide home (+0.92) and the trails' fade
			look = "deep twisted coil, blade far back, heat on it; a dash into a spin slash, a rising backhand, a load dip and a leaping finisher on the real hit: blade trails, hit-stops, staggers and a launch, the fire bloom; he hops, lands, slides home",
			wanted = { "ember crackle", "fire arc swing" },
		},
		wolfstep = {
			tier = 1,
			preroll = 0.15,
			linger = 0.5,
			look = "low crouch, daggers reversed; the lunge on the real dash; two crossed cuts on the real hit (the X); a skid of dust as he stops",
			wanted = { "dagger draw", "two quick cuts", "skid" },
		},
		spurshot = {
			tier = 1,
			preroll = 0.2,
			linger = 0.5,
			look = "he points, a gold nail spinning at his fingertip; a spiral shot to the target and a gold ring under it (the slow marker is real); green motes back to the horse (rider: check from the saddle)",
			wanted = { "spinning nail whine", "spiral gunshot" },
		},
		ripcord_frenzy = {
			tier = 1,
			preroll = 0.25,
			linger = 0.6,
			look = "first cast: grabs the cord on his chest and yanks; on the real form change smoke, orange sparks and a hunched shuddering roar; later casts: a rev with sparks and a small green-orange heal glow. No blood",
			wanted = { "cord yank", "chainsaw engine rev", "roar" },
		},
		null_edge = {
			tier = 1,
			preroll = 0.2,
			linger = 0.5,
			look = "the black sword hoisted overhead, black flakes rising off it; a heavy chop with a black slash and erased-magic sparks on the real hit; black wisps at his feet for the magic resist",
			wanted = { "heavy blade lift", "chop impact", "anti-magic fizz" },
		},
		bitter_vapor = {
			tier = 1,
			preroll = 0.2,
			linger = 0.6,
			look = "she lifts a vial, sniffs, tosses it; it arcs onto the target and shatters as the real poison lands, a green bubbling cloud over the area (markers are real); a green leaf drifts to the ally she really heals",
			wanted = { "vial uncork sniff", "glass shatter", "bubbling" },
		},
		iron_rush = {
			tier = 1,
			preroll = 0.2,
			linger = 0.45,
			look = "store model: plates flash gold, steam vents; shoulder down, a dusty stomp; the ram on the real hit with a gold flash, and a scrape along the real knockback (the stun stars are real)",
			wanted = { "armor clank", "stomp", "heavy ram crunch", "scrape" },
		},
		blooming_aid = {
			tier = 1,
			preroll = 0.2,
			linger = 0.5,
			look = "heal: green glow between her palms, reaching out; motes stream to the really healed ally with pink petals of light. Punch (no one low): a pink glowing fist, a punch into the ground and a crack racing to the target into a spiderweb",
			wanted = { "soft heal chime", "glove tug", "ground punch crack" },
		},
	},
})
