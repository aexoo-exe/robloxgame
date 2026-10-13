-- Vetted Creator Store models drawn in place of a unit's hand-built look (client visuals only), by
-- unit id (UnitConfig key). The models are kept as generated pure data in src/shared/UnitModels/
-- (scripts/models-build.luau, from dumps made in Studio by scripts/studio/export-models.luau: every
-- script is deleted unrun, nothing from the model runs). Figure builds the figure from that data,
-- with each part on the figure anchor of its limb, so every pose, the hitbox, star size, cost ring,
-- flashes (a Highlight), form tints and fades work as for any figure. A unit whose model data is
-- missing keeps its hand-built look (UnitLookConfig).
--
-- Fields:
--   model    the UnitModels data key drawn for the unit
--   outfit   LookKit pieces added on top (UnitAvatarConfig `outfit` format), e.g. steam
--   forms    { [form name] = { model, outfit?, scale? } }: a form drawn as a model instead of its
--            FormLookConfig look (`scale` multiplies the form's RenderConfig size)
-- A mounted rider's horse model is chosen in HorseLookConfig (`model`).

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

return deepFreeze({
	iron_rush = { model = "iron_rush" }, -- 432489765 (180 parts: the heaviest figure)
	skyboulder = { model = "skyboulder" }, -- 9877369056
	boiling_crown = { -- 12125701097, with its steam kept
		model = "boiling_crown",
		outfit = { steam = { rate = 4, color = Color3.fromRGB(245, 240, 235), size = 0.16 } },
	},
	titanheart = { -- the Titan form: 4231104573
		forms = { Titan = { model = "titanheart_titan" } },
	},
})
