-- The item the player has picked up to place: an inventory item, or an item in one of their units'
-- slots. While one is selected, tapping one of the player's units asks the server to equip it there
-- (or move it there), through BoardController's unit tap handler (InventoryStrip installs it).
-- Presentation only: the server decides.

local ItemSelection = {}

-- { kind = "inventory", index } or { kind = "unit", unitId, slot }, with the item's id.
export type Selection = { kind: string, itemId: string, index: number?, unitId: string?, slot: number? }

local current: Selection? = nil
local callbacks: { (Selection?) -> () } = {}

function ItemSelection.get(): Selection?
	return current
end

function ItemSelection.set(selection: Selection?)
	current = selection
	for _, callback in callbacks do
		callback(current)
	end
end

function ItemSelection.clear()
	ItemSelection.set(nil)
end

-- Calls `callback(selection)` whenever the selection changes.
function ItemSelection.onChanged(callback: (Selection?) -> ())
	table.insert(callbacks, callback)
end

return ItemSelection
