-- Catalog avatars for roster units (client visuals only), keyed by unit id (UnitConfig key). A unit
-- with an entry is drawn as a blocky R6 avatar wearing these Roblox catalog items instead of its
-- hand-built look (UnitLookConfig) or placeholder. The server builds each avatar once at start
-- (src/server/AvatarService.luau) and shares it; the client poses it like any figure (Figure).
-- If an item fails or the avatar takes too long to load, the unit keeps its usual figure and the
-- server warns once, naming the unit and the asset. Display names stay in SkinConfig.
--
-- Fields:
--   accessories  { { slot, id } }: slot is the HumanoidDescription accessory it goes in, by the
--                asset's catalog type: "Hat", "Hair", "Face", "Neck", "Shoulders", "Front",
--                "Back" or "Waist" (a hair sold as a Hat must go in "Hat", or it is dropped)
--   shirt, pants classic clothing asset ids (R6 renders classic clothing, not layered clothing)
--   face         a face asset id (optional; the default face otherwise)
--   skin         body color for every limb; `colors` { head, torso, leftArm, rightArm, leftLeg,
--                rightLeg } overrides single limbs
--   scale        size multiplier (as FigureConfig.characters `scale`; presentation only)
--   prop         false: no class prop in the hands (default: the class prop, as placeholders)
--
-- Item ids are catalog asset ids (catalog.roblox.com). Shortlisted thumbnails live in
-- docs/references/catalog/<unit_id>/ (local only).

return table.freeze({
	-- How long the server waits for one avatar before giving up on it (seconds).
	loadTimeout = 20,

	units = table.freeze({
		threefold_crash = table.freeze({
			accessories = table.freeze({
				table.freeze({ slot = "Hat", id = 16429913206 }), -- green hair under a black bandana
				table.freeze({ slot = "Waist", id = 107872214372202 }), -- green waist wrap with three swords
			}),
			shirt = 12191230699, -- bare scarred chest, green wrap, red sash
			pants = 12191247392, -- dark robe with the hanging red sash
			skin = Color3.fromRGB(234, 184, 146),
			-- Keeps the Blade class sword in his right hand (it follows the hand like any held
			-- weapon); `prop = false` leaves only the three on the belt.
		}),
	}),
})
