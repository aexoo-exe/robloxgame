-- The HUD's look in one place: colors, fonts, corners and outlines, sizes, icon glyphs and the feel
-- of its animations (client only; see src/client/UI.luau). Dark, sleek panels with gold accents and
-- angled highlights; big chunky buttons with thick outlines in bright colors for the main actions.
--
-- Layout sizes are in reference pixels: every HUD screen is scaled by a UIScale so the reference
-- layout fits the safe area of the screen (see `scale`), on phones and desktops alike. Icons are
-- text glyphs (no image assets); swap a glyph here to change it everywhere.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function freezeAll(value)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			freezeAll(child)
		end
		table.freeze(value)
	end
	return value
end

return freezeAll({
	-- The reference layout is designed for this size; screens smaller or larger scale it by the
	-- smaller of width / reference.X and height / reference.Y, kept within min and max.
	scale = { reference = Vector2.new(1100, 560), min = 0.5, max = 1.7 },

	fonts = {
		display = Enum.Font.LuckiestGuy, -- titles, big numbers, button labels
		number = Enum.Font.FredokaOne, -- stat numbers
		body = Enum.Font.GothamBold, -- names and short text
		light = Enum.Font.Gotham,
	},

	colors = {
		panel = rgb(20, 22, 34),
		panelLight = rgb(36, 40, 60),
		panelTransparency = 0.08,
		gold = rgb(255, 198, 66),
		goldDark = rgb(170, 112, 24),
		outline = rgb(8, 8, 14),
		text = rgb(255, 255, 255),
		textDim = rgb(165, 172, 195),
		highlight = rgb(255, 255, 255), -- the gloss on panels and buttons

		-- Main actions, bright and distinct.
		reroll = rgb(40, 170, 255),
		levelUp = rgb(170, 95, 255),
		buy = rgb(70, 205, 95),
		sell = rgb(240, 80, 70),
		disabled = rgb(70, 74, 90),

		health = rgb(80, 220, 100),
		healthLow = rgb(240, 80, 70),
		xp = rgb(120, 200, 255),
		win = rgb(80, 225, 110),
		loss = rgb(240, 80, 70),
		draw = rgb(170, 175, 190),
		you = rgb(255, 198, 66),
		opponent = rgb(240, 80, 70),
	},

	-- Panels: rounded corners, a gold outline and a slanted gold accent across one corner.
	corner = 10,
	buttonCorner = 12,
	panelStroke = 2,
	buttonStroke = 3,
	accentAngle = -14, -- degrees of the slanted accent stripes

	-- Round kinds (Pve.Kind) in the top bar's round tracker.
	roundKinds = {
		Creep = { glyph = "🐾", color = rgb(90, 190, 90) },
		PvP = { glyph = "⚔", color = rgb(70, 150, 255) },
		Boss = { glyph = "💀", color = rgb(235, 70, 70) },
	},
	-- Phases (Shared.Phase) in the top bar: a short tag and its color.
	phases = {
		Waiting = { text = "WAITING", color = rgb(120, 125, 145) },
		Lobby = { text = "GET READY", color = rgb(255, 198, 66) },
		Preparation = { text = "PLAN", color = rgb(60, 160, 255) },
		Combat = { text = "FIGHT", color = rgb(240, 80, 70) },
		Results = { text = "RESULT", color = rgb(255, 198, 66) },
		MatchOver = { text = "GAME OVER", color = rgb(170, 95, 255) },
	},

	-- Icon glyphs.
	icons = {
		health = "❤",
		attack = "⚔",
		abilityPower = "✦",
		armor = "🛡",
		magicResist = "✧",
		attackSpeed = "⚡",
		range = "🎯",
		mana = "💧",
		move = "👟",
		star = "★",
		winStreak = "🔥",
		lossStreak = "❄",
		win = "✔",
		loss = "✖",
		draw = "=",
		opponent = "⚔",
		close = "✕",
		timer = "⏱",
		fastForward = "▶▶",
	},

	-- Sizes in reference pixels.
	sizes = {
		margin = 10,
		topBarHeight = 52,
		shopCard = Vector2.new(124, 96),
		shopButton = Vector2.new(112, 96),
		shopStrip = 34, -- the stats row above the shop cards
		sidePanelWidth = 200,
		playerRow = 40,
		traitRow = 30,
		infoPanelWidth = 300,
		textSmall = 13,
		text = 16,
		textLarge = 22,
		textHuge = 40,
	},

	-- Space the HUD covers, in reference pixels, that the camera keeps the board and bench out of
	-- (Arena fits the camera into the rest of the screen). Side panels may overlap the board's edge.
	boardInsets = { top = 64, bottom = 150, left = 110, right = 120 },

	-- Feel: button bounce, number count-ups, pops and celebrations (seconds).
	motion = {
		pressScale = 0.9,
		bounceScale = 1.08,
		bounceTime = 0.18,
		countUpTime = 0.45,
		popScale = 1.25,
		popTime = 0.25,
		toastTime = 1.6,
		resultTime = 3.5,
	},
})
