# Forms (transformations)

A **form** is a state a unit can switch into in the middle of a fight. A unit type can list its
forms in order in `UnitConfig.luau`. It starts every fight in the first one and moves on when that
form's trigger fires. Unit types without `forms` behave exactly as before.

The two riders (`spurshot`, `orbit_breaker`) were the first users. They start **Mounted** and drop
to **Dismounted** when their horse's health pool runs out. Overhaul 1 added more
(`docs/design/overhaul-1.md`):

| Unit | Forms | How it moves on |
| --- | --- | --- |
| `spurshot`, `orbit_breaker` | Mounted, Dismounted | horse pool empty; remount after a takedown only with the riders' bond (flag) |
| `ripcord_frenzy` | Unarmed, Chainsaw | first cast (ON_CAST) |
| `shade_pack` | Lurking, Pack Out | first cast |
| `field_medic` | Medic, Bruiser | below 50% health, once |
| `titanheart` | Human, Titan | below 50% health, once; back to Human when the Titan pool is empty |
| `elastic_wardrum` | Gear 1, Gear 2, Gear 3 | each cast |
| `ascending_core` | Core I, Core II, Core III | each cast |

## Where things live

| File | What it holds |
| --- | --- |
| `src/shared/UnitConfig.luau` | Each unit's `forms` list. The riders' list is built by `mountedForms(id)`. |
| `src/shared/FormConfig.luau` | Every tunable number: the global pool rules and the rider mount values. |
| `src/shared/Forms.luau` | Form data rules: the trigger registry, stat changes, rule lookup, validation. |
| `src/shared/Battle.luau` | The engine side: `Battle.enterForm`, `Battle.checkForm`, and the pool in `Battle.damage`. |
| `src/client/CombatPlayback.luau`, `UnitView.luau` | Shows Form events: the pool bar, the form's look and a pop-up label. |
| `src/shared/RenderConfig.luau` | `formHealthColor`, `formLooks` (per form name: label, placeholder horse color). |

Form changes are decided only by the combat simulation on the server. Clients receive them as
`Form` events in the fight's event list, plus `formHealth` on hit and heal events and the starting
form in each unit summary. The headless sim (`sim/run.luau`) runs the same engine, so forms count in
the balance numbers. `sim/Mechanics.luau` also prints a "Forms" line per unit with forms.

## A form's fields

```lua
{
	name = "Mounted",                       -- unique within the unit
	stats = { MoveSpeed = { flat = 0.2 } }, -- optional; AD, AP, AttackSpeed, Armor, MR, MoveSpeed
	ability = { name = ..., effects = ... },-- optional; replaces the unit's ability in this form
	health = 220,                           -- optional own health pool (scaled like unit health)
	range = 1,                              -- optional; attack range while in this form
	splash = { percent = 40 },              -- optional; basic attacks also hit enemies next to the target
	rules = { ... },                        -- optional overrides of FormConfig.rules
	trigger = {                             -- optional; what moves the unit on
		type = "FORM_HEALTH_DEPLETED",
		to = "Dismounted",                  -- optional; default is the next form in the list
		healthPercent = 100,                -- optional; the destination pool's starting fill
		maxUses = 1,                        -- optional; times per fight this trigger can fire (1: once per fight)
		belowPercent = 50,                  -- HEALTH_BELOW only: the health threshold
		unlockedBy = "remount",             -- optional; fires only for units with this per-fight flag
	},
}
```

An ability with `formOnly = true` and no effects only fires the form's ON_CAST trigger (a cast
that just transforms).

Stat changes are added to the unit's buffs while it is in the form: (base + flat) x (1 + percent / 100).
A form's `health` pool is multiplied by the star level and the global health multiplier, the same
way unit health is (`StarLevel.scaleHealth`).

## How a health pool works

While the current form has pool health left, every hit goes to the pool and the unit's own health
is untouched. When a hit empties the pool, the rest of that hit is thrown away and the form's
trigger moves the unit on. These rules can be changed in `FormConfig.rules`, or per form via `rules`:

| Rule | Default | Meaning |
| --- | --- | --- |
| `shieldsAbsorbBeforeFormHealth` | true | Shields soak a hit before the pool. |
| `healingRestoresFormHealth` | false | Heals only restore the unit's own health. |
| `damageOverTimeHitsFormHealth` | true | DoT ticks hit the pool. |
| `statusEffectsCarryThrough` | true | Stuns and DoTs survive a form change. When false, they end; buffs and shields always stay. |
| `formHealthDamageGivesMana` | true | Pool damage gives mana as if the unit's own health had lost it. |

## Triggers

| Trigger | Fires when | Notes |
| --- | --- | --- |
| `FORM_HEALTH_DEPLETED` | a hit empties the current form's pool | The form needs `health`. |
| `TAKEDOWN` | the unit lands the killing blow on an enemy board unit (summons don't count) | Used for rider remounts: off by default, unlocked per fight by the riders' bond. |
| `ON_CAST` | the unit finishes a cast | The next cast uses the next form's ability. |
| `HEALTH_BELOW` | the unit's own health falls below `belowPercent` of its max | Checked after every hit it survives; use `maxUses = 1` for once per fight. |

To add a trigger (a timer, say), add one entry to `TRIGGERS` in `Forms.luau`. The
entry gives the hook it listens to and its condition. If the trigger needs a new moment (for
example "Cast" or "Tick"), add it to `Forms.Hook` and add one `Battle.checkForm(battle, unit, hook)`
call where that moment happens (in `Abilities.cast` or `CombatSim.step`).

## Adding forms to a unit

1. Put the form's numbers in `FormConfig.luau`, or write them inline if they are not meant for tuning.
2. In `UnitConfig.luau`, after the unit's `add(...)` line, set `roster.<id>.forms = { ... }`
   (see `mountedForms`).
3. If players should see the form, give it a `RenderConfig.formLooks` entry (`label`, and
   optionally `mount`, `scale` for size, `tint` for body color). Without one, the form name pops
   up on change and the unit keeps its plain look. Form names must be unique across characters
   (the riders share theirs); RosterTest checks it.
4. Run the tests. `RosterTest` checks every form list with `Forms.validate`, and any ability
   override with `Abilities.validate`. Fights that include the changed unit will no longer match
   `tests/RegressionFingerprints.luau`. Check them with `lune run tests/RegressionFights.luau check`,
   then regenerate the fingerprints on purpose (see `tests/RegressionFights.luau`).

## Rider mounts (current numbers in `FormConfig.mount`)

- Horse pool: `spurshot` 300, `orbit_breaker` 260, scaled like unit health by the roster health dial (`CombatConfig.globalHealthMultiplier`, 1.403136): 421 and 365 at 1 star.
- Mounted: +0.2 move speed (the riders' former extra speed; their base is now 1.0), +0 attack damage.
- Remount: off for everyone (`remountEnabled`), except riders whose bond is active (both riders on
  the board set the `remountFlag`). A remount happens after a takedown, at most `remountsPerFight`
  (1) times per fight, with the horse pool at `remountHorseHealthPercent` (50%).
- Each rider form has its own ability (spurshot heals the horse while Mounted and himself on foot;
  orbit_breaker bounces twice while Mounted, once on foot).
- Placeholder look: a brown block body and head under the rider, and an orange pool bar stacked
  above the health bar.
