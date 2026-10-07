# Forms (transformations)

A **form** is a state a unit can switch into in the middle of a fight. A unit type can list its
forms in order in `UnitConfig.luau`. It starts every fight in the first one and moves on when that
form's trigger fires. Unit types without `forms` behave exactly as before.

The two riders (`spurshot`, `orbit_breaker`) are the first users. They start **Mounted** and drop
to **Dismounted** when their horse's health pool runs out.

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
	rules = { ... },                        -- optional overrides of FormConfig.rules
	trigger = {                             -- optional; what moves the unit on
		type = "FORM_HEALTH_DEPLETED",
		to = "Dismounted",                  -- optional; default is the next form in the list
		healthPercent = 100,                -- optional; the destination pool's starting fill
		maxUses = 1,                        -- optional; times per fight this trigger can fire
	},
}
```

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
| `TAKEDOWN` | the unit lands the killing blow on an enemy board unit (summons don't count) | Used only for rider remounts, which are off by default. |

To add a trigger (HP threshold, on cast, timer), add one entry to `TRIGGERS` in `Forms.luau`. The
entry gives the hook it listens to and its condition. If the trigger needs a new moment (for
example "Cast" or "Tick"), add it to `Forms.Hook` and add one `Battle.checkForm(battle, unit, hook)`
call where that moment happens (in `Abilities.cast` or `CombatSim.step`).

## Adding forms to a unit

1. Put the form's numbers in `FormConfig.luau`, or write them inline if they are not meant for tuning.
2. In `UnitConfig.luau`, after the unit's `add(...)` line, set `roster.<id>.forms = { ... }`
   (see `mountedForms`).
3. If players should see the form, give it a `RenderConfig.formLooks` entry. Without one, the form
   name pops up on change and the unit keeps its plain look.
4. Run the tests. `RosterTest` checks every form list with `Forms.validate`, and any ability
   override with `Abilities.validate`. Fights that include the changed unit will no longer match
   `tests/RegressionFingerprints.luau`. Check them with `lune run tests/RegressionFights.luau check`,
   then regenerate the fingerprints on purpose (see `tests/RegressionFights.luau`).

## Rider mounts (current numbers in `FormConfig.mount`)

- Horse pool: `spurshot` 220, `orbit_breaker` 260 (before scaling: 255 and 302 at 1 star).
- Mounted: +0.2 move speed (the riders' former extra speed; their base is now 1.0), +0 attack damage.
- Remount: off. When on, a Dismounted rider remounts after a takedown, at most `remountsPerFight`
  (1) times per fight, with the horse pool at `remountHorseHealthPercent` (50%).
- Placeholder look: a brown block body and head under the rider, and an orange pool bar stacked
  above the health bar.
