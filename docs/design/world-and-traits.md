BLOCK 1 — WORLD / TRAITS / SYSTEM CONTRACT

LEGEND
[H] = hard rule / implementation contract.
[T] = tunable starting balance value.

WORLD
The continent of Veyrahn was fractured when a celestial engine called the Crownstar shattered, scattering energy across six rival powers.
Ironveil builds disciplined fortress-cities; Emberwake embraces volatile flame; Tideglass channels restorative lunar seas; Stormcrest rules the floating highlands; Starfall studies celestial fragments; Eclipse hunts forbidden power in the spaces between them.
Their champions meet in the Crown Trials, where alliances between factions create temporary armies strong enough to reshape the world.
Transformations eventually represent a champion awakening deeper Crownstar power, but transformation mechanics remain deferred.

BASE STAT BANDS [H — unchanged]
Cost | HP       | AD    | AS        | Armor/MR
1    | 500-750  | 40-65 | .55-.80  | 15-40
2    | 600-900  | 45-70 | .55-.85  | 20-45
3    | 700-1050 | 50-80 | .60-.90  | 20-50
4    | 800-1200 | 55-90 | .65-.95  | 25-60
5    | 900-1400 | 60-100| .65-1.00 | 30-70

AP baseline = 100 [H].
Magic DAMAGE/AREA_DAMAGE, HEAL and SHIELD scale by AP/100 [H].
Existing diagnostic 1★ damage/fight targets remain the balancing target [H]:
1c frontline/support 250-600; carry 700-1000.
2c tank/support 350-750; bruiser/carry 750-1150.
3c tank/support 450-900; carry 1100-1600.
4c tank/support 500-1100; carry 1600-2200.
5c tank/utility 700-1400; carry 2200-3200.


====================
ORIGINS
====================

IRONVEIL — Kaien Vale, Tarek Flint, Dax Ironwind, Orin Bastion
Theme: disciplined armor / fortress fighters.
Breakpoints [H]: 2 / 4
2: Ironveil units gain +12 Armor and +12 MR. [T]
4: Ironveil units gain +28 Armor and +28 MR. [T]

EMBERWAKE — Bren Ashward, Rook Ember, Marek Sol, Kairo Zenith
Theme: aggression / escalating physical pressure.
Breakpoints [H]: 2 / 4
2: Emberwake units gain +12% AD. [T]
4: Emberwake units gain +25% AD and +15% AttackSpeed. [T]

TIDEGLASS — Cera Morn, Sena Lume, Calyx Mere, Maelin Shore
Theme: shields / healing / endurance.
Breakpoints [H]: 2 / 4
2: Tideglass units gain +15 AP; all allies gain +8 MR. [T]
4: Tideglass units gain +35 AP; all allies gain +18 MR. [T]

STORMCREST — Lio Veylan, Ione Gale, Veyra Storm, Torra Gale
Theme: speed / mobility.
Breakpoints [H]: 2 / 4
2: Stormcrest units gain +15% AttackSpeed. [T]
4: Stormcrest units gain +35% AttackSpeed and +15% MoveSpeed. [T]

STARFALL — Sola Aven, Mira Quill, Solenne Ray, Astra Ren
Theme: celestial magic / precision.
Breakpoints [H]: 2 / 4
2: Starfall units gain +20 AP. [T]
4: Starfall units gain +45 AP. [T]

ECLIPSE — Kes Vanta, Vela Nox, Vael Noct, Nyra Voss, Sevrin Null
Theme: assassins / forbidden power.
Breakpoints [H]: 2 / 3 / 5
2: Eclipse units gain +10% AD and +10 AP. [T]
3: +20% AD and +20 AP. [T]
5: +35% AD and +40 AP. [T]


====================
CLASSES
====================

VANGUARD
Members: Kaien, Bren, Rook, Tarek, Orin, Kairo, Torra
Breakpoints [H]: 2 / 4 / 6
2: Vanguards gain +10 Armor/MR. [T]
4: +22 Armor/MR. [T]
6: +38 Armor/MR. [T]

WARDEN
Members: Kaien, Sena, Tarek, Calyx, Orin
Breakpoints [H]: 2 / 4
Combat start: SHIELD each Warden for:
2: 120 for 6s. [T]
4: 280 for 6s. [T]

DUELIST
Members: Lio, Rook, Marek, Dax, Vael, Torra, Kairo
Breakpoints [H]: 2 / 4 / 6
2: Duelists gain +12% AttackSpeed. [T]
4: +28%. [T]
6: +50%. [T]

MARKSMAN
Members: Mira, Ione, Solenne, Nyra
Breakpoints [H]: 2 / 4
2: Marksmen gain +12% AD. [T]
4: +30% AD. [T]

ARCANIST
Members: Sola, Vela, Veyra, Solenne, Maelin, Astra, Sevrin
Breakpoints [H]: 2 / 4 / 6
2: Arcanists gain +15 AP. [T]
4: +35 AP. [T]
6: +60 AP. [T]

MYSTIC
Members: Cera, Sena, Calyx, Maelin, Astra
Breakpoints [H]: 2 / 4
2: All allies gain +10 MR; Mystics gain +10 AP. [T]
4: All allies gain +25 MR; Mystics gain +25 AP. [T]

REAVER
Members: Kes, Dax, Vela, Vael, Nyra, Sevrin
Breakpoints [H]: 2 / 4 / 6
2: Reavers gain +10% AD and +10% AttackSpeed. [T]
4: +20% AD and +25% AttackSpeed. [T]
6: +35% AD and +45% AttackSpeed. [T]


====================
TRAIT RULES
====================

Every character has exactly 1 Origin. [H]
Every character has 1 or 2 Classes. [H]
A unit counts once toward every trait listed on that unit. [H]
Trait bonuses use existing combat stats/effects only. [H]
Trait bonuses from different traits stack. [H]
Same-trait breakpoint effects replace lower breakpoint values; they do NOT stack. [H]
Trait membership and breakpoint counts above are hard roster structure. [H]
All numeric bonuses are [T] and should be simulation-tested after implementation.


====================
NEW BUILDING BLOCKS
====================

NONE REQUIRED.

Roster v0.1 intentionally uses only:
DAMAGE, AREA_DAMAGE, HEAL, SHIELD, STUN, BUFF, DASH.

And only:
SELF, CURRENT_TARGET, LOWEST_HP_ALLY, NEAREST_ENEMY,
FARTHEST_ENEMY, HIGHEST_AD_ENEMY.

This is intentional [H]: do not expand the generic combat API merely to make the first expanded roster more exotic.


====================
SHARED POOL
====================

ROSTER DISTRIBUTION [H]
1-cost: 7 characters
2-cost: 6
3-cost: 5
4-cost: 4
5-cost: 3
TOTAL: 25

Reason:
More low-cost units are required for early-board variety and reliable upgrades.
The roster narrows upward so premium units remain distinct and readable.
Three 5-costs is enough for legendary chase units without making level 9/10 shops repetitive.

POOL SIZE PER CHARACTER [T]
1-cost: 22 copies
2-cost: 20 copies
3-cost: 17 copies
4-cost: 10 copies
5-cost: 9 copies

Decision: KEEP the original 22/20/17/10/9 initially.

YES — build the shared pool together with the expanded roster.
Reason [H]: once 25 units exist, unconstrained independent shops will distort upgrade frequency and make future shop-odds balancing misleading. Claude should implement roster data + shared pool before traits.


====================
EXISTING-UNIT CHANGES
====================

Combat stats: NONE.
Abilities: NONE beyond already-implemented balance pass v0.2.
Only Origin/Class metadata is added.

Mira remains v0.2 Starbolt: 120/190/310 physical + 20/30/45% AS.
Dax remains v0.2 Flashbreak: FARTHEST_ENEMY, DASH 3, 300/475/750 physical.
Nyra remains v0.2 Voidline Shot: 320/500/800 physical.
All other existing abilities remain unchanged.


====================
DEFERRED
====================

Transformation mechanics.
Items / item recipes.
Trait emblems or +1 trait items.
Chosen/headliner-style systems.
Unique 5-cost rule-breaking mechanics.
New effect types/selectors.
Ability crits.
Crowd-control immunity/tenacity.
Healing reduction.
Armor/MR penetration.
Execute mechanics.
Revives.
Summons.
Mana manipulation.
Trait-specific VFX beyond presentation.
Final shop odds / pool tuning.
Final trait numbers.
Final roster balance — rerun simulations after roster, then again after traits.
