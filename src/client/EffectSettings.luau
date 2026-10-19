-- Player toggles for combat presentation, read live from attributes on the local player so a
-- settings menu (or the Studio command bar) can flip them:
--   ReducedEffects       true: ultimates skip their extra layers and screen dimming
--   ReducedCameraMotion  true: no camera pushes from ultimates (shake stays capped by tier), and
--                        no ultimate moments
--   UltimateMoments      false: no ultimate moments (UltimateMoment: the board slowing and the
--                        camera leaning in on the local player's ultimates); on when unset
-- Presentation only.

local Players = game:GetService("Players")

local EffectSettings = {}

local function flag(name: string): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute(name) == true
end

function EffectSettings.reducedEffects(): boolean
	return flag("ReducedEffects")
end

function EffectSettings.reducedCameraMotion(): boolean
	return flag("ReducedCameraMotion")
end

function EffectSettings.ultimateMoments(): boolean
	local player = Players.LocalPlayer
	return player == nil or player:GetAttribute("UltimateMoments") ~= false
end

return EffectSettings
