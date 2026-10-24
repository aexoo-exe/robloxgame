local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncCheck = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SyncCheck"))

print("robloxgame client is alive!")
print("[client]", SyncCheck.message)

local Arena = require(script.Arena)
local BoardController = require(script.BoardController)
local Celebrate = require(script.Celebrate)
local CombatPlayback = require(script.CombatPlayback)
local DevLineup = require(script.DevLineup)
local FeedbackPanel = require(script.FeedbackPanel)
local HowToPlay = require(script.HowToPlay)
local HubAudio = require(script.HubAudio)
local HubExhibits = require(script.HubExhibits)
local HubHud = require(script.HubHud)
local HubLighting = require(script.HubLighting)
local HubScenery = require(script.HubScenery)
local InventoryStrip = require(script.InventoryStrip)
local ItemBadgeTooltip = require(script.ItemBadgeTooltip)
local ItemPickPanel = require(script.ItemPickPanel)
local MatchHud = require(script.MatchHud)
local MatchIntro = require(script.MatchIntro)
local PlayerList = require(script.PlayerList)
local PostMatchSummary = require(script.PostMatchSummary)
local ProfilePanel = require(script.ProfilePanel)
local RefusalNotice = require(script.RefusalNotice)
local RejoinNotice = require(script.RejoinNotice)
local RewardScreen = require(script.RewardScreen)
local RoundResult = require(script.RoundResult)
local ShopPanel = require(script.ShopPanel)
local TopBar = require(script.TopBar)
local TraitPanel = require(script.TraitPanel)
local UI = require(script.UI)
local UnitAvatars = require(script.UnitAvatars)
local UnitInfoPanel = require(script.UnitInfoPanel)
local UnitOutlines = require(script.UnitOutlines)
local UnitTooltip = require(script.UnitTooltip)
local Vfx = require(script.Vfx)

UnitAvatars.start() -- preload avatar templates in the hub; lock the ready set per match (no look swaps)
Vfx.start() -- preload the picked effect textures (effects stay neon until each has loaded)
Arena.start()
BoardController.start()
CombatPlayback.start()
TopBar.start()
ShopPanel.start()
PlayerList.start()
TraitPanel.start()
UnitInfoPanel.start()
InventoryStrip.start()
ItemPickPanel.start()
RoundResult.start()
MatchHud.start()
MatchIntro.start()
RewardScreen.start()
UnitTooltip.start()
UnitOutlines.start() -- the shared thin outline on the units in view (FigureConfig.outline)
ItemBadgeTooltip.start()
RefusalNotice.start()
HubHud.start()
HubScenery.start()
HubExhibits.start()
HubAudio.start()
HowToPlay.start() -- playtest: first-match intro and the "?" button
FeedbackPanel.start() -- playtest: stars and a line of text after each match
PostMatchSummary.start() -- retention: XP, level-ups, quests and mastery after each match (hub)
ProfilePanel.start() -- retention: level, coins, title, quests, mastery (hub)
RejoinNotice.start() -- after the match screens: asks the server for the match state once they listen
DevLineup.start() -- Studio only

-- In a match (the server's InMatch attribute, HubService): the board camera and the match HUD.
-- Otherwise the player walks around the hub with the normal camera.
local localPlayer = game:GetService("Players").LocalPlayer
local function applyMode()
	local inMatch = localPlayer:GetAttribute("InMatch") == true
	Arena.setActive(inMatch)
	HubLighting.setActive(not inMatch)
	HubScenery.setActive(not inMatch)
	HubAudio.setActive(not inMatch)
	UI.setMatchShown(inMatch)
	HubHud.setShown(not inMatch)
	HubExhibits.setShown(not inMatch)
end
localPlayer:GetAttributeChangedSignal("InMatch"):Connect(applyMode)
applyMode()

-- Keep the board and bench in the part of the screen the HUD leaves free.
local function fitBoard()
	Arena.setViewInsets(UI.boardInsets())
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitBoard)
fitBoard()

-- Upgrades get a sparkle and a star badge over the unit.
BoardController.onUpgrade(function(unit)
	local position = BoardController.unitPosition(unit.id)
	if position then
		Celebrate.starUp(position, unit.starLevel)
	end
end)
