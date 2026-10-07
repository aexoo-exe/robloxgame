-- Placeholder trait symbols, keyed by trait id (the `origin` and `classes` names in UnitConfig).
-- Shown on shop cards, unit info boards and the unit hover tooltip (src/client/TraitIcon.luau
-- draws them). Not final art: each symbol is a colored shape with one or two letters, needing no
-- image assets. Origins are circles and classes are diamonds, so the two kinds read apart at a
-- glance; letters are unique across all traits.
--
-- Each entry:
--   name     display name shown next to the symbol
--   letters  one or two letters drawn on the shape
--   shape    "circle", "diamond" or "square"
--   color    { red, green, blue } (0-255); the letters are drawn dark or light to contrast with it
--   image    optional image id ("rbxassetid://..."). When set, the image is drawn instead of the
--            shape and letters, so real icons replace these by changing only this file.
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.

local function icon(name: string, letters: string, shape: string, color: { number })
	return table.freeze({ name = name, letters = letters, shape = shape, color = table.freeze(color) })
end

return table.freeze({
	-- Origins: circles, in the old origin colors.
	Hunters = icon("Hunters", "HU", "circle", { 214, 120, 52 }),
	Corps = icon("Corps", "CO", "circle", { 112, 152, 196 }),
	Spirit = icon("Spirit", "SP", "circle", { 120, 200, 140 }),
	Cursed = icon("Cursed", "CU", "circle", { 150, 70, 180 }),
	Arcane = icon("Arcane", "AR", "circle", { 90, 110, 230 }),
	Titans = icon("Titans", "TI", "circle", { 150, 120, 95 }),
	Shinobi = icon("Shinobi", "SH", "circle", { 70, 170, 175 }),
	Crew = icon("Crew", "CR", "circle", { 232, 92, 92 }),
	Heroes = icon("Heroes", "HE", "circle", { 240, 200, 70 }),

	-- Classes: diamonds.
	Blade = icon("Blade", "BL", "diamond", { 205, 205, 215 }),
	Assassin = icon("Assassin", "AS", "diamond", { 200, 40, 60 }),
	Marksman = icon("Marksman", "MA", "diamond", { 110, 190, 60 }),
	Brawler = icon("Brawler", "BR", "diamond", { 255, 140, 170 }),
	Support = icon("Support", "SU", "diamond", { 150, 230, 230 }),
	Guardian = icon("Guardian", "GU", "diamond", { 210, 170, 110 }),
	Caster = icon("Caster", "CA", "diamond", { 230, 80, 200 }),
})
