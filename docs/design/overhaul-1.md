# Overhaul 1: roster data, 30 ability reworks, traits and bonds

Status: implemented on `feature/overhaul-1`. **Every number below is a placeholder.** Section 7 lists
the Tuning A changes; where it differs from sections 1-4, section 7 is current. This pass is
about mechanics; balance comes later from the sim.

Character names in brackets are display names (they live only in `SkinConfig.luau`). Code and data
use the ids.

Where things live:

| What | File |
| --- | --- |
| Stats and ability amounts | `src/shared/UnitConfig.luau` |
| Ability switches and limits | `src/shared/AbilityConfig.luau` |
| Form numbers | `src/shared/FormConfig.luau` |
| Trait breakpoints and numbers | `src/shared/TraitConfig.luau` |
| Bonds | `src/shared/BondConfig.luau` |
| Fight-time trait and bond handlers | `src/shared/TraitCombat.luau` |
| Engine pieces | `Abilities.luau`, `Battle.luau`, `CombatSim.luau`, `Forms.luau`, `HexGrid.luau` |
| Placeholder visuals | `src/shared/RenderConfig.luau`, `src/client/CombatPlayback.luau`, `UnitView.luau`, `CombatEffects.luau`, `TraitPanel.luau` |

## 1. Roster data

- night_parade's display name is now **Keto** (was Bangs).
- Factions: snapfire moves to Corps, night_command to Arcane. Their body colors follow their
  faction color in SkinConfig.
- Classes: redline_cut Blade/Guardian, spurshot Marksman/Brawler, frozen_moment Assassin/Marksman,
  restoration_strike Support/Guardian, titanheart Guardian/Brawler, skyboulder Guardian,
  echo_legion Caster, flare_kick Brawler/Assassin, field_medic Support/Brawler.
- Membership after the changes: Hunters 5, Corps 4, Spirit 5, Cursed 6, Arcane 4, Titans 4,
  Shinobi 5, Crew 4, Heroes 5; Blade 10, Brawler 11, Caster 11, Marksman 6, Assassin 9,
  Guardian 8, Support 5.
- Stat identity (base health before the roster health dial, 1.403136 since Tuning A):

| Unit | Before | After |
| --- | --- | --- |
| spurshot | 550 HP, 64 AD, range 3, horse 220 | 650 HP, 56 AD, range 2, horse 300 |
| skyboulder | 900 HP, 76 AD, 38 armor, range 4 | 1050 HP, 64 AD, 50 armor, range 2 |
| restoration_strike | 1100 HP, 48 armor | 1200 HP, 58 armor |

Mana bars changed by Phase 3: spurshot 0/80 (it casts at full spin stacks, see below),
flare_kick 15/50 (was 30/90), starless_burst 20/160 (was 20/100).

## 2. Engine pieces

All are data, validated by `Abilities.validate`, `Abilities.validateUnit`, `Forms.validate` or
`Traits.validate`, simulated only on the server, and covered by `tests/OverhaulEngineTest.luau`.

### Effects and effect fields (Abilities)

| Piece | Data |
| --- | --- |
| Slow / reduced damage dealt | `DEBUFF` with `status` SLOW (attack and move speed) or WEAKEN (damage dealt); CURSE is the Cursed trait's |
| Burn, poison | `DAMAGE_OVER_TIME` `status` BURN or POISON; `weakenPercent` weakens the victim for the duration |
| LINE area | `AREA_DAMAGE shape = "LINE"`: caster through the center, `length` past it (none: to the board edge), `startAfterTarget` |
| CONE area | `AREA_DAMAGE shape = "CONE"`: `radius`, optional `angle` (half width, default 30), `falloff` percent per hex |
| Knockback | `KNOCKBACK`: one hex straight away from the caster, only if free |
| Bounce | `BOUNCE`: from the target to the nearest other enemy, `count` times, never the same enemy twice |
| Multi-hit over time | any effect's `delay` (seconds); `fixedCenter` keeps a delayed area where it was cast |
| Damage when a stun ends | `AREA_STUN damageOnEnd = { damageType, amount, healPercentOfDamage? }` |
| On kill | `condition = { type = "KILLED" }` |
| Missing-health scaling | `bonus = { type = "MISSING_HEALTH", percent }` |
| Bonus vs a status | `bonus = { type = "TARGET_STATUS", status, percent }` |
| "No ally needs healing" fallback | `condition = { type = "ALLY_BELOW", healthPercent, negate = true }` |
| Other conditions | `SUMMONS_ALIVE atLeast`, `ENEMY_HAS_CAST`, `CAST_CYCLE every, at` (cast number `at` of each cycle of `every`); all but KILLED are checked at cast start |
| N lowest-health allies | selectors `LOWEST_HP_ALLIES` / `LOWEST_HP_OTHER_ALLIES` with `count` |
| Heal per enemy hit | `AREA_DAMAGE healPerHit`; lifesteal `healPercentOfDamage` |
| Heal a form pool | `HEAL pool = true` |
| Summons that last until killed | `SUMMON permanent = true`; `manaPerHit` (summoner mana); `refill = true` |
| Recall | `RECALL` (no selector); `bonus RECALLED` scales later effects per summon recalled |
| Selectors | `ATTACKER_OF_LOWEST_ALLY` (fallback current target), `LOWEST_HP_ENEMY_NEARBY` (ability `nearbyRange`; fallback current target), `LARGEST_CLUSTER` (ability `clusterRadius`, default 2), `LAST_CASTER_ENEMY` |
| Stack bonus | `bonus STACKS`: per attack stack held when the cast began |

The bonus formula is always amount x (1 + factor x percent / 100), with factor the missing-health
fraction, 1/0 for a status, the stack count, or the summons recalled.

### Ability options

`castTime` (0 = instant cast), `resetAttackTimer`, `selfStun` (seconds), `nearbyRange`,
`clusterRadius`, `onTargetKilled = { window, maxRepeats, effects }` (follow-up when the caster's
target dies, as a new cast on the next tick), `formOnly` (no effects; the cast only fires the
form's ON_CAST trigger). Per-unit max and starting mana were already in UnitConfig.

### Forms

New triggers `ON_CAST` and `HEALTH_BELOW` (`belowPercent`), new form fields `range` and
`splash = { percent }` (basic attacks also hit enemies next to the target), triggers can be
`unlockedBy` a per-fight flag (the riders' bond). `maxUses = 1` is the once-per-fight limit.
Looks: `RenderConfig.formLooks[name]` can set `scale` (size) and `tint` (body color). See
`docs/forms.md`.

### Unit passives (Abilities.validateUnit)

- `aura = { radius, interval, damageType, amount, buffs = { { stat, flatPerEnemy } } }`: pulses all
  fight, even while stunned (victims gain at most `CombatConfig.auraManaCap` = 2 mana per pulse).
- `attackStacks = { max, castAtMax }`: basic attacks on one target build stacks (a new target starts
  over); with `castAtMax` the unit casts at max stacks instead of on mana, and its mana bar shows
  the stacks.

### Battle

Multiplier stats `DamageDealt`, `DamageTaken`, `MagicDamageTaken`, `HealPower` (start at 1),
`CritChance` and `CritDamage`; statuses (`Battle.Status`, `Battle.hasStatus`); hooks
(`Battle.addHook`: damageMultiplier, attack, cast, death, takedown, damaged, shieldBroken, tick);
a scheduler (`Battle.schedule`); `Battle.vanish` (untargetable, not acting); `Battle.execute`;
`Battle.knockback`, `Battle.recall`, `Battle.healFormPool`, `Battle.tickAuras`, `Battle.giveMana`.

### Events and playback

New events: `Area`, `Bounce`, `Knockback`, `FollowUp`, `Vanish`, `Mana`, `Mark`, `Meter`. Damage
events now carry `damageType` and tags (`area`, `splash`, `aura`, `stunEnd`, `execute`); Buff and
Dot events carry `status`. CastReader reads these first and falls back to the old matching.
Placeholder visuals: line/cone pulses, a bounce projectile, knockback slides, status labels
("Slowed", "Burning", ...), vanish see-through, callouts for marks and meter phases, form size and
tint, client-only clones for echo_legion's cast, and a "tongue" attack projectile for shade_pack.

## 3. Abilities (30 reworked)

The other 12 (flashline, cinder_arc, wolfstep, null_edge, burst_vector, thunder_nest,
horizon_cut, reelbreaker, night_command, severing_temple, final_argument, infinite_collapse) are
unchanged. Values are 1/2/3-star. "New" marks a placeholder chosen for this pass.

### Corps
- **redline_cut** [Mika]: dash up to 3 to `ATTACKER_OF_LOWEST_ALLY` (the enemy whose target is her
  lowest-health other ally; fallback current target), retarget, physical 215/345/550, then AS
  +20/32/50% for 4s (unchanged numbers).
- **cyclone_edge** [Revi]: unchanged cast. New: for 4s (the buff's duration) after each cast,
  when his current target dies he dashes up to 4 to the nearest enemy and repeats the area hit
  (radius 1, physical 330/525/840), at most `AbilityConfig.cycloneEdgeRepeats` = 2 times per cast.
- **snapfire** [Ray]: magic area radius 1 on current target 270/430/690 (was 300/480/770 on
  highest AD), +30% against burning enemies, then burn radius 1: magic 20/32/52 per second for 3s.

### Spirit
- **spurshot** [Jonny]: casts at **4 spin stacks** (not mana; the full-stacks option). Basic
  attacks on the same target build stacks; switching target starts over. Shot at current target:
  physical 120/190/305, +15% per stack (x1.6 at 4), SLOW 25/30/35% for 2s, then heals the horse
  pool 80/130/210 while Mounted, or himself 50/80/130 when Dismounted. Stacks are spent.
- **orbit_breaker** [Jyro]: physical 220/350/560 and stun 1/1.5/2s on current target, then a
  bounce of physical 100/160/250, no stun: 2 bounces while Mounted, 1 Dismounted.
- **clockbreaker** [Goataro]: four physical hits of 45/70/115 at 0, 0.25, 0.5, 0.75s, then
  physical 200/320/510 and stun 1/1.5/2s on that target at 1s. Cast time 1s. No area stun.
- **frozen_moment** [Za Warudo]: radius-2 area stun around himself 1/1.5/2s; each stunned enemy
  takes a physical knife hit of 180/290/460 when its stun ends; he heals 40% of that damage.
- **restoration_strike** [Joeskay]: shield himself 250/400/640 for 4s, heal his two lowest-health
  other allies 300/480/770 each (was one ally 450/720/1150), then physical 200/320/510. He never
  heals himself.

### Cursed
- **ripcord_frenzy** [Dengi]: first cast only transforms to **Chainsaw** for the rest of the fight
  (AS +35%, basic-attack splash 40%). Its ability there: heal himself 100/160/255.
- **crimson_hunger** [Kenny]: physical 200/320/510 on current target, +100% at no health left
  (scales with missing health); heals 250/400/640 only if the hit kills.
- **shade_pack** [Potential Man]: first cast summons 2/2/3 wolves that last until killed (30/35/40%
  HP, 45/50/55% AD, 50% armor/MR, 90% AS, melee, move 1.1); each wolf hit gives him 4 mana. Then
  form **Pack Out**: magic area radius 1 on current target 180/290/460, area stun radius 1
  0.75/1/1.25s, and dead wolves return (`shadePackResummon` = on). Ranged attack: tongue visual.
- **night_parade** [Keto]: a cast counter (`nightParadeCycle` = 3, CAST_CYCLE condition). Casts 1
  and 2 each summon a curse that lasts until killed (35/40/45% HP, 40/50/60% AD, 45% armor/MR, 85%
  AS, melee, move 1.0). Cast 3 recalls every living curse (even none) and fires a LINE from him
  through current target to the board edge: magic 120/190/305, +100% per curse recalled. Then the
  count starts over. (Tuning A: was "with 3 curses alive", which never happened.)

### Arcane
- **bitter_vapor** [Meow-Meow]: unchanged, and the poison now WEAKENs: victims deal 20/25/30% less
  damage while it lasts (4s).
- **starless_burst** [Archmage]: mana 20/160. One magic blast radius 2 on the largest enemy cluster
  (radius 2 counted) 600/960/1540, then a 2s self-stun. No shield.

### Titans
- **iron_rush** [Armored Giant]: armor +30/45/70 for 5s, dash up to 2 at current target (only as
  far as needed), physical 85/135/215, stun 0.75/1/1.5s, knockback 1 hex if free.
- **titanheart** [Aaron]: starts **Human** (AD -25%, armor -15, MR -15). Below 50% health, once per
  fight, becomes **Titan**: own pool 900 (1263 at 1 star after the dial), AD +35%, armor +15,
  splash 35%, drawn 1.35x larger. When the pool empties he is Human again. Ability in both forms:
  physical 250/400/640 on current target (placeholder from the director).
- **skyboulder** [Beast Giant]: physical CONE radius 2 toward current target 300/480/770, 40% less
  per hex past the first, then armor +30/45/70 for 5s.
- **boiling_crown** [Colossal Giant]: aura radius 1: magic 20/32/50 per second to each enemy
  inside, all fight; +8/12/18 armor and MR per enemy inside. Ability: magic blast radius 2 around
  himself 220/350/560. The old damage over time and self-buff are gone.

### Shinobi
- **blooming_aid** [Saku]: heal lowest-health ally 120/190/305 if any ally is below 70%
  (`bloomingAidHealBelowPercent`); otherwise physical 150/240/385 on current target.
- **marsh_fortress** [Toad Samurai]: no shield. Physical radius 1 around himself 110/175/280,
  healing himself 60/95/150 per enemy hit.
- **volt_spear** [Saucekay]: lunge up to 2 at current target, magic 300/480/770, stun
  0.75/1.25/1.75s, then burn magic 30/48/76 per second for 3s.
- **mirror_script** [Kashi]: copy the ability of the enemy that cast most recently (same cost
  scaling as before). If no living enemy has cast yet: magic 250/400/640 on current target.
- **echo_legion** [Fish Cake]: no summons. A projectile at current target becomes a radius-2 magic
  area hitting 110/175/280 four times (0.25, 0.5, 0.75, 1s), staying where the target stood. Two
  client-only clones appear during the cast. **Ability display name is a placeholder: "Echo
  Barrage" (flagged for renaming).**

### Crew
- **flare_kick** [Love-cook]: mana 15/50. Instant cast: dash up to 2 to the lowest-health enemy
  within 2 hexes (fallback current target), retarget, physical 110/175/280, attack timer reset. No
  splash.
- **field_medic** [Boku wa Docta]: heal all allies 45/70/110 (no shield). Below 50%, once per
  fight: **Bruiser** for the rest of the fight: range 1, AD +35, AS +20%, armor +15; its ability:
  physical 200/320/510 on current target (placeholder).
- **threefold_crash** [Moss Head]: no dash. Physical 120/190/305 twice (0s and 0.25s), then at 0.5s
  a physical radius-1 hit around himself 140/225/360 and a stun on his target 0.75/1.25/1.75s.
- **elastic_wardrum** [Rubber Man]: **Gear 1** at start. Cast 1: Gear 2 (AS +30%). Cast 2: Gear 3
  (AS +30%, splash 40%). Cast 3 onward: shield 400/640/1025 for 4s and a physical radius-1 slam
  200/320/510.

### Heroes
- **skybreaker** [Quirkless]: no dash. Physical 210/335/535 on current target, then a LINE of
  physical 105/170/270 through the 2 hexes behind it.
- **zero_field** [Urarocka]: enemies within 1 of current target are held 0.75/1/1.25s and take
  magic 150/240/385 when it ends. The all-allies AS +12/20/32% for 5s stays.
- **ascending_core** [Sonion]: the AD/AP/AS stacks (max 3) never expire. Forms **Core I**, **Core
  II**, **Core III**: each cast moves him up one (larger and brighter look). Core I and II keep the
  magic area radius 1 400/640/1025; Core III casts a LINE from him through current target to the
  board edge, magic 450/720/1150. Every form's cast also adds a stack.

## 4. Traits (TraitConfig) and bonds (BondConfig)

Steps count different characters on the board.

| Trait | Step | Effect (placeholders) |
| --- | --- | --- |
| Hunters | 2 / 4 | mark the enemy with the most health; Hunters +20% / +35% damage to it; at 4 Hunters heal 10% max health when it dies; the mark moves |
| Corps | 2 / 3 | a Corps takedown: Corps units (3: whole team) +25% / +35% AS for 3s / 4s |
| Spirit | 2 / 4 | Spirit units start with a 150 / 300 shield (8s); at 4 a broken trait shield gives +30% AS for 4s |
| Cursed | 2 / 4 / 6 | 1 / 1 / 2 passive dummies in front at fight start (450 / 800 / 800 health, 20 / 35 / 35 armor and MR); at 4+ whoever destroys one is cursed: -25% damage dealt for 4s |
| Arcane | 2 / 3 | +20 starting mana for Arcane / +30 for the whole team |
| Titans | 2 / 3 | +15% / +25% max health; at 3 regenerate 1.5% max health per second |
| Shinobi | 2 / 4 | once per fight below 30% health: vanish 1s, return with a 150 / 300 shield (4s); at 4 also +40% AS for 3s |
| Crew | 2 / 3 | each Crew takedown: every Crew unit +5% / +8% AD and +5 / +8 AP for the fight (stacking); after a PvP fight takedowns pay 1 gold each, capped at 1 / 2 per round |
| Heroes | 2 / 4 | meter of 4, +1 per Hero cast; below half the team takes 10% / 18% less damage, from half it deals 10% / 18% more; full: starts over (2) or both for the rest of the fight (4) |
| Blade | 2 / 4 / 6 | +10% / 20% / 32% AD |
| Assassin | 2 / 4 / 6 | +10 / 15 / 20 points crit chance, +0.15 / 0.25 / 0.35 crit damage; at 4 jump to the nearest free enemy back-row hex at fight start; at 6 attacks execute enemies below 12% health (never bosses) |
| Brawler | 2 / 4 / 6 | +15% / 25% / 40% max health |
| Caster | 2 / 4 / 6 | +12 / 25 / 40 AP (Tuning A; was 15 / 30 / 50) |
| Guardian | 2 / 4 / 6 | members +15 / 30 / 50 armor and MR; everyone else +5 / 10 / 15 |
| Marksman | 2 / 4 | +4% / +7% AS per basic attack, up to 10 stacks, for the fight |
| Support | 2 / 4 | team heals and shields +15% / +25% (HealPower); at 4 the team takes 15% less magic damage |

| Bond | Units | Effect |
| --- | --- | --- |
| crash_kick | threefold_crash + flare_kick | a takedown by one gives the other +20% damage dealt for 4s |
| cursed_pair | night_parade + infinite_collapse | both +12% damage dealt while both live; when one dies the survivor gains 40 mana and +30% damage dealt for 5s |
| riders | spurshot + orbit_breaker | each may remount once per fight (the existing remount rules: after a takedown, horse at 50%) |

The trait panel shows every trait on the board with breakpoint pips (partial traits dimmed) and
the active bonds by both characters' names.

## 5. Simulation

`sim/run.luau` uses the same traits and bonds as the server (Traits.combatParams) and pays Crew
gold after PvP fights. Bots value traits when buying (`Bot.traitGain`: shared traits, the next
breakpoint, completing a bond; best offers first, a little below their gold floor for a
breakpoint or a bond). The report adds bond use in the final five rounds, fight-time trait
effects per side, Crew gold in the gold summary, and (Mechanics) per-fight counts of the new
pieces; the Forms lines already cover every unit with forms.

## 6. Assumptions and simplifications

- redline_cut: "her lowest-health ally" is her lowest-health other ally that an enemy is attacking.
- cyclone_edge: any death of his current target counts, not only his own kills; the follow-up
  repeats the full area amount.
- spurshot casts at full stacks; mana from attacks and damage is ignored for it.
- clockbreaker's hits and threefold_crash's sequence are delayed effects; they are dropped if the
  caster dies first. All delayed hits use the target chosen at the cast.
- frozen_moment and zero_field: the hit lands at the stun's nominal end, even if the stun was
  extended by another stun or ended by a form change.
- shade_pack, night_parade: each caster counts all of its own living summons.
- night_parade: the firing cast (cast 3 of each cycle) only recalls and fires; it summons nothing.
- mirror_script: "most recently cast" is among living enemies; copying a formOnly ability does
  nothing.
- echo_legion: the projectile is not drawn separately; the area pulses show the landing.
- titanheart: "lower stats" are AD, armor and MR in Human form; health is unchanged.
- elastic_wardrum: gears are three forms; casts 1 and 2 only change gear.
- ascending_core: the stack buffs are in all three forms' abilities, so the third stack is reached
  on the third cast (in Core III).
- Shinobi: vanished units do not act.
- Cursed dummies are summoned by the first Cursed unit on the board; they never move.
- Crew gold is paid for practice and ghost PvP fights too (the player's own takedowns).

## 7. Tuning A (first balance pass)

Part 1 fixes: night_parade uses a cast counter (section 3); Corps, Arcane, Titans and Crew top
steps moved from 4 to 3; the Heroes meter fills in 4 casts (was 6).

Part 2: unit numbers, old -> new (1/2/3-star; 2- and 3-star values kept in proportion).

| Unit | Change |
| --- | --- |
| boiling_crown | aura 20/32/50 -> 7/11/18 per second; blast 220/350/560 -> 120/190/300 |
| skyboulder | cone 300/480/770 -> 145/235/375 |
| titanheart | max mana 110 -> 180; hit 250/400/640 -> 215/345/555 |
| burst_vector | area 210/335/535 -> 105/165/265 |
| orbit_breaker | hit 220/350/560 -> 110/180/285; bounce 100/160/250 -> 50/80/125 (both forms) |
| starless_burst | blast 600/960/1540 -> 370/595/955 |
| echo_legion | each of the 4 hits 110/175/280 -> 74/117/188 |
| infinite_collapse | area 450/720/1150 -> 350/560/895 |
| night_parade | curse HP 35/40/45% -> 60/70/80%, AD 40/50/60% -> 80/100/120%, AS 85% -> 100%; line 120/190/305 -> 540/855/1370 |
| night_command | shadows last 9/10/12s -> 15/17/20s, HP 30/35/40% -> 50/55/65%, AD 50/55/65% -> 75/85/100% |
| reelbreaker | hit 390/625/1000 -> 830/1330/2130 |
| clockbreaker | small hits 45/70/115 -> 85/130/215; final hit 200/320/510 -> 375/600/960 |
| final_argument | 900/1500/3000 -> 1465/2445/4890 true |
| flashline | hit 140/225/360 -> 350/565/900; AD 63 -> 81 |
| null_edge | hit 130/210/335 -> 325/525/840; AD 61 -> 64 |
| wolfstep | hit 135/215/345 -> 340/540/865; AD 62 -> 72 |
| ripcord_frenzy | chainsaw AS +35% -> +60%, splash 40% -> 70%; AD 58 -> 70 |
| cinder_arc | hit 105/170/270 -> 165/265/425; area 65/105/170 -> 100/165/265 |

Estimation: a unit's measured 1-star damage was split into basic attacks, estimated as
AD x attacks per second x 7.5 (calibrated on the 1-cost units, which have simple kits), and the
rest (ability, aura, summons, forms). The non-attack part was scaled by
(target - attacks) / (measured - attacks). Ability multipliers were capped at 2.5x; past that,
attack damage made up the rest. Details per unit in the Tuning A handoff.

Part 3: roster health dial 1.2992 -> 1.403136 (x1.08); Caster AP 15/30/50 -> 12/25/40; boss
combat health 24500/30000/32000/33000 -> 28700/33800/36400/37600 (rounds 8/12/16/20).
## 8. Tuning B

- night_parade: the cycle is 2 casts (AbilityConfig.nightParadeCycle 3 -> 2). Cast 1 summons two
  curses (was one per summoning cast); cast 2 recalls every living curse (even none) and fires the
  line; then it repeats. Max mana 110 -> 40 (about one cast every 5 seconds). Line base
  540/855/1370 -> 70/110/180 (+100% per curse recalled, unchanged).- Sim damage ranges (report only): redline_cut is measured against the carry range of its cost;
  skyboulder, titanheart and elastic_wardrum against a new "bruiser" range halfway between the
  support and carry ranges (1c 475-800, 2c 550-950, 3c 775-1250, 4c 1050-1650, 5c 1450-2300).- Trims (attack damage and ability scaled by the same factor, target / measured, so the measured
  split stays): burst_vector AD 67 -> 52, area 105/165/265 -> 80/130/205; orbit_breaker AD 68 ->
  54, hit 110/180/285 -> 85/140/225, bounce 50/80/125 -> 40/65/100; severing_temple AD 98 -> 74,
  area 450/720/1150 -> 340/545/875, damage over time 35/55/90 -> 27/42/68 per second.- Trait bot (sim only): with 8 players, seat 4 is a "trait" strategy (sim/Bot.luau header) in place
  of the "no copies" bot. It commits to the trait it holds most of, buys and fields toward its top
  step, then a second trait, and completes bonds. The report adds it to results by strategy and
  lists, per committed trait, how often its board reached each step and its average placement.