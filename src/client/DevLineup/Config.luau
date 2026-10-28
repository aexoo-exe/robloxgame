-- DevLineup's fixed settings: lineup layout, the preview stage, key 3's field, the test arenas,
-- the slice unit and camera, and the key help. Studio only (see DevLineup).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
local HubConfig = require(Shared:WaitForChild("HubConfig"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))

local Config = {}

Config.ORIGIN_ORDER = { "Hunters", "Corps", "Spirit", "Cursed", "Arcane", "Titans", "Shinobi", "Crew", "Heroes" }
Config.BASE = HubConfig.center + Vector3.new(0, 260, 0) -- clear sky above the hub
Config.SPACING = 5.5 -- between units in a row
Config.ROW_GAP = 9
Config.HEIGHT = RenderConfig.unitSize.Y
Config.STAGE = Config.BASE + Vector3.new(0, 0, -40) -- the preview stage, in front of the lineup
Config.PREVIEW = AnimationConfig.preview
Config.QUALITIES = { "low", "medium", "high" }
Config.DUMMY_COLOR = Color3.fromRGB(150, 150, 160)
Config.SLICE_UNIT = "echo_legion" -- K: the vertical slice's unit
-- The slice camera's orbit (arenaFraming "slice"): degrees around the focus from square-on side,
-- degrees above level, studs from the focus, studs the focus is raised. `sliceFraming` is what each
-- K / S replay starts from (P saves the live `sliceView` into it, for this session).
export type SliceView = { yaw: number, pitch: number, distance: number, height: number }
Config.SLICE_DEFAULT = { yaw = 131.4, pitch = 20.4, distance = 12, height = 0 } :: SliceView

-- Key 3's preview fight (cast): the unit in its side's front middle cell and dummies across from
-- it, in the dummies' own board coordinates (row 4 = their front): one in front, two beside it,
-- three behind and one further back, so lines, cones and areas all have targets to show on.
Config.FIELD_ORIGIN = Config.STAGE + Vector3.new(0, 0, -60)
Config.FIELD_UNIT = { 4, 4 }
Config.FIELD_DUMMY = "placeholder_creep" -- a PvE creep's look; its stats are replaced
Config.FIELD_DUMMIES = { { 4, 4 }, { 5, 4 }, { 3, 4 }, { 4, 3 }, { 5, 3 }, { 3, 3 }, { 4, 2 } }
-- For a unit whose cast heals a wounded ally: an ally beside it, worn down by the dummy across.
-- Column 5 is on the far side from the arena cameras (they look from the -X side), so it never
-- stands between the camera and the caster; it stays in the front row so the dummy across from it
-- (FIELD_DUMMIES 5,4) is its nearest enemy and wears it down.
Config.FIELD_ALLY = "placeholder_creep_big"
Config.FIELD_ALLY_CELL = { 5, 4 }
Config.FIELD_ALLY_HEALTH = 1000
Config.FIELD_MANA = 12 -- the unit's mana bar in the preview fight (one attack fills most of it)
Config.FIELD_SECONDS = 25 -- how long the preview fight runs
Config.FIELD_AFTER = 3.5 -- seconds of the fight shown after the cast

-- Key 3's test arena (T) and its fixed cameras (C; arenaFraming).
Config.ARENA_MODES = { "off", "gray", "bright" }
Config.ARENA_CAMERAS = { "gameplay", "close", "wide" }
Config.GRAY_CENTER = HubConfig.center + Vector3.new(0, 700, 0) -- the board center in the gray arena
Config.GRAY_SIZE = 400 -- the gray arena's floor, and the box of walls around it
Config.GRAY_HEIGHT = 200
Config.GRAY_FLOOR = Color3.fromRGB(95, 95, 100) -- a true mid-gray
Config.GRAY_BACKDROP = Color3.fromRGB(122, 122, 128) -- a little lighter, so the horizon reads
Config.CLOSE_FILL = 0.6 -- the close camera: the caster and its target fill this much of the height
Config.GRAY_LIGHTING = {
	Ambient = Color3.fromRGB(110, 110, 110),
	OutdoorAmbient = Color3.fromRGB(128, 128, 128),
	Brightness = 2,
	ClockTime = 13,
	GeographicLatitude = 0,
	ColorShift_Top = Color3.new(0, 0, 0),
	ColorShift_Bottom = Color3.new(0, 0, 0),
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0,
	ExposureCompensation = 0,
	ShadowSoftness = 0.6,
	GlobalShadows = true,
	FogStart = 0,
	FogEnd = 100000,
} :: { [string]: any }

-- Step keys: next and previous close-up.
Config.NEXT_KEYS = { [Enum.KeyCode.Period] = true, [Enum.KeyCode.RightBracket] = true, [Enum.KeyCode.Right] = true }
Config.PREVIOUS_KEYS = { [Enum.KeyCode.Comma] = true, [Enum.KeyCode.LeftBracket] = true, [Enum.KeyCode.Left] = true }

Config.OVERVIEW_HELP = "L close   . / ] / Right: next   , / [ / Left: previous"
Config.CLOSE_UP_HELP = table.concat({
	"L close   M lineup   . ] Right: next   , [ Left: previous",
	"1 attack   2 crit   3 real ability   4 get hit   5 stun   6 death   7 victory   8 heal + shield",
	"9 auto loop   F form   X star level   Q quality   V kit textures   S slow ultimate   O freeze + dump",
	"T arena (off / gray / bright)   C arena camera (gameplay / close / wide)   R reel (ReelConfig)",
	"K slice: "
		.. Config.SLICE_UNIT
		.. "'s ultimate, G: with the match camera (S after it: the same at 0.25x)   slice camera: RMB drag / arrows"
		.. " orbit, wheel / + - zoom, Q / E up / down, P save",
}, "\n")

return Config
