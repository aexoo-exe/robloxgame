-- DevLineup's shared, changing state: the lineup, the close-up's preview stage and its clock, the
-- arena and camera modes, the HUD, the reel and the slice camera. One table, read and written by
-- every DevLineup module. Studio only (see DevLineup).

local Config = require(script.Parent.Config)

local Figure = require(script.Parent.Parent.Figure)
local UnitView = require(script.Parent.Parent.UnitView)

export type Entry = {
	unitType: string,
	figure: Figure.Figure,
	root: CFrame,
	height: number,
	mounted: boolean,
}

-- The close-up's preview stage: the unit and a target dummy as fight views.
export type Stage = {
	unitType: string,
	folder: Folder,
	actor: UnitView.UnitView,
	dummy: UnitView.UnitView,
	starLevel: number,
	formIndex: number, -- the form shown (UnitConfig forms), 1 for the first
	pending: { { at: number, run: () -> () } },
	dying: { UnitView.UnitView },
	auto: boolean,
	autoCount: number,
	nextAuto: number,
	camera: CFrame,
	stageCamera: CFrame, -- the stage's own framing (the camera returns to it after a field preview)
	fieldPreview: Folder?, -- key 3's preview fight, while it is shown
	fieldFocus: Vector3?, -- what its camera looks at
	fieldOffset: Vector3?, -- from the real arena cells to its cells
	previewSeconds: number?, -- how long its playback runs (stage seconds)
	castPresses: number,
}

local State = {
	folder = nil :: Folder?,
	entries = {} :: { Entry },
	focus = nil :: number?,
	stage = nil :: Stage?,
	-- The stage runs on its own clock (stage seconds), so the preview can play in slow motion or
	-- freeze (DevLineup QA handle).
	stageTime = 0,
	timeScale = 1,
	frozenScale = nil :: number?, -- the time scale before O froze the effects
	cameraMode = "front", -- stage camera framing (Stage.stageFraming)
	arenaMode = "off", -- Config.ARENA_MODES
	arenaCamera = "gameplay", -- Config.ARENA_CAMERAS
	arenaRestore = nil :: (() -> ())?, -- undoes what the shown arena changed outside the stage
	titleText = "", -- the HUD title before the arena / camera suffix
	-- The reel (R): running, a token that ends its loop when bumped, the modes it replaced, its card.
	reelRunning = false,
	reelToken = 0,
	reelSaved = nil :: { arena: string, camera: string }?,
	reelGui = nil :: ScreenGui?,
	reelCard = nil :: TextLabel?,
	heartbeat = nil :: RBXScriptConnection?,
	savedCamera = nil :: { cameraType: Enum.CameraType, cframe: CFrame }?,
	hud = nil :: ScreenGui?,
	hudTitle = nil :: TextLabel?,
	hudHelp = nil :: TextLabel?,
	freezeButton = nil :: TextButton?,
	emotesWereEnabled = nil :: boolean?,
	-- The slice camera (Slice): the framing each K / S replay starts from, the live orbit, the arena
	-- and camera it replaced, and a token that cancels a pending restore.
	sliceFraming = table.clone(Config.SLICE_DEFAULT) :: Config.SliceView,
	sliceView = table.clone(Config.SLICE_DEFAULT) :: Config.SliceView,
	sliceSaved = nil :: { arena: string, camera: string }?,
	sliceToken = 0,
	-- Next / previous close-up (Lineup.step), set by DevLineup.start so the HUD buttons can call it.
	step = nil :: ((number) -> ())?,
}

-- The stage clock (stage seconds): every effect of the stage and its field preview runs on it.
function State.stageClock(): number
	return State.stageTime
end

return State
