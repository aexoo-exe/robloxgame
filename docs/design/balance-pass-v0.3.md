BALANCE PASS v0.3 — PRE-TRAIT

[H] = implement for next simulation
[T] = tunable / confidence lower

1. FIGHT LENGTH

[H] GLOBAL CHANGE:
All units: base HP × 1.15.

Example: 800 HP -> 920 HP.
Do NOT change AD, AS, Armor, MR, mana, or ability damage globally.

Target: 22–25s next simulation.

Reason:
19.3s is too short for this game. With 1.5–2.5 casts/fight, another ~15% effective health should create room for second/third casts and frontline interaction without directly weakening carries.

Do NOT move the target to 19–20s yet. Long-term target remains 24–30s [T], but I would accept ~22–25s before traits because defensive traits may extend fights further.


2. BACKLINE ACCESS

[H] Seven FARTHEST_ENEMY users is too many.

KEEP:
Dax — FARTHEST_ENEMY
Vael — FARTHEST_ENEMY
Sevrin — FARTHEST_ENEMY
Nyra — FARTHEST_ENEMY

CHANGE:
Kes: FARTHEST_ENEMY -> HIGHEST_AD_ENEMY
Ione: FARTHEST_ENEMY -> CURRENT_TARGET
Solenne: FARTHEST_ENEMY -> CURRENT_TARGET

Reason:
Dax/Vael/Sevrin are intentional divers.
Nyra is the dedicated backline sniper.
Ione/Solenne should behave as conventional ranged carries instead of adding unavoidable backline pressure.
Kes remains an opportunistic assassin but no longer duplicates the same farthest-unit pattern.

Goal: reduce seven direct backline-targeters to four.


3. DASH FIXES

MAREK SOL
[H]
Target: CURRENT_TARGET -> HIGHEST_AD_ENEMY.
DASH: 2 -> 3 hexes.
Damage target becomes HIGHEST_AD_ENEMY.

Old:
DASH toward CURRENT_TARGET up to 2.
CURRENT_TARGET DAMAGE 210/335/535.

New:
DASH toward HIGHEST_AD_ENEMY up to 3.
HIGHEST_AD_ENEMY DAMAGE 210/335/535.

Reason: 3% movement proves the current dash is functionally decorative.

KES VANTA
[H]
Target: FARTHEST_ENEMY -> HIGHEST_AD_ENEMY.
DASH: 2 -> 3 hexes.
Damage target becomes HIGHEST_AD_ENEMY.

Damage stays 145/230/370.

Reason: a 3-hex approach should much more reliably put Kes in melee range of his selected target instead of causing immediate retargeting.


4. INDIVIDUAL CHANGES

Do NOT buff all current LOW units yet. HP +15% increases survival/casts and should disproportionately help units currently dying before completing their intended output.

Make only these obvious corrections now:

ORIN BASTION [H]
AD: 58 -> 64.
AS: .60 -> .65.
Reason: 480 damage with 2.5 casts means survival is already excellent; extra HP will not solve his extremely low basic-attack contribution.

CALYX MERE [H]
AD: 54 -> 60.
AS: .65 -> .70.
Reason: 445 with 1.8 casts is below even the tank/support floor; modest baseline damage increase.

ASTRA REN [T]
Falling Constellation:
400/650/1050 -> 450/725/1175 magic.
Reason: 1997 is materially below the intended 5-cost carry output despite surviving 71% of fights. HP helps, but Astra probably still needs ability compensation.

HOLD:
Kes, Lio, Marek, Dax, Vael, Veyra, Nyra.

Reason: these are precisely the units most likely to move substantially from HP/backline/targeting changes. Do not contaminate the experiment with simultaneous buffs.


5. DIAGNOSTIC DAMAGE RANGES

[H] Do NOT recalibrate simply because roster size increased.

Roster size should change composition diversity and shop availability, not the expected combat contribution of a deployed unit.

Keep current ranges for this next test:
1c frontline/support: 250–600
1c carry: 700–1000

2c tank/support: 350–750
2c bruiser/carry: 750–1150

3c tank/support: 450–900
3c carry: 1100–1600

4c tank/support: 500–1100
4c carry: 1600–2200

5c tank/utility: 700–1400
5c carry: 2200–3200

IMPORTANT:
Judge role + damage together. Dax/Vael-style divers can legitimately sit slightly below conventional carry ranges if they reliably disrupt valuable backliners.


6. 3-STAR ACCESS

[H] With rerolling bots, record PER COST:
- % of matches containing ≥1 3-star.
- % of winners containing ≥1 3-star.
- Average round first 3-star appears.
- Average number of 3-stars per match.
- Copies held when failed upgrades occur.
- Gold spent rerolling.
- Level when 3-star is completed.

HEALTHY STARTING TARGETS [T]:
1-cost: ≥1 3★ in 45–65% of matches.
2-cost: 30–50%.
3-cost: 15–30%.
4-cost: 3–10%.
5-cost: <2%.

Winner rate should be higher than match-wide occurrence, but a 3-star should not be practically mandatory to win.

Do NOT change 22/20/17/10/9 pool sizes until this bot test exists.


NEXT SIMULATION

Run 200 matches with:
+15% HP globally
Ione/Solenne targeting changes
Marek/Kes fixes
Orin/Calyx buffs
Astra ability buff

Report:
fight duration + distribution,
timeout rate,
all 25 damage/casts,
survival share,
dash movement rates,
targeting/backline survival,
match duration/final round,
and reroll/3-star metrics.

Do NOT implement traits yet.

Decision gate:
If average fight reaches ~22–25s and LOW outliers collapse from 10 to roughly ≤4, v0.3 worked. Fix remaining individual outliers, establish the clean roster baseline, THEN add traits.
