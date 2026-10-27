# VFX + Sound Overhaul Plan

Every ultimate rebuilt to the playbook standard ([ultimate-playbook.md](ultimate-playbook.md)):
coil / set -> snaps -> the finisher on the real hit -> recover and slide home, poses about 2x,
trails on weapons and limbs, ViewScale on readable layers, half the tier budget at peak, library
sounds ([sound-picks.md](sound-picks.md)). Done: **cinder_arc** (template) and **flashline**. The
other 40 below are grouped in waves of 3 (one of 4) that share assets and patterns, so the first unit
of a wave builds what the other two reuse. Progress: [overhaul-queue.md](overhaul-queue.md). Build each
with `/slice-unit <unit_id> "<concept>"` using the concept below.

**Order.** Most visible first. The playtest unit pick rates (PlaytestMatches "units",
`scripts/playtest-report`) don't exist yet, so waves are ordered by cost and tier (the 5-costs and
tier 4-5 ultimates are what players chase and remember); re-order the later waves once pick rates
come in.

Kit names below: `VfxRecipe` (kitBolts, kitCrackleAura, kitAuraSpike, kitHitStar, kitSpeedLines,
kitDust, kitFireBurst, kitSteam, kitSwoosh, kitBurst, meshRing, flames, embers, sparks, smoke,
debris, splash, shock, arcs), `UltimateKit` (orb, converge, shell, groove, pool, beam, slashes,
aura, streaks, zap, drift), `ImpactEffects` (ring, flatRing, light, impactFrame), `BladeTrail`
(weapon and limb trails), `HitFeel`, `UltimateCallout`. Sounds are library names.

## Waves

| # | Archetype | Units (in build order) | Shared assets and patterns |
|---|---|---|---|
| 1 | Domains and big magic | infinite_collapse, severing_temple, starless_burst | UltimateKit.orb / shell / beam, meshRing layers, a held "stillness" beat, camera cue (tier 4-5) |
| 2 | Heavy brawlers | final_argument, elastic_wardrum, reelbreaker | fist trails (BladeTrail on the hand), shock cones, kitDust ground cracks, impactHeavy layering |
| 3 | Energy blasts | ascending_core, echo_legion, skybreaker | charge with converge + kitAuraSpike, release beams / spheres, crackle on the body |
| 4 | Titans and heavy | boiling_crown, titanheart, skyboulder, iron_rush | kitSteam, debris, ground cracks, slow heavy timing, store-model poses |
| 5 | Spirits and rush | clockbreaker, frozen_moment, restoration_strike | a spirit figure behind the caster (shell + tinted afterimage), fist rush streaks, time-freeze tint |
| 6 | Summons and shadows | night_command, night_parade, shade_pack | UltimateKit.pool, dark rising silhouettes, eye glows, summon pop-ins on real summon cells |
| 7 | Swords I | cyclone_edge, redline_cut, horizon_cut | BladeTrail cuts, cable lines (UltimateKit.streaks), spin slashes, kitSwoosh finisher |
| 8 | Lightning and speed | thunder_nest, volt_spear, mirror_script | kitBolts, kitCrackleAura, zig-zag dash paths, chirp / buzz cues |
| 9 | Fire and explosions | snapfire, burst_vector, flare_kick | kitFireBurst, flames re-emitted short, smoke, explosion layering |
| 10 | Support and healing | zero_field, field_medic, blooming_aid | soft rings, motes to healed allies (converge), heal twinkles, float / slam poses |
| 11 | Swords II | threefold_crash, null_edge, wolfstep | three-trail cuts, erase sparks, crossed X cuts, skid dust |
| 12 | Bruisers | crimson_hunger, ripcord_frenzy, marsh_fortress | tendril / limb trails, roars and shudders, splash rings |
| 13 | Marksmen and throws | orbit_breaker, spurshot, bitter_vapor | spinning projectile arcs, spiral shocks, thrown-object arcs with a landing cloud |

## Concepts

Format: tier, then the beats (anticipation -> real hit -> recover), **signature moment**, trails,
kit reuse, sounds.

### Wave 1: domains and big magic

**infinite_collapse** (tier 5). Calm stop; one hand draws a blue orb that pulls motes in
(converge), the other pushes a red orb out; the set holds both apart, shivering, then a dead-still
beat. The snap brings them together into a violet sphere (UltimateKit.orb) flicked at the target,
much faster than the build; erasure on the real hit: a hollow shell and a meshRing, a camera push.
Recover: hand back in pocket. **Signature:** the slow two-orb build vs the instant flick. Trails:
the flick hand. Reuse: orb, converge, shell, meshRing, impactFrame. Sounds: energyCharge (x2,
pitched apart), energyRelease, impactHeavy, windGust.

**severing_temple** (tier 5). A hand sign coil; the set raises a dark shrine behind the area
(UltimateKit.block layers rising), the floor darkens (pool). A bell-like beat of stillness, then
the area fills with fast cuts on the real hit (UltimateKit.slashes, many short trails), every enemy
staggering. Recover: shrine sinks. **Signature:** the stillness, then the cut storm. Reuse: pool,
block, slashes, kitHitStar. Sounds: magicChime (deep, as a bell), slashMetal (rapid), impactHeavy.

**starless_burst** (tier 4). Staff raised, calm; a pale magic circle opens ring by ring
(meshRing + flatRing, one more ring per earlier cast), glyphs riding it; light gathers at the staff
tip (converge); stillness; one clean thin beam along the real line (UltimateKit.beam, white core),
a bright groove (UltimateKit.groove). Recover: staff lowers. **Signature:** the growing circle and
a beam that is thin, not fat. Reuse: meshRing, flatRing, converge, beam, groove. Sounds:
magicChime, energyCharge, energyRelease.

### Wave 2: heavy brawlers

**final_argument** (tier 5). Slouched and bored, then straightens; the fist draws back slowly
(a 0.5 s set with a bend of air, kitAuraSpike low), dust lifts; camera goes face then fist; an
almost invisible punch on the real hit: white impactFrame, a huge shock cone, a long ground crack.
Recover: back to bored. **Signature:** the boredom-to-punch contrast and the white flash. Trails:
a short fist trail. Reuse: shock, kitDust, groove, impactFrame. Sounds: windGust (rising),
impactHeavy, groundSlam, rockDebris.

**elastic_wardrum** (tier 4). Coil with bouncing leg pumps and pink-white steam (kitSteam);
the set swells an arm (pose scale) with white clouds; drumbeat rings (flatRing x3 on beats); a giant
stretched fist on the real hit with a shock ring. Recover: deflates, laughing pose. **Signature:**
the stretched giant limb. Trails: long fist trail. Reuse: kitSteam, flatRing, shock. Sounds:
punchRush (drumbeats), impactHeavy, whooshHeavy.

**reelbreaker** (tier 4). Rod overhead and whipped forward; the line flies to the farthest enemy and
holds taut (UltimateKit.streaks as the line); the free fist draws back glowing yellow-green and
growing (kitAuraSpike on the hand); yank and punch together on the real hit: the target pulled in
and struck. Recover: rod shouldered. **Signature:** the taut line and the growing fist. Trails: rod
tip and fist. Reuse: streaks, kitAuraSpike, kitHitStar. Sounds: whooshLight, energyCharge,
impactHeavy.

### Wave 3: energy blasts

**ascending_core** (tier 5). Fists clench and a yell; gold aura spikes climb (kitAuraSpike) with
blue sparks; hands cupped at the hip, light growing between them (orb), stones float (drift); a held
stillness; a thick beam on the real hit (beam + groove) with a camera cue. Recover: aura settles.
**Signature:** the cupped-hands charge. Trails: hands. Reuse: kitAuraSpike, orb, drift, beam,
groove. Sounds: energyCharge, electricBuzz, energyRelease, explosion.

**echo_legion** (tier 4). Two shadow clones pop in (smoke puffs) and help form a blue sphere over
his raised hand (orb), four white blades spinning out; clones vanish in smoke; the throw; on the
real hit the sphere opens into a wide wind sphere (shell + windGust) that pulses. Recover: hand
shaken out. **Signature:** the clones building it. Reuse: smoke, orb, shell, meshRing. Sounds:
energyCharge, windGust, impactHeavy.

**skybreaker** (tier 2). Green lightning crackles over him (kitCrackleAura) as the fist draws back;
a load dip; the smash on the real hit with a pressure cone (shock) and green streaks carrying
through the real line behind the target (streaks, kitDust). Recover: arm hangs, wince. **Signature:**
the crackle on the body. Trails: fist. Reuse: kitCrackleAura, shock, streaks. Sounds: electricBuzz,
impactHeavy, windGust.

### Wave 4: titans and heavy

**boiling_crown** (tier 5, store model). Sinks and trembles, steam thickening white to orange
(kitSteam), a glow in the chest, the ground blackens and cracks (groove, pool); stillness; an
eruption column and dome on the real hit (steamColumn, shell), he heaves up and back; steam rolls
out. **Signature:** the slow, heavy heat build. Reuse: kitSteam, steamColumn, shell, groove,
debris. Sounds: fireCrackle, explosion, groundSlam.

**titanheart** (tier 3). Plant and draw back with steam venting; a heavy blow with steam and a crack
on the real hit. The form change (health trigger): a bolt from the sky (kitBolts), a huge flash
(impactFrame), steam everywhere. **Signature:** the transformation bolt. Trails: fist. Reuse:
kitSteam, kitBolts, impactFrame, kitDust. Sounds: lightningCrack, explosion, impactHeavy.

**skyboulder** (tier 3, store model). A boulder appears at his side; he turns far away, sinks, then
whips around and lunges; a spray of fragments across the real cone cells (debris), the nearest
biggest, dust where they land. **Signature:** the whip-around throw. Trails: throwing arm. Reuse:
debris, kitDust, rockDebris pattern. Sounds: whooshHeavy, rockDebris, groundSlam.

**iron_rush** (tier 1, store model). Plates flash gold (light), steam vents; shoulder down, a dusty
stomp; the ram on the real hit with a gold flash and a scrape along the real knockback (kitDust).
**Signature:** the shoulder-down ram. Reuse: kitSteam, kitDust, kitHitStar. Sounds: groundSlam,
impactHeavy.

### Wave 5: spirits and rush

**clockbreaker** (tier 3). Hands in pockets, brim down the whole time; a tall spirit fades in behind
him (shell + tinted silhouette) and lunges past him; fist afterimages pour into the target with a
small impact on each real hit; a big burst and hit-stop on the last. **Signature:** he never moves,
the spirit does everything. Trails: spirit fists. Reuse: shell, streaks, kitHitStar. Sounds:
punchRush, impactHeavy.

**frozen_moment** (tier 4). Arms flung wide, a small gold sphere and a ticking clock under him; on
the real stun the sphere snaps over the area and the color drains (a tint), frozen enemies glazed;
he flicks knives that hang in the air pointed at the targets, then drop in as time resumes on the
real hits. **Signature:** the frozen, colorless beat. Reuse: shell, flatRing, kitHitStar. Sounds:
magicChime (clock tick), slashMetal, windGust.

**restoration_strike** (tier 4). A pink spirit with a tall crest fades in behind him; diamond shards
swirl in and lock into the real shield; pink beams to each really healed ally whose cracks close
with sparkles; the spirit throws three quick punches. **Signature:** cracks closing. Reuse: shell,
converge, sparks, beam. Sounds: healTwinkle, punchRush, magicChime.

### Wave 6: summons and shadows

**night_command** (tier 4). Hand raised, eyes glow purple, mist at his feet; a black-purple pool
spreads under him (pool); stillness and a push; a dark silhouette with lit eyes rises out of the
pool at each real summon cell; pool drains, daggers glint. **Signature:** the eyes in the pool.
Reuse: pool, shell, drift. Sounds: windGust (low), magicChime (dark), energyRelease.

**night_parade** (tier 4). Summon cast: palm up, a dark vortex turns over it (orb + streaks), a curse
drops out onto each real summon cell. Firing cast: curses come apart into dark streams into the palm,
a ball tightens and darkens, a push and the streak to the target on the real hit. **Signature:** the
streams into the palm. Reuse: orb, converge, streaks, pool. Sounds: energyCharge, energyRelease.

**shade_pack** (tier 2). A dog hand sign; a black wolf with lit eyes rises from his shadow on each
real summon (pool + drift); later casts: hands high, a dark circle over the target, a shadow shape
drops onto the real area with a dark splash (splash, tinted). **Signature:** the hand sign and the
rising shape. Reuse: pool, splash, drift. Sounds: windGust, groundSlam.

### Wave 7: swords I

**cyclone_edge** (tier 4). Two cables shoot from his hips to the target (streaks), gas puffs; he
sinks and launches; the whole body spins into a blade tornado on the real dash, a whirl of rings
and cuts on the real hit; a low crouch after. **Signature:** the spinning tornado. Trails: two
blades, reverse grip. Reuse: streaks, smoke, slashes, meshRing, BladeTrail. Sounds: whooshHeavy,
slashMetal, windGust.

**redline_cut** (tier 2). Head snaps toward the threat, scarf flicks; a cable and gas puff on the
real dash; a full spin with a red cut on the real hit; lands with blades crossed, a red ring for
her attack speed. **Signature:** the scarf flick and the crossed landing. Trails: two thin blades.
Reuse: streaks, smoke, kitSwoosh, flatRing. Sounds: whooshLight, slashMetal.

**horizon_cut** (tier 3). Cleaver raised two-handed, black-red energy pouring off it (kitAuraSpike on
the blade), ground darkens; the swing launches a black crescent with a red rim that crosses the
board onto the real hit (kitSwoosh, travelling), a scorched line behind it (groove). **Signature:**
the travelling crescent. Trails: the cleaver. Reuse: kitAuraSpike, kitSwoosh, groove. Sounds:
energyCharge, whooshHeavy, slashMetal, impactHeavy.

### Wave 8: lightning and speed

**thunder_nest** (tier 3). Crackling head, drops low with a claw hand (kitCrackleAura); a
three-kink zig-zag of lightning from start to landing on the real dash (kitBolts per segment); a
lightning dome snaps out on the real hit (shell + arcs); stunned enemies twitch with arcs.
**Signature:** the zig-zag path. Trails: claw hand. Reuse: kitCrackleAura, kitBolts, shell, arcs.
Sounds: electricBuzz, lightningCrack.

**volt_spear** (tier 3). Hand down and back with a crackling blue-white ball (orb + arcs) and a rapid
chirp; drops low; a lightning-torn groove along the real lunge (groove + kitBolts); a burst through
the target on the real hit. **Signature:** the chirping ball in the hand. Trails: the hand. Reuse:
orb, arcs, groove, kitBolts. Sounds: electricBuzz (chirp), lightningCrack.

**mirror_script** (tier 3). Lifts his headband, a red eye with turning marks; copy: a flickering red
ghost of the copied pose over him (shell, tinted), a red thread from the copied enemy (streaks), the
copied effects with red sparks; no copy: lightning in his hand and a quick strike. **Signature:** the
red ghost pose. Reuse: shell, streaks, sparks, arcs. Sounds: magicChime, electricBuzz,
lightningCrack.

### Wave 9: fire and explosions

**snapfire** (tier 3). Calm gloved hand up with a spark ring; a tiny snap; a fuse of fire races
along the ground (flames re-emitted along a path); orange flame and black smoke over the real area
(kitFireBurst, smoke); a bigger second burst on an already burning target. He lowers his hand,
unbothered. **Signature:** the tiny snap vs the big burst. Reuse: sparks, flames, kitFireBurst,
smoke. Sounds: fireCrackle (snap), fireBurst, explosion.

**burst_vector** (tier 2). Palms pop with sparks; a palm blast under him rocket-jumps him up (rise);
a big orange explosion with black smoke on the real area as he lands; crouch and an orange ring for
his buff. **Signature:** the rocket jump. Trails: both palms. Reuse: kitFireBurst, smoke,
flatRing. Sounds: explosion, fireBurst.

**flare_kick** (tier 2). A full spin on one leg as the leg catches fire (flames on the foot,
re-emitted short); a fire trail along the real dash; a flaming kick burst on the real hit; lands on
one foot and straightens his tie. **Signature:** the burning leg. Trails: the kicking leg (limb
trail). Reuse: flames, kitFireBurst, embers. Sounds: whooshHeavy, fireBurst, impactLight.

### Wave 10: support and healing

**zero_field** (tier 3). Fingertips touch, pink pads glow, a tap; pink rings over the area
(flatRing); every held enemy floats up turning in a pink glow (rise poses); a pink pulse under each
sped-up ally; she claps and they slam down on the real end-of-hold hits (dust). **Signature:** the
float, then the clap and slam. Reuse: flatRing, drift, kitDust. Sounds: magicChime, groundSlam.

**field_medic** (tier 2). Medic: a small bag pops, a green cross turns above him, gentle green rings
roll out and motes rise on each really healed ally (converge). Bruiser: claws back, a heavy swipe
with dark claw marks; the real change into the bruiser with a puff. **Signature:** the turning cross.
Reuse: flatRing, converge, slashes. Sounds: healTwinkle, whooshHeavy, impactLight.

**blooming_aid** (tier 1). Heal: green glow between her palms, reaching out; motes stream to the
really healed ally with pink petals of light. Punch (no ally low): a pink glowing fist, a punch into
the ground and a crack racing to the target. **Signature:** the ground crack punch. Trails: fist.
Reuse: converge, groove, kitDust. Sounds: healTwinkle, groundSlam.

### Wave 11: swords II

**threefold_crash** (tier 3). Third sword in his teeth, two crossed, a green aura; a right cut and a
crossing left cut on the two real hits; a 1.5-turn spin with arms wide on the real area hit, a green
tornado of rings and cuts; holds with his back turned. **Signature:** three trails at once. Trails:
three blades. Reuse: BladeTrail x3, slashes, meshRing. Sounds: slashMetal, whooshHeavy.

**null_edge** (tier 1). The black sword hoisted overhead, black flakes rising off it (drift); a heavy
chop with a black slash and erase sparks on the real hit; black wisps at his feet for the magic
resist. **Signature:** the oversized black chop. Trails: the greatsword. Reuse: drift, kitSwoosh,
sparks. Sounds: whooshHeavy, slashMetal, impactHeavy.

**wolfstep** (tier 1). Low crouch, daggers reversed; the lunge on the real dash; two crossed cuts on
the real hit (the X); a skid of dust as he stops. **Signature:** the X. Trails: two daggers. Reuse:
BladeTrail x2, kitHitStar, kitDust. Sounds: whooshLight, slashMetal.

### Wave 12: bruisers

**crimson_hunger** (tier 2). Four crimson tendrils flare from his back (limb-like trails), one red
eye; they lash onto the target together; the burst grows bigger and darker the more hurt he is; on a
real kill-heal red light is drawn back into him (converge). **Signature:** the four-tendril lash.
Reuse: streaks, kitHitStar, converge. Sounds: whooshHeavy, impactHeavy.

**ripcord_frenzy** (tier 1). First cast: grabs the cord on his chest and yanks; on the real form
change smoke, orange sparks and a hunched shuddering roar; later casts: a rev with sparks and a small
heal glow. No blood. **Signature:** the yank. Reuse: smoke, sparks. Sounds: electricBuzz (rev),
punchRush, healTwinkle.

**marsh_fortress** (tier 2). Puffs up with pipe smoke (smoke); a big hop (rise) that lands exactly on
the real hit; a water-splash ring over the area with mud and bubbles (splash, bubbles); motes into him
for the real heal. **Signature:** the hop and splash. Reuse: smoke, splash, bubbles, converge. Sounds:
waterSplash, groundSlam, healTwinkle.

### Wave 13: marksmen and throws

**orbit_breaker** (tier 2). A steel ball spinning in his palm with gold motes circling (orb +
drift); a sidearm whip throws it; a golden spiral shock on the real hit and on each real bounce.
**Signature:** the spiral. Trails: the ball. Reuse: orb, drift, meshRing. Sounds: whooshLight,
magicChime, impactLight.

**spurshot** (tier 1). He points, a gold nail spinning at his fingertip; a spiral shot to the target
and a gold ring under it (the slow marker is real); green motes back to the horse. **Signature:**
the spinning nail. Trails: the projectile. Reuse: orb, streaks, flatRing. Sounds: energyCharge
(short), whooshLight, impactLight.

**bitter_vapor** (tier 1). She lifts a vial, sniffs, tosses it; it arcs onto the target and shatters
as the real poison lands, a green bubbling cloud over the area (bubbles, smoke tinted); a green
leaf drifts to the ally she really heals. **Signature:** the sniff and the arcing vial. Trails: the
vial. Reuse: bubbles, smoke, drift. Sounds: whooshLight, magicChime (glass), waterSplash (soft).
