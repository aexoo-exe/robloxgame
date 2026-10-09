BLOCK 2 — 42-CHARACTER ROSTER v1.1 (roster block updated for Overhaul 1)

HP below = PRE-1.16 global multiplier [H].
AP baseline 100; crit baseline 25%/140% [H].
Ability values [T].

Overhaul 1 changed factions (ORIGIN), classes and three stat lines; this block shows the
current values (MANA here is v1.1: spurshot now 0/80 and casts at full spin stacks, flare_kick
15/50, starless_burst 20/160). The abilities below are the v1.1 originals: the 30 reworked
abilities are in docs/design/overhaul-1.md, which replaces them where they differ.

NAME            C ORIGIN   CLASS(ES)          HP   AD ARM MR AS   RNG MOV MANA
Lightitsu       1 Hunters  Blade/Assassin     560 63 20 20 .78   1 1.1 20/90
Tontaro         1 Hunters  Blade              650 57 28 25 .70   1 1.0 30/90
Thorvinn        1 Corps    Blade              590 62 22 20 .77   1 1.1 20/80
Jonny           1 Spirit   Marksman/Brawler   650 56 18 18 .76   2 1.2 20/80
Dengi           1 Cursed   Brawler            700 58 28 24 .72   1 1.0 30/90
Pasta           1 Arcane   Blade              680 61 30 35 .68   1 1.0 30/90
Meow-Meow       1 Arcane   Support            580 43 20 30 .62   3 1.0 40/100
Armored Giant   1 Titans   Guardian           750 48 40 35 .56   1 .9  40/100
Saku            1 Shinobi  Support            600 46 22 28 .65   2 1.0 40/100

Mika            2 Corps    Blade/Guardian     690 68 27 25 .83   1 1.1 20/80
Love-cook       2 Crew     Brawler/Assassin   760 69 30 27 .78   1 1.1 30/90
Kachan          2 Heroes   Caster/Marksman    650 67 22 24 .78   4 1.0 20/80
Quirkless       2 Heroes   Brawler            820 66 35 30 .70   1 1.0 30/90
Kenny           2 Cursed   Assassin           720 70 26 27 .82   1 1.1 20/80
Jyro            2 Spirit   Marksman           660 68 23 25 .82   3 1.2 20/90
Toad Samurai    2 Shinobi  Guardian           900 52 45 42 .58   1 .9  40/110
Potential Man   2 Cursed   Caster             650 50 23 30 .67   3 1.0 30/100
Boku wa Docta   2 Crew     Support/Brawler    640 46 24 32 .68   3 1.0 40/110

Saucekay        3 Shinobi  Blade/Assassin     790 79 28 30 .88   1 1.1 20/90
Zolduck         3 Hunters  Assassin           770 78 26 27 .90   1 1.2 20/90
Moss Head       3 Crew     Blade              900 80 38 32 .78   1 1.0 30/100
Aaron           3 Titans   Guardian/Brawler  1050 65 50 45 .62   1 .9  40/110
Ray             3 Corps    Caster             740 57 24 32 .70   4 1.0 20/90
Kashi           3 Shinobi  Assassin/Caster    780 72 30 34 .82   2 1.1 30/100
Goataro         3 Spirit   Brawler            930 79 40 36 .72   1 1.0 30/100
Beast Giant     3 Titans   Guardian          1050 64 50 35 .72   2 .9  30/100
Itchigo         3 Hunters  Blade/Marksman     820 80 32 30 .84   3 1.0 20/90
Urarocka        3 Heroes   Support            760 52 27 35 .68   3 1.0 40/110

Freaks          4 Hunters  Brawler           1050 88 45 40 .72   2 1.0 40/130
Rubber Man      4 Crew     Brawler/Guardian  1200 84 55 50 .80   1 1.0 40/110
Archmage        4 Arcane   Caster/Marksman    830 67 28 48 .80   4 1.0 20/100
Fish Cake       4 Shinobi  Caster            1050 82 42 42 .82   2 1.1 30/110
Leveler         4 Arcane   Assassin            900 89 32 34 .94   1 1.1 30/100
Za Warudo       4 Spirit   Assassin/Marksman   950 88 38 38 .86   1 1.0 40/110
Revi            4 Corps    Blade/Assassin      860 90 30 30 .95   1 1.2 20/90
Keto            4 Cursed   Caster              900 68 32 42 .75   3 1.0 30/110
Joeskay         4 Spirit   Support/Guardian   1200 78 58 45 .72   1 1.0 40/120

Thukuna         5 Cursed   Caster/Blade       1100 98 45 48 .88   2 1.1 30/110
Sonion          5 Heroes   Brawler/Caster     1250 94 55 50 .88   2 1.1 30/100
Punchman        5 Heroes   Brawler            1350 100 65 60 .75  1 1.0 0/150
The Strongest   5 Cursed   Caster             1050 78 42 65 .82   4 1.0 40/120
Colossal Giant  5 Titans   Guardian/Caster    1400 72 70 65 .65   1 .8  50/130


====================
1-COST ABILITIES
====================

LIGHTITSU — FLASHLINE [T]
DASH FARTHEST_ENEMY up to 4; new CURRENT_TARGET.
DAMAGE physical: 140/225/360.
Transformation: white-gold lightning speed form.

TONTARO — CINDER ARC [T]
CURRENT_TARGET DAMAGE physical: 105/170/270.
AREA_DAMAGE target radius 1 magic: 65/105/170.
SELF BUFF AS +18/28/42% for 5s.
Transformation: ember patterns spread across blade and coat.

THORVINN — WOLFSTEP [T]
DASH HIGHEST_AD_ENEMY up to 3; new CURRENT_TARGET.
DAMAGE physical: 135/215/345.
Transformation: spectral dagger trails follow his movement.

JONNY — SPURSHOT [T]
FARTHEST_ENEMY DAMAGE physical: 140/225/360.
SELF BUFF AS +15/25/40% for 4s.
Transformation: rider and mount gain spiraling metallic energy.

DENGI — RIPCORD FRENZY [T]
SELF BUFF AS +25/40/60% for 5s.
SELF HEAL 80/130/210.
Transformation: mechanical blades emerge across his combat form.

PASTA — NULL EDGE [T]
CURRENT_TARGET DAMAGE physical: 130/210/335.
SELF BUFF MR +25/40/65 for 5s.
Transformation: dark null-energy armor covers one side.

MEOW-MEOW — BITTER VAPOR [T]
CURRENT_TARGET-centered DAMAGE_OVER_TIME radius 1 magic:
22/35/56 per second for 4s.
LOWEST_HP_ALLY HEAL: 70/110/175.
Transformation: colored medicinal vapor forms an orbiting halo.

ARMORED GIANT — IRON RUSH [T]
SELF BUFF Armor +30/45/70 for 5s.
DASH HIGHEST_AD_ENEMY up to 2; new CURRENT_TARGET.
HIGHEST_AD_ENEMY DAMAGE physical: 85/135/215.
HIGHEST_AD_ENEMY STUN: .75/1/1.5s.
Transformation: armor locks into a heavier siege frame.

SAKU — BLOOMING AID [T]
LOWEST_HP_ALLY HEAL: 120/190/305.
Transformation: luminous healing crest spreads across her arms.


====================
2-COST ABILITIES
====================

MIKA — REDLINE CUT [T]
DASH HIGHEST_AD_ENEMY up to 3; new CURRENT_TARGET.
DAMAGE physical: 215/345/550.
SELF BUFF AS +20/32/50% for 4s.
Transformation: crimson aerial-energy trails.

LOVE-COOK — FLARE KICK [T]
CURRENT_TARGET DAMAGE physical: 150/240/385.
AREA_DAMAGE target radius 1 magic: 75/120/190.
Transformation: one leg ignites in spiraling flame.

KACHAN — BURST VECTOR [T]
CURRENT_TARGET-centered AREA_DAMAGE radius 1 magic: 210/335/535.
SELF BUFF AD +10/15/25% for 4s.
Transformation: angular explosive wings flare behind him.

QUIRKLESS — SKYBREAKER [T]
DASH HIGHEST_AD_ENEMY up to 3.
AREA_DAMAGE target radius 1 physical: 210/335/535.
Transformation: bright energy veins cover his body.

KENNY — CRIMSON HUNGER [T]
CURRENT_TARGET DAMAGE physical: 220/350/560.
SELF HEAL: 90/145/230.
Transformation: crimson appendages unfold behind him.

JYRO — ORBIT BREAKER [T]
CURRENT_TARGET DAMAGE physical: 220/350/560.
STUN: 1/1.5/2s.
Transformation: rotating spheres form a geometric field.

TOAD SAMURAI — MARSH FORTRESS [T]
SELF SHIELD: 280/450/720 for 6s.
SELF-centered AREA_DAMAGE radius 1 physical: 85/135/215.
Transformation: armor expands into a guardian shell.

POTENTIAL MAN — SHADE PACK [T]
SUMMON 2/2/3 beasts for 8/9/10s.
Stats: 30/35/40% HP; 45/50/55% AD;
50% Armor/MR; 90% AS; R1; MOV1.1.
Transformation: living shadows gather around him.

BOKU WA DOCTA — FIELD MEDIC [T]
ALL_ALLIES HEAL: 45/70/110.
LOWEST_HP_ALLY SHIELD: 150/240/385 for 5s.
Transformation: compact medic form expands into guardian physique.


====================
3-COST ABILITIES
====================

SAUCEKAY — VOLT SPEAR [T]
DASH FARTHEST_ENEMY up to 4; new CURRENT_TARGET.
DAMAGE magic: 300/480/770.
STUN .75/1.25/1.75s.
Transformation: violet lightning armor surrounds him.

ZOLDUCK — THUNDER NEST [T]
DASH HIGHEST_AD_ENEMY up to 3.
SELF AREA_DAMAGE radius 1 magic: 250/400/640.
AREA_STUN SELF radius 1: 1/1.5/2s.
Transformation: pale electricity engulfs his silhouette.

MOSS HEAD — THREEFOLD CRASH [T]
DASH HIGHEST_AD_ENEMY up to 3.
AREA_DAMAGE target radius 1 physical: 280/450/720.
Primary target STUN .75/1.25/1.75s.
Transformation: spectral blade arcs rotate around him.

AARON — TITANHEART [T]
SELF SHIELD 360/575/920 for 6s.
SELF BUFF Armor +30/45/70 and AD +15/25/40% for 6s.
Transformation: hardened giant combat form.

RAY — SNAPFIRE [T]
HIGHEST_AD_ENEMY-centered AREA_DAMAGE radius 1 magic:
300/480/770.
Transformation: flame sigils ignite around both hands.

KASHI — MIRROR SCRIPT [T]
COPY HIGHEST_AD_ENEMY.
Magnitude:
copied 1–3c = 80%;
4c = 60%;
5c = 45%.
Transformation: copied energy patterns surround his awakened eye.

GOATARO — CLOCKBREAKER [T]
AREA_STUN SELF radius 1: 1/1.5/2s.
CURRENT_TARGET DAMAGE physical: 300/480/770.
Transformation: towering spectral fighter manifests behind him.

BEAST GIANT — SKYBOULDER [T]
FARTHEST_ENEMY-centered AREA_DAMAGE radius 1 physical:
300/480/770.
Transformation: orbiting stone fragments gather around his arm.

ITCHIGO — HORIZON CUT [T]
FARTHEST_ENEMY DAMAGE magic: 330/525/840.
Transformation: dark-red energy wraps his blade.

URAROCKA — ZERO FIELD [T]
AREA_STUN SELF radius 2: .75/1.25/1.75s.
ALL_ALLIES BUFF AS +12/20/32% for 5s.
Transformation: gravity rings orbit her equipment.


====================
4-COST ABILITIES
====================

FREAKS — REELBREAKER [T]
PULL FARTHEST_ENEMY; pulled enemy becomes CURRENT_TARGET.
CURRENT_TARGET DAMAGE physical: 390/625/1000.
Transformation: concentrated aura gathers around an oversized striking fist.

RUBBER MAN — ELASTIC WARDRUM [T]
SELF SHIELD 400/640/1025 for 6s.
SELF BUFF AD +20/32/50%, AS +20/32/50% for 6s.
Transformation: exaggerated bright rhythm-powered form.

ARCHMAGE — STARLESS BURST [T]
HIGHEST_AD_ENEMY-centered AREA_DAMAGE radius 1 magic:
350/560/895.
SELF SHIELD 250/400/640 for 5s.
Transformation: immense layered spell lattice unfolds.

FISH CAKE — ECHO LEGION [T]
SUMMON 2/2/3 clones for 8/9/10s:
25/30/35% HP; 35/40/45% AD;
40% Armor/MR; 100% AS; R1; MOV1.1.
Then CURRENT_TARGET AREA_DAMAGE radius 1 magic: 270/430/690.
Transformation: radiant cloak surrounds him and his echoes.

LEVELER — NIGHT COMMAND [T]
SUMMON 2/3/3 soldiers for 9/10/12s:
30/35/40% HP; 50/55/65% AD;
55% Armor/MR; 95% AS; R1; MOV1.1.
Transformation: sovereign shadow armor manifests.

ZA WARUDO — FROZEN MOMENT [T]
AREA_STUN SELF radius 1: 1/1.5/2s.
CURRENT_TARGET DAMAGE physical: 320/510/815.
SELF HEAL 180/290/465.
Transformation: golden shadow-energy freezes nearby space.

REVI — CYCLONE EDGE [T]
DASH HIGHEST_AD_ENEMY up to 4; new CURRENT_TARGET.
AREA_DAMAGE target radius 1 physical: 330/525/840.
SELF BUFF AS +35/55/80% for 4s.
Transformation: silver blade trails form a continuous ring.

KETO — NIGHT PARADE [T]
CURRENT_TARGET-centered AREA_DAMAGE radius 1 magic:
220/350/560.
SUMMON 2/2/3 curses for 9/10/12s:
35/40/45% HP; 40/50/60% AD;
45% Armor/MR; 85% AS; R1; MOV1.0.
Transformation: a procession of dark spirits gathers behind him.

JOESKAY — RESTORATION STRIKE [T]
LOWEST_HP_OTHER_ALLY HEAL: 450/720/1150.
CURRENT_TARGET DAMAGE physical: 200/320/510.
Transformation: crystalline restoration energy coats his fists.


====================
5-COST ABILITIES
====================

THUKUNA — SEVERING TEMPLE [T]
CURRENT_TARGET-centered AREA_DAMAGE radius 2 physical:
450/720/1150.
Enemies initially hit receive DAMAGE_OVER_TIME magic:
35/55/90 per second for 4s.
Transformation: dark markings expand as slicing energy surrounds him.

SONION — ASCENDING CORE [T]
Each cast adds one stack for 8s:
+10/15/22% AD
+12/18/27 AP
+10/15/22% AS
Maximum 3 stacks [H].
Recast refreshes duration.
CURRENT_TARGET-centered AREA_DAMAGE radius 1 magic:
400/640/1025.
Transformation: each cast intensifies his rising luminous aura.

PUNCHMAN — FINAL ARGUMENT [T]
Mana 0/150 [H].
CURRENT_TARGET TRUE DAMAGE: 900/1500/3000.
No stun, dash, shield or secondary effect.
Transformation: restrained pressure builds before a single overwhelming strike.

THE STRONGEST — INFINITE COLLAPSE [T]
HIGHEST_AD_ENEMY-centered AREA_STUN radius 2:
1.5/2/2s.
SELF SHIELD: 350/560/895 for 5s.
Same center AREA_DAMAGE magic: 450/720/1150.
Transformation: luminous spatial rings distort the battlefield.

COLOSSAL GIANT — BOILING CROWN [T]
SELF-centered AREA_DAMAGE radius 1 magic: 170/270/430.
Enemies initially hit receive DAMAGE_OVER_TIME magic:
30/48/76 per second for 4s.
SELF BUFF Armor/MR +30/45/70 for 6s.
Transformation: colossal frame erupts in incandescent steam.


==================================================
SIMULATION ORDER / ACCEPTANCE GATES
==================================================

[H] FIRST: all 42 units, traits OFF, duos OFF.
[H] SECOND: core traits ON.
[H] THIRD: duos ON.

Roster-only targets [T]:
Average fight: 22–25s.
Timeouts: 1–3%.
No more than ~15% deviation from diagnostic damage band before individual adjustment.

Measure:
damage/casts/survival;
damage by basic attacks vs ability vs DOT vs summons;
backline survival;
dash movement success;
PULL cast rate + pulled-target survival;
summon damage/entity uptime;
COPY output grouped by copied cost;
stun uptime;
healing/shielding;
Punchman cast rate/overkill;
Sonion stacks reached per fight;
trait/duo usage after activation;
2★/3★ acquisition by cost and reroll strategy.

[H] If roster-only fights average >25s OR timeouts >3%, return global HP
1.16 -> 1.12 before nerfing damage broadly.

[H] If roster-only fights average <22s, investigate burst distribution first;
do NOT automatically raise HP again.

NEXT MILESTONE after stable roster + trait baseline:
TRANSFORMATIONS.
