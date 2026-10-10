# Items

Items 1: simple finished items, no components or recipes. **Every number is a starting value.**
The server decides everything: offers, picks, equips. Clients only ask.

## Where things live

| What | File |
| --- | --- |
| Rules, offers, every item number, recommendation tags | `src/shared/ItemConfig.luau` |
| Display names, effect text templates, placeholder icons | `src/shared/ItemSkinConfig.luau` |
| Item lists, offers, effect text, tags, validation | `src/shared/Items.luau` |
| Item effects in a fight | `src/shared/ItemCombat.luau` (run by `CombatSim.run`) |
| Inventory, equip, move, return, offers, picks | `src/shared/PlayerState.luau`, `Board.luau` |
| Server | `PlayerService` (requests, offers), `RoundService` (offers at Results) |
| UI | `InventoryStrip`, `ItemPickPanel`, `UnitInfoPanel`, `ItemIcon`, `ItemSelection`, item pips in `UnitView` |
| Sim | `sim/Bot.luau` (pick and equip), `sim/run.luau` (item report) |

## Rules

- Every unit has **3 item slots** and can never hold two of the same item.
- Every player has an **inventory** (cap 10). Picking needs a free place; items returned by a sale
  or a merge come back even past the cap.
- During **Preparation** a player can equip an inventory item on a unit on the board or bench,
  move it to another unit, or return it to the inventory (refused when full). From the start of
  Combat until the next Preparation nothing about items can change.
- **Selling** a unit returns its items to the inventory. When copies **merge**, the consumed copies'
  items move to the merged unit; any it cannot hold (slots full, or a second copy) return to the
  inventory.
- Items work in **every form** of a unit. **Summons** carry none. **Ghost** boards are copies of a
  player's board, so they fight with that player's items; practice boards have none.

## Item choices

- After the round-3 creep fight and after each boss fight (rounds 8, 12, 16, 20), every player is
  offered a choice: pick 1 of 3 (round 20: 1 of 4). The offer does not depend on winning.
- Offers are rolled per player from their own seeded generator: one offensive, one ability, one
  defensive (round 20 adds any other), never the same item twice in one offer.
- The pick screen shows each item's icon, name and effect text. It stays open through the next
  Preparation ("Later" folds it into a button); if nothing was picked when Preparation ends, the
  first option is taken (lost if the inventory is full).
- Round 3 no longer pays creep gold (the item replaces it). Boss gold is unchanged.

## The items

| Item | Category | Stats | Effect |
| --- | --- | --- | --- |
| Sunforged Blade | Offensive | +20% AD, +20% crit chance | abilities can crit (own crit chance and crit damage) |
| Runaway Clock | Offensive | +10% attack speed | each attack: +3% attack speed for the fight, up to 12 stacks |
| Golden Arrow | Offensive | +10% AD, +15% crit chance | attacks lower the target's armor by 30% for 3s |
| Oni Cutter | Offensive | +10% AD, +10% attack speed | +20% damage to enemies with more max health than the holder |
| Ghoul's Mask | Offensive | +10% AD | heals 12% of all damage dealt; once, below 40% health: shield of 15% max health for 5s |
| Thousand-Year Staff | Ability | +40 AP | |
| Strange Fruit | Ability | | +20 starting mana; +10 mana after each cast |
| Curse-Breaker Spear | Ability | +10% AD, +10 AP | +5 mana per attack |
| Tattered Grimoire | Ability | +15 AP, +10% max health | ability damage burns for 15% of the damage (true damage) over 4s; burning enemies receive 33% less healing |
| Giant's Serum | Ability | | each attack or hit taken: +2% AD and +2 AP, up to 20 stacks; at 20: +20 armor and MR |
| Steel Arm | Defensive | +35% max health | |
| Straw Doll | Defensive | +30 armor | when hit by a basic attack: 40 magic damage to adjacent enemies, at most once every 2s |
| Cloud Cloak | Defensive | +30 MR | heals 2% of max health every 2s |
| Sand Gourd | Defensive | +10 armor and MR | +10 of each per enemy currently targeting the holder |
| Conqueror's Will | Defensive | +15% attack speed | immune to stuns (single, area, holds) for the first 12s; pulls and knockbacks still work |

Details:
- Healing reduction (WOUND) applies to heals and regeneration, not shields.
- Ability crits use the holder's own crit chance and crit damage.
- Effect text in the game is filled from ItemConfig, so it always shows the current numbers.
- Target: one item is worth roughly +10-15% of a unit's output, three items roughly +40-50%.

## Recommendation tags

Each unit shows up to 3 tags from its classes (`ItemConfig.classTags`): Blade (Attack, Crit),
Assassin (Crit, Attack), Marksman (Speed, Attack), Brawler (Tank, Sustain), Guardian (Tank),
Caster (Ability, Mana), Support (Mana, Ability). While a unit is selected, inventory items sharing
a tag are outlined. Tags never block equipping.

## Engine pieces

- `HealingReceived` stat (multiplies every heal the unit receives), statuses SHRED and WOUND.
- A `hit` hook (every hit, after its event), stun immunity (`stunImmuneUntilTick`, Immune event),
  ability crits (`abilityCrit`), silent mana gains, item-tagged damage over time.
- Events an item causes carry `item` = its id, so the sim can measure each item's damage, healing
  and shielding.

## UI (placeholders)

- Inventory strip, bottom left above the shop: drag an item onto a unit, or tap it then tap a unit.
- Unit info panel: tags, three slots with equipped items and their effect text; tap an item to
  pick it up and tap another unit to move it; its arrow returns it to the inventory.
- Small item pips over the health bar, on the board, bench and in combat.
- Pick screen for item choices.

## Sim

Bots pick the offered item of the category they hold fewest of, and equip after fielding:
offensive items on their highest-attack-damage carry, ability items on their unit with the most
ability damage, defensive items on front-line units with the most health; rerolling bots put
items on their targets first. The report shows pick rate per item, placement by item held, items
per player by round, fight length by equipped items, each item's damage, healing and shielding,
boss damage with items, and Runaway Clock on Marksman units.
It also compares each item like for like: units holding it against the same character at the same
star level without it (damage dealt with summons, healing given, seconds alive), as a percentage.
The 2-cost rerolling bot chases two targets at once, like the 1-cost one.
