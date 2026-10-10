-- Items (docs/items.md): slots, inventory, equipping, moving, returning, selling, merging, the
-- combat lock and carrying items into combat. Item ids here are placeholders; the rules do not
-- depend on what an item does.

local Board = require("../src/shared/Board")
local CombatSim = require("../src/shared/CombatSim")
local ItemConfig = require("../src/shared/ItemConfig")
local PlayerState = require("../src/shared/PlayerState")
local UnitConfig = require("../src/shared/UnitConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local SLOTS = ItemConfig.rules.slotsPerUnit

-- A player with plenty of gold and a known shop, and helpers to buy and find units.
local function newPlayer()
	local state = PlayerState.new(7)
	state.gold = 200
	return state
end

local function buy(state, unitType: string): string
	state.shop[1] = unitType
	local id = tostring(state.nextUnitId)
	assert(PlayerState.buyUnit(state, 1), "test setup: buy " .. unitType)
	return id
end

local function unitsOf(state, unitType: string)
	local result = {}
	for _, unit in Board.getUnits(state.board) do
		if unit.unitType == unitType then
			table.insert(result, unit)
		end
	end
	return result
end

local tests = {}

table.insert(tests, {
	name = "items: equip from the inventory, up to three per unit, never two of the same",
	run = function()
		local state = newPlayer()
		local id = buy(state, "cinder_arc")
		state.inventory = { "a", "a", "b", "c", "d" }
		assert(PlayerState.equipItem(state, 1, id), "equip a")
		local ok, reason = PlayerState.equipItem(state, 1, id)
		assert(not ok and reason == PlayerState.Refusal.DuplicateItem, "a second copy is refused")
		assert(PlayerState.equipItem(state, 2, id), "equip b")
		assert(PlayerState.equipItem(state, 2, id), "equip c")
		ok, reason = PlayerState.equipItem(state, 2, id)
		assert(not ok and reason == PlayerState.Refusal.ItemSlotsFull, "a fourth item is refused")
		expectEqual(#state.board.units[id].items, SLOTS, "three equipped")
		expectEqual(table.concat(state.inventory, ","), "a,d", "inventory after equipping")
		assert(not PlayerState.equipItem(state, 99, id), "a bad inventory index is refused")
		assert(not PlayerState.equipItem(state, 1, "nope"), "an unknown unit is refused")
	end,
})

table.insert(tests, {
	name = "items: move between units and return to the inventory; nothing changes during combat",
	run = function()
		local state = newPlayer()
		local first = buy(state, "cinder_arc")
		local second = buy(state, "flashline")
		state.inventory = { "a", "b" }
		PlayerState.equipItem(state, 1, first)
		PlayerState.equipItem(state, 1, first)
		assert(PlayerState.moveItem(state, first, 1, second), "move a")
		expectEqual(state.board.units[second].items[1], "a", "moved")
		expectEqual(#state.board.units[first].items, 1, "one left")
		assert(PlayerState.unequipItem(state, first, 1), "return b")
		expectEqual(state.inventory[1], "b", "back in the inventory")

		PlayerState.startCombat(state)
		local ok, reason = PlayerState.equipItem(state, 1, first)
		assert(not ok and reason == PlayerState.Refusal.ItemsLocked, "equip locked in combat")
		ok, reason = PlayerState.moveItem(state, second, 1, first)
		assert(not ok and reason == PlayerState.Refusal.ItemsLocked, "move locked in combat")
		ok, reason = PlayerState.unequipItem(state, second, 1)
		assert(not ok and reason == PlayerState.Refusal.ItemsLocked, "return locked in combat")
		PlayerState.endCombat(state)
		ok = PlayerState.equipItem(state, 1, first)
		assert(not ok, "still locked at Results")
		PlayerState.startPreparation(state)
		assert(PlayerState.equipItem(state, 1, first), "unlocked at the next Preparation")
	end,
})

table.insert(tests, {
	name = "items: a full inventory refuses returns; selling a unit returns its items",
	run = function()
		local state = newPlayer()
		local id = buy(state, "cinder_arc")
		state.inventory = { "a" }
		PlayerState.equipItem(state, 1, id)
		for i = 1, ItemConfig.rules.inventoryCap do
			table.insert(state.inventory, "x" .. i)
		end
		local ok, reason = PlayerState.unequipItem(state, id, 1)
		assert(not ok and reason == PlayerState.Refusal.InventoryFull, "full inventory")
		assert(PlayerState.sellUnit(state, id), "sell")
		expectEqual(state.inventory[#state.inventory], "a", "the sold unit's item came back")
	end,
})

table.insert(tests, {
	name = "items: a merge moves the copies' items to the merged unit; extras return to the inventory",
	run = function()
		local state = newPlayer()
		local a = buy(state, "cinder_arc")
		local b = buy(state, "cinder_arc")
		state.inventory = { "x", "y", "z", "x", "w" }
		PlayerState.equipItem(state, 1, a) -- x on a
		PlayerState.equipItem(state, 1, a) -- y on a
		PlayerState.equipItem(state, 1, b) -- z on b
		PlayerState.equipItem(state, 1, b) -- x on b (a second copy of x, on another unit)
		PlayerState.equipItem(state, 1, b) -- w on b
		buy(state, "cinder_arc") -- completes the merge
		local merged = unitsOf(state, "cinder_arc")
		expectEqual(#merged, 1, "merged")
		expectEqual(merged[1].starLevel, 2, "2-star")
		expectEqual(#merged[1].items, SLOTS, "the merged unit holds three")
		local held = {}
		for _, item in merged[1].items do
			assert(not held[item], "no duplicates after a merge")
			held[item] = true
		end
		-- Five items went in; three stay on the unit and two return.
		expectEqual(#state.inventory, 2, "the rest returned")
	end,
})

table.insert(tests, {
	name = "items: units carry their items into combat; summons carry none",
	run = function()
		local result = CombatSim.run({
			boards = {
				{ { id = "a", unitType = "shade_pack", column = 4, row = 4, items = { "a", "b" } } },
				{ { id = "b", unitType = "cinder_arc", column = 4, row = 4 } },
			},
			columns = 7,
			rows = 4,
			unitTypes = UnitConfig,
			ticksPerSecond = 20,
			maxTicks = 20,
			seed = 1,
		})
		expectEqual(table.concat(result.units[1].items, ","), "a,b", "summary items")
		expectEqual(#result.units[2].items, 0, "no items")
	end,
})

-- Item effects ---------------------------------------------------------------------------------------

local Abilities = require("../src/shared/Abilities")
local Battle = require("../src/shared/Battle")
local ItemCombat = require("../src/shared/ItemCombat")
local ItemsModule = require("../src/shared/Items")

local function near(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) < 1e-6, string.format("%s: expected %s, got %s", label, expected, actual))
end

-- A sturdy unit type that does nothing unless overridden.
local function unitType(overrides)
	local stats = {
		health = 1000,
		attackDamage = 100,
		attacksPerSecond = 1,
		range = 1,
		moveSpeed = 0.001,
		armor = 0,
		magicResist = 0,
	}
	for key, value in overrides or {} do
		stats[key] = value
	end
	return stats
end

-- A battle of a holder (side 1, with `items`) next to one or more dummies (side 2), items applied.
-- Health is reset to the listed values (no health dial). Returns the battle and its units.
local function itemBattle(items, holderOverrides, enemies: number?, critChance: number?)
	local types = { Holder = unitType(holderOverrides), Dummy = unitType({ attackDamage = 10, health = 100000 }) }
	local boards = { { { id = "h", unitType = "Holder", column = 4, row = 4, items = items } }, {} }
	-- Side 2 at (4,4) rotates to (4,5), next to the holder; more dummies at the back.
	local cells = { { 4, 4 }, { 1, 1 }, { 7, 1 } }
	for i = 1, enemies or 1 do
		table.insert(boards[2], { id = "d" .. i, unitType = "Dummy", column = cells[i][1], row = cells[i][2] })
	end
	local battle = Battle.new({
		boards = boards,
		columns = 7,
		rows = 4,
		unitTypes = types,
		ticksPerSecond = 20,
		maxTicks = 2000,
		seed = 1,
		critChance = critChance or 0,
	})
	for _, unit in battle.units do
		unit.maxHealth = types[unit.unitType].health
		unit.baseMaxHealth = unit.maxHealth
		unit.health = unit.maxHealth
	end
	ItemCombat.setup(battle)
	return battle, battle.units
end

local function eventsOfKind(battle, kind: string)
	local found = {}
	for _, event in battle.events do
		if event.kind == kind then
			table.insert(found, event)
		end
	end
	return found
end

table.insert(tests, {
	name = "item data: every item is valid, has a skin, and its effect text fills every number",
	run = function()
		local ItemSkinConfig = require("../src/shared/ItemSkinConfig")
		local ok, reason = ItemsModule.validate(Battle.StatFields, ItemCombat.effects)
		assert(ok, tostring(reason))
		for _, id in ItemsModule.ids() do
			local skin = ItemSkinConfig.items[id]
			assert(skin and skin.name ~= "" and #skin.letters >= 1, id .. " needs a skin")
			local text = ItemsModule.describe(id, ItemSkinConfig)
			assert(text ~= "" and not string.find(text, "?", 1, true), id .. " text: " .. text)
			assert(not string.find(text, "{", 1, true), id .. " has an unfilled number: " .. text)
		end
		for id in ItemSkinConfig.items do
			assert(ItemConfig.items[id], "skin for an unknown item " .. id)
		end
	end,
})

table.insert(tests, {
	name = "item stats apply for the whole fight, and stack with each other",
	run = function()
		local battle, units = itemBattle({ "steel_arm", "thousand_year_staff", "oni_cutter" })
		local holder = units[1]
		expectEqual(holder.maxHealth, 1350, "+35% max health")
		expectEqual(holder.health, 1350, "current health raised too")
		near(Battle.stat(battle, holder, "AP"), 140, "+40 AP")
		near(Battle.stat(battle, holder, "AD"), 110, "+10% AD")
		near(Battle.stat(battle, holder, "AttackSpeed"), 1.1, "+10% attack speed")
	end,
})

table.insert(tests, {
	name = "sunforged_blade: abilities can crit, using the holder's crit chance and crit damage",
	run = function()
		local battle, units = itemBattle({ "sunforged_blade" }, nil, 1, 1)
		local holder = units[1]
		holder.ability = {
			name = "Hit",
			effects = { { type = "DAMAGE", target = "NEAREST_ENEMY", damageType = "TRUE", amount = 100 } },
		}
		Abilities.cast(battle, holder)
		local hit = eventsOfKind(battle, "Damage")[1]
		assert(hit.crit, "the ability hit crit")
		expectEqual(hit.damage, math.round(100 * Battle.stat(battle, holder, "CritDamage")), "crit damage")
	end,
})

table.insert(tests, {
	name = "runaway_clock and giants_serum stack per attack; golden_arrow shreds; spear gives mana",
	run = function()
		local battle, units = itemBattle({ "runaway_clock", "golden_arrow", "cursebreaker_spear" }, { maxMana = 1000 })
		local holder, dummy = units[1], units[2]
		local before = Battle.stat(battle, holder, "AttackSpeed")
		for _ = 1, 3 do
			Battle.runHooks(battle, "attack", holder, dummy)
		end
		near(Battle.stat(battle, holder, "AttackSpeed"), before + 3 * 0.03, "+3% per attack, 3 attacks (on base 1)")
		assert(Battle.hasStatus(battle, dummy, Battle.Status.Shred), "armor shredded")
		expectEqual(holder.mana, 15, "+5 mana per attack")

		local serumBattle, serumUnits = itemBattle({ "giants_serum" })
		local serum = serumUnits[1]
		for _ = 1, 25 do
			Battle.runHooks(serumBattle, "attack", serum, serumUnits[2])
		end
		near(Battle.stat(serumBattle, serum, "AD"), 100 * 1.4, "20 stacks of +2% AD")
		near(Battle.stat(serumBattle, serum, "AP"), 140, "20 stacks of +2 AP")
		near(Battle.stat(serumBattle, serum, "Armor"), 20, "full stacks: +20 armor")
	end,
})

table.insert(tests, {
	name = "oni_cutter, ghouls_mask: bonus vs bigger enemies, lifesteal and the low-health shield",
	run = function()
		local battle, units = itemBattle({ "oni_cutter", "ghouls_mask" })
		local holder, dummy = units[1], units[2]
		holder.health = 500
		Battle.damage(battle, holder, dummy, 100, "TRUE", "Damage")
		local hit = eventsOfKind(battle, "Damage")[1]
		expectEqual(hit.damage, 120, "+20% against a bigger enemy")
		expectEqual(holder.health, 514, "healed 12% of 120, rounded")
		Battle.damage(battle, dummy, holder, 200, "TRUE", "Damage")
		expectEqual(holder.shield, 150, "below 40%: a shield of 15% max health")
		local shields = eventsOfKind(battle, "Shield")
		expectEqual(shields[#shields].item, "ghouls_mask", "the shield event names the item")
	end,
})

table.insert(tests, {
	name = "tattered_grimoire burns ability hits and wounds; healing reduction lowers heals",
	run = function()
		local battle, units = itemBattle({ "tattered_grimoire" })
		local holder, dummy = units[1], units[2]
		Battle.damage(battle, holder, dummy, 400, "TRUE", "Damage")
		assert(Battle.hasStatus(battle, dummy, Battle.Status.Burn), "burning")
		assert(Battle.hasStatus(battle, dummy, Battle.Status.Wound), "wounded")
		dummy.health = 50000
		Battle.heal(battle, dummy, dummy, 100)
		expectEqual(dummy.health, 50067, "33% less healing")
		Battle.damage(battle, holder, dummy, 400, "TRUE", "Attack")
		battle.tick += 20
		Battle.tickDots(battle)
		local tick = eventsOfKind(battle, "Damage")
		expectEqual(tick[#tick].item, "tattered_grimoire", "burn ticks name the item")
		expectEqual(tick[#tick].damage, 15, "15% of 400 over 4s")
	end,
})

table.insert(tests, {
	name = "straw_doll, cloud_cloak, sand_gourd, conquerors_will, strange_fruit",
	run = function()
		local battle, units = itemBattle({ "straw_doll", "cloud_cloak", "sand_gourd" }, nil, 1)
		local holder, dummy = units[1], units[2]
		local dummyHealth = dummy.health
		Battle.damage(battle, dummy, holder, 10, "PHYSICAL", "Attack")
		expectEqual(dummyHealth - dummy.health, 40, "40 magic back to the adjacent attacker")
		Battle.damage(battle, dummy, holder, 10, "PHYSICAL", "Attack")
		expectEqual(dummyHealth - dummy.health, 40, "not again within 2s")
		dummy.target = holder
		holder.health = 500
		for _ = 1, 40 do
			battle.tick += 1
			Battle.runHooks(battle, "tick")
		end
		expectEqual(holder.health, 520, "2% of max health at 2s")
		near(Battle.stat(battle, holder, "Armor"), 30 + 10 + 10, "+10 armor per enemy targeting")

		local willBattle, willUnits = itemBattle({ "conquerors_will", "strange_fruit" }, { maxMana = 100 })
		local will = willUnits[1]
		Battle.stun(willBattle, willUnits[2], will, 1)
		expectEqual(will.stunnedUntilTick, 0, "immune at the start")
		expectEqual(#eventsOfKind(willBattle, "Immune"), 1, "Immune event")
		expectEqual(will.mana, 20, "+20 starting mana")
		willBattle.tick = 20 * 13
		Battle.stun(willBattle, willUnits[2], will, 1)
		assert(will.stunnedUntilTick > willBattle.tick, "stunned after 12s")
	end,
})

-- Item choices -------------------------------------------------------------------------------------

local Items = require("../src/shared/Items")
local SeededRandom = require("../src/shared/SeededRandom")

table.insert(tests, {
	name = "item choices: rounds 3, 8, 12, 16 offer 3 items and round 20 offers 4",
	run = function()
		for round = 1, 25 do
			local expected = if round == 20
				then 4
				elseif round == 3 or round == 8 or round == 12 or round == 16 then 3
				else 0
			expectEqual(Items.offerSize(round), expected, "round " .. round)
		end
	end,
})

table.insert(tests, {
	name = "item choices: one offensive, one ability, one defensive, no duplicates, seeded",
	run = function()
		local Category = ItemConfig.Category
		for seed = 1, 50 do
			for _, count in { 3, 4 } do
				local offer = Items.rollOffer(SeededRandom.new(seed), count)
				expectEqual(#offer, count, "offer size")
				local seen = {}
				for i, id in offer do
					assert(Items.isItem(id), "unknown item " .. tostring(id))
					assert(not seen[id], "duplicate in an offer")
					seen[id] = true
					local wanted = ({ Category.Offensive, Category.Ability, Category.Defensive })[i]
					if wanted then
						expectEqual(ItemConfig.items[id].category, wanted, "slot " .. i .. " category")
					end
				end
				local again = Items.rollOffer(SeededRandom.new(seed), count)
				expectEqual(table.concat(again, ","), table.concat(offer, ","), "same seed, same offer")
			end
		end
		expectEqual(#Items.ids(), 15, "fifteen items")
	end,
})

table.insert(tests, {
	name = "item choices: pick one; unpicked, the first is taken when Preparation ends",
	run = function()
		local state = newPlayer()
		PlayerState.offerItems(state, 3)
		local offer = table.clone(state.itemOffer)
		assert(PlayerState.pickItem(state, 2), "pick the second")
		expectEqual(state.inventory[1], offer[2], "picked into the inventory")
		expectEqual(state.itemOffer, nil, "the choice closes")
		local ok, reason = PlayerState.pickItem(state, 1)
		assert(not ok and reason == PlayerState.Refusal.NoItemOffer, "nothing left to pick")

		PlayerState.offerItems(state, 3)
		local second = table.clone(state.itemOffer)
		expectEqual(PlayerState.getView(state).itemOffer[1], second[1], "the view shows the choice")
		PlayerState.startCombat(state)
		expectEqual(state.inventory[2], second[1], "the first item taken at the end of Preparation")
		expectEqual(state.itemOffer, nil, "closed")
	end,
})

table.insert(tests, {
	name = "item choices: a full inventory refuses the pick",
	run = function()
		local state = newPlayer()
		for i = 1, ItemConfig.rules.inventoryCap do
			state.inventory[i] = "x" .. i
		end
		PlayerState.offerItems(state, 3)
		local ok, reason = PlayerState.pickItem(state, 1)
		assert(not ok and reason == PlayerState.Refusal.InventoryFull, "full")
	end,
})

return tests
